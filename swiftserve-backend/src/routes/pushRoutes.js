const express = require('express');
const { ipKeyGenerator, rateLimit } = require('express-rate-limit');

const authenticateUser = require('../middleware/authMiddleware');
const { db } = require('../config/firebase');
const { registerDevice } = require('../services/pushService');

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 60,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  keyGenerator: (req) => `${req.user?.uid || 'anonymous'}:${ipKeyGenerator(req.ip)}`,
});

const router = express.Router();

// The app registers or revokes this phone's FCM token for the signed-in user.
router.post('/devices', authenticateUser, limiter, async (req, res, next) => {
  try {
    const result = await registerDevice({ db, uid: req.user.uid, body: req.body });
    return res.status(result.status).json({ message: result.message });
  } catch (error) {
    return next(error);
  }
});

module.exports = router;
