const crypto = require('crypto');
const fs = require('fs/promises');
const path = require('path');
const { FieldValue } = require('firebase-admin/firestore');
const {
  LOCAL_BACKEND,
  isLocalStorage,
  removeStoredFiles,
  resolveUploadsDir,
  saveLocalBuffer,
} = require('./verificationStorageService');
const { newEvidence, faceResultFor, verifiableRoles } = require('./workerVerificationPolicy');
const { evaluateWorkerVerification } = require('./verificationDecisionService');
const { validateFaceCapture } = require('./captureQualityService');

// Euclidean distance between face-api descriptors, mapped to a 0-100
// similarity using historical display anchors. These anchors are not supported
// by a measured SwiftServe genuine/impostor calibration dataset.
const SIMILARITY_ANCHORS = Object.freeze([
  [0, 100],
  [0.45, 80],
  [0.6, 60],
  [1, 0],
]);
const DEFAULT_AUTO_VERIFY_MIN = 80;
const DEFAULT_REVIEW_MIN = 60;
const DESCRIPTOR_DIMENSIONS = 128;
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
  const { Canvas, Image, ImageData, createCanvas, loadImage } = canvas;

  const wasmDirectory = `${path.dirname(require.resolve('@tensorflow/tfjs-backend-wasm'))}${path.sep}`;
  wasm.setWasmPaths(wasmDirectory);
  faceapi.env.monkeyPatch({ Canvas, Image, ImageData });
  return { tf, faceapi, createCanvas, loadImage };
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

const MAX_INFERENCE_SIDE = 1600;
const EXIF_ROTATION = Object.freeze({ 3: 180, 6: 90, 8: 270 });

// Phone cameras usually store pixels sideways plus an EXIF orientation tag,
// which node-canvas ignores. Returns the clockwise rotation the tag asks for.
const exifRotation = (buffer) => {
  if (!buffer || buffer[0] !== 0xff || buffer[1] !== 0xd8) return 0;
  let offset = 2;
  while (offset + 4 <= buffer.length && buffer[offset] === 0xff) {
    const marker = buffer[offset + 1];
    const length = buffer.readUInt16BE(offset + 2);
    if (marker === 0xda) return 0;
    if (marker === 0xe1 && buffer.toString('ascii', offset + 4, offset + 8) === 'Exif') {
      const tiff = offset + 10;
      if (tiff + 8 > buffer.length) return 0;
      const littleEndian = buffer.toString('ascii', tiff, tiff + 2) === 'II';
      const read16 = (at) => (littleEndian ? buffer.readUInt16LE(at) : buffer.readUInt16BE(at));
      const read32 = (at) => (littleEndian ? buffer.readUInt32LE(at) : buffer.readUInt32BE(at));
      const directory = tiff + read32(tiff + 4);
      if (directory + 2 > buffer.length) return 0;
      for (let index = 0; index < read16(directory); index += 1) {
        const entry = directory + 2 + index * 12;
        if (entry + 10 > buffer.length) return 0;
        if (read16(entry) === 0x0112) return EXIF_ROTATION[read16(entry + 8)] || 0;
      }
      return 0;
    }
    offset += 2 + length;
  }
  return 0;
};

const rotatedCanvas = (createCanvas, decodedImage, degrees) => {
  const scale = Math.min(1, MAX_INFERENCE_SIDE / Math.max(decodedImage.width, decodedImage.height));
  const width = Math.round(decodedImage.width * scale);
  const height = Math.round(decodedImage.height * scale);
  const sideways = degrees % 180 !== 0;
  const target = createCanvas(sideways ? height : width, sideways ? width : height);
  const context = target.getContext('2d');
  context.translate(target.width / 2, target.height / 2);
  context.rotate((degrees * Math.PI) / 180);
  context.drawImage(decodedImage, -width / 2, -height / 2, width, height);
  return target;
};

const largestDetection = (detections) => detections.reduce((largest, current) => (
  current.detection.box.area > largest.detection.box.area ? current : largest
));

const getFaceDescriptor = async (imageBuffer, image, runtime, { quality = validateFaceCapture } = {}) => {
  const activeRuntime = runtime || await loadModels();
  const decodedImage = await activeRuntime.loadImage(imageBuffer);
  // Honour the EXIF tag first, then try the other orientations in case the ID
  // card itself was photographed sideways or upside down.
  const base = exifRotation(imageBuffer);
  const turns = activeRuntime.createCanvas ? [0, 90, 270, 180] : [null];

  for (const turn of turns) {
    const candidate = turn === null
      ? decodedImage
      : rotatedCanvas(activeRuntime.createCanvas, decodedImage, (base + turn) % 360);
    const detections = await activeRuntime.faceapi
      .detectAllFaces(candidate)
      .withFaceLandmarks()
      .withFaceDescriptors();
    if (detections.length === 0) continue;
    if (detections.length === 1) {
      await quality(candidate, detections[0], image);
      return detections[0].descriptor;
    }
    // Many IDs print a small secondary "ghost" portrait; use the main photo.
    if (image === 'document') {
      const selected = largestDetection(detections);
      await quality(candidate, selected, image);
      return selected.descriptor;
    }
    throw new FaceDetectionError('MULTIPLE_FACES_DETECTED', image);
  }
  throw new FaceDetectionError('FACE_NOT_DETECTED', image);
};

const percentFromEnv = (value, fallback) => {
  const parsed = Number(value);
  return value !== undefined && value !== '' && Number.isFinite(parsed) && parsed >= 0 && parsed <= 100
    ? parsed
    : fallback;
};

const decisionThresholds = (env = process.env) => {
  const autoVerifyMin = percentFromEnv(env.FACE_AUTO_VERIFY_MIN, DEFAULT_AUTO_VERIFY_MIN);
  const reviewMin = Math.min(percentFromEnv(env.FACE_REVIEW_MIN, DEFAULT_REVIEW_MIN), autoVerifyMin);
  return { autoVerifyMin, reviewMin };
};

const distanceToSimilarity = (distance) => {
  let similarity = 0;
  for (let index = 1; index < SIMILARITY_ANCHORS.length; index += 1) {
    const [toDistance, toScore] = SIMILARITY_ANCHORS[index];
    if (distance <= toDistance) {
      const [fromDistance, fromScore] = SIMILARITY_ANCHORS[index - 1];
      const ratio = (distance - fromDistance) / (toDistance - fromDistance);
      similarity = fromScore + ratio * (toScore - fromScore);
      break;
    }
  }
  return Math.round(similarity * 100) / 100;
};

const bandFor = (similarity, { autoVerifyMin, reviewMin }) => {
  if (similarity >= autoVerifyMin) return 'strong';
  if (similarity >= reviewMin) return 'borderline';
  return 'mismatch';
};

const compareDescriptors = (a, b, thresholds = decisionThresholds()) => {
  const invalid = message => Object.assign(new TypeError(message), { code: 'INVALID_FACE_DESCRIPTOR' });
  for (const descriptor of [a, b]) {
    if (!(Array.isArray(descriptor) || ArrayBuffer.isView(descriptor)) || descriptor.length !== DESCRIPTOR_DIMENSIONS) {
      throw invalid(`Face descriptors must contain exactly ${DESCRIPTOR_DIMENSIONS} dimensions.`);
    }
    let nonzero = false;
    for (let index = 0; index < DESCRIPTOR_DIMENSIONS; index += 1) {
      if (!Number.isFinite(descriptor[index])) {
        throw invalid('Face descriptors must contain only finite numbers.');
      }
      if (descriptor[index] !== 0) nonzero = true;
    }
    // Exact zero is a known unusable output, including the library's empty-crop
    // fallback. No norm interval or normalization is justified by current data.
    if (!nonzero) throw invalid('Face descriptors must not be zero vectors.');
  }

  let squaredDifference = 0;
  for (let index = 0; index < a.length; index += 1) {
    const difference = a[index] - b[index];
    squaredDifference += difference * difference;
  }
  if (!Number.isFinite(squaredDifference)) {
    throw invalid('Face descriptor distance could not be represented.');
  }

  const distance = Number(Math.sqrt(squaredDifference).toFixed(6));
  const similarity = distanceToSimilarity(distance);
  const band = bandFor(similarity, thresholds);

  // `confidence` is kept as an alias of `similarity` for older clients.
  return {
    match: band !== 'mismatch',
    band,
    distance,
    similarity,
    confidence: similarity,
  };
};

const verifyFaces = async (
  documentBuffer,
  selfieBuffer,
  { descriptor = getFaceDescriptor, thresholds = decisionThresholds() } = {},
) => {
  // Process sequentially to avoid holding two inference pipelines in memory.
  const documentDescriptor = await descriptor(documentBuffer, 'document');
  const selfieDescriptor = await descriptor(selfieBuffer, 'selfie');
  return compareDescriptors(documentDescriptor, selfieDescriptor, thresholds);
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

// Saves one image to local disk or Cloud Storage and returns the stored path.
const storeImage = async ({ backend, bucket, filePath, file, uploadsDir }) => {
  if (backend === LOCAL_BACKEND) return saveLocalBuffer(filePath, file.buffer, uploadsDir);
  await bucket.file(filePath).save(file.buffer, {
    resumable: false,
    metadata: { contentType: file.mimetype },
  });
  return filePath;
};

// Mismatches store no images, only the score, so admins can spot repeated
// failed attempts.
const recordFailedAttempt = (verificationRef, comparison, thresholds, attemptedAt) => verificationRef
  .collection('face_attempts')
  .add({
    similarity: comparison.similarity,
    distance: comparison.distance,
    reviewMin: thresholds.reviewMin,
    face: faceResultFor(comparison),
    attemptedAt,
  })
  .catch((error) => console.error('Failed to record face match attempt:', error));

const compareAndCreateSubmission = async ({
  uid,
  idType,
  idNumber,
  document,
  selfie,
  db,
  storage,
  documentBinding,
  verify = verifyFaces,
  thresholds = decisionThresholds(),
  now = () => new Date(),
  uploadsDir = resolveUploadsDir(),
  blobStorage = process.env.SWIFTSERVE_NETLIFY_PILOT === 'true' ? require('./netlifyVerificationStorage').getBlobStorage() : null,
}) => {
  const userRef = db.collection('users').doc(uid);
  const verificationRef = db.collection('worker_verifications').doc(uid);
  const [userSnapshot, verificationSnapshot] = await Promise.all([
    userRef.get(),
    verificationRef.get(),
  ]);
  const user = userSnapshot.data();

  if (!userSnapshot.exists || !verifiableRoles.includes(user?.role)) {
    throw new WorkerAccessError('A worker or client account is required.');
  }
  if (user.verificationStatus === 'verified') {
    throw new VerificationConflictError('This account is already verified.');
  }
  const prior = verificationSnapshot.exists ? verificationSnapshot.data() : null;
  if (prior && !FINAL_OR_REPLACEABLE_STATUSES.has(prior.status)) {
    throw new VerificationConflictError('A verification submission is already being reviewed.');
  }

  const comparison = await verify(document.buffer, selfie.buffer, { thresholds });
  if (!comparison.match) {
    await recordFailedAttempt(verificationRef, comparison, thresholds, now());
    return { ...comparison, faceResult: faceResultFor(comparison) };
  }

  const submittedAt = now();
  // Face matching is independent evidence, never worker authorization.
  const status = 'pending';
  const submissionId = crypto.randomUUID();
  const evidence = newEvidence(comparison, { workerId: uid, submissionId, now: submittedAt, thresholds });
  const workerDecision = evaluateWorkerVerification(evidence, { workerId: uid, account: user, now: submittedAt });
  const basePath = `worker_verifications/${uid}/${submissionId}`;
  // TODO(billing): local disk while there is no Storage bucket. Set
  // VERIFICATION_STORAGE=gcs with a real FIREBASE_STORAGE_BUCKET for production.
  const backend = blobStorage ? 'netlify-blobs' : (isLocalStorage() || !storage?.bucket ? LOCAL_BACKEND : 'gcs');
  const bucket = backend === 'gcs' ? storage.bucket() : null;
  const storedPaths = [];

  try {
    const governmentIdPath = blobStorage ? await blobStorage.save({ owner: uid, submissionId, kind: 'document', file: document }) : await storeImage({
      backend,
      bucket,
      filePath: `${basePath}/government_id.${extensionFor(document.mimetype)}`,
      file: document,
      uploadsDir,
    });
    storedPaths.push(governmentIdPath);
    const facePhotoPath = blobStorage ? await blobStorage.save({ owner: uid, submissionId, kind: 'selfie', file: selfie }) : await storeImage({
      backend,
      bucket,
      filePath: `${basePath}/face_photo.${extensionFor(selfie.mimetype)}`,
      file: selfie,
      uploadsDir,
    });
    storedPaths.push(facePhotoPath);

    const writeSubmission = async batch => {
    if (blobStorage) await blobStorage.attach(batch, storedPaths, uid, submissionId);
    batch.set(verificationRef, {
      ...evidence,
      workerDecision,
      workerId: uid,
      submissionId,
      ...(documentBinding ? { documentBinding } : {}),
      idType: String(idType).trim(),
      maskedIdNumber: maskIdNumber(idNumber),
      governmentIdPath,
      governmentIdMimeType: document.mimetype,
      facePhotoPath,
      facePhotoMimeType: selfie.mimetype,
      storageBackend: backend,
      idSubmitted: true,
      faceVerified: true,
      faceDistance: comparison.distance,
      faceMatchConfidence: comparison.similarity,
      faceMatchBand: comparison.band,
      faceMatchThreshold: thresholds.reviewMin,
      faceAutoVerifyMin: thresholds.autoVerifyMin,
      faceReviewFlag: comparison.band === 'borderline' ? 'borderline' : FieldValue.delete(),
      faceVerificationProvider: 'local_face_api',
      faceVerifiedAt: submittedAt,
      status,
      adminNotes: '',
      submittedAt,
      updatedAt: submittedAt,
      reviewedAt: FieldValue.delete(),
      reviewedBy: FieldValue.delete(),
      purgeAfter: FieldValue.delete(),
    }, { merge: true });
    };
    // Recheck after inference/upload in every storage mode. A concurrent legacy
    // approval or newer submission must not be overwritten by this request.
    await db.runTransaction(async tx => {
        const currentUser = await tx.get(userRef), currentVerification = await tx.get(verificationRef);
        if (documentBinding) {
          await require('./documentSuitabilityService').acceptedDocument(db, uid, documentBinding.sessionId, documentBinding.attemptId, documentBinding.sha256, tx);
        }
        if (!verifiableRoles.includes(currentUser.data()?.role) || currentUser.data()?.verificationStatus === 'verified' ||
          (currentVerification.exists && !FINAL_OR_REPLACEABLE_STATUSES.has(currentVerification.data().status))) {
          throw new VerificationConflictError('Verification eligibility changed during upload.');
        }
        await writeSubmission(tx);
    });
  } catch (error) {
    if (blobStorage) await blobStorage.requestDeletion(storedPaths).catch(() => {});
    else await removeStoredFiles({ paths: storedPaths, backend, storage, uploadsDir }).catch(() => {});
    throw error;
  }

  if (prior) {
    const priorPaths = [prior.governmentIdPath, prior.facePhotoPath];
    // Older records may name a storage target that is no longer configured.
    await Promise.resolve()
      .then(() => (prior.storageBackend === 'netlify-blobs' && blobStorage
        ? blobStorage.requestDeletion(priorPaths)
        : (prior.storageBackend || 'gcs') === LOCAL_BACKEND
        ? removeStoredFiles({ paths: priorPaths, backend: LOCAL_BACKEND, uploadsDir })
        : markForDeletion(storage.bucket(), priorPaths, submittedAt)))
      .catch((error) => console.error('Failed to clean up replaced verification images:', error));
  }

  return { ...comparison, status, faceResult: evidence.face, workerDecision };
};

const resetModelStateForTests = () => {
  faceRuntime = undefined;
  modelsPromise = undefined;
};

module.exports = {
  DEFAULT_AUTO_VERIFY_MIN,
  DEFAULT_REVIEW_MIN,
  DESCRIPTOR_DIMENSIONS,
  MODEL_FILES,
  MODELS_PATH,
  FaceDetectionError,
  VerificationConflictError,
  WorkerAccessError,
  compareAndCreateSubmission,
  compareDescriptors,
  decisionThresholds,
  distanceToSimilarity,
  exifRotation,
  getFaceDescriptor,
  loadModels,
  markForDeletion,
  maskIdNumber,
  resetModelStateForTests,
  validateModelFiles,
  verifyFaces,
};
