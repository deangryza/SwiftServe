const crypto = require('crypto');
const { FieldValue } = require('firebase-admin/firestore');
const {
  CompareFacesCommand,
  RekognitionClient,
} = require('@aws-sdk/client-rekognition');

const FINAL_OR_REPLACEABLE_STATUSES = new Set([
  'rejected',
  'resubmission_required',
]);

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

const createRekognitionClient = () => new RekognitionClient({
  region: process.env.AWS_REGION || 'ap-southeast-1',
});

const configuredThreshold = () => {
  const value = Number(process.env.FACE_MATCH_THRESHOLD || 80);
  if (!Number.isFinite(value) || value < 0 || value > 100) {
    throw new Error('FACE_MATCH_THRESHOLD must be a number from 0 to 100.');
  }
  return value;
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
    paths.filter(Boolean).map((path) => bucket.file(path).setMetadata({ customTime: value })),
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
  rekognition = createRekognitionClient(),
  threshold = configuredThreshold(),
  now = () => new Date(),
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

  const output = await rekognition.send(new CompareFacesCommand({
    SourceImage: { Bytes: document.buffer },
    TargetImage: { Bytes: selfie.buffer },
    SimilarityThreshold: threshold,
  }));
  const bestMatch = output.FaceMatches?.[0];
  if (!bestMatch) {
    return { match: false, confidence: 0 };
  }

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
      faceMatchConfidence: Number(bestMatch.Similarity || 0),
      faceMatchThreshold: threshold,
      faceVerificationProvider: 'aws_rekognition',
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
      uploadedPaths.map((path) => bucket.file(path).delete({ ignoreNotFound: true })),
    );
    throw error;
  }

  if (prior) {
    await markForDeletion(bucket, [prior.governmentIdPath, prior.facePhotoPath], submittedAt)
      .catch((error) => console.error('Failed to schedule replaced verification images for deletion:', error));
  }

  return {
    match: true,
    confidence: Number(bestMatch.Similarity || 0),
    status: 'pending',
  };
};

module.exports = {
  VerificationConflictError,
  WorkerAccessError,
  compareAndCreateSubmission,
  configuredThreshold,
  createRekognitionClient,
  markForDeletion,
  maskIdNumber,
};

