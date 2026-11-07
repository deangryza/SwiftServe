// INACTIVE design/preparation module: not imported by Firebase initialization.
// Wiring this into a build requires a separately reviewed staging-only entry point.
const PROJECT = 'swiftserve-staging-2026';
const DATABASE = '(default)';

function httpsOrigin(value) {
  if (typeof value !== 'string' || !value) throw new Error('Staging requires an approved HTTPS origin.');
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password || url.pathname !== '/' ||
      url.search || url.hash || url.port || ['localhost','127.0.0.1','[::1]'].includes(url.hostname) ||
      value !== url.origin) throw new Error('Staging requires an exact HTTPS origin without a path or credentials.');
  return url.origin;
}

export function validateHostedStagingTarget(env, { approvedOrigin } = {}) {
  if (env.VITE_SWIFTSERVE_TARGET !== 'hosted-staging') throw new Error('Explicit hosted-staging target required.');
  if (env.VITE_FIREBASE_PROJECT_ID !== PROJECT) throw new Error('Staging rejects production and unknown Firebase projects.');
  if (env.VITE_FIRESTORE_DATABASE_ID !== DATABASE) throw new Error('Staging requires the explicit default Firestore database.');
  if (env.VITE_USE_FIREBASE_EMULATORS !== 'false') throw new Error('Hosted staging requires an explicit non-emulator configuration.');
  if (env.VITE_FIREBASE_AUTH_DOMAIN !== `${PROJECT}.firebaseapp.com`) throw new Error('Staging Auth domain must match the staging project.');
  const origin = httpsOrigin(approvedOrigin);
  if (httpsOrigin(env.VITE_API_BASE_URL) !== origin) throw new Error('Staging API must use the separately approved site origin.');
  return Object.freeze({ project: PROJECT, database: DATABASE, emulator: false, apiBaseUrl: origin });
}
