const { expiryEventId } = require("./expiryIdentifiers");
function createPolicy({ FieldPath, FieldValue, Timestamp }) {
  const INTERVAL_MS = 30 * 60 * 1000;
  const PAGE_SIZE = 100;
  const MAX_PER_RUN = 1000;
  const assignmentFields = [
    "workerId",
    "workerName",
    "acceptedAt",
    "ongoingAt",
    "completedAt",
    "cancelledAt",
    "errandStage",
    "pickedUpAt",
    "deliveringAt",
  ];
  const linkedCollections = ["conversations", "reports", "sos_alerts"];

  function eligibility(data, asOf) {
    if (!data) return "missing_request";
    if (data.status !== "pending") return "status_changed";
    if (
      typeof data.clientId !== "string" ||
      !data.clientId.trim() ||
      data.clientId.length > 128
    )
      return "missing_owner";
    if (
      assignmentFields.some(
        (field) => data[field] != null && data[field] !== "",
      )
    ) {
      return "assignment_or_transaction";
    }
    // schedule alone predates date/time selection: do not infer a time for it.
    if (!(data.scheduleFrom instanceof Timestamp))
      return "missing_or_invalid_start";
    if (
      data.scheduleTo != null &&
      (!(data.scheduleTo instanceof Timestamp) ||
        data.scheduleTo.toMillis() < data.scheduleFrom.toMillis())
    )
      return "invalid_date_range";
    if (
      data.schedule != null &&
      (!(data.schedule instanceof Timestamp) ||
        !data.schedule.isEqual(data.scheduleFrom))
    )
      return "inconsistent_schedule";
    const wall = new Date(data.scheduleFrom.toMillis() + 8 * 60 * 60 * 1000);
    // Philippine midnight records include legacy date-only posts. Keep both those
    // and intentional midnight selections until explicit time metadata exists.
    if (wall.getUTCHours() === 0 && wall.getUTCMinutes() === 0)
      return "ambiguous_midnight";
    if (data.scheduleFrom.toMillis() >= asOf.toMillis()) return "not_expired";
    return null;
  }

  function safeCode(error) {
    const code = String(error?.code ?? "unknown");
    return /^[a-zA-Z0-9_/-]{1,64}$/.test(code) ? code : "unknown";
  }

  async function inspectAndExpire(db, reference, asOf, dryRun, hooks = {}) {
    return db.runTransaction(async (transaction) => {
      if (hooks.guard) await hooks.guard(transaction);
      const latest = await transaction.get(reference);
      const reason = eligibility(latest.data(), asOf);
      if (reason) return reason;
      // All reads precede the atomic status/notification writes. Query even rejected/old applications:
      // zero applications means no application documents in any status.
      const applications = await transaction.get(
        reference.collection("applications").limit(1),
      );
      if (!applications.empty) return "has_applications";
      const tracking = await transaction.get(
        reference.collection("private").doc("rider_location"),
      );
      if (tracking.exists) return "tracking_record";
      for (const name of linkedCollections) {
        const linked = await transaction.get(
          db.collection(name).where("requestId", "==", reference.id).limit(1),
        );
        if (!linked.empty) return `linked_${name}`;
      }
      for (const name of ["reviews", "client_reviews"]) {
        const review = await transaction.get(
          db.collection(name).doc(reference.id),
        );
        if (review.exists) return `linked_${name}`;
      }
      const notification = db
        .collection("notifications")
        .doc(expiryEventId(reference.id));
      const existingNotification = await transaction.get(notification);
      if (
        hooks.guard &&
        existingNotification.exists &&
        (existingNotification.data().recipientId !== latest.data().clientId ||
          existingNotification.data().requestId !== reference.id ||
          existingNotification.data().type !== "jobExpired")
      ) {
        throw new Error("Notification identity mismatch");
      }
      if (hooks.prepare)
        await hooks.prepare(transaction, latest.data(), notification);
      // Recheck after all eligibility/context reads, immediately before writes.
      // Reading the fenced checkpoint also makes takeover conflict at commit.
      if (hooks.guard) await hooks.guard(transaction);
      if (!dryRun) {
        transaction.update(reference, {
          status: "expired",
          expiredAt: FieldValue.serverTimestamp(),
        });
        // A stable event ID prevents duplicates across retries and concurrent runners.
        // Preserve any existing read state rather than replacing the notification.
        if (!existingNotification.exists)
          transaction.set(notification, {
            recipientId: latest.data().clientId,
            recipientRole: "client",
            senderId: "system",
            requestId: reference.id,
            type: "jobExpired",
            title: "Job Post Expired",
            body: `Your job post "${String(latest.data().title || "Untitled request").slice(0, 80)}" has expired because the requested service time has passed and no worker applied. The post is now unavailable. You can review the details and repost it with a new date and time.`,
            read: false,
            createdAt: FieldValue.serverTimestamp(),
          });
      }
      if (!dryRun && hooks.write)
        hooks.write(transaction, latest.data(), notification);
      return dryRun ? "would_expire" : "expired";
    });
  }

  async function runExpiredJobCleanup({
    db,
    dryRun = true,
    now = () => new Date(),
    logger = console,
    startAfterId = null,
    maxPerRun = MAX_PER_RUN,
    pageSize = PAGE_SIZE,
    shouldStop = () => false,
    onProgress = async () => {},
  }) {
    if (
      !Number.isInteger(maxPerRun) ||
      maxPerRun < 1 ||
      maxPerRun > MAX_PER_RUN ||
      !Number.isInteger(pageSize) ||
      pageSize < 1 ||
      pageSize > PAGE_SIZE
    ) {
      throw new RangeError("Invalid cleanup scan limits.");
    }
    const date = now();
    if (!(date instanceof Date) || !Number.isFinite(date.getTime()))
      throw new TypeError("Invalid cleanup clock.");
    const asOf = Timestamp.fromDate(date);
    const result = {
      scanned: 0,
      expiredExamined: 0,
      expired: 0,
      wouldExpire: 0,
      skipped: {},
      errors: 0,
      dryRun,
      nextAfterId: startAfterId,
      status: "partial",
    };
    let cursor = startAfterId;
    try {
      while (result.scanned < maxPerRun) {
        if (shouldStop()) {
          result.status = "interrupted";
          break;
        }
        const limit = Math.min(pageSize, maxPerRun - result.scanned);
        let query = db
          .collection("service_requests")
          .where("status", "==", "pending")
          .orderBy(FieldPath.documentId())
          .limit(limit);
        if (cursor) query = query.startAfter(cursor);
        const page = await query.get();
        if (shouldStop()) {
          result.status = "interrupted";
          break;
        }
        if (page.empty) {
          result.status = "complete";
          break;
        }
        for (const candidate of page.docs) {
          if (shouldStop()) {
            result.status = "interrupted";
            break;
          }
          result.scanned++;
          const data = candidate.data();
          if (
            data.scheduleFrom instanceof Timestamp &&
            data.scheduleFrom.toMillis() < asOf.toMillis()
          ) {
            result.expiredExamined++;
          }
          try {
            const outcome = await inspectAndExpire(
              db,
              candidate.ref,
              asOf,
              dryRun,
            );
            if (outcome === "expired" || outcome === "would_expire") {
              result[outcome === "expired" ? "expired" : "wouldExpire"]++;
              logger.info({
                event: `expired_job_${outcome}`,
                requestId: candidate.id,
              });
            } else {
              result.skipped[outcome] = (result.skipped[outcome] || 0) + 1;
              if (
                [
                  "missing_owner",
                  "missing_or_invalid_start",
                  "invalid_date_range",
                  "inconsistent_schedule",
                  "ambiguous_midnight",
                ].includes(outcome)
              ) {
                logger.warn({
                  event: "expired_job_skipped",
                  requestId: candidate.id,
                  reason: outcome,
                });
              }
            }
            // Save only after this transaction succeeds. A crash between commit and
            // checkpoint replays safely; never advance past a failed transaction.
            await onProgress(candidate.id);
            cursor = candidate.id;
          } catch (error) {
            result.errors++;
            result.status = "failed";
            logger.error({
              event: "expired_job_error",
              requestId: candidate.id,
              code: safeCode(error),
            });
            break;
          }
        }
        if (result.status === "failed" || result.status === "interrupted")
          break;
        if (shouldStop()) {
          result.status = "interrupted";
          break;
        }
        if (page.size < limit) {
          result.status = "complete";
          break;
        }
      }
    } catch (error) {
      result.errors++;
      result.status = "failed";
      logger.error({ event: "expired_job_scan_error", code: safeCode(error) });
    }
    result.nextAfterId = result.status === "complete" ? null : cursor;
    logger[result.status === "failed" ? "error" : "info"]({
      event: `expired_job_batch_${result.status}`,
      ...result,
    });
    return result;
  }

  function startExpiredJobCleanup({
    db,
    env = process.env,
    logger = console,
    run = runExpiredJobCleanup,
    setTimer = setTimeout,
    clearTimer = clearTimeout,
  }) {
    if (env.EXPIRED_JOB_CLEANUP_ENABLED !== "true") return { async stop() {} };
    const dryRun = env.EXPIRED_JOB_CLEANUP_DRY_RUN !== "false";
    let stopped = false;
    let timer;
    let active = null;
    let cursor = null;
    function tick() {
      if (stopped || active) return active;
      active = (async () => {
        try {
          const result = await run({
            db,
            dryRun,
            logger,
            startAfterId: cursor,
            shouldStop: () => stopped,
          });
          cursor = result.nextAfterId;
          if (result.errors > 0 || result.status === "failed") {
            logger.error({
              event: "expired_job_scheduler_failed",
              errors: result.errors,
            });
          }
        } catch (error) {
          logger.error({
            event: "expired_job_scheduler_error",
            code: safeCode(error),
          });
        } finally {
          if (!stopped) timer = setTimer(tick, INTERVAL_MS);
        }
      })();
      const current = active;
      current.then(() => {
        if (active === current) active = null;
      });
      return current;
    }
    logger.info({
      event: "expired_job_scheduler_started",
      intervalMinutes: 30,
      dryRun,
    });
    timer = setTimer(tick, 0);
    return {
      async stop() {
        stopped = true;
        clearTimer(timer);
        await active;
      },
    };
  }

  return {
    eligibility,
    inspectAndExpire,
    runExpiredJobCleanup,
    startExpiredJobCleanup,
    INTERVAL_MS,
    safeCode,
  };
}
module.exports = { createPolicy };
