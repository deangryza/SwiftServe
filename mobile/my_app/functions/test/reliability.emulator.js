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
describe("expiration reliability and recovery", { skip: !host }, () => {
  const req = createRequire(path.resolve(__dirname, "../../rules-tests/package.json"));
  const { initializeTestEnvironment } = req("@firebase/rules-unit-testing");
  const client = req("firebase/firestore");
  const projectId = "demo-swiftserve-reliability";
  const epoch = Date.parse("2026-10-29T04:00:00Z");
  // Write/send gates are injected ONLY into a loopback demo; all sends are fake.
  const env = { FUNCTIONS_EMULATOR: "true", FIRESTORE_EMULATOR_HOST: host,
    EXPIRY_EXPECTED_PROJECT: projectId, EXPIRY_DATABASE: "(default)",
    EXPIRED_JOB_CLEANUP_ENABLED: "true", EXPIRED_JOB_CLEANUP_DRY_RUN: "false",
    EXPIRY_METADATA_WRITES_ENABLED: "true", EXPIRY_PUSH_ENABLED: "true",
    EXPIRY_TOKEN_REGISTRATION_ENABLED: "true" };
  let app, db, environment;
  const options = extra => ({ db, env, now: () => epoch, ...extra });
  const job = id => db.collection("service_requests").doc(id);
  const event = id => db.collection("_jobExpiryPushOutbox").doc(id);
  const pending = () => ({ clientId: "client", status: "pending", title: "Audit task",
    scheduleFrom: Timestamp.fromMillis(epoch - 3600000) });
  const hashed = id => "jobExpired.v2." + createHash("sha256").update(id, "utf8").digest("hex");
  async function allowedCreate(id) {
    const viewer = environment.authenticatedContext("client").firestore();
    const time = client.Timestamp.fromMillis(epoch - 3600000);
    await client.setDoc(client.doc(viewer, "service_requests", id), {
      clientId: "client", clientName: "Client", title: "Audit task", category: "Other",
      budget: 100, description: "Emulator only", location: "Online", modality: "online",
      status: "pending", schedule: time, scheduleFrom: time, scheduleTo: time,
      createdAt: client.serverTimestamp(),
    });
  }
  async function device() {
    await registerDevice(options({ uid: "client", data: { installationId: "a".repeat(32),
      token: "fake-emulator-token-not-for-fcm", platform: "android" } }));
  }
  async function fixture() { await job("a").set(pending()); await sweep(options()); await device(); }
  before(async () => {
    environment = await initializeTestEnvironment({ projectId, firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8") } });
    app = initializeApp({ projectId }, "expiry-reliability-tests"); db = getFirestore(app);
  });
  beforeEach(async () => {
    await environment.clearFirestore();
    await db.doc("_jobExpiryControl/settings").set({ previewEnabled: true,
      expirationEnabled: true, pushEnabled: true, registrationEnabled: true });
  });
  after(async () => { await environment.cleanup(); await db.terminate(); await deleteApp(app); });

  test("rule-valid long, dotted and Unicode IDs expire atomically without starving later jobs", async () => {
    const ids = ["a".repeat(1495), "b.place", "café", "zz_valid"];
    for (const id of ids) await allowedCreate(id);
    assert.equal((await sweep(options())).affected, 4);
    await sweep(options());
    for (const id of ids) {
      const eid = id === "zz_valid" ? "jobExpired_zz_valid" : hashed(id);
      assert.equal((await job(id).get()).data().status, "expired");
      assert.equal((await event(eid).get()).data().requestId, id);
      assert.equal((await db.collection("notifications").doc(eid).get()).data().requestId, id);
      assert.ok(Buffer.byteLength(eid) < 1500);
    }
    assert.equal((await db.collection("notifications").get()).size, 4);
    assert.notEqual(hashed("b.place"), hashed("café"));
  });

  test("legacy dotted IDs dispatch; 100 permanently malformed events become terminal and valid work resumes", async () => {
    await device();
    for (let n = 0; n < 100; n++) {
      const id = "invalid." + String(n).padStart(3, "0");
      await event(id).set({ status: "pending", dueAt: Timestamp.fromMillis(epoch - 1),
        requestId: "missing", recipientId: "client", eventId: id, type: "jobExpired", attempts: 0 });
    }
    await job("z.place").set({ ...pending(), status: "expired" });
    const eid = "jobExpired_z.place";
    const context = { requestId: "z.place", recipientId: "client", type: "jobExpired" };
    await db.collection("notifications").doc(eid).set(context);
    await event(eid).set({ ...context, eventId: eid, status: "pending", attempts: 0,
      dueAt: Timestamp.fromMillis(epoch) });
    let sends = 0;
    await retryDue(options({ send: async () => sends++ }));
    await retryDue(options({ send: async () => sends++ }));
    await retryDue(options({ send: async () => sends++ }));
    assert.equal(sends, 1);
    assert.equal((await event(eid).get()).data().status, "accepted");
    const dead = await db.collection("_jobExpiryPushOutbox").where("status", "==", "dead_letter").get();
    assert.equal(dead.size, 100);
    assert.equal(dead.docs[0].data().reason, "invalid_event_context");
    assert.equal(dead.docs[0].data().attempts, 0);
  });

  test("hashed events deliver the exact original long ID once", async () => {
    const id = "a".repeat(1495); await allowedCreate(id); await sweep(options()); await device();
    const sent = [];
    await dispatch(options({ eventId: hashed(id), send: async message => sent.push(message.data) }));
    await retryDue(options({ send: async message => sent.push(message.data) }));
    assert.equal(sent.length, 1); assert.equal(sent[0].requestId, id);
  });

  test("100 valid dotted jobs do not starve an ordinary event during recovery", async () => {
    const batch = db.batch();
    for (let n = 0; n < 100; n++) batch.set(job("bad." + String(n).padStart(3, "0")), pending());
    batch.set(job("zz_valid"), pending()); await batch.commit();
    await sweep(options()); await device(); let sends = 0;
    for (let n = 0; n < 3; n++) await retryDue(options({ send: async () => sends++ }));
    assert.equal(sends, 101);
    assert.equal((await event("jobExpired_zz_valid").get()).data().status, "accepted");
    assert.equal((await db.collection("_jobExpiryPushOutbox").where("status", "==", "dead_letter").get()).size, 0);
  });

  test("slow preview renews fenced lease, checkpoints and resumes without overlapping candidate work", async () => {
    const batch = db.batch();
    for (let n = 0; n < 101; n++) batch.set(job("j" + String(n).padStart(3, "0")), pending());
    await batch.commit(); let clock = epoch; let active = false; let calls = 0;
    const preview = { ...env, EXPIRED_JOB_CLEANUP_DRY_RUN: "true" };
    const slow = options({ env: preview, now: () => clock, maxDocuments: 100,
      inspect: async (...args) => {
        assert.equal(active, false); active = true;
        assert.equal((await sweep(options({ env: preview, now: () => clock }))).status, "busy");
        const result = await inspectAndExpire(...args); clock += 1600; calls++; active = false; return result;
      } });
    assert.equal((await sweep(slow)).status, "continuation_required");
    assert.equal(calls, 100);
    assert.equal((await db.doc("_jobExpiryControl/preview").get()).data().cursor, "j099");
    const resumed = await sweep(options({ env: preview, now: () => clock }));
    assert.equal(resumed.scanned, 1); assert.equal(resumed.status, "complete");
    assert.equal((await db.collection("notifications").get()).size, 0);
  });

  test("a candidate crossing lease expiry cannot write; takeover fences stale work and resume completes", async () => {
    await job("a").set(pending()); let clock = epoch;
    await assert.rejects(sweep(options({ now: () => clock, inspect: async (...args) => {
      const hooks = args[4]; const prepare = hooks.prepare;
      hooks.prepare = async (...values) => { await prepare(...values); clock += 120001; };
      return inspectAndExpire(...args);
    } })), /Lease lost/);
    assert.equal((await job("a").get()).data().status, "pending");
    assert.equal((await db.collection("notifications").get()).size, 0);
    assert.equal((await sweep(options({ now: () => clock }))).status, "complete");
    assert.equal((await job("a").get()).data().status, "expired");
  });

  for (const attempts of [7, 8]) test(`interrupted claim at ${attempts} respects ceiling under concurrent repeated recovery`, async () => {
    await fixture();
    await event("jobExpired_a").update({ status: "sending", attempts, owner: "crashed",
      dueAt: Timestamp.fromMillis(epoch - 1) });
    let sends = 0; const send = async () => sends++;
    await Promise.all([retryDue(options({ send })), retryDue(options({ send }))]);
    await retryDue(options({ send, now: () => epoch + 10000000 }));
    const data = (await event("jobExpired_a").get()).data();
    assert.equal(data.attempts, 8); assert.equal(sends, attempts === 7 ? 1 : 0);
    assert.equal(data.status, attempts === 7 ? "accepted" : "dead_letter");
    if (attempts === 8) assert.equal(data.reason, "attempt_limit");
  });
});
