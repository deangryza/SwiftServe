require('dotenv').config();
const app = require('./src/app');
const { loadModels } = require('./src/services/faceVerificationService');

const PORT = process.env.PORT || 5000;

const start = async () => {
  await loadModels();
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
