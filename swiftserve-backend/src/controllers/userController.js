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
      category,
      skills,
    } = req.body;

    if (!fullName || !email || !['client', 'worker'].includes(role)) {
      return res.status(400).json({
        message: 'Full name, email, and a valid role are required.',
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
      category: category || '',
      skills: Array.isArray(skills) ? skills : [],
      verificationStatus: role === 'worker' ? 'pending' : 'not_required',
      createdAt: new Date(),
      updatedAt: new Date(),
    };

    const batch = db.batch();
    batch.set(userRef, userData);
    if (role === 'worker') {
      batch.set(db.collection('worker_profiles').doc(uid), {
        workerId: uid,
        fullName,
        category: category || '',
        skills: Array.isArray(skills) ? skills : [],
        location: address || '',
        verificationStatus: 'pending',
        rating: 0,
        completedJobs: 0,
        createdAt: new Date(),
        updatedAt: new Date(),
      });
    }
    await batch.commit();

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
