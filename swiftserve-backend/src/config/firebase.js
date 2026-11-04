if (process.env.SWIFTSERVE_LIVE_READ_ONLY === 'true') {
  module.exports = require('./liveAdminReadOnly').getFirebase();
} else if (process.env.SWIFTSERVE_NETLIFY_PILOT === 'true') {
  module.exports = require('./netlifyPilot').initializePilot();
} else if (process.env.SWIFTSERVE_STAGING === 'true') {
  module.exports = require('./stagingFirebase').getStagingFirebase();
} else {
const { applicationDefault, initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');

initializeApp({
  credential: applicationDefault(),
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
