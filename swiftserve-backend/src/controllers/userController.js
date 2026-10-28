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

const ROLES = ['client', 'worker'];

// Accounts created before dual roles only have `role`.
const rolesOf = (user) => {
  const roles = Array.isArray(user.roles) ? user.roles.filter((role) => ROLES.includes(role)) : [];
  if (roles.length) return roles;
  return [user.role === 'worker' ? 'worker' : 'client'];
};

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
      description,
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
    const publicProfileRef = db.collection('public_profiles').doc(uid);
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
      roles: [role],
      category: category || '',
      skills: Array.isArray(skills) ? skills : [],
      description: description || '',
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
        transaction.set(publicProfileRef, {
          uid,
          fullName,
          role,
          roles: [role],
          photoBase64: photo || '',
          location: address || '',
          description: description || '',
          category: role === 'worker' ? category || '' : '',
          skills: role === 'worker' && Array.isArray(skills) ? skills : [],
          createdAt: new Date(),
          updatedAt: new Date(),
        });
        if (role === 'worker') {
          transaction.set(db.collection('worker_profiles').doc(uid), {
            workerId: uid,
            fullName,
            category: category || '',
            skills: Array.isArray(skills) ? skills : [],
            location: address || '',
            description: description || '',
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
    const userRef = db.collection('users').doc(req.user.uid);
    const userSnapshot = await userRef.get();
    if (!userSnapshot.exists) {
      return res.status(404).json({ message: 'Profile not found.' });
    }
    const user = userSnapshot.data();
    const updatedAt = new Date();
    const batch = db.batch();
    batch.update(userRef, { photoBase64, updatedAt });
    batch.set(db.collection('public_profiles').doc(req.user.uid), {
      uid: req.user.uid,
      fullName: user.fullName || 'SwiftServe user',
      role: user.role === 'worker' ? 'worker' : 'client',
      photoBase64,
      updatedAt,
    }, { merge: true });
    await batch.commit();
    return res.status(200).json({ message: 'Profile photo updated.' });
  } catch (error) {
    if (error.code === 5) return res.status(404).json({ message: 'Profile not found.' });
    console.error('Update profile photo error:', error);
    return res.status(500).json({ message: 'Failed to save profile photo.' });
  }
};

class RoleRequestError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const addRole = async (req, res) => {
  const uid = req.user.uid;
  const { role, category, description } = req.body;
  if (!ROLES.includes(role)) {
    return res.status(400).json({ message: 'A valid role is required.' });
  }
  const trimmedCategory = String(category || '').trim();
  if (role === 'worker' && !trimmedCategory) {
    return res.status(400).json({ message: 'Choose a service category to work in.' });
  }

  const userRef = db.collection('users').doc(uid);
  const publicProfileRef = db.collection('public_profiles').doc(uid);
  const workerProfileRef = db.collection('worker_profiles').doc(uid);
  try {
    const roles = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(userRef);
      if (!snapshot.exists) {
        throw new RoleRequestError(404, 'PROFILE_NOT_FOUND', 'Profile not found.');
      }
      const user = snapshot.data();
      const currentRoles = rolesOf(user);
      if (currentRoles.includes(role)) {
        throw new RoleRequestError(409, 'ROLE_ALREADY_ADDED', `This account is already a ${role}.`);
      }
      const nextRoles = [...currentRoles, role];
      const updatedAt = new Date();

      if (role === 'client') {
        transaction.set(userRef, { roles: nextRoles, updatedAt }, { merge: true });
        transaction.set(publicProfileRef, { roles: nextRoles, updatedAt }, { merge: true });
        return nextRoles;
      }

      const skills = [trimmedCategory];
      const workerDescription = description || user.description || '';
      const verificationStatus = !user.verificationStatus || user.verificationStatus === 'not_required'
        ? 'pending'
        : user.verificationStatus;
      transaction.set(userRef, {
        roles: nextRoles,
        category: trimmedCategory,
        skills,
        description: workerDescription,
        verificationStatus,
        updatedAt,
      }, { merge: true });
      transaction.set(publicProfileRef, {
        roles: nextRoles,
        category: trimmedCategory,
        skills,
        description: workerDescription,
        updatedAt,
      }, { merge: true });
      transaction.set(workerProfileRef, {
        workerId: uid,
        fullName: user.fullName || 'SwiftServe user',
        category: trimmedCategory,
        skills,
        location: user.address || '',
        description: workerDescription,
        verificationStatus,
        rating: 0,
        completedJobs: 0,
        createdAt: updatedAt,
        updatedAt,
      });
      return nextRoles;
    });
    return res.status(200).json({ message: `${role} role added.`, roles });
  } catch (error) {
    if (error instanceof RoleRequestError) {
      return res.status(error.status).json({ code: error.code, message: error.message });
    }
    console.error('Add role error:', error);
    return res.status(500).json({ message: 'Failed to add role.' });
  }
};

const switchRole = async (req, res) => {
  const { role } = req.body;
  if (!ROLES.includes(role)) {
    return res.status(400).json({ message: 'A valid role is required.' });
  }
  try {
    const userRef = db.collection('users').doc(req.user.uid);
    const snapshot = await userRef.get();
    if (!snapshot.exists) {
      return res.status(404).json({ message: 'Profile not found.' });
    }
    const roles = rolesOf(snapshot.data());
    if (!roles.includes(role)) {
      return res.status(403).json({
        code: 'ROLE_NOT_ADDED',
        message: `Add the ${role} role to this account first.`,
      });
    }
    const updatedAt = new Date();
    const batch = db.batch();
    batch.update(userRef, { role, roles, updatedAt });
    batch.set(db.collection('public_profiles').doc(req.user.uid), {
      role,
      roles,
      updatedAt,
    }, { merge: true });
    await batch.commit();
    return res.status(200).json({ message: `Switched to ${role}.`, role, roles });
  } catch (error) {
    console.error('Switch role error:', error);
    return res.status(500).json({ message: 'Failed to switch role.' });
  }
};

module.exports = {
  addRole,
  createUserProfile,
  rolesOf,
  switchRole,
  updateProfilePhoto,
};
