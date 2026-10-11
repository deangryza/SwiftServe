const { db } = require('../config/firebase');
const { normalizeProfilePhoto } = require('../services/profilePhotoService');

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
      photoBase64,
    } = req.body;

    if (!fullName || !email || !['client', 'worker'].includes(role)) {
      return res.status(400).json({
        message: 'Full name, email, and a valid role are required.',
      });
    }

    const userRef = db.collection('users').doc(uid);

    let photo;
    if (photoBase64 !== undefined) {
      try {
        photo = await normalizeProfilePhoto(photoBase64);
      } catch (_) {
        return res.status(400).json({ message: 'Choose a valid, small JPEG or PNG profile photo.' });
      }
    }

    const userData = {
      uid,
      fullName,
      email,
      phoneNumber: phoneNumber || '',
      address: address || '',
      role,
      category: category || '',
      skills: Array.isArray(skills) ? skills : [],
      ...(photo ? { photoBase64: photo } : {}),
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

const updateProfilePhoto = async (req, res) => {
  let photoBase64;
  try {
    photoBase64 = await normalizeProfilePhoto(req.body.photoBase64);
  } catch (_) {
    return res.status(400).json({ message: 'Choose a valid, small JPEG or PNG profile photo.' });
  }
  try {
    await db.collection('users').doc(req.user.uid).update({ photoBase64, updatedAt: new Date() });
    return res.status(200).json({ message: 'Profile photo updated.' });
  } catch (error) {
    if (error.code === 5) return res.status(404).json({ message: 'Profile not found.' });
    console.error('Update profile photo error:', error);
    return res.status(500).json({ message: 'Failed to save profile photo.' });
  }
};

module.exports = {
  createUserProfile,
  updateProfilePhoto,
};
