require('dotenv').config();
const app = require('./src/app');
const { isFaceCheckDisabled, loadModels } = require('./src/services/faceVerificationService');

const PORT = process.env.PORT || 5000;

const start = async () => {
  // TODO(face-verification): temporary bypass skips the heavy FaceAPI model
  // load. Re-enable automatically once DISABLE_FACE_VERIFICATION is unset.
  if (isFaceCheckDisabled()) {
    console.log('Face verification disabled — skipping model load (ID-only mode).');
  } else {
    await loadModels();
  }
  return app.listen(PORT, () => {
    console.log(`SwiftServe backend listening on port ${PORT}`);
  });
};

if (require.main === module) {
  start().catch((error) => {
    console.error(`SwiftServe backend failed to start: ${error.message}`);
    process.exit(1);
  });
}

module.exports = { start };
