# Boltlog – Flow of Logic (Detailed)

This document describes the end-to-end flow of logic in the Boltlog app: app startup, role-based navigation, ride creation, driver discovery, negotiation, acceptance, cancellation, and notifications.

---

## 1. App startup and entry

1. **`main.dart`**
   - Flutter binding, Firebase init, Firestore offline persistence, Crashlytics, theme load.
   - FCM: `FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler)`.
   - Background handler: on message, writes to `notifications` with `userId`, `type`, `title`, `message`, `rideId`, `data`, `isRead`, `createdAt`.
   - `NotificationService().initialize()` (permission, foreground/background handlers, token).
   - `ConnectivityService()`.
   - `runApp(BoltlogApp())` → `MaterialApp(home: AppInitializer())`.

2. **`AppInitializer`**
   - Waits for Firebase Auth and any initial setup, then shows **SplashScreen**.

3. **`SplashScreen`**
   - If **no user**: after short delay → `AuthEntryScreen`.
   - If **user logged in**: `UserService.getUser(uid)` (cache then server), read `role`.
   - **Driver** (`role == 'driver'`) → `TransporterNavigation` (pushAndRemoveUntil, clear stack).
   - **Other** (sender/passenger/unknown) → `MainNavigation` (pushAndRemoveUntil, clear stack).

---

## 2. Role-based shells

- **Sender**: `MainNavigation` (bottom nav: Home, History, Profile, etc.). Home shows “Request Transport”, “Recent Deliveries”, active rides.
- **Driver**: `TransporterNavigation` (Driver Dashboard, Active Deliveries, Profile, etc.).

Both shells run **pending notification handling** in a post-frame callback:
- `NotificationService.getPendingRideId()` (consumes static `pendingRideId`).
- If non-null: `RideService().getRideById(rideId)` → push **RequestDetailScreen(ride)** so notification tap opens that ride (deep link).
- Also ensure FCM token is saved for current user.

---

## 3. Sender: creating a ride (request transport)

1. **Home** → “Request Transport” → **RideBookingScreen**.
2. **RideBookingScreen**
   - Pickup/dropoff: free text or **AddressAutocompleteField** (Places Autocomplete), or **LocationPickerScreen** / **SavedLocationsScreen**. Sets `_pickupLat/Lng`, `_dropoffLat/Lng`.
   - Transport type, package type, weight/dimensions, notes, payment method (e.g. cash).
   - **Pricing**: `PricingService` uses `RoutingService.getRouteDistance()` (Directions API) when coordinates exist → suggested price; user can set a minimum floor.
   - On submit: check no other active ride for user, build **RideModel** (status `'open'`), call **`RideService().createRide(ride)`**.
3. **`RideService.createRide`**
   - Writes ride to `rides/{rideId}`.
   - **Notify nearby drivers**: `UserService.getNearbyDriversOnce(pickupLat, pickupLng)` (drivers within radius), then for each driver `NotificationService.createNotification(...)` with `rideId`, `type: 'new_request'`, etc.
   - `createNotification` writes to `notifications` (title, message, type, rideId, data). Cloud Function `onNotificationCreated` (when deployed) reads `users/{userId}.fcmToken` and sends FCM (notification + data.rideId).
4. **After create**
   - Success → `pushReplacement` to **ActiveRideTrackingScreen(ride)** so sender tracks the request and can cancel or later accept an offer.

---

## 4. Driver: seeing and opening a request

1. **Transporter dashboards** (e.g. **DriverDashboardScreen**, **TransporterDashboardScreen**)
   - Stream open/pending rides (e.g. `RideService.streamOpenRides()` or equivalent).
   - **Distance filter**: `filterAndSortRidesByDistance(rides, driverLat, driverLng)` (from `ride_distance_utils.dart`) so driver sees only **nearby** requests, sorted by distance; UI shows “X km away”.
2. Driver taps a request → **RequestDetailScreen(ride)**.
3. **RequestDetailScreen**
   - Shows pickup/dropoff, map (optional route polyline via **RoutingService.getRoute**), price, package info.
   - If driver not verified (documents): message “Verify your documents to accept or negotiate”.
   - **Negotiation**: driver can **accept** sender’s price or **counter-offer** (+10% / +20% / +30% or custom). Counter-offer writes to `rides/{rideId}/offers` (or ride/offers subcollection) and updates ride (e.g. `counterOffer`, `priceStatus`); **NotificationService** notifies sender (e.g. `counter_offer`).
   - **Earnings**: “You’ll receive $X.XX” = `(finalPrice ?? price) * (1 - PricingService.platformFeePercentage)`.
   - **Accept (driver)** when price agreed: **`RideService().acceptRide(ride.id!, transporterId)`** → sets `driverId`, status → `in_progress`, deducts platform fee when applicable.
   - **Cancel delivery**: **`_showTransporterCancelDialog`** → **`RideService().cancelRideWithReason(..., cancelledBy: 'transporter')`**; sender is notified.

---

## 5. Sender: viewing offers and accepting (negotiation)

1. Sender sees request on **ActiveRideTrackingScreen** (streamed via `RideService.streamRideById(rideId)`).
2. When there are offers or counter-offers, sender can go to **TransporterViewersScreen(rideId)** (e.g. “Who’s viewing” / list of transporters) — entry point may be from a CTA on tracking or home.
3. **TransporterViewersScreen**
   - Streams “viewers” (e.g. `RideService.streamOnlineViewers(rideId)`).
   - Button “Choose Transporter” → **TransporterSelectionScreen(rideId)**.
4. **TransporterSelectionScreen**
   - Streams ride and **offers** (e.g. `RideService.streamOffers(rideId)`).
   - For each offer: transporter info, “Their bid”, “~X min to pickup” (Distance Matrix if used).
   - **Accept offer**:
     - **Direct accept**: **`RideService().acceptRide(rideId, transporterId)`** then **`markSelectedOffer`**.
     - **After negotiation**: sender accepts counter-offer via **`RideService().respondToCounterOffer(rideId, offerId, accepted: true)`** (and optionally sender counter-offer with `senderCounterOffer`). Ride gets `finalPrice`; transporter is notified (“Offer accepted”); transporter then calls **acceptRide** to confirm and start delivery.
   - Commission/fee: uses `finalPrice` (or `price`) and **PricingService.platformFeePercentage**.

---

## 6. Ride status and lifecycle

- **RideModel** fields used in flow: `status`, `userId`, `driverId`, `price`, `finalPrice`, `counterOffer`, `priceStatus`, `cancelledAt`, `cancelledBy`, `cancellationReason`, `acceptedTransporterId`, etc.
- **Status progression**: `open` → (driver counters / sender accepts) → `pending` (negotiation) → driver accepts → `in_progress` → `parcel_collected` → `completed` (or `cancelled`).
- **Sender confirmations (Firestore fields, client-only; no Cloud Function required)**:
  - After transporter **markPickedUp**: `pickupMarkedByDriverAt` → sender taps **Confirm parcel collected** → `pickupConfirmedBySenderAt` (optional acknowledgment; status stays `parcel_collected`).
  - After transporter **markDelivered**: `deliveryMarkedByDriverAt` (status still `parcel_collected`) → sender taps **Confirm parcel delivered** → `senderConfirmDeliveryComplete` sets `status: completed`, `completedAt`, `deliveryConfirmedBySenderAt`.
- **ActiveRideTrackingScreen** shows status message and timeline; when `driverId != null`, sender can open **ChatScreen** or (when completed) **RatingScreen**.

---

## 7. Cancellation (inDrive-style)

- **Sender cancels**
  - From **ActiveRideTrackingScreen**: “Cancel request” → **`_showCancelDialog`** → **`RideService().cancelRideWithReason(..., cancelledBy: 'sender')`**.
  - Dialog: free vs late cancellation (e.g. **`RideService().isFreeCancellation(ride)`**), reason required; transporter is notified.
- **Transporter cancels**
  - From **RequestDetailScreen**: “Cancel delivery” → **`_showTransporterCancelDialog`** → **`cancelRideWithReason(..., cancelledBy: 'transporter')`**; sender is notified.

---

## 8. Notifications and deep link

- **NotificationService**
  - Static **pendingRideId** set when FCM payload has `data.rideId` (e.g. in `onMessageOpenedApp` and `getInitialMessage()`).
  - **getPendingRideId()** returns and clears it (consumed once after app open).
- **MainNavigation / TransporterNavigation** (post-frame): if `getPendingRideId()` non-null → **RequestDetailScreen(ride)** so notification tap opens that request.
- **Creating a notification**: `NotificationService.createNotification(...)` writes to Firestore `notifications`; Cloud Function **onNotificationCreated** (when deployed) sends FCM to user’s `fcmToken` with `data.rideId` and `data.type` for deep link.

---

## 9. Key services and files

| Concern | Service / util | Main methods / usage |
|--------|----------------|------------------------|
| Ride CRUD, lifecycle | **RideService** | `createRide`, `getRideById`, `streamRideById`, `acceptRide`, `submitCounterOffer`, `respondToCounterOffer`, `cancelRideWithReason`, `isFreeCancellation`, `streamOpenRides`, `streamOffers`, `streamOnlineViewers`, `markSelectedOffer` |
| Pricing / commission | **PricingService** | `platformFeePercentage`, recommended price from distance, price from route |
| Routing / distance | **RoutingService** | `getRoute`, `getRouteDistance`, `getOptimizedRoute` |
| Distance filter (driver list) | **ride_distance_utils** | `filterAndSortRidesByDistance`, `distanceToPickupKm` |
| Nearby drivers | **UserService** | `getNearbyDriversOnce` (for notify on create) |
| Notifications | **NotificationService** | `initialize`, `createNotification`, `pendingRideId` / `getPendingRideId`, `saveTokenToUser` |
| Places / address | **PlacesAutocompleteService** | Used by **AddressAutocompleteField** |

---

## 10. Summary flow (high level)

1. **App** → Splash → Auth or role-based shell (MainNavigation vs TransporterNavigation).
2. **Sender**: Book ride (RideBookingScreen) → createRide → notify nearby drivers → ActiveRideTrackingScreen; optionally TransporterViewersScreen → TransporterSelectionScreen → accept offer / respondToCounterOffer.
3. **Driver**: Dashboard (rides filtered/sorted by distance) → RequestDetailScreen → counter-offer or accept → acceptRide / cancel delivery (cancelRideWithReason).
4. **Notifications**: Firestore + (when deployed) Cloud Function FCM; tap sets pendingRideId → shell opens RequestDetailScreen(ride).
5. **Cancellation**: Sender or transporter cancels with reason; other party notified; free vs late logic via isFreeCancellation.

This is the detailed flow of logic for Boltlog as implemented in the codebase.
