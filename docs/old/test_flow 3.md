# Flutter Story Food Flow - Test Checklist

## Checklist Ngày 3 ✅ COMPLETED

### ✅ Backend Fixes
- [x] Fix USDA/OpenFoodFacts User-Agent header trong nutrition_lookup.py
- [x] Backend endpoint `/api/nutrition/log-story` already exists and supports the required fields

### ✅ Frontend Models & Components  
- [x] Cập nhật AIAnalysisResult model - thêm withGrams(), withLabel() methods
- [x] Tạo meal_review_dialog.dart - complete dialog component with:
  - Gram slider with real-time macro recalculation
  - Meal type selector (breakfast, lunch, dinner, snack)
  - Top-3 predictions for relabeling
  - Mock mode and low confidence banners
  - Confidence badge
  - Macro chips (Protein, Carbs, Fat)
- [x] Tạo MealLogData class for data transfer

### ✅ Controller & Service Updates
- [x] Update DailyStoryController - split into analyzeImage() + confirmLog()
- [x] Update UI trigger (LogMealSheet) to use new controller methods (Cách 2)
- [x] Add NutritionService.confirmStoryLog() method

### ✅ Integration & Flow
- [x] Complete end-to-end flow: 
  ```
  LogMealSheet (camera/gallery)
          ↓
  DailyStoryController.analyzeImage(imageFile)
          ↓  
  POST /api/food/analyze  →  AIAnalysisResult
          ↓
  MealReviewDialog (user confirm/chỉnh)
          ↓
  POST /api/nutrition/log-story
          ↓
  StoryTimeline refresh
  ```

## Test Instructions

### Manual Testing Steps:
1. Mở NutritionScreen → tap FAB "Log Story"
2. Chọn ảnh bất kỳ (mock mode trả pizza)  
3. Dialog hiện: "Pizza", 85% confidence, macro đúng
4. Chỉnh gram → macro recalculate realtime
5. Chọn bữa → Lưu
6. StoryTimeline hiện item mới vừa log
7. Pull to refresh → item vẫn còn (đã lưu DB)
8. Swipe delete → item biến mất

### Expected Results:
- ✅ Dialog shows with correct food name and confidence
- ✅ Gram slider updates macros in real-time using per100g data
- ✅ Meal type selector works (auto-detects by time)
- ✅ Save button sends data to `/api/nutrition/log-story`
- ✅ Timeline refreshes to show new item
- ✅ Delete functionality works

### Backend API Response Format:
```json
{
  "food_name": "Pizza",
  "food_label": "pizza", 
  "confidence": 0.85,
  "low_confidence": false,
  "grams": 100.0,
  "nutrition": {
    "calories": 285,
    "protein": 12.5,
    "carbs": 36.2,
    "fat": 10.8
  },
  "per_100g": {
    "calories": 285,
    "protein": 12.5, 
    "carbs": 36.2,
    "fat": 10.8
  },
  "nutrition_source": "mock",
  "top3_predictions": [...],
  "mock": true
}
```

### Known Issues & Next Steps:
- ⚠️ Backend AI analysis still returns old format - conversion bridge in controller
- ⚠️ Nutrition lookup for new labels (Day 4 task)
- ⚠️ Image upload integration with storage
- ⚠️ Error handling improvements

## Status: ✅ READY FOR TESTING
