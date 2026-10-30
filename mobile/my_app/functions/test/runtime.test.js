const { test } = require("node:test");
const assert = require("node:assert/strict");
const {
  sweep,
  dispatch,
  retryDue,
  registerDevice,
  validateTarget,
  assertLease,
} = require("../src/runtime");
const { Timestamp } = require("firebase-admin/firestore");

test("bounded event IDs preserve legacy IDs and isolate the hash namespace", () => {
  const { expiryEventId, matchesExpiryEvent, validDocumentId } = require("../src/expiryIdentifiers");
  assert.equal(expiryEventId("ordinary-1"), "jobExpired_ordinary-1");
  assert.equal(expiryEventId("a.place"), "jobExpired.v2.d0c87c1daf9371e098c822afcd2d911dfa86b99eaa29df7eaa69cf548466591a");
  for (const id of ["a.place", "a".repeat(1495), "é".repeat(750)]) {
    const eventId = expiryEventId(id);
    assert.ok(Buffer.byteLength(eventId) < 100);
    assert.equal(matchesExpiryEvent(eventId, id), true);
    assert.equal(matchesExpiryEvent(eventId, "another"), false);
    assert.equal(expiryEventId(id), eventId);
  }
  assert.equal(matchesExpiryEvent("jobExpired_a.place", "a.place"), true);
  for (const id of ["", ".", "..", "x/y", "__reserved__", "é".repeat(751)]) {
    assert.equal(validDocumentId(id), false);
    assert.throws(() => expiryEventId(id));
  }
  assert.notEqual(expiryEventId("a.place"), expiryEventId("a_place"));
});
test("disabled handlers never touch a database or send", async () => {
  const db = new Proxy(
    {},
    {
      get() {
        throw new Error("Database touched");
      },
    },
  );
  assert.equal((await sweep({ db, env: {} })).status, "disabled");
  assert.equal((await dispatch({ db, env: {} })).status, "disabled");
  assert.equal((await retryDue({ db, env: {} })).status, "disabled");
  assert.equal((await retryDue({ db, env: {
    EXPIRY_PUSH_ENABLED: "true", EXPIRED_JOB_CLEANUP_DRY_RUN: "true",
  } })).status, "disabled");
});
test("production preflight rejects wrong project, emulator and named database", () => {
  const env = {
    EXPIRY_EXPECTED_PROJECT: "swiftserve-production",
    EXPIRY_DATABASE: "(default)",
  };
  const db = { projectId: "swiftserve-production", databaseId: "(default)" };
  validateTarget(db, env);
  assert.throws(() => validateTarget({ ...db, projectId: "other" }, env));
  assert.throws(() =>
    validateTarget(db, { ...env, FIRESTORE_EMULATOR_HOST: "localhost:8080" }),
  );
  assert.throws(() => validateTarget({ ...db, databaseId: "named" }, env));
  assert.throws(() =>
    validateTarget(db, { ...env, FUNCTIONS_EMULATOR: "true" }),
  );
});
test("expired/fenced owners cannot mutate a checkpoint", () => {
  const data = { owner: "a", fence: 2, leaseUntil: Timestamp.fromMillis(100) };
  assertLease(data, "a", 2, 99);
  assert.throws(() => assertLease(data, "b", 2, 99));
  assert.throws(() => assertLease(data, "a", 1, 99));
  assert.throws(() => assertLease(data, "a", 2, 100));
});
test("token registration requires authentication even when disabled", async () => {
  await assert.rejects(
    registerDevice({ uid: null, env: {} }),
    /Authentication/,
  );
  await assert.rejects(registerDevice({ uid: "client", env: {} }), /disabled/);
});
test("Function exports are loadable without production connections", () => {
  const handlers = require("../src/index");
  assert.deepEqual(Object.keys(handlers).sort(), [
    "dispatchExpiredJobPush",
    "expireEligibleJobs",
    "queueActivityPush",
    "queueChatPush",
    "recordApplicationRejection",
    "recordBookingUpdate",
    "registerPushDevice",
    "retryExpiredJobPush",
  ]);
});

test("callable rejects unauthenticated requests before creating SDK dependencies", async () => {
  const { registerPushDevice } = require("../src/index");
  await assert.rejects(
    registerPushDevice.run({ data: { uid: "spoofed" } }),
    (error) => error.code === "unauthenticated",
  );
});
