const { test } = require('node:test');
const assert = require('node:assert/strict');
const { documentRetryBaseline } = require('../scripts/benchmarkVerificationPerformance');

// Run this file in its own process: it intentionally instruments the isolated
// service import, and never initializes a Firebase client or an API server.
test('three synthetic transaction callbacks hash the same upload only once', async () => {
  const result = await documentRetryBaseline();
  assert.equal(result.transactionCallbacks, 3);
  assert.equal(result.digestCalls, 1);
  assert.equal(result.networkUsed, false);
  assert.ok(result.fixtureBytes > 4 * 1024 * 1024);
  assert.ok(Number.isFinite(result.digestTotalMs));
});
