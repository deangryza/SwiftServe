const { describe, test, before, beforeEach, after } = require("node:test");
const assert = require("node:assert/strict");
const { createRequire } = require("node:module");
const path = require("node:path");
const fs = require("node:fs");
const { initializeApp, deleteApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const {
  sweep,
  dispatch,
  retryDue,
  registerDevice,
  CONTROL,
  OUTBOX,
} = require("../src/runtime");
const { inspectAndExpire } = require("../src/expiredJobCleanupService");
const host = process.env.FIRESTORE_EMULATOR_HOST;
if (host && !/^127\.0\.0\.1:\d+$/.test(host))
  throw new Error("Loopback emulator only");
describe("Firebase expiration and push persistence", { skip: !host }, () => {
  const rulesRequire = createRequire(
    path.resolve(__dirname, "../../rules-tests/package.json"),
  );
  const { initializeTestEnvironment, assertFails } = rulesRequire(
    "@firebase/rules-unit-testing",
  );
  const client = rulesRequire("firebase/firestore");
  const projectId = "demo-swiftserve-cleanup";
  const env = {
    FUNCTIONS_EMULATOR: "true",
    FIRESTORE_EMULATOR_HOST: host,
    EXPIRY_EXPECTED_PROJECT: projectId,
    EXPIRY_DATABASE: "(default)",
    EXPIRED_JOB_CLEANUP_ENABLED: "true",
    EXPIRY_METADATA_WRITES_ENABLED: "true",
    EXPIRED_JOB_CLEANUP_DRY_RUN: "false",
    EXPIRY_PUSH_ENABLED: "true",
    EXPIRY_TOKEN_REGISTRATION_ENABLED: "true",
  };
  // These write flags exist ONLY in this explicitly isolated demo emulator fixture.
  const time = Date.parse("2026-10-29T04:00:00Z");
  let app, db, environment;
  const job = (id) => db.collection("service_requests").doc(id);
  const out = (id) => db.collection(OUTBOX).doc(`jobExpired_${id}`);
  const pending = () => ({
    clientId: "client",
    status: "pending",
    title: "Task",
    scheduleFrom: Timestamp.fromMillis(time - 3600000),
  });
  const options = (extra) => ({ db, env, now: () => time, ...extra });
  const device = (token) =>
    registerDevice(
      options({
        uid: "client",
        data: { installationId: "a".repeat(32), token, platform: "android" },
      }),
    );
  async function fixture(id = "a") {
    await job(id).set(pending());
    await sweep(options());
  }
  before(async () => {
    environment = await initializeTestEnvironment({
      projectId,
      firestore: {
        rules: fs.readFileSync(
          path.resolve(__dirname, "../../firestore.rules"),
          "utf8",
        ),
      },
    });
    app = initializeApp({ projectId }, "functions-expiry-tests");
    db = getFirestore(app);
  });
  beforeEach(async () => {
    await environment.clearFirestore();
    await db.collection(CONTROL).doc("settings").set({
      previewEnabled: true,
      expirationEnabled: true,
      pushEnabled: true,
      registrationEnabled: true,
    });
  });
  after(async () => {
    await environment.cleanup();
    await db.terminate();
    await deleteApp(app);
  });
  test("atomic expiration creates one notification/outbox; duplicate sweeps keep read state", async () => {
    await fixture();
    await db.doc("notifications/jobExpired_a").update({ read: true });
    await sweep(options());
    assert.equal((await job("a").get()).data().status, "expired");
    assert.equal(
      (await db.doc("notifications/jobExpired_a").get()).data().read,
      true,
    );
    assert.equal((await db.collection(OUTBOX).get()).size, 1);
  });
  test("durable dry run writes metadata only; metadata gate prevents even leases", async () => {
    await job("a").set(pending());
    assert.equal(
      (
        await sweep(
          options({ env: { ...env, EXPIRY_METADATA_WRITES_ENABLED: "false" } }),
        )
      ).status,
      "metadata_disabled",
    );
    assert.equal((await db.doc(`${CONTROL}/expiration`).get()).exists, false);
    const result = await sweep(
      options({ env: { ...env, EXPIRED_JOB_CLEANUP_DRY_RUN: "true" } }),
    );
    assert.equal(result.affected, 1);
    assert.equal((await job("a").get()).data().status, "pending");
    assert.equal((await db.collection("notifications").get()).empty, true);
    assert.equal((await db.collection(OUTBOX).get()).empty, true);
  });
  test("1001 pending jobs continue across invocations and restart at persisted cursor", async () => {
    for (let offset = 0; offset < 1001; offset += 400) {
      const batch = db.batch();
      for (let n = offset; n < Math.min(offset + 400, 1001); n++)
        batch.set(job(`j${String(n).padStart(4, "0")}`), {
          ...pending(),
          scheduleFrom: Timestamp.fromMillis(time + 3600000),
        });
      await batch.commit();
    }
    const first = await sweep(options());
    assert.equal(first.scanned, 1000);
    assert.equal(first.status, "continuation_required");
    const second = await sweep(options());
    assert.equal(second.scanned, 1);
    assert.equal(second.status, "complete");
    assert.equal(
      (await db.doc(`${CONTROL}/expiration`).get()).data().cursor,
      null,
    );
  });
  test("interrupting a page does not advance beyond unfinished candidates", async () => {
    await job("a").set(pending());
    await job("b").set(pending());
    let calls = 0;
    const result = await sweep(
      options({
        shouldStop: () => calls >= 1,
        inspect: async (...args) => {
          const result = await inspectAndExpire(...args);
          calls++;
          return result;
        },
      }),
    );
    assert.equal(result.status, "interrupted");
    assert.equal((await db.doc(`${CONTROL}/expiration`).get()).data().cursor, "a");
    assert.equal((await job("b").get()).data().status, "pending");
    assert.equal((await sweep(options())).status, "complete");
    assert.equal((await job("b").get()).data().status, "expired");
  });
  test("failed candidate throws, keeps last successful cursor and next invocation recovers", async () => {
    await job("a").set(pending());
    await job("b").set(pending());
    await assert.rejects(
      sweep(
        options({
          inspect: async (...args) => {
            if (args[1].id === "b") throw new Error("network failure");
            return inspectAndExpire(...args);
          },
        }),
      ),
      /network failure/,
    );
    assert.equal(
      (await db.doc(`${CONTROL}/expiration`).get()).data().status,
      "failed",
    );
    assert.equal((await db.doc(`${CONTROL}/expiration`).get()).data().cursor, "a");
    await sweep(options());
    assert.equal((await out("b").get()).exists, true);
  });
  test("concurrent runner cannot acquire live lease; stale runner is fenced after takeover", async () => {
    await job("a").set(pending());
    let reached;
    const ready = new Promise((resolve) => {
      reached = resolve;
    });
    let resume;
    const paused = new Promise((resolve) => {
      resume = resolve;
    });
    const stale = sweep(
      options({
        inspect: async (...args) => {
          reached();
          await paused;
          return inspectAndExpire(...args);
        },
      }),
    );
    await ready;
    assert.equal((await sweep(options())).status, "busy");
    await db
      .doc(`${CONTROL}/expiration`)
      .update({ leaseUntil: Timestamp.fromMillis(0) });
    const replacement = await sweep(options());
    assert.equal(replacement.affected, 1);
    resume();
    await assert.rejects(stale, /Lease lost/);
    assert.equal((await db.collection(OUTBOX).get()).size, 1);
  });
  test("applied, booked, future and legacy jobs remain untouched", async () => {
    for (const id of ["applied", "booked", "future", "legacy"])
      await job(id).set(pending());
    await job("applied")
      .collection("applications")
      .doc("w")
      .set({ status: "rejected" });
    await job("booked").update({ workerId: "w" });
    await job("future").update({
      scheduleFrom: Timestamp.fromMillis(time + 1),
    });
    await job("legacy").set({ clientId: "client", status: "pending" });
    assert.equal((await sweep(options())).affected, 0);
  });
  test("duplicate/concurrent triggers produce one FCM acceptance per token", async () => {
    await fixture();
    await device("token-abcdefghijklmnopqrstuv");
    let sent = 0;
    const send = async () => {
      sent++;
      return "accepted";
    };
    await Promise.all([
      dispatch(options({ eventId: "jobExpired_a", send })),
      dispatch(options({ eventId: "jobExpired_a", send })),
    ]);
    await dispatch(options({ eventId: "jobExpired_a", send }));
    assert.equal(sent, 1);
    assert.equal((await out("a").get()).data().status, "accepted");
  });
  test("partial send failure retries without resending already accepted tokens", async () => {
    await fixture();
    await device("token-abcdefghijklmnopqrstuv");
    await registerDevice(
      options({
        uid: "client",
        data: {
          installationId: "b".repeat(32),
          token: "token-second-abcdefghijklmnop",
          platform: "ios",
        },
      }),
    );
    const calls = {};
    const send = async ({ token }) => {
      calls[token] = (calls[token] || 0) + 1;
      if (token.includes("second") && calls[token] === 1)
        throw Object.assign(new Error("unavailable"), {
          code: "messaging/server-unavailable",
        });
    };
    assert.equal(
      (await dispatch(options({ eventId: "jobExpired_a", send }))).status,
      "pending",
    );
    assert.equal(
      (await out("a").get()).data().lastErrorCode,
      "messaging/server-unavailable",
    );
    await retryDue(options({ send, now: () => time + 1000000 }));
    assert.equal(calls["token-abcdefghijklmnopqrstuv"], 1);
    assert.equal(calls["token-second-abcdefghijklmnop"], 2);
    assert.equal((await out("a").get()).data().status, "accepted");
  });
  test("invalid tokens are removed conditionally and are not retried", async () => {
    await fixture();
    await device("token-abcdefghijklmnopqrstuv");
    await dispatch(
      options({
        eventId: "jobExpired_a",
        send: async () => {
          throw Object.assign(new Error(), {
            code: "messaging/registration-token-not-registered",
          });
        },
      }),
    );
    assert.equal(
      (await db.collection("users/client/push_devices").get()).empty,
      true,
    );
  });
  test("token rebinding prevents old account pushes; revoke cannot remove a newer binding", async () => {
    const token = "token-abcdefghijklmnopqrstuv";
    await fixture();
    await device(token);
    const data = { installationId: "a".repeat(32), token, platform: "android" };
    await registerDevice(options({ uid: "other", data }));
    let sent = 0;
    await dispatch(
      options({ eventId: "jobExpired_a", send: async () => sent++ }),
    );
    assert.equal(sent, 0);
    await registerDevice(
      options({ uid: "client", data: { ...data, revoke: true } }),
    );
    assert.equal(
      (await db.collection("_pushTokenOwners").get()).docs[0].data().uid,
      "other",
    );
  });
  test("client SDKs cannot access tokens, bindings, outbox or control; user cannot spoof UID", async () => {
    await device("token-abcdefghijklmnopqrstuv");
    for (const uid of ["client", "other"]) {
      const viewer = environment.authenticatedContext(uid).firestore();
      for (const target of [
        "users/client/push_devices/" + "a".repeat(32),
        `${CONTROL}/settings`,
        `${OUTBOX}/jobExpired_a`,
        "_pushTokenOwners/hash",
      ]) {
        await assertFails(client.getDoc(client.doc(viewer, target)));
        await assertFails(
          client.setDoc(client.doc(viewer, target), { enabled: true }),
        );
      }
    }
    await assert.rejects(
      registerDevice(options({ uid: null, data: {} })),
      /Authentication/,
    );
  });
  test("stale sending claim is recovered; accepted journal suppresses replay", async () => {
    await fixture();
    await device("token-abcdefghijklmnopqrstuv");
    await out("a").update({
      status: "sending",
      owner: "crashed",
      dueAt: Timestamp.fromMillis(time - 1),
    });
    let sent = 0;
    const send = async () => sent++;
    await retryDue(options({ send }));
    assert.equal(sent, 1);
    await out("a").update({
      status: "sending",
      dueAt: Timestamp.fromMillis(time - 1),
    });
    await retryDue(options({ send }));
    assert.equal(sent, 1);
  });
  test("persistent failure reaches dead letter and scheduled retry stops sending", async () => {
    await fixture();
    await device("token-abcdefghijklmnopqrstuv");
    let sent = 0;
    const send = async () => {
      sent++;
      throw new Error("network");
    };
    for (let n = 0; n < 8; n++) {
      await out("a").update({ dueAt: Timestamp.fromMillis(time) });
      await dispatch(options({ eventId: "jobExpired_a", send }));
    }
    assert.equal((await out("a").get()).data().status, "dead_letter");
    await retryDue(options({ send, now: () => time + 10000000 }));
    assert.equal(sent, 8);
  });
  test("bad event ownership is dead-lettered without sending or blocking healthy events", async () => {
    await fixture();
    await device("token-abcdefghijklmnopqrstuv");
    await db.doc("notifications/jobExpired_a").update({ recipientId: "other" });
    let sent = 0;
    assert.equal(
      (
        await dispatch(
          options({ eventId: "jobExpired_a", send: async () => sent++ }),
        )
      ).status,
      "dead_letter",
    );
    assert.equal(sent, 0);
  });
  test("shutdown requested before scanning releases checkpoint without completing sweep", async () => {
    await job("a").set(pending());
    const result = await sweep(options({ shouldStop: () => true }));
    assert.equal(result.status, "interrupted");
    assert.equal((await job("a").get()).data().status, "pending");
    assert.equal(
      (await db.doc(`${CONTROL}/expiration`).get())
        .data()
        .leaseUntil.toMillis(),
      0,
    );
    await sweep(options());
    assert.equal((await job("a").get()).data().status, "expired");
  });
  test("push emergency gate and dry-run prevent any FCM call", async () => {
    await fixture();
    await device("token-abcdefghijklmnopqrstuv");
    let sent = 0;
    const send = async () => sent++;
    assert.equal(
      (
        await dispatch(
          options({
            eventId: "jobExpired_a",
            send,
            env: { ...env, EXPIRED_JOB_CLEANUP_DRY_RUN: "true" },
          }),
        )
      ).status,
      "disabled",
    );
    await db.doc(`${CONTROL}/settings`).update({ pushEnabled: false });
    await assert.rejects(
      dispatch(options({ eventId: "jobExpired_a", send })),
      /gate closed/,
    );
    assert.equal(sent, 0);
  });
  test("malformed event paths are dead-lettered before document lookup", async () => {
    await fixture();
    await out("a").update({ requestId: null });
    let sent = 0;
    assert.equal(
      (
        await dispatch(
          options({ eventId: "jobExpired_a", send: async () => sent++ }),
        )
      ).status,
      "dead_letter",
    );
    assert.equal(sent, 0);
  });
  test("demo walkthrough fixture expires only isolated emulator data", async () => {
    await db
      .doc("users/client")
      .set({ role: "client", fullName: "Demo client" });
    const { execFile } = require("node:child_process");
    const { promisify } = require("node:util");
    const result = await promisify(execFile)(
      process.execPath,
      [path.join(__dirname, "localFlow.js"), "client", "--demo-write"],
      { env: { ...process.env, FIRESTORE_EMULATOR_HOST: host } },
    );
    assert.match(result.stdout, /demoOnly: true/);
    const jobs = await db.collection("service_requests").get();
    assert.equal(jobs.size, 1);
    assert.equal(jobs.docs[0].data().status, "expired");
    assert.equal((await db.collection("notifications").get()).size, 1);
  });
  test("runtime emergency gate blocks candidate writes and push sends", async () => {
    await job("a").set(pending());
    await db.doc(`${CONTROL}/settings`).update({ expirationEnabled: false });
    await assert.rejects(sweep(options()), /gate closed/);
    assert.equal((await job("a").get()).data().status, "pending");
  });
});
