const express = require('express');
const { ipKeyGenerator, rateLimit } = require('express-rate-limit');

const { db } = require('../config/firebase');
const { OtpError, sendOtp, verifyOtp } = require('../services/otpService');

// Per-IP limit on top of the per-number limits in otpService.
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  keyGenerator: (req) => ipKeyGenerator(req.ip),
  handler: (_req, res) => res.status(429).json({
    code: 'OTP_COOLDOWN',
    message: 'Too many verification requests. Try again later.',
  }),
});

const handle = (work) => async (req, res, next) => {
  res.set('Cache-Control', 'no-store');
  try {
    return res.json(await work(req));
  } catch (error) {
    if (error instanceof OtpError) {
      return res.status(error.status).json({ code: error.code, message: error.message, ...error.extra });
    }
    return next(error);
  }
};

const router = express.Router();

// No sign-in: email sign-ups verify their phone before the account exists.
router.post('/send', limiter, handle((req) => sendOtp({
  db, phone: String(req.body?.phoneNumber || '').trim(),
})));

router.post('/verify', limiter, handle((req) => verifyOtp({
  db, phone: String(req.body?.phoneNumber || '').trim(), code: String(req.body?.code || '').trim(),
})));

module.exports = router;
