const authenticateUser = require('./authMiddleware');
const { auth, db } = require('../config/firebase');
const { PERMISSIONS, isSuperAdmin, can } = require('../services/adminAccessService');

const requireAdmin = [
  authenticateUser,
  async (req, res, next) => {
    if (req.user?.staff === true) {
      try {
        // Check revocation/disabled state and current database permissions on every request.
        await auth.verifyIdToken(req.headers.authorization.slice(7), true);
        const record = await db.collection('admin_accounts').doc(req.user.uid).get();
        const data = record.data();
        const currentUser = await auth.getUser(req.user.uid);
        if (!record.exists || data.status !== 'active' || !Array.isArray(data.permissions)) {
          return res.status(403).json({ message: 'Administrator access is inactive.' });
        }
        if (currentUser.disabled || currentUser.customClaims?.staff !== true || currentUser.email?.toLowerCase() !== data.email?.toLowerCase()) return res.status(403).json({ message: 'Administrator account synchronization is required.' });
        req.adminAccess = { uid: req.user.uid, name: data.fullName, role: data.role,
          isSuperAdmin: false, fullAccess: false, permissions: data.permissions.filter(key => Object.hasOwn(PERMISSIONS, key)) };
      } catch { return res.status(403).json({ message: 'Administrator access could not be verified.' }); }
    } else if (req.user?.admin === true) {
      // Preserve existing full-access administrators without silently promoting them.
      try {
        await auth.verifyIdToken(req.headers.authorization.slice(7), true);
        const current = await auth.getUser(req.user.uid);
        if (current.disabled || current.customClaims?.admin !== true || current.customClaims?.staff === true) return res.sendStatus(403);
        const trusted = isSuperAdmin({ ...current.customClaims, uid: req.user.uid });
        req.adminAccess = { uid: req.user.uid, isSuperAdmin: trusted,
          fullAccess: true, role: trusted ? 'Super Admin' : 'Administrator', permissions: Object.keys(PERMISSIONS) };
      } catch { return res.status(403).json({ message: 'Administrator access could not be verified.' }); }
    } else {
      return res.status(403).json({ message: 'Administrator access is required.' });
    }
    return next();
  },
];

requireAdmin.permission = (...permissions) => (req, res, next) =>
  permissions.some(permission => can(req.adminAccess, permission)) ? next() : res.status(403).json({ message: 'You do not have permission to access this module.' });
requireAdmin.superAdmin = (req, res, next) => req.adminAccess?.isSuperAdmin === true
  ? next() : res.status(403).json({ message: 'Only the Super Admin can manage administrators.' });

module.exports = requireAdmin;
