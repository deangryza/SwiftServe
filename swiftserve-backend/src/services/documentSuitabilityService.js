const { randomUUID, createHash } = require('node:crypto');
const { loadImage } = require('canvas');
const { saveLocalBuffer, removeLocalPaths, isLocalStorage } = require('./verificationStorageService');
const STATES = Object.freeze(['DOCUMENT_PENDING', 'DOCUMENT_REVIEW_REQUIRED', 'DOCUMENT_ACCEPTED', 'DOCUMENT_REJECTED', 'DOCUMENT_UNREADABLE']);
const TYPES = Object.freeze(['National ID', "Driver's License", 'Passport', 'UMID', 'Postal ID', "Voter's ID"]);
const REASONS = Object.freeze({ SUITABLE: 'Document accepted for further verification. This is not government authentication.',
  NOT_SUPPORTED: 'Please upload a clear image of the declared supported ID. Selfies and unrelated photos are not accepted.',
  INCOMPLETE: 'Document areas are cropped. Capture the entire document.', UNREADABLE: 'The document is unreadable. Upload a clearer image.' });
const fail = (code, status = 409) => Object.assign(new Error(code), { code, status });
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const mockDocument = record => record?.mock === true || record?.providerType === 'MOCK' || record?.checkSource === 'SYNTHETIC_FIXTURE';
const dateText = value => value?.toDate ? value.toDate().toISOString() : value instanceof Date ? value.toISOString() : null;
function documentEnvironment(db) {
  if (require('./workerVerificationPolicy').adminReviewMode()) return;
  const loopback = value => /^(127\.0\.0\.1|localhost):\d+$/.test(value || '');
  if (!/^demo-[a-z0-9-]+$/.test(db.projectId || '') || db.databaseId !== '(default)'
    || process.env.GCLOUD_PROJECT !== db.projectId || !loopback(process.env.FIRESTORE_EMULATOR_HOST)
    || !loopback(process.env.FIREBASE_AUTH_EMULATOR_HOST) || ['GOOGLE_APPLICATION_CREDENTIALS','K_SERVICE','NETLIFY','RENDER'].some(k => process.env[k])) {
    throw fail('DOCUMENT_DEMO_ENVIRONMENT_REQUIRED', 503);
  }
}
const live = record => record && record.expiresAt?.toDate ? record.expiresAt.toDate() > new Date() : record?.expiresAt instanceof Date && record.expiresAt > new Date();
function bound(record, uid, sessionId, attemptId, allowExpired = false) {
  if (!record || record.ownerId !== uid || record.sessionId !== sessionId || record.attemptId !== attemptId) throw fail('DOCUMENT_ATTEMPT_STALE');
  if (!allowExpired && !live(record)) throw fail('DOCUMENT_SESSION_EXPIRED');
}
async function acceptedDocument(db, uid, sessionId, attemptId, bytes, tx) {
  documentEnvironment(db);
  const ref = db.collection('document_suitability').doc(uid);
  const record = (await (tx ? tx.get(ref) : ref.get())).data();
  bound(record, uid, sessionId, attemptId);
  if (record.status !== 'DOCUMENT_ACCEPTED' || mockDocument(record)) throw fail('DOCUMENT_REVIEW_REQUIRED');
  const hash = typeof bytes === 'string' ? bytes : digest(bytes);
  if (record.sha256 !== hash) throw fail('DOCUMENT_IMAGE_CHANGED');
  return { sessionId, attemptId, sha256: hash, declaredType: record.declaredType };
}
function publicDocument(record) {
  if (!record) return { status: 'DOCUMENT_PENDING' };
  return { ownerId: record.ownerId, sessionId: record.sessionId, attemptId: record.attemptId,
    status: live(record) ? record.status : 'DOCUMENT_UNREADABLE', declaredType: record.declaredType,
    submittedAt: dateText(record.submittedAt), expiresAt: dateText(record.expiresAt), imageDigest: record.sha256, mock: mockDocument(record),
    reason: live(record) ? REASONS[record.reasonCode] || '' : 'Document review expired. Please upload a replacement.',
    history: (record.history || []).map(item => ({ ...item, reviewedAt: dateText(item.reviewedAt) })) };
}
// Friendly retake guidance when the automatic ID check cannot use the photo.
const FACE_GUIDANCE = Object.freeze({
  FACE_NOT_DETECTED: 'We could not find the photo on your ID. Lay the card flat, fill the frame with it, avoid glare and try again.',
  MULTIPLE_FACES_DETECTED: 'More than one face was found. Photograph only the ID card, with nothing else in the frame.',
});
const defaultFaceCheck = buffer => require('./faceVerificationService').getFaceDescriptor(buffer, 'document');
function createDocumentService({ db, uploadsDir, audit, checkFace = defaultFaceCheck }) {
  const refFor = uid => db.collection('document_suitability').doc(uid);
  function active(user) {
    if (!user || !['client', 'worker'].includes(user.role) || [user.status, user.accountStatus].some(v => ['suspended','disabled','inactive'].includes(v))) throw fail('DOCUMENT_ACCOUNT_REQUIRED', 403);
  }
  async function account(uid) {
    documentEnvironment(db);
    if (process.env.NATIONAL_ID_MOCK_ENABLED === 'true') throw fail('USE_MOCK_IDENTITY_SESSION', 503);
    const user = (await db.collection('users').doc(uid).get()).data();
    active(user);
    return user;
  }
  return {
    account,
    async get(uid) { await account(uid); return publicDocument((await refFor(uid).get()).data()); },
    async submit(uid, fields, file) {
      await account(uid);
      if (!isLocalStorage() || process.env.SWIFTSERVE_NETLIFY_PILOT === 'true') throw fail('DOCUMENT_LOCAL_STORAGE_REQUIRED', 503);
      if (!TYPES.includes(fields.idType) || !file) throw fail('INVALID_DOCUMENT_UPLOAD', 400);
      if (!Buffer.isBuffer(file.buffer) || !file.buffer.length || file.buffer.length > (fields.idType === 'National ID' ? 20 : 5) * 1024 * 1024) throw fail('INVALID_DOCUMENT_UPLOAD', 400);
      const png = file.mimetype === 'image/png' && file.buffer.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]));
      const jpeg = file.mimetype === 'image/jpeg' && file.buffer[0] === 255 && file.buffer[1] === 216 && file.buffer[2] === 255;
      if (!png && !jpeg) throw fail('INVALID_DOCUMENT_UPLOAD', 415);
      let decoded;
      try { decoded = await loadImage(file.buffer); } catch { throw fail('DOCUMENT_UNREADABLE', 422); }
      if (!decoded.width || !decoded.height || decoded.width * decoded.height > 16000000) throw fail('DOCUMENT_UNREADABLE', 422);
      // Admin-review mode checks the ID straight away instead of queueing it for
      // a person: the same face detection the later match uses must succeed.
      const autoChecked = require('./workerVerificationPolicy').adminReviewMode();
      if (autoChecked) {
        try { await checkFace(file.buffer); } catch (error) {
          if (!['FACE_NOT_DETECTED', 'MULTIPLE_FACES_DETECTED', 'IMAGE_QUALITY'].includes(error?.code)) throw error;
          throw Object.assign(fail(error.code, 422), { reason: error.reason, image: 'document',
            publicMessage: FACE_GUIDANCE[error.code] || `${error.message} Then photograph your ID again.` });
        }
      }
      // The submitted bytes are unchanged across Firestore retries. Hash once;
      // ownership, account state and attempt binding still recheck in every retry.
      const imageDigest = digest(file.buffer);
      // The same photo file on a second account is one ID shared by two people.
      const sameImage = await db.collection('document_suitability').where('sha256', '==', imageDigest).limit(5).get();
      if (sameImage.docs.some(doc => doc.id !== uid)) {
        throw Object.assign(fail('DOCUMENT_ALREADY_USED', 409), { image: 'document',
          publicMessage: 'This ID photo is already in use on another account. Use your own ID, or contact support if this is a mistake.' });
      }
      const attemptId = randomUUID(), imagePath = `document_suitability/${uid}/${attemptId}.${file.mimetype === 'image/png' ? 'png' : 'jpg'}`;
      await saveLocalBuffer(imagePath, file.buffer, uploadsDir);
      let committed = false, prior;
      try {
        const record = await db.runTransaction(async tx => {
          active((await tx.get(db.collection('users').doc(uid))).data());
          prior = (await tx.get(refFor(uid))).data();
          if (prior) bound(prior, uid, fields.sessionId, fields.attemptId, true);
          else if (fields.sessionId || fields.attemptId) throw fail('DOCUMENT_ATTEMPT_STALE');
          const now = new Date();
          const sessionId = prior?.sessionId || randomUUID();
          const decision = autoChecked ? { status: 'DOCUMENT_ACCEPTED', reasonCode: 'SUITABLE', reviewerId: 'auto_document_check', reviewedAt: now, sessionId, attemptId } : null;
          const value = { ownerId: uid, sessionId, attemptId,
            declaredType: fields.idType, status: 'DOCUMENT_REVIEW_REQUIRED', mock: false,
            sha256: imageDigest, imagePath, contentType: file.mimetype,
            submittedAt: now, expiresAt: new Date(now.getTime() + 30 * 86400000),
            ...(decision || {}), history: [...(prior?.history || []), ...(decision ? [decision] : [])].slice(-20) };
          tx.set(refFor(uid), value);
          audit(tx, { uid }, 'document.submitted', uid, { sessionId: value.sessionId, attemptId, ...(decision ? { autoAccepted: true } : {}) });
          return value;
        });
        committed = true;
        if (prior?.imagePath) await removeLocalPaths([prior.imagePath], uploadsDir).catch(() => {});
        return publicDocument(record);
      } finally { if (!committed) await removeLocalPaths([imagePath], uploadsDir).catch(() => {}); }
    },
    async review(uid, actor, body) {
      documentEnvironment(db);
      if (process.env.NATIONAL_ID_MOCK_ENABLED === 'true') throw fail('USE_MOCK_IDENTITY_SESSION', 503);
      if (actor.uid === uid) throw fail('SELF_REVIEW_FORBIDDEN', 403);
      const allowed = { DOCUMENT_ACCEPTED: ['SUITABLE'], DOCUMENT_REJECTED: ['NOT_SUPPORTED','INCOMPLETE'], DOCUMENT_UNREADABLE: ['UNREADABLE'] };
      if (!allowed[body.status]?.includes(body.reasonCode)) throw fail('INVALID_DOCUMENT_DECISION', 400);
      return db.runTransaction(async tx => {
        const ref = refFor(uid), record = (await tx.get(ref)).data();
        bound(record, uid, body.sessionId, body.attemptId);
        if (mockDocument(record) || record.status !== 'DOCUMENT_REVIEW_REQUIRED') throw fail('DOCUMENT_NOT_REVIEWABLE');
        const decision = { status: body.status, reasonCode: body.reasonCode, reviewerId: actor.uid, reviewedAt: new Date(), sessionId: record.sessionId, attemptId: record.attemptId };
        const updated = { ...record, ...decision, history: [...(record.history || []), decision].slice(-20) };
        tx.set(ref, updated);
        audit(tx, actor, 'document.reviewed', uid, decision);
        return publicDocument(updated);
      });
    },
    refFor,
  };
}
module.exports = { STATES, TYPES, publicDocument, acceptedDocument, createDocumentService, digest, documentEnvironment, liveDocument: live };
