const crypto = require('node:crypto');

const { db } = require('../config/firebase');
const { normalizeProfilePhoto } = require('../services/profilePhotoService');

const normalizePhoneNumber = (value) => {
  const phoneNumber = String(value || '').replace(/[\s()-]/g, '');
  return /^\+[1-9]\d{7,14}$/.test(phoneNumber) ? phoneNumber : null;
};

const phoneClaimId = (phoneNumber) => crypto
  .createHash('sha256')
  .update(phoneNumber)
  .digest('hex');

class PhoneNumberConflictError extends Error {}

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

    const normalizedPhoneNumber = normalizePhoneNumber(phoneNumber);

    if (!fullName || !email || !['client', 'worker'].includes(role)) {
      return res.status(400).json({
        message: 'Full name, email, and a valid role are required.',
      });
    }
    if (!normalizedPhoneNumber) {
      return res.status(400).json({
        code: 'INVALID_PHONE_NUMBER',
        message: 'A valid international phone number is required.',
      });
    }

    const userRef = db.collection('users').doc(uid);
    const duplicateProfiles = await db.collection('users')
      .where('phoneNumber', '==', normalizedPhoneNumber)
      .limit(5)
      .get();
    if (duplicateProfiles.docs.some((document) => document.id !== uid)) {
      return res.status(409).json({
        code: 'PHONE_NUMBER_IN_USE',
        message: 'This phone number is already registered to another account.',
      });
    }

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
      phoneNumber: normalizedPhoneNumber,
      address: address || '',
      role,
      category: category || '',
      skills: Array.isArray(skills) ? skills : [],
      ...(photo ? { photoBase64: photo } : {}),
      verificationStatus: role === 'worker' ? 'pending' : 'not_required',
      createdAt: new Date(),
      updatedAt: new Date(),
    };

    const claimRef = db.collection('phone_number_claims').doc(
      phoneClaimId(normalizedPhoneNumber),
    );
    try {
      await db.runTransaction(async (transaction) => {
        const claim = await transaction.get(claimRef);
        if (claim.exists && claim.data().uid !== uid) {
          throw new PhoneNumberConflictError();
        }
        transaction.set(claimRef, {
          uid,
          phoneNumber: normalizedPhoneNumber,
          updatedAt: new Date(),
          ...(!claim.exists ? { createdAt: new Date() } : {}),
        });
        transaction.set(userRef, userData);
        if (role === 'worker') {
          transaction.set(db.collection('worker_profiles').doc(uid), {
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
      });
    } catch (error) {
      if (error instanceof PhoneNumberConflictError) {
        return res.status(409).json({
          code: 'PHONE_NUMBER_IN_USE',
          message: 'This phone number is already registered to another account.',
        });
      }
      throw error;
    }

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
