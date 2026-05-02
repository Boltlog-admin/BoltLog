# Deploy Firestore rules (fix for sender-transporter chat).
# Requires: Firebase CLI installed and logged in (firebase login).
& npx --yes firebase-tools deploy --only firestore
