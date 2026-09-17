# TASKS.md — Saman Fitness

> Theo dõi trạng thái các task theo từng module.
> Cập nhật khi bắt đầu / hoàn thành task.
> Format: `- [ ]` todo · `- [x]` done · `- [~]` in progress

---

## Legend

| Symbol | Meaning |
|---|---|
| `[ ]` | Chưa làm |
| `[~]` | Đang làm |
| `[x]` | Hoàn thành |
| `[!]` | Blocked / cần review |

---

## Phase 0 — Project Setup

- [x] Khởi tạo Flutter project
- [x] Khởi tạo FastAPI backend
- [x] Kết nối MongoDB
- [x] Cấu hình Riverpod v2
- [x] Setup Dio HTTP client + JWT interceptor
- [x] Cấu hình Cloudinary
- [x] Setup môi trường dev (mock classifier)
- [ ] Viết `.env.example` đầy đủ
- [ ] Setup CI/CD pipeline cơ bản

---

## Phase 1 — Authentication (F6)

### Backend
- [x] `POST /api/v1/auth/login` — OAuth Google / Facebook / Apple
- [x] JWT generation + validation middleware
- [ ] `POST /api/v1/auth/refresh` — Refresh token
- [ ] Unit test: auth service

### Frontend
- [x] Google Sign-In flow
- [x] Facebook Sign-In flow
- [x] Apple Sign-In flow
- [x] JWT storage (Hive)
- [x] Auto-login khi app restart
- [ ] Profile setup screen (sau lần đầu login)

---

## Phase 2 — Food Recognition & Nutrition Logging (F1 + F2)

### Backend — Food Analysis
- [x] `POST /api/v1/food/analyze` — nhận ảnh, trả food + macro
- [x] `ClassificationProviderFactory` — chọn pytorch / mock
- [x] `FoodAnalysisEnsemble` — pipeline phân tích ảnh
- [x] `NutritionMappingService` — tra cứu macro từ MongoDB / USDA
- [ ] Test với PyTorch model thực (không phải mock)
- [ ] Handle edge case: ảnh không phải món ăn
- [ ] Unit test: food analysis service

### Backend — Nutrition Logging
- [x] `POST /api/v1/nutrition/log` — ghi log bữa ăn
- [x] `GET /api/v1/nutrition/daily` — lấy daily summary
- [ ] `POST /api/v1/nutrition/water` — log nước uống
- [ ] `POST /api/v1/nutrition/plan` — tạo meal plan AI
- [ ] `GET /api/v1/nutrition/plan` — lấy meal plan hiện tại

### Frontend
- [x] Camera / ImagePicker integration
- [x] Food analysis result screen (review + confirm)
- [x] Daily nutrition dashboard (macros progress bar)
- [ ] Meal log list theo ngày
- [ ] Water tracking UI
- [ ] Meal plan screen
- [ ] Manual food entry (fallback khi ảnh không nhận dạng được)

---

## Phase 3 — Workout Tracking (F3)

### Backend
- [x] `GET /api/v1/workout/exercises` — danh sách bài tập
- [x] `POST /api/v1/workout/log` — log buổi tập
- [ ] Seed data: exercises collection (muscle group, difficulty, media)
- [ ] `GET /api/v1/workout/history` — lịch sử tập luyện
- [ ] Unit test: workout service

### Frontend
- [x] Exercise library screen (filter theo muscle group, difficulty)
- [x] Exercise detail screen (video / GIF demo)
- [ ] Active workout screen (log sets / reps / weight)
- [ ] Workout history screen
- [ ] Workout summary screen (sau khi kết thúc buổi tập)

---

## Phase 4 — AI Chat Assistant (F4)

### Backend
- [x] `POST /api/v1/chat/message` — gửi/nhận tin nhắn AI
- [x] Gemini API integration
- [x] OpenAI fallback
- [x] Context builder (profile + nutrition + workout)
- [ ] Stream response (SSE) cho UX mượt hơn
- [ ] Lưu chat history vào MongoDB
- [ ] Unit test: chat service (mock AI provider)

### Frontend
- [x] Chat UI screen
- [x] Message bubbles (user / assistant)
- [ ] Streaming response UI (typing indicator)
- [ ] Chat history persistence

---

## Phase 5 — Progress Reports (F5)

### Backend
- [ ] `GET /api/v1/reports/nutrition` — báo cáo dinh dưỡng (day / week / month)
- [ ] `GET /api/v1/reports/workout` — báo cáo tập luyện
- [ ] Aggregation queries MongoDB cho weekly/monthly stats

### Frontend
- [ ] Nutrition report screen (charts: calories, macro trends)
- [ ] Workout report screen (charts: frequency, volume)
- [ ] Date range picker (week / month)

---

## Phase 6 — Polish & Production

- [ ] Error states cho tất cả màn hình (empty state, network error)
- [ ] Loading skeletons thay vì spinner
- [ ] Onboarding flow (lần đầu dùng app)
- [ ] Push notifications (nhắc nhở log bữa ăn, uống nước)
- [ ] App icon + splash screen
- [ ] Switch sang PyTorch classifier trên production
- [ ] MongoDB indexes đầy đủ
- [ ] Rate limiting trên backend API
- [ ] Privacy policy + AI disclaimer screen
- [ ] App Store / Google Play submission

---

## Backlog (Post-MVP)

- [ ] Mở rộng food dataset với món Việt Nam
- [ ] Barcode scanning cho packaged food
- [ ] Wearable / smartwatch integration
- [ ] Weekly email report
- [ ] Dark mode

---

## Known Issues / Blockers

| ID | Issue | Status | Owner |
|---|---|---|---|
| #001 | Food-101 dataset thiếu món Việt — accuracy thấp với món Việt | Open | - |
| #002 | Mock classifier trả kết quả deterministic — cần test với real model | Open | - |
| #003 | Gemini API rate limit trong giờ cao điểm | Open | - |

---
