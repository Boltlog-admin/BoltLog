/**
 * Grants Firebase Auth custom claim { admin: true } so the account can use the BoltLog admin website.
 *
 * Prerequisites:
 * 1. Download a service account key (Firebase console → Project settings → Service accounts).
 * 2. Set GOOGLE_APPLICATION_CREDENTIALS to the JSON file path, or run:
 *    set GOOGLE_APPLICATION_CREDENTIALS=C:\path\to\serviceAccount.json   (Windows)
 *    export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json   (macOS/Linux)
 *
 * Usage (from functions/ folder):
 *   npm run set-admin-claim -- <AUTH_UID>
 *   npm run set-admin-claim -- admin@boltlog.org
 *
 * If you pass an email (contains @), the script looks up the user and sets the claim on that UID.
 * After running, the user must sign out and sign in again (or wait for token refresh) to get the claim.
 */

const admin = require("firebase-admin");

const arg = process.argv[2];
if (!arg) {
  console.error(
    "Usage: npm run set-admin-claim -- <AUTH_UID | email@example.com>",
  );
  process.exit(1);
}

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.warn(
    "GOOGLE_APPLICATION_CREDENTIALS not set — using Application Default Credentials if available (e.g. GitHub Actions after google-github-actions/auth, or `gcloud auth application-default login`).",
  );
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

async function main() {
  const raw = arg.trim();
  let uid;
  if (raw.includes("@")) {
    const email = raw.toLowerCase();
    const user = await admin.auth().getUserByEmail(email);
    uid = user.uid;
    console.log("Resolved email → uid:", email, "→", uid);
  } else {
    uid = raw;
  }

  await admin.auth().setCustomUserClaims(uid, { admin: true });
  console.log("OK: custom claim { admin: true } set for uid:", uid);
  console.log(
    "User must sign out and sign in again on the BoltLog admin website.",
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
