const { db, storage } = require('../config/firebase');

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
  faceVerified: Boolean(verification.faceVerified),
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
    return res.json({
      item: {
        ...serialize(workerId, data, user.data()),
        governmentIdUrl: await signedUrl(data.governmentIdPath),
        facePhotoUrl: await signedUrl(data.facePhotoPath),
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
    const batch = db.batch();
    const now = new Date();
    const reviewedBy = req.user.email || req.user.uid;
    batch.update(verificationRef, {
      status,
      adminNotes,
      reviewedAt: now,
      reviewedBy,
      updatedAt: now,
    });
    batch.set(db.collection('users').doc(workerId), {
      verificationStatus: status,
      updatedAt: now,
    }, { merge: true });
    batch.set(db.collection('worker_profiles').doc(workerId), {
      verificationStatus: status,
      updatedAt: now,
    }, { merge: true });
    batch.set(db.collection('notifications').doc(), {
      recipientId: workerId,
      senderId: req.user.uid,
      title: 'Verification updated',
      body: `Your worker verification is now ${status.replaceAll('_', ' ')}.`,
      read: false,
      createdAt: now,
    });
    await batch.commit();
    return res.json({
      item: serialize(
        workerId,
        { ...verification.data(), status, adminNotes, reviewedAt: now, reviewedBy },
        user.data(),
      ),
    });
  } catch (error) {
    console.error('Update verification error:', error);
    return res.status(500).json({ message: 'Failed to update verification.' });
  }
};

module.exports = { listVerifications, getVerification, updateVerification };
