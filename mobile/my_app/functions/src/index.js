const { initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const runtime = require("./runtime");
// ADC only: no service-account keys, no database connection at module discovery.
setGlobalOptions({
  ...(process.env.EXPIRY_SERVICE_ACCOUNT
    ? { serviceAccount: process.env.EXPIRY_SERVICE_ACCOUNT }
    : {}),
  region: process.env.EXPIRY_REGION || "us-central1",
  maxInstances: 1,
  concurrency: 1,
  timeoutSeconds: 540,
});
let stopping = false;
process.once("SIGTERM", () => {
  stopping = true;
});
function dependencies() {
  if (!getApps().length) initializeApp();
  const db = getFirestore();
  return {
    db,
    env: process.env,
    send: (message) => getMessaging().send(message),
  };
}
exports.expireEligibleJobs = onSchedule(
  { schedule: "every 30 minutes", timeZone: "UTC", retryCount: 3 },
  async () => {
    if (process.env.EXPIRED_JOB_CLEANUP_ENABLED !== "true") return;
    const result = await runtime.sweep({
      ...dependencies(),
      shouldStop: () => stopping,
    });
    console.info({ event: "expiry_sweep", ...result });
    if (["interrupted", "continuation_required"].includes(result.status))
      throw new Error(`Expiry scan ${result.status}; checkpoint retained`);
  },
);
exports.dispatchExpiredJobPush = onDocumentCreated(
  {
    document: "_jobExpiryPushOutbox/{eventId}",
    database: "(default)",
    retry: true,
  },
  async (event) => {
    if (process.env.EXPIRY_PUSH_ENABLED !== "true" && process.env.ACTIVITY_PUSH_ENABLED !== "true") return;
    console.info({
      event: "expiry_push_attempt",
      eventId: event.params.eventId,
      ...(await runtime.dispatch({
        ...dependencies(),
        eventId: event.params.eventId,
      })),
    });
  },
);
exports.retryExpiredJobPush = onSchedule(
  { schedule: "every 5 minutes", timeZone: "UTC", retryCount: 3 },
  async () => {
    if (process.env.EXPIRY_PUSH_ENABLED !== "true" && process.env.ACTIVITY_PUSH_ENABLED !== "true") return;
    console.info({
      event: "push_recovery",
      ...(await runtime.retryDue(dependencies())),
    });
  },
);
exports.registerPushDevice = onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth)
      throw new HttpsError("unauthenticated", "Sign in first.");
    try {
      return await runtime.registerDevice({
        ...dependencies(),
        uid: request.auth.uid,
        data: request.data,
      });
    } catch (_) {
      throw new HttpsError(
        "failed-precondition",
        "Device registration unavailable.",
      );
    }
  },
);

exports.queueActivityPush = onDocumentCreated({ document: "notifications/{notificationId}", database: "(default)", retry: true }, async event => {
  if (process.env.ACTIVITY_PUSH_ENABLED !== "true") return;
  await require("./activityPush").enqueue({ ...dependencies(), notificationId: event.params.notificationId });
});
exports.queueChatPush = onDocumentCreated({ document: "conversations/{conversationId}/messages/{messageId}", database: "(default)", retry: true }, async event => {
  if (process.env.ACTIVITY_PUSH_ENABLED !== "true") return;
  await require("./activityPush").enqueue({ ...dependencies(), conversationId: event.params.conversationId, messageId: event.params.messageId });
});
exports.recordBookingUpdate = onDocumentUpdated({ document: "service_requests/{requestId}", database: "(default)", retry: true }, async event => {
  if (process.env.ACTIVITY_EVENTS_ENABLED !== "true" || event.data.before.data().status === event.data.after.data().status) return;
  await require('./activityPush').recordUpdate({ ...dependencies(), requestId: event.params.requestId,
    status: event.data.after.data().status, version: `${event.data.after.updateTime.seconds}:${event.data.after.updateTime.nanoseconds}` });
});
exports.recordApplicationRejection = onDocumentUpdated({ document: "service_requests/{requestId}/applications/{workerId}", database: "(default)", retry: true }, async event => {
  if (process.env.ACTIVITY_EVENTS_ENABLED !== "true" || event.data.before.data().status === event.data.after.data().status) return;
  await require('./activityPush').recordUpdate({ ...dependencies(), requestId: event.params.requestId, workerId: event.params.workerId,
    status: event.data.after.data().status, version: `${event.data.after.updateTime.seconds}:${event.data.after.updateTime.nanoseconds}` });
});
