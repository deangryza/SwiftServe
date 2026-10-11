const express = require('express');

const authenticateUser = require('../middleware/authMiddleware');
const { createUserProfile, updateProfilePhoto } = require('../controllers/userController');

const router = express.Router();

router.post('/profile', authenticateUser, createUserProfile);
router.patch('/profile/photo', authenticateUser, updateProfilePhoto);

module.exports = router;
