const authenticateUser = require('./authMiddleware');

const requireAdmin = [
  authenticateUser,
  (req, res, next) => {
    if (req.user?.admin !== true) {
      return res.status(403).json({
        message: 'Administrator access is required.',
      });
    }
    return next();
  },
];

module.exports = requireAdmin;
