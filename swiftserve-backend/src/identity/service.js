const { createHash, randomUUID } = require('node:crypto');
const { Timestamp, FieldPath } = require('firebase-admin/firestore');
const { validateBirthday } = require('../services/registrationBirthday');
const { MockPSAProvider } = require('./provider');
const { LABEL, CONSENT_VERSION, fail, localTarget, validateImages, tensorflowFace } = require('./policy');
const COLLECTION = '_identityVerificationSessions';
const TTL = 10 * 60 * 1000, LEASE = 2 * 60 * 1000;
const stamp = ms => Timestamp.fromMillis(ms);
const millis = value => value instanceof Timestamp ? value.toMillis() : 0;
const final = new Set(['VERIFIED', 'REJECTED', 'EXPIRED', 'MANUAL_REVIEW']);
const validRef = value => /^mock-v1-[a-f0-9]{64}$/.test(value || '');
const own = (data, uid) => { if (!data || data.userId !== uid || data.providerType !== 'MOCK') throw fail(404, 'SESSION_NOT_FOUND'); };
const publicResult = data => ({
  verificationReference: data.verificationReference, userId: data.userId,
  accountType: data.accountType, verificationStatus: data.verificationStatus,
  governmentVerificationStatus: data.governmentVerificationStatus,
  faceVerificationStatus: data.faceVerificationStatus, livenessStatus: data.livenessStatus,
  providerType: 'MOCK', label: LABEL, officiallyVerified: false,
  retryable: data.retryable === true, rejectionReasonCode: data.rejectionReasonCode || null,
  consentVersion: data.consentVersion, expiresAt: millis(data.expiresAt),
  checkSource: data.checkSource,
  attempts: data.attempts, reviewerId: data.reviewerId || null,
});
class IdentityService {
  constructor({ db, env = process.env, clock = Date.now, provider, face, liveness, images = validateImages } = {}) {
    Object.assign(this, { db, env, clock, images });
    this.provider = provider || new MockPSAProvider(env.NATIONAL_ID_MOCK_SCENARIO || 'manual_review');
    const synthetic = env.NATIONAL_ID_SYNTHETIC_CHECKS === 'true';
    const fixture = (name, fallback) => async () => {
      const outcome = env[name] || fallback;
      if (!['PASSED', 'FAILED', 'MANUAL_REVIEW'].includes(outcome)) throw fail(400, 'INVALID_MOCK_CHECK');
      return { outcome };
    };
    this.face = face || (synthetic ? fixture('NATIONAL_ID_SYNTHETIC_FACE', 'PASSED') : (document, selfie) => tensorflowFace(document, selfie, env));
    // Camera-side blink/turn checks are not trusted server-side liveness proof.
    this.liveness = liveness || (synthetic ? fixture('NATIONAL_ID_SYNTHETIC_LIVENESS', 'PASSED') : async () => ({ outcome: 'UNSUPPORTED' }));
  }
  guard() { localTarget(this.db, this.env); }
  ref(id) { if (!validRef(id)) throw fail(400, 'INVALID_SESSION'); return this.db.collection(COLLECTION).doc(id); }
  async eligible(uid) {
    this.guard();
    const profile = (await this.db.collection('users').doc(uid).get()).data();
    if (!profile || !['client', 'worker'].includes(profile.role) || profile.status === 'suspended') throw fail(403, 'ACCOUNT_REQUIRED');
    const age = validateBirthday(profile.dateOfBirth, new Date(this.clock()));
    if (age) throw fail(age.status, age.code);
    return profile;
  }
  async create(uid, requestId) {
    const profile = await this.eligible(uid);
    if (typeof requestId !== 'string' || !/^[a-zA-Z0-9_-]{16,64}$/.test(requestId)) throw fail(400, 'INVALID_REQUEST_ID');
    const id = `mock-v1-${createHash('sha256').update(JSON.stringify(['swiftserve.identity.mock.v1', uid, requestId])).digest('hex')}`;
    const ref = this.ref(id), now = this.clock();
    return this.db.runTransaction(async tx => {
      const old = (await tx.get(ref)).data();
      if (old) { own(old, uid); return publicResult(old); }
      const data = { userId: uid, accountType: profile.role, verificationReference: id,
        providerType: 'MOCK', label: LABEL, officiallyVerified: false,
        checkSource: this.env.NATIONAL_ID_SYNTHETIC_CHECKS === 'true' ? 'SYNTHETIC_FIXTURE' : 'SERVER_ADAPTER',
        verificationStatus: 'CONSENT_REQUIRED', consentVersion: null, consentTimestamp: null,
        governmentVerificationStatus: 'NOT_STARTED', faceVerificationStatus: 'NOT_STARTED', livenessStatus: 'NOT_STARTED',
        submittedAt: null, completedAt: null, createdAt: stamp(now), updatedAt: stamp(now), expiresAt: stamp(now + TTL),
        attempts: 0, fence: 0, leaseOwner: null, leaseUntil: null, retryable: false,
        history: ['NOT_STARTED', 'CONSENT_REQUIRED'],
      };
      tx.set(ref, data); return publicResult(data);
    });
  }
  async get(uid, id) {
    this.guard(); const ref = this.ref(id);
    return this.db.runTransaction(async tx => {
      const data = (await tx.get(ref)).data(); own(data, uid);
      if (!['VERIFIED', 'REJECTED', 'EXPIRED'].includes(data.verificationStatus) && millis(data.expiresAt) <= this.clock()) {
        const next = { ...data, verificationStatus: 'EXPIRED', retryable: false, updatedAt: stamp(this.clock()) };
        tx.set(ref, next); return publicResult(next);
      }
      if (data.verificationStatus === 'PROCESSING' && millis(data.leaseUntil) <= this.clock()) {
        const next = { ...data, verificationStatus: 'FAILED', retryable: data.attempts < 3,
          rejectionReasonCode: 'INTERRUPTED', leaseOwner: null, leaseUntil: null, updatedAt: stamp(this.clock()) };
        tx.set(ref, next); return publicResult(next);
      }
      return publicResult(data);
    });
  }
  async consent(uid, id, version) {
    await this.eligible(uid); const ref = this.ref(id);
    if (version !== CONSENT_VERSION) throw fail(400, 'CONSENT_VERSION_REQUIRED');
    return this.db.runTransaction(async tx => {
      const data = (await tx.get(ref)).data(); own(data, uid);
      if (millis(data.expiresAt) <= this.clock()) throw fail(410, 'SESSION_EXPIRED');
      if (data.consentVersion === version) return publicResult(data);
      if (data.verificationStatus !== 'CONSENT_REQUIRED') throw fail(409, 'SESSION_CONFLICT');
      const next = { ...data, consentVersion: version, consentTimestamp: stamp(this.clock()),
        verificationStatus: 'PENDING', updatedAt: stamp(this.clock()), history: [...data.history, 'PENDING'] };
      tx.set(ref, next); return publicResult(next);
    });
  }
  async submit(uid, id, document, selfie, documentFormat) {
    await this.eligible(uid); const ref = this.ref(id);
    const owner = randomUUID();
    const claim = await this.db.runTransaction(async tx => {
      const data = (await tx.get(ref)).data(); own(data, uid);
      if (final.has(data.verificationStatus)) return { done: publicResult(data) };
      if (millis(data.expiresAt) <= this.clock()) throw fail(410, 'SESSION_EXPIRED');
      if (data.consentVersion !== CONSENT_VERSION || !data.consentTimestamp) throw fail(403, 'CONSENT_REQUIRED');
      if (data.verificationStatus === 'PROCESSING' && millis(data.leaseUntil) > this.clock()) throw fail(409, 'PROCESSING');
      if (data.attempts >= 3 || (data.verificationStatus === 'FAILED' && !data.retryable)) throw fail(409, 'RETRY_LIMIT');
      const next = { ...data, verificationStatus: 'PROCESSING', submittedAt: data.submittedAt || stamp(this.clock()),
        updatedAt: stamp(this.clock()), attempts: data.attempts + 1, fence: data.fence + 1,
        leaseOwner: owner, leaseUntil: stamp(this.clock() + LEASE), history: [...data.history.slice(-10), 'PROCESSING'] };
      tx.set(ref, next); return next;
    });
    if (claim.done) return claim.done;
    const finish = result => this.db.runTransaction(async tx => {
      const current = (await tx.get(ref)).data(); own(current, uid);
      if (current.leaseOwner !== owner || current.fence !== claim.fence || millis(current.leaseUntil) <= this.clock()) throw fail(409, 'LEASE_LOST');
      const expired = millis(current.expiresAt) <= this.clock();
      const next = { ...current, ...result, ...(expired ? { verificationStatus: 'EXPIRED', retryable: false } : {}),
        updatedAt: stamp(this.clock()), completedAt: stamp(this.clock()), leaseOwner: null, leaseUntil: null,
        history: [...current.history.slice(-10), ...(result.stages || []), expired ? 'EXPIRED' : result.verificationStatus] };
      next.retryable = !expired && result.retryable === true && current.attempts < 3;
      delete next.stages;
      tx.set(ref, next); return publicResult(next);
    });
    try {
      if (!['physical_image', 'digital_image'].includes(documentFormat)) throw fail(400, 'INVALID_DOCUMENT_FORMAT');
      await this.images(document, selfie);
      const government = await this.provider.authenticate({ reference: id });
      if (government.providerType !== 'MOCK' || !['PASSED', 'FAILED', 'EXPIRED', 'MANUAL_REVIEW'].includes(government.outcome)) throw fail(502, 'INVALID_PROVIDER_RESULT');
      if (government.outcome === 'EXPIRED') return await finish({ verificationStatus: 'EXPIRED', governmentVerificationStatus: 'EXPIRED', retryable: false });
      if (government.outcome === 'FAILED') return await finish({ verificationStatus: 'REJECTED', governmentVerificationStatus: 'FAILED', rejectionReasonCode: 'GOVERNMENT_MISMATCH', retryable: false });
      const face = await this.face(document, selfie);
      const live = await this.liveness(selfie);
      const allowed = ['PASSED', 'FAILED', 'MANUAL_REVIEW', 'UNAVAILABLE', 'UNSUPPORTED'];
      if (!allowed.includes(face.outcome) || !allowed.includes(live.outcome)) throw fail(502, 'INVALID_CHECK_RESULT');
      const rejected = face.outcome === 'FAILED' || live.outcome === 'FAILED';
      const passed = government.outcome === 'PASSED' && face.outcome === 'PASSED' && live.outcome === 'PASSED';
      return await finish({ verificationStatus: rejected ? 'REJECTED' : passed ? 'VERIFIED' : 'MANUAL_REVIEW',
        governmentVerificationStatus: government.outcome, faceVerificationStatus: face.outcome, livenessStatus: live.outcome,
        rejectionReasonCode: face.outcome === 'FAILED' ? 'FACE_MISMATCH' : live.outcome === 'FAILED' ? 'LIVENESS_FAILED' : null,
        retryable: false, stages: [
          ...(government.outcome === 'PASSED' ? ['GOVERNMENT_VERIFIED'] : []),
          ...(face.outcome === 'PASSED' ? ['FACE_VERIFIED'] : []),
        ] });
    } catch (error) {
      if (error.code === 'LEASE_LOST') throw error;
      return finish({ verificationStatus: 'FAILED', retryable: error.code === 'PROVIDER_UNAVAILABLE',
        rejectionReasonCode: ['PROVIDER_UNAVAILABLE', 'IMAGE_QUALITY', 'INVALID_IMAGE', 'INVALID_DOCUMENT_FORMAT'].includes(error.code) ? error.code : 'CHECK_UNAVAILABLE' });
    }
  }
  async list(cursor) {
    this.guard();
    if (cursor && !validRef(cursor)) throw fail(400, 'INVALID_CURSOR');
    let query = this.db.collection(COLLECTION).where('verificationStatus', '==', 'MANUAL_REVIEW').orderBy(FieldPath.documentId());
    if (cursor) query = query.startAfter(cursor);
    const result = await query.limit(25).get();
    return {
      items: result.docs.filter(doc => millis(doc.data().expiresAt) > this.clock()).map(doc => publicResult(doc.data())),
      nextCursor: result.docs.length === 25 ? result.docs.at(-1).data().verificationReference : null,
    };
  }
  async review(id, reviewerId, decision, reason) {
    this.guard(); const ref = this.ref(id);
    if (!['approve', 'reject'].includes(decision) || !['CHECKS_REVIEWED', 'INCONSISTENT_EVIDENCE', 'UNSUPPORTED_CHECKS'].includes(reason)) throw fail(400, 'INVALID_REVIEW');
    return this.db.runTransaction(async tx => {
      const data = (await tx.get(ref)).data();
      if (!data || data.providerType !== 'MOCK') throw fail(404, 'SESSION_NOT_FOUND');
      if (data.userId === reviewerId) throw fail(403, 'SELF_REVIEW_FORBIDDEN');
      if (data.verificationStatus !== 'MANUAL_REVIEW' || millis(data.expiresAt) <= this.clock()) throw fail(409, 'REVIEW_UNAVAILABLE');
      if (decision === 'approve' && (!['PASSED', 'MANUAL_REVIEW'].includes(data.governmentVerificationStatus) ||
        data.faceVerificationStatus !== 'PASSED' || data.livenessStatus !== 'PASSED')) throw fail(409, 'REQUIRED_CHECKS_MISSING');
      const next = { ...data, verificationStatus: decision === 'approve' ? 'VERIFIED' : 'REJECTED',
        reviewerId, reviewReasonCode: reason, reviewedAt: stamp(this.clock()), completedAt: stamp(this.clock()), updatedAt: stamp(this.clock()) };
      tx.set(ref, next);
      tx.set(this.db.collection('_identityVerificationAudit').doc(`${id}-${data.fence}`), {
        verificationReference: id, reviewerId, decision, reasonCode: reason, providerType: 'MOCK', createdAt: stamp(this.clock()),
      });
      return publicResult(next);
    });
  }
}
module.exports = { IdentityService, COLLECTION, validRef, publicResult };
