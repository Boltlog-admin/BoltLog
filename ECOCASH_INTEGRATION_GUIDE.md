# EcoCash Integration Guide

## Overview
This guide explains how to best integrate EcoCash mobile money payments into the Boltlog application. EcoCash is Zimbabwe's largest mobile money platform, making it essential for local payments.

## Integration Methods

### Method 1: Paynow (Recommended for Quick Setup) ⭐
**Best for:** Quick implementation, supports multiple payment methods

**Advantages:**
- ✅ Easy to set up
- ✅ Supports EcoCash, OneMoney, Telecash
- ✅ Handles USSD prompts automatically
- ✅ Provides payment status polling
- ✅ Lower technical complexity

**Setup Steps:**
1. Register at [Paynow.co.zw](https://www.paynow.co.zw)
2. Get Integration ID and Key
3. Configure callback URLs
4. Update `EcoCashService` with credentials

**Cost:** Transaction fees apply (typically 2-3%)

---

### Method 2: Direct EcoCash Merchant API
**Best for:** Direct control, lower fees, high volume

**Advantages:**
- ✅ Direct integration with EcoCash
- ✅ Potentially lower fees
- ✅ More control over payment flow
- ✅ Better for high-volume merchants

**Requirements:**
- EcoCash merchant account
- Business registration documents
- API credentials from EcoCash
- Technical integration support

**Setup Steps:**
1. Contact EcoCash Business Services
2. Complete merchant registration
3. Get API credentials
4. Implement API integration

**Cost:** Negotiable based on volume

---

### Method 3: USSD Push (User-Initiated)
**Best for:** Simple implementation, no merchant account needed

**How it works:**
- User initiates payment from their phone
- App provides payment instructions
- User completes payment via USSD
- App verifies payment

**Limitations:**
- Requires manual verification
- No automatic confirmation
- User must remember to pay

---

## Recommended Implementation: Paynow

### Why Paynow?
1. **Fastest Setup** - Can be live in days
2. **Multiple Providers** - EcoCash, OneMoney, Telecash
3. **Reliable** - Established payment aggregator
4. **Good Documentation** - Clear API docs
5. **Support** - Technical support available

### Implementation Steps

#### 1. Register with Paynow
- Visit [paynow.co.zw](https://www.paynow.co.zw)
- Create merchant account
- Complete verification
- Get Integration ID and Key

#### 2. Configure Backend
Update `lib/services/ecocash_service.dart`:
```dart
static const String _paynowIntegrationId = 'YOUR_INTEGRATION_ID';
static const String _paynowIntegrationKey = 'YOUR_INTEGRATION_KEY';
```

#### 3. Set Up Callback URLs
- **Result URL:** `https://your-backend.com/paynow/result`
  - Receives payment status updates
  - Must be publicly accessible
  - Use Firebase Cloud Functions or your backend

- **Return URL:** `boltlog://payment/return`
  - Deep link back to app after payment
  - Configure in `android/app/src/main/AndroidManifest.xml`

#### 4. Add Crypto Dependency
Update `pubspec.yaml`:
```yaml
dependencies:
  crypto: ^3.0.3  # For MD5 hashing
```

#### 5. Update Payment Service
The `EcoCashService` is already created. Just:
- Add your Paynow credentials
- Configure callback URLs
- Test with small amounts

---

## Payment Flow

### User Experience:
1. **User books ride** → Selects EcoCash payment
2. **App initiates payment** → Sends request to Paynow
3. **User receives USSD prompt** → On their phone
4. **User enters PIN** → Confirms payment
5. **Payment processed** → App polls for status
6. **Payment confirmed** → Ride booking completed

### Technical Flow:
```
1. User selects EcoCash → RideBookingScreen
2. processEcoCashPayment() → EcoCashService
3. initiatePayment() → Paynow API
4. Payment request sent → User's phone
5. User confirms → Paynow processes
6. Poll payment status → Every 5 seconds
7. Payment confirmed → Update Firestore
8. Ride booking completed → User notified
```

---

## Code Integration

### 1. Update Payment Service
In `lib/services/payment_service.dart`, replace the mobile money section:

```dart
case PaymentMethodType.mobileMoney:
  // Check if it's EcoCash
  final paymentMethod = await _paymentMethodsCollection
      .doc(paymentMethodId)
      .get();
  
  final provider = paymentMethod.data()?['mobileMoneyProvider'] as String?;
  
  if (provider == 'EcoCash') {
    final ecocashService = EcoCashService();
    return await ecocashService.processEcoCashPayment(
      rideId: rideId,
      amount: amount,
      phoneNumber: paymentMethod.data()?['mobileMoneyNumber'] as String,
      paymentMethodId: paymentMethodId,
    );
  }
  // Handle other providers...
  break;
```

### 2. Add Deep Link Configuration

**Android** (`android/app/src/main/AndroidManifest.xml`):
```xml
<activity>
  <intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="boltlog" android:host="payment" />
  </intent-filter>
</activity>
```

**iOS** (`ios/Runner/Info.plist`):
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>boltlog</string>
    </array>
  </dict>
</array>
```

### 3. Handle Payment Return
Create `lib/screens/payment_return_screen.dart`:
```dart
class PaymentReturnScreen extends StatelessWidget {
  final String? status;
  final String? reference;
  
  // Handle payment return from Paynow
  // Check payment status and navigate accordingly
}
```

---

## Security Best Practices

### 1. Never Store Sensitive Data
- ✅ Store only phone numbers (masked)
- ✅ Never store PINs or passwords
- ✅ Use secure backend for API keys

### 2. Validate Payments
- ✅ Always verify payment status server-side
- ✅ Use payment references to prevent duplicates
- ✅ Implement idempotency checks

### 3. Handle Errors Gracefully
- ✅ Network timeouts
- ✅ Payment cancellations
- ✅ Insufficient funds
- ✅ Invalid phone numbers

### 4. User Experience
- ✅ Clear payment instructions
- ✅ Progress indicators
- ✅ Payment status updates
- ✅ Retry mechanisms

---

## Testing

### Test Payment Flow:
1. Use Paynow test credentials
2. Test with small amounts (ZWL 1-10)
3. Verify payment status updates
4. Test cancellation flow
5. Test timeout scenarios

### Test Scenarios:
- ✅ Successful payment
- ✅ Payment cancellation
- ✅ Network timeout
- ✅ Invalid phone number
- ✅ Insufficient funds
- ✅ Payment retry

---

## Production Checklist

### Before Going Live:
- [ ] Register with Paynow (or EcoCash directly)
- [ ] Get production credentials
- [ ] Configure callback URLs
- [ ] Set up Firebase Cloud Functions for callbacks
- [ ] Test with real payments (small amounts)
- [ ] Implement payment retry logic
- [ ] Add payment status notifications
- [ ] Set up monitoring and alerts
- [ ] Document error handling
- [ ] Train support team

---

## Cost Considerations

### Paynow Fees:
- **Transaction Fee:** ~2-3% per transaction
- **Setup Fee:** Usually free
- **Monthly Fee:** May apply for high volume

### Direct EcoCash:
- **Negotiable** based on volume
- **Potentially lower** for high-volume merchants
- **Requires** merchant account setup

---

## Support & Resources

### Paynow:
- Website: [paynow.co.zw](https://www.paynow.co.zw)
- Documentation: Available in merchant portal
- Support: support@paynow.co.zw

### EcoCash Business:
- Contact: Business Services Department
- Email: business@ecocash.co.zw
- Phone: +263 4 700 000

---

## Alternative: Manual Verification

If API integration is not immediately possible, you can implement a manual verification flow:

1. **User selects EcoCash** → App generates payment reference
2. **User receives instructions** → "Send ZWL X to merchant number Y, use reference Z"
3. **User completes payment** → Via USSD on their phone
4. **User confirms in app** → "I have paid"
5. **Admin verifies** → Check merchant account
6. **Payment confirmed** → Ride booking activated

**Pros:** No API needed, works immediately
**Cons:** Manual verification, slower, not scalable

---

## Next Steps

1. **Choose Integration Method:**
   - Paynow (recommended for quick start)
   - Direct EcoCash API (for long-term)

2. **Set Up Credentials:**
   - Register with chosen provider
   - Get API credentials
   - Configure in `EcoCashService`

3. **Implement Callbacks:**
   - Set up backend endpoint
   - Handle payment status updates
   - Update Firestore accordingly

4. **Test Thoroughly:**
   - Test payment flow
   - Test error scenarios
   - Test with real users (small amounts)

5. **Go Live:**
   - Switch to production credentials
   - Monitor transactions
   - Provide user support

---

## Code Files Created

- ✅ `lib/services/ecocash_service.dart` - EcoCash payment service
- ✅ `ECOCASH_INTEGRATION_GUIDE.md` - This guide

## Integration Status

**Current:** Service structure created, ready for credentials
**Next:** Add Paynow/EcoCash credentials and test
**ETA:** 1-2 weeks for full integration (depending on provider approval)

---

**Recommendation:** Start with Paynow for fastest implementation, then consider direct EcoCash API for long-term cost optimization.
