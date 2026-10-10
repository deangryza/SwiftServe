const express = require('express');
const cors = require('cors');
const multer = require('multer');

require('./config/firebase');

const testRoutes = require('./routes/testRoutes');
const userRoutes = require('./routes/userRoutes');
const adminVerificationRoutes = require('./routes/adminVerificationRoutes');
const verificationRoutes = require('./routes/verificationRoutes');

const app = express();

app.use(cors());
app.use(express.json());

app.get('/', (req, res) => {
  res.json({
    message: 'SwiftServe backend is running!',
  });
});

app.use('/api/test', testRoutes);
app.use('/api/users', userRoutes);
app.use('/api/admin/verifications', adminVerificationRoutes);
app.use('/api/admin', require('./routes/adminDataRoutes'));
app.use('/api', verificationRoutes());

app.use((error, _req, res, _next) => {
  if (error?.code === 'LIMIT_FILE_SIZE') {
    return res.status(413).json({ code: 'IMAGE_TOO_LARGE', message: 'Each image must be 5 MB or smaller.' });
  }
  if (error?.code === 'UNSUPPORTED_IMAGE_TYPE') {
    return res.status(415).json({ code: error.code, message: error.message });
  }
  if (error instanceof multer.MulterError) {
    return res.status(400).json({ code: 'INVALID_UPLOAD', message: 'Invalid multipart upload.' });
  }
  console.error('Unhandled API error:', error);
  return res.status(500).json({ code: 'INTERNAL_ERROR', message: 'The request could not be completed.' });
});

module.exports = app;
