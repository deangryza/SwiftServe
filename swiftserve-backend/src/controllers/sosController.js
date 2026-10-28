const { db } = require('../config/firebase');

const ACTIVE_JOB_STATUSES = new Set(['accepted', 'ongoing']);

const validPosition = (value) => {
  if (!value || typeof value !== 'object') return null;
  const lat = Number(value.lat);
  const lng = Number(value.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  const accuracy = Number(value.accuracy);
  return { lat, lng, ...(Number.isFinite(accuracy) ? { accuracy } : {}) };
};

const person = (uid, role, user = {}) => ({
  uid,
  role,
  name: user.fullName || 'SwiftServe user',
  phone: user.phoneNumber || '',
  email: user.email || '',
  photoBase64: user.photoBase64 || '',
});

// The worker's identity as SwiftServe verified it; the ID photos themselves
// are purged after the verification decision, so only the metadata remains.
const workerIdentity = (verification = {}, user = {}) => ({
  verificationStatus: verification.status || user.verificationStatus || 'pending',
  idType: verification.idType || '',
  maskedIdNumber: verification.maskedIdNumber || '',
  faceMatchConfidence: verification.faceMatchConfidence ?? null,
  reviewedAt: verification.reviewedAt || null,
});

const raiseSos = async (req, res) => {
  const uid = req.user.uid;
  const requestId = String(req.body.requestId || '');
  if (!requestId) {
    return res.status(400).json({ message: 'A booking is required.' });
  }
  const position = validPosition(req.body.position);

  try {
    const requestRef = db.collection('service_requests').doc(requestId);
    const requestSnapshot = await requestRef.get();
    if (!requestSnapshot.exists) {
      return res.status(404).json({ message: 'Booking not found.' });
    }
    const job = requestSnapshot.data();
    const raisedByRole = job.clientId === uid ? 'client' : job.workerId === uid ? 'worker' : null;
    if (!raisedByRole) {
      return res.status(403).json({ code: 'NOT_A_PARTICIPANT', message: 'You are not part of this booking.' });
    }
    if (!ACTIVE_JOB_STATUSES.has(job.status) || job.modality === 'online') {
      return res.status(409).json({
        code: 'SOS_NOT_AVAILABLE',
        message: 'SOS is available during accepted or ongoing in-person jobs.',
      });
    }

    const now = new Date();
    const existing = await db.collection('sos_alerts')
      .where('requestId', '==', requestId)
      .where('raisedByUid', '==', uid)
      .where('status', '==', 'active')
      .limit(1)
      .get();
    if (existing.docs.length) {
      const alertRef = existing.docs[0].ref;
      await alertRef.update({
        ...(position ? { position, positionUpdatedAt: now } : {}),
        pressCount: (existing.docs[0].data().pressCount || 1) + 1,
        updatedAt: now,
      });
      return res.status(200).json({ id: alertRef.id, status: 'active' });
    }

    const otherUid = raisedByRole === 'client' ? job.workerId : job.clientId;
    const workerId = job.workerId;
    const [raiserUser, otherUser, verification, privateLocation] = await Promise.all([
      db.collection('users').doc(uid).get(),
      otherUid ? db.collection('users').doc(otherUid).get() : null,
      workerId ? db.collection('worker_verifications').doc(workerId).get() : null,
      requestRef.collection('private').doc('location').get(),
    ]);
    const data = (snapshot) => (snapshot?.exists ? snapshot.data() : {});
    const workerUser = raisedByRole === 'worker' ? data(raiserUser) : data(otherUser);

    const alertRef = db.collection('sos_alerts').doc();
    await alertRef.set({
      requestId,
      jobTitle: job.title || '',
      jobCategory: job.category || '',
      jobStatus: job.status,
      modality: job.modality || 'onsite',
      raisedByUid: uid,
      raisedBy: person(uid, raisedByRole, data(raiserUser)),
      otherParty: otherUid
        ? person(otherUid, raisedByRole === 'client' ? 'worker' : 'client', data(otherUser))
        : null,
      workerIdentity: workerId ? workerIdentity(data(verification), workerUser) : null,
      jobAddress: data(privateLocation).address || job.location || '',
      position,
      ...(position ? { positionUpdatedAt: now } : {}),
      pressCount: 1,
      status: 'active',
      createdAt: now,
      updatedAt: now,
    });
    return res.status(201).json({ id: alertRef.id, status: 'active' });
  } catch (error) {
    console.error('Raise SOS error:', error);
    return res.status(500).json({ message: 'Failed to send the SOS alert.' });
  }
};

const markSafe = async (req, res) => {
  try {
    const alertRef = db.collection('sos_alerts').doc(req.params.id);
    const snapshot = await alertRef.get();
    if (!snapshot.exists || snapshot.data().raisedByUid !== req.user.uid) {
      return res.status(404).json({ message: 'Alert not found.' });
    }
    if (snapshot.data().status === 'resolved') {
      return res.status(200).json({ id: alertRef.id, status: 'resolved' });
    }
    const now = new Date();
    await alertRef.update({ status: 'safe', safeAt: now, updatedAt: now });
    return res.status(200).json({ id: alertRef.id, status: 'safe' });
  } catch (error) {
    console.error('Mark SOS safe error:', error);
    return res.status(500).json({ message: 'Failed to update the alert.' });
  }
};

module.exports = { markSafe, raiseSos };
