require('dotenv').config();

const { auth } = require('../src/config/firebase');

const [action, identifier] = process.argv.slice(2);

if (!['grant', 'revoke'].includes(action) || !identifier) {
  console.error('Usage: npm run admin:claim -- <grant|revoke> <uid|email>');
  process.exit(1);
}

const run = async () => {
  const user = identifier.includes('@')
    ? await auth.getUserByEmail(identifier)
    : await auth.getUser(identifier);
  await auth.setCustomUserClaims(user.uid, {
    ...(user.customClaims || {}),
    admin: action === 'grant',
  });
  console.log(`${action === 'grant' ? 'Granted' : 'Revoked'} admin claim for ${user.email || user.uid}.`);
};

run().catch((error) => {
  console.error(error);
  process.exit(1);
});
