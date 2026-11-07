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
router.get('/', requireAdmin.permission('verification.view'), listVerifications);
router.get('/:workerId/image', requireAdmin.permission('verification.view'), getVerificationImage);
router.get('/:workerId', requireAdmin.permission('verification.view'), getVerification);
router.patch('/:workerId', requireAdmin.permission('verification.manage'), updateVerification);

module.exports = router;
