const express = require('express');
const { ipKeyGenerator, rateLimit } = require('express-rate-limit');

const authenticateUser = require('../middleware/authMiddleware');
const { markSafe, raiseSos } = require('../controllers/sosController');

// Generous: repeated presses only refresh the location of the same alert.
const limiter = rateLimit({
  windowMs: 5 * 60 * 1000,
  limit: 30,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  keyGenerator: (req) => `${req.user?.uid || 'anonymous'}:${ipKeyGenerator(req.ip)}`,
  handler: (_req, res) => res.status(429).json({
    code: 'RATE_LIMITED',
    message: 'Too many SOS requests. Try again in a few minutes.',
  }),
});

const router = express.Router();

router.post('/', authenticateUser, limiter, raiseSos);
router.post('/:id/safe', authenticateUser, limiter, markSafe);

module.exports = router;
