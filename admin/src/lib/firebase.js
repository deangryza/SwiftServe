import { getApp, getApps, initializeApp } from 'firebase/app';
import { connectAuthEmulator, getAuth } from 'firebase/auth';
import { validateFirebaseTarget } from './firebaseTarget';

validateFirebaseTarget(import.meta.env);

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
};

const app = getApps().length ? getApp() : initializeApp(firebaseConfig);

export const auth = getAuth(app);
if (import.meta.env.VITE_USE_FIREBASE_EMULATORS === 'true') {
  const identityDemo = import.meta.env.VITE_ENABLE_NATIONAL_ID_MOCK === 'true' && firebaseConfig.projectId === 'demo-swiftserve-cleanup';
  if (!import.meta.env.DEV || (!identityDemo && !['demo-swiftserve-admin-management', 'demo-swiftserve-netlify'].includes(firebaseConfig.projectId)) || app.options.projectId !== firebaseConfig.projectId) {
    throw new Error('Admin Auth emulator mode is restricted to the local demo development build.');
  }
  if (!auth.emulatorConfig) connectAuthEmulator(auth, identityDemo ? 'http://127.0.0.1:9099' : firebaseConfig.projectId === 'demo-swiftserve-netlify' ? 'http://127.0.0.1:9599' : 'http://127.0.0.1:9499');
}
