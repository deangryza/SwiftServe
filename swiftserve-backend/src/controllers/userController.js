const { db } = require('../config/firebase');

const createUserProfile = async (req, res) => {
  try {
    const uid = req.user.uid;

    const {
      fullName,
      email,
      phoneNumber,
      address,
      role,
    } = req.body;

    if (!fullName || !email || !role) {
      return res.status(400).json({
        message: 'Full name, email, and role are required.',
      });
    }

    const userRef = db.collection('users').doc(uid);

    const userData = {
      uid,
      fullName,
      email,
      phoneNumber: phoneNumber || '',
      address: address || '',
      role,
      verificationStatus: role === 'worker' ? 'not_required' : 'not_required',
      createdAt: new Date(),
      updatedAt: new Date(),
    };

    await userRef.set(userData);

    return res.status(201).json({
      message: 'User profile created successfully.',
      user: userData,
    });
  } catch (error) {
    console.error('Create user profile error:', error);

    return res.status(500).json({
      message: 'Failed to create user profile.',
    });
  }
};

module.exports = {
  createUserProfile,
};