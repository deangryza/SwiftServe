const crypto = require('node:crypto');
const { auth, db } = require('../config/firebase');

// Signup advisory only: Auth uniqueness and transactional phone claims remain
// authoritative. Never return account IDs, provider information or profile data.
async function checkRegistrationAvailability(req, res) {
  res.set('Cache-Control', 'no-store');
  const { kind, value } = req.body || {};
  if (!['email', 'phone'].includes(kind) || typeof value !== 'string'
    || Object.keys(req.body).some(key => !['kind', 'value'].includes(key))) {
    return res.status(400).json({ message: 'Enter one valid email address or phone number.' });
  }
  const normalized = kind === 'email' ? value.trim().toLowerCase() : value.trim();
  if (kind === 'email'
    ? normalized.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)
    : !/^\+[1-9]\d{7,14}$/.test(normalized)) {
    return res.status(400).json({ message: 'Enter a valid email address or international phone number.' });
  }
  const ownUid = req.user?.uid;
  try {
    let authUser;
    try {
      authUser = kind === 'email'
        ? await auth.getUserByEmail(normalized)
        : await auth.getUserByPhoneNumber(normalized);
    } catch (error) {
      if (error.code !== 'auth/user-not-found') throw error;
    }
    if (authUser && authUser.uid !== ownUid) return res.json({ available: false });
    if (kind === 'phone') {
      const hash = crypto.createHash('sha256').update(normalized).digest('hex');
      const claim = await db.collection('phone_number_claims').doc(hash).get();
      if (claim.exists && (!ownUid || claim.data().uid !== ownUid)) return res.json({ available: false });
      // Legacy profiles may predate phone_number_claims.
      const existing = await db.collection('users').where('phoneNumber', '==', normalized).limit(2).get();
      if (existing.docs.some(document => document.id !== ownUid)) return res.json({ available: false });
    }
    return res.json({ available: true });
  } catch (_) {
    // Do not log submitted contact information, auth tokens or SDK error data.
    return res.status(503).json({ message: 'Availability could not be checked. Please try again.' });
  }
}

module.exports = { checkRegistrationAvailability };
