# 💰 Vehicle Classes and Pricing Model

## Overview
This document describes the pricing model implemented for different vehicle types based on distance and route type (local vs inter-city).

---

## 🏍️ Motorcycle (Bike Express) - Harare Pricing

**Distance-based tiered pricing:**

| Distance Range | Price (USD) |
|---------------|-------------|
| 0-3 km        | $2          |
| 3-5 km        | $3          |
| 5-7 km        | $4          |
| 7-9 km        | $5          |
| 9-14 km       | $6          |
| 14-17 km      | $7          |
| 17-19 km      | $8          |
| 19-22 km      | $9          |
| 22km+         | $9 + ($0.4 × additional km) |

**Example:**
- 25 km = $9 + (3 km × $0.4) = $10.20

---

## 🚐 Van (Runner)

**Pricing:**
- **Inter-city**: $5 per parcel (for routes ≥ 30km)
- **Intra-city**: Motorcycle pricing × 1.2 (for routes < 30km)

---

## 🚚 Pickup Truck (1.2t)

**Pricing:**
- **$2 per kilometer** (flat rate for all distances)

**Example:**
- 10 km = $20
- 25 km = $50

---

## 🚛 Truck 3-5tn - Gweru Pricing

**Pricing:**
- **Local (≤10km)**: $40 - $50 (average: $45)
- **Longer distances**: $45 + ($3 × additional km beyond 10km)

**Example:**
- 10 km = $45
- 15 km = $45 + (5 km × $3) = $60

---

## 🚛 Truck 7.5tn - Gweru Pricing

**Pricing:**
- **Local (≤10km)**: Starting price $80
- **Inter-city (≥30km)**: Distance × $2.5

**Example:**
- 10 km (local) = $80
- 50 km (inter-city) = 50 × $2.5 = $125

---

## 🚛 Truck 10-15tn - Gweru Pricing

**Pricing:**
- **Local (≤10km)**: $120 - $140 (average: $130)
- **Longer distances**: $130 + ($2.5 × additional km beyond 10km)

**Example:**
- 10 km (local) = $130
- 30 km (inter-city) = $130 + (20 km × $2.5) = $180

---

## 🚛 Truck 20tn

**Pricing:**
- **Local (≤10km)**: Starting price $130 (based on 10-15tn pricing)
- **Longer distances**: $130 + ($2.5 × additional km beyond 10km)

---

## 📍 Route Classification

**Local (Intra-city):**
- Distance < 30 km
- Within the same city

**Inter-city:**
- Distance ≥ 30 km
- Between different cities

---

## 💡 Pricing Notes

**Important:** Pricing is based **solely on distance** and vehicle type. Package size, weight, or type (fragile, large, etc.) does not affect the price. All pricing is calculated based on the distance between pickup and dropoff locations.

---

## 🔧 Implementation Details

### PricingService Class
Located in: `lib/services/pricing_service.dart`

**Key Methods:**
- `calculateDistance()` - Calculates distance between coordinates
- `isLocalRoute()` - Determines if route is local or inter-city
- `calculatePrice()` - Main method that calculates price based on vehicle type
- `getPriceRange()` - Returns price range string for trucks with ranges

### Integration
- **Ride Booking Screen**: Automatically calculates suggested price when:
  - Transport type is selected
  - Pickup and dropoff locations are set
  - Coordinates are available

### Price Display
- Shows suggested price with route type (Local/Inter-city)
- Shows distance for reference
- Shows price range for trucks (e.g., "$40 - $50")
- Auto-fills price field if empty

---

## 📊 Pricing Examples

### Example 1: Motorcycle, 15km
- Distance: 15 km (within 14-17 km range)
- Price: **$7**

### Example 2: Pickup Truck, 25km
- Distance: 25 km
- Price: 25 × $2 = **$50**

### Example 3: Truck 5tn, 8km (Local)
- Distance: 8 km (local, ≤10km)
- Price: **$45** (within $40-$50 range)

### Example 4: Truck 7.5tn, 50km (Inter-city)
- Distance: 50 km (inter-city)
- Price: 50 × $2.5 = **$125**

### Example 5: Truck 20tn, 5km (Local)
- Distance: 5 km (local, ≤10km)
- Price: **$130**

---

## 🎯 Notes

1. **Distance Calculation**: Uses Haversine formula via Geolocator for accurate distance
2. **Geocoding Fallback**: If coordinates aren't available, addresses are geocoded automatically
3. **Real-time Updates**: Price recalculates automatically when:
   - Transport type changes
   - Pickup/dropoff locations change
   - Package type changes
4. **Price Ranges**: For trucks with price ranges, the average is used for calculation, but the range is displayed to users
