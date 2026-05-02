# Deduction Logic Update

## Overview
Updated the deduction logic so that the 2% fee is only deducted **after negotiation when the request has been accepted** by the sender, not immediately when the transporter accepts. If the wallet balance is insufficient, the transporter is notified to top up their account.

---

## ✅ Changes Implemented

### 1. **Deduction Timing**

#### Old Behavior:
- ❌ Fee deducted immediately when transporter accepts ride
- ❌ Error thrown if balance insufficient

#### New Behavior:
- ✅ Fee deducted **only after negotiation when sender accepts**
- ✅ If balance insufficient, transporter receives notification to top up
- ✅ Ride can still be accepted, but deduction happens when negotiation completes

---

### 2. **Updated Methods**

#### `acceptRide()` - Updated
**Location:** `lib/services/ride_service.dart`

**Changes:**
- ✅ Removed immediate deduction
- ✅ Ride accepted without charging
- ✅ Balance checked after acceptance
- ✅ Notification sent if balance insufficient

**Flow:**
1. Transporter accepts ride
2. Ride status → `'in_progress'`
3. Balance checked
4. If insufficient → Notification sent to transporter
5. Deduction happens later when negotiation completes

#### `respondToCounterOffer()` - Updated
**Location:** `lib/services/ride_service.dart`

**Changes:**
- ✅ Deduction happens when sender accepts counter-offer
- ✅ Balance checked before deduction
- ✅ If insufficient → Error thrown + Notification sent
- ✅ Transaction fails if balance insufficient

**Flow:**
1. Sender accepts counter-offer (negotiation complete)
2. Balance checked
3. If sufficient → Fee deducted, ride updated
4. If insufficient → Error thrown, notification sent, transaction fails

---

### 3. **New Helper Methods**

#### `checkBalanceAndNotify()`
**Purpose:** Check balance and send notification if insufficient

**Parameters:**
- `transporterId`: Transporter's user ID
- `requiredAmount`: Amount needed (2% of ride price)

**Returns:** `bool` - true if sufficient, false if insufficient

**Behavior:**
- Checks transporter's wallet balance
- If insufficient, creates notification
- Returns false if insufficient

#### `deductAcceptanceFee()`
**Purpose:** Deduct the 2% fee from transporter's wallet

**Parameters:**
- `transporterId`: Transporter's user ID
- `ridePrice`: Final negotiated price

**Behavior:**
- Calculates 2% fee
- Deducts from wallet balance
- Throws error if insufficient

---

### 4. **Notification System**

#### Notification Type: `insufficient_balance`

**Fields:**
- `type`: `'insufficient_balance'`
- `title`: `'Insufficient Balance'`
- `message`: `'Your wallet balance ($X.XX) is insufficient. Please top up $Y.YY to complete this request.'`
- `rideId`: Related ride ID
- `data`: 
  - `requiredAmount`: Fee amount needed
  - `currentBalance`: Current wallet balance
  - `shortfall`: Amount needed to top up

**When Sent:**
1. When transporter accepts ride but balance is insufficient
2. When sender accepts counter-offer but transporter's balance is insufficient

---

## 🔄 Updated Flow

### Flow 1: Direct Acceptance (No Negotiation)

```
1. Transporter clicks "Accept Offer"
   ↓
2. acceptRide() called
   ↓
3. Ride accepted (status → 'in_progress')
   ↓
4. Balance checked
   ↓
5a. If sufficient → No notification
5b. If insufficient → Notification sent
   ↓
6. Deduction happens when sender confirms
```

### Flow 2: With Negotiation

```
1. Transporter makes counter-offer
   ↓
2. Sender accepts counter-offer
   ↓
3. respondToCounterOffer() called
   ↓
4. Balance checked
   ↓
5a. If sufficient → Fee deducted, ride updated
5b. If insufficient → Error thrown, notification sent
```

---

## 📊 Balance Check Logic

### When Balance is Checked:

1. **After `acceptRide()`** (non-blocking)
   - Ride accepted regardless
   - Notification sent if insufficient
   - Deduction happens later

2. **During `respondToCounterOffer()`** (blocking)
   - Transaction fails if insufficient
   - Notification sent
   - Deduction prevented

### Calculation:
```dart
final fee = ridePrice * 0.02; // 2% of ride price
final currentBalance = transporter.driverWalletBalance;
final isSufficient = currentBalance >= fee;
```

---

## 🔔 Notification Details

### Notification Content:

**Title:** "Insufficient Balance"

**Message:** 
- "Your wallet balance ($X.XX) is insufficient. Please top up $Y.YY to complete this request."

**Data Included:**
- `requiredAmount`: Fee amount (2% of ride price)
- `currentBalance`: Transporter's current balance
- `shortfall`: Amount needed (requiredAmount - currentBalance)
- `rideId`: Related ride ID

---

## ✅ Benefits

1. **Better UX:**
   - Transporter can accept rides even with low balance
   - Gets notified to top up before negotiation completes
   - No sudden errors blocking acceptance

2. **Clear Timing:**
   - Deduction happens at the right time (after negotiation)
   - Transporter knows when they'll be charged

3. **Proactive Notifications:**
   - Transporter warned early about insufficient balance
   - Can top up before negotiation completes

---

## 🧪 Testing Scenarios

### Scenario 1: Sufficient Balance
1. Transporter accepts ride
2. Balance sufficient
3. Negotiation completes
4. Fee deducted successfully ✅

### Scenario 2: Insufficient Balance (Early Warning)
1. Transporter accepts ride
2. Balance insufficient
3. Notification sent
4. Transporter tops up
5. Negotiation completes
6. Fee deducted successfully ✅

### Scenario 3: Insufficient Balance (During Negotiation)
1. Transporter makes counter-offer
2. Sender accepts
3. Balance insufficient
4. Error thrown
5. Notification sent
6. Transaction fails
7. Transporter must top up and retry ✅

---

## 📝 Code Changes Summary

### Files Modified:
1. ✅ `lib/services/ride_service.dart`
   - Updated `acceptRide()` - removed immediate deduction
   - Updated `respondToCounterOffer()` - added deduction after negotiation
   - Added `checkBalanceAndNotify()` - helper method
   - Added `deductAcceptanceFee()` - helper method
   - Added notification imports

### New Imports:
- `package:flutter/foundation.dart` (for debugPrint)
- `notification_service.dart` (for sending notifications)

---

## ⚠️ Important Notes

1. **Non-Refundable:**
   - Once deducted, fee is NOT refunded (even if ride cancelled)
   - This is by design

2. **Transaction Safety:**
   - Deduction happens in Firestore transaction
   - Ensures atomicity (all or nothing)

3. **Notification Timing:**
   - Notifications sent after transaction completes
   - Prevents blocking the acceptance flow

---

**Status:** ✅ Complete
**Last Updated:** Deduction logic updated to occur after negotiation completion
