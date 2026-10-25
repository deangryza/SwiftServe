const { test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const configPath = require.resolve('../src/config/firebase');
require.cache[configPath] = { id: configPath, filename: configPath, loaded: true, exports: {
  db: {},
  auth: {
    verifyIdToken: async (token) => {
      if (token !== 'good-token') throw new Error('bad token');
      return { uid: 'client-1' };
    },
  },
  bucket: {},
} };
process.env.ORS_API_KEY = 'test-ors-key';
const app = require('../src/app');

let fetchCalls;
let fetchImpl;
global.fetch = async (...args) => {
  fetchCalls.push(args);
  return fetchImpl(...args);
};

const orsResponse = (coordinates) => ({
  ok: true,
  status: 200,
  json: async () => ({
    features: [{
      geometry: { coordinates },
      properties: { summary: { distance: 1234.5, duration: 321.1 } },
    }],
  }),
});

beforeEach(() => {
  fetchCalls = [];
  fetchImpl = async () => orsResponse([[121.0, 14.5], [121.01, 14.51], [121.02, 14.52]]);
});

const postErrand = (body, token = 'good-token') => {
  const req = request(app).post('/api/routes/errand');
  if (token) req.set('Authorization', `Bearer ${token}`);
  return req.send(body);
};

test('rejects requests without a token', async () => {
  await postErrand({ from: { lat: 14.5, lng: 121 }, to: { lat: 14.52, lng: 121.02 } }, null)
    .expect(401);
  assert.equal(fetchCalls.length, 0);
});

test('rejects bad coordinates', async () => {
  await postErrand({ from: { lat: 'x', lng: 121 }, to: { lat: 14.52, lng: 121.02 } }).expect(400);
  await postErrand({ from: { lat: 95, lng: 121 }, to: { lat: 14.52, lng: 121.02 } }).expect(400);
  await postErrand({ to: { lat: 14.52, lng: 121.02 } }).expect(400);
  // Manila to Cebu is well over 200 km.
  await postErrand({ from: { lat: 14.5995, lng: 120.9842 }, to: { lat: 10.3157, lng: 123.8854 } })
    .expect(400);
  assert.equal(fetchCalls.length, 0);
});

test('returns the road route with points flipped to [lat, lng]', async () => {
  const res = await postErrand({ from: { lat: 14.5, lng: 121 }, to: { lat: 14.52, lng: 121.02 } })
    .expect(200);
  assert.deepEqual(res.body, {
    points: [[14.5, 121.0], [14.51, 121.01], [14.52, 121.02]],
    distanceMeters: 1234.5,
    durationSeconds: 321.1,
  });
  assert.equal(fetchCalls.length, 1);
  const [url, options] = fetchCalls[0];
  assert.match(url, /driving-car\/geojson$/);
  assert.equal(options.headers.Authorization, 'test-ors-key');
  assert.deepEqual(JSON.parse(options.body), { coordinates: [[121, 14.5], [121.02, 14.52]] });
});

test('returns 502 when ORS fails', async () => {
  fetchImpl = async () => ({ ok: false, status: 500, json: async () => ({}) });
  const res = await postErrand({ from: { lat: 14.6, lng: 121.1 }, to: { lat: 14.62, lng: 121.12 } })
    .expect(502);
  assert.equal(res.body.code, 'ROUTING_UNAVAILABLE');
});

test('caches identical requests', async () => {
  const body = { from: { lat: 14.7, lng: 121.2 }, to: { lat: 14.72, lng: 121.22 } };
  await postErrand(body).expect(200);
  await postErrand(body).expect(200);
  assert.equal(fetchCalls.length, 1);
});
