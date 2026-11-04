const express = require('express');
const { ipKeyGenerator, rateLimit } = require('express-rate-limit');
const multer = require('multer');

const authenticateUser = require('../middleware/authMiddleware');
const { db, storage } = require('../config/firebase');
const {
  FaceDetectionError,
  VerificationConflictError,
  WorkerAccessError,
  compareAndCreateSubmission,
  verifyFaces,
} =require('../services/faceVerificationService');
const { faceResultFor } = require('../services/workerVerificationPolicy');
const { CaptureQualityError } = require('../services/captureQualityService');
const { acceptedDocument } = require('../services/documentSuitabilityService');

const ALLOWED_IMAGE_TYPES = new Set(['image/jpeg', 'image/png']);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: process.env.SWIFTSERVE_NETLIFY_PILOT === 'true' ? 1536 * 1024 : 5 * 1024 * 1024, files: 2, fields: 4 },
  fileFilter: (_req, file, callback) => {
    if (!ALLOWED_IMAGE_TYPES.has(file.mimetype)) {
      const error = new Error('Only JPEG and PNG images are supported.');
      error.code = 'UNSUPPORTED_IMAGE_TYPE';
      return callback(error);
    }
    return callback(null, true);
  },
});

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 5,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  keyGenerator: (req) => `${req.user?.uid || 'anonymous'}:${ipKeyGenerator(req.ip)}`,
  handler: (_req, res) => res.status(429).json({
    code: 'RATE_LIMITED',
    message: 'Too many verification attempts. Try again later.',
  }),
});

const uploadPair = upload.fields([
  { name: 'document', maxCount: 1 },
  { name: 'selfie', maxCount: 1 },
]);

const hasExpectedSignature = (file) => {
  const bytes = file?.buffer;
  if (!bytes || bytes.length < 8) return false;
  if (file.mimetype === 'image/jpeg') {
    return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  }
  return bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
};

const createVerificationRouter = ({
  authenticate = authenticateUser,
  database = db,
  firebaseStorage = storage,
  compare = compareAndCreateSubmission,
  faceCompare = verifyFaces,
  attemptLimiter = limiter,
  checkDocument = acceptedDocument,
} = {}) => {
  const router = express.Router();

  router.post(['/verify', '/verify/face'], authenticate, attemptLimiter, (req, res, next) => {
    if (process.env.NATIONAL_ID_MOCK_ENABLED === 'true') {
      return res.status(503).json({ code: 'USE_MOCK_IDENTITY_SESSION', message: 'The isolated identity demo cannot use the legacy worker auto-approval path.' });
    }
    if (process.env.SWIFTSERVE_NETLIFY_PILOT === 'true') {
      // Hosted inference is unverified. Preserve the normal local comparison path.
      return res.status(503).json({ code: 'PILOT_FACE_VERIFICATION_UNVERIFIED', message: 'Face verification is unavailable in the local Netlify pilot. Use the existing local verification workflow.' });
    }
    uploadPair(req, res, (error) => {
      if (error) return next(error);
      return next();
    });
  }, async (req, res, next) => {
    let document;
    let selfie;
    try {
      document = req.files?.document?.[0];
      selfie = req.files?.selfie?.[0];
      if (Object.keys(req.body || {}).some(key => !['idType', 'idNumber', 'documentSessionId', 'documentAttemptId'].includes(key))) {
        return res.status(400).json({ code: 'INVALID_VERIFICATION_FIELDS', message: 'Only ID type and number are accepted; verification decisions are server-owned.' });
      }
      const idType = String(req.body?.idType || '').trim();
      const idNumber = String(req.body?.idNumber || '').trim();
      if (!document || !selfie || !idType || !idNumber) {
        return res.status(400).json({
          code: 'INVALID_UPLOAD',
          message: 'ID type, ID number, document, and selfie are required.',
        });
      }
      if (!hasExpectedSignature(document) || !hasExpectedSignature(selfie)) {
        return res.status(415).json({
          code: 'UNSUPPORTED_IMAGE_TYPE',
          message: 'The uploaded files are not valid JPEG or PNG images.',
        });
      }
      const documentBinding = await checkDocument(database, req.user.uid, req.body.documentSessionId, req.body.documentAttemptId, document.buffer);
      if (documentBinding && documentBinding.declaredType !== idType) throw Object.assign(new Error('Document type changed'), { code: 'DOCUMENT_TYPE_CHANGED', status: 409 });
      let result;
      if (req.path === '/verify/face') {
        const profile = (await database.collection('users').doc(req.user.uid).get()).data();
        if (!profile || !['client', 'worker'].includes(profile.role)
          || [profile.accountStatus, profile.status].some(status => ['suspended', 'disabled', 'inactive'].includes(status))) {
          return res.status(403).json({ code: 'ACCOUNT_REQUIRED', message: 'An active SwiftServe profile is required.' });
        }
        // Comparison only: no submission, image storage, trust/profile or worker writes.
        result = await faceCompare(document.buffer, selfie.buffer);
        result = { ...result, faceResult: faceResultFor(result), status: 'pending',
          governmentStatus: 'NOT_INTEGRATED', livenessStatus: 'NOT_IMPLEMENTED', reviewStatus: 'NOT_REQUIRED',
          workerDecision: { status: 'NOT_APPLICABLE', eligible: false, officiallyVerified: false } };
      } else result = await compare({
        uid: req.user.uid,
        idType,
        idNumber,
        document,
        selfie,
        db: database,
        storage: firebaseStorage,
        documentBinding,
      });
      if (!result.match) {
        return res.json({
          match: false,
          similarity: result.similarity,
          confidence: result.confidence,
          distance: result.distance,
          band: result.band,
          faceResult: result.faceResult,
          code: 'FACE_MISMATCH',
        });
      }
      return res.status(201).json({
        match: true,
        similarity: result.similarity,
        confidence: result.confidence,
        distance: result.distance,
        band: result.band,
        faceResult: result.faceResult,
        workerDecision: result.workerDecision,
        governmentStatus: result.governmentStatus || 'NOT_INTEGRATED',
        livenessStatus: result.livenessStatus || 'NOT_IMPLEMENTED',
        reviewStatus: result.reviewStatus || 'PENDING',
        verification: { status: result.status },
      });
    } catch (error) {
      if (error.code?.startsWith('DOCUMENT_') && error.status) {
        return res.status(error.status).json({ code: error.code, message: 'Document review is required. Refresh the document status or upload a replacement.' });
      }
      if (error instanceof CaptureQualityError) {
        return res.status(422).json({ code: error.code, reason: error.reason, image: error.image, message: error.message });
      }
      if (error instanceof WorkerAccessError) {
        return res.status(403).json({ code: 'WORKER_REQUIRED', message: error.message });
      }
      if (error instanceof VerificationConflictError) {
        return res.status(409).json({ code: 'VERIFICATION_CONFLICT', message: error.message });
      }
      if (error instanceof FaceDetectionError) {
        return res.status(400).json({
          code: error.code,
          message: error.message,
          image: error.image,
          faceResult: { status: error.code === 'FACE_NOT_DETECTED' ? 'FACE_NOT_DETECTED' : 'ERROR' },
        });
      }
      return next(error);
    } finally {
      if (document) document.buffer = undefined;
      if (selfie) selfie.buffer = undefined;
    }
  });

  return router;
};

module.exports = createVerificationRouter;
