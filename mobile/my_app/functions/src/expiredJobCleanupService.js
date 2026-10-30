module.exports = require("./expiredJobPolicy").createPolicy(
  require("firebase-admin/firestore"),
);
