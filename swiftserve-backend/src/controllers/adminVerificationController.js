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
  isFinalStatus,
  purgeDateFor,
} = require('../services/verificationDecisionService');

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

const serialize = (id, verification, user = {}) => ({
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
  purgeAfter: toIso(verification.purgeAfter),
  reviewDate: toIso(verification.reviewedAt),
  reviewedBy: verification.reviewedBy || null,
  adminNotes: verification.adminNotes || '',
});

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
  const base = `${req.protocol}://${req.get('host')}`;
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
        governmentIdUrl: backend === LOCAL_BACKEND
          ? localImageUrl(req, workerId)
          : await signedUrl(data.governmentIdPath),
        facePhotoUrl: !data.facePhotoPath
          ? null
          : backend === LOCAL_BACKEND
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
  const { status, adminNotes = '' } = req.body;
  if (!ALLOWED_STATUSES.has(status)) {
    return res.status(400).json({ message: 'Unsupported verification status.' });
  }
  try {
    const workerId = req.params.workerId;
    const verificationRef = db.collection('worker_verifications').doc(workerId);
    const [verification, user] = await Promise.all([
      verificationRef.get(),
      db.collection('users').doc(workerId).get(),
    ]);
    if (!verification.exists) {
      return res.status(404).json({ message: 'Verification request not found.' });
    }
    const { status: currentStatus, reviewedBy: priorReviewer } = verification.data();
    // Automatic face-match approvals stay revocable by an admin.
    const isAutoDecision = currentStatus === 'verified' && priorReviewer === AUTO_REVIEWER;
    if (isFinalStatus(currentStatus) && status !== currentStatus && !isAutoDecision) {
      return res.status(409).json({ message: 'A final verification decision cannot be reopened.' });
    }
    const batch = db.batch();
    const now = new Date();
    const reviewedBy = req.user.email || req.user.uid;
    const isFinalDecision = isFinalStatus(status);
    const purgeAfter = purgeDateFor(status, now);
    batch.update(verificationRef, {
      status,
      adminNotes,
      reviewedAt: now,
      reviewedBy,
      updatedAt: now,
      ...(isFinalDecision ? { purgeAfter } : {}),
    });
    addStatusWrites(batch, db, workerId, status, { senderId: req.user.uid, now });
    await batch.commit();
    if (isFinalDecision) {
      const priorBackend = verification.data().storageBackend || 'gcs';
      // TODO(billing): local files are deleted at decision time (no 30-day
      // GCS lifecycle here). GCS docs keep the mark-for-deletion flow.
      if (priorBackend === LOCAL_BACKEND) {
        await removeStoredFiles({
          paths: [verification.data().governmentIdPath, verification.data().facePhotoPath],
          backend: LOCAL_BACKEND,
          uploadsDir: resolveUploadsDir(),
        }).catch((error) => console.error('Failed to remove local verification images:', error));
      } else {
        await markForDeletion(
          storage.bucket(),
          [verification.data().governmentIdPath, verification.data().facePhotoPath],
          now,
        );
      }
    }
    return res.json({
      item: serialize(
        workerId,
        {
          ...verification.data(),
          status,
          adminNotes,
          reviewedAt: now,
          reviewedBy,
          purgeAfter,
        },
        user.data(),
      ),
    });
  } catch (error) {
    console.error('Update verification error:', error);
    return res.status(500).json({ message: 'Failed to update verification.' });
  }
};

// TODO(billing): serves locally stored ID and selfie photos to admins while there is
// no Storage bucket. Remove the route + handler when VERIFICATION_STORAGE=gcs.
const createImageHandler = ({ database = db, uploadsDir } = {}) => async (req, res) => {
  try {
    const workerId = req.params.workerId;
    const snapshot = await database.collection('worker_verifications').doc(workerId).get();
    if (!snapshot.exists) {
      return res.status(404).json({ message: 'Verification request not found.' });
    }
    const data = snapshot.data();
    const isSelfie = req.query?.kind === 'selfie';
    const imagePath = isSelfie ? data.facePhotoPath : data.governmentIdPath;
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
