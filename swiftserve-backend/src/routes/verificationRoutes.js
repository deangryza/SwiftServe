const express = require('express');
const { ipKeyGenerator, rateLimit } = require('express-rate-limit');
const multer = require('multer');

const authenticateUser = require('../middleware/authMiddleware');
const { db, storage } = require('../config/firebase');
const {
  VerificationConflictError,
  WorkerAccessError,
  compareAndCreateSubmission,
} = require('../services/faceVerificationService');

const ALLOWED_IMAGE_TYPES = new Set(['image/jpeg', 'image/png']);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024, files: 2, fields: 2 },
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
  attemptLimiter = limiter,
} = {}) => {
  const router = express.Router();

  router.post('/verify', authenticate, attemptLimiter, (req, res, next) => {
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
      const result = await compare({
        uid: req.user.uid,
        idType,
        idNumber,
        document,
        selfie,
        db: database,
        storage: firebaseStorage,
      });
      if (!result.match) {
        return res.json({ match: false, confidence: 0, code: 'FACE_MISMATCH' });
      }
      return res.status(201).json({
        match: true,
        confidence: result.confidence,
        verification: { status: result.status },
      });
    } catch (error) {
      if (error instanceof WorkerAccessError) {
        return res.status(403).json({ code: 'WORKER_REQUIRED', message: error.message });
      }
      if (error instanceof VerificationConflictError) {
        return res.status(409).json({ code: 'VERIFICATION_CONFLICT', message: error.message });
      }
      if (error?.name === 'InvalidParameterException') {
        return res.status(400).json({
          code: 'FACE_NOT_DETECTED',
          message: 'No usable face was detected in one or both images.',
        });
      }
      if (['ThrottlingException', 'ProvisionedThroughputExceededException', 'InternalServerError'].includes(error?.name)) {
        return res.status(503).json({
          code: 'VERIFICATION_UNAVAILABLE',
          message: 'Face verification is temporarily unavailable.',
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
