const express = require('express');
const { rateLimit } = require('express-rate-limit');
const { checkRegistrationAvailability } = require('../controllers/registrationAvailabilityController');

const authenticateUser = require('../middleware/authMiddleware');
const {
  addRole,
  createUserProfile,
  switchRole,
  updateProfileAddress,
  updateProfilePhoto,
} = require('../controllers/userController');

const router = express.Router();

router.post('/registration-availability', rateLimit({
  windowMs: 60 * 1000,
  limit: 30,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  message: { message: 'Too many availability checks. Please wait a minute and try again.' },
}), (req, res, next) => req.headers.authorization ? authenticateUser(req, res, next) : next(), checkRegistrationAvailability);

router.post('/profile', authenticateUser, createUserProfile);
router.post('/profile/address', authenticateUser, updateProfileAddress);
router.post('/profile/details', authenticateUser, updateProfileAddress);
router.patch('/profile/photo', authenticateUser, updateProfilePhoto);
router.post('/roles', authenticateUser, addRole);
router.post('/role', authenticateUser, switchRole);

module.exports = router;
