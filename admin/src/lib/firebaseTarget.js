// Public configuration only. This does not grant server-side authority.
export function validateFirebaseTarget(env) {
  const emulator = env.VITE_USE_FIREBASE_EMULATORS === 'true';
  const project = env.VITE_FIREBASE_PROJECT_ID;
  if (env.VITE_ENABLE_NATIONAL_ID_MOCK === 'true') {
    const mockUrl = new URL(env.VITE_API_BASE_URL || '');
    if (!env.DEV || !emulator || project !== 'demo-swiftserve-cleanup' ||
        env.VITE_FIRESTORE_DATABASE_ID !== '(default)' || mockUrl.protocol !== 'http:' ||
        !['127.0.0.1', 'localhost'].includes(mockUrl.hostname) || mockUrl.port !== '5007' ||
        mockUrl.username || mockUrl.password || mockUrl.pathname !== '/' || mockUrl.search || mockUrl.hash) {
      throw new Error('Identity mock review requires the exact demo project, default database and loopback API on port 5007.');
    }
    return { project, emulator };
  }
  if (emulator) {
    if (!env.DEV || !['demo-swiftserve-admin-management', 'demo-swiftserve-netlify'].includes(project)) {
      throw new Error('Admin emulator mode requires the isolated development demo project.');
    }
  } else if (project !== 'swiftserve-production') {
    throw new Error('Admin cloud configuration must explicitly target swiftserve-production.');
  }
  const url = new URL(env.VITE_API_BASE_URL || 'http://localhost:5000');
  const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if (url.username || url.password || (!loopback && url.protocol !== 'https:') || !['http:', 'https:'].includes(url.protocol)) {
    throw new Error('Admin API requires HTTPS or a local loopback development server.');
  }
  if (!emulator && loopback && url.port === '5003') {
    throw new Error('Production Auth must not send tokens to the demo backend on port 5003.');
  }
  return { project, emulator };
}
