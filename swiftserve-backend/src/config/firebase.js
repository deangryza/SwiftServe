if (process.env.SWIFTSERVE_LIVE_READ_ONLY === 'true') {
  module.exports = require('./liveAdminReadOnly').getFirebase();
} else if (process.env.SWIFTSERVE_NETLIFY_PILOT === 'true') {
  module.exports = require('./netlifyPilot').initializePilot();
} else if (process.env.SWIFTSERVE_STAGING === 'true') {
  module.exports = require('./stagingFirebase').getStagingFirebase();
} else {
const { applicationDefault, cert, initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');

// Hosts without a key file (Railway) supply the service account as base64.
const encodedServiceAccount = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64;

initializeApp({
  credential: encodedServiceAccount
    ? cert(JSON.parse(Buffer.from(encodedServiceAccount, 'base64').toString('utf8')))
    : applicationDefault(),
  storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
});

const auth = getAuth();
const db = getFirestore();
const storage = getStorage();

module.exports = {
  auth,
  db,
  storage,
};
}
