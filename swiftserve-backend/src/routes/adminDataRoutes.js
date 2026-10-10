const express = require('express');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { db, auth } = require('../config/firebase');
const requireAdmin = require('../middleware/adminMiddleware');

const router = express.Router();
router.use(requireAdmin);
const collections = { users: 'users', bookings: 'service_requests', categories: 'service_categories', reports: 'reports' };
const title = value => String(value || '').replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
const iso = value => value?.toDate ? value.toDate().toISOString() : value || '';
function normalize(kind, document) {
  const data = document.data();
  const base = { ...data, id: document.id, createdAt: iso(data.createdAt), updatedAt: iso(data.updatedAt) };
  if (kind === 'users') return { ...base, name: data.fullName || data.name || data.email || document.id,
    role: title(data.role), location: data.address || '', phone: data.phoneNumber || '',
    status: data.accountStatus === 'suspended' ? 'Suspended' : data.role === 'worker' ? title(data.verificationStatus || 'pending') : 'Active',
    dateJoined: iso(data.createdAt).slice(0, 10), joinDate: iso(data.createdAt).slice(0, 10) };
  if (kind === 'bookings') { const schedule = iso(data.schedule); return { ...base,
    serviceTitle: data.title || '', providerName: data.workerName || 'Unassigned', clientName: data.clientName || '',
    date: schedule.slice(0, 10), time: schedule.slice(11, 16), amount: data.budget || 0,
    status: title(data.status), schedule }; }
  if (kind === 'categories') return { ...base, status: title(data.status || 'active'), dateCreated: iso(data.createdAt).slice(0, 10) };
  return { ...base, status: title(data.status || 'pending'), date: iso(data.createdAt).slice(0, 10),
    reporter: data.reporterName || data.reporter || '', reportedUser: data.reportedUserName || data.reportedUser || '' };
}
async function list(kind) {
  const snapshot = await db.collection(collections[kind]).get();
  let items = snapshot.docs.map(document => normalize(kind, document));
  if (kind === 'users') {
    const [bookingSnapshot, verificationSnapshot] = await Promise.all([db.collection('service_requests').get(), db.collection('worker_verifications').get()]);
    const verificationByUser = new Map(verificationSnapshot.docs.map(document => [document.id, document.data()]));
    const bookings = bookingSnapshot.docs.map(document => document.data());
    items = items.map(user => {
      const verification = verificationByUser.get(user.id);
      return { ...user, bookingsMade: bookings.filter(booking => booking.clientId === user.id).length,
        completedJobs: bookings.filter(booking => booking.workerId === user.id && booking.status === 'completed').length,
        idSubmitted: verification ? Boolean(verification.governmentIdPath || verification.governmentIdUrl) : null,
        faceVerified: verification?.faceVerified ?? null };
    });
  }
  if (kind === 'bookings') {
    const userSnapshot = await db.collection('users').get();
    const users = new Map(userSnapshot.docs.map(document => [document.id, document.data()]));
    items = items.map(booking => {
      const client = users.get(booking.clientId) || {};
      const worker = users.get(booking.workerId) || {};
      return { ...booking, clientEmail: client.email || '', clientPhone: client.phoneNumber || '',
        providerName: worker.fullName || booking.providerName, providerEmail: worker.email || '', providerPhone: worker.phoneNumber || '' };
    });
  }
  return items.sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
}
async function categories() {
  const [items, users, bookings] = await Promise.all([list('categories'), list('users'), list('bookings')]);
  return items.map(item => ({ ...item,
    workerCount: users.filter(user => user.role === 'Worker' && user.category === item.name).length,
    bookingCount: bookings.filter(booking => booking.category === item.name).length }));
}
router.get('/overview', async (_req, res, next) => {
  try {
    const [users, bookings, reports, categoryItems, verifications] = await Promise.all([
      list('users'), list('bookings'), list('reports'), categories(), db.collection('worker_verifications').get(),
    ]);
    res.json({ users, bookings, reports, categories: categoryItems,
      verifications: verifications.docs.map(document => ({ id: document.id, status: document.data().status, createdAt: iso(document.data().submittedAt || document.data().createdAt), idSubmitted: Boolean(document.data().governmentIdPath), faceVerified: document.data().faceVerified ?? null })) });
  } catch (error) { next(error); }
});
router.get('/profile', async (req, res, next) => {
  try {
    const [user, document] = await Promise.all([auth.getUser(req.user.uid), db.collection('users').doc(req.user.uid).get()]);
    const data = document.data() || {};
    const names = (data.fullName || user.displayName || '').split(' ');
    res.json({ item: { firstName: data.firstName || names[0] || '', lastName: data.lastName || names.slice(1).join(' '),
      email: user.email || '', phone: data.phoneNumber || '', role: 'Administrator', status: user.disabled ? 'Disabled' : 'Active',
      avatarInitials: (names.map(name => name[0] || '').join('').slice(0, 2) || 'A').toUpperCase(),
      createdAt: user.metadata.creationTime, lastLogin: user.metadata.lastSignInTime } });
  } catch (error) { next(error); }
});
router.get('/notifications', async (req, res, next) => {
  try {
    const snapshot = await db.collection('notifications').where('recipientId', '==', req.user.uid).get();
    res.json({ items: snapshot.docs.map(document => ({ id: document.id, title: document.data().title || 'Update', body: document.data().body || '', read: document.data().read === true, createdAt: iso(document.data().createdAt) })).sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 30) });
  } catch (error) { next(error); }
});
router.patch('/profile', async (req, res, next) => {
  try {
    const { firstName, lastName, phone, email } = req.body;
    const user = await auth.getUser(req.user.uid);
    if (email !== user.email) return res.status(400).json({ message: 'Email changes require Firebase account verification. Keep your current email.' });
    if (![firstName, lastName, phone].every(value => typeof value === 'string' && value.length <= 200)) return res.status(400).json({ message: 'Invalid profile fields.' });
    await db.collection('users').doc(req.user.uid).set({ firstName, lastName, fullName: `${firstName} ${lastName}`.trim(), phoneNumber: phone, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    await auth.updateUser(req.user.uid, { displayName: `${firstName} ${lastName}`.trim() });
    res.json({ success: true });
  } catch (error) { next(error); }
});
router.get('/:kind', async (req, res, next) => {
  try {
    if (!collections[req.params.kind]) return res.sendStatus(404);
    res.json({ items: req.params.kind === 'categories' ? await categories() : await list(req.params.kind) });
  } catch (error) { next(error); }
});
function categoryFields(body) {
  if (typeof body.name !== 'string' || !body.name.trim() || body.name.length > 100 || typeof body.description !== 'string' || body.description.length > 2000 || !['Active', 'Inactive'].includes(body.status)) return null;
  return { name: body.name.trim(), description: body.description, status: body.status.toLowerCase() };
}
router.post('/categories', async (req, res, next) => {
  try {
    const data = categoryFields(req.body);
    if (!data) return res.status(400).json({ message: 'Invalid category fields.' });
    const now = Timestamp.now();
    const reference = await db.collection('service_categories').add({
      ...data,
      createdAt: now,
      updatedAt: now,
    });
    res.status(201).json({ item: { ...normalize('categories', await reference.get()), workerCount: 0, bookingCount: 0 } });
  } catch (error) { next(error); }
});
router.patch('/:kind/:id', async (req, res, next) => {
  try {
    const { kind, id } = req.params;
    if (!collections[kind]) return res.sendStatus(404);
    const reference = db.collection(collections[kind]).doc(id);
    const snapshot = await reference.get();
    if (!snapshot.exists) return res.status(404).json({ message: 'Record not found.' });
    let update;
    if (kind === 'users') {
      if (id === req.user.uid) return res.status(400).json({ message: 'You cannot change your own account status.' });
      if (!['Suspended', 'Approved'].includes(req.body.status)) return res.status(400).json({ message: 'Use Worker Verification to approve or reject verification.' });
      const user = await auth.getUser(id);
      if (user.customClaims?.admin) return res.status(400).json({ message: 'Administrator accounts cannot be managed here.' });
      await auth.updateUser(id, { disabled: req.body.status === 'Suspended' });
      if (req.body.status === 'Suspended') await auth.revokeRefreshTokens(id);
      update = { accountStatus: req.body.status === 'Suspended' ? 'suspended' : 'active' };
    } else if (kind === 'bookings') {
      if (req.body.status !== 'Cancelled') return res.status(400).json({ message: 'Only cancellation is supported.' });
      await db.runTransaction(async transaction => {
        const current = await transaction.get(reference);
        if (!['pending', 'accepted', 'ongoing'].includes(current.data()?.status)) { const error = new Error('This booking can no longer be cancelled.'); error.status = 409; throw error; }
        if (current.data().status !== 'pending' && req.body.override !== true) { const error = new Error('Accepted or ongoing bookings require an admin override.'); error.status = 409; throw error; }
        transaction.update(reference, { status: 'cancelled', cancelledBy: req.user.uid, updatedAt: FieldValue.serverTimestamp() });
      });
    } else if (kind === 'reports') {
      if (!['Pending', 'Under Review', 'Resolved', 'Dismissed'].includes(req.body.status) || !['adminNotes', 'resolution'].every(field => typeof req.body[field] === 'string' && req.body[field].length <= 5000)) return res.status(400).json({ message: 'Invalid report fields.' });
      if (req.body.adminAction && req.body.adminAction !== 'No Action') return res.status(400).json({ message: 'Manage account restrictions through User Management.' });
      update = { status: req.body.status.toLowerCase().replace(/ /g, '_'), adminNotes: req.body.adminNotes, resolution: req.body.resolution, adminAction: 'No Action', reviewedBy: req.user.uid };
    } else {
      update = categoryFields({ ...snapshot.data(), status: title(snapshot.data().status), ...req.body });
      if (!update) return res.status(400).json({ message: 'Invalid category fields.' });
    }
    if (update) await reference.update({ ...update, updatedAt: FieldValue.serverTimestamp() });
    res.json({ item: normalize(kind, await reference.get()) });
  } catch (error) { if (error.status) return res.status(error.status).json({ message: error.message }); next(error); }
});
router.delete('/categories/:id', async (req, res, next) => {
  try {
    const item = (await categories()).find(category => category.id === req.params.id);
    if (!item) return res.sendStatus(404);
    if (item.workerCount || item.bookingCount) return res.status(409).json({ message: 'Category is in use. Deactivate it instead.' });
    await db.collection('service_categories').doc(item.id).delete();
    res.json({ success: true });
  } catch (error) { next(error); }
});
module.exports = router;
