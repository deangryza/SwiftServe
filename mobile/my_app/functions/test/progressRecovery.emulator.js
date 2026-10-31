const { describe, test, before, beforeEach, after } = require("node:test");
const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { createRequire } = require("node:module");
const path = require("node:path");
const fs = require("node:fs");
const { initializeApp, deleteApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { sweep, dispatch, retryDue, registerDevice } = require("../src/runtime");
const { inspectAndExpire } = require("../src/expiredJobCleanupService");
const host = process.env.FIRESTORE_EMULATOR_HOST;
if (host && !/^127\.0\.0\.1:\d+$/.test(host)) throw new Error("Loopback emulator required");

describe("candidate progress and push metadata recovery", { skip: !host }, () => {
  const req = createRequire(path.resolve(__dirname, "../../rules-tests/package.json"));
  const { initializeTestEnvironment } = req("@firebase/rules-unit-testing");
  const projectId = "demo-swiftserve-progress";
  const epoch = Date.parse("2026-10-29T04:00:00Z");
  // Injected ONLY into the isolated loopback emulator. All sends below are fake.
  const env = { FUNCTIONS_EMULATOR: "true", FIRESTORE_EMULATOR_HOST: host,
    EXPIRY_EXPECTED_PROJECT: projectId, EXPIRY_DATABASE: "(default)",
    EXPIRED_JOB_CLEANUP_ENABLED: "true", EXPIRED_JOB_CLEANUP_DRY_RUN: "false",
    EXPIRY_METADATA_WRITES_ENABLED: "true", EXPIRY_PUSH_ENABLED: "true",
    EXPIRY_TOKEN_REGISTRATION_ENABLED: "true" };
  let app, db, environment;
  const options = extra => ({ db, env, now: () => epoch, ...extra });
  const job = id => db.collection("service_requests").doc(id);
  const out = id => db.collection("_jobExpiryPushOutbox").doc("jobExpired_" + id);
  const pending = () => ({ clientId: "client", status: "pending", title: "Task",
    scheduleFrom: Timestamp.fromMillis(epoch - 3600000) });
  const device = () => registerDevice(options({ uid: "client", data: {
    installationId: "a".repeat(32), token: "fake-emulator-only-token-not-for-fcm", platform: "ios" } }));
  async function fixture(id = "a") { await job(id).set(pending()); await sweep(options()); }
  before(async () => {
    environment = await initializeTestEnvironment({ projectId, firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8") } });
    app = initializeApp({ projectId }, "progress-recovery-tests"); db = getFirestore(app);
  });
  beforeEach(async () => {
    await environment.clearFirestore();
    await db.doc("_jobExpiryControl/settings").set({ previewEnabled: true,
      expirationEnabled: true, pushEnabled: true, registrationEnabled: true });
  });
  after(async () => { await environment.cleanup(); await db.terminate(); await deleteApp(app); });

  test("repeated 2.5-second candidate processing progresses past 96 and completes every eligible job", async () => {
    const batch = db.batch();
    for (let n = 0; n < 201; n++) batch.set(job("j" + String(n).padStart(3, "0")), pending());
    await batch.commit(); let clock = epoch; const visited = []; const runs = [];
    for (let n = 0; n < 3; n++) {
      runs.push(await sweep(options({ env: { ...env, EXPIRED_JOB_CLEANUP_DRY_RUN: "true" },
        now: () => clock, inspect: async (...args) => {
          const result = await inspectAndExpire(...args);
          visited.push(args[1].id); clock += 2500; return result;
        } })));
    }
    assert.deepEqual(runs.map(r => r.status), ["interrupted", "interrupted", "complete"]);
    assert.deepEqual(runs.map(r => r.scanned), [96, 96, 9]);
    assert.equal(new Set(visited).size, 201); assert.equal(visited.length, 201);
    assert.deepEqual(visited, Array.from({ length: 201 }, (_, n) => "j" + String(n).padStart(3, "0")));
    assert.equal((await db.doc("_jobExpiryControl/preview").get()).data().cursor, null);
    assert.equal((await db.collection("notifications").get()).size, 0);
    assert.equal((await db.collection("service_requests").where("status", "==", "pending").get()).size, 201);
  });

  test("takeover resumes inside a page and stale candidate cannot overwrite the new checkpoint", async () => {
    await job("a").set(pending()); await job("b").set(pending());
    let clock = epoch, reached, resume;
    const ready = new Promise(resolve => { reached = resolve; });
    const paused = new Promise(resolve => { resume = resolve; });
    const preview = { ...env, EXPIRED_JOB_CLEANUP_DRY_RUN: "true" };
    const stale = sweep(options({ env: preview, now: () => clock, inspect: async (...args) => {
      if (args[1].id === "b") { reached(); await paused; }
      return inspectAndExpire(...args);
    } }));
    await ready;
    const prior = (await db.doc("_jobExpiryControl/preview").get()).data();
    assert.equal((await sweep(options({ env: preview, now: () => clock }))).status, "busy");
    clock += 120001;
    const replacement = await sweep(options({ env: preview, now: () => clock }));
    const latest = (await db.doc("_jobExpiryControl/preview").get()).data();
    resume(); await assert.rejects(stale, /Lease lost/);
    assert.equal(prior.cursor, "a"); assert.equal(replacement.scanned, 1);
    assert.equal(latest.fence, prior.fence + 1);
    assert.deepEqual((await db.doc("_jobExpiryControl/preview").get()).data(), latest);
  });

  test("APNs hashes the full event ID: shared-prefix IDs differ and retry key stays stable", async () => {
    const ids = ["a".repeat(100) + "1", "a".repeat(100) + "2"];
    for (const id of ids) await job(id).set(pending());
    await sweep(options()); await device(); const sent = [];
    const send = async message => { sent.push(message); if (sent.length === 1) throw new Error("retry"); };
    for (const id of ids) await dispatch(options({ eventId: "jobExpired_" + id, send }));
    await retryDue(options({ send, now: () => epoch + 1000000 }));
    assert.equal(sent.length, 3);
    const keys = sent.map(m => m.apns.headers["apns-collapse-id"]);
    assert.notEqual(keys[0], keys[1]); assert.equal(keys[0], keys[2]);
    for (const [index, key] of keys.entries()) {
      assert.equal(Buffer.byteLength(key, "utf8"), 64);
      assert.match(key, /^[a-f0-9]{64}$/);
      assert.equal(key, createHash("sha256").update(sent[index].data.eventId, "utf8").digest("hex"));
    }
  });

  for (const kind of ["numeric", "missing", "null"]) test(`${kind} dueAt is preserved and dead-lettered before sending`, async () => {
    await fixture(); await device();
    const data = (await out("a").get()).data();
    if (kind === "missing") delete data.dueAt;
    else data.dueAt = kind === "numeric" ? 0 : null;
    await out("a").set(data); let sends = 0;
    assert.equal((await dispatch(options({ eventId: "jobExpired_a", send: async () => sends++ }))).status, "dead_letter");
    const terminal = (await out("a").get()).data();
    assert.equal(terminal.reason, "invalid_retry_metadata"); assert.equal(sends, 0);
    assert.equal(terminal.attempts, 0); assert.equal(terminal.requestId, "a");
    assert.equal(Object.hasOwn(terminal, "dueAt"), Object.hasOwn(data, "dueAt"));
    assert.equal(terminal.dueAt, data.dueAt);
  });

  test("valid future timestamps wait and valid due timestamps deliver", async () => {
    await fixture(); await device(); let sends = 0;
    await out("a").update({ dueAt: Timestamp.fromMillis(epoch + 1) });
    assert.equal((await dispatch(options({ eventId: "jobExpired_a", send: async () => sends++ }))).status, "skipped");
    assert.equal((await dispatch(options({ eventId: "jobExpired_a", now: () => epoch + 1, send: async () => sends++ }))).status, "accepted");
    assert.equal(sends, 1);
  });

  test("bounded metadata recovery finds missing timestamps across pages without blocking a valid send", async () => {
    await fixture("zz_valid"); await device();
    const batch = db.batch();
    for (let n = 0; n < 205; n++) batch.set(out("bad" + String(n).padStart(3, "0")), {
      eventId: "jobExpired_bad" + String(n).padStart(3, "0"), type: "jobExpired",
      recipientId: "client", requestId: "bad" + n, status: "pending", attempts: 0,
    });
    await batch.commit(); let sends = 0; const runs = [];
    for (let n = 0; n < 4; n++) runs.push(await retryDue(options({ send: async () => sends++ })));
    assert.equal(sends, 1); assert.equal((await out("zz_valid").get()).data().status, "accepted");
    assert.equal((await db.collection("_jobExpiryPushOutbox").where("status", "==", "dead_letter").get()).size, 205);
    assert.ok(runs.every(r => r.metadata.scanned <= 100));
    assert.equal(runs[0].status, "continuation_required");
    assert.equal(runs.at(-1).metadata.status, "complete");
    assert.equal(runs.at(-1).status, "complete");
    assert.equal((await db.doc("_jobExpiryControl/pushMetadata").get()).data().cursor, null);
  });

  test("metadata audit respects a live lease, resumes an expired cursor and leaves future events untouched", async () => {
    await fixture();
    await out("a").update({ dueAt: Timestamp.fromMillis(epoch + 1000000) });
    await out("bad").set({ status: "pending", requestId: "bad", attempts: 0 });
    const ref = db.doc("_jobExpiryControl/pushMetadata");
    await ref.set({ version: 1, project: projectId, database: "(default)",
      owner: "crashed", fence: 7, cursor: "jobExpired_a", leaseUntil: Timestamp.fromMillis(epoch + 1) });
    assert.equal((await retryDue(options({ send: async () => assert.fail("Future event") }))).metadata.status, "busy");
    assert.equal((await out("bad").get()).data().status, "pending");
    await Promise.all([0, 1].map(() => retryDue(options({ now: () => epoch + 2,
      send: async () => assert.fail("Future event") }))));
    assert.equal((await out("bad").get()).data().reason, "invalid_retry_metadata");
    assert.equal((await out("a").get()).data().status, "pending");
    assert.ok((await ref.get()).data().fence >= 8);
  });

  test("metadata audit failure retains the last successful candidate and reports failure before resuming", async () => {
    for (const id of ["a", "b"]) await out(id).set({ status: "pending", requestId: id, attempts: 0 });
    let transactions = 0;
    const failing = new Proxy(db, { get(target, key) {
      if (key === "runTransaction") return async (...args) => {
        if (++transactions === 3) throw new Error("Injected transaction failure");
        return target.runTransaction(...args);
      };
      const value = Reflect.get(target, key, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    await assert.rejects(retryDue(options({ db: failing, send: async () => assert.fail("Malformed event") })), /Push recovery failures/);
    const state = (await db.doc("_jobExpiryControl/pushMetadata").get()).data();
    assert.equal(state.status, "failed"); assert.equal(state.cursor, "jobExpired_a");
    assert.equal((await out("a").get()).data().status, "dead_letter");
    assert.equal((await out("b").get()).data().status, "pending");
    await retryDue(options({ send: async () => assert.fail("Malformed event") }));
    assert.equal((await out("b").get()).data().status, "dead_letter");
  });

  test("an in-flight send cannot overwrite metadata quarantine when it later finishes", async () => {
    await fixture(); await device(); let sends = 0;
    await assert.rejects(dispatch(options({ eventId: "jobExpired_a", send: async () => {
      sends++;
      await out("a").update({ dueAt: null }); // Simulate corrupted metadata during a send.
      await retryDue(options({ send: async () => assert.fail("Quarantined event") }));
    } })), /Push lease lost/);
    const data = (await out("a").get()).data();
    assert.equal(data.status, "dead_letter"); assert.equal(data.reason, "invalid_retry_metadata");
    assert.equal((await out("a").collection("deliveries").get()).docs[0].data().status, "accepted");
    await retryDue(options({ send: async () => sends++ })); assert.equal(sends, 1);
  });
});
