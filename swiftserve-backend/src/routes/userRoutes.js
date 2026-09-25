const express = require('express');

const authenticateUser = require('../middleware/authMiddleware');
const { createUserProfile } = require('../controllers/userController');

const router = express.Router();

router.post('/profile', authenticateUser, createUserProfile);

module.exports = router;