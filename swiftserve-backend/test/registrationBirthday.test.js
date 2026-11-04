const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validateBirthday, INELIGIBLE } = require('../src/services/registrationBirthday');
const now = new Date('2026-11-02T16:00:00Z');
test('eighteenth birthday uses month/day and Philippine midnight', () => {
  assert.equal(validateBirthday('2008-11-03', now), null);
  assert.equal(validateBirthday('2008-11-04', now).message, INELIGIBLE);
  assert.equal(validateBirthday('2008-11-03', new Date(now.getTime() - 1)).status, 403);
  assert.equal(validateBirthday('2007-12-31', now), null);
});
test('malformed, absent, normalized and future birthdays fail closed', () => {
  for (const value of [undefined, null, 20000101, '', '2000-2-01', '2000-01-01T00:00:00Z', '2007-02-29', '2000-13-01', '1899-01-01', '2026-11-04']) {
    assert.equal(validateBirthday(value, now).status, 400, String(value));
  }
});
test('leap-day births reach eighteen on March 1 in nonleap years', () => {
  assert.equal(validateBirthday('2008-02-29', new Date('2026-02-28T04:00Z')).status, 403);
  assert.equal(validateBirthday('2008-02-29', new Date('2026-03-01T04:00Z')), null);
});
