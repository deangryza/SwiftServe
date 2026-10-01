const express = require('express');
const requireAdmin = require('../middleware/adminMiddleware');
const {
  listVerifications,
  getVerification,
  getVerificationImage,
  updateVerification,
} = require('../controllers/adminVerificationController');

const router = express.Router();

router.use(requireAdmin);
router.get('/', listVerifications);
router.get('/:workerId/image', getVerificationImage);
router.get('/:workerId', getVerification);
router.patch('/:workerId', updateVerification);

module.exports = router;
