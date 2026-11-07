const { validatePilot } = require('../../src/config/netlifyPilot');
let wrapped;
exports.handler = async (event, context) => {
  try { validatePilot(); } catch {
    return { statusCode: 503, body: JSON.stringify({ code: 'PILOT_CONFIGURATION_REJECTED' }) };
  }
  // Conservative budget below the platform's 6 MB base64 envelope limit.
  const bytes = event.isBase64Encoded ? Buffer.byteLength(event.body || '', 'base64') : Buffer.byteLength(event.body || '');
  if (bytes > 4 * 1024 * 1024) return { statusCode: 413, body: JSON.stringify({ code: 'PILOT_PAYLOAD_TOO_LARGE' }) };
  if (context.getRemainingTimeInMillis && context.getRemainingTimeInMillis() < 5000) {
    return { statusCode: 503, body: JSON.stringify({ code: 'PILOT_EXECUTION_BUDGET' }) };
  }
  // This entry point accepts LOCAL invocations only. Netlify Dev omits AWS's
  // sourceIp; supply a fixed loopback bucket and never trust caller-supplied XFF.
  event = { ...event, headers: { ...event.headers }, multiValueHeaders: { ...event.multiValueHeaders }, requestContext: { ...event.requestContext,
    identity: { ...event.requestContext?.identity, sourceIp: '127.0.0.1' } } };
  for (const key of Object.keys(event.headers)) if (key.toLowerCase() === 'x-forwarded-for') delete event.headers[key];
  for (const key of Object.keys(event.multiValueHeaders)) if (key.toLowerCase() === 'x-forwarded-for') delete event.multiValueHeaders[key];
  if (!wrapped) {
    const serverless = require('serverless-http');
    wrapped = serverless(require('../../src/app'), { binary: ['image/png', 'image/jpeg', 'application/octet-stream'] });
  }
  if (event.blobs) {
    const data = JSON.parse(Buffer.from(event.blobs, 'base64').toString('utf8'));
    const url = new URL(data.url);
    if (url.protocol !== 'http:' || !['127.0.0.1','localhost','[::1]'].includes(url.hostname)) {
      return { statusCode: 503, body: JSON.stringify({ code: 'PILOT_REMOTE_BLOBS_REJECTED' }) };
    }
    // Blobs SDK 11's legacy Lambda connector omits uncachedEdgeURL. Netlify
    // Dev has a single local server, so both consistency endpoints use it.
    require('@netlify/blobs').setEnvironmentContext({ siteID: event.headers['x-nf-site-id'], token: data.token,
      edgeURL: data.url, uncachedEdgeURL: data.url });
  }
  return wrapped(event, context);
};
