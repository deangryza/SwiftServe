// Shared deployable policy, using this package's SDK types for compatibility.
module.exports = require('../../../mobile/my_app/functions/src/expiredJobPolicy').createPolicy(require('firebase-admin/firestore'));
