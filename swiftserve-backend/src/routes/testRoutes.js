const express = require('express');
const authenticateUser = require('../middleware/authMiddleware');

const router = express.Router();

router.get('/protected', authenticateUser, (req, res) => {
  res.json({
    message: 'You accessed a protected route!',
    user: req.user,
  });
});

module.exports = router;