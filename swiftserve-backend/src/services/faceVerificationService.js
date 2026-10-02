const crypto = require('crypto');
const fs = require('fs/promises');
const path = require('path');
const { FieldValue } = require('firebase-admin/firestore');
const {
  isLocalStorage,
  removeStoredFiles,
  resolveUploadsDir,
  saveLocalBuffer,
} = require('./verificationStorageService');

const FACE_MATCH_THRESHOLD = 0.6;
const MODELS_PATH = path.resolve(__dirname, '../../models');
const MODEL_FILES = Object.freeze([
  'ssd_mobilenetv1_model-weights_manifest.json',
  'ssd_mobilenetv1_model.bin',
  'face_landmark_68_model-weights_manifest.json',
  'face_landmark_68_model.bin',
  'face_recognition_model-weights_manifest.json',
  'face_recognition_model.bin',
]);
const FINAL_OR_REPLACEABLE_STATUSES = new Set([
  'rejected',
  'resubmission_required',
]);

// TODO(face-verification): temporary bypass. Set DISABLE_FACE_VERIFICATION=false
// (or unset) to re-enable automatic face matching.
const isFaceCheckDisabled = () =>
  process.env.DISABLE_FACE_VERIFICATION === 'true';

let faceRuntime;
let modelsPromise;

class FaceDetectionError extends Error {
  constructor(code, image) {
    const label = image === 'document' ? 'document image' : 'selfie';
    const message = code === 'MULTIPLE_FACES_DETECTED'
      ? `More than one face was detected in the ${label}.`
      : `No usable face was detected in the ${label}.`;
    super(message);
    this.name = 'FaceDetectionError';
    this.code = code;
    this.image = image;
  }
}

class VerificationConflictError extends Error {
  constructor(message) {
    super(message);
    this.name = 'VerificationConflictError';
  }
}

class WorkerAccessError extends Error {
  constructor(message) {
    super(message);
    this.name = 'WorkerAccessError';
  }
}

const createFaceRuntime = () => {
  // The WASM backend supports Node 22 without native TensorFlow bindings.
  const tf = require('@tensorflow/tfjs');
  const wasm = require('@tensorflow/tfjs-backend-wasm');
  const faceapi = require('@vladmandic/face-api/dist/face-api.node-wasm.js');
  const canvas = require('canvas');
  const { Canvas, Image, ImageData, loadImage } = canvas;

  const wasmDirectory = `${path.dirname(require.resolve('@tensorflow/tfjs-backend-wasm'))}${path.sep}`;
  wasm.setWasmPaths(wasmDirectory);
  faceapi.env.monkeyPatch({ Canvas, Image, ImageData });
  return { tf, faceapi, loadImage };
};

const getFaceRuntime = () => {
  if (!faceRuntime) faceRuntime = createFaceRuntime();
  return faceRuntime;
};

const validateModelFiles = async (modelsPath = MODELS_PATH) => {
  const missing = [];
  for (const filename of MODEL_FILES) {
    try {
      const stats = await fs.stat(path.join(modelsPath, filename));
      if (!stats.isFile() || stats.size === 0) missing.push(filename);
    } catch {
      missing.push(filename);
    }
  }
  if (missing.length > 0) {
    throw new Error(
      `Face model files are missing or empty: ${missing.join(', ')}. Run "npm run models:download".`,
    );
  }
};

const loadModels = async ({ modelsPath = MODELS_PATH, runtime } = {}) => {
  if (modelsPromise) return modelsPromise;

  modelsPromise = (async () => {
    await validateModelFiles(modelsPath);
    const activeRuntime = runtime || getFaceRuntime();
    await activeRuntime.tf.setBackend('wasm');
    await activeRuntime.tf.ready();
    await Promise.all([
      activeRuntime.faceapi.nets.ssdMobilenetv1.loadFromDisk(modelsPath),
      activeRuntime.faceapi.nets.faceLandmark68Net.loadFromDisk(modelsPath),
      activeRuntime.faceapi.nets.faceRecognitionNet.loadFromDisk(modelsPath),
    ]);
    return activeRuntime;
  })();

  try {
    return await modelsPromise;
  } catch (error) {
    modelsPromise = undefined;
    throw error;
  }
};

const getFaceDescriptor = async (imageBuffer, image, runtime) => {
  const activeRuntime = runtime || await loadModels();
  const decodedImage = await activeRuntime.loadImage(imageBuffer);
  const detections = await activeRuntime.faceapi
    .detectAllFaces(decodedImage)
    .withFaceLandmarks()
    .withFaceDescriptors();

  if (detections.length === 0) {
    throw new FaceDetectionError('FACE_NOT_DETECTED', image);
  }
  if (detections.length > 1) {
    throw new FaceDetectionError('MULTIPLE_FACES_DETECTED', image);
  }
  return detections[0].descriptor;
};

const compareDescriptors = (a, b, threshold = FACE_MATCH_THRESHOLD) => {
  if (!a || !b || a.length === 0 || a.length !== b.length) {
    throw new TypeError('Face descriptors must be non-empty and have equal lengths.');
  }

  let squaredDifference = 0;
  for (let index = 0; index < a.length; index += 1) {
    if (!Number.isFinite(a[index]) || !Number.isFinite(b[index])) {
      throw new TypeError('Face descriptors must contain only finite numbers.');
    }
    const difference = a[index] - b[index];
    squaredDifference += difference * difference;
  }

  const rawDistance = Math.sqrt(squaredDifference);
  const confidence = Math.round(
    Math.min(100, Math.max(0, (1 - rawDistance) * 100)) * 100,
  ) / 100;

  return {
    match: rawDistance <= threshold,
    distance: Number(rawDistance.toFixed(6)),
    confidence,
  };
};

const verifyFaces = async (
  documentBuffer,
  selfieBuffer,
  { descriptor = getFaceDescriptor } = {},
) => {
  // Process sequentially to avoid holding two inference pipelines in memory.
  const documentDescriptor = await descriptor(documentBuffer, 'document');
  const selfieDescriptor = await descriptor(selfieBuffer, 'selfie');
  return compareDescriptors(documentDescriptor, selfieDescriptor);
};

const maskIdNumber = (value) => {
  const normalized = String(value || '').trim();
  const suffix = normalized.slice(-4);
  return `${'*'.repeat(Math.max(8, normalized.length - suffix.length))}${suffix}`;
};

const extensionFor = (mimeType) => mimeType === 'image/png' ? 'png' : 'jpg';

const markForDeletion = async (bucket, paths, customTime = new Date()) => {
  const value = customTime.toISOString();
  await Promise.all(
    paths.filter(Boolean).map((filePath) => bucket.file(filePath).setMetadata({ customTime: value })),
  );
};

const compareAndCreateSubmission = async ({
  uid,
  idType,
  idNumber,
  document,
  selfie,
  db,
  storage,
  verify = verifyFaces,
  now = () => new Date(),
  uploadsDir = resolveUploadsDir(),
}) => {
  const userRef = db.collection('users').doc(uid);
  const verificationRef = db.collection('worker_verifications').doc(uid);
  const [userSnapshot, verificationSnapshot] = await Promise.all([
    userRef.get(),
    verificationRef.get(),
  ]);
  const user = userSnapshot.data();

  if (!userSnapshot.exists || user?.role !== 'worker') {
    throw new WorkerAccessError('Worker access is required.');
  }
  if (user.verificationStatus === 'verified') {
    throw new VerificationConflictError('This worker is already verified.');
  }
  const prior = verificationSnapshot.exists ? verificationSnapshot.data() : null;
  if (prior && !FINAL_OR_REPLACEABLE_STATUSES.has(prior.status)) {
    throw new VerificationConflictError('A verification submission is already being reviewed.');
  }

  // TODO(face-verification): temporary ID-only bypass. Workers submit just the
  // government ID and an admin approves manually. Re-enable by requiring the
  // selfie again and restoring the verify() call below.
  if (isFaceCheckDisabled()) {
    return createIdOnlySubmission({
      uid,
      idType,
      idNumber,
      document,
      db,
      storage,
      verificationRef,
      prior,
      now,
      uploadsDir,
    });
  }

  const comparison = await verify(document.buffer, selfie.buffer);
  if (!comparison.match) return comparison;

  const submittedAt = now();
  const submissionId = crypto.randomUUID();
  const basePath = `worker_verifications/${uid}/${submissionId}`;
  const governmentIdPath = `${basePath}/government_id.${extensionFor(document.mimetype)}`;
  const facePhotoPath = `${basePath}/face_photo.${extensionFor(selfie.mimetype)}`;
  const bucket = storage.bucket();
  const uploadedPaths = [];

  try {
    await bucket.file(governmentIdPath).save(document.buffer, {
      resumable: false,
      metadata: { contentType: document.mimetype },
    });
    uploadedPaths.push(governmentIdPath);
    await bucket.file(facePhotoPath).save(selfie.buffer, {
      resumable: false,
      metadata: { contentType: selfie.mimetype },
    });
    uploadedPaths.push(facePhotoPath);

    await verificationRef.set({
      workerId: uid,
      submissionId,
      idType: String(idType).trim(),
      maskedIdNumber: maskIdNumber(idNumber),
      governmentIdPath,
      facePhotoPath,
      idSubmitted: true,
      faceVerified: true,
      faceDistance: comparison.distance,
      faceMatchConfidence: comparison.confidence,
      faceMatchThreshold: FACE_MATCH_THRESHOLD,
      faceVerificationProvider: 'local_face_api',
      faceVerifiedAt: submittedAt,
      status: 'pending',
      adminNotes: '',
      submittedAt,
      updatedAt: submittedAt,
      reviewedAt: FieldValue.delete(),
      reviewedBy: FieldValue.delete(),
      purgeAfter: FieldValue.delete(),
    }, { merge: true });
  } catch (error) {
    await Promise.allSettled(
      uploadedPaths.map((filePath) => bucket.file(filePath).delete({ ignoreNotFound: true })),
    );
    throw error;
  }

  if (prior) {
    await markForDeletion(bucket, [prior.governmentIdPath, prior.facePhotoPath], submittedAt)
      .catch((error) => console.error('Failed to schedule replaced verification images for deletion:', error));
  }

  return { ...comparison, status: 'pending' };
};

const createIdOnlySubmission = async ({
  uid,
  idType,
  idNumber,
  document,
  db,
  storage,
  verificationRef,
  prior,
  now,
  uploadsDir = resolveUploadsDir(),
}) => {
  const submittedAt = now();
  const submissionId = crypto.randomUUID();
  const basePath = `worker_verifications/${uid}/${submissionId}`;
  const fileName = `government_id.${extensionFor(document.mimetype)}`;
  const bucket = storage?.bucket ? storage.bucket() : null;
  let governmentIdPath = `${basePath}/${fileName}`;
  let backend = 'gcs';

  try {
    // TODO(billing): local disk while there is no Storage bucket. The GCS
    // branch below is the production path; restore by setting
    // VERIFICATION_STORAGE=gcs with a real FIREBASE_STORAGE_BUCKET.
    if (isLocalStorage() || !bucket) {
      governmentIdPath = await saveLocalBuffer(`${basePath}/${fileName}`, document.buffer, uploadsDir);
      backend = 'local';
    } else {
      await bucket.file(governmentIdPath).save(document.buffer, {
        resumable: false,
        metadata: { contentType: document.mimetype },
      });
    }

    await verificationRef.set({
      workerId: uid,
      submissionId,
      idType: String(idType).trim(),
      maskedIdNumber: maskIdNumber(idNumber),
      governmentIdPath,
      governmentIdMimeType: document.mimetype,
      storageBackend: backend,
      facePhotoPath: null,
      idSubmitted: true,
      faceVerified: false,
      faceDistance: null,
      faceMatchConfidence: null,
      faceMatchThreshold: null,
      faceVerificationProvider: 'bypassed',
      faceVerifiedAt: FieldValue.delete(),
      status: 'pending',
      adminNotes: '',
      submittedAt,
      updatedAt: submittedAt,
      reviewedAt: FieldValue.delete(),
      reviewedBy: FieldValue.delete(),
      purgeAfter: FieldValue.delete(),
    }, { merge: true });
  } catch (error) {
    if (backend === 'local') {
      await removeStoredFiles({ paths: [governmentIdPath], backend, uploadsDir });
    } else if (bucket) {
      await bucket.file(governmentIdPath).delete({ ignoreNotFound: true }).catch(() => {});
    }
    throw error;
  }

  if (prior) {
    await removeStoredFiles({
      paths: [prior.governmentIdPath, prior.facePhotoPath],
      backend: prior.storageBackend || 'gcs',
      storage,
      uploadsDir,
    }).catch((error) => console.error('Failed to remove replaced verification images:', error));
  }

  return { match: true, confidence: null, distance: null, status: 'pending', bypassed: true };
};

const resetModelStateForTests = () => {
  faceRuntime = undefined;
  modelsPromise = undefined;
};

module.exports = {
  FACE_MATCH_THRESHOLD,
  MODEL_FILES,
  MODELS_PATH,
  FaceDetectionError,
  VerificationConflictError,
  WorkerAccessError,
  compareAndCreateSubmission,
  compareDescriptors,
  getFaceDescriptor,
  isFaceCheckDisabled,
  loadModels,
  markForDeletion,
  maskIdNumber,
  resetModelStateForTests,
  validateModelFiles,
  verifyFaces,
};
