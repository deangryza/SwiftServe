const { createHash } = require('node:crypto');
const { Timestamp } = require('firebase-admin/firestore');
const { validDocumentId } = require('./expiryIdentifiers');
const OUTBOX = '_jobExpiryPushOutbox';
const idFor = (...parts) => `activity.v1.${createHash('sha256').update(JSON.stringify(parts)).digest('hex')}`;
const validUid = value => typeof value === 'string' && value.length <= 128 && validDocumentId(value);
const active = env => env.ACTIVITY_PUSH_ENABLED === 'true' && env.ACTIVITY_PUSH_DRY_RUN === 'false';
// Never trust notification title/body as a lock-screen payload. Resolve the
// underlying relationship again in the dispatch transaction, including retries.
async function context(tx, db, event) {
  if (!validUid(event.recipientId)) return null;
  if (event.notificationId && event.conversationId) return null;
  if (event.conversationId) {
    if (!validDocumentId(event.conversationId) || !validDocumentId(event.messageId)) return null;
    const conversation = (await tx.get(db.doc(`conversations/${event.conversationId}`))).data();
    const message = (await tx.get(db.doc(`conversations/${event.conversationId}/messages/${event.messageId}`))).data();
    const ids = conversation?.participantIds;
    if (!Array.isArray(ids) || ids.length !== 2 || !ids.every(validUid) || ids[0] === ids[1] ||
        !ids.includes(event.recipientId) || !ids.includes(message?.senderId) || message.senderId === event.recipientId) return null;
    const sender = message.senderId;
    const blocks = await Promise.all([
      tx.get(db.doc(`user_blocks/${sender}_${event.recipientId}`)),
      tx.get(db.doc(`user_blocks/${event.recipientId}_${sender}`)),
    ]);
    if (blocks.some(value => value.exists)) return null;
    const profile = (await tx.get(db.doc(`public_profiles/${sender}`))).data();
    const name = typeof profile?.fullName === 'string' ? profile.fullName.slice(0, 60) : 'Someone';
    // Message contents are never put into FCM; names use the public profile.
    return { title: name, body: 'Sent you a message.', type: 'chatMessage',
      conversationId: event.conversationId };
  }
  if (!validDocumentId(event.notificationId)) return null;
  const notification = (await tx.get(db.doc(`notifications/${event.notificationId}`))).data();
  if (!notification || notification.recipientId !== event.recipientId || notification.senderId === event.recipientId ||
      notification.type === 'jobExpired') return null;
  if (notification.type === 'verificationUpdated') return { title: 'Verification updated', body: 'Open SwiftServe to view your update.', type: 'activity' };
  if (!validDocumentId(notification.requestId)) return null;
  const job = (await tx.get(db.doc(`service_requests/${notification.requestId}`))).data();
  const application = (await tx.get(db.doc(`service_requests/${notification.requestId}/applications/${event.recipientId}`))).data();
  if (!job || (job.clientId !== event.recipientId && job.workerId !== event.recipientId && !application)) return null;
  return { title: 'SwiftServe update', body: 'Open SwiftServe to view your update.', type: 'activity' };
}
async function enqueue({ db, env = process.env, notificationId, conversationId, messageId, now = Date.now }) {
  if (!active(env)) return { status: 'disabled' };
  require('./runtime').validateTarget(db, env);
  if ((!notificationId && (!validDocumentId(conversationId) || !validDocumentId(messageId))) ||
      (notificationId && !validDocumentId(notificationId))) throw new Error('Invalid source');
  return db.runTransaction(async tx => {
    const settings = (await tx.get(db.doc('_jobExpiryControl/settings'))).data();
    if (settings?.activityPushEnabled !== true) return { status: 'disabled' };
    let recipients;
    if (notificationId) {
      const data = (await tx.get(db.doc(`notifications/${notificationId}`))).data();
      recipients = validUid(data?.recipientId) ? [data.recipientId] : [];
    } else {
      const data = (await tx.get(db.doc(`conversations/${conversationId}`))).data();
      const message = (await tx.get(db.doc(`conversations/${conversationId}/messages/${messageId}`))).data();
      recipients = Array.isArray(data?.participantIds) ? data.participantIds.filter(uid => uid !== message?.senderId) : [];
    }
    const writes = [];
    for (const recipientId of recipients) {
      const source = notificationId ? { notificationId } : { conversationId, messageId };
      const eventId = idFor(notificationId ? 'notification' : 'message', source, recipientId);
      const event = { ...source, eventId, recipientId, type: 'activityPush' };
      const payload = await context(tx, db, event);
      const ref = db.collection(OUTBOX).doc(eventId);
      const existing = await tx.get(ref);
      if (payload && !existing.exists) writes.push([ref, { ...event, status: 'pending', attempts: 0,
        dueAt: Timestamp.fromMillis(now()), createdAt: Timestamp.fromMillis(now()) }]);
    }
    for (const [ref, data] of writes) tx.create(ref, data);
    return { status: 'queued', count: writes.length };
  });
}
// Fill only gaps in the existing in-app system. Accepted/application-created
// records already come from the application transaction; do not duplicate them.
async function recordUpdate({ db, env = process.env, requestId, workerId, status, version, now = Date.now }) {
  if (env.ACTIVITY_EVENTS_ENABLED !== 'true') return { status: 'disabled' };
  require('./runtime').validateTarget(db, env);
  if (!validDocumentId(requestId) || (workerId && !validUid(workerId)) || typeof version !== 'string') throw new Error('Invalid update');
  return db.runTransaction(async tx => {
    const settings = (await tx.get(db.doc('_jobExpiryControl/settings'))).data();
    if (settings?.activityEventsEnabled !== true) return { status: 'disabled' };
    const job = (await tx.get(db.doc(`service_requests/${requestId}`))).data();
    if (!job) return { status: 'skipped' };
    let recipients, type;
    if (workerId) {
      const application = (await tx.get(db.doc(`service_requests/${requestId}/applications/${workerId}`))).data();
      if (status !== 'rejected' || application?.status !== status) return { status: 'skipped' };
      recipients = [workerId]; type = 'applicationRejected';
    } else {
      if (!['ongoing', 'completed', 'cancelled'].includes(status) || job.status !== status) return { status: 'skipped' };
      recipients = [...new Set([job.clientId, job.workerId].filter(validUid))]; type = 'bookingUpdated';
    }
    const writes = [];
    for (const recipientId of recipients) {
      const id = idFor('update', requestId, workerId || '', status, version, recipientId);
      const ref = db.doc(`notifications/${id}`);
      const journal = db.doc(`_jobExpiryControl/activityEvents/records/${id}`);
      const recorded = (await tx.get(journal)).data();
      if (recorded) {
        if (recorded.recipientId !== recipientId || recorded.requestId !== requestId || recorded.type !== type)
          throw new Error('Activity identity mismatch');
        continue;
      }
      writes.push([journal, { recipientId, requestId, type, createdAt: Timestamp.fromMillis(now()) }]);
      if (!(await tx.get(ref)).exists) writes.push([ref, { recipientId, senderId: 'system', requestId, type,
        recipientRole: recipientId === job.clientId ? 'client' : 'worker', title: type === 'applicationRejected' ? 'Application not selected' : 'Booking updated',
        body: type === 'applicationRejected' ? 'Open SwiftServe to view your application.' : `Your booking is ${status}.`, read: false, createdAt: Timestamp.fromMillis(now()) }]);
    }
    for (const [ref, data] of writes) tx.create(ref, data);
    return { status: 'recorded', count: writes.length };
  });
}
module.exports = { idFor, context, enqueue, active, recordUpdate };
