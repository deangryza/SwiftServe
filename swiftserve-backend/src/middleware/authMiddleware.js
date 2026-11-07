const { auth } = require('../config/firebase');

const authenticateUser = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        message: 'Authentication token is missing.',
      });
    }

    const idToken = authHeader.split('Bearer ')[1];

    // Every authenticated route exposed by the local Netlify adapter checks
    // revocation/disabled state. Preserve the existing non-pilot SDK call contract.
    const decodedToken = process.env.SWIFTSERVE_NETLIFY_PILOT === 'true'
      ? await auth.verifyIdToken(idToken, true)
      : await auth.verifyIdToken(idToken);

    req.user = decodedToken;

    next();
  } catch (error) {
    if (process.env.SWIFTSERVE_STAGING === 'true') require('../config/stagingFirebase').diagnostic('authentication', error);
    else console.error('Authentication error:', String(error.code || 'AUTHENTICATION_FAILED').replace(/[^a-zA-Z0-9_/-]/g,'').slice(0,80));

    return res.status(401).json({
      message: 'Invalid or expired authentication token.',
    });
  }
};

module.exports = authenticateUser;
