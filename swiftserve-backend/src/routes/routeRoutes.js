const express = require('express');
const { rateLimit } = require('express-rate-limit');

const authenticateUser = require('../middleware/authMiddleware');
const { getRoadRoute } = require('../services/routingService');

const MAX_DISTANCE_KM = 200;

const limiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 30,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  keyGenerator: (req) => req.user.uid,
  handler: (_req, res) => res.status(429).json({
    code: 'RATE_LIMITED',
    message: 'Too many route requests. Try again later.',
  }),
});

const parsePoint = (value) => {
  const lat = value?.lat;
  const lng = value?.lng;
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return { lat, lng };
};

const haversineKm = (a, b) => {
  const toRad = (deg) => (deg * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2
    + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(h));
};

const router = express.Router();

router.post('/errand', authenticateUser, limiter, async (req, res, next) => {
  const from = parsePoint(req.body?.from);
  const to = parsePoint(req.body?.to);
  if (!from || !to) {
    return res.status(400).json({
      code: 'INVALID_COORDINATES',
      message: 'from and to must each have numeric lat and lng within range.',
    });
  }
  if (haversineKm(from, to) > MAX_DISTANCE_KM) {
    return res.status(400).json({
      code: 'ROUTE_TOO_LONG',
      message: `Pickup and drop-off must be within ${MAX_DISTANCE_KM} km of each other.`,
    });
  }

  try {
    return res.json(await getRoadRoute({ from, to }));
  } catch (error) {
    if (error.code === 'ROUTING_NOT_CONFIGURED') {
      return res.status(503).json({ code: error.code, message: error.message });
    }
    if (error.code === 'ROUTING_UNAVAILABLE') {
      return res.status(502).json({ code: error.code, message: error.message });
    }
    return next(error);
  }
});

module.exports = router;
