/**
 * Grants Storage Object Viewer on the Cloud Functions source bucket to the
 * Compute and Cloud Build service accounts so "firebase deploy --only functions" can build.
 * Run once with: npx gcloud auth application-default login
 * Then: node grant-gcf-bucket-access.js
 */
const { Storage } = require('@google-cloud/storage');

const PROJECT_NUMBER = '28158895372';
const REGION = 'us-central1';
const BUCKET_NAME = `gcf-sources-${PROJECT_NUMBER}-${REGION}`;

const SERVICE_ACCOUNTS = [
  `${PROJECT_NUMBER}-compute@developer.gserviceaccount.com`,
  `${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com`,
];

const ROLE = 'roles/storage.objectViewer';

async function main() {
  const storage = new Storage({ projectId: 'boltlog' });
  const bucket = storage.bucket(BUCKET_NAME);

  try {
    const [policy] = await bucket.iam.getPolicy({ requestedPolicyVersion: 3 });
    let binding = policy.bindings.find((b) => b.role === ROLE);
    if (!binding) {
      binding = { role: ROLE, members: [] };
      policy.bindings.push(binding);
    }
    const toAdd = SERVICE_ACCOUNTS.map(
      (sa) => `serviceAccount:${sa}`
    ).filter((m) => !binding.members.includes(m));
    if (toAdd.length === 0) {
      console.log('Bucket IAM already has the required bindings. OK.');
      return;
    }
    binding.members.push(...toAdd);
    await bucket.iam.setPolicy(policy);
    console.log('Granted', ROLE, 'on bucket', BUCKET_NAME, 'to:', toAdd);
  } catch (err) {
    if (err.code === 404) {
      console.warn('Bucket', BUCKET_NAME, 'not found yet (created on first deploy).');
      console.warn('Grant project-level Storage Object Viewer in Console to both service accounts, then deploy again.');
      process.exitCode = 1;
      return;
    }
    if (err.message && err.message.includes('Could not load the default credentials')) {
      console.error('Run once: npx gcloud auth application-default login');
      console.error('(Install gcloud first: winget install Google.CloudSDK)');
      process.exitCode = 1;
      return;
    }
    throw err;
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
