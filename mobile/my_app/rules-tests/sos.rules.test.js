const fs = require('node:fs');
const path = require('node:path');
const { after, before, beforeEach, test } = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
} = require('firebase/firestore');

const projectRoot = path.resolve(__dirname, '..');
let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'swiftserve-rules-test',
    firestore: {
      rules: fs.readFileSync(path.join(projectRoot, 'firestore.rules'), 'utf8'),
    },
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'sos_alerts/alert-1'), {
      requestId: 'request-1',
      raisedByUid: 'client-1',
      otherParty: { uid: 'worker-1', phone: '+639172222222' },
      status: 'active',
    });
  });
});

after(async () => {
  await environment.cleanup();
});

test('only the person who raised an SOS alert can read it', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertSucceeds(getDoc(doc(client, 'sos_alerts/alert-1')));
  await assertFails(getDoc(doc(worker, 'sos_alerts/alert-1')));
  await assertFails(
    getDoc(doc(environment.unauthenticatedContext().firestore(), 'sos_alerts/alert-1')),
  );
  await assertFails(getDocs(collection(client, 'sos_alerts')));
});

test('SOS alerts are written only by the backend', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  await assertFails(
    setDoc(doc(client, 'sos_alerts/fake'), {
      raisedByUid: 'client-1',
      status: 'active',
    }),
  );
  await assertFails(
    updateDoc(doc(client, 'sos_alerts/alert-1'), { status: 'resolved' }),
  );
});
