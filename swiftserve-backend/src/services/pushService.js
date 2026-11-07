const { FieldValue, Timestamp } = require('firebase-admin/firestore');

// Phone registrations: push_devices/{uid}/devices/{installationId}.
// Clients never read or write these directly (Firestore denies unmatched paths).
const devicesOf = (db, uid) => db.collection('push_devices').doc(uid).collection('devices');

// One document per delivered event, created atomically, so restarts or a
// second API instance never push the same event twice.
const DISPATCH = '_pushDispatch';

const ID = /^[A-Za-z0-9_-]{1,128}$/;
const MAX_TOKEN = 4096;

const isId = (value) => typeof value === 'string' && ID.test(value);

/** Validates and saves (or revokes) one phone's push registration. */
async function registerDevice({ db, uid, body }) {
  const { installationId, token, platform } = body || {};
  if (!isId(installationId)) return { status: 400, message: 'installationId is invalid.' };
  const ref = devicesOf(db, uid).doc(installationId);
  if (body.revoke === true) {
    await ref.delete();
    return { status: 200, message: 'Device removed.' };
  }
  if (typeof token !== 'string' || !token || token.length > MAX_TOKEN) {
    return { status: 400, message: 'token is invalid.' };
  }
  if (!['android', 'ios'].includes(platform)) return { status: 400, message: 'platform is invalid.' };
  await ref.set({
    token,
    platform,
    enabled: body.enabled === true,
    chats: body.chats !== false,
    activities: body.activities !== false,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { status: 200, message: 'Device registered.' };
}

const INVALID_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

/** Sends one push to every enabled phone of [recipientId] that wants [kind]. */
async function sendToUser({ db, messaging, recipientId, kind, title, body, data }) {
  const devices = await devicesOf(db, recipientId).get();
  const targets = devices.docs.filter((doc) => {
    const device = doc.data();
    return device.enabled === true && device[kind] !== false && typeof device.token === 'string';
  });
  if (!targets.length) return 0;
  const response = await messaging.sendEach(targets.map((doc) => ({
    token: doc.data().token,
    notification: { title, body },
    data,
    android: { priority: 'high', notification: { channelId: 'swiftserve_jobs' } },
    apns: { payload: { aps: { sound: 'default' } } },
  })));
  // Drop phones whose token is no longer valid (app uninstalled, etc.).
  await Promise.all(response.responses.map((result, index) => (
    !result.success && INVALID_TOKEN_CODES.has(result.error?.code)
      ? targets[index].ref.delete().catch(() => {})
      : null
  )));
  return response.successCount;
}

/** Atomically claims an event; false when it was already pushed. */
async function claim(db, eventId) {
  try {
    await db.collection(DISPATCH).doc(eventId).create({ at: FieldValue.serverTimestamp() });
    return true;
  } catch (error) {
    if (error.code === 6 || error.code === 'already-exists') return false;
    throw error;
  }
}

const clip = (value, max) => String(value ?? '').slice(0, max);

async function pushNotification({ db, messaging, id, notification }) {
  const recipientId = notification.recipientId;
  if (!isId(id) || !isId(recipientId) || notification.senderId === recipientId) return;
  const eventId = `n_${id}`;
  if (!(await claim(db, eventId))) return;
  await sendToUser({
    db,
    messaging,
    recipientId,
    kind: 'activities',
    title: clip(notification.title || 'SwiftServe update', 120),
    body: clip(notification.body || 'Open SwiftServe to view your update.', 240),
    data: { type: 'activity', notificationId: id, recipientId, eventId },
  });
}

async function pushChat({ db, messaging, id, conversation }) {
  const { lastMessageId, lastSenderId, participantIds } = conversation;
  if (!isId(id) || !isId(lastMessageId) || !isId(lastSenderId) || !Array.isArray(participantIds)) return;
  const eventId = `m_${id}_${lastMessageId}`.slice(0, 128);
  if (!(await claim(db, eventId))) return;
  const sender = (await db.collection('public_profiles').doc(lastSenderId).get()).data();
  const name = clip(sender?.fullName || 'New message', 60);
  const hiddenFor = Array.isArray(conversation.hiddenFor) ? conversation.hiddenFor : [];
  for (const recipientId of participantIds) {
    if (!isId(recipientId) || recipientId === lastSenderId || hiddenFor.includes(recipientId)) continue;
    // Message text is never sent through push; it may be private.
    await sendToUser({
      db,
      messaging,
      recipientId,
      kind: 'chats',
      title: name,
      body: 'Sent you a message.',
      data: { type: 'chatMessage', conversationId: id, recipientId, eventId },
    });
  }
}

/**
 * Watches new notifications and chat messages and pushes them to phones.
 * Only events newer than [since] are considered, so a restart does not
 * replay old history. Returns a function that stops watching.
 */
function startPushDispatcher({ db, messaging, since = Date.now() - 5 * 60 * 1000, log = console }) {
  const from = Timestamp.fromMillis(since);
  const handle = (label, work) => work().catch((error) => {
    log.error(`Push ${label} failed:`, error.message);
  });

  const stopNotifications = db.collection('notifications')
    .where('createdAt', '>', from)
    .onSnapshot((snapshot) => {
      for (const change of snapshot.docChanges()) {
        if (change.type !== 'added') continue;
        handle('notification', () => pushNotification({
          db, messaging, id: change.doc.id, notification: change.doc.data(),
        }));
      }
    }, (error) => log.error('Push notification watcher stopped:', error.message));

  const stopChats = db.collection('conversations')
    .where('updatedAt', '>', from)
    .onSnapshot((snapshot) => {
      for (const change of snapshot.docChanges()) {
        if (change.type === 'removed') continue;
        handle('chat', () => pushChat({ db, messaging, id: change.doc.id, conversation: change.doc.data() }));
      }
    }, (error) => log.error('Push chat watcher stopped:', error.message));

  return () => {
    stopNotifications();
    stopChats();
  };
}

module.exports = {
  registerDevice,
  sendToUser,
  pushNotification,
  pushChat,
  startPushDispatcher,
};
