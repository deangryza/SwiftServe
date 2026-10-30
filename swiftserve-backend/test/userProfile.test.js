const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');
const { createCanvas } = require('canvas');

const records = {};
const phoneClaims = {};
const publicProfiles = {};
const workerProfiles = {};
const collections = {
  users: records,
  phone_number_claims: phoneClaims,
  public_profiles: publicProfiles,
  worker_profiles: workerProfiles,
};
const db = {
  collection: name => ({
    doc: id => ({
      name,
      id,
      get: async () => {
        const value = (collections[name] || {})[id];
        return { exists: value !== undefined, data: () => value };
      },
      update: async data => {
        const target = collections[name] || records;
        if (!target[id]) throw Object.assign(new Error('Missing'), { code: 5 });
        target[id] = { ...target[id], ...data };
      },
    }),
    where: (field, _operator, value) => ({
      limit: () => ({
        get: async () => ({
          docs: Object.entries(collections[name] || {})
            .filter(([, data]) => data[field] === value)
            .map(([id, data]) => ({ id, data: () => data })),
        }),
      }),
    }),
  }),
  runTransaction: async callback => {
    const pending = [];
    const transaction = {
      get: async ref => {
        const value = (collections[ref.name] || {})[ref.id];
        return { exists: value !== undefined, data: () => value };
      },
      set: (ref, data, options) => pending.push([ref, data, options]),
    };
    const result = await callback(transaction);
    pending.forEach(([ref, data, options]) => {
      const target = collections[ref.name] || (collections[ref.name] = {});
      target[ref.id] = options?.merge ? { ...target[ref.id], ...data } : data;
    });
    return result;
  },
  batch: () => {
    const pending = [];
    return {
      set: (ref, data, options) => pending.push(['set', ref, data, options]),
      update: (ref, data) => pending.push(['update', ref, data]),
      commit: async () => pending.forEach(([operation, ref, data, options]) => {
        const target = collections[ref.name] || (collections[ref.name] = {});
        if (operation === 'update' || options?.merge) {
          target[ref.id] = { ...target[ref.id], ...data };
        } else {
          target[ref.id] = data;
        }
      }),
    };
  },
};
const configPath = require.resolve('../src/config/firebase');
require.cache[configPath] = { id: configPath, filename: configPath, loaded: true, exports: {
  db, auth: { verifyIdToken: async token => ({ uid: token }) },
} };
const app = express();
app.use(express.json());
app.use('/api/users', require('../src/routes/userRoutes'));
const photo = createCanvas(8, 8).toBuffer('image/png').toString('base64');

test('worker service edits replace removed categories across all profiles and preserve credibility', async () => {
  records.serviceEditor = { role: 'worker', roles: ['client', 'worker'], skills: ['Electrical'], category: 'Electrical', address: 'Private address' };
  publicProfiles.serviceEditor = { skills: ['Electrical'], rating: 4.7, reviewCount: 9, description: 'Existing About' };
  workerProfiles.serviceEditor = { skills: ['Electrical'], verificationStatus: 'verified', photoBase64: 'photo' };
  const services = ['Repair', 'Pet grooming'];
  await request(app).post('/api/users/profile/details').set('Authorization', 'Bearer serviceEditor')
    .send({ fullName: 'Worker', services: [' Repair ', 'Pet grooming', 'repair'], uid: 'other', verificationStatus: 'pending' }).expect(200);
  for (const profile of [records.serviceEditor, publicProfiles.serviceEditor, workerProfiles.serviceEditor]) {
    assert.deepEqual(profile.skills, services);
    assert.equal(profile.category, 'Repair');
  }
  assert.equal(records.serviceEditor.address, 'Private address');
  assert.equal(publicProfiles.serviceEditor.description, 'Existing About');
  assert.equal(publicProfiles.serviceEditor.rating, 4.7);
  assert.equal(publicProfiles.serviceEditor.reviewCount, 9);
  assert.equal(workerProfiles.serviceEditor.verificationStatus, 'verified');
  assert.equal(workerProfiles.serviceEditor.photoBase64, 'photo');
});

test('service edits reject clients, inactive worker roles and missing worker profiles without partial saves', async () => {
  for (const [uid, data, workerExists] of [
    ['serviceClient', { role: 'client' }, false],
    ['serviceInactive', { role: 'client', roles: ['client', 'worker'] }, true],
    ['serviceMissing', { role: 'worker' }, false],
  ]) {
    records[uid] = { ...data, fullName: 'Original' };
    if (workerExists) workerProfiles[uid] = { skills: ['Old'] };
    await request(app).post('/api/users/profile/details').set('Authorization', `Bearer ${uid}`)
      .send({ fullName: 'Changed', description: 'Changed', services: ['Repair'] }).expect(403);
    assert.equal(records[uid].fullName, 'Original');
    assert.equal(publicProfiles[uid], undefined);
    if (!workerExists) assert.equal(workerProfiles[uid], undefined);
  }
});

test('a failed service edit transaction leaves all profile projections unchanged', async () => {
  const uid = 'failedServiceEdit';
  records[uid] = { role: 'worker', fullName: 'Original', skills: ['Electrical'] };
  publicProfiles[uid] = { skills: ['Electrical'], rating: 4.8 };
  workerProfiles[uid] = { skills: ['Electrical'], verificationStatus: 'verified' };
  const originalTransaction = db.runTransaction;
  db.runTransaction = async callback => originalTransaction(async transaction => {
    await callback(transaction);
    throw new Error('Simulated failure before commit');
  });
  try {
    await request(app).post('/api/users/profile/details').set('Authorization', `Bearer ${uid}`)
      .send({ fullName: 'Changed', services: ['Repair', 'Gardening'] }).expect(500);
    for (const profile of [records[uid], publicProfiles[uid], workerProfiles[uid]]) {
      assert.deepEqual(profile.skills, ['Electrical']);
    }
    assert.equal(records[uid].fullName, 'Original');
    assert.equal(publicProfiles[uid].rating, 4.8);
    assert.equal(workerProfiles[uid].verificationStatus, 'verified');
  } finally {
    db.runTransaction = originalTransaction;
  }
});

test('invalid service edits cannot remove all categories or save unresolved Other', async () => {
  records.serviceInvalid = { role: 'worker', skills: ['Repair'] };
  workerProfiles.serviceInvalid = { skills: ['Repair'] };
  for (const services of [[], null, 'Repair', [''], ['Other'], ['x'.repeat(81)], [42]]) {
    await request(app).post('/api/users/profile/details').set('Authorization', 'Bearer serviceInvalid')
      .send({ fullName: 'Worker', services }).expect(400);
  }
  assert.deepEqual(records.serviceInvalid.skills, ['Repair']);
  assert.deepEqual(workerProfiles.serviceInvalid.skills, ['Repair']);
  await request(app).post('/api/users/profile/details').send({ fullName: 'Worker', services: ['Repair'] }).expect(401);
});

test('worker registration preserves every resolved service in private and public profiles', async () => {
  const skills = ['Electrical', 'Repair', 'Pet grooming'];
  await request(app).post('/api/users/profile').set('Authorization', 'Bearer multiServiceWorker')
    .send({ fullName: 'Multi Service', email: 'multi@example.com', phoneNumber: '+639175555551',
      role: 'worker', address: 'Brgy. Ligas, Malolos, Bulacan', category: skills[0], skills }).expect(201);
  for (const data of [records.multiServiceWorker, publicProfiles.multiServiceWorker, workerProfiles.multiServiceWorker]) {
    assert.deepEqual(data.skills, skills);
    assert.equal(data.category, 'Electrical');
    assert.ok(!data.skills.includes('Other'));
  }
});

for (const role of ['client', 'worker']) {
  test(`About edits publish the ${role} description without altering a legacy address`, async () => {
    const uid = `about-${role}`;
    records[uid] = { role, address: 'Unstructured private legacy address', description: 'Old' };
    publicProfiles[uid] = { location: 'Malolos', description: 'Old', rating: 4.8 };
    if (role === 'worker') workerProfiles[uid] = { description: 'Old', verificationStatus: 'verified' };
    await request(app).post('/api/users/profile/details').set('Authorization', `Bearer ${uid}`)
      .send({ fullName: 'Chichay', description: '  Friendly and reliable.  ', uid: 'otherAccount' }).expect(200);
    assert.equal(records[uid].description, 'Friendly and reliable.');
    assert.equal(publicProfiles[uid].description, 'Friendly and reliable.');
    assert.equal(publicProfiles[uid].location, 'Malolos');
    assert.equal(publicProfiles[uid].rating, 4.8);
    assert.equal(records[uid].address, 'Unstructured private legacy address');
    if (role === 'worker') {
      assert.equal(workerProfiles[uid].description, 'Friendly and reliable.');
      assert.equal(workerProfiles[uid].verificationStatus, 'verified');
    } else assert.equal(workerProfiles[uid], undefined);
    await request(app).post('/api/users/profile/details').set('Authorization', `Bearer ${uid}`)
      .send({ fullName: 'Chichay', description: '' }).expect(200);
    assert.equal(publicProfiles[uid].description, '');
  });
}

test('About validates length/type and requires authentication before writing', async () => {
  records.aboutInvalid = { description: 'Keep' };
  await request(app).post('/api/users/profile/details').send({ fullName: 'Name', description: 'New' }).expect(401);
  for (const description of [null, 42, {}, 'x'.repeat(501)]) {
    await request(app).post('/api/users/profile/details').set('Authorization', 'Bearer aboutInvalid')
      .send({ fullName: 'Name', description }).expect(400);
  }
  assert.equal(records.aboutInvalid.description, 'Keep');
  assert.equal(publicProfiles.aboutInvalid, undefined);
});

test('About and address save together; address-only updates preserve About', async () => {
  records.aboutAddress = { role: 'worker' };
  workerProfiles.aboutAddress = { verificationStatus: 'verified' };
  const address = '123 Private Street, Brgy. Ligas, Malolos, Bulacan';
  await request(app).post('/api/users/profile/details').set('Authorization', 'Bearer aboutAddress')
    .send({ fullName: 'Name', address, description: 'x'.repeat(500) }).expect(200);
  assert.equal(records.aboutAddress.address, address);
  assert.equal(publicProfiles.aboutAddress.location, 'Brgy. Ligas, Malolos');
  assert.equal(publicProfiles.aboutAddress.description.length, 500);
  assert.equal(workerProfiles.aboutAddress.description.length, 500);
  await request(app).post('/api/users/profile/address').set('Authorization', 'Bearer aboutAddress')
    .send({ fullName: 'Name', address: 'Brgy. Tikay, Malolos, Bulacan' }).expect(200);
  assert.equal(publicProfiles.aboutAddress.description.length, 500);
});

for (const role of ['client', 'worker']) {
  test(`address edits synchronize the ${role} public area without exposing the residence`, async () => {
    const uid = `address-edit-${role}`;
    records[uid] = { fullName: 'Chichay', role, address: 'Old address', photoBase64: 'photo' };
    publicProfiles[uid] = { location: 'Old area', rating: 4.5, reviewCount: 2, photoBase64: 'photo' };
    workerProfiles[uid] = { location: 'Old area', verificationStatus: 'verified', skills: ['Repairs'] };
    records.otherAccount = { address: 'Unchanged' };
    const payload = { fullName: 'Chichay Updated', address: '123 Example Street, Brgy. Ligas, Malolos, Bulacan',
      uid: 'otherAccount', location: 'Do not trust this', verificationStatus: 'verified' };
    for (let attempt = 0; attempt < 2; attempt++) {
      await request(app).post('/api/users/profile/address').set('Authorization', `Bearer ${uid}`)
        .send(payload).expect(200);
    }
    assert.equal(records[uid].address, payload.address);
    assert.equal(records[uid].fullName, payload.fullName);
    assert.equal(publicProfiles[uid].location, 'Brgy. Ligas, Malolos');
    assert.equal(publicProfiles[uid].barangay, 'Ligas');
    assert.equal(publicProfiles[uid].cityMunicipality, 'Malolos');
    assert.equal(publicProfiles[uid].rating, 4.5);
    assert.equal(publicProfiles[uid].reviewCount, 2);
    assert.equal(publicProfiles[uid].photoBase64, 'photo');
    assert.equal(workerProfiles[uid].location, 'Brgy. Ligas, Malolos');
    assert.equal(workerProfiles[uid].verificationStatus, 'verified');
    assert.deepEqual(workerProfiles[uid].skills, ['Repairs']);
    assert.ok(!JSON.stringify(publicProfiles[uid]).includes('Example Street'));
    assert.ok(!JSON.stringify(workerProfiles[uid]).includes('Example Street'));
    assert.equal(records.otherAccount.address, 'Unchanged');
  });
}

test('address edits require authentication and a safely parsed area', async () => {
  records.invalidAddress = { address: 'Original', role: 'client' };
  const payload = { fullName: 'Name', address: '123 Street, Brgy. Ligas, Malolos, Bulacan' };
  await request(app).post('/api/users/profile/address').send(payload).expect(401);
  for (const address of ['', '123 Street', 'Brgy. Ligas, 123 Street', null]) {
    await request(app).post('/api/users/profile/address').set('Authorization', 'Bearer invalidAddress')
      .send({ ...payload, address }).expect(400);
  }
  assert.equal(records.invalidAddress.address, 'Original');
  assert.equal(publicProfiles.invalidAddress, undefined);
  await request(app).post('/api/users/profile/address').set('Authorization', 'Bearer missingAddressUser')
    .send(payload).expect(404);
  assert.equal(publicProfiles.missingAddressUser, undefined);
});

test('a client address edit does not create a worker account', async () => {
  records.addressOnlyClient = { role: 'client' };
  await request(app).post('/api/users/profile/address').set('Authorization', 'Bearer addressOnlyClient')
    .send({ fullName: 'Client', address: 'Brgy. Ligas, Malolos, Bulacan' }).expect(200);
  assert.equal(workerProfiles.addressOnlyClient, undefined);
});

test('a failed address transaction reports failure and leaves all projections unchanged', async () => {
  const runTransaction = db.runTransaction;
  records.failedAddress = { address: 'Original' };
  publicProfiles.failedAddress = { location: 'Original area' };
  db.runTransaction = async callback => runTransaction(async transaction => {
    await callback(transaction);
    throw new Error('Simulated transaction failure before commit');
  });
  try {
    await request(app).post('/api/users/profile/address').set('Authorization', 'Bearer failedAddress')
      .send({ fullName: 'Client', address: 'Brgy. Ligas, Malolos, Bulacan' }).expect(500);
    assert.equal(records.failedAddress.address, 'Original');
    assert.equal(publicProfiles.failedAddress.location, 'Original area');
  } finally {
    db.runTransaction = runTransaction;
  }
});

for (const [index, role] of ['client', 'worker'].entries()) {
  test(`registration keeps the ${role} address private and publishes locality only`, async () => {
    const uid = `privacy-${role}`;
    const address = '123 Example Street, Brgy. Ligas, Malolos, Bulacan';
    await request(app).post('/api/users/profile').set('Authorization', `Bearer ${uid}`)
      .send({ fullName: 'Privacy User', email: 'privacy@example.com', phoneNumber: `+63917666666${index + 1}`,
        role, address, location: '456 Do Not Publish Road' }).expect(201);
    assert.equal(records[uid].address, address);
    assert.equal(publicProfiles[uid].location, 'Brgy. Ligas, Malolos');
    assert.equal(publicProfiles[uid].barangay, 'Ligas');
    assert.equal(publicProfiles[uid].cityMunicipality, 'Malolos');
    assert.equal(publicProfiles[uid].address, undefined);
    assert.ok(!JSON.stringify(publicProfiles[uid]).includes('Example Street'));
    if (role === 'worker') assert.equal(workerProfiles[uid].location, 'Brgy. Ligas, Malolos');
  });
}

test('role changes redact both public projections without changing private address or credibility', async () => {
  const uid = 'privacy-dual';
  const address = '123 Example Street, Brgy. Ligas, Malolos, Bulacan';
  records[uid] = { fullName: 'Dual Privacy', address, role: 'client', roles: ['client'], verificationStatus: 'verified' };
  publicProfiles[uid] = { location: address };
  await request(app).post('/api/users/roles').set('Authorization', `Bearer ${uid}`)
    .send({ role: 'worker', category: 'Repairs' }).expect(200);
  workerProfiles[uid].rating = 4.8;
  workerProfiles[uid].completedJobs = 9;
  for (const role of ['worker', 'client', 'worker']) {
    await request(app).post('/api/users/role').set('Authorization', `Bearer ${uid}`).send({ role }).expect(200);
    assert.equal(publicProfiles[uid].location, 'Brgy. Ligas, Malolos');
    assert.equal(workerProfiles[uid].location, 'Brgy. Ligas, Malolos');
    assert.equal(records[uid].address, address);
    assert.equal(workerProfiles[uid].rating, 4.8);
    assert.equal(workerProfiles[uid].completedJobs, 9);
    assert.equal(records[uid].verificationStatus, 'verified');
  }
});

test('photo refresh redacts legacy public location using the current private address', async () => {
  const uid = 'privacy-photo';
  const address = '123 Example Street, Brgy. Ligas, Malolos, Bulacan';
  records[uid] = { fullName: 'Privacy Photo', address, role: 'worker' };
  publicProfiles[uid] = { location: address };
  workerProfiles[uid] = { workerId: uid, location: address, rating: 4.5 };
  await request(app).patch('/api/users/profile/photo').set('Authorization', `Bearer ${uid}`).send({ photoBase64: photo }).expect(200);
  assert.equal(publicProfiles[uid].location, 'Brgy. Ligas, Malolos');
  assert.equal(workerProfiles[uid].location, 'Brgy. Ligas, Malolos');
  assert.equal(workerProfiles[uid].rating, 4.5);
  assert.equal(records[uid].address, address);
});

test('unknown legacy address is not echoed into either public projection', async () => {
  const uid = 'privacy-unknown';
  records[uid] = { fullName: 'Legacy Privacy', address: '123 Private Landmark', role: 'client', roles: ['client'] };
  await request(app).post('/api/users/roles').set('Authorization', `Bearer ${uid}`)
    .send({ role: 'worker', category: 'Repairs' }).expect(200);
  assert.equal(publicProfiles[uid].location, '');
  assert.equal(workerProfiles[uid].location, '');
  assert.equal(records[uid].address, '123 Private Landmark');
});

test('identity status survives adding worker access and repeated role changes', async () => {
  for (const status of ['verified', 'pending', 'rejected', 'expired', 'revoked']) {
    const uid = `shared-identity-${status}`;
    records[uid] = { fullName: 'Dual Identity', role: 'client', roles: ['client'], verificationStatus: status };
    await request(app).post('/api/users/roles').set('Authorization', `Bearer ${uid}`)
      .send({ role: 'worker', category: 'Plumbing' }).expect(200);
    assert.equal(records[uid].verificationStatus, status);
    assert.equal(workerProfiles[uid].verificationStatus, status);
    for (const role of ['worker', 'client', 'worker']) {
      await request(app).post('/api/users/role').set('Authorization', `Bearer ${uid}`)
        .send({ role }).expect(200);
      assert.equal(records[uid].verificationStatus, status);
    }
  }
});

test('registration persists a usable thumbnail with the actual name', async () => {
  await request(app).post('/api/users/profile').set('Authorization', 'Bearer alice')
    .send({ fullName: 'Alice Santos', email: 'alice@example.com', phoneNumber: '+639171111111', role: 'client', photoBase64: photo }).expect(201);
  assert.equal(records.alice.fullName, 'Alice Santos');
  assert.equal(Buffer.from(records.alice.photoBase64, 'base64')[0], 0xff);
  assert.equal(publicProfiles.alice.fullName, 'Alice Santos');
  assert.equal(publicProfiles.alice.role, 'client');
  assert.equal(publicProfiles.alice.photoBase64, records.alice.photoBase64);
  assert.equal(publicProfiles.alice.location, '');
  assert.equal(publicProfiles.alice.description, '');
  assert.deepEqual(publicProfiles.alice.skills, []);
});

test('photo updates affect only the authenticated profile and preserve its details', async () => {
  records.bob = { fullName: 'Bob', role: 'client', phoneNumber: '123' };
  await request(app).patch('/api/users/profile/photo').send({ photoBase64: photo }).expect(401);
  await request(app).patch('/api/users/profile/photo').set('Authorization', 'Bearer bob')
    .send({ uid: 'alice', photoBase64: photo }).expect(200);
  assert.equal(records.bob.fullName, 'Bob');
  assert.equal(records.bob.phoneNumber, '123');
  assert.ok(records.bob.photoBase64);
  assert.equal(publicProfiles.bob.fullName, 'Bob');
  assert.equal(publicProfiles.bob.photoBase64, records.bob.photoBase64);
  await request(app).patch('/api/users/profile/photo').set('Authorization', 'Bearer missing')
    .send({ photoBase64: photo }).expect(404);
});

test('invalid and oversized images are rejected before writing a profile', async () => {
  for (const photoBase64 of ['not an image', 'A'.repeat(65540), Buffer.from('fake').toString('base64')]) {
    await request(app).post('/api/users/profile').set('Authorization', 'Bearer invalid')
      .send({ fullName: 'Invalid', email: 'invalid@example.com', phoneNumber: '+639172222222', role: 'client', photoBase64 }).expect(400);
  }
  assert.equal(records.invalid, undefined);
});

test('a phone number can belong to only one account', async () => {
  const first = await request(app).post('/api/users/profile')
    .set('Authorization', 'Bearer phone-owner')
    .send({
      fullName: 'Phone Owner',
      email: 'owner@example.com',
      phoneNumber: '+63 917 333 3333',
      role: 'client',
    });
  assert.equal(first.status, 201);

  const duplicate = await request(app).post('/api/users/profile')
    .set('Authorization', 'Bearer other-user')
    .send({
      fullName: 'Other User',
      email: 'other@example.com',
      phoneNumber: '+639173333333',
      role: 'worker',
    });
  assert.equal(duplicate.status, 409);
  assert.equal(duplicate.body.code, 'PHONE_NUMBER_IN_USE');
  assert.equal(records['other-user'], undefined);

  const retry = await request(app).post('/api/users/profile')
    .set('Authorization', 'Bearer phone-owner')
    .send({
      fullName: 'Phone Owner',
      email: 'owner@example.com',
      phoneNumber: '+639173333333',
      role: 'client',
    });
  assert.equal(retry.status, 201);
});

test('profile creation rejects missing or invalid phone numbers', async () => {
  for (const phoneNumber of ['', '09171234567', '+123']) {
    const response = await request(app).post('/api/users/profile')
      .set('Authorization', `Bearer invalid-phone-${phoneNumber}`)
      .send({
        fullName: 'Invalid Phone',
        email: 'invalid-phone@example.com',
        phoneNumber,
        role: 'client',
      });
    assert.equal(response.status, 400);
    assert.equal(response.body.code, 'INVALID_PHONE_NUMBER');
  }
});

test('registration records the starting role in roles', async () => {
  await request(app).post('/api/users/profile').set('Authorization', 'Bearer starter')
    .send({ fullName: 'Starter', email: 'starter@example.com', phoneNumber: '+639174444444', role: 'client' }).expect(201);
  assert.deepEqual(records.starter.roles, ['client']);
  assert.deepEqual(publicProfiles.starter.roles, ['client']);
});

test('a client can add the worker role without losing profile data', async () => {
  records.dual = {
    fullName: 'Dual User', role: 'client', phoneNumber: '+639175555555',
    address: 'Cebu', photoBase64: 'photo', verificationStatus: 'not_required',
  };
  publicProfiles.dual = { fullName: 'Dual User', role: 'client', photoBase64: 'photo' };

  await request(app).post('/api/users/roles').send({ role: 'worker', category: 'Plumbing' }).expect(401);
  await request(app).post('/api/users/roles').set('Authorization', 'Bearer dual')
    .send({ role: 'worker' }).expect(400);
  await request(app).post('/api/users/roles').set('Authorization', 'Bearer dual')
    .send({ role: 'worker', category: 'Plumbing' }).expect(200);

  assert.equal(records.dual.role, 'client');
  assert.deepEqual(records.dual.roles, ['client', 'worker']);
  assert.equal(records.dual.phoneNumber, '+639175555555');
  assert.equal(records.dual.photoBase64, 'photo');
  assert.equal(records.dual.verificationStatus, 'pending');
  assert.deepEqual(records.dual.skills, ['Plumbing']);
  assert.equal(publicProfiles.dual.photoBase64, 'photo');
  assert.deepEqual(publicProfiles.dual.roles, ['client', 'worker']);
  assert.equal(workerProfiles.dual.category, 'Plumbing');
  assert.equal(workerProfiles.dual.verificationStatus, 'pending');

  const again = await request(app).post('/api/users/roles').set('Authorization', 'Bearer dual')
    .send({ role: 'worker', category: 'Plumbing' });
  assert.equal(again.status, 409);
  assert.equal(again.body.code, 'ROLE_ALREADY_ADDED');
});

test('adding a role keeps an existing worker verification', async () => {
  records.verifiedworker = { fullName: 'Vera', role: 'worker', verificationStatus: 'verified' };
  await request(app).post('/api/users/roles').set('Authorization', 'Bearer verifiedworker')
    .send({ role: 'client' }).expect(200);
  assert.deepEqual(records.verifiedworker.roles, ['worker', 'client']);
  assert.equal(records.verifiedworker.verificationStatus, 'verified');
});

test('switching is limited to roles the account owns', async () => {
  records.switcher = { fullName: 'Switcher', role: 'client', roles: ['client', 'worker'] };
  records.single = { fullName: 'Single', role: 'client' };

  const denied = await request(app).post('/api/users/role').set('Authorization', 'Bearer single')
    .send({ role: 'worker' });
  assert.equal(denied.status, 403);
  assert.equal(denied.body.code, 'ROLE_NOT_ADDED');
  assert.equal(records.single.role, 'client');

  await request(app).post('/api/users/role').set('Authorization', 'Bearer switcher')
    .send({ role: 'admin' }).expect(400);
  await request(app).post('/api/users/role').set('Authorization', 'Bearer switcher')
    .send({ role: 'worker' }).expect(200);
  assert.equal(records.switcher.role, 'worker');
  assert.equal(publicProfiles.switcher.role, 'worker');
  assert.deepEqual(publicProfiles.switcher.roles, ['client', 'worker']);

  await request(app).post('/api/users/role').set('Authorization', 'Bearer switcher')
    .send({ role: 'client' }).expect(200);
  assert.equal(records.switcher.role, 'client');
  await request(app).post('/api/users/role').set('Authorization', 'Bearer nobody')
    .send({ role: 'client' }).expect(404);
});
