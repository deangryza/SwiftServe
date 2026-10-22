const { test } = require('node:test');
const request = require('supertest');

const configPath = require.resolve('../src/config/firebase');
require.cache[configPath] = { id: configPath, filename: configPath, loaded: true, exports: {
  db: {}, auth: {}, bucket: {},
} };
const app = require('../src/app');

test('health endpoint responds without authentication', async () => {
  await request(app).get('/api/health').expect(200, { ok: true });
});
