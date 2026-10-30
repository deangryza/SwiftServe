// Local HTTP transport only. No real Firebase Auth or FCM endpoints are used.
const { test } = require("node:test");
const assert = require("node:assert/strict");
const host = process.env.FUNCTIONS_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (host !== "127.0.0.1:5001" || authHost !== "127.0.0.1:9099")
  throw new Error("Explicit loopback Functions/Auth emulators required");
const url = `http://${host}/demo-swiftserve-cleanup/us-central1/registerPushDevice`;
test("emulated callable rejects anonymous registration", async () => {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ data: { uid: "spoofed" } }),
  });
  assert.equal(response.status, 401);
  assert.equal((await response.json()).error.status, "UNAUTHENTICATED");
});
test("authenticated caller cannot bypass disabled registration", async () => {
  const signup = await fetch(
    `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-only`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        email: `local-${Date.now()}@example.test`,
        password: "emulator-fixture-only",
        returnSecureToken: true,
      }),
    },
  );
  assert.equal(signup.status, 200);
  const { idToken } = await signup.json();
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({ data: { uid: "spoofed" } }),
  });
  // App Check is enforced in deployed code. Emulators may bypass attestation;
  // either rejection still proves that no registration was enabled.
  assert.ok([401, 412].includes(response.status));
  assert.ok(
    ["UNAUTHENTICATED", "FAILED_PRECONDITION"].includes(
      (await response.json()).error.status,
    ),
  );
});
