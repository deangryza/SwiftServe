const crypto = require('node:crypto');

const { db } = require('../config/firebase');
const { normalizeProfilePhoto } = require('../services/profilePhotoService');
const { publicProfileLocation } = require('../services/publicProfileLocation');

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
          ...publicProfileLocation(address),
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
            ...publicProfileLocation(address),
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

// Only the authenticated account can update its private address and public area.
// Keep these projections atomic: never report a private-only address save.
const updateProfileAddress = async (req, res) => {
  const fullName = typeof req.body.fullName === 'string' ? req.body.fullName.trim() : '';
  const hasAddress = Object.hasOwn(req.body, 'address');
  const hasDescription = Object.hasOwn(req.body, 'description');
  const hasServices = Object.hasOwn(req.body, 'services');
  const address = typeof req.body.address === 'string' ? req.body.address.trim() : '';
  const location = hasAddress ? publicProfileLocation(address) : {};
  if (!fullName || fullName.length > 120 || (!hasAddress && !hasDescription && !hasServices)
    || (hasAddress && (!location.barangay || !location.cityMunicipality))) {
    return res.status(400).json({ message: 'Enter your name and an address containing barangay and city / municipality.' });
  }
  if (hasDescription && (typeof req.body.description !== 'string' || req.body.description.length > 500)) {
    return res.status(400).json({ message: 'About must be text of 500 characters or fewer.' });
  }
  const description = hasDescription ? { description: req.body.description.trim() } : {};
  let services = [];
  if (hasServices) {
    if (!Array.isArray(req.body.services) || req.body.services.length === 0 || req.body.services.length > 50
      || req.body.services.some(value => typeof value !== 'string' || !value.trim() || value.trim().length > 80 || value.trim().toLowerCase() === 'other')) {
      return res.status(400).json({ message: 'Select at least one service and specify the actual service for Other.' });
    }
    for (const value of req.body.services) {
      const name = value.trim();
      if (!services.some(item => item.toLowerCase() === name.toLowerCase())) services.push(name);
    }
  }
  const serviceFields = hasServices ? { category: services[0], skills: services } : {};
  try {
    const uid = req.user.uid;
    const userRef = db.collection('users').doc(uid);
    const publicRef = db.collection('public_profiles').doc(uid);
    const workerRef = db.collection('worker_profiles').doc(uid);
    const found = await db.runTransaction(async transaction => {
      const userSnapshot = await transaction.get(userRef);
      const workerSnapshot = await transaction.get(workerRef);
      if (!userSnapshot.exists) return false;
      const user = userSnapshot.data();
      if (hasServices && (user.role !== 'worker' || !rolesOf(user).includes('worker') || !workerSnapshot.exists)) {
        return 'forbidden';
      }
      const updatedAt = new Date();
      transaction.set(userRef, { fullName, ...(hasAddress ? { address } : {}), ...description, ...serviceFields, updatedAt }, { merge: true });
      transaction.set(publicRef, {
        uid, fullName,
        role: user.role === 'worker' ? 'worker' : 'client',
        ...location, ...description, ...serviceFields, updatedAt,
      }, { merge: true });
      if (workerSnapshot.exists) {
        transaction.set(workerRef, { ...location, ...description, ...serviceFields, updatedAt }, { merge: true });
      }
      return true;
    });
    if (!found) return res.status(404).json({ message: 'Profile not found.' });
    if (found === 'forbidden') return res.status(403).json({ message: 'Service categories can only be edited from an existing worker account in Worker mode.' });
    return res.status(200).json({ message: 'Profile and public location updated.' });
  } catch (_) {
    // Do not log the request body or private residential address.
    return res.status(500).json({ message: 'Failed to update profile. Please try again.' });
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
    const location = publicProfileLocation(user.address);
    const workerRef = db.collection('worker_profiles').doc(req.user.uid);
    const worker = rolesOf(user).includes('worker') ? await workerRef.get() : null;
    const updatedAt = new Date();
    const batch = db.batch();
    batch.update(userRef, { photoBase64, updatedAt });
    batch.set(db.collection('public_profiles').doc(req.user.uid), {
      uid: req.user.uid,
      fullName: user.fullName || 'SwiftServe user',
      role: user.role === 'worker' ? 'worker' : 'client',
      photoBase64,
      ...location,
      updatedAt,
    }, { merge: true });
    if (worker?.exists) batch.set(workerRef, { ...location, updatedAt }, { merge: true });
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
      const location = publicProfileLocation(user.address);
      const existingWorker = await transaction.get(workerProfileRef);
      if (currentRoles.includes(role)) {
        throw new RoleRequestError(409, 'ROLE_ALREADY_ADDED', `This account is already a ${role}.`);
      }
      const nextRoles = [...currentRoles, role];
      const updatedAt = new Date();

      if (role === 'client') {
        transaction.set(userRef, { roles: nextRoles, updatedAt }, { merge: true });
        transaction.set(publicProfileRef, { roles: nextRoles, ...location, updatedAt }, { merge: true });
        if (existingWorker.exists) transaction.set(workerProfileRef, { ...location, updatedAt }, { merge: true });
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
        ...location,
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
        ...location,
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
    const user = snapshot.data();
    const roles = rolesOf(user);
    if (!roles.includes(role)) {
      return res.status(403).json({
        code: 'ROLE_NOT_ADDED',
        message: `Add the ${role} role to this account first.`,
      });
    }
    const updatedAt = new Date();
    const location = publicProfileLocation(user.address);
    const workerRef = db.collection('worker_profiles').doc(req.user.uid);
    const worker = roles.includes('worker') ? await workerRef.get() : null;
    const batch = db.batch();
    batch.update(userRef, { role, roles, updatedAt });
    batch.set(db.collection('public_profiles').doc(req.user.uid), {
      role,
      roles,
      ...location,
      updatedAt,
    }, { merge: true });
    if (worker?.exists) batch.set(workerRef, { ...location, updatedAt }, { merge: true });
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
  updateProfileAddress,
  updateProfilePhoto,
};
