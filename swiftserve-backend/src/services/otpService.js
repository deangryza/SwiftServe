const crypto = require('node:crypto');

// SMS one-time codes through IPROG SMS (https://www.iprogsms.com/api/v1/documentation).
// The IPROG token never leaves the backend, and the generated code that IPROG
// echoes back in its send response is never returned to the app.
const IPROG_BASE = 'https://www.iprogsms.com/api/v1/otp';
const CODE_MINUTES = 5;
const RESEND_COOLDOWN_MS = 60 * 1000;
const MAX_SENDS_PER_HOUR = 5;
const MAX_WRONG_CODES = 5;
const TOKEN_TTL_MS = 24 * 60 * 60 * 1000;

class OtpError extends Error {
  constructor(status, code, message, extra = {}) {
    super(message);
    Object.assign(this, { status, code, extra });
  }
}

/** Only Philippine mobile numbers: +63 followed by 9XXXXXXXXX. */
const isPhilippineMobile = (phone) => typeof phone === 'string' && /^\+639\d{9}$/.test(phone);
const toIprogNumber = (phone) => phone.slice(1); // '+639…' → '639…'

const phoneKey = (phone) => crypto.createHash('sha256').update(phone).digest('hex');

function secret(env) {
  const value = env.OTP_TOKEN_SECRET;
  if (!value || value.length < 16) throw new Error('OTP_TOKEN_SECRET must be set (at least 16 characters).');
  return value;
}

/** A signed proof that [phone] passed OTP, checked again at profile creation. */
function signPhoneToken(phone, { env = process.env, now = Date.now() } = {}) {
  const payload = Buffer.from(JSON.stringify({ phone, exp: now + TOKEN_TTL_MS })).toString('base64url');
  const signature = crypto.createHmac('sha256', secret(env)).update(payload).digest('base64url');
  return `${payload}.${signature}`;
}

/** Returns the verified phone number, or null when the token is invalid or expired. */
function readPhoneToken(token, { env = process.env, now = Date.now() } = {}) {
  if (typeof token !== 'string' || !token.includes('.')) return null;
  const [payload, signature] = token.split('.');
  const expected = crypto.createHmac('sha256', secret(env)).update(payload).digest('base64url');
  const a = Buffer.from(signature || '');
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try {
    const { phone, exp } = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    return typeof phone === 'string' && typeof exp === 'number' && exp > now ? phone : null;
  } catch (_) {
    return null;
  }
}

async function callIprog(path, body, { env = process.env, fetchImpl = fetch } = {}) {
  const apiToken = env.IPROGSMS_API_TOKEN;
  if (!apiToken) throw new OtpError(503, 'OTP_UNAVAILABLE', 'Phone verification is not configured.');
  let response;
  try {
    response = await fetchImpl(`${IPROG_BASE}/${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ api_token: apiToken, ...body }),
      signal: AbortSignal.timeout(15000),
    });
  } catch (error) {
    console.error('IPROG SMS request failed:', error.cause?.code || error.name);
    throw new OtpError(502, 'OTP_SEND_FAILED', 'The SMS service could not be reached. Try again.');
  }
  let data = {};
  try {
    data = await response.json();
  } catch (_) { /* treated as failure below */ }
  return { ok: response.ok && data.status === 'success', data };
}

/** Sends a new code to [phone], enforcing resend and hourly limits. */
async function sendOtp({ db, phone, env = process.env, fetchImpl = fetch, now = Date.now() }) {
  if (!isPhilippineMobile(phone)) {
    throw new OtpError(400, 'INVALID_PHONE_NUMBER', 'Enter a valid Philippine mobile number (+63 9XX XXX XXXX).');
  }
  // Emergency switch for SMS provider outages: the app skips the code step.
  if (env.PHONE_OTP_REQUIRED === 'false') return { otpSkipped: true };
  const ref = db.collection('otp_requests').doc(phoneKey(phone));
  await db.runTransaction(async (transaction) => {
    const record = (await transaction.get(ref)).data() || {};
    const sends = (Array.isArray(record.sends) ? record.sends : []).filter((at) => at > now - 60 * 60 * 1000);
    const last = sends[sends.length - 1] || 0;
    if (now - last < RESEND_COOLDOWN_MS) {
      throw new OtpError(429, 'OTP_COOLDOWN', 'Please wait before requesting another code.', {
        retryAfterSeconds: Math.ceil((RESEND_COOLDOWN_MS - (now - last)) / 1000),
      });
    }
    if (sends.length >= MAX_SENDS_PER_HOUR) {
      throw new OtpError(429, 'OTP_COOLDOWN', 'Too many codes requested. Try again in an hour.', {
        retryAfterSeconds: Math.ceil((sends[0] + 60 * 60 * 1000 - now) / 1000),
      });
    }
    transaction.set(ref, { sends: [...sends, now], wrongCodes: 0, updatedAt: new Date(now) });
  });
  // No SMS went out, so this attempt must not count against the resend limits.
  const forgetSend = () => db.runTransaction(async (transaction) => {
    const record = (await transaction.get(ref)).data() || {};
    transaction.set(ref, { ...record, sends: (record.sends || []).filter((at) => at !== now) });
  }).catch(() => {});
  let result;
  try {
    result = await callIprog('send_otp', {
      phone_number: toIprogNumber(phone),
      expires_in_minutes: CODE_MINUTES,
      message: `Your SwiftServe code is :otp. It expires in ${CODE_MINUTES} minutes. Do not share it.`,
    }, { env, fetchImpl });
  } catch (error) {
    await forgetSend();
    throw error;
  }
  if (!result.ok) {
    await forgetSend();
    throw new OtpError(502, 'OTP_SEND_FAILED', 'The code could not be sent. Try again.');
  }
  return { expiresInMinutes: CODE_MINUTES };
}

/** Checks [code] for [phone]; returns a signed verification token on success. */
async function verifyOtp({ db, phone, code, env = process.env, fetchImpl = fetch, now = Date.now() }) {
  if (!isPhilippineMobile(phone)) {
    throw new OtpError(400, 'INVALID_PHONE_NUMBER', 'Enter a valid Philippine mobile number (+63 9XX XXX XXXX).');
  }
  if (typeof code !== 'string' || !/^\d{4,8}$/.test(code)) {
    throw new OtpError(400, 'OTP_INVALID', 'Enter the code from the SMS.');
  }
  const ref = db.collection('otp_requests').doc(phoneKey(phone));
  const record = (await ref.get()).data() || {};
  if ((record.wrongCodes || 0) >= MAX_WRONG_CODES) {
    throw new OtpError(429, 'OTP_TOO_MANY_ATTEMPTS', 'Too many wrong codes. Request a new code.');
  }
  const result = await callIprog('verify_otp', { phone_number: toIprogNumber(phone), otp: code }, { env, fetchImpl });
  if (!result.ok) {
    await ref.set({ wrongCodes: (record.wrongCodes || 0) + 1, updatedAt: new Date(now) }, { merge: true });
    throw new OtpError(400, 'OTP_INVALID', 'That code is incorrect or has expired.');
  }
  await ref.set({ wrongCodes: MAX_WRONG_CODES, verifiedAt: new Date(now) }, { merge: true });
  return { verificationToken: signPhoneToken(phone, { env, now }) };
}

module.exports = {
  OtpError,
  isPhilippineMobile,
  toIprogNumber,
  signPhoneToken,
  readPhoneToken,
  sendOtp,
  verifyOtp,
};
