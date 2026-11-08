const { db, storage } = require('../config/firebase');
const { markForDeletion } = require('../services/faceVerificationService');
const {
  LOCAL_BACKEND,
  removeStoredFiles,
  resolveUploadsDir,
  sendLocalFile,
} = require('../services/verificationStorageService');
const {
  AUTO_REVIEWER,
  addStatusWrites,
  isLegacyClosure,
  isFinalStatus,
  purgeDateFor,
  evaluateWorkerVerification,
} = require('../services/verificationDecisionService');
const { SCHEMA_VERSION } = require('../services/workerVerificationPolicy');

const ALLOWED_STATUSES = new Set([
  'under_review',
  'verified',
  'rejected',
  'resubmission_required',
]);

const toIso = (value) => {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return value;
};

const serialize = (id, verification, user = {}) => {
  const currentDecision = evaluateWorkerVerification(verification, { workerId: id, account: user });
  // Legacy records stay reviewable for reject/resubmit; approvalReady stays
  // false for them because their evidence fails the current policy.
  const reviewable = !['verified', 'rejected'].includes(verification.status)
    && user.verificationStatus !== 'verified';
  return ({
  verificationId: id,
  workerId: id,
  workerName: user.fullName || 'Worker',
  category: user.category || '',
  location: user.address || '',
  email: user.email || '',
  phone: user.phoneNumber || '',
  dateJoined: toIso(user.createdAt),
  submittedDate: toIso(verification.submittedAt),
  status: verification.status || 'pending',
  idType: verification.idType || '',
  maskedIdNumber: verification.maskedIdNumber || '',
  idSubmitted: Boolean(verification.idSubmitted),
  storageBackend: verification.storageBackend || 'gcs',
  faceVerified: Boolean(verification.faceVerified),
  faceMatchConfidence: verification.faceMatchConfidence ?? null,
  faceMatchThreshold: verification.faceMatchThreshold ?? null,
  faceAutoVerifyMin: verification.faceAutoVerifyMin ?? null,
  faceMatchBand: verification.faceMatchBand || null,
  faceReviewFlag: verification.faceReviewFlag || null,
  autoVerified: verification.reviewedBy === AUTO_REVIEWER,
  faceVerificationProvider: verification.faceVerificationProvider || null,
  faceVerifiedAt: toIso(verification.faceVerifiedAt),
  // Private authorized-review projection; never part of public worker profiles.
  face: verification.face || null,
  governmentStatus: verification.government?.status || 'NOT_INTEGRATED',
  livenessStatus: verification.liveness?.status || 'NOT_IMPLEMENTED',
  workerDecision: verification.workerDecision || null,
  schemaVersion: verification.schemaVersion || null,
  providerType: verification.providerType || 'NONE',
  checkSource: verification.checkSource || 'SERVER',
  governmentProvider: verification.government?.provider || 'NONE',
  reviewStatus: verification.review?.status || 'PENDING',
  policyReasons: [...currentDecision.reasonCodes, ...(!verification.documentBinding && verification.status !== 'verified' ? ['DOCUMENT_REVIEW_REQUIRED'] : [])],
  officialGovernmentAuthenticated: currentDecision.officiallyVerified,
  reviewable,
  documentSuitabilityBound: Boolean(verification.documentBinding),
  approvalReady: reviewable && Boolean(verification.documentBinding) && currentDecision.reasonCodes.every(code => code === 'ADMIN_REVIEW_REQUIRED'),
  purgeAfter: toIso(verification.purgeAfter),
  reviewDate: toIso(verification.reviewedAt),
  reviewedBy: verification.reviewedBy || null,
  adminNotes: verification.adminNotes || '',
}); };

const listVerifications = async (req, res) => {
  try {
    const snapshot = await db.collection('worker_verifications').get();
    const items = await Promise.all(snapshot.docs.map(async (document) => {
      const user = await db.collection('users').doc(document.id).get();
      return serialize(document.id, document.data(), user.data());
    }));
    return res.json({ items });
  } catch (error) {
    console.error('List verifications error:', error);
    return res.status(500).json({ message: 'Failed to load verification requests.' });
  }
};

const signedUrl = async (path) => {
  if (!path) return null;
  const [url] = await storage.bucket().file(path).getSignedUrl({
    action: 'read',
    expires: Date.now() + 15 * 60 * 1000,
  });
  return url;
};

const localImageUrl = (req, workerId, kind = 'document') => {
  const base = process.env.SWIFTSERVE_NETLIFY_PILOT === 'true' ? '' : `${req.protocol}://${req.get('host')}`;
  const url = `${base}/api/admin/verifications/${encodeURIComponent(workerId)}/image`;
  return kind === 'selfie' ? `${url}?kind=selfie` : url;
};

const getVerification = async (req, res) => {
  try {
    const workerId = req.params.workerId;
    const [verification, user] = await Promise.all([
      db.collection('worker_verifications').doc(workerId).get(),
      db.collection('users').doc(workerId).get(),
    ]);
    if (!verification.exists) {
      return res.status(404).json({ message: 'Verification request not found.' });
    }
    const data = verification.data();
    const backend = data.storageBackend || 'gcs';
    return res.json({
      item: {
        ...serialize(workerId, data, user.data()),
        // TODO(billing): local files are served through the authenticated
        // image route below (plain links can't carry the admin Bearer token,
        // so the admin app fetches them into a blob URL). GCS docs keep
        // signed URLs. Remove the branch when VERIFICATION_STORAGE=gcs.
        governmentIdUrl: [LOCAL_BACKEND, 'netlify-blobs'].includes(backend)
          ? localImageUrl(req, workerId)
          : await signedUrl(data.governmentIdPath),
        facePhotoUrl: !data.facePhotoPath
          ? null
          : [LOCAL_BACKEND, 'netlify-blobs'].includes(backend)
            ? localImageUrl(req, workerId, 'selfie')
            : await signedUrl(data.facePhotoPath),
      },
    });
  } catch (error) {
    console.error('Get verification error:', error);
    return res.status(500).json({ message: 'Failed to load verification details.' });
  }
};

const updateVerification = async (req, res) => {
  const { can, addAudit, actorOf } = require('../services/adminAccessService');
  if (!req.user?.uid || !can(req.adminAccess, 'verification.manage')) {
    return res.status(403).json({ code: 'VERIFICATION_REVIEW_FORBIDDEN' });
  }
  if (Object.keys(req.body || {}).some(key => !['status', 'adminNotes'].includes(key))) {
    return res.status(400).json({ code: 'INVALID_VERIFICATION_FIELDS' });
  }
  const { status, adminNotes = '' } = req.body || {};
  if (!ALLOWED_STATUSES.has(status) || typeof adminNotes !== 'string' || adminNotes.length > 2000) {
    return res.status(400).json({ message: 'Unsupported verification status.' });
  }
  try {
    const workerId = req.params.workerId;
    if (workerId === req.user.uid) return res.status(403).json({ code: 'SELF_REVIEW_FORBIDDEN' });
    const verificationRef = db.collection('worker_verifications').doc(workerId);
    const isFinalDecision = isFinalStatus(status);
    const { before, updated, account, now } = await db.runTransaction(async transaction => {
      const verification = await transaction.get(verificationRef);
      const user = await transaction.get(db.collection('users').doc(workerId));
      const now = new Date(), purgeAfter = purgeDateFor(status, now);
      const before = verification.data(), account = user.data();
      const refuse = (code, message, status = 409) => { throw Object.assign(new Error(message), { code, status }); };
      if (!verification.exists || !user.exists) refuse('VERIFICATION_NOT_FOUND', 'Verification request not found.', 404);
      if ((before.schemaVersion !== SCHEMA_VERSION && !isLegacyClosure(before, workerId, status))
        || before.status === 'verified' || account.verificationStatus === 'verified') {
        refuse('LEGACY_VERIFICATION_PROTECTED', 'Existing verified and legacy records require a separately approved transition.');
      }
      if (isFinalStatus(before.status) && status !== before.status) refuse('FINAL_VERIFICATION_DECISION', 'A final verification decision cannot be reopened.');
      if (status === 'verified' && before.documentBinding) {
        const binding = before.documentBinding;
        await require('../services/documentSuitabilityService').acceptedDocument(db, workerId, binding.sessionId, binding.attemptId, binding.sha256, transaction);
      }
      const review = { required: true, status: status === 'verified' ? 'APPROVED' : status === 'rejected' ? 'REJECTED' : 'PENDING',
        reviewerId: req.user.uid, reviewedAt: now, reasonCode: status === 'verified' ? 'CHECKS_REVIEWED' : status === 'rejected' ? 'REVIEW_REJECTED' : 'REVIEW_PENDING' };
      const updated = { ...before, review, status, adminNotes, reviewedAt: now, reviewedBy: req.user.uid,
        updatedAt: now, ...(isFinalDecision ? { purgeAfter } : {}) };
      if (status === 'verified' && evaluateWorkerVerification(updated, { workerId, account, now }).eligible && !before.documentBinding) {
        refuse('DOCUMENT_REVIEW_REQUIRED', 'Document suitability must be reviewed for the current evidence attempt before approval.');
      }
      updated.workerDecision = addStatusWrites(transaction, db, workerId, status, {
        senderId: req.user.uid, now, evidence: updated, account,
      });
      transaction.update(verificationRef, updated);
      addAudit(transaction, actorOf(req), 'verification.reviewed', workerId, { status, policyVersion: updated.workerDecision.policyVersion });
      return { before, updated, account, now };
    });
    if (isFinalDecision) {
      const priorBackend = before.storageBackend || 'gcs';
      // TODO(billing): local files are deleted at decision time (no 30-day
      // GCS lifecycle here). GCS docs keep the mark-for-deletion flow.
      if (priorBackend === 'netlify-blobs') {
        // Retention is already journaled. Reads stop at the deadline; reconciliation
        // deletes expired objects without an untracked fire-and-forget operation.
        await require('../services/netlifyVerificationStorage').getBlobStorage()
          .requestDeletion([before.governmentIdPath, before.facePhotoPath]);
      } else if (priorBackend === LOCAL_BACKEND) {
        await removeStoredFiles({
          paths: [before.governmentIdPath, before.facePhotoPath],
          backend: LOCAL_BACKEND,
          uploadsDir: resolveUploadsDir(),
        }).catch((error) => console.error('Failed to remove local verification images:', error));
      } else {
        // The decision is already saved, so a storage problem must not report failure.
        await Promise.resolve()
          .then(() => markForDeletion(storage.bucket(), [before.governmentIdPath, before.facePhotoPath], now))
          .catch((error) => console.error('Failed to mark verification images for deletion:', error));
      }
    }
    return res.json({ item: serialize(workerId, updated, account) });
  } catch (error) {
    if (error.status && error.code) return res.status(error.status).json({ code: error.code, message: error.message, reasonCodes: error.reasonCodes });
    console.error('Update verification error:', error);
    return res.status(500).json({ message: 'Failed to update verification.' });
  }
};

// TODO(billing): serves locally stored ID and selfie photos to admins while there is
// no Storage bucket. Remove the route + handler when VERIFICATION_STORAGE=gcs.
const createImageHandler = ({ database = db, uploadsDir, blobs } = {}) => async (req, res) => {
  try {
    res.setHeader('Cache-Control', 'private, no-store, max-age=0');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    if (Object.keys(req.query || {}).some(key => key !== 'kind') || (req.query?.kind && !['document','selfie'].includes(req.query.kind))) return res.sendStatus(400);
    const workerId = req.params.workerId;
    const snapshot = await database.collection('worker_verifications').doc(workerId).get();
    if (!snapshot.exists) {
      return res.status(404).json({ message: 'Verification request not found.' });
    }
    const data = snapshot.data();
    const isSelfie = req.query?.kind === 'selfie';
    const imagePath = isSelfie ? data.facePhotoPath : data.governmentIdPath;
    if (data.storageBackend === 'netlify-blobs') {
      const adapter = blobs || require('../services/netlifyVerificationStorage').getBlobStorage();
      const image = await adapter.read({ key: imagePath, owner: workerId, submissionId: data.submissionId, kind: isSelfie ? 'selfie' : 'document' });
      res.type(image.contentType); return res.send(image.bytes);
    }
    if ((data.storageBackend || 'gcs') !== LOCAL_BACKEND || !imagePath) {
      return res.status(404).json({ message: 'No locally stored verification image.' });
    }
    const served = await sendLocalFile(res, imagePath, {
      uploadsDir: uploadsDir || resolveUploadsDir(),
      contentType: isSelfie ? data.facePhotoMimeType : data.governmentIdMimeType,
    });
    if (!served) {
      return res.status(404).json({ message: 'Verification image not found.' });
    }
  } catch (error) {
    if (error.status === 404) return res.sendStatus(404);
    console.error('Get verification image error:', error);
    return res.status(500).json({ message: 'Failed to load verification image.' });
  }
};

const getVerificationImage = createImageHandler();

module.exports = {
  listVerifications,
  getVerification,
  getVerificationImage,
  createImageHandler,
  localImageUrl,
  updateVerification,
};
