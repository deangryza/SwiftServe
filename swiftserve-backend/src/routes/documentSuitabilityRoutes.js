const express = require('express');
const multer = require('multer');
const { db, auth } = require('../config/firebase');
const admin = require('../middleware/adminMiddleware');
const { addAudit, actorOf } = require('../services/adminAccessService');
const { createDocumentService, publicDocument, documentEnvironment, liveDocument } = require('../services/documentSuitabilityService');
const { sendLocalFile } = require('../services/verificationStorageService');
const { rateLimit } = require('express-rate-limit');
const service = createDocumentService({ db, audit: addAudit });
const safe = fn => async (req, res) => { try { await fn(req, res); } catch (e) {
  res.status(e.status || 500).json({ code: e.status ? e.code : 'DOCUMENT_PROCESSING_ERROR', message: e.status === 422 ? 'Document unreadable. Please upload a clear JPEG/PNG document image.' : 'Document review could not be completed. Refresh its status and try again.' });
} };
const user = express.Router(), review = express.Router();
const localOnly = (_req,res,next) => { try { documentEnvironment(db); next(); } catch { res.status(503).json({code:'DOCUMENT_DEMO_ENVIRONMENT_REQUIRED',message:'Document review is available only in the isolated demo emulator pilot.'}); } };
user.use(localOnly); review.use(localOnly);
user.use(async (req, res, next) => { try {
  const token = req.headers.authorization?.match(/^Bearer (.+)$/)?.[1];
  if (!token) return res.sendStatus(401);
  req.user = await auth.verifyIdToken(token, true);
  if ((await auth.getUser(req.user.uid)).disabled) return res.sendStatus(401);
  next();
} catch { res.sendStatus(401); } });
user.use(rateLimit({ windowMs: 15 * 60 * 1000, limit: 30, standardHeaders: 'draft-7', legacyHeaders: false }));
user.get('/', safe(async (req, res) => { res.set('Cache-Control', 'no-store'); res.json({ item: await service.get(req.user.uid) }); }));
const image = uid => safe(async (req, res) => {
  res.set('Cache-Control', 'private, no-store'); res.set('X-Content-Type-Options', 'nosniff');
  const record = (await service.refFor(uid(req)).get()).data();
  if (!record?.imagePath || !liveDocument(record)) return res.sendStatus(404);
  if (req.query.attemptId !== record.attemptId) return res.status(409).json({ code: 'DOCUMENT_ATTEMPT_STALE' });
  if (!await sendLocalFile(res, record.imagePath, { contentType: record.contentType })) res.sendStatus(404);
});
user.get('/image', safe(async (req, res) => { await service.account(req.user.uid); return image(r => r.user.uid)(req, res); }));
const upload = multer({ storage: multer.memoryStorage(), limits: { files: 1, fileSize: 5 * 1024 * 1024, fields: 3, fieldSize: 128 },
  fileFilter: (_req, file, cb) => cb(null, ['image/jpeg','image/png'].includes(file.mimetype)) }).single('document');
user.post('/', (req, res, next) => upload(req, res, error => error ? res.status(400).json({ code: 'INVALID_DOCUMENT_UPLOAD' }) : next()), safe(async (req, res) => {
  try {
    if (Object.keys(req.body || {}).some(k => !['idType','sessionId','attemptId'].includes(k))) return res.status(400).json({ code: 'INVALID_DOCUMENT_FIELDS' });
    res.status(201).json({ item: await service.submit(req.user.uid, req.body, req.file) });
  } finally { req.file?.buffer?.fill(0); }
}));
review.use(admin);
review.get('/', admin.permission('verification.view'), safe(async (_req, res) => {
  res.set('Cache-Control','no-store');
  let query = db.collection('document_suitability').orderBy('submittedAt', 'desc').orderBy(require('firebase-admin/firestore').FieldPath.documentId(), 'desc');
  if (_req.query.after) {
    let cursor;
    try { if (typeof _req.query.after !== 'string' || _req.query.after.length > 1024) throw Error(); cursor=JSON.parse(Buffer.from(_req.query.after,'base64url').toString()); }
    catch { return res.status(400).json({code:'INVALID_DOCUMENT_CURSOR'}); }
    if (!Array.isArray(cursor) || cursor.length!==2 || !Number.isFinite(cursor[0]) || cursor[0]<0 || typeof cursor[1]!=='string' || cursor[1].length>128 || !cursor[1]) return res.status(400).json({code:'INVALID_DOCUMENT_CURSOR'});
    query=query.startAfter(new Date(cursor[0]),cursor[1]);
  }
  const snapshot = await query.limit(100).get();
  const last=snapshot.docs.at(-1), data=last?.data();
  const time=data?.submittedAt?.toMillis ? data.submittedAt.toMillis() : data?.submittedAt?.getTime();
  const next=snapshot.docs.length===100 && Number.isFinite(time) ? Buffer.from(JSON.stringify([time,last.id])).toString('base64url') : null;
  res.json({ items: snapshot.docs.map(doc => publicDocument(doc.data())), next });
}));
review.get('/:uid/image', admin.permission('verification.view'), image(r => r.params.uid));
review.patch('/:uid', admin.permission('verification.manage'), safe(async (req, res) => {
  if (Object.keys(req.body || {}).some(k => !['sessionId','attemptId','status','reasonCode'].includes(k))) return res.status(400).json({ code: 'INVALID_DOCUMENT_FIELDS' });
  res.json({ item: await service.review(req.params.uid, actorOf(req), req.body) });
}));
module.exports = { user, review };
