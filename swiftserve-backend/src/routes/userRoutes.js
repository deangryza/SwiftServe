const express = require('express');

const authenticateUser = require('../middleware/authMiddleware');
const {
  addRole,
  createUserProfile,
  switchRole,
  updateProfilePhoto,
} = require('../controllers/userController');

const router = express.Router();

router.post('/profile', authenticateUser, createUserProfile);
router.patch('/profile/photo', authenticateUser, updateProfilePhoto);
router.post('/roles', authenticateUser, addRole);
router.post('/role', authenticateUser, switchRole);

module.exports = router;
