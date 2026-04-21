import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getFirestore } from "firebase/firestore";
import { getFunctions } from "firebase/functions";

// Public config (same values as lib/firebase_options.dart web). Override with .env for other projects.
const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY ?? "AIzaSyDAaFAu_FDneVj954kiKlrTLp3BDlhiOJw",
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN ?? "boltlog.firebaseapp.com",
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID ?? "boltlog",
  storageBucket:
    import.meta.env.VITE_FIREBASE_STORAGE_BUCKET ?? "boltlog.firebasestorage.app",
  messagingSenderId:
    import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID ?? "28158895372",
  appId:
    import.meta.env.VITE_FIREBASE_APP_ID ?? "1:28158895372:web:eda905124ed85a63719529",
};

export const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);
export const functions = getFunctions(app, "us-central1");
