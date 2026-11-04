const express = require('express');
const cors = require('cors');
const multer = require('multer');

require('./config/firebase');

const testRoutes = require('./routes/testRoutes');
const userRoutes = require('./routes/userRoutes');
const adminVerificationRoutes = require('./routes/adminVerificationRoutes');
const verificationRoutes = require('./routes/verificationRoutes');

const app = express();

if (process.env.SWIFTSERVE_NETLIFY_PILOT === 'true') {
  app.disable('x-powered-by');
  app.use(cors({ origin(origin, callback) {
    const allowed = ['http://localhost:8888', 'http://127.0.0.1:8888', 'http://127.0.0.1:5181'];
    if (!origin || allowed.includes(origin)) return callback(null, true);
    return callback(Object.assign(new Error('Origin is not allowed.'), { status: 403 }));
  } }));
  app.use('/api/admin', require('express-rate-limit').rateLimit({ windowMs: 60000, limit: 120, standardHeaders: 'draft-8', legacyHeaders: false }));
} else app.use(cors());
app.use(express.json());
if (process.env.SWIFTSERVE_STAGING === 'true') {
  app.use(require('./middleware/stagingDiagnostics').requestDiagnostics);
}

app.get('/', (req, res) => {
  res.json({
    message: 'SwiftServe backend is running!',
  });
});

app.get('/api/health', (req, res) => {
  if (process.env.SWIFTSERVE_STAGING === 'true') {
    return res.json({ ok: true, environment: 'staging', projectId: 'swiftserve-staging-2026', databaseId: '(default)' });
  }
  res.json({ ok: true });
});

if (process.env.SWIFTSERVE_STAGING === 'true') {
  app.use('/api', require('./middleware/stagingDiagnostics').verifyStagingAppCheck());
  app.get('/api/staging/session', require('./middleware/authMiddleware'), async (req, res) => {
    try {
      const { db } = require('./config/firebase');
      const profile = await db.collection('users').doc(req.user.uid).get();
      res.json({ ok: true, projectId: 'swiftserve-staging-2026', databaseId: '(default)',
        profileExists: profile.exists, role: profile.exists ? profile.data().role : null });
    } catch (error) {
      require('./config/stagingFirebase').diagnostic('firestore', error);
      res.status(503).json({ code: 'STAGING_FIRESTORE_UNAVAILABLE', message: 'Staging Firestore could not be reached.' });
    }
  });
}

app.use('/api/test', testRoutes);
app.use('/api/users', userRoutes);
// Disabled by default and guarded BEFORE authentication/database reads. Mock
// records cannot change existing worker verification or production profiles.
const identityRouters = require('./routes/nationalIdRoutes').createIdentityRouters({
  ...require('./config/firebase'), admin: require('./middleware/adminMiddleware'),
});
app.use('/api/identity', identityRouters.user);
app.use('/api/admin/identity', identityRouters.review);
app.use('/api/admin/verifications', adminVerificationRoutes);
app.use('/api/admin/administrators', require('./routes/adminManagementRoutes'));
app.use('/api/admin', require('./routes/adminDataRoutes'));
app.use('/api/routes', require('./routes/routeRoutes'));
app.use('/api/sos', require('./routes/sosRoutes'));
app.use('/api', verificationRoutes());
const documentSuitability = require('./routes/documentSuitabilityRoutes');
app.use('/api/verification/document', documentSuitability.user);
app.use('/api/admin/document-reviews', documentSuitability.review);
if (process.env.SWIFTSERVE_NETLIFY_PILOT === 'true') app.use('/api/pilot', require('./routes/netlifyPilotRoutes'));

app.use((error, _req, res, _next) => {
  if (process.env.SWIFTSERVE_NETLIFY_PILOT === 'true' && error.status === 403) return res.status(403).json({ code: 'PILOT_REQUEST_REJECTED' });
  if (error?.code === 'LIMIT_FILE_SIZE') {
    return res.status(413).json({ code: 'IMAGE_TOO_LARGE', message: 'Each image must be 5 MB or smaller.' });
  }
  if (error?.code === 'UNSUPPORTED_IMAGE_TYPE') {
    return res.status(415).json({ code: error.code, message: error.message });
  }
  if (error instanceof multer.MulterError) {
    return res.status(400).json({ code: 'INVALID_UPLOAD', message: 'Invalid multipart upload.' });
  }
  if (process.env.SWIFTSERVE_STAGING === 'true') require('./config/stagingFirebase').diagnostic('api', error);
  else console.error('Unhandled API error:', error);
  return res.status(500).json({ code: 'INTERNAL_ERROR', message: 'The request could not be completed.' });
});

module.exports = app;
