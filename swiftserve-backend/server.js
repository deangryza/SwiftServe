require('dotenv').config();
const app = require('./src/app');
const { loadModels } = require('./src/services/faceVerificationService');

const PORT = process.env.PORT || 5000;

const start = async () => {
  // API replicas must not bypass the dedicated worker's preflight and disk lock.
  if (process.env.EXPIRED_JOB_CLEANUP_ENABLED === 'true') {
    throw new Error('Run cleanup only through npm run jobs:cleanup; disable it in API instances.');
  }
  await loadModels();
  const server = app.listen(PORT, () => {
    console.log(`SwiftServe backend listening on port ${PORT}`);
  });
  return server;
};

if (require.main === module) {
  start().catch((error) => {
    console.error(`SwiftServe backend failed to start: ${error.message}`);
    process.exit(1);
  });
}

module.exports = { start };
