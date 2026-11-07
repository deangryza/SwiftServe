const express = require('express');
const multer = require('multer');
const { rateLimit, ipKeyGenerator } = require('express-rate-limit');
const { IdentityService } = require('../identity/service');
const { fields, fail } = require('../identity/policy');
const { MAX_BYTES } = require('../services/verificationImagePolicy');

function createIdentityRouters({ db, auth, admin, service = new IdentityService({ db }), limiter } = {}) {
  const user = express.Router(), review = express.Router();
  const safe = handler => async (req, res) => {
    try { await handler(req, res); }
    catch (error) {
      // No document contents, names, tokens, biometrics or stack traces in output/logs.
      const known = /^[A-Z_]{3,50}$/.test(error.code || '');
      res.status(known && error.status ? error.status : 503).json({
        code: known ? error.code : 'IDENTITY_UNAVAILABLE',
        message: 'Local mock verification could not finish. Check the status and retry if available.',
      });
    }
  };
  const gate = (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    if (req.headers.origin && !/^http:\/\/(localhost|127\.0\.0\.1):\d+$/.test(req.headers.origin)) return res.status(403).json({ code: 'LOCAL_ORIGIN_REQUIRED' });
    try { service.guard(); next(); } catch { res.status(503).json({ code: 'MOCK_ENVIRONMENT_REQUIRED' }); }
  };
  const authenticate = async (req, res, next) => {
    try {
      if (!req.headers.authorization?.startsWith('Bearer ')) throw fail(401, 'UNAUTHENTICATED');
      req.user = await auth.verifyIdToken(req.headers.authorization.slice(7), true);
      if (!req.user?.uid) throw fail(401, 'UNAUTHENTICATED');
      next();
    } catch { res.status(401).json({ code: 'UNAUTHENTICATED' }); }
  };
  const attempts = limiter || rateLimit({
    windowMs: 15 * 60 * 1000, limit: 15, standardHeaders: 'draft-8', legacyHeaders: false,
    keyGenerator: req => `${req.user.uid}:${ipKeyGenerator(req.ip)}`,
    handler: (_req, res) => res.status(429).json({ code: 'RATE_LIMITED' }),
  });
  user.use(gate, authenticate);
  user.post('/sessions', attempts, safe(async (req, res) => {
    fields(req.body, ['requestId']);
    res.status(201).json(await service.create(req.user.uid, req.body.requestId));
  }));
  user.get('/sessions/:id', safe(async (req, res) => res.json(await service.get(req.user.uid, req.params.id))));
  user.post('/sessions/:id/consent', attempts, safe(async (req, res) => {
    fields(req.body, ['consent', 'consentVersion']);
    if (req.body.consent !== true) throw fail(403, 'CONSENT_REQUIRED');
    res.json(await service.consent(req.user.uid, req.params.id, req.body.consentVersion));
  }));
  const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: MAX_BYTES, files: 2, fields: 1, fieldSize: 64, parts: 3 },
    fileFilter: (_req, file, callback) => callback(
      ['image/jpeg', 'image/png'].includes(file.mimetype) ? null : fail(415, 'INVALID_IMAGE_TYPE'), true,
    ),
  }).fields([{ name: 'document', maxCount: 1 }, { name: 'selfie', maxCount: 1 }]);
  user.post('/sessions/:id/submit', attempts, async (req, res, next) => {
    try {
      await service.eligible(req.user.uid);
      const record = await service.get(req.user.uid, req.params.id);
      if (!record.consentVersion) return res.status(403).json({ code: 'CONSENT_REQUIRED' });
      upload(req, res, error => {
        if (!error) return next();
        for (const files of Object.values(req.files || {})) for (const file of files) file.buffer?.fill(0);
        res.status(error.code === 'LIMIT_FILE_SIZE' ? 413 : 400).json({ code: 'INVALID_UPLOAD' });
      });
    } catch (error) { res.status(error.status || 503).json({ code: error.code || 'IDENTITY_UNAVAILABLE' }); }
  }, safe(async (req, res) => {
    const document = req.files?.document?.[0], selfie = req.files?.selfie?.[0];
    try {
      fields(req.body, ['documentFormat']);
      if (!document || !selfie) throw fail(400, 'IMAGE_PAIR_REQUIRED');
      res.json(await service.submit(req.user.uid, req.params.id, document, selfie, req.body.documentFormat));
    } finally {
      document?.buffer?.fill(0); selfie?.buffer?.fill(0);
    }
  }));
  review.use(gate, admin);
  review.get('/sessions', admin.permission('verification.view'), safe(async (req, res) => {
    fields(req.query, ['after']);
    res.json(await service.list(req.query.after));
  }));
  review.patch('/sessions/:id', admin.permission('verification.manage'), safe(async (req, res) => {
    fields(req.body, ['decision', 'reasonCode']);
    res.json(await service.review(req.params.id, req.user.uid, req.body.decision, req.body.reasonCode));
  }));
  return { user, review };
}
module.exports = { createIdentityRouters };
