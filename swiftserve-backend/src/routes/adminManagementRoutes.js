const express = require('express');
const { FieldValue } = require('firebase-admin/firestore');
const { auth, db } = require('../config/firebase');
const requireAdmin = require('../middleware/adminMiddleware');
const { normalizePermissions, isSuperAdmin, addAudit, actorOf } = require('../services/adminAccessService');
const router = express.Router();
router.use(requireAdmin, requireAdmin.superAdmin);
const invalid = message => Object.assign(new Error(message), { status: 400 });
const time = value => value?.toDate ? value.toDate().toISOString() : value || null;
function fields(body, create) {
  const allowed = create ? ['fullName', 'email', 'password', 'role', 'permissions'] : ['fullName', 'email', 'role', 'permissions', 'status', 'version'];
  if (Object.keys(body).some(key => !allowed.includes(key))) throw invalid('Unsupported administrator field.');
  if (typeof body.fullName !== 'string' || !body.fullName.trim() || body.fullName.length > 120 ||
    typeof body.email !== 'string' || body.email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email) ||
    typeof body.role !== 'string' || !body.role.trim() || body.role.length > 60 || /super[\s_-]*admin/i.test(body.role)) throw invalid('Enter a valid name, email and regular admin role.');
  if (create && (typeof body.password !== 'string' || body.password.length < 12 || body.password.length > 128 ||
    !/[a-z]/.test(body.password) || !/[A-Z]/.test(body.password) || !/\d/.test(body.password) || !/[^\w\s]/.test(body.password))) throw invalid('Use a temporary password with 12–128 characters, uppercase, lowercase, a number and a symbol.');
  if (!create && (!['active', 'inactive', 'suspended'].includes(body.status) || !Number.isInteger(body.version))) throw invalid('Invalid status or version. Refresh the administrator list.');
  return { fullName: body.fullName.trim(), email: body.email.trim().toLowerCase(), role: body.role.trim(),
    permissions: normalizePermissions(body.permissions) };
}
function item(user, record) {
  const claims = { ...user.customClaims, uid: user.uid };
  const superAdmin = isSuperAdmin(claims);
  return { id: user.uid, fullName: record?.fullName || user.displayName || '', email: user.email || '',
    role: superAdmin ? 'Super Admin' : record?.role || 'Legacy administrator', isSuperAdmin: superAdmin,
    managed: user.customClaims?.staff === true && Boolean(record), permissions: record?.permissions || [],
    status: record?.status || (user.disabled ? 'inactive' : 'active'), authDisabled: user.disabled,
    createdAt: time(record?.createdAt) || user.metadata.creationTime, lastLogin: user.metadata.lastSignInTime || null,
    version: record?.version ?? 0, syncRequired: record?.syncRequired === true };
}
router.get('/', async (_req, res, next) => {
  try {
    const records = await db.collection('admin_accounts').get();
    const byId = new Map(records.docs.map(doc => [doc.id, doc.data()]));
    const items = [];
    let pageToken;
    do {
      const page = await auth.listUsers(1000, pageToken);
      for (const user of page.users) if (user.customClaims?.admin === true || user.customClaims?.staff === true || byId.has(user.uid)) items.push(item(user, byId.get(user.uid)));
      pageToken = page.pageToken;
    } while (pageToken);
    res.json({ items });
  } catch (error) { next(error); }
});
router.get('/audit', async (req, res, next) => {
  try {
    let query = db.collection('admin_audit_logs');
    if (req.query.actorId) {
      if (typeof req.query.actorId !== 'string' || req.query.actorId.length > 128 || req.query.actorId.includes('/')) throw invalid('Invalid activity filter.');
      query = query.where('actorId', '==', req.query.actorId);
    }
    const snapshot = await query.orderBy('createdAt', 'desc').limit(100).get();
    res.json({ items: snapshot.docs.map(doc => ({ id: doc.id, ...doc.data(), createdAt: time(doc.data().createdAt) })) });
  } catch (error) { next(error); }
});
router.post('/', async (req, res, next) => {
  let created;
  try {
    const data = fields(req.body, true);
    created = await auth.createUser({ email: data.email, displayName: data.fullName, password: req.body.password, disabled: true });
    const reference = db.collection('admin_accounts').doc(created.uid);
    const batch = db.batch();
    batch.set(reference, { ...data, status: 'provisioning', version: 0, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(), createdBy: req.user.uid });
    addAudit(batch, actorOf(req), 'admin.created', created.uid, { ...data, status: 'provisioning' });
    await batch.commit();
    // Never set admin:true: that is the legacy full-access authority.
    await auth.setCustomUserClaims(created.uid, { staff: true });
    await auth.updateUser(created.uid, { disabled: false });
    await db.runTransaction(async transaction => {
      const snapshot = await transaction.get(reference);
      if (snapshot.data()?.status !== 'provisioning' || snapshot.data()?.version !== 0) throw Object.assign(new Error('Administrator setup changed. Refresh the directory.'), { status: 409 });
      transaction.update(reference, { status: 'active', updatedAt: FieldValue.serverTimestamp() });
      addAudit(transaction, actorOf(req), 'admin.activated', created.uid, { status: 'active' });
    });
    res.status(201).json({ item: item(await auth.getUser(created.uid), (await reference.get()).data()) });
  } catch (error) {
    if (created) {
      // Retain a recoverable provisioning record; never delete an existing account.
      await auth.updateUser(created.uid, { disabled: true }).catch(() => {});
    }
    if (error.code === 'auth/email-already-exists') return res.status(409).json({ message: 'This email already belongs to an account. Existing users are never promoted here.' });
    if (error.status) return res.status(error.status).json({ message: error.message });
    next(error);
  }
});
router.post('/:id/complete-setup', async (req, res, next) => {
  try {
    const reference = db.collection('admin_accounts').doc(req.params.id);
    const snapshot = await reference.get();
    const data = snapshot.data();
    const user = await auth.getUser(req.params.id);
    if (!snapshot.exists || data.status !== 'provisioning' || !data.createdBy || user.email !== data.email || user.customClaims?.admin === true) throw invalid('Only an incomplete managed-admin setup can be retried.');
    normalizePermissions(data.permissions);
    await auth.setCustomUserClaims(user.uid, { staff: true });
    await auth.updateUser(user.uid, { disabled: false });
    await db.runTransaction(async transaction => {
      const current = await transaction.get(reference);
      if (current.data()?.status !== 'provisioning' || current.data()?.version !== data.version) throw Object.assign(new Error('Administrator setup changed. Refresh the directory.'), { status: 409 });
      transaction.update(reference, { status: 'active', version: data.version + 1, updatedAt: FieldValue.serverTimestamp() });
      addAudit(transaction, actorOf(req), 'admin.setup_recovered', user.uid, { status: 'active' });
    });
    res.json({ success: true });
  } catch (error) {
    // A provisioning record remains unauthorized even if Auth was enabled.
    if (error.status) return res.status(error.status).json({ message: error.message });
    next(error);
  }
});
router.patch('/:id', async (req, res, next) => {
  let locked;
  let committed = false;
  try {
    const { id } = req.params;
    if (id === req.user.uid) throw invalid('You cannot change your own administrative access.');
    const data = fields(req.body, false);
    const user = await auth.getUser(id);
    if (user.customClaims?.admin === true || isSuperAdmin({ ...user.customClaims, uid: id }) || user.customClaims?.staff !== true) throw invalid('Super Admin and legacy accounts are protected. Only managed regular administrators can be edited.');
    const reference = db.collection('admin_accounts').doc(id);
    // Inactive during cross-service synchronization. Concurrent editors cannot restore stale permissions.
    locked = await db.runTransaction(async transaction => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) throw invalid('Administrator record not found.');
      const prior = snapshot.data();
      if (prior.syncRequired && prior.status === 'updating' && (!Number.isFinite(prior.syncStartedAt) || Date.now() - prior.syncStartedAt < 300000)) throw Object.assign(new Error('An administrator update is in progress. Retry after it finishes.'), { status: 409 });
      if (prior.version !== req.body.version) throw Object.assign(new Error('This administrator changed. Refresh before saving.'), { status: 409 });
      const version = prior.version + 1;
      transaction.update(reference, { ...data, status: 'updating', syncRequired: true, syncStartedAt: Date.now(), version, updatedAt: FieldValue.serverTimestamp() });
      addAudit(transaction, actorOf(req), 'admin.updated', id, { before: { role: prior.role, permissions: prior.permissions, status: prior.status }, after: { ...data, status: req.body.status } });
      return { reference, version };
    });
    await auth.updateUser(id, { email: data.email, displayName: data.fullName, disabled: req.body.status !== 'active' });
    if (req.body.status !== 'active') await auth.revokeRefreshTokens(id);
    await db.runTransaction(async transaction => {
      const current = await transaction.get(locked.reference);
      if (current.data()?.version !== locked.version || current.data()?.status !== 'updating') throw new Error('Administrator synchronization ownership lost.');
      transaction.update(locked.reference, { status: req.body.status, syncRequired: false, updatedAt: FieldValue.serverTimestamp() });
      addAudit(transaction, actorOf(req), 'admin.status_changed', id, { status: req.body.status });
    });
    committed = true;
    res.json({ item: item(await auth.getUser(id), (await locked.reference.get()).data()) });
  } catch (error) {
    if (committed) return res.status(503).json({ message: 'The administrator update was applied, but its confirmation could not be loaded. Refresh the list before retrying.' });
    if (locked) {
      // Fail closed, but leave a retryable state (never leave a permanent 'updating' lock).
      await db.runTransaction(async transaction => {
        const snapshot = await transaction.get(locked.reference);
        if (snapshot.data()?.version === locked.version && snapshot.data()?.status === 'updating') {
          transaction.update(locked.reference, { status: 'inactive', syncRequired: true });
          addAudit(transaction, actorOf(req), 'admin.sync_failed', req.params.id, { status: 'inactive' });
        }
      }).catch(() => {});
      return res.status(503).json({ message: 'The account is blocked pending synchronization. Refresh and retry this administrator update.' });
    }
    if (error.status) return res.status(error.status).json({ message: error.message });
    next(error);
  }
});
module.exports = router;
