# Kiểm tra feature Nutrition – Báo cáo toàn diện (chỉ đọc, không sửa code)

## 1. Danh sách màn hình UI liên quan nutrition

| Màn hình / Widget | Đường dẫn | Button/Field chính | Hành vi khi nhấn |
|-------------------|-----------|--------------------|-------------------|
| **NutritionScreen** (màn chính) | `frontend/lib/screens/nutrition/nutrition_screen.dart` | Search (AppBar), Refresh, Log Story (FAB), DateSelector, Water +/- | Search → mở FoodLogScreen bottom sheet; Refresh → `_loadData()`; Log Story → mở LogMealSheet; chọn ngày → `_loadData()` |
| **FoodLogScreen** | `frontend/lib/screens/food_log_screen.dart` | Ô tìm kiếm, Tạo món mới, Thêm vào plan (theo meal type) | Search → `NutritionService.searchFoods`; Thêm món → `nutritionProvider.addMeal` + đóng sheet trả `true` |
| **NutritionDashboardScreen** | `frontend/lib/features/nutrition/presentation/screens/nutrition_dashboard_screen.dart` | Thêm món (FAB), RefreshIndicator, Calendar | FAB → Navigator sang AddMealScreen; Pull-to-refresh → refresh `dailyNutritionControllerProvider` |
| **AddMealScreen** | `frontend/lib/features/nutrition/presentation/screens/add_meal_screen.dart` | Tên món, Calories, Submit | Submit → `dailyNutritionControllerProvider.addMeal(calories, name)` (không gọi API nutrition trực tiếp) |
| **LogMealSheet** | `frontend/lib/features/nutrition/presentation/widgets/log_meal_sheet.dart` | Chụp ảnh / ghi chú, gửi story | Gọi repository/service upload log story |
| **StoryTimeline** | `frontend/lib/features/nutrition/presentation/widgets/story_timeline.dart` | Hiển thị danh sách meal log theo ngày | Load từ `getLogStories(date)` |
| **MealCard** | `frontend/lib/screens/nutrition/widgets/meal_card.dart` | Swipe (Dismissible) → Swap | Gọi `nutritionProvider.swapMeal(meal, goal)` → POST swap_meal |
| **NutritionSummary** | `frontend/lib/screens/nutrition/widgets/nutrition_summary.dart` | Chỉ hiển thị | — |
| **DateSelector** | `frontend/lib/screens/nutrition/widgets/date_selector.dart` | 7 ngày tuần | onDateSelected → parent `_loadData()` |

---

## 2. API endpoints liên quan nutrition

### Backend (FastAPI) – `backend/routers/nutrition.py`  
Prefix: `/api/nutrition`, **toàn bộ route** đều có `dependencies=[Depends(get_current_user)]`.

| Method | Đường dẫn | File client gọi | Tham số | Ví dụ request / response |
|--------|-----------|------------------|---------|---------------------------|
| GET | `/api/nutrition/foods/search?q=...&limit=10` | `frontend/lib/services/nutrition_service.dart` → `searchFoods(query)` | Headers: `Authorization: Bearer <token>`. Query: `q`, `limit` | **Request:** `GET /api/nutrition/foods/search?q=pho` **Response:** `{"foods":[...],"total":n,"query":"pho"}` |
| POST | `/api/nutrition/foods` | NutritionService (create custom food – config gọi `foods/create` chưa khớp) | Body: `FoodCreate` (name, calories, protein, carbs, fat, tags) | **Response:** `{"id":"...","message":"...","food":{...},"status":"mock_implementation"}` |
| POST | `/api/nutrition/logs` | Có thể từ repo/impl (log story flow khác) | Body: `NutritionLog` (date, meal_type, foods, total_calories, notes) | **Response:** `{"id":"...","message":"Nutrition log created successfully",...}` |
| GET | `/api/nutrition/logs/{date}` | Có thể từ get daily logs | Path: date. Headers: Bearer | **Response:** `{"date":"...","logs":[...],"total":n}` |
| PUT | `/api/nutrition/logs/{log_id}/confirm` | — | Path: log_id | **Response:** `{"id":"...","status":"confirmed",...}` |
| PUT | `/api/nutrition/logs/{log_id}/swap` | — | Body: `MealSwapRequest` | **Response:** `{"id":"...","message":"Meal swapped successfully",...}` |
| DELETE | `/api/nutrition/logs/{log_id}` | — | Path: log_id | **Response:** `{"id":"...","message":"... deleted"}` |
| POST | `/api/nutrition/water` | `nutrition_provider.dart` + `nutrition_service.dart` | Body: `{"date":"...","amount_ml":n}` | **Response:** `{"id":"...","message":"Water intake logged successfully",...}` |
| GET | `/api/nutrition/{date}` | `frontend/lib/providers/nutrition_provider.dart` → `loadDailyPlan` qua `ApiClient.dio.get(ApiConfig.nutritionGetEndpoint + "/" + dateStr)` | Path: date (yyyy-MM-dd). Headers: Bearer | **Request:** `GET /api/nutrition/2026-03-15` **Response (hiện tại – mock):** `{"date":"2026-03-15","entries":[],"total_calories":0,"total_protein":0,"total_carbs":0,"total_fat":0,"message":"Mock data - implement database integration"}` — **không có trường `plan` hay `meals`** |
| POST | `/api/nutrition/generate-plan` | `frontend/lib/providers/nutrition_provider.dart` → `generateAutoPlan` | Body: `NutritionPlanRequest`: target_calories, dietary_preferences, allergies, goal. Headers: Bearer | **Request:** `POST /api/nutrition/generate-plan` body `{"target_calories":2000,"dietary_preferences":[],"allergies":[],"goal":"maintain"}` **Response:** `{"plan":{"date":"...","target_calories":...,"meals":[{"meal_type":"Breakfast","time":"07:00","foods":[{"name":"Oatmeal","calories":...,"protein":10,"carbs":30,"fat":5}]},...],"total_calories":...,"nutrition_summary":{...}},"generated_at":"...","user_preferences":{...}}` |
| GET | `/api/nutrition/report/weekly?start_date=...` | — | Query: start_date (optional) | **Response:** mock weekly summary |
| POST | `/api/nutrition/log` | Legacy | Body: `NutritionEntry` | **Response:** mock |

**Endpoints frontend gọi nhưng backend chưa có (404 nếu gọi):**

- `POST /api/nutrition/add-meal` — `api_config.dart` `addMealEndpoint`, `nutrition_provider.addMeal`, `nutrition_service.addMealToPlan`
- `POST /api/nutrition/update` — `nutrition_provider._syncPlan`, `ApiConfig.nutritionUpdateEndpoint`
- `POST /api/nutrition/log-story` — `nutrition_service.uploadLogStory`, repository createMealLog
- `GET /api/nutrition/log-story/{date}` — `nutrition_service.getLogStories`
- `DELETE /api/nutrition/log-story/{logId}` — `nutrition_service.deleteLogStory`
- `POST /api/nutrition/confirm-log` — `nutrition_service.confirmMealLog`
- `POST /api/nutrition/swap_meal` — `nutrition_provider.swapMeal` (backend có PUT `/logs/{id}/swap`, không có POST `swap_meal`)

**Food analysis (ML):**  
- `POST /api/food/analyze` — `frontend/lib/services/nutrition_service.dart` (analyzeFoodImage), `remote_inference_service.dart`. Headers: Bearer. Body: multipart/form-data (image). **Response:** JSON kết quả phân tích ảnh món ăn.

---

## 3. Luồng dữ liệu / sequence (tóm tắt)

1. User mở tab Nutrition (MainScreen → NutritionScreen).
2. `initState` → `_loadData()` → đọc `profileProvider`, gọi `nutritionProvider.loadDailyPlan(date, fallbackCalories, fallbackGoal)`.
3. **loadDailyPlan:**  
   - Nếu cache có cho `date` và không forceRefresh → trả plan từ cache.  
   - GET `ApiConfig.nutritionGetEndpoint + "/" + dateStr` (= `GET /api/nutrition/{date}`).
4. **Nếu GET 200 và data không null:**  
   - Parse `NutritionPlan.fromJson(data['plan'] ?? data)`.  
   - Backend hiện trả mock: không có `plan`, không có `meals` → `meals = []` → UI hiển thị “Chưa có kế hoạch nào” và **không** gọi generate.
5. **Nếu GET không 200 hoặc data null:**  
   - Gọi `generateAutoPlan(date, targetCalories: fallbackCalories, goal: fallbackGoal)` → POST `/api/nutrition/generate-plan` với body `date, target_calories, goal`.
6. **Backend generate-plan:**  
   - `MealGenerator.generate_daily_plan(...)` (mock/rule-based) → trả plan có `meals` dạng `[{ meal_type, time, foods: [{ name, calories, protein, carbs, fat }] }]`.
7. Frontend nhận 200 → `NutritionPlan.fromJson(data['plan'] ?? data)`. Cấu trúc `meals` của backend (foods array trong từng meal) **không khớp** với `Meal.fromJson` (mong đợi từng phần tử meal có sẵn name, calories, meal_type, time...) → có thể parse lỗi hoặc hiển thị sai (ví dụ name "Unknown Food", calories 0).
8. Kết quả: **render plan** (hoặc lỗi/trống) từ `nutritionProvider` state → NutritionSummary, MealCard list, Water tracker.

---

## 4. Logic tạo/gợi ý plan

- **Loại:** Rule-based / mock (không ML). File: `backend/services/meal_generator.py`.
- **Điểm gọi:** `backend/routers/nutrition.py` → `POST /api/nutrition/generate-plan` → `meal_generator.generate_daily_plan(target_calories, dietary_preferences, allergies, goal)`.
- **Trigger:** Chỉ khi frontend gọi POST generate-plan (hiện tại chỉ khi GET `/api/nutrition/{date}` **không** 200 hoặc data null; **không** trigger khi GET 200 nhưng `meals` rỗng).
- **Tham số:**  
  - `target_calories` (int),  
  - `dietary_preferences` (list),  
  - `allergies` (list),  
  - `goal`: "maintain" | "lose" | "gain".
- **Logic mock (MealGenerator):** Trả plan cố định: 3 bữa (Breakfast 15% cal, Lunch 35%, Dinner 35%) với Oatmeal, Grilled Chicken, Salmon; không dùng độ tuổi, weight, DB.  
- **Logic đầy đủ (class MealGeneratorService phía dưới trong file):** Dùng DB `foods`, nhóm Dish/Carb/Vitamin, điểm theo goal (WEIGHT_LOSS / MUSCLE_GAIN / MAINTAIN), tránh allergies; phân bổ cal_breakfast 30%, lunch 35%, dinner 35%, snack nếu thiếu. Router **đang dùng** `MealGenerator` (mock), **không** dùng `MealGeneratorService` (cần DB).

---

## 5. Bảng/collection cơ sở dữ liệu

- **nutrition_plans** (MongoDB, `backend/app/database.py` → `nutrition_collection = db["nutrition_plans"]`):  
  - Dùng trong POST `/api/nutrition/logs` (insert log), GET `/api/nutrition/logs/{date}` (find theo user_email + date).  
  - Field quan trọng: `user_email`, `date`, `meal_type`, `foods`, `total_calories`, `notes`, `created_at`, `updated_at`.
- **foods** (MongoDB, `foods_collection`):  
  - GET `/api/nutrition/foods/search` ($text search); seed từ `backend/seed_nutrition_data.py`.  
  - Field: `name`, `calories`, `protein`, `carbs`, `fat`, `tags`, `_id` (và có thể category, serving_size, ...).
- **users**: Auth và get_current_user; không lưu plan trực tiếp trong user.

**Lưu ý:** GET `/api/nutrition/{date}` **không** đọc từ `nutrition_plans` hay bất kỳ collection nào; luôn trả mock (entries rỗng, không có plan/meals). Plan được tạo từ POST generate-plan nhưng **không** được lưu vào DB trong luồng hiện tại.

---

## 6. Tác vụ nền / cron / scheduled jobs

**Không tìm thấy.** Không có cron, celery, hay scheduled job nào liên quan nutrition trong repo.

---

## 7. Caching / queue / Redis

**Không tìm thấy** Redis hay queue cho nutrition.  
- Frontend: cache trong memory tại `frontend/lib/providers/nutrition_provider.dart` (`_localCache` map theo date).  
- Feature nutrition (story/inference): `frontend/lib/features/nutrition/data/services/in_memory_cache_service.dart` (cache kết quả phân tích ảnh theo hash).

---

## 8. Authentication / Authorization

- **Header:** `Authorization: Bearer <token>`.
- **Nơi kiểm tra:**  
  - Backend: `backend/auth_utils.py` → `verify_token(credentials = Depends(security))` → decode JWT lấy email → `get_current_user(email)` → tìm user trong `users_collection`; nếu không có user → 401.  
  - Router: `backend/routers/nutrition.py` khai báo `dependencies=[Depends(get_current_user)]` cho toàn bộ router → mọi route nutrition đều cần token hợp lệ.
- **Client:** `frontend/lib/services/api_client.dart` — InterceptorsWrapper đọc token từ FlutterSecureStorage (`auth_token` hoặc `jwt_token`) và gán `Authorization: Bearer $token`.

---

## 9. Xử lý lỗi / exception

- **OPTIONS (CORS preflight):** `backend/main.py` middleware: nếu method OPTIONS, trả **204** với headers CORS (Allow-Origin, Allow-Methods, Allow-Headers, Allow-Credentials); không trả 400.
- **401:** `auth_utils.verify_token` hoặc `get_current_user` → `HTTPException(status_code=401, detail="Token invalid")` hoặc "User not found".  
  - `backend/auth/dependencies.py`: thiếu header → 401 "Token missing or invalid format".  
  - Frontend: `api_client.dart` onError 401 in log "Token hết hạn hoặc không hợp lệ".
- **404:** Trong nutrition: `user_repo.get_by_email(...)` không tìm thấy user → 404 "User not found" (GET `/{date}`, generate-plan, report/weekly, log).
- **500:** Try/except trong nutrition router → `HTTPException(status_code=500, detail=str(e))` (search_foods, create_food, create_nutrition_log, get_nutrition_logs, generate_plan, ...).
- **503:** Khi `nutrition_collection` hoặc `foods_collection` là None → "Database not available".
- **Log:** `backend/routers/nutrition.py` — `logger.info` / `logger.error` (tạo food); Python logging mặc định in ra stdout/stderr (format trong `main.py`: `%(asctime)s - %(levelname)s - %(message)s`).

---

## 10. File / dòng log khi “không thấy plan”

- **Frontend (debug):**  
  - `lib/providers/nutrition_provider.dart`: `debugPrint("🤖 Auto-pilot: Creating new plan for $dateStr...")` khi vào nhánh gọi generateAutoPlan.  
  - `lib/config/api_config.dart`: `print('[API] GET ... (done) status=...')`, `print('[API] POST ... error body: ...')` khi có lỗi.  
  - `lib/services/api_client.dart`: `print('[DIO] Request: ...')`, `print('[DIO] Error: ...')`, `print('Token hết hạn hoặc không hợp lệ ...')` khi 401.
- **Backend:**  
  - `backend/main.py`: OPTIONS log `logger.info("CORS preflight request path=... origin=... acrm=... acrh=...")`.  
  - `backend/routers/nutrition.py`: logger.info/error khi create food (user, payload, food_id, error).  
  - Khi 401/404/500: FastAPI trả response; có thể xem body và status trong console backend (uvicorn) hoặc log middleware nếu bật.

**Ví dụ log cần xem khi không thấy plan:**  
- Console Flutter: `[DIO] Request: GET https://.../api/nutrition/2026-03-15` → status 200 hay 401/500.  
- Flutter: có thấy `🤖 Auto-pilot: Creating new plan for 2026-03-15` không (nếu có → GET đã fail hoặc data null).  
- Backend console: có log 401/404/500 sau request GET nutrition hoặc POST generate-plan không.

---

## 11. Các bước tái tạo “không có gợi ý plan” (local/dev)

1. Backend chạy local: `cd backend && uvicorn main:app --reload --host 0.0.0.0 --port 8000` (hoặc dùng biến PORT).
2. Frontend: `api_config.dart` trỏ `baseUrl` tới backend (ví dụ `http://127.0.0.1:8000` cho local).
3. Đăng ký/đăng nhập → lấy token (qua app hoặc POST `/api/auth/login`).
4. Cập nhật profile (có goal, targetCalories) nếu app bắt profile hợp lệ khi vào Nutrition.
5. Vào tab Nutrition (ngày hôm nay hoặc bất kỳ).
6. Quan sát:  
   - Nếu GET `/api/nutrition/{date}` trả 200 với body mock (không có `meals`) → frontend parse plan với `meals = []` → hiển thị “Chưa có kế hoạch nào” và **không** gọi generate.  
   - Nếu GET trả 401 (thiếu/sai token) → catch → có thể gọi generateAutoPlan; nếu generate cũng 401 thì vẫn không có plan.
7. Thử đổi ngày (DateSelector) và refresh để lặp lại GET.
8. (Tùy chọn) Gọi trực tiếp POST `/api/nutrition/generate-plan` với token để xem response và so cấu trúc với `NutritionPlan.fromJson`.
9. Kiểm tra console Flutter (DIO, API, Auto-pilot) và console backend (status, exception).

---

## 12. Test cases / curl (copy-paste, expected ngắn)

**Biến test (thay bằng giá trị thực):**  
- `BASE=https://saman-app-v5us.onrender.com` hoặc `BASE=http://127.0.0.1:8000`  
- `TOKEN=<jwt_sau_khi_login>`

```bash
# OPTIONS preflight
curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "$BASE/api/nutrition/2026-03-15" \
  -H "Origin: http://localhost:5173" -H "Access-Control-Request-Method: GET" -H "Access-Control-Request-Headers: Authorization"
# Expected: 204

# GET user profile (cần cho nutrition flow)
curl -s -w "\n%{http_code}" -X GET "$BASE/api/user/profile" -H "Authorization: Bearer $TOKEN"
# Expected: 200, body JSON có email / profile

# GET nutrition by date (auth)
curl -s -w "\n%{http_code}" -X GET "$BASE/api/nutrition/2026-03-15" -H "Authorization: Bearer $TOKEN"
# Expected: 200, body có "date","entries", "total_calories"; hiện không có "plan"/"meals"

# POST generate-plan
curl -s -w "\n%{http_code}" -X POST "$BASE/api/nutrition/generate-plan" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"target_calories":2000,"dietary_preferences":[],"allergies":[],"goal":"maintain"}'
# Expected: 200, body có "plan", "plan"."meals" (array)
```

**Không token (expect 401):**
```bash
curl -s -w "\n%{http_code}" -X GET "$BASE/api/nutrition/2026-03-15"
# Expected: 401, body {"detail":"Token invalid"} hoặc tương đương
```

---

## 13. Giả thuyết “không thấy plan” và cách xác minh

| # | Giả thuyết | Giá trị/log cần capture |
|---|------------|---------------------------|
| 1 | GET `/api/nutrition/{date}` trả 200 nhưng không có `plan`/`meals` → frontend không gọi generate, hiển thị plan rỗng | Response body GET: có "entries":[] và không có "meals"? Log Flutter: không thấy "Auto-pilot: Creating new plan". |
| 2 | CORS preflight chặn hoặc sai → request thực không gửi được / không gửi kèm credentials | Network tab: OPTIONS 204 có Access-Control-Allow-Origin + Credentials; GET có gửi Authorization. |
| 3 | Token thiếu/sai/hết hạn → 401 → loadDailyPlan vào catch; generateAutoPlan cũng 401 → vẫn không có plan | Response GET và POST generate-plan: status 401. Log Flutter: "Token hết hạn hoặc không hợp lệ" hoặc [DIO] Error. |
| 4 | Cấu trúc response generate-plan (meals[].foods[]) không khớp NutritionPlan/Meal.fromJson → parse lỗi hoặc meals rỗng/sai | So sánh JSON trả về từ POST generate-plan với `Meal.fromJson` (cần name, calories, meal_type, time ở từng meal item). |
| 5 | DB/users không có user (get_current_user trả 404) hoặc nutrition_collection None (503) khi gọi route dùng DB | Backend log/response: 404 "User not found" hoặc 503 "Database not available". |

---

## 14. ML / service ngoài

- **Phân tích ảnh món ăn:** `POST /api/food/analyze` — `backend/routers/food_analysis.py`, service `FoodAnalysisEnsemble` (classification + portion estimation), config từ `food_analysis_config.json` / `model_config.py`.  
- **Health check ML:** `backend/routers/health.py` có endpoint kiểm tra model (ví dụ model path tồn tại). Có thể có route dạng `/api/health/ml` hoặc tương tự — cần xem file health.py đầy đủ để nêu đúng URL.  
- **Nutrition plan:** Không dùng ML; MealGenerator là rule-based/mock.

---

## 15. File/đường dẫn quan trọng (≤20)

| Đường dẫn | Mục đích |
|-----------|----------|
| `frontend/lib/screens/nutrition/nutrition_screen.dart` | Màn nutrition chính, load plan, search, log story |
| `frontend/lib/providers/nutrition_provider.dart` | State plan, loadDailyPlan, generateAutoPlan, addMeal, swapMeal, water |
| `frontend/lib/config/api_config.dart` | baseUrl, nutritionGetEndpoint, generatePlanEndpoint, addMealEndpoint |
| `frontend/lib/services/api_client.dart` | Dio singleton, interceptors gắn Bearer token |
| `frontend/lib/services/nutrition_service.dart` | Gọi API: searchFoods, addMealToPlan, water, log-story, analyze, confirm |
| `frontend/lib/models/nutrition_model.dart` | NutritionPlan, Meal, Supplement, fromJson/toJson |
| `frontend/lib/screens/food_log_screen.dart` | Bottom sheet tìm món, thêm vào plan |
| `frontend/lib/features/nutrition/data/repositories/nutrition_repository_impl.dart` | Analyze image, createMealLog, getDailyMealLogs (gọi NutritionService) |
| `frontend/lib/features/nutrition/data/services/remote_inference_service.dart` | Gọi POST /api/food/analyze |
| `backend/routers/nutrition.py` | Tất cả route /api/nutrition/*, auth, GET date, POST generate-plan, logs, water |
| `backend/services/meal_generator.py` | MealGenerator.generate_daily_plan (mock), MealGeneratorService (DB-based, chưa dùng ở router) |
| `backend/app/database.py` | nutrition_collection (nutrition_plans), foods_collection |
| `backend/auth_utils.py` | verify_token, get_current_user (JWT + users_collection) |
| `backend/main.py` | CORS, OPTIONS 204, include_router(nutrition_router) |
| `backend/seed_nutrition_data.py` | Seed foods collection |
| `backend/routers/food_analysis.py` | POST /api/food/analyze (ML) |

---

## Tổng kết – Nơi cần kiểm tra ngay khi “không có plan”

1. **GET `/api/nutrition/{date}`** — Nếu trả 200 với body mock (chỉ `entries: []`, không có `plan`/`meals`) thì frontend sẽ **không** gọi generate-plan và luôn hiển thị “Chưa có kế hoạch nào”. Cần sửa backend trả plan theo ngày (hoặc lưu plan sau generate) **hoặc** sửa frontend: khi `plan.meals.isEmpty` sau GET 200 thì gọi `generateAutoPlan`.
2. **Token và CORS** — Kiểm tra request từ app có gửi `Authorization: Bearer <token>` và OPTIONS trả 204 với Allow-Credentials; nếu 401 thì cả GET và generate-plan đều fail.
3. **Cấu trúc response POST generate-plan** — So với `NutritionPlan.fromJson` / `Meal.fromJson`: backend đang trả `meals[].foods[]`, frontend mong đợi từng phần tử meal có sẵn name, calories, meal_type, time; cần map hoặc đổi format để UI nhận đúng plan.
