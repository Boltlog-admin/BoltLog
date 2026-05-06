const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const STORAGE_BUCKET = 'boltlog.firebasestorage.app';

function getStorageBucket() {
  return admin.storage().bucket(STORAGE_BUCKET);
}

/**
 * Lazy-load Vision so `firebase deploy` source discovery never executes
 * `require("@google-cloud/vision")` at module load (can crash with a generic error in CI).
 */
let visionClient;
function getVisionClient() {
  if (!visionClient) {
    const vision = require('@google-cloud/vision');
    visionClient = new vision.ImageAnnotatorClient();
  }
  return visionClient;
}

/**
 * Callable function: upload image to Storage.
 * Client sends: { path: string, imageBase64: string }
 * Returns: { path: string }
 * Requires: authenticated user (request.auth.uid)
 */
exports.uploadDriverImage = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be signed in to upload images',
    );
  }

  const { path, imageBase64 } = data;
  if (!path || !imageBase64) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'path and imageBase64 are required',
    );
  }

  if (!path.startsWith('drivers/') && !path.startsWith('senders/')) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Path must start with drivers/ or senders/',
    );
  }

  try {
    const buffer = Buffer.from(imageBase64, 'base64');
    const file = getStorageBucket().file(path);
    await file.save(buffer, {
      metadata: { contentType: 'image/jpeg' },
    });
    return { path };
  } catch (err) {
    console.error('Upload error:', err);
    throw new functions.https.HttpsError(
      'internal',
      err.message || 'Upload failed',
    );
  }
});

/**
 * Firestore trigger: when a driver profile is created/updated and has
 * required documents (license + selfie), automatically verify the
 * account using a simple face-based check.
 */
exports.onDriverDocumentsUpdated = functions.firestore
  .document('users/{uid}')
  .onWrite(async (change, context) => {
    const after = change.after.exists ? change.after.data() : null;
    if (!after) {
      return null;
    }

    const role = (after.role || '').toLowerCase();
    if (role !== 'driver') {
      return null;
    }

    const {
      driverLicenseImageUrl,
      selfieImageUrl,
      verificationStatus,
    } = after;

    const before = change.before.exists ? change.before.data() : null;
    if (before) {
      const {
        driverLicenseImageUrl: prevDriverLicenseImageUrl,
        selfieImageUrl: prevSelfieImageUrl,
      } = before;

      const licenseImageUnchanged =
        prevDriverLicenseImageUrl === driverLicenseImageUrl;
      const selfieImageUnchanged = prevSelfieImageUrl === selfieImageUrl;

      if (licenseImageUnchanged && selfieImageUnchanged) {
        return null;
      }
    }

    if (!driverLicenseImageUrl || !selfieImageUrl) {
      return null;
    }

    if (
      verificationStatus === 'verified' ||
      verificationStatus === 'auto_verified'
    ) {
      return null;
    }

    const bucketName = 'boltlog.firebasestorage.app';

    async function analyzeFaces(gcsPath) {
      try {
        const gcsUri = `gs://${bucketName}/${gcsPath}`;
        const [result] = await getVisionClient().faceDetection(gcsUri);
        const faces = result.faceAnnotations || [];
        return {
          hasFace: faces.length > 0,
          faceCount: faces.length,
        };
      } catch (err) {
        console.error('Vision API error for', gcsPath, err);
        return {
          hasFace: false,
          faceCount: 0,
          error: err.message || String(err),
        };
      }
    }

    let autoVerified = false;

    try {
      const [idAnalysis, selfieAnalysis] = await Promise.all([
        analyzeFaces(driverLicenseImageUrl),
        analyzeFaces(selfieImageUrl),
      ]);

      const selfieOk = !!selfieAnalysis.hasFace;
      const licenseOk = !!idAnalysis.hasFace;

      autoVerified = selfieOk;

      let finalStatus = autoVerified ? 'auto_verified' : 'needs_review';
      let verificationNotes = null;

      if (!selfieOk) {
        finalStatus = 'needs_review';
        verificationNotes =
          'We could not clearly detect your face in the selfie. Please retake a selfie in good lighting with only your face visible.';
      } else if (!licenseOk) {
        finalStatus = 'auto_verified';
        verificationNotes =
          'Your account is verified, but we could not clearly detect the face on your licence photo. If requested, please re-upload a clearer photo of your licence.';
      }

      await change.after.ref.update({
        verificationStatus: finalStatus,
        verifiedAt: finalStatus === 'auto_verified' ? new Date().toISOString() : null,
        verificationNotes,
      });
    } catch (err) {
      console.error('Error during automatic verification:', err);
      await change.after.ref.update({
        verificationStatus: 'needs_review',
        verificationNotes:
          'Automatic verification error. Please contact support or re-upload your documents.',
      });
    }

    return null;
  });

/**
 * When a notification document is created, send a real FCM push to the user's device.
 */
exports.onNotificationCreated = functions.firestore
  .document('notifications/{notificationId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return null;

    const { userId, title, message, type, rideId } = data;
    if (!userId || !title || !message) {
      console.warn('onNotificationCreated: missing userId, title, or message');
      return null;
    }

    let fcmToken;
    try {
      const userSnap = await admin.firestore().collection('users').doc(userId).get();
      if (!userSnap.exists) {
        console.warn('onNotificationCreated: user not found', userId);
        return null;
      }
      fcmToken = userSnap.data().fcmToken || null;
    } catch (e) {
      console.error('onNotificationCreated: error reading user', e);
      return null;
    }

    if (!fcmToken) {
      console.warn('onNotificationCreated: no fcmToken for user', userId);
      return null;
    }

    const t = title || 'Boltlog';
    const b = message;
    const payload = {
      token: fcmToken,
      notification: {
        title: t,
        body: b,
      },
      data: {
        type: String(type != null ? type : ''),
        rideId: String(rideId != null ? rideId : ''),
        userId: String(userId),
        title: String(t),
        message: String(b),
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'default',
          sound: 'default',
          defaultSound: true,
          defaultVibrateTimings: true,
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        },
      },
      apns: {
        headers: {
          'apns-priority': '10',
        },
        payload: {
          aps: {
            alert: {
              title: t,
              body: b,
            },
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    try {
      await admin.messaging().send(payload);
      console.log('FCM sent to', userId, 'for notification', context.params.notificationId);
    } catch (e) {
      console.error('onNotificationCreated: FCM send failed', e);
    }
    return null;
  });

// --- Transporter commit (Admin SDK; bypasses client Firestore rules) ---

function rideDriverSlotOpenFromField(driverIdField) {
  if (driverIdField === null || driverIdField === undefined) return true;
  const d = String(driverIdField).trim();
  if (!d) return true;
  const lower = d.toLowerCase();
  return lower === 'unassigned' || lower === 'none' || lower === 'null';
}

function senderUidString(userIdField) {
  if (userIdField === null || userIdField === undefined) return null;
  if (typeof userIdField === 'string') return userIdField;
  if (typeof userIdField === 'object' && userIdField.path) {
    const parts = String(userIdField.path).split('/');
    return parts[parts.length - 1] || null;
  }
  return String(userIdField);
}

/** One active transporter assignment at a time (mirrors former client checks). */
async function assertTransporterFreeForAcceptance(db, transporterId, rideIdBeingAccepted) {
  const delivering = await db
    .collection('rides')
    .where('driverId', '==', transporterId)
    .where('status', 'in', ['in_progress', 'parcel_collected'])
    .limit(10)
    .get();
  for (const doc of delivering.docs) {
    if (doc.id === rideIdBeingAccepted) continue;
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Finish your current delivery before accepting another request.',
    );
  }

  const reserved = await db
    .collection('rides')
    .where('acceptedTransporterId', '==', transporterId)
    .where('status', '==', 'pending')
    .limit(25)
    .get();
  for (const doc of reserved.docs) {
    if (doc.id === rideIdBeingAccepted) continue;
    const d = doc.data();
    const driver = d.driverId ? String(d.driverId).trim() : '';
    if (driver) continue;
    throw new functions.https.HttpsError(
      'failed-precondition',
      'You already have a booking in progress. Complete delivery or cancel it before accepting another.',
    );
  }

  const awaitingSender = await db
    .collection('rides')
    .where('awaitingSenderConfirmDriverId', '==', transporterId)
    .where('status', '==', 'pending')
    .limit(25)
    .get();
  for (const doc of awaitingSender.docs) {
    if (doc.id === rideIdBeingAccepted) continue;
    throw new functions.https.HttpsError(
      'failed-precondition',
      'You are already waiting for another sender to confirm a delivery.',
    );
  }
}

exports.transporterCommitRide = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Sign in required');
  }

  const rideId = typeof data.rideId === 'string' ? data.rideId.trim() : '';
  const transporterId =
    typeof data.transporterId === 'string' ? data.transporterId.trim() : '';
  if (!rideId || !transporterId) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'rideId and transporterId are required',
    );
  }

  if (context.auth.uid !== transporterId) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Caller must match transporterId',
    );
  }

  const db = admin.firestore();
  try {
    const out = await commitTransporterRideInternal(db, rideId, transporterId);
    if (out.wroteCommit) {
      try {
        await createTransporterCommitNotifications(
          db,
          rideId,
          transporterId,
          out.senderUserId,
        );
      } catch (notifyErr) {
        console.error('transporterCommitRide notifications failed', notifyErr);
      }
    }
    return {
      ok: true,
      wroteCommit: out.wroteCommit,
      senderUserId: out.senderUserId || null,
    };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) {
      throw e;
    }
    console.error('transporterCommitRide', e);
    throw new functions.https.HttpsError(
      'internal',
      e.message || 'Transaction failed',
    );
  }
});

function readBearerTokenFromHeaders(headers) {
  const authHeader = headers.authorization || headers.Authorization || '';
  if (typeof authHeader !== 'string') return null;
  const parts = authHeader.split(' ');
  if (parts.length !== 2) return null;
  if (parts[0].toLowerCase() !== 'bearer') return null;
  const token = parts[1].trim();
  return token || null;
}

// HTTP endpoint fallback for Android builds where callable auth channel may fail.
exports.transporterCommitRideHttp = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  if (req.method !== 'POST') {
    res.status(405).json({error: 'method-not-allowed'});
    return;
  }

  try {
    const token = readBearerTokenFromHeaders(req.headers);
    if (!token) {
      res.status(401).json({error: 'missing-auth-token'});
      return;
    }
    const decoded = await admin.auth().verifyIdToken(token, true);
    const authUid = (decoded && decoded.uid) || '';
    if (!authUid) {
      res.status(401).json({error: 'invalid-auth-token'});
      return;
    }

    const body = req.body || {};
    const rideId = typeof body.rideId === 'string' ? body.rideId.trim() : '';
    const transporterId =
      typeof body.transporterId === 'string' ? body.transporterId.trim() : '';
    if (!rideId || !transporterId) {
      res.status(400).json({error: 'rideId and transporterId are required'});
      return;
    }
    if (authUid !== transporterId) {
      res.status(403).json({error: 'Caller must match transporterId'});
      return;
    }

    const db = admin.firestore();
    const out = await commitTransporterRideInternal(db, rideId, transporterId);
    if (out.wroteCommit) {
      try {
        await createTransporterCommitNotifications(
          db,
          rideId,
          transporterId,
          out.senderUserId,
        );
      } catch (notifyErr) {
        console.error('transporterCommitRideHttp notifications failed', notifyErr);
      }
    }

    res.status(200).json({
      ok: true,
      wroteCommit: !!out.wroteCommit,
      senderUserId: out.senderUserId || null,
    });
  } catch (e) {
    const code = e instanceof functions.https.HttpsError ? e.code : 'internal';
    const message =
      (e instanceof functions.https.HttpsError ? e.message : null) ||
      e.message ||
      'Transaction failed';
    console.error('transporterCommitRideHttp', e);
    res.status(500).json({error: code, message: String(message)});
  }
});

async function commitTransporterRideInternal(db, rideId, transporterId) {
  await assertTransporterFreeForAcceptance(db, transporterId, rideId);
  const rideRef = db.collection('rides').doc(rideId);
  return db.runTransaction(async (transaction) => {
      const rideSnap = await transaction.get(rideRef);
      if (!rideSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Ride not found');
      }

      const rideData = rideSnap.data();
      const senderUid = senderUidString(rideData.userId);
      if (senderUid && senderUid === transporterId) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Cannot accept your own delivery request',
        );
      }

      const rideStatus = rideData.status || 'open';
      const priceStatus = rideData.priceStatus;
      const currentDriverId = rideData.driverId
        ? String(rideData.driverId).trim()
        : '';

      const awaiting = rideData.awaitingSenderConfirmDriverId
        ? String(rideData.awaitingSenderConfirmDriverId).trim()
        : '';

      if (
        awaiting === transporterId &&
        (rideStatus === 'pending' || rideStatus === 'open')
      ) {
        return { wroteCommit: false, senderUserId: senderUid };
      }

      if (
        currentDriverId === transporterId &&
        ['in_progress', 'parcel_collected', 'completed'].includes(rideStatus)
      ) {
        return { wroteCommit: false, senderUserId: senderUid };
      }

      if (rideStatus === 'cancelled') {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Ride is no longer available for acceptance',
        );
      }

      if (awaiting && awaiting !== transporterId) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Another transporter is already waiting for sender confirmation',
        );
      }

      const negotiatingId = rideData.negotiatingTransporterId
        ? String(rideData.negotiatingTransporterId).trim()
        : '';
      const acceptedForId = rideData.acceptedTransporterId
        ? String(rideData.acceptedTransporterId).trim()
        : '';

      const canAcceptActiveNegotiation =
        rideStatus === 'pending' &&
        negotiatingId === transporterId &&
        (priceStatus === 'pending' ||
          priceStatus === null ||
          priceStatus === undefined);

      if (
        rideStatus !== 'open' &&
        !(rideStatus === 'pending' && priceStatus === 'accepted') &&
        !canAcceptActiveNegotiation
      ) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Ride is no longer available for acceptance',
        );
      }

      if (rideStatus === 'pending' && priceStatus === 'accepted') {
        if (acceptedForId && acceptedForId !== transporterId) {
          throw new functions.https.HttpsError(
            'failed-precondition',
            'This request was approved for another transporter',
          );
        }
      }

      if (
        !rideDriverSlotOpenFromField(rideData.driverId) &&
        currentDriverId &&
        currentDriverId !== transporterId
      ) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Ride has already been accepted by another transporter',
        );
      }

      const price = typeof rideData.price === 'number' ? rideData.price : 0;
      const counterOffer =
        typeof rideData.counterOffer === 'number' ? rideData.counterOffer : null;
      const lockedFare =
        rideData.finalPrice != null
          ? Number(rideData.finalPrice)
          : counterOffer != null
            ? counterOffer
            : price;

      const updatePayload = {
        awaitingSenderConfirmDriverId: transporterId,
        negotiatingTransporterId: transporterId,
        status: 'pending',
        updatedAt: new Date().toISOString(),
      };

      if (rideData.finalPrice == null) {
        updatePayload.finalPrice = lockedFare;
      }

      if (canAcceptActiveNegotiation) {
        updatePayload.counterOffer = admin.firestore.FieldValue.delete();
        updatePayload.priceStatus = 'accepted';
      }

      transaction.update(rideRef, updatePayload);
      return { wroteCommit: true, senderUserId: senderUid };
    });
}

async function createTransporterCommitNotifications(
  db,
  rideId,
  transporterId,
  senderUserId,
) {
  const senderId = senderUserId ? String(senderUserId).trim() : '';
  const driverId = String(transporterId || '').trim();
  if (!senderId || !driverId) return;
  const now = new Date().toISOString();
  const notifications = db.collection('notifications');

  await Promise.all([
    notifications.add({
      userId: senderId,
      type: 'transporter_awaits_sender_confirm',
      title: 'Transporter accepted your request',
      message:
        'A transporter is ready to deliver. Open the request to confirm or view their profile.',
      rideId,
      isRead: false,
      createdAt: now,
      data: { rideId },
    }),
    notifications.add({
      userId: driverId,
      type: 'waiting_sender_confirm',
      title: 'Waiting for sender',
      message:
        'The sender must confirm before the trip starts and the map opens.',
      rideId,
      isRead: false,
      createdAt: now,
      data: { rideId },
    }),
  ]);
}

// Org policies may block public invoker IAM on HTTPS functions.
// This trigger-based queue keeps transporter commit working without open invoker bindings.
exports.onTransporterCommitRequestCreated = functions.firestore
  .document('transporterCommitRequests/{requestId}')
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const rideId = typeof data.rideId === 'string' ? data.rideId.trim() : '';
    const transporterId =
      typeof data.transporterId === 'string' ? data.transporterId.trim() : '';
    const requesterUid =
      typeof data.requesterUid === 'string' ? data.requesterUid.trim() : '';

    if (!rideId || !transporterId || !requesterUid) {
      await snap.ref.update({
        status: 'error',
        errorCode: 'invalid-argument',
        errorMessage: 'rideId, transporterId, requesterUid are required',
        updatedAt: new Date().toISOString(),
      });
      return null;
    }
    if (requesterUid !== transporterId) {
      await snap.ref.update({
        status: 'error',
        errorCode: 'permission-denied',
        errorMessage: 'requesterUid must match transporterId',
        updatedAt: new Date().toISOString(),
      });
      return null;
    }

    try {
      const out = await commitTransporterRideInternal(
        admin.firestore(),
        rideId,
        transporterId,
      );
      if (out.wroteCommit) {
        try {
          await createTransporterCommitNotifications(
            admin.firestore(),
            rideId,
            transporterId,
            out.senderUserId,
          );
        } catch (notifyErr) {
          console.error(
            'onTransporterCommitRequestCreated notifications failed',
            notifyErr,
          );
        }
      }
      await snap.ref.update({
        status: 'done',
        wroteCommit: !!out.wroteCommit,
        senderUserId: out.senderUserId || null,
        updatedAt: new Date().toISOString(),
      });
    } catch (e) {
      const code = e instanceof functions.https.HttpsError ? e.code : 'internal';
      const msg =
        (e instanceof functions.https.HttpsError ? e.message : null) ||
        e.message ||
        'Transaction failed';
      await snap.ref.update({
        status: 'error',
        errorCode: code,
        errorMessage: String(msg),
        updatedAt: new Date().toISOString(),
      });
    }
    return null;
  });

function assertAdminCaller(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Sign in required');
  }
  const claims = context.auth.token || {};
  const isAdmin = claims.admin === true;
  if (!isAdmin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Admin privileges required',
    );
  }
}

exports.adminSetUserPassword = functions.https.onCall(async (data, context) => {
  assertAdminCaller(context);
  const uid = typeof data.uid === 'string' ? data.uid.trim() : '';
  const newPassword =
    typeof data.newPassword === 'string' ? data.newPassword : '';
  if (!uid || !newPassword) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'uid and newPassword are required',
    );
  }
  if (newPassword.length < 6) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Password must be at least 6 characters',
    );
  }
  await admin.auth().updateUser(uid, {password: newPassword});
  return {ok: true};
});

exports.adminSendPasswordResetEmail = functions.https.onCall(
  async (data, context) => {
    assertAdminCaller(context);
    const uid = typeof data.uid === 'string' ? data.uid.trim() : '';
    if (!uid) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'uid is required',
      );
    }
    const user = await admin.auth().getUser(uid);
    if (!user.email) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Target user has no email',
      );
    }
    const link = await admin.auth().generatePasswordResetLink(user.email);
    return {ok: true, email: user.email, resetLink: link};
  },
);

exports.adminResetAccount = functions.https.onCall(async (data, context) => {
  assertAdminCaller(context);
  const uid = typeof data.uid === 'string' ? data.uid.trim() : '';
  if (!uid) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'uid is required',
    );
  }
  const now = new Date().toISOString();
  await admin.auth().updateUser(uid, {disabled: true});
  await admin
    .firestore()
    .collection('users')
    .doc(uid)
    .set(
      {
        accountStatus: 'reset',
        accountResetAt: now,
        accountResetBy: context.auth.uid,
        isAvailable: false,
        fcmToken: admin.firestore.FieldValue.delete(),
        fcmTokenUpdatedAt: admin.firestore.FieldValue.delete(),
      },
      {merge: true},
    );
  return {ok: true, disabled: true};
});
