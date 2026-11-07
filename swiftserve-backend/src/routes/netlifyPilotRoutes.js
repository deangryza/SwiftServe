// Isolated manual-review pilot. Does not fabricate a successful face comparison.
const express = require('express');
const multer = require('multer');
const { randomUUID } = require('node:crypto');
const { auth, db } = require('../config/firebase');
const authenticate = require('../middleware/authMiddleware');
const { inspectImage, MAX_BYTES } = require('../services/verificationImagePolicy');
const { maskIdNumber } = require('../services/faceVerificationService');
const { getBlobStorage } = require('../services/netlifyVerificationStorage');
const router = express.Router();
router.post('/verification-images/reconcile', require('../middleware/adminMiddleware'), require('../middleware/adminMiddleware').superAdmin, async (_req, res, next) => {
  try {
    const deadline = Date.now() + 45000;
    const result = await getBlobStorage().reconcile({ shouldStop: () => Date.now() >= deadline });
    res.status(result.failed || result.interrupted || result.lostOwnership ? 503 : 200).json(result);
  } catch (error) { next(error); }
});
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: MAX_BYTES, files: 2, fields: 2, fieldSize: 256 } }).fields([{ name: 'document', maxCount: 1 }, { name: 'selfie', maxCount: 1 }]);
router.post('/verification-images', authenticate, require('express-rate-limit').rateLimit({ windowMs: 900000, limit: 5, legacyHeaders: false }), async (req, res, next) => {
  try {
    // Reject ineligible callers before buffering multipart files or loading canvas.
    const [user, prior] = await Promise.all([db.collection('users').doc(req.user.uid).get(), db.collection('worker_verifications').doc(req.user.uid).get()]);
    if (user.data()?.role !== 'worker' || user.data()?.accountStatus === 'suspended') return res.sendStatus(403);
    if (user.data()?.verificationStatus === 'verified' || (prior.exists && !['rejected','resubmission_required'].includes(prior.data().status))) return res.status(409).json({code:'VERIFICATION_CONFLICT'});
    const time = new Date(), midnight = Date.UTC(time.getUTCFullYear(),time.getUTCMonth(),time.getUTCDate());
    const quota = db.collection('pilot_upload_quotas').doc(require('node:crypto').createHash('sha256').update(req.user.uid+'/'+time.toISOString().slice(0,10)).digest('hex'));
    await db.runTransaction(async tx => {
      const row=await tx.get(quota), attempts=row.data()?.attempts ?? 0;
      if (!Number.isSafeInteger(attempts) || attempts<0 || attempts>=5) throw Object.assign(new Error('Daily pilot upload limit reached.'),{status:429});
      tx.set(quota,{attempts:attempts+1,owner:req.user.uid,updatedAt:time,expiresAt:new Date(midnight+2*86400000)});
    });
    next();
  } catch(error) {
    if(error.status)return res.sendStatus(error.status);
    next(error);
  }
}, upload, async (req, res, next) => {
  const files = [req.files?.document?.[0], req.files?.selfie?.[0]];
  const keys = [], adapter = getBlobStorage();
  try {
    if (typeof req.body.idType !== 'string' || !req.body.idType.trim() || req.body.idType.length > 120 || typeof req.body.idNumber !== 'string' || !req.body.idNumber.trim() || req.body.idNumber.length > 120) return res.sendStatus(400);
    // Reject oversized headers BEFORE native decoding. Decode only on upload;
    // no canvas or face model is loaded for ordinary admin requests.
    for (const file of files) {
      const expected = inspectImage(file);
      let image;
      try { image = await require('canvas').loadImage(file.buffer); }
      catch { return res.status(400).json({ code: 'PILOT_IMAGE_DECODE_FAILED' }); }
      if (image.width !== expected.width || image.height !== expected.height) return res.status(400).json({code:'PILOT_IMAGE_DIMENSIONS_MISMATCH'});
    }
    const submissionId = randomUUID();
    for (let i = 0; i < 2; i++) keys.push(await adapter.save({ owner: req.user.uid, submissionId, kind: i ? 'selfie' : 'document', file: files[i] }));
    await db.runTransaction(async tx => {
      const userRef = db.collection('users').doc(req.user.uid), ref = db.collection('worker_verifications').doc(req.user.uid);
      const current = await tx.get(userRef), prior = await tx.get(ref);
      if (current.data()?.role !== 'worker' || current.data()?.accountStatus === 'suspended' || current.data()?.verificationStatus === 'verified' ||
        (prior.exists && !['rejected', 'resubmission_required'].includes(prior.data().status))) throw Object.assign(new Error('Verification is already active.'), { status: 409 });
      await adapter.attach(tx, keys, req.user.uid, submissionId);
      tx.set(ref, { workerId: req.user.uid, submissionId, status: 'pending', storageBackend: 'netlify-blobs',
        governmentIdPath: keys[0], facePhotoPath: keys[1], governmentIdMimeType: files[0].mimetype, facePhotoMimeType: files[1].mimetype,
        idType: req.body.idType.trim(), maskedIdNumber: maskIdNumber(req.body.idNumber), idSubmitted: true, faceVerified: false,
        faceVerificationProvider: 'manual_local_pilot', submittedAt: new Date(), updatedAt: new Date() });
    });
    return res.status(201).json({ verification: { status: 'pending', faceVerified: false }, manualReviewRequired: true });
  } catch (error) {
    await adapter.requestDeletion(keys).catch(() => {});
    if (error.status) return res.status(error.status).json({ code: error.code || 'PILOT_UPLOAD_REJECTED' });
    next(error);
  } finally { for (const file of files) if (file) file.buffer = undefined; }
});
module.exports = router;
