import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canOpen, canAccess, landingPage } from '../src/lib/adminAccess.js';

test('only explicit Super Admin can open management, including by direct URL', () => {
  assert.equal(canOpen({ fullAccess: true, isSuperAdmin: true }, '/dashboard/administrators'), true);
  for (const access of [null, { fullAccess: true }, { permissions: ['admin.manage', 'users.view'] }]) {
    assert.equal(canOpen(access, '/dashboard/administrators'), false);
  }
});
test('regular administrator navigation and landing respect assigned modules', () => {
  const access = { permissions: ['reports.view'] };
  assert.equal(canOpen(access, '/dashboard/reports'), true);
  assert.equal(canOpen(access, '/dashboard/users'), false);
  assert.equal(canOpen(access, '/dashboard'), false);
  assert.equal(canAccess(access, 'reports.manage'), false);
  assert.equal(landingPage(access), '/dashboard/reports');
  assert.equal(landingPage({ permissions: [] }), '/dashboard/profile');
});
test('legacy full access retains existing modules without management promotion', () => {
  assert.equal(canOpen({ fullAccess: true }, '/dashboard/verification'), true);
  assert.equal(canOpen({ fullAccess: true }, '/dashboard/sos'), true);
  assert.equal(canOpen(null, '/dashboard/profile'), false);
  assert.equal(canOpen({ permissions: [] }, '/dashboard/profile'), true);
});
