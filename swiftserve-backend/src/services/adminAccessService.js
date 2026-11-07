const { FieldValue } = require('firebase-admin/firestore');
const { db } = require('../config/firebase');

const PERMISSIONS = Object.freeze({
  'dashboard.view': 'Dashboard statistics', 'analytics.view': 'Platform analytics',
  'users.view': 'View all users', 'users.edit': 'Edit user names', 'users.manage': 'Suspend / restore users',
  'workers.view': 'View workers', 'workers.manage': 'Manage worker account status',
  'clients.view': 'View clients', 'clients.manage': 'Manage client account status',
  'verification.view': 'View worker verification', 'verification.manage': 'Review worker verification',
  'reports.view': 'View reports', 'reports.manage': 'Manage reports',
  'bookings.view': 'View bookings', 'bookings.manage': 'Manage bookings',
  'categories.view': 'View service categories', 'categories.manage': 'Manage service categories',
  'sos.view': 'View SOS alerts', 'sos.manage': 'Manage SOS alerts',
});
function isSuperAdmin(claims, env = process.env) {
  return claims?.admin === true && claims?.staff !== true && (claims.superAdmin === true ||
    String(env.SWIFTSERVE_SUPER_ADMIN_UIDS || '').split(',').map(value => value.trim()).filter(Boolean).includes(claims.uid));
}
function normalizePermissions(values) {
  if (!Array.isArray(values) || values.length > Object.keys(PERMISSIONS).length ||
    values.some(value => typeof value !== 'string' || !Object.hasOwn(PERMISSIONS, value))) {
    const error = new Error('Select valid administrator permissions.'); error.status = 400; throw error;
  }
  const selected = new Set(values);
  for (const value of values) {
    if (value.endsWith('.manage') || value.endsWith('.edit')) selected.add(value.split('.')[0] + '.view');
  }
  return [...selected].sort();
}
const can = (context, permission) => context?.fullAccess === true || context?.permissions?.includes(permission) === true;
const auditData = (actor, action, targetId, details = {}) => ({
  actorId: actor.uid, actorName: actor.name || actor.email || actor.uid,
  action, targetId, details, createdAt: FieldValue.serverTimestamp(),
});
// All administrative mutations use this with their Firestore batch/transaction.
function addAudit(writer, actor, action, targetId, details) {
  writer.set(db.collection('admin_audit_logs').doc(), auditData(actor, action, targetId, details));
}
function actorOf(req) { return { uid: req.user.uid, email: req.user.email || '', name: req.adminAccess?.name || req.user.name || '' }; }
module.exports = { PERMISSIONS, isSuperAdmin, normalizePermissions, can, auditData, addAudit, actorOf };
