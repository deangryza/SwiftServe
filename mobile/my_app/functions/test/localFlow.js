// Explicit demo-only fixture for the mobile in-app notification/repost walkthrough.
const { initializeApp, deleteApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { sweep } = require("../src/runtime");
async function main() {
  if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || ""))
    throw new Error("Loopback demo emulator required");
  const uid = process.argv[2];
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(uid || ""))
    throw new Error("Pass the existing demo client UID");
  const write = process.argv.includes("--demo-write");
  const projectId = "demo-swiftserve-cleanup";
  const app = initializeApp({ projectId });
  const db = getFirestore(app);
  try {
    const user = (await db.doc(`users/${uid}`).get()).data();
    if (user?.role !== "client")
      throw new Error("Existing demo Client profile required");
    const ref = db.collection("service_requests").doc();
    const past = new Date(Date.now() - 3600000);
    past.setUTCMinutes(17, 0, 0);
    const schedule = Timestamp.fromDate(past);
    await ref.create({
      clientId: uid,
      clientName: user.fullName || "Local client",
      title: "Local expiry walkthrough",
      category: "Other",
      budget: 100,
      description: "Emulator-only test request",
      location: "Online",
      modality: "online",
      status: "pending",
      schedule,
      scheduleFrom: schedule,
      scheduleTo: schedule,
      createdAt: Timestamp.now(),
    });
    await db
      .doc("_jobExpiryControl/settings")
      .set({
        previewEnabled: true,
        expirationEnabled: write,
        pushEnabled: false,
        registrationEnabled: false,
      });
    const result = await sweep({
      db,
      env: {
        FUNCTIONS_EMULATOR: "true",
        FIRESTORE_EMULATOR_HOST: process.env.FIRESTORE_EMULATOR_HOST,
        EXPIRY_EXPECTED_PROJECT: projectId,
        EXPIRY_DATABASE: "(default)",
        EXPIRED_JOB_CLEANUP_ENABLED: "true",
        EXPIRED_JOB_CLEANUP_DRY_RUN: write ? "false" : "true",
        EXPIRY_METADATA_WRITES_ENABLED: "true",
      },
    });
    console.info({
      demoOnly: true,
      requestId: ref.id,
      notificationId: `jobExpired_${ref.id}`,
      ...result,
    });
  } finally {
    await db.terminate();
    await deleteApp(app);
  }
}
main().catch(() => {
  console.error(
    "Demo fixture failed; verify emulator and existing Client UID.",
  );
  process.exitCode = 1;
});
