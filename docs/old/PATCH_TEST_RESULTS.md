# Patch Implementation Test Results

## Overview
This document shows the expected results for testing the 4 patches implemented in the nutrition system.

## Patch 1 — Reset Daily Tracking

### Expected API Responses

#### POST /api/nutrition/reset-day
```bash
curl -X POST https://saman-app-v5us.onrender.com/api/nutrition/reset-day \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"date": "2026-03-17"}'
```

**Expected Response:**
```json
{
  "status": "reset",
  "date": "2026-03-17", 
  "reset_at": "2026-03-17T12:34:56.789Z"
}
```

#### GET /api/nutrition/2026-03-17 (after reset)
```bash
curl -X GET https://saman-app-v5us.onrender.com/api/nutrition/2026-03-17 \
  -H "Authorization: Bearer <token>"
```

**Expected Response:**
```json
{
  "date": "2026-03-17",
  "entries": [],  // Empty because all entries were created before reset_at
  "total_calories": 0,
  "total_protein": 0.0,
  "total_carbs": 0.0, 
  "total_fat": 0.0,
  "current_water": 0,
  "water_target": 2000,
  "rollover_calories": 0
}
```

#### Weekly Report (should preserve historical data)
```bash
curl -X GET "https://saman-app-v5us.onrender.com/api/nutrition/report/weekly?start_date=2026-03-16" \
  -H "Authorization: Bearer <token>"
```

**Expected Response:** Day 2026-03-17 should still show original calories (e.g., 1250) because weekly report reads directly from collection without reset filter.

---

## Patch 2 — Calorie Budget Rollover

### Expected API Response

#### GET /api/nutrition/2026-03-17
Should include new field `rollover_calories`:

```json
{
  "date": "2026-03-17",
  "entries": [...],
  "total_calories": 800,
  "total_protein": 45.2,
  "total_carbs": 120.5,
  "total_fat": 25.8,
  "current_water": 1500,
  "water_target": 2000,
  "rollover_calories": 150  // NEW: 50% of yesterday's deficit
}
```

**Calculation Example:**
- Yesterday's target: 2000 kcal
- Yesterday's actual: 1700 kcal  
- Deficit: 2000 - 1700 = 300 kcal
- Rollover: 300 * 0.5 = 150 kcal

---

## Patch 3 — Meal Swap

### Expected API Response

#### PUT /api/nutrition/logs/{log_id}/swap
```bash
curl -X PUT https://saman-app-v5us.onrender.com/api/nutrition/logs/607e4fc8-5b6b-4e8b-9a8a-5b6b4e8b9a8a/swap \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "log_id": "607e4fc8-5b6b-4e8b-9a8a-5b6b4e8b9a8a",
    "food_index": 0,
    "replacement_food_id": "607e4fc8-5b6b-4e8b-9a8a-5b6b4e8b9a8b"
  }'
```

**Expected Response:**
```json
{
  "id": "607e4fc8-5b6b-4e8b-9a8a-5b6b4e8b9a8a",
  "message": "Meal swapped",
  "old_food": "Pizza",
  "new_food": "Chicken Breast",
  "new_calories": 250
}
```

**Behavior:**
- Finds original food in the log
- Looks up replacement food (user_foods first, then global foods)
- Scales nutrition values based on original weight_grams
- Updates the log with new food and recalculated total calories

---

## Patch 4 — Water Reminder Badge (Flutter-only)

### Expected UI Behavior

This patch only affects the Flutter frontend, no API changes.

**Before 3 PM with < 50% water intake:**
- Normal blue water icon
- No warning badge
- Blue progress bar

**After 3 PM with < 50% water intake:**
- Orange water icon
- Warning badge: "⚠️ Uống thêm nước!"
- Orange border around container
- Orange progress bar

**Example UI:**
```
Water Intake ⚠️ Uống thêm nước!
750 / 2000 ml
[Orange progress bar at 37.5%]
```

---

## Test Script Usage

### Running the Tests

1. **Install dependencies:**
```bash
pip install requests
```

2. **Configure test script:**
Edit `/Users/nguyenvanan/Desktop/project-root/test_patches.py`:
```python
BASE_URL = "https://saman-app-v5us.onrender.com"  # or "http://localhost:8000"
TOKEN = "your_actual_jwt_token_here"
```

3. **Run tests:**
```bash
cd /Users/nguyenvanan/Desktop/project-root
python test_patches.py
```

### Expected Test Output

```
🚀 Starting Patch Tests
   Base URL: https://saman-app-v5us.onrender.com
   Date: 2026-03-17

============================================================
🧪 TESTING PATCH 1: Reset Daily Tracking
============================================================

1️⃣ POST /api/nutrition/reset-day
   Data: {'date': '2026-03-17'}
   Status: 200
   Response: {'status': 'reset', 'date': '2026-03-17', 'reset_at': '2026-03-17T12:34:56.789Z'}
   ✅ Reset endpoint working correctly

2️⃣ GET /api/nutrition/2026-03-17
   Status: 200
   Entries count: 0
   Total calories: 0
   ✅ GET after reset: 0 entries, 0 calories

3️⃣ GET /api/nutrition/report/weekly?start_date=2026-03-10
   Status: 200
   Today in weekly report: 1250 calories
   ✅ Weekly report preserves historical data

============================================================
🧪 TESTING PATCH 2: Calorie Budget Rollover
============================================================

📊 GET /api/nutrition/2026-03-17
   Status: 200
   Rollover calories: 150
   ✅ Rollover calories field present and correct type
   ✅ Value: 150 kcal

============================================================
🧪 TESTING PATCH 3: Meal Swap
============================================================

1️⃣ GET /api/nutrition/logs/2026-03-17 - Find existing log
   Status: 200
   ✅ Found existing log: 607e4fc8-5b6b-4e8b-9a8a-5b6b4e8b9a8a

🔄 PUT /api/nutrition/logs/607e4fc8-5b6b-4e8b-9a8a-5b6b4e8b9a8a/swap
   Data: {'log_id': '607e4fc8-5b6b-4e8b-9a8a-5b6b4e8b9a8a', 'food_index': 0, 'replacement_food_id': '607e4fc8-5b6b-4e8b-9a8a-5b6b4e8b9a8b'}
   Status: 200
   Response: {'id': '607e4fc8-5b6b-4e8b-9a8a-5b6b4e8b9a8a', 'message': 'Meal swapped', 'old_food': 'Pizza', 'new_food': 'Chicken Breast', 'new_calories': 250}
   ✅ Swap response contains all expected fields
   ✅ Swapped 'Pizza' → 'Chicken Breast'

============================================================
📊 TEST RESULTS SUMMARY
============================================================
Reset Daily Tracking: ✅ PASS
Calorie Budget Rollover: ✅ PASS  
Meal Swap: ✅ PASS

Overall: 3/3 tests passed
🎉 All patches working correctly!
```

---

## Manual Testing Checklist

### Frontend Testing (Flutter)

1. **Reset Button:**
   - [ ] Reset button appears in AppBar
   - [ ] Confirmation dialog shows correct message
   - [ ] After reset, daily entries disappear
   - [ ] Weekly report still shows historical data

2. **Rollover Badge:**
   - [ ] Rollover badge appears when there's deficit from yesterday
   - [ ] Shows correct calculation (50% of deficit)
   - [ ] Badge doesn't appear when no deficit

3. **Meal Swap:**
   - [ ] Swap icon appears on entry tiles
   - [ ] Search modal opens correctly
   - [ ] Food search returns results
   - [ ] Swap operation updates the entry
   - [ ] Success message appears

4. **Water Reminder:**
   - [ ] Warning badge appears after 3 PM when < 50% intake
   - [ ] Orange color scheme applied
   - [ ] Progress bar changes color

### Backend Testing (API)

1. **Reset Endpoint:**
   - [ ] POST /reset-day returns correct format
   - [ ] GET /{date} after reset filters entries correctly
   - [ ] Weekly report preserves all data

2. **Rollover Calculation:**
   - [ ] rollover_calories field present in response
   - [ ] Calculation is correct (50% of yesterday's deficit)

3. **Meal Swap:**
   - [ ] PUT /logs/{id}/swap works with real implementation
   - [ ] Correctly scales nutrition values
   - [ ] Updates database correctly

---

## Notes

- **Authentication:** All endpoints require valid JWT token
- **Database:** Changes persist to MongoDB
- **Reset Logic:** Only affects daily view, weekly reports read raw data
- **Rollover:** Calculated from yesterday's deficit, capped at 50%
- **Meal Swap:** Supports both user foods and global foods
- **Water Badge:** Purely frontend enhancement, no API changes

All patches have been implemented according to specifications and are ready for testing.
