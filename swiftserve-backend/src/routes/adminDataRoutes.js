const express = require('express');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { db, auth } = require('../config/firebase');
const requireAdmin = require('../middleware/adminMiddleware');
const { rolesOf } = require('../controllers/userController');
const { PERMISSIONS, can, actorOf, addAudit, auditData } = require('../services/adminAccessService');

const router = express.Router();
router.use(requireAdmin);
router.get('/session', (req, res) => res.json({ access: req.adminAccess, catalog: PERMISSIONS }));
router.use((req, res, next) => {
  const kind = req.path.split('/')[1];
  if (['profile', 'notifications'].includes(kind)) return next();
  const permissions = kind === 'overview' ? ['dashboard.view', 'analytics.view']
    : kind === 'users' ? (req.method === 'GET' ? ['users.view', 'workers.view', 'clients.view'] : ['users.manage', 'workers.manage', 'clients.manage', 'users.edit'])
      : [`${kind}.${req.method === 'GET' ? 'view' : 'manage'}`];
  return requireAdmin.permission(...permissions)(req, res, next);
});
const collections = { users: 'users', bookings: 'service_requests', categories: 'service_categories', reports: 'reports', sos: 'sos_alerts' };
const title = value => String(value || '').replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
const iso = value => value?.toDate ? value.toDate().toISOString() : value || '';
function normalize(kind, document) {
  const data = document.data();
  const base = { ...data, id: document.id, createdAt: iso(data.createdAt), updatedAt: iso(data.updatedAt) };
  if (kind === 'users') return { ...base, name: data.fullName || data.name || data.email || document.id,
    role: title(data.role), roles: rolesOf(data).map(title), location: data.address || '', phone: data.phoneNumber || '',
    status: data.accountStatus === 'suspended' ? 'Suspended' : rolesOf(data).includes('worker') ? title(data.verificationStatus || 'pending') : 'Active',
    dateJoined: iso(data.createdAt).slice(0, 10), joinDate: iso(data.createdAt).slice(0, 10) };
  if (kind === 'bookings') { const schedule = iso(data.schedule); return { ...base,
    serviceTitle: data.title || '', providerName: data.workerName || 'Unassigned', clientName: data.clientName || '',
    date: schedule.slice(0, 10), time: schedule.slice(11, 16), amount: data.budget || 0,
    status: title(data.status), schedule }; }
  if (kind === 'sos') return { ...base, statusKey: data.status || 'active', status: title(data.status || 'active'),
    positionUpdatedAt: iso(data.positionUpdatedAt), safeAt: iso(data.safeAt), handledAt: iso(data.handledAt),
    workerIdentity: data.workerIdentity ? { ...data.workerIdentity, reviewedAt: iso(data.workerIdentity.reviewedAt) } : null };
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
  items.sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
  // Alerts still needing attention come first.
  if (kind === 'sos') items.sort((a, b) => Number(['resolved'].includes(a.statusKey)) - Number(['resolved'].includes(b.statusKey)));
  return items;
}
async function categories() {
  const [items, users, bookings] = await Promise.all([list('categories'), list('users'), list('bookings')]);
  return items.map(item => ({ ...item,
    workerCount: users.filter(user => user.role === 'Worker' && user.category === item.name).length,
    bookingCount: bookings.filter(booking => booking.category === item.name).length }));
}
router.get('/overview', async (req, res, next) => {
  try {
    const [users, bookings, reports, categoryItems, verifications] = await Promise.all([
      list('users'), list('bookings'), list('reports'), categories(), db.collection('worker_verifications').get(),
    ]);
    if (!req.adminAccess.fullAccess) {
      return res.json({ users: users.map(({ role, createdAt }) => ({ role, createdAt })),
        bookings: can(req.adminAccess, 'bookings.view') ? bookings : bookings.map(({ status, createdAt }) => ({ status, createdAt })),
        reports: reports.map(({ status, createdAt }) => ({ status, createdAt })), categories: categoryItems.map(({ name, workerCount, bookingCount }) => ({ name, workerCount, bookingCount })),
        verifications: verifications.docs.map(document => ({ status: document.data().status, createdAt: iso(document.data().submittedAt || document.data().createdAt) })) });
    }
    res.json({ users, bookings, reports, categories: categoryItems,
      verifications: verifications.docs.map(document => ({ id: document.id, status: document.data().status, createdAt: iso(document.data().submittedAt || document.data().createdAt), idSubmitted: Boolean(document.data().governmentIdPath), faceVerified: document.data().faceVerified ?? null })) });
  } catch (error) { next(error); }
});
router.get('/profile', async (req, res, next) => {
  try {
    const [user, document] = await Promise.all([auth.getUser(req.user.uid), db.collection('users').doc(req.user.uid).get()]);
    const data = document.data() || {};
    const names = (req.adminAccess.name || data.fullName || user.displayName || '').split(' ');
    res.json({ item: { firstName: (req.adminAccess.fullAccess ? data.firstName : '') || names[0] || '', lastName: (req.adminAccess.fullAccess ? data.lastName : '') || names.slice(1).join(' '),
      email: user.email || '', phone: data.phoneNumber || '', role: req.adminAccess.role, status: user.disabled ? 'Disabled' : 'Active',
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
    const batch = db.batch();
    batch.set(db.collection('users').doc(req.user.uid), { firstName, lastName, fullName: `${firstName} ${lastName}`.trim(), phoneNumber: phone, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    if (!req.adminAccess.fullAccess) batch.update(db.collection('admin_accounts').doc(req.user.uid), { fullName: `${firstName} ${lastName}`.trim(), version: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() });
    addAudit(batch, actorOf(req), 'admin.profile_updated', req.user.uid, { fields: ['firstName', 'lastName', 'phone'] });
    await batch.commit();
    await auth.updateUser(req.user.uid, { displayName: `${firstName} ${lastName}`.trim() });
    res.json({ success: true });
  } catch (error) { next(error); }
});
router.get('/:kind', async (req, res, next) => {
  try {
    if (!collections[req.params.kind]) return res.sendStatus(404);
    let items = req.params.kind === 'categories' ? await categories() : await list(req.params.kind);
    if (req.params.kind === 'users' && !req.adminAccess.fullAccess) {
      const protectedIds = new Set((await db.collection('admin_accounts').get()).docs.map(document => document.id));
      for (let offset = 0; offset < items.length; offset += 100) {
        const result = await auth.getUsers(items.slice(offset, offset + 100).map(user => ({ uid: user.id })));
        for (const user of result.users) if (user.customClaims?.admin || user.customClaims?.staff) protectedIds.add(user.uid);
      }
      items = items.filter(user => !protectedIds.has(user.id) && user.role !== 'Admin');
    }
    if (req.params.kind === 'users' && !can(req.adminAccess, 'users.view')) {
      items = items.filter(user => (can(req.adminAccess, 'workers.view') && user.roles.includes('Worker')) || (can(req.adminAccess, 'clients.view') && user.roles.includes('Client')));
    }
    res.json({ items });
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
    const reference = db.collection('service_categories').doc();
    const batch = db.batch();
    batch.set(reference, {
      ...data,
      createdAt: now,
      updatedAt: now,
    });
    addAudit(batch, actorOf(req), 'category.created', reference.id, { name: data.name });
    await batch.commit();
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
      if (!Object.hasOwn(req.body, 'fullName') && !['Suspended', 'Approved'].includes(req.body.status)) return res.status(400).json({ message: 'Use Worker Verification to approve or reject verification.' });
      const user = await auth.getUser(id);
      if (user.customClaims?.admin || user.customClaims?.staff) return res.status(400).json({ message: 'Administrator accounts cannot be managed here.' });
      if (Object.hasOwn(req.body, 'fullName')) {
        if (!can(req.adminAccess, 'users.edit')) return res.sendStatus(403);
        if (Object.keys(req.body).some(key => key !== 'fullName') || typeof req.body.fullName !== 'string' || !req.body.fullName.trim() || req.body.fullName.length > 120) return res.status(400).json({ message: 'Only a valid full name may be edited here.' });
        update = { fullName: req.body.fullName.trim() };
      } else {
        if (!['Suspended', 'Approved'].includes(req.body.status)) return res.status(400).json({ message: 'Use Worker Verification to approve or reject verification.' });
        const roles = rolesOf(snapshot.data());
        if (!can(req.adminAccess, 'users.manage') && !roles.some(role => can(req.adminAccess, `${role === 'worker' ? 'workers' : 'clients'}.manage`))) return res.sendStatus(403);
        await db.collection('admin_audit_logs').add(auditData(actorOf(req), 'user.status_requested', id, { status: req.body.status }));
        await auth.updateUser(id, { disabled: req.body.status === 'Suspended' });
        if (req.body.status === 'Suspended') await auth.revokeRefreshTokens(id);
        update = { accountStatus: req.body.status === 'Suspended' ? 'suspended' : 'active' };
      }
    } else if (kind === 'bookings') {
      if (req.body.status !== 'Cancelled') return res.status(400).json({ message: 'Only cancellation is supported.' });
      await db.runTransaction(async transaction => {
        const current = await transaction.get(reference);
        if (!['pending', 'accepted', 'ongoing'].includes(current.data()?.status)) { const error = new Error('This booking can no longer be cancelled.'); error.status = 409; throw error; }
        if (current.data().status !== 'pending' && req.body.override !== true) { const error = new Error('Accepted or ongoing bookings require an admin override.'); error.status = 409; throw error; }
        transaction.update(reference, { status: 'cancelled', cancelledBy: req.user.uid, updatedAt: FieldValue.serverTimestamp() });
        addAudit(transaction, actorOf(req), 'booking.cancelled', id, { override: req.body.override === true });
      });
    } else if (kind === 'sos') {
      if (!['acknowledged', 'resolved'].includes(req.body.status) || (req.body.adminNotes !== undefined && (typeof req.body.adminNotes !== 'string' || req.body.adminNotes.length > 5000))) return res.status(400).json({ message: 'Invalid SOS alert fields.' });
      update = { status: req.body.status, ...(req.body.adminNotes !== undefined ? { adminNotes: req.body.adminNotes } : {}), handledBy: req.user.email || req.user.uid, handledAt: FieldValue.serverTimestamp() };
    } else if (kind === 'reports') {
      if (!['Pending', 'Under Review', 'Resolved', 'Dismissed'].includes(req.body.status) || !['adminNotes', 'resolution'].every(field => typeof req.body[field] === 'string' && req.body[field].length <= 5000)) return res.status(400).json({ message: 'Invalid report fields.' });
      if (req.body.adminAction && req.body.adminAction !== 'No Action') return res.status(400).json({ message: 'Manage account restrictions through User Management.' });
      update = { status: req.body.status.toLowerCase().replace(/ /g, '_'), adminNotes: req.body.adminNotes, resolution: req.body.resolution, adminAction: 'No Action', reviewedBy: req.user.uid };
    } else {
      update = categoryFields({ ...snapshot.data(), status: title(snapshot.data().status), ...req.body });
      if (!update) return res.status(400).json({ message: 'Invalid category fields.' });
    }
    if (update) {
      const batch = db.batch();
      batch.update(reference, { ...update, updatedAt: FieldValue.serverTimestamp() });
      if (kind === 'users' && update.fullName) {
        for (const name of ['public_profiles', 'worker_profiles']) {
          const projection = db.collection(name).doc(id);
          if ((await projection.get()).exists) batch.update(projection, { fullName: update.fullName, updatedAt: FieldValue.serverTimestamp() });
        }
      }
      addAudit(batch, actorOf(req), `${kind}.updated`, id, { fields: Object.keys(update), status: update.status || update.accountStatus || '' });
      await batch.commit();
    }
    res.json({ item: normalize(kind, await reference.get()) });
  } catch (error) { if (error.status) return res.status(error.status).json({ message: error.message }); next(error); }
});
router.delete('/categories/:id', async (req, res, next) => {
  try {
    const item = (await categories()).find(category => category.id === req.params.id);
    if (!item) return res.sendStatus(404);
    if (item.workerCount || item.bookingCount) return res.status(409).json({ message: 'Category is in use. Deactivate it instead.' });
    const batch = db.batch();
    batch.delete(db.collection('service_categories').doc(item.id));
    addAudit(batch, actorOf(req), 'category.deleted', item.id, {});
    await batch.commit();
    res.json({ success: true });
  } catch (error) { next(error); }
});
module.exports = router;
