const { ANDROID_APP, getStagingFirebase, diagnostic } = require('../config/stagingFirebase');

function requestDiagnostics(req, res, next) {
  res.on('finish', () => console.info(JSON.stringify({ environment: 'staging',
    category: 'http', method: req.method, status: res.statusCode })));
  next();
}
function appCheckMiddleware(verify) {
  return async (req, res, next) => {
    const token = req.get('X-Firebase-AppCheck');
    if (!token) return res.status(401).json({ code: 'STAGING_APP_CHECK_MISSING', message: 'Staging App Check token is required.' });
    try {
      const decoded = await verify(token);
      if (decoded.appId !== ANDROID_APP) throw Object.assign(new Error(), { code: 'app-check/wrong-app' });
      return next();
    } catch (error) {
      diagnostic('app-check', error);
      return res.status(401).json({ code: 'STAGING_APP_CHECK_INVALID', message: 'Staging App Check failed. Retry after registering the debug device.' });
    }
  };
}
function verifyStagingAppCheck() {
  return appCheckMiddleware(token => getStagingFirebase().appCheck.verifyToken(token));
}
module.exports = { requestDiagnostics, appCheckMiddleware, verifyStagingAppCheck };
