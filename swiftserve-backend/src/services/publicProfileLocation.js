// Keep aligned with Flutter's public_profile_location.dart; shared vectors test
// both implementations. Unknown legacy formats fail closed, never echo raw text.
const barangayPrefix = /^(?:brgy\.?|barangay)\s+/i;
const cityPrefix = /^(?:city\s*\/\s*municipality\s*:|(?:city|municipality)\s+of\s+)/i;
const citySuffix = /\s+(?:city|municipality)$/i;
const details = /\b(?:street|st|road|rd|avenue|ave|house|lot|block|blk|unit|building|bldg|subdivision|subd|village|villas|landmark|sitio|purok|phase|tower|condo|floor|compound|near|beside|across|highway|hwy|lane|drive|barangay|brgy)\b/i;
const cityName = value => typeof value === 'string' ? value.trim().replace(cityPrefix, '').replace(citySuffix, '').trim() : '';
const barangayName = value => typeof value === 'string' ? value.trim().replace(barangayPrefix, '').trim() : '';
function name(value, digits = false) {
  if (!value || value.length > 80 || /[\r\n\x00-\x1f]/.test(value) || details.test(value)) return '';
  const pattern = digits
    ? /^[A-Za-z0-9\u00C0-\u024F\u1E00-\u1EFF][A-Za-z0-9\u00C0-\u024F\u1E00-\u1EFF .'-]*$/
    : /^[A-Za-z\u00C0-\u024F\u1E00-\u1EFF][A-Za-z\u00C0-\u024F\u1E00-\u1EFF .'-]*$/;
  if (!pattern.test(value)) return '';
  return value.replace(/\s+/g, ' ');
}
function fields(barangay = '', cityMunicipality = '') {
  return { location: cityMunicipality ? (barangay ? `Brgy. ${barangay}, ${cityMunicipality}` : cityMunicipality) : '',
    barangay: cityMunicipality ? barangay : '', cityMunicipality };
}
function publicProfileLocation(value) {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    if (Object.hasOwn(value, 'cityMunicipality')) {
      return fields(name(barangayName(value.barangay), true), name(cityName(value.cityMunicipality)));
    }
    value = value.location;
  }
  if (typeof value !== 'string' || value.length > 300 || /[\r\n\x00-\x1f]/.test(value)) return fields();
  const parts = value.split(',').map(part => part.trim());
  for (let i = 0; i + 1 < parts.length; i++) {
    if (!barangayPrefix.test(parts[i])) continue;
    const city = name(cityName(parts[i + 1]));
    if (city) return fields(name(barangayName(parts[i]), true), city);
  }
  for (const part of parts) {
    if (!cityPrefix.test(part) && !citySuffix.test(part)) continue;
    const city = name(cityName(part));
    if (city) return fields('', city);
  }
  return fields();
}
module.exports = { publicProfileLocation };
