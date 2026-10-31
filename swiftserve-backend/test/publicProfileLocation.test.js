const { test } = require('node:test');
const assert = require('node:assert/strict');
const cases = require('../../mobile/my_app/test/fixtures/public_profile_locations.json');
const { publicProfileLocation } = require('../src/services/publicProfileLocation');
for (const [index, fixture] of cases.entries()) {
  test(`public location shared vector ${index + 1}`, () => {
    const result = publicProfileLocation(fixture.input);
    assert.equal(result.location, fixture.expected);
    assert.deepEqual(Object.keys(result).sort(), ['barangay', 'cityMunicipality', 'location']);
    assert.equal(publicProfileLocation(result).location, fixture.expected);
  });
}
test('overlong raw or structured addresses fail closed', () => {
  assert.equal(publicProfileLocation(`Brgy. Ligas, ${'x'.repeat(301)}`).location, '');
  assert.equal(publicProfileLocation({ cityMunicipality: 'x'.repeat(81) }).location, '');
});
