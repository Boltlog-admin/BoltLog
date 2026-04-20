import { useCallback, useEffect, useState } from "react";
import { FirebaseError } from "firebase/app";
import {
  type User,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signOut,
} from "firebase/auth";
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  query,
  setDoc,
  type Firestore,
} from "firebase/firestore";
import { auth, db } from "./firebase";

/** When the form shows a plain username (no @), Firebase sign-in uses this email. */
const ADMIN_LOGIN_EMAIL_DOMAIN = "boltlog-admin.local";

function loginIdentifierToEmail(raw: string): string {
  const s = raw.trim();
  if (!s) return s;
  // Firebase Email/Password sign-in is case-insensitive; normalize to avoid typos.
  if (s.includes("@")) return s.toLowerCase();
  return `${s.toLowerCase()}@${ADMIN_LOGIN_EMAIL_DOMAIN}`;
}

function formatLoginError(e: unknown, emailUsed: string): string {
  const code = e instanceof FirebaseError ? e.code : "";
  const lines = [
    "Sign-in failed — Firebase rejected the email/password (or the user does not exist).",
    "",
    "In Firebase Console → project boltlog:",
    "1. Authentication → Sign-in method → enable Email/Password.",
    `2. Authentication → Users → check this exact email exists: ${emailUsed}`,
    "   If missing: Add user with that email and password. If it exists: use Password reset.",
    "3. Authentication → Settings → Authorized domains → add this site’s host, e.g. boltlog-admin.github.io",
    "4. After the user exists: set custom claim admin:true (functions/scripts/set-admin-claim.js), then sign in again.",
    "",
    `Resolved email: ${emailUsed}`,
    code ? `Firebase: ${code}` : String(e),
  ];
  if (code === "auth/unauthorized-domain") {
    lines.unshift(
      "This website’s domain is not in Firebase Authorized domains — add it in step 3.",
      "",
    );
  }
  return lines.join("\n");
}

type Tab = "users" | "rides" | "activity" | "inbox" | "document";
type UserRow = {
  id: string;
  email?: string;
  role?: string;
  data: Record<string, unknown>;
};
type ActivityRow = {
  id: string;
  source: "rides" | "notifications";
  activityType: string;
  rideId?: string;
  senderId?: string;
  driverId?: string;
  userId?: string;
  status?: string;
  message?: string;
  atText: string;
  atMs: number;
  raw: Record<string, unknown>;
};
type InboxRow = {
  id: string;
  source: "bugReports" | "notifications";
  userId?: string;
  userEmail?: string;
  title?: string;
  description?: string;
  status?: string;
  createdAtText: string;
  createdAtMs: number;
};

function docRefFromPath(firestore: Firestore, path: string) {
  const parts = path.split("/").filter(Boolean);
  if (parts.length < 2 || parts.length % 2 !== 0) {
    throw new Error(
      "Path must be collection/doc pairs, e.g. users/abc or rides/r1/offers/o1",
    );
  }
  return doc(firestore, ...(parts as [string, ...string[]]));
}

const shell: React.CSSProperties = {
  maxWidth: 1200,
  margin: "0 auto",
  padding: "1.25rem",
};

const card: React.CSSProperties = {
  background: "#fff",
  borderRadius: 12,
  padding: "1.25rem",
  boxShadow: "0 1px 3px rgb(0 0 0 / 0.08)",
  marginBottom: "1rem",
};

const btnPrimary: React.CSSProperties = {
  background: "#1e40af",
  color: "#fff",
  border: "none",
  borderRadius: 8,
  padding: "0.5rem 1rem",
  fontWeight: 600,
};

const btnDanger: React.CSSProperties = {
  ...btnPrimary,
  background: "#b91c1c",
};

const btnGhost: React.CSSProperties = {
  background: "transparent",
  color: "#475569",
  border: "1px solid #cbd5e1",
  borderRadius: 8,
  padding: "0.5rem 0.75rem",
};

function serializeDocData(data: Record<string, unknown>): string {
  const out: Record<string, unknown> = { ...data };
  for (const k of Object.keys(out)) {
    const v = out[k];
    if (v instanceof Timestamp) {
      out[k] = { __firestoreTimestamp: true, seconds: v.seconds, nanoseconds: v.nanoseconds };
    }
  }
  return JSON.stringify(out, null, 2);
}

function parseDocJson(text: string): Record<string, unknown> {
  const raw = JSON.parse(text) as Record<string, unknown>;
  const out: Record<string, unknown> = { ...raw };
  for (const k of Object.keys(out)) {
    const v = out[k];
    if (
      v &&
      typeof v === "object" &&
      (v as { __firestoreTimestamp?: boolean }).__firestoreTimestamp === true
    ) {
      const t = v as { seconds: number; nanoseconds: number };
      out[k] = new Timestamp(t.seconds, t.nanoseconds);
    }
  }
  return out;
}

function normalizeRole(role: unknown): string {
  return typeof role === "string" ? role.trim().toLowerCase() : "";
}

function isDriverRole(role: unknown): boolean {
  const r = normalizeRole(role);
  return r === "driver" || r === "transporter";
}

function isSenderRole(role: unknown): boolean {
  const r = normalizeRole(role);
  return r === "passenger" || r === "sender" || r.length === 0;
}

function isAdminRole(role: unknown): boolean {
  const r = normalizeRole(role);
  return r === "admin" || r === "super_admin" || r === "superadmin";
}

function formatValue(v: unknown): string {
  if (v === null || v === undefined) return "—";
  if (v instanceof Timestamp) return v.toDate().toISOString();
  if (typeof v === "object") {
    try {
      return JSON.stringify(v);
    } catch {
      return String(v);
    }
  }
  return String(v);
}

function namePartsFromUser(data: Record<string, unknown>): {
  firstName: string;
  surname: string;
} {
  const displayNameRaw =
    (typeof data.displayName === "string" ? data.displayName : "") ||
    (typeof data.idFullName === "string" ? data.idFullName : "");
  const displayName = displayNameRaw.trim();
  if (!displayName) return { firstName: "—", surname: "—" };
  const parts = displayName.split(/\s+/).filter(Boolean);
  if (parts.length === 1) return { firstName: parts[0], surname: "—" };
  return { firstName: parts[0], surname: parts.slice(1).join(" ") };
}

function toMillis(v: unknown): number {
  if (!v) return 0;
  if (v instanceof Timestamp) return v.toMillis();
  if (typeof v === "string") {
    const parsed = Date.parse(v);
    return Number.isNaN(parsed) ? 0 : parsed;
  }
  if (typeof v === "number" && Number.isFinite(v)) return v;
  return 0;
}

function readableWhen(v: unknown): string {
  if (v instanceof Timestamp) return v.toDate().toISOString();
  if (typeof v === "string") return v;
  if (typeof v === "number" && Number.isFinite(v)) {
    return new Date(v).toISOString();
  }
  return "—";
}

export default function App() {
  const [user, setUser] = useState<User | null>(null);
  const [isAdmin, setIsAdmin] = useState<boolean | null>(null);
  const [authReady, setAuthReady] = useState(false);
  const [username, setUsername] = useState("admin@boltlog.org");
  const [password, setPassword] = useState("admin");
  const [authError, setAuthError] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>("users");
  const [busy, setBusy] = useState(false);
  const [toast, setToast] = useState<string | null>(null);

  const [usersRows, setUsersRows] = useState<UserRow[]>([]);
  const [ridesRows, setRidesRows] = useState<
    { id: string; status?: string; userId?: string; driverId?: string }[]
  >([]);
  const [activityRows, setActivityRows] = useState<ActivityRow[]>([]);
  const [inboxRows, setInboxRows] = useState<InboxRow[]>([]);

  const [explorerPath, setExplorerPath] = useState("users/");
  const [explorerJson, setExplorerJson] = useState("");
  const [explorerExists, setExplorerExists] = useState<boolean | null>(null);

  const [selectedUserId, setSelectedUserId] = useState<string | null>(null);
  const [userEditJson, setUserEditJson] = useState("");

  const refreshClaims = useCallback(async (u: User | null) => {
    if (!u) {
      setIsAdmin(null);
      return;
    }
    const token = await u.getIdTokenResult(true);
    setIsAdmin(token.claims.admin === true);
  }, []);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (u) => {
      setUser(u);
      await refreshClaims(u);
      setAuthReady(true);
    });
    return () => unsub();
  }, [refreshClaims]);

  const showToast = (msg: string) => {
    setToast(msg);
    setTimeout(() => setToast(null), 4000);
  };

  const loadUsers = async () => {
    setBusy(true);
    setAuthError(null);
    try {
      const snap = await getDocs(query(collection(db, "users"), limit(500)));
      setUsersRows(
        snap.docs.map((d) => {
          const x = d.data() as Record<string, unknown>;
          return {
            id: d.id,
            email: x.email as string | undefined,
            role: x.role as string | undefined,
            data: x,
          };
        }),
      );
      showToast(`Loaded ${snap.size} users`);
    } catch (e) {
      setAuthError(String(e));
    } finally {
      setBusy(false);
    }
  };

  const loadRides = async () => {
    setBusy(true);
    setAuthError(null);
    try {
      const snap = await getDocs(query(collection(db, "rides"), limit(200)));
      setRidesRows(
        snap.docs.map((d) => {
          const x = d.data() as Record<string, unknown>;
          return {
            id: d.id,
            status: x.status as string | undefined,
            userId: x.userId as string | undefined,
            driverId: x.driverId as string | undefined,
          };
        }),
      );
      showToast(`Loaded ${snap.size} rides`);
    } catch (e) {
      setAuthError(String(e));
    } finally {
      setBusy(false);
    }
  };

  const loadActivities = async () => {
    setBusy(true);
    setAuthError(null);
    try {
      const [ridesSnap, notificationsSnap] = await Promise.all([
        getDocs(query(collection(db, "rides"), limit(500))),
        getDocs(query(collection(db, "notifications"), limit(500))),
      ]);

      const rideActivities: ActivityRow[] = ridesSnap.docs.map((d) => {
        const x = d.data() as Record<string, unknown>;
        const status = (x.status as string | undefined) ?? "unknown";
        const rideId = d.id;
        const senderId =
          (typeof x.userId === "string" ? x.userId : undefined) ??
          (typeof x.senderId === "string" ? x.senderId : undefined);
        const driverId = typeof x.driverId === "string" ? x.driverId : undefined;
        const when = x.completedAt ?? x.updatedAt ?? x.createdAt;
        return {
          id: `ride-${d.id}`,
          source: "rides",
          activityType: `ride_${status}`,
          rideId,
          senderId,
          driverId,
          status,
          message: `Ride ${status.replaceAll("_", " ")}`,
          atText: readableWhen(when),
          atMs: toMillis(when),
          raw: x,
        };
      });

      const notificationActivities: ActivityRow[] = notificationsSnap.docs.map((d) => {
        const x = d.data() as Record<string, unknown>;
        const type = (x.type as string | undefined) ?? "notification";
        const rideId = typeof x.rideId === "string" ? x.rideId : undefined;
        const userId = typeof x.userId === "string" ? x.userId : undefined;
        const when = x.createdAt;
        return {
          id: `notif-${d.id}`,
          source: "notifications",
          activityType: type,
          rideId,
          userId,
          status: undefined,
          message:
            `${formatValue(x.title)}${x.message ? `: ${formatValue(x.message)}` : ""}`,
          atText: readableWhen(when),
          atMs: toMillis(when),
          raw: x,
        };
      });

      const all = [...rideActivities, ...notificationActivities].sort(
        (a, b) => b.atMs - a.atMs,
      );
      setActivityRows(all);
      showToast(
        `Loaded ${all.length} activities (${rideActivities.length} rides, ${notificationActivities.length} notifications)`,
      );
    } catch (e) {
      setAuthError(String(e));
    } finally {
      setBusy(false);
    }
  };

  const loadInbox = async () => {
    setBusy(true);
    setAuthError(null);
    try {
      const [bugReportsSnap, notificationsSnap] = await Promise.all([
        getDocs(query(collection(db, "bugReports"), limit(500))),
        getDocs(query(collection(db, "notifications"), limit(500))),
      ]);

      const bugRows: InboxRow[] = bugReportsSnap.docs.map((d) => {
        const x = d.data() as Record<string, unknown>;
        const when = x.createdAt;
        return {
          id: d.id,
          source: "bugReports",
          userId: typeof x.userId === "string" ? x.userId : undefined,
          userEmail: typeof x.userEmail === "string" ? x.userEmail : undefined,
          title: "Bug report",
          description: typeof x.description === "string" ? x.description : undefined,
          status: typeof x.status === "string" ? x.status : "open",
          createdAtText: readableWhen(when),
          createdAtMs: toMillis(when),
        };
      });

      const notifRows: InboxRow[] = notificationsSnap.docs
        .map((d) => {
          const x = d.data() as Record<string, unknown>;
          const type = normalizeRole(x.type);
          const looksLikeReport =
            type.includes("report") || type.includes("issue") || type.includes("bug");
          if (!looksLikeReport) return null;
          const when = x.createdAt;
          return {
            id: d.id,
            source: "notifications",
            userId: typeof x.userId === "string" ? x.userId : undefined,
            title: typeof x.title === "string" ? x.title : "Report notification",
            description: typeof x.message === "string" ? x.message : undefined,
            status: (x.isRead as boolean | undefined) ? "read" : "unread",
            createdAtText: readableWhen(when),
            createdAtMs: toMillis(when),
          } as InboxRow;
        })
        .filter((row): row is InboxRow => row !== null);

      const rows = [...bugRows, ...notifRows].sort((a, b) => b.createdAtMs - a.createdAtMs);
      setInboxRows(rows);
      showToast(`Loaded ${rows.length} inbox reports`);
    } catch (e) {
      setAuthError(String(e));
    } finally {
      setBusy(false);
    }
  };

  const updateBugReportStatus = async (reportId: string, status: "open" | "in_progress" | "resolved" | "closed") => {
    setBusy(true);
    setAuthError(null);
    try {
      await setDoc(
        doc(db, "bugReports", reportId),
        {
          status,
          updatedAt: new Date().toISOString(),
          updatedBy: user?.uid ?? null,
        },
        { merge: true },
      );
      showToast(`Report ${reportId} set to ${status}`);
      await loadInbox();
    } catch (e) {
      setAuthError(String(e));
    } finally {
      setBusy(false);
    }
  };

  const openUserEditor = async (uid: string) => {
    setSelectedUserId(uid);
    setBusy(true);
    try {
      const r = await getDoc(doc(db, "users", uid));
      if (!r.exists()) {
        setUserEditJson("{}");
        showToast("User doc missing — create with Save");
      } else {
        setUserEditJson(serializeDocData(r.data() as Record<string, unknown>));
      }
    } catch (e) {
      setAuthError(String(e));
      setUserEditJson("{}");
    } finally {
      setBusy(false);
    }
  };

  const saveUserDoc = async () => {
    if (!selectedUserId) return;
    setBusy(true);
    try {
      const data = parseDocJson(userEditJson);
      await setDoc(doc(db, "users", selectedUserId), data, { merge: true });
      showToast("User document saved");
      await loadUsers();
    } catch (e) {
      setAuthError(String(e));
    } finally {
      setBusy(false);
    }
  };

  const setUserRole = async (uid: string, role: "Passenger" | "Driver" | "admin" | "super_admin") => {
    setBusy(true);
    setAuthError(null);
    try {
      await setDoc(
        doc(db, "users", uid),
        {
          role,
          isAdmin: role === "admin" || role === "super_admin",
          superAdmin: role === "super_admin",
          roleUpdatedAt: new Date().toISOString(),
        },
        { merge: true },
      );
      showToast(`Role updated to ${role} for ${uid}`);
      await loadUsers();
      if (selectedUserId === uid) {
        await openUserEditor(uid);
      }
    } catch (e) {
      setAuthError(String(e));
    } finally {
      setBusy(false);
    }
  };

  const setAccountDecision = async (
    uid: string,
    decision: "accepted" | "declined",
  ) => {
    setBusy(true);
    setAuthError(null);
    try {
      const isAccepted = decision === "accepted";
      await setDoc(
        doc(db, "users", uid),
        {
          verificationStatus: isAccepted ? "verified" : "rejected",
          isAvailable: isAccepted ? true : false,
          accountDecision: decision,
          decisionAt: new Date().toISOString(),
          decisionBy: user?.uid ?? null,
        },
        { merge: true },
      );
      showToast(`Account ${decision} for ${uid}`);
      await loadUsers();
      if (selectedUserId === uid) {
        await openUserEditor(uid);
      }
    } catch (e) {
      setAuthError(String(e));
    } finally {
      setBusy(false);
    }
  };

  const deleteUserDoc = async () => {
    if (!selectedUserId) return;
    if (!confirm(`Delete Firestore doc users/${selectedUserId} ? (Auth user is not deleted.)`)) return;
    setBusy(true);
    try {
      await deleteDoc(doc(db, "users", selectedUserId));
      showToast("User document deleted");
      setSelectedUserId(null);
      setUserEditJson("");
      await loadUsers();
    } catch (e) {
      setAuthError(String(e));
    } finally {
      setBusy(false);
    }
  };

  const loadExplorerDoc = async () => {
    const p = explorerPath.trim();
    if (!p) return;
    setBusy(true);
    setExplorerExists(null);
    try {
      const ref = docRefFromPath(db, p);
      const r = await getDoc(ref);
      setExplorerExists(r.exists());
      if (r.exists()) {
        setExplorerJson(serializeDocData(r.data() as Record<string, unknown>));
      } else {
        setExplorerJson("{}");
      }
      showToast(r.exists() ? "Document loaded" : "Document missing — you can create with Save");
    } catch (e) {
      setAuthError(String(e));
      setExplorerJson("");
    } finally {
      setBusy(false);
    }
  };

  const saveExplorerDoc = async () => {
    const p = explorerPath.trim();
    if (!p) return;
    setBusy(true);
    try {
      const data = parseDocJson(explorerJson);
      const ref = docRefFromPath(db, p);
      await setDoc(ref, data, { merge: false });
      setExplorerExists(true);
      showToast("Document written (replaced)");
    } catch (e) {
      setAuthError(String(e));
    } finally {
      setBusy(false);
    }
  };

  const mergeExplorerDoc = async () => {
    const p = explorerPath.trim();
    if (!p) return;
    setBusy(true);
    try {
      const data = parseDocJson(explorerJson);
      const ref = docRefFromPath(db, p);
      await setDoc(ref, data, { merge: true });
      setExplorerExists(true);
      showToast("Document merged");
    } catch (e) {
      setAuthError(String(e));
    } finally {
      setBusy(false);
    }
  };

  const deleteExplorerDoc = async () => {
    const p = explorerPath.trim();
    if (!p) return;
    if (!confirm(`Delete document at ${p} ?`)) return;
    setBusy(true);
    try {
      await deleteDoc(docRefFromPath(db, p));
      setExplorerJson("");
      setExplorerExists(false);
      showToast("Document deleted");
    } catch (e) {
      setAuthError(String(e));
    } finally {
      setBusy(false);
    }
  };

  const login = async (ev: React.FormEvent) => {
    ev.preventDefault();
    setAuthError(null);
    setBusy(true);
    const emailUsed = loginIdentifierToEmail(username);
    try {
      const cred = await signInWithEmailAndPassword(auth, emailUsed, password);
      await cred.user.getIdToken(true);
      await refreshClaims(cred.user);
    } catch (e) {
      setAuthError(formatLoginError(e, emailUsed));
    } finally {
      setBusy(false);
    }
  };

  const logout = async () => {
    await signOut(auth);
    setIsAdmin(null);
  };

  const driverRows = usersRows.filter((u) => isDriverRole(u.role));
  const senderRows = usersRows.filter((u) => isSenderRole(u.role));
  const adminRows = usersRows.filter((u) => isAdminRole(u.role));
  const otherRoleRows = usersRows.filter(
    (u) => !isDriverRole(u.role) && !isSenderRole(u.role) && !isAdminRole(u.role),
  );

  if (!authReady) {
    return (
      <div style={{ ...shell, paddingTop: "3rem", textAlign: "center" }}>
        Loading…
      </div>
    );
  }

  if (!user) {
    return (
      <div style={shell}>
        <h1 style={{ marginTop: 0, color: "#1e40af" }}>BoltLog Admin</h1>
        <p style={{ marginBottom: "0.75rem" }}>
          <a
            href={`${import.meta.env.BASE_URL}app/`}
            style={{ color: "#2563eb", fontSize: 14, textDecoration: "underline" }}
          >
            Open BoltLog app (web)
          </a>
        </p>
        <p style={{ color: "#64748b", maxWidth: 520 }}>
          Enter a <strong>full email</strong> (e.g. <code>admin@boltlog.org</code>) if that user exists
          in Firebase — we use it exactly (after lowercasing). Or enter only{" "}
          <code>admin</code> → we sign in as <code>admin@{ADMIN_LOGIN_EMAIL_DOMAIN}</code>.
          The account needs Email/Password enabled, must exist under Authentication → Users, and
          needs custom claim <code>admin: true</code> (see{" "}
          <code>functions/scripts/set-admin-claim.js</code>).
        </p>
        <div style={card}>
          <form onSubmit={login}>
            <div style={{ marginBottom: "0.75rem" }}>
              <label>
                <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 4 }}>
                  Username or email
                </div>
                <input
                  type="text"
                  autoComplete="username"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  required
                  style={{ width: "100%", maxWidth: 360, padding: "0.5rem 0.6rem" }}
                />
              </label>
            </div>
            <div style={{ marginBottom: "1rem" }}>
              <label>
                <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 4 }}>Password</div>
                <input
                  type="password"
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  style={{ width: "100%", maxWidth: 360, padding: "0.5rem 0.6rem" }}
                />
              </label>
            </div>
            <button type="submit" disabled={busy} style={btnPrimary}>
              {busy ? "Signing in…" : "Sign in"}
            </button>
          </form>
          <p
            style={{
              marginTop: "0.75rem",
              fontSize: 12,
              color: "#64748b",
            }}
          >
            Firebase email for this sign-in:{" "}
            <code style={{ fontSize: 12 }}>{loginIdentifierToEmail(username) || "—"}</code>
          </p>
          {authError && (
            <pre
              style={{
                marginTop: "1rem",
                padding: "0.75rem",
                background: "#fef2f2",
                color: "#991b1b",
                borderRadius: 8,
                overflow: "auto",
                fontSize: 13,
              }}
            >
              {authError}
            </pre>
          )}
        </div>
      </div>
    );
  }

  if (!isAdmin) {
    return (
      <div style={shell}>
        <h1 style={{ color: "#b91c1c" }}>Not authorized</h1>
        <p>
          Signed in as <strong>{user.email}</strong> but this account does not have
          the <code>admin</code> custom claim. A project owner must grant it with the
          Admin SDK (service account JSON +{" "}
          <code>GOOGLE_APPLICATION_CREDENTIALS</code>), from the <code>functions/</code>{" "}
          folder:
        </p>
        <pre
          style={{
            padding: "0.75rem",
            background: "#f1f5f9",
            borderRadius: 8,
            fontSize: 13,
            overflow: "auto",
          }}
        >
          {`npm run set-admin-claim -- ${user.email ?? "<email>"}`}
        </pre>
        <p style={{ color: "#64748b", fontSize: 14 }}>
          Then use <strong>Sign out</strong> here and sign in again so your token picks up
          the claim.
        </p>
        <p style={{ color: "#64748b", fontSize: 14 }}>
          <strong>Maintainers:</strong> In this repo on GitHub, add secret{" "}
          <code>FIREBASE_ADMIN_SA_KEY</code> (Firebase Console → Project settings → Service
          accounts → generate private key JSON), then run{" "}
          <strong>Actions → Set Firebase admin custom claim</strong> with this email. The
          workflow uses the same <code>npm run set-admin-claim</code> step as above.
        </p>
        <button type="button" onClick={() => logout()} style={btnGhost}>
          Sign out
        </button>
      </div>
    );
  }

  return (
    <div style={shell}>
      <header
        style={{
          display: "flex",
          flexWrap: "wrap",
          alignItems: "center",
          gap: "0.75rem",
          marginBottom: "1rem",
        }}
      >
        <h1 style={{ margin: 0, color: "#1e40af", flex: "1 1 auto" }}>BoltLog Admin</h1>
        <a
          href={`${import.meta.env.BASE_URL}app/`}
          style={{ color: "#2563eb", fontSize: 14, textDecoration: "underline" }}
        >
          Open BoltLog app (web)
        </a>
        <span style={{ color: "#64748b", fontSize: 14 }}>{user.email}</span>
        <button type="button" onClick={() => logout()} style={btnGhost}>
          Sign out
        </button>
      </header>

      {toast && (
        <div
          style={{
            padding: "0.6rem 1rem",
            background: "#ecfdf5",
            color: "#065f46",
            borderRadius: 8,
            marginBottom: "0.75rem",
            fontSize: 14,
          }}
        >
          {toast}
        </div>
      )}

      <nav style={{ display: "flex", gap: 8, marginBottom: "1rem", flexWrap: "wrap" }}>
        {(
          [
            ["users", "Users"],
            ["rides", "Rides"],
            ["activity", "Activity"],
            ["inbox", "Inbox"],
            ["document", "Document"],
          ] as const
        ).map(([id, label]) => (
          <button
            key={id}
            type="button"
            onClick={() => setTab(id)}
            style={{
              ...btnGhost,
              fontWeight: 600,
              borderColor: tab === id ? "#1e40af" : "#cbd5e1",
              color: tab === id ? "#1e40af" : "#475569",
            }}
          >
            {label}
          </button>
        ))}
      </nav>

      {authError && (
        <pre
          style={{
            padding: "0.75rem",
            background: "#fef2f2",
            color: "#991b1b",
            borderRadius: 8,
            fontSize: 13,
            marginBottom: "1rem",
          }}
        >
          {authError}
        </pre>
      )}

      {tab === "users" && (
        <div style={card}>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: "1rem" }}>
            <button type="button" disabled={busy} onClick={loadUsers} style={btnPrimary}>
              Refresh list
            </button>
          </div>
          <div
            style={{
              display: "grid",
              gap: "0.5rem",
              gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
              marginBottom: "1rem",
            }}
          >
            <div style={{ background: "#eff6ff", borderRadius: 8, padding: "0.65rem 0.75rem" }}>
              <div style={{ fontSize: 12, color: "#475569" }}>Total users</div>
              <div style={{ fontSize: 18, fontWeight: 700, color: "#1e3a8a" }}>{usersRows.length}</div>
            </div>
            <div style={{ background: "#ecfdf5", borderRadius: 8, padding: "0.65rem 0.75rem" }}>
              <div style={{ fontSize: 12, color: "#475569" }}>Drivers</div>
              <div style={{ fontSize: 18, fontWeight: 700, color: "#065f46" }}>{driverRows.length}</div>
            </div>
            <div style={{ background: "#fefce8", borderRadius: 8, padding: "0.65rem 0.75rem" }}>
              <div style={{ fontSize: 12, color: "#475569" }}>Senders</div>
              <div style={{ fontSize: 18, fontWeight: 700, color: "#854d0e" }}>{senderRows.length}</div>
            </div>
            <div style={{ background: "#f3e8ff", borderRadius: 8, padding: "0.65rem 0.75rem" }}>
              <div style={{ fontSize: 12, color: "#475569" }}>Admins</div>
              <div style={{ fontSize: 18, fontWeight: 700, color: "#6d28d9" }}>{adminRows.length}</div>
            </div>
          </div>

          <h3 style={{ marginTop: 0, marginBottom: "0.5rem", color: "#6d28d9" }}>Admin Accounts</h3>
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14 }}>
              <thead>
                <tr style={{ textAlign: "left", borderBottom: "2px solid #e2e8f0" }}>
                  <th style={{ padding: "0.5rem" }}>Name</th>
                  <th style={{ padding: "0.5rem" }}>Surname</th>
                  <th style={{ padding: "0.5rem" }}>Email</th>
                  <th style={{ padding: "0.5rem" }}>Role</th>
                  <th style={{ padding: "0.5rem" }}>Role actions</th>
                  <th style={{ padding: "0.5rem" }} />
                </tr>
              </thead>
              <tbody>
                {adminRows.map((r) => {
                  const np = namePartsFromUser(r.data);
                  return (
                  <tr key={r.id} style={{ borderBottom: "1px solid #f1f5f9" }}>
                    <td style={{ padding: "0.5rem" }}>{np.firstName}</td>
                    <td style={{ padding: "0.5rem" }}>{np.surname}</td>
                    <td style={{ padding: "0.5rem" }}>{r.email ?? "—"}</td>
                    <td style={{ padding: "0.5rem" }}>{r.role ?? "—"}</td>
                    <td style={{ padding: "0.5rem" }}>
                      <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                        <button type="button" style={btnGhost} disabled={busy} onClick={() => setUserRole(r.id, "admin")}>
                          Make admin
                        </button>
                        <button type="button" style={btnGhost} disabled={busy} onClick={() => setUserRole(r.id, "super_admin")}>
                          Make super admin
                        </button>
                        <button type="button" style={btnGhost} disabled={busy} onClick={() => setUserRole(r.id, "Passenger")}>
                          Downgrade to sender
                        </button>
                      </div>
                    </td>
                    <td style={{ padding: "0.5rem" }}>
                      <button type="button" style={btnGhost} onClick={() => openUserEditor(r.id)}>
                        Edit JSON
                      </button>
                    </td>
                  </tr>
                )})}
              </tbody>
            </table>
          </div>

          <h3 style={{ marginTop: 0, marginBottom: "0.5rem", color: "#065f46" }}>Drivers</h3>
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14 }}>
              <thead>
                <tr style={{ textAlign: "left", borderBottom: "2px solid #e2e8f0" }}>
                  <th style={{ padding: "0.5rem" }}>Name</th>
                  <th style={{ padding: "0.5rem" }}>Surname</th>
                  <th style={{ padding: "0.5rem" }}>Email</th>
                  <th style={{ padding: "0.5rem" }}>Phone</th>
                  <th style={{ padding: "0.5rem" }}>Role</th>
                  <th style={{ padding: "0.5rem" }}>Truck</th>
                  <th style={{ padding: "0.5rem" }}>Vehicle #</th>
                  <th style={{ padding: "0.5rem" }}>Available</th>
                  <th style={{ padding: "0.5rem" }}>Verification</th>
                  <th style={{ padding: "0.5rem" }}>Wallet</th>
                  <th style={{ padding: "0.5rem" }}>Decision</th>
                  <th style={{ padding: "0.5rem" }}>Role actions</th>
                  <th style={{ padding: "0.5rem" }} />
                </tr>
              </thead>
              <tbody>
                {driverRows.map((r) => {
                  const np = namePartsFromUser(r.data);
                  return (
                  <tr key={r.id} style={{ borderBottom: "1px solid #f1f5f9" }}>
                    <td style={{ padding: "0.5rem" }}>{np.firstName}</td>
                    <td style={{ padding: "0.5rem" }}>{np.surname}</td>
                    <td style={{ padding: "0.5rem" }}>{r.email ?? "—"}</td>
                    <td style={{ padding: "0.5rem" }}>{formatValue(r.data.phoneNumber)}</td>
                    <td style={{ padding: "0.5rem" }}>{r.role ?? "—"}</td>
                    <td style={{ padding: "0.5rem" }}>{formatValue(r.data.truckType)}</td>
                    <td style={{ padding: "0.5rem" }}>{formatValue(r.data.vehicleNumber)}</td>
                    <td style={{ padding: "0.5rem" }}>{formatValue(r.data.isAvailable)}</td>
                    <td style={{ padding: "0.5rem" }}>{formatValue(r.data.verificationStatus)}</td>
                    <td style={{ padding: "0.5rem" }}>{formatValue(r.data.driverWalletBalance)}</td>
                    <td style={{ padding: "0.5rem" }}>
                      <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                        <button
                          type="button"
                          style={btnGhost}
                          disabled={busy}
                          onClick={() => setAccountDecision(r.id, "accepted")}
                        >
                          Accept
                        </button>
                        <button
                          type="button"
                          style={btnGhost}
                          disabled={busy}
                          onClick={() => setAccountDecision(r.id, "declined")}
                        >
                          Decline
                        </button>
                      </div>
                    </td>
                    <td style={{ padding: "0.5rem" }}>
                      <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                        <button type="button" style={btnGhost} disabled={busy} onClick={() => setUserRole(r.id, "Driver")}>
                          Driver
                        </button>
                        <button type="button" style={btnGhost} disabled={busy} onClick={() => setUserRole(r.id, "Passenger")}>
                          Sender
                        </button>
                        <button type="button" style={btnGhost} disabled={busy} onClick={() => setUserRole(r.id, "admin")}>
                          Admin
                        </button>
                        <button type="button" style={btnGhost} disabled={busy} onClick={() => setUserRole(r.id, "super_admin")}>
                          Super admin
                        </button>
                      </div>
                    </td>
                    <td style={{ padding: "0.5rem" }}>
                      <button type="button" style={btnGhost} onClick={() => openUserEditor(r.id)}>
                        Edit JSON
                      </button>
                    </td>
                  </tr>
                )})}
              </tbody>
            </table>
          </div>

          <h3 style={{ marginTop: "1.25rem", marginBottom: "0.5rem", color: "#854d0e" }}>Senders</h3>
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14 }}>
              <thead>
                <tr style={{ textAlign: "left", borderBottom: "2px solid #e2e8f0" }}>
                  <th style={{ padding: "0.5rem" }}>Name</th>
                  <th style={{ padding: "0.5rem" }}>Surname</th>
                  <th style={{ padding: "0.5rem" }}>Email</th>
                  <th style={{ padding: "0.5rem" }}>Phone</th>
                  <th style={{ padding: "0.5rem" }}>Role</th>
                  <th style={{ padding: "0.5rem" }}>Created</th>
                  <th style={{ padding: "0.5rem" }}>Last Login</th>
                  <th style={{ padding: "0.5rem" }}>Decision</th>
                  <th style={{ padding: "0.5rem" }}>Role actions</th>
                  <th style={{ padding: "0.5rem" }} />
                </tr>
              </thead>
              <tbody>
                {senderRows.map((r) => {
                  const np = namePartsFromUser(r.data);
                  return (
                  <tr key={r.id} style={{ borderBottom: "1px solid #f1f5f9" }}>
                    <td style={{ padding: "0.5rem" }}>{np.firstName}</td>
                    <td style={{ padding: "0.5rem" }}>{np.surname}</td>
                    <td style={{ padding: "0.5rem" }}>{r.email ?? "—"}</td>
                    <td style={{ padding: "0.5rem" }}>{formatValue(r.data.phoneNumber)}</td>
                    <td style={{ padding: "0.5rem" }}>{r.role ?? "—"}</td>
                    <td style={{ padding: "0.5rem" }}>{formatValue(r.data.createdAt)}</td>
                    <td style={{ padding: "0.5rem" }}>{formatValue(r.data.lastLoginAt)}</td>
                    <td style={{ padding: "0.5rem" }}>
                      <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                        <button
                          type="button"
                          style={btnGhost}
                          disabled={busy}
                          onClick={() => setAccountDecision(r.id, "accepted")}
                        >
                          Accept
                        </button>
                        <button
                          type="button"
                          style={btnGhost}
                          disabled={busy}
                          onClick={() => setAccountDecision(r.id, "declined")}
                        >
                          Decline
                        </button>
                      </div>
                    </td>
                    <td style={{ padding: "0.5rem" }}>
                      <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                        <button type="button" style={btnGhost} disabled={busy} onClick={() => setUserRole(r.id, "Passenger")}>
                          Sender
                        </button>
                        <button type="button" style={btnGhost} disabled={busy} onClick={() => setUserRole(r.id, "Driver")}>
                          Driver
                        </button>
                        <button type="button" style={btnGhost} disabled={busy} onClick={() => setUserRole(r.id, "admin")}>
                          Admin
                        </button>
                        <button type="button" style={btnGhost} disabled={busy} onClick={() => setUserRole(r.id, "super_admin")}>
                          Super admin
                        </button>
                      </div>
                    </td>
                    <td style={{ padding: "0.5rem" }}>
                      <button type="button" style={btnGhost} onClick={() => openUserEditor(r.id)}>
                        Edit JSON
                      </button>
                    </td>
                  </tr>
                )})}
              </tbody>
            </table>
          </div>

          {otherRoleRows.length > 0 && (
            <details style={{ marginTop: "1rem" }}>
              <summary style={{ cursor: "pointer", color: "#334155", fontWeight: 600 }}>
                Users with other/unknown role ({otherRoleRows.length})
              </summary>
              <div style={{ overflowX: "auto", marginTop: "0.5rem" }}>
                <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14 }}>
                  <thead>
                    <tr style={{ textAlign: "left", borderBottom: "2px solid #e2e8f0" }}>
                      <th style={{ padding: "0.5rem" }}>Name</th>
                      <th style={{ padding: "0.5rem" }}>Surname</th>
                      <th style={{ padding: "0.5rem" }}>Email</th>
                      <th style={{ padding: "0.5rem" }}>Role</th>
                      <th style={{ padding: "0.5rem" }} />
                    </tr>
                  </thead>
                  <tbody>
                    {otherRoleRows.map((r) => {
                      const np = namePartsFromUser(r.data);
                      return (
                      <tr key={r.id} style={{ borderBottom: "1px solid #f1f5f9" }}>
                        <td style={{ padding: "0.5rem" }}>{np.firstName}</td>
                        <td style={{ padding: "0.5rem" }}>{np.surname}</td>
                        <td style={{ padding: "0.5rem" }}>{r.email ?? "—"}</td>
                        <td style={{ padding: "0.5rem" }}>{r.role ?? "—"}</td>
                        <td style={{ padding: "0.5rem" }}>
                          <button type="button" style={btnGhost} onClick={() => openUserEditor(r.id)}>
                            Edit JSON
                          </button>
                        </td>
                      </tr>
                    )})}
                  </tbody>
                </table>
              </div>
            </details>
          )}

          {selectedUserId && (
            <div style={{ marginTop: "1.5rem" }}>
              <h3 style={{ margin: "0 0 0.5rem" }}>Edit user /users/{selectedUserId}</h3>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: "0.75rem" }}>
                <button
                  type="button"
                  style={btnGhost}
                  disabled={busy}
                  onClick={() => setAccountDecision(selectedUserId, "accepted")}
                >
                  Accept Account
                </button>
                <button
                  type="button"
                  style={btnGhost}
                  disabled={busy}
                  onClick={() => setAccountDecision(selectedUserId, "declined")}
                >
                  Decline Account
                </button>
                <button type="button" style={btnGhost} disabled={busy} onClick={() => setUserRole(selectedUserId, "Passenger")}>
                  Set Sender
                </button>
                <button type="button" style={btnGhost} disabled={busy} onClick={() => setUserRole(selectedUserId, "Driver")}>
                  Set Driver
                </button>
                <button type="button" style={btnGhost} disabled={busy} onClick={() => setUserRole(selectedUserId, "admin")}>
                  Set Admin
                </button>
                <button type="button" style={btnGhost} disabled={busy} onClick={() => setUserRole(selectedUserId, "super_admin")}>
                  Set Super Admin
                </button>
              </div>
              <details style={{ marginBottom: "0.75rem" }}>
                <summary style={{ cursor: "pointer", color: "#334155", fontWeight: 600 }}>
                  Show full user details snapshot
                </summary>
                <pre
                  style={{
                    marginTop: "0.5rem",
                    padding: "0.75rem",
                    background: "#f8fafc",
                    borderRadius: 8,
                    overflow: "auto",
                    fontSize: 12,
                  }}
                >
                  {JSON.stringify(
                    usersRows.find((u) => u.id === selectedUserId)?.data ?? {},
                    null,
                    2,
                  )}
                </pre>
              </details>
              <p style={{ fontSize: 13, color: "#64748b", marginTop: 0 }}>
                Valid JSON only. Timestamps round-trip as{" "}
                <code>{`{ "__firestoreTimestamp": true, "seconds": n, "nanoseconds": n }`}</code>.
              </p>
              <textarea
                value={userEditJson}
                onChange={(e) => setUserEditJson(e.target.value)}
                rows={16}
                style={{
                  width: "100%",
                  fontFamily: "monospace",
                  fontSize: 12,
                  padding: "0.75rem",
                  borderRadius: 8,
                  border: "1px solid #cbd5e1",
                }}
              />
              <div style={{ display: "flex", gap: 8, marginTop: "0.75rem", flexWrap: "wrap" }}>
                <button type="button" disabled={busy} onClick={saveUserDoc} style={btnPrimary}>
                  Save (merge)
                </button>
                <button type="button" disabled={busy} onClick={deleteUserDoc} style={btnDanger}>
                  Delete Firestore user doc
                </button>
                <button
                  type="button"
                  style={btnGhost}
                  onClick={() => {
                    setSelectedUserId(null);
                    setUserEditJson("");
                  }}
                >
                  Close editor
                </button>
              </div>
            </div>
          )}
        </div>
      )}

      {tab === "rides" && (
        <div style={card}>
          <button type="button" disabled={busy} onClick={loadRides} style={btnPrimary}>
            Load recent rides
          </button>
          <p style={{ fontSize: 13, color: "#64748b" }}>
            Up to 200 ride docs (default order). Use the Document tab for full edits.
          </p>
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14 }}>
              <thead>
                <tr style={{ textAlign: "left", borderBottom: "2px solid #e2e8f0" }}>
                  <th style={{ padding: "0.5rem" }}>Ride ID</th>
                  <th style={{ padding: "0.5rem" }}>Status</th>
                  <th style={{ padding: "0.5rem" }}>Sender</th>
                  <th style={{ padding: "0.5rem" }}>Driver</th>
                </tr>
              </thead>
              <tbody>
                {ridesRows.map((r) => (
                  <tr key={r.id} style={{ borderBottom: "1px solid #f1f5f9" }}>
                    <td style={{ padding: "0.5rem", fontFamily: "monospace", fontSize: 12 }}>{r.id}</td>
                    <td style={{ padding: "0.5rem" }}>{r.status ?? "—"}</td>
                    <td style={{ padding: "0.5rem", fontSize: 12 }}>{r.userId ?? "—"}</td>
                    <td style={{ padding: "0.5rem", fontSize: 12 }}>{r.driverId ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {tab === "activity" && (
        <div style={card}>
          <button type="button" disabled={busy} onClick={loadActivities} style={btnPrimary}>
            Load activity feed
          </button>
          <p style={{ fontSize: 13, color: "#64748b" }}>
            Shows timeline events from rides and notifications, including ride completion activity.
          </p>
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14 }}>
              <thead>
                <tr style={{ textAlign: "left", borderBottom: "2px solid #e2e8f0" }}>
                  <th style={{ padding: "0.5rem" }}>When</th>
                  <th style={{ padding: "0.5rem" }}>Source</th>
                  <th style={{ padding: "0.5rem" }}>Activity</th>
                  <th style={{ padding: "0.5rem" }}>Ride ID</th>
                  <th style={{ padding: "0.5rem" }}>Sender</th>
                  <th style={{ padding: "0.5rem" }}>Driver</th>
                  <th style={{ padding: "0.5rem" }}>User</th>
                  <th style={{ padding: "0.5rem" }}>Status</th>
                  <th style={{ padding: "0.5rem" }}>Message</th>
                </tr>
              </thead>
              <tbody>
                {activityRows.map((r) => (
                  <tr key={r.id} style={{ borderBottom: "1px solid #f1f5f9" }}>
                    <td style={{ padding: "0.5rem", whiteSpace: "nowrap" }}>{r.atText}</td>
                    <td style={{ padding: "0.5rem" }}>{r.source}</td>
                    <td style={{ padding: "0.5rem" }}>{r.activityType}</td>
                    <td style={{ padding: "0.5rem", fontFamily: "monospace", fontSize: 12 }}>
                      {r.rideId ?? "—"}
                    </td>
                    <td style={{ padding: "0.5rem", fontFamily: "monospace", fontSize: 12 }}>
                      {r.senderId ?? "—"}
                    </td>
                    <td style={{ padding: "0.5rem", fontFamily: "monospace", fontSize: 12 }}>
                      {r.driverId ?? "—"}
                    </td>
                    <td style={{ padding: "0.5rem", fontFamily: "monospace", fontSize: 12 }}>
                      {r.userId ?? "—"}
                    </td>
                    <td style={{ padding: "0.5rem" }}>{r.status ?? "—"}</td>
                    <td style={{ padding: "0.5rem", maxWidth: 420 }}>{r.message ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {tab === "inbox" && (
        <div style={card}>
          <button type="button" disabled={busy} onClick={loadInbox} style={btnPrimary}>
            Load inbox reports
          </button>
          <p style={{ fontSize: 13, color: "#64748b" }}>
            Reported issues from <code>bugReports</code> and report-like notifications.
          </p>
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14 }}>
              <thead>
                <tr style={{ textAlign: "left", borderBottom: "2px solid #e2e8f0" }}>
                  <th style={{ padding: "0.5rem" }}>When</th>
                  <th style={{ padding: "0.5rem" }}>Source</th>
                  <th style={{ padding: "0.5rem" }}>User ID</th>
                  <th style={{ padding: "0.5rem" }}>Email</th>
                  <th style={{ padding: "0.5rem" }}>Title</th>
                  <th style={{ padding: "0.5rem" }}>Description</th>
                  <th style={{ padding: "0.5rem" }}>Status</th>
                  <th style={{ padding: "0.5rem" }}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {inboxRows.map((r) => (
                  <tr key={`${r.source}-${r.id}`} style={{ borderBottom: "1px solid #f1f5f9" }}>
                    <td style={{ padding: "0.5rem", whiteSpace: "nowrap" }}>{r.createdAtText}</td>
                    <td style={{ padding: "0.5rem" }}>{r.source}</td>
                    <td style={{ padding: "0.5rem", fontFamily: "monospace", fontSize: 12 }}>{r.userId ?? "—"}</td>
                    <td style={{ padding: "0.5rem" }}>{r.userEmail ?? "—"}</td>
                    <td style={{ padding: "0.5rem" }}>{r.title ?? "—"}</td>
                    <td style={{ padding: "0.5rem", maxWidth: 360 }}>{r.description ?? "—"}</td>
                    <td style={{ padding: "0.5rem" }}>{r.status ?? "—"}</td>
                    <td style={{ padding: "0.5rem" }}>
                      {r.source === "bugReports" ? (
                        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                          <button type="button" style={btnGhost} disabled={busy} onClick={() => updateBugReportStatus(r.id, "in_progress")}>
                            In progress
                          </button>
                          <button type="button" style={btnGhost} disabled={busy} onClick={() => updateBugReportStatus(r.id, "resolved")}>
                            Resolve
                          </button>
                          <button type="button" style={btnGhost} disabled={busy} onClick={() => updateBugReportStatus(r.id, "closed")}>
                            Close
                          </button>
                        </div>
                      ) : (
                        "—"
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {tab === "document" && (
        <div style={card}>
          <h3 style={{ marginTop: 0 }}>Any document path</h3>
          <p style={{ fontSize: 13, color: "#64748b", marginTop: 0 }}>
            Examples: <code>users/&lt;uid&gt;</code>, <code>rides/&lt;id&gt;</code>,{" "}
            <code>rides/&lt;id&gt;/offers/&lt;offerId&gt;</code>
          </p>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center", marginBottom: 8 }}>
            <input
              value={explorerPath}
              onChange={(e) => setExplorerPath(e.target.value)}
              placeholder="users/abc123"
              style={{ flex: "1 1 280px", minWidth: 200, padding: "0.5rem 0.6rem" }}
            />
            <button type="button" disabled={busy} onClick={loadExplorerDoc} style={btnPrimary}>
              Load
            </button>
            <button type="button" disabled={busy} onClick={mergeExplorerDoc} style={btnGhost}>
              Save merge
            </button>
            <button type="button" disabled={busy} onClick={saveExplorerDoc} style={btnGhost}>
              Save replace
            </button>
            <button type="button" disabled={busy} onClick={deleteExplorerDoc} style={btnDanger}>
              Delete doc
            </button>
          </div>
          {explorerExists !== null && (
            <p style={{ fontSize: 13 }}>
              Status:{" "}
              <strong>{explorerExists ? "exists" : "missing"}</strong>
            </p>
          )}
          <textarea
            value={explorerJson}
            onChange={(e) => setExplorerJson(e.target.value)}
            rows={22}
            style={{
              width: "100%",
              fontFamily: "monospace",
              fontSize: 12,
              padding: "0.75rem",
              borderRadius: 8,
              border: "1px solid #cbd5e1",
            }}
          />
        </div>
      )}

      <p style={{ fontSize: 12, color: "#94a3b8", marginTop: "2rem" }}>
        Admin access is powerful. Use dedicated accounts, strong passwords, and audit changes in Firebase.
      </p>
    </div>
  );
}
