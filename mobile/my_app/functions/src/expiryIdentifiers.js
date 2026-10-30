const { createHash } = require("node:crypto");
// Preserve existing ordinary IDs. The dotted v2 namespace cannot collide with
// the legacy [A-Za-z0-9_-] namespace. Keep the original request ID in the record.
function validDocumentId(id) {
  return typeof id === "string" && id.length > 0 &&
    Buffer.byteLength(id, "utf8") <= 1500 && !id.includes("/") &&
    id !== "." && id !== ".." && !/^__.*__$/.test(id);
}
function expiryEventId(requestId) {
  if (!validDocumentId(requestId)) throw new Error("Invalid request ID");
  return /^[A-Za-z0-9_-]{1,128}$/.test(requestId)
    ? `jobExpired_${requestId}`
    : `jobExpired.v2.${createHash("sha256").update(requestId, "utf8").digest("hex")}`;
}
function matchesExpiryEvent(eventId, requestId) {
  return validDocumentId(requestId) && validDocumentId(eventId) &&
    (eventId === expiryEventId(requestId) || eventId === `jobExpired_${requestId}`);
}
module.exports = { expiryEventId, matchesExpiryEvent, validDocumentId };
