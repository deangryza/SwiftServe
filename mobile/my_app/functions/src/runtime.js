const { randomUUID, createHash } = require("node:crypto");
const { FieldPath, Timestamp } = require("firebase-admin/firestore");
const { inspectAndExpire, safeCode } = require("./expiredJobCleanupService");
const { expiryEventId, matchesExpiryEvent, validDocumentId } = require("./expiryIdentifiers");
const CONTROL = "_jobExpiryControl";
const OUTBOX = "_jobExpiryPushOutbox";
const LEASE_MS = 120000;
const RENEW_MS = 30000;
const MAX_ATTEMPTS = 8;
const stamp = (ms) => Timestamp.fromMillis(ms);
function validateTarget(db, env = process.env) {
  const local = env.FUNCTIONS_EMULATOR === "true";
  const project = db.projectId;
  if (env.EXPIRY_DATABASE !== "(default)" || db.databaseId !== "(default)")
    throw new Error("Default database required");
  if (local) {
    if (
      !project.startsWith("demo-") ||
      !env.FIRESTORE_EMULATOR_HOST ||
      env.EXPIRY_EXPECTED_PROJECT !== project
    )
      throw new Error("Isolated demo emulator required");
  } else if (
    project !== "swiftserve-production" ||
    env.EXPIRY_EXPECTED_PROJECT !== project ||
    env.FIRESTORE_EMULATOR_HOST
  ) {
    throw new Error("Production project/emulator mismatch");
  }
}
function enabled(env, name) {
  return env[name] === "true";
}
async function gate(tx, db, field) {
  const settings = await tx.get(db.collection(CONTROL).doc("settings"));
  if (settings.data()?.[field] !== true)
    throw new Error(`Runtime gate closed: ${field}`);
}
function assertLease(data, owner, fence, now) {
  if (
    data?.owner !== owner ||
    data?.fence !== fence ||
    !(data?.leaseUntil instanceof Timestamp) ||
    data.leaseUntil.toMillis() <= now
  )
    throw new Error("Lease lost");
}
async function sweep({
  db,
  env = process.env,
  now = Date.now,
  budgetMs = 240000,
  maxDocuments = 1000,
  shouldStop = () => false,
  inspect = inspectAndExpire,
}) {
  if (!enabled(env, "EXPIRED_JOB_CLEANUP_ENABLED"))
    return { status: "disabled" };
  validateTarget(db, env);
  // Durable preview writes operational metadata, never jobs/notifications/outbox.
  if (!enabled(env, "EXPIRY_METADATA_WRITES_ENABLED"))
    return { status: "metadata_disabled" };
  const dryRun = env.EXPIRED_JOB_CLEANUP_DRY_RUN !== "false";
  const field = dryRun ? "previewEnabled" : "expirationEnabled";
  const ref = db.collection(CONTROL).doc(dryRun ? "preview" : "expiration");
  const owner = randomUUID();
  const started = now();
  const claim = await db.runTransaction(async (tx) => {
    await gate(tx, db, field);
    const data = (await tx.get(ref)).data() || {};
    if (data.leaseUntil?.toMillis() > now()) return null;
    if (data.version != null && data.version !== 1)
      throw new Error("Unknown checkpoint version");
    if (
      data.project &&
      (data.project !== db.projectId || data.database !== "(default)")
    )
      throw new Error("Checkpoint target mismatch");
    const next = {
      version: 1,
      project: db.projectId,
      database: "(default)",
      owner,
      fence: (data.fence || 0) + 1,
      cutoff: data.cutoff || stamp(now()),
      cursor: data.cursor || null,
      leaseUntil: stamp(now() + LEASE_MS),
    };
    tx.set(ref, next);
    return next;
  });
  if (!claim) return { status: "busy" };
  let cursor = claim.cursor;
  let scanned = 0;
  let affected = 0;
  let renewedAt = started;
  const guard = async (tx) => {
    await gate(tx, db, field);
    assertLease((await tx.get(ref)).data(), owner, claim.fence, now());
  };
  async function progress(
    complete = false,
    release = false,
    status = "continuation_required",
  ) {
    await db.runTransaction(async (tx) => {
      await guard(tx);
      tx.update(ref, {
        cursor: complete ? null : cursor,
        cutoff: complete ? null : claim.cutoff,
        leaseUntil: stamp(release ? 0 : now() + LEASE_MS),
        status: complete ? "complete" : status,
        ...(complete ? { completedAt: stamp(now()) } : {}),
      });
    });
    renewedAt = now();
  }
  try {
    while (
      scanned < maxDocuments &&
      now() - started < budgetMs &&
      !shouldStop()
    ) {
      await progress();
      let query = db
        .collection("service_requests")
        .where("status", "==", "pending")
        .orderBy(FieldPath.documentId())
        .limit(Math.min(100, maxDocuments - scanned));
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      if (page.empty) {
        await progress(true, true);
        return { status: "complete", scanned, affected, dryRun };
      }
      for (const doc of page.docs) {
        if (shouldStop() || now() - started >= budgetMs) {
          await progress(false, true, "interrupted");
          return { status: "interrupted", scanned, affected, dryRun };
        }
        // Sequential fenced heartbeat; never race a timer against candidate work.
        if (now() - renewedAt >= RENEW_MS) await progress();
        const out = db.collection(OUTBOX).doc(expiryEventId(doc.id));
        let exists = false;
        const result = await inspect(db, doc.ref, claim.cutoff, dryRun, {
          guard,
          prepare: async (tx, data) => {
            if (dryRun) return;
            const snapshot = await tx.get(out);
            exists = snapshot.exists;
            if (
              exists &&
              (snapshot.data().recipientId !== data.clientId ||
                snapshot.data().requestId !== doc.id)
            )
              throw new Error("Outbox identity mismatch");
          },
          write: (tx, data) => {
            if (!exists)
              tx.create(out, {
                recipientId: data.clientId,
                requestId: doc.id,
                eventId: out.id,
                type: "jobExpired",
                status: "pending",
                dueAt: stamp(now()),
                attempts: 0,
                createdAt: stamp(now()),
              });
          },
        });
        scanned++;
        if (["expired", "would_expire"].includes(result)) affected++;
        // Commit precedes checkpoint: replay after a crash is safe, skipping a
        // failed candidate is not. Every cursor write is fenced transactionally.
        cursor = doc.id;
        await progress();
      }
    }
    await progress(
      false,
      true,
      shouldStop() ? "interrupted" : "continuation_required",
    );
    return {
      status: shouldStop() ? "interrupted" : "continuation_required",
      scanned,
      affected,
      dryRun,
    };
  } catch (error) {
    // Do not overwrite a new owner's checkpoint; failed scans are never complete.
    try {
      await progress(false, true, "failed");
    } catch (_) {
      /* lease takeover/gate closure: recover after expiry */
    }
    throw error;
  }
}
async function pushRecoveryGate(tx, db) {
  const settings = (await tx.get(db.collection(CONTROL).doc("settings"))).data();
  if (settings?.pushEnabled !== true && settings?.activityPushEnabled !== true) throw new Error("Runtime push gate closed");
}
const invalidTokens = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);
const activity = require("./activityPush");
const pushActive = env => (enabled(env, "EXPIRY_PUSH_ENABLED") && env.EXPIRED_JOB_CLEANUP_DRY_RUN === "false") || activity.active(env);
const validRetryMetadata = (data) => data?.dueAt instanceof Timestamp;
async function dispatch({
  db,
  send,
  eventId,
  env = process.env,
  now = Date.now,
}) {
  if (
    !pushActive(env)
  )
    return { status: "disabled" };
  validateTarget(db, env);
  if (!validDocumentId(eventId))
    throw new Error("Invalid event ID");
  const ref = db.collection(OUTBOX).doc(eventId);
  const owner = randomUUID();
  const event = await db.runTransaction(async (tx) => {
    const data = (await tx.get(ref)).data();
    const generic = data?.type === "activityPush";
    if (generic ? !activity.active(env) : !(enabled(env, "EXPIRY_PUSH_ENABLED") && env.EXPIRED_JOB_CLEANUP_DRY_RUN === "false")) return null;
    await gate(tx, db, generic ? "activityPushEnabled" : "pushEnabled");
    if (
      !data ||
      ["accepted", "no_targets", "dead_letter"].includes(data.status)
    )
      return null;
    if (!validRetryMetadata(data)) {
      tx.update(ref, {
        status: "dead_letter",
        reason: "invalid_retry_metadata",
        updatedAt: stamp(now()),
      });
      return { invalid: true };
    }
    if (data.dueAt.toMillis() > now()) return null;
    if (
      (!generic && !matchesExpiryEvent(eventId, data.requestId)) ||
      typeof data.recipientId !== "string" ||
      !data.recipientId ||
      data.recipientId.includes("/") ||
      data.recipientId.length > 128
    ) {
      tx.update(ref, {
        status: "dead_letter",
        reason: "invalid_event_context",
        updatedAt: stamp(now()),
      });
      return { invalid: true };
    }
    let payload;
    if (generic) {
      const source = data.notificationId ? { notificationId: data.notificationId } : { conversationId: data.conversationId, messageId: data.messageId };
      if (data.eventId === eventId && eventId === activity.idFor(data.notificationId ? "notification" : "message", source, data.recipientId))
        payload = await activity.context(tx, db, data);
      if (!payload) {
        tx.update(ref, { status: "dead_letter", reason: "invalid_event_context", updatedAt: stamp(now()) });
        return { invalid: true };
      }
    } else {
    const notification = (
      await tx.get(db.collection("notifications").doc(eventId))
    ).data();
    const job = (
      await tx.get(db.collection("service_requests").doc(data.requestId))
    ).data();
    if (
      data.type !== "jobExpired" ||
      data.eventId !== eventId ||
      notification?.recipientId !== data.recipientId ||
      notification?.requestId !== data.requestId ||
      notification?.type !== "jobExpired" ||
      job?.clientId !== data.recipientId ||
      job?.status !== "expired"
    ) {
      tx.update(ref, {
        status: "dead_letter",
        reason: "invalid_event_context",
        updatedAt: stamp(now()),
      });
      return { invalid: true };
    }
    }
    // Crashed final claims are terminal too; do not reclaim them for attempt 9.
    // Preserve the event and delivery journals for diagnosis/manual reconciliation.
    if (!Number.isInteger(data.attempts ?? 0) || (data.attempts ?? 0) < 0 ||
        (data.attempts ?? 0) >= MAX_ATTEMPTS) {
      tx.update(ref, { status: "dead_letter", reason: "attempt_limit", updatedAt: stamp(now()) });
      return { invalid: true };
    }
    const attempts = (data.attempts || 0) + 1;
    tx.update(ref, {
      owner,
      attempts,
      status: "sending",
      dueAt: stamp(now() + LEASE_MS),
    });
    return { ...data, attempts, payload };
  });
  if (!event) return { status: "skipped" };
  if (event.invalid) return { status: "dead_letter" };
  let retry = false;
  let accepted = 0;
  let invalid = 0;
  let lastErrorCode = null;
  try {
    const devices = await db
      .collection("users")
      .doc(event.recipientId)
      .collection("push_devices")
      .limit(21)
      .get();
    if (devices.size > 20) throw new Error("Device limit exceeded");
    if (devices.empty) retry = true; // New device registration can recover a recent event.
    for (const device of devices.docs) {
      const token = device.data().token;
      if (typeof token !== "string") continue;
      const hash = createHash("sha256").update(token).digest("hex");
      const delivery = ref.collection("deliveries").doc(hash);
      const canSend = await db.runTransaction(async (tx) => {
        await gate(tx, db, event.type === "activityPush" ? "activityPushEnabled" : "pushEnabled");
        const current = (await tx.get(ref)).data();
        if (current?.owner !== owner || current.status !== "sending" ||
            current.attempts !== event.attempts || current.attempts > MAX_ATTEMPTS ||
            !validRetryMetadata(current) || current.dueAt.toMillis() <= now())
          throw new Error("Push lease lost");
        const live = (await tx.get(device.ref)).data();
        const binding = (
          await tx.get(db.collection("_pushTokenOwners").doc(hash))
        ).data();
        const done = (await tx.get(delivery)).data();
        if (done?.status === "accepted") return "already_accepted";
        if (
          binding?.uid !== event.recipientId ||
          binding?.installationId !== device.id ||
          live?.token !== token ||
          live?.enabled !== true ||
          (event.payload?.type === "chatMessage" ? live?.chats === false : live?.activities === false) ||
          done?.status === "invalid"
        )
          return "ignore";
        return "send";
      });
      if (canSend === "already_accepted") {
        accepted++;
        continue;
      }
      if (canSend !== "send") continue;
      try {
        await send({
          token,
          notification: {
            title: event.payload?.title || "Job Post Expired",
            body: event.payload?.body || "Open SwiftServe to review your request and repost.",
          },
          data: {
            type: event.payload?.type || "jobExpired",
            eventId,
            ...(event.requestId ? { requestId: event.requestId } : {}),
            ...(event.notificationId ? { notificationId: event.notificationId } : {}),
            ...(event.conversationId ? { conversationId: event.conversationId } : {}),
            recipientId: event.recipientId,
          },
          android: {
            notification: { tag: eventId, channelId: "swiftserve_jobs" },
          },
          apns: { headers: {
            "apns-collapse-id": createHash("sha256").update(eventId, "utf8").digest("hex"),
          } },
        });
        await delivery.set({ status: "accepted", acceptedAt: stamp(now()) });
        accepted++;
      } catch (error) {
        lastErrorCode = safeCode(error);
        if (invalidTokens.has(error.code)) {
          invalid++;
          await db.runTransaction(async (tx) => {
            const live = await tx.get(device.ref);
            const bindingRef = db.collection('_pushTokenOwners').doc(hash);
            const binding = (await tx.get(bindingRef)).data();
            if (live.data()?.token === token) tx.delete(device.ref);
            if (binding?.uid === event.recipientId && binding?.installationId === device.id)
              tx.delete(bindingRef);
            tx.set(delivery, { status: "invalid" });
          });
        } else retry = true;
      }
    }
  } catch (error) {
    lastErrorCode = safeCode(error);
    retry = true;
  }
  const status = retry
    ? event.attempts >= MAX_ATTEMPTS
      ? "dead_letter"
      : "pending"
    : accepted > 0
      ? "accepted"
      : "no_targets";
  await db.runTransaction(async (tx) => {
    const data = (await tx.get(ref)).data();
    if (data?.owner !== owner || data.status !== "sending" || data.attempts !== event.attempts)
      throw new Error("Push lease lost");
    tx.update(ref, {
      status,
      acceptedDevices: accepted,
      invalidDevices: invalid,
      lastErrorCode,
      ...(status === "dead_letter" ? { reason: "attempt_limit" } : {}),
      dueAt: stamp(now() + Math.min(3600000, 30000 * 2 ** event.attempts)),
      updatedAt: stamp(now()),
    });
  });
  return {
    status,
    acceptedDevices: accepted,
    invalidDevices: invalid,
    lastErrorCode,
  };
}
// Timestamp inequalities exclude missing/non-Timestamp fields. Independently
// audit a bounded, durable ID-ordered slice so old malformed events are found.
async function auditRetryMetadata({ db, env = process.env, now = Date.now }) {
  const ref = db.collection(CONTROL).doc("pushMetadata");
  const owner = randomUUID();
  const claim = await db.runTransaction(async (tx) => {
    await pushRecoveryGate(tx, db);
    const data = (await tx.get(ref)).data() || {};
    if (data.leaseUntil instanceof Timestamp && data.leaseUntil.toMillis() > now()) return null;
    if ((data.version != null && data.version !== 1) ||
        (data.project && (data.project !== db.projectId || data.database !== "(default)")))
      throw new Error("Push metadata checkpoint mismatch");
    const next = { version: 1, project: db.projectId, database: "(default)",
      owner, fence: (data.fence || 0) + 1, cursor: data.cursor || null,
      leaseUntil: stamp(now() + LEASE_MS) };
    tx.set(ref, next);
    return next;
  });
  if (!claim) return { status: "busy", scanned: 0, deadLettered: 0 };
  let scanned = 0;
  let deadLettered = 0;
  async function release(status, complete = false) {
    await db.runTransaction(async (tx) => {
      await pushRecoveryGate(tx, db);
      assertLease((await tx.get(ref)).data(), owner, claim.fence, now());
      tx.update(ref, { leaseUntil: stamp(0), status, ...(complete ? { cursor: null } : {}) });
    });
  }
  try {
    let query = db.collection(OUTBOX).where("status", "in", ["pending", "sending"])
      .orderBy(FieldPath.documentId()).limit(100);
    if (claim.cursor) query = query.startAfter(claim.cursor);
    const page = await query.get();
    for (const doc of page.docs) {
      const quarantined = await db.runTransaction(async (tx) => {
        await pushRecoveryGate(tx, db);
        const lease = (await tx.get(ref)).data();
        const data = (await tx.get(doc.ref)).data();
        assertLease(lease, owner, claim.fence, now());
        const reason = !validRetryMetadata(data) ? 'invalid_retry_metadata'
          : !['jobExpired', 'activityPush'].includes(data?.type) ? 'invalid_event_context' : null;
        const invalid = data && ["pending", "sending"].includes(data.status) && reason;
        if (invalid) tx.update(doc.ref, { status: "dead_letter",
          reason, updatedAt: stamp(now()) });
        // Quarantine and cursor movement commit together. Future valid events
        // keep their state, attempts and dueAt; stale audits conflict/fail closed.
        tx.update(ref, { cursor: doc.id, leaseUntil: stamp(now() + LEASE_MS) });
        return Boolean(invalid);
      });
      scanned++;
      if (quarantined) deadLettered++;
    }
    const status = page.empty ? "complete" : "continuation_required";
    await release(status, page.empty);
    return { status, scanned, deadLettered };
  } catch (error) {
    try { await release("failed"); } catch (_) { /* do not overwrite a new owner */ }
    throw error;
  }
}
async function retryDue(options) {
  if (
    !pushActive(options.env || process.env)
  )
    return { status: "disabled" };
  validateTarget(options.db, options.env);
  const env = options.env || process.env;
  const types = [
    ...(enabled(env, 'EXPIRY_PUSH_ENABLED') && env.EXPIRED_JOB_CLEANUP_DRY_RUN === 'false' ? ['jobExpired'] : []),
    ...(activity.active(env) ? ['activityPush'] : []),
  ];
  const snapshot = await options.db
    .collection(OUTBOX)
    .where('type', 'in', types)
    .where("status", "in", ["pending", "sending"])
    .where("dueAt", "<=", stamp((options.now || Date.now)()))
    .orderBy("dueAt")
    .limit(100)
    .get();
  let failures = 0;
  for (const doc of snapshot.docs) {
    try {
      await dispatch({ ...options, eventId: doc.id });
    } catch (_) {
      failures++;
    }
  }
  let metadata;
  try {
    metadata = await auditRetryMetadata(options);
  } catch (_) {
    failures++;
  }
  if (failures) throw new Error(`Push recovery failures: ${failures}`);
  return {
    scanned: snapshot.size,
    status: snapshot.size === 100 || metadata.status !== "complete"
      ? "continuation_required" : "complete",
    metadata,
  };
}
async function registerDevice({
  db,
  uid,
  data,
  env = process.env,
  now = Date.now,
}) {
  if (!uid) throw new Error("Authentication required");
  if (!enabled(env, "EXPIRY_TOKEN_REGISTRATION_ENABLED"))
    throw new Error("Registration disabled");
  validateTarget(db, env);
  if (
    !/^[a-f0-9]{32}$/.test(data?.installationId || "") ||
    ["enabled", "chats", "activities", "revoke"].some(key => data?.[key] !== undefined && typeof data[key] !== "boolean") ||
    !["android", "ios"].includes(data.platform) ||
    typeof data.token !== "string" ||
    data.token.length < 20 ||
    data.token.length > 4096
  )
    throw new Error("Invalid device");
  const ref = db
    .collection("users")
    .doc(uid)
    .collection("push_devices")
    .doc(data.installationId);
  await db.runTransaction(async (tx) => {
    await gate(tx, db, "registrationEnabled");
    const existing = await tx.get(ref);
    const hash = createHash("sha256").update(data.token).digest("hex");
    const binding = db.collection("_pushTokenOwners").doc(hash);
    const previous = (await tx.get(binding)).data();
    const oldToken = existing.data()?.token;
    const oldBinding = typeof oldToken === 'string' && oldToken !== data.token
      ? db.collection('_pushTokenOwners').doc(createHash('sha256').update(oldToken).digest('hex')) : null;
    const oldOwner = oldBinding ? (await tx.get(oldBinding)).data() : null;
    const devices = await tx.get(ref.parent.limit(21));
    if (!existing.exists && devices.size >= 20)
      throw new Error("Device limit exceeded");
    if (data.revoke === true) {
      if (existing.data()?.token === data.token) tx.delete(ref);
      if (
        previous?.uid === uid &&
        previous?.installationId === data.installationId
      )
        tx.delete(binding);
      return;
    }
    // Possession of a current FCM token binds this installation to its current account.
    // Old accounts retain no ability to send to a newly bound token.
    if (oldBinding && oldOwner?.uid === uid && oldOwner?.installationId === data.installationId)
      tx.delete(oldBinding);
    tx.set(binding, {
      uid,
      installationId: data.installationId,
      updatedAt: stamp(now()),
    });
    tx.set(ref, {
      token: data.token,
      platform: data.platform,
      enabled: data.enabled !== false,
      chats: data.chats !== false,
      activities: data.activities !== false,
      updatedAt: stamp(now()),
    });
  });
  return { registered: data.revoke !== true };
}
module.exports = {
  sweep,
  dispatch,
  retryDue,
  registerDevice,
  validateTarget,
  assertLease,
  CONTROL,
  OUTBOX,
};
