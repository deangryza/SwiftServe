const INELIGIBLE = 'You are not eligible to use SwiftServe. You must be at least 18 years old to create an account.';

// Accept only a real calendar date. Do not parse date-only values in host time.
function validateBirthday(value, now = new Date()) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return { status: 400, code: 'INVALID_BIRTHDAY', message: 'A valid birthday is required (YYYY-MM-DD).' };
  }
  const [year, month, day] = value.split('-').map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (year < 1900 || parsed.getUTCFullYear() !== year || parsed.getUTCMonth() + 1 !== month || parsed.getUTCDate() !== day) {
    return { status: 400, code: 'INVALID_BIRTHDAY', message: 'Select a valid birthday.' };
  }
  const current = new Date(now.getTime() + 8 * 60 * 60 * 1000);
  const cy = current.getUTCFullYear(), cm = current.getUTCMonth() + 1, cd = current.getUTCDate();
  if (value > `${cy}-${String(cm).padStart(2, '0')}-${String(cd).padStart(2, '0')}`) {
    return { status: 400, code: 'INVALID_BIRTHDAY', message: 'Birthday cannot be in the future.' };
  }
  const age = cy - year - ((cm < month || (cm === month && cd < day)) ? 1 : 0);
  return age < 18 ? { status: 403, code: 'UNDERAGE_REGISTRATION', message: INELIGIBLE } : null;
}

module.exports = { validateBirthday, INELIGIBLE };
