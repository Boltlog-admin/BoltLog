# Boltlog APK - Application Flow Analysis

## 📱 Application Overview
**Boltlog** is a goods transportation marketplace app (similar to inDrive) where users can:
- **Senders (Passengers)**: Request transport for goods by offering their price
- **Transporters (Drivers)**: View available deliveries and accept transport requests

**APK Details:**
- **Location**: `build\app\outputs\flutter-apk\app-release.apk`
- **Size**: 50.8MB
- **Version**: 2.4.0 (Build 302)
- **Package**: `com.example.boltlog`

---

## 🔄 Complete Application Flow

### 1. **App Initialization** (`main.dart`)
```
┌─────────────────────────────────┐
│  App Launch                      │
│  - Initialize Flutter            │
│  - Initialize Firebase           │
│  - Run BoltlogApp                │
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│  SplashScreen (3 seconds)       │
│  - Display logo & branding       │
│  - Check authentication state    │
└──────────────┬──────────────────┘
               │
               ├─── User Logged In? ──┐
               │                       │
               │                       ▼
               │              ┌─────────────────────┐
               │              │ Check User Role    │
               │              └─────────┬──────────┘
               │                        │
               │                        ├─── Driver? ──► TransporterNavigation
               │                        │
               │                        └─── Passenger? ──► MainNavigation
               │
               └─── Not Logged In? ──► AuthEntryScreen
```

### 2. **Authentication Flow**

#### **A. Auth Entry Screen** (`auth_entry_screen.dart`)
```
┌─────────────────────────────────┐
│  AuthEntryScreen                 │
│  - Role Selection (Sender/       │
│    Transporter)                  │
│  - Phone Number Input            │
│  - "Join Now" → SignupScreen     │
│  - "Log in" → LoginScreen        │
└──────────────┬──────────────────┘
               │
               ├─── Join Now ──► SignupScreen
               │
               └─── Log In ──► LoginScreen
```

#### **B. Signup Flow** (`signup_screen.dart`)
```
┌─────────────────────────────────┐
│  SignupScreen                    │
│  - Full Name                     │
│  - Email                         │
│  - Phone Number                  │
│  - Password                      │
│  - Confirm Password             │
│  - Role (Sender/Transporter)    │
└──────────────┬──────────────────┘
               │
               │ Create Firebase Account
               │ Create Firestore User Document
               │
               ▼
┌─────────────────────────────────┐
│  OTPVerificationScreen           │
│  - 6-digit OTP input             │
│  - Auto-verify on complete        │
│  - Resend code option            │
└──────────────┬──────────────────┘
               │
               │ Verify Phone Number
               │
               ▼
         Navigate to Home
         (Based on Role)
```

#### **C. Login Flow** (`login_screen.dart`)
```
┌─────────────────────────────────┐
│  LoginScreen                     │
│  - Phone/Email Input             │
│  - Password                      │
│  - Role Toggle (UI only)        │
│  - "Forgot Password?" link      │
└──────────────┬──────────────────┘
               │
               │ Firebase Email/Password Auth
               │
               ├─── Success ──► Check Role ──► Navigate
               │
               └─── Failure ──► Show Error
```

### 3. **Passenger (Sender) Flow**

#### **Main Navigation** (`main_navigation.dart`)
```
┌─────────────────────────────────┐
│  MainNavigation                  │
│  Bottom Navigation:              │
│  1. Home (HomeScreen)           │
│  2. History (RideHistoryScreen)  │
│  3. Profile (ProfileScreen)     │
└─────────────────────────────────┘
```

#### **Home Screen** (`home_screen.dart`)
```
┌─────────────────────────────────┐
│  HomeScreen                      │
│  - Welcome message               │
│  - Quick Actions Grid:           │
│    • Request Transport           │
│    • Delivery History            │
│    • Payment                     │
│    • Support                     │
│  - Recent Deliveries List        │
└──────────────┬──────────────────┘
               │
               └─── Request Transport ──► RideBookingScreen
```

#### **Ride Booking Flow** (`ride_booking_screen.dart`)
```
┌─────────────────────────────────┐
│  RideBookingScreen               │
│  Input Fields:                   │
│  - Pickup Location (Map picker)  │
│  - Dropoff Location (Map picker) │
│  - Package Description           │
│  - Package Type (Small/Medium/   │
│    Large/Fragile)                │
│  - Weight (kg)                   │
│  - Dimensions (LxWxH)           │
│  - Estimated Value (optional)    │
│  - Your Price Offer *             │
│  - Additional Notes              │
└──────────────┬──────────────────┘
               │
               │ Auto-calculate suggested price
               │
               │ Create Ride in Firestore
               │ Status: "pending"
               │
               ▼
┌─────────────────────────────────┐
│  Success → Return to Home        │
│  - Show success message          │
│  - Ride appears in History       │
└─────────────────────────────────┘
```

### 4. **Transporter (Driver) Flow**

#### **Transporter Navigation** (`transporter_navigation.dart`)
```
┌─────────────────────────────────┐
│  TransporterNavigation           │
│  Bottom Navigation:              │
│  1. Available (Dashboard)       │
│  2. Active (ActiveDeliveries)    │
│  3. Profile (ProfileScreen)      │
└─────────────────────────────────┘
```

#### **Transporter Dashboard** (`transporter_dashboard_screen.dart`)
```
┌─────────────────────────────────┐
│  TransporterDashboardScreen      │
│  - Stream of Available Rides     │
│    (Status: "pending")           │
│                                  │
│  For each ride card:             │
│  - Package Description           │
│  - Package Type & Weight         │
│  - Pickup Location               │
│  - Dropoff Location              │
│  - Price Offer                   │
│  - Estimated Value               │
│  - "Accept Delivery" Button      │
└──────────────┬──────────────────┘
               │
               │ Accept Ride
               │ Update Ride Status: "accepted"
               │ Assign Transporter ID
               │
               ▼
┌─────────────────────────────────┐
│  Ride moved to Active Deliveries│
│  - Removed from Available list   │
│  - Appears in Active tab         │
└─────────────────────────────────┘
```

#### **Active Deliveries** (`active_deliveries_screen.dart`)
```
┌─────────────────────────────────┐
│  ActiveDeliveriesScreen          │
│  - List of accepted rides        │
│  - Status tracking               │
│  - Navigation to delivery        │
│  - Chat with sender              │
└─────────────────────────────────┘
```

### 5. **Supporting Features**

#### **Location Services**
- **LocationPickerScreen**: Google Maps integration for selecting pickup/dropoff
- **SavedLocationsScreen**: Manage frequently used addresses
- Uses `geolocator` and `geocoding` packages

#### **Communication**
- **ChatScreen**: In-app messaging between sender and transporter
- Firebase Cloud Messaging for notifications

#### **Rating System**
- **RatingScreen**: Rate completed deliveries
- Stores ratings in Firestore

#### **Profile Management**
- **ProfileScreen**: View/edit user profile
- Update personal information
- View statistics

---

## 🔐 Authentication & Data Flow

### Firebase Services Used:
1. **Firebase Authentication**
   - Email/Password authentication
   - Phone number verification (OTP)
   - User session management

2. **Cloud Firestore**
   - User profiles (`users` collection)
   - Ride requests (`rides` collection)
   - Messages (`messages` collection)
   - Ratings (`ratings` collection)
   - Saved locations (`savedLocations` collection)

3. **Firebase Cloud Messaging**
   - Push notifications for ride updates
   - Chat message notifications

---

## 📊 Data Models

### User Model
```dart
- uid: String
- email: String
- displayName: String
- phoneNumber: String
- role: "Passenger" | "Driver"
- createdAt: DateTime
```

### Ride Model
```dart
- id: String
- userId: String (sender ID)
- transporterId: String? (assigned driver)
- pickupLocation: String
- dropoffLocation: String
- pickupLat/Lng: double?
- dropoffLat/Lng: double?
- packageDescription: String?
- packageType: "small" | "medium" | "large" | "fragile"
- weight: double?
- dimensions: String?
- estimatedValue: double?
- price: double (sender's offer)
- status: "pending" | "accepted" | "in_progress" | "completed" | "cancelled"
- notes: String?
- createdAt: DateTime
```

---

## 🎯 Key User Journeys

### Journey 1: Sender Requests Transport
1. Launch app → Splash → Auth (if needed)
2. Home Screen → "Request Transport"
3. Fill booking form:
   - Select pickup/dropoff locations
   - Enter package details
   - Set price offer
4. Submit → Ride created in Firestore
5. Wait for transporter acceptance

### Journey 2: Transporter Accepts Delivery
1. Launch app → Splash → Auth (if needed)
2. Transporter Dashboard → View available rides
3. Review ride details (locations, price, package info)
4. Tap "Accept Delivery"
5. Ride status changes to "accepted"
6. Ride moves to "Active Deliveries" tab
7. Can chat with sender, navigate to locations

### Journey 3: Complete Delivery
1. Transporter marks delivery as complete
2. Sender receives notification
3. Rating screen appears
4. Both parties rate each other
5. Ride status: "completed"
6. Payment processing (if integrated)

---

## 🛠️ Technical Stack

### Frontend
- **Framework**: Flutter (Dart)
- **State Management**: StreamBuilder (Firebase streams)
- **UI**: Material Design 3
- **Fonts**: Google Fonts (Inter, Plus Jakarta Sans)

### Backend Services
- **Authentication**: Firebase Auth
- **Database**: Cloud Firestore
- **Storage**: Firebase Storage (for images)
- **Messaging**: Firebase Cloud Messaging

### Maps & Location
- **Maps**: Google Maps Flutter
- **Location**: Geolocator, Geocoding

### Key Packages
- `firebase_core`, `firebase_auth`, `cloud_firestore`
- `google_maps_flutter`
- `geolocator`, `geocoding`
- `firebase_messaging`
- `image_picker`
- `google_fonts`

---

## 🔄 State Management Flow

### Real-time Updates
- **Rides**: Stream from Firestore (`streamAvailableRides()`, `streamUserRides()`)
- **Users**: Stream user profile updates
- **Messages**: Real-time chat via Firestore streams

### Navigation State
- Bottom navigation tabs maintain state
- Screen navigation uses MaterialPageRoute
- Auth state managed by Firebase Auth streams

---

## 📱 Screen Hierarchy

```
BoltlogApp
└── SplashScreen
    ├── AuthEntryScreen
    │   ├── SignupScreen
    │   │   └── OTPVerificationScreen
    │   └── LoginScreen
    │       └── ForgotPasswordScreen
    │
    ├── MainNavigation (Passenger)
    │   ├── HomeScreen
    │   │   └── RideBookingScreen
    │   │       ├── LocationPickerScreen
    │   │       └── SavedLocationsScreen
    │   ├── RideHistoryScreen
    │   └── ProfileScreen
    │
    └── TransporterNavigation (Driver)
        ├── TransporterDashboardScreen
        ├── ActiveDeliveriesScreen
        │   └── ChatScreen
        └── ProfileScreen
```

---

## ⚠️ Important Notes

1. **Phone Authentication**: Currently uses Firebase Phone Auth, but OTP verification may need backend setup
2. **Maps API Key**: Requires Google Maps API key in `AndroidManifest.xml`
3. **Permissions**: App requires location permissions for map features
4. **Payment**: Payment integration is placeholder (marked as TODO)
5. **Social Login**: Social login buttons are UI-only (not implemented)

---

## 🚀 Build Information

- **Build System**: Gradle 8.14
- **Android Gradle Plugin**: 8.11.1
- **Kotlin**: 2.2.20
- **Min SDK**: 21 (Android 5.0)
- **Target SDK**: Latest (as per Flutter defaults)
- **Java Version**: 17

---

## 📝 Summary

Boltlog is a **bid-based goods transportation marketplace** where:
- **Senders** create transport requests with their price offers
- **Transporters** browse available requests and accept deliveries
- Real-time updates via Firebase Firestore streams
- In-app chat for communication
- Rating system for completed deliveries
- Google Maps integration for location services

The app follows a clean separation between passenger and transporter flows, with role-based navigation and feature access.
