# WC-P04a: Khảo sát Hợp đồng Lịch tập (Schedule Contract Audit)

- **Ngày thực hiện**: 2026-11-04
- **Trạng thái**: PASS (Read-only khảo sát & lập bản đồ hợp đồng)
- **Mục tiêu**: Khảo sát mã nguồn Frontend và Backend để làm rõ cách hệ thống Saman lưu trữ, quản lý và hiển thị lịch tập / giáo án tập luyện (Schedules / Custom Plans), đồng thời đánh giá năng lực của AI Engine hiện tại trong việc sinh kế hoạch tập nhiều ngày.

---

## 1. Tổng quan & Bản đồ Module

```
+-----------------------------------------------------------------------------------+
| FRONTEND                                                                          |
|                                                                                   |
|  [Workout Home UI]  <--- static ---  scheduledWorkoutProvider / upcomingPlans     |
|                                                                                   |
|  [Create Plan UI]   ---> savePlan() ---> workoutDemoRepository (Mock Repo)        |
|                                                                                   |
|  [Workout Feature]  ---> WorkoutRepositoryImpl ---> POST /api/workouts/plans      |
+-----------------------------------------------------------------------------------+
                                            |
                                            v (HTTP JSON REST)
+-----------------------------------------------------------------------------------+
| BACKEND                                                                           |
|                                                                                   |
|  [FastAPI Router]   ---> backend/routers/workout.py                               |
|                          - POST /api/workouts/plans                               |
|                          - GET  /api/workouts/plans                               |
|                          - PUT  /api/workouts/plans/{id}                          |
|                          - DEL  /api/workouts/plans/{id}                          |
|                                            |                                      |
|                                            v                                      |
|  [MongoDB]          ---> custom_plans_collection ("custom_plans")                 |
|                                                                                   |
|  [AI Coach Engine]  ---> backend/app/services/workout_recommendation.py           |
|                          - recommend_workouts(): 1 buổi tập duy nhất (max 5 bài)  |
|                          - context: "schedule": "not_persisted"                   |
+-----------------------------------------------------------------------------------+
```

---

## 2. Backend API & Data Contracts (`custom_plans`)

### 2.1. File nguồn
- Router: [`backend/routers/workout.py`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/backend/routers/workout.py#L261-L300)
- MongoDB Collection: `custom_plans_collection` (tên collection: `custom_plans`)
- Xác thực: Yêu cầu Header `Authorization: Bearer <token>` qua dependency `verify_token` hoặc `get_current_user`.

### 2.2. Danh sách Endpoints

| Phương thức | Endpoint | Chức năng | Input | Output |
| :--- | :--- | :--- | :--- | :--- |
| `GET` | `/api/workouts/plans` | Lấy danh sách giáo án của user | Query: `difficulty`, `target_muscle` | `{"plans": [...], "total_count": int, "filters_applied": {...}}` |
| `POST` | `/api/workouts/plans` | Tạo giáo án mới | Body JSON: `WorkoutPlan` | `{"id": "...", "message": "...", "plan": {...}, "created_at": "..."}` |
| `PUT` | `/api/workouts/plans/{plan_id}`| Cập nhật giáo án hiện có | Path: `plan_id`, Body: `WorkoutPlan` | `{"id": "...", "message": "...", "plan": {...}, "updated_at": "..."}` |
| `DELETE` | `/api/workouts/plans/{plan_id}`| Xóa giáo án | Path: `plan_id` | `{"id": "...", "message": "...", "deleted_at": "..."}` |

### 2.3. Pydantic Models & Data Schema
Tại [`backend/routers/workout.py`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/backend/routers/workout.py):

```python
class Exercise(pd.BaseModel):
    name: str
    sets: int
    reps: int
    weight: Optional[float] = None
    rest_time: int  # tính bằng giây

class WorkoutPlan(pd.BaseModel):
    id: Optional[str] = None
    name: str
    description: str
    exercises: List[Exercise]
    duration_minutes: int
    difficulty: str  # beginner, intermediate, advanced
    target_muscles: List[str]
```

### 2.4. JSON Request Payload Chuẩn (`POST /api/workouts/plans`)
```json
{
  "name": "Full Body Push Focus",
  "description": "AI-generated workout routine",
  "difficulty": "intermediate",
  "duration_minutes": 45,
  "target_muscles": ["Chest", "Shoulders", "Triceps"],
  "exercises": [
    {
      "name": "Dumbbell Bench Press",
      "sets": 4,
      "reps": 10,
      "weight": 20.0,
      "rest_time": 90
    },
    {
      "name": "Push-up",
      "sets": 3,
      "reps": 15,
      "weight": null,
      "rest_time": 60
    }
  ]
}
```

### 2.5. MongoDB Document Structure (`custom_plans`)
Khi được insert vào collection `custom_plans`, backend tự động đính kèm thông tin chủ sở hữu:
```json
{
  "_id": ObjectId("..."),
  "name": "Full Body Push Focus",
  "description": "AI-generated workout routine",
  "difficulty": "intermediate",
  "duration_minutes": 45,
  "target_muscles": ["Chest", "Shoulders", "Triceps"],
  "exercises": [...],
  "email": "user@example.com",
  "user_id": "67b0...",
  "created_at": ISODate("2026-11-04T09:00:00Z")
}
```

> [!NOTE]
> **Nhận định quan trọng về Backend Plan**:
> Model `WorkoutPlan` và collection `custom_plans` hiện tại biểu diễn **một buổi tập đơn lẻ (Single Routine)**, KHÔNG PHẢI một lịch tập theo tuần hay lịch theo ngày cụ thể (Calendar Schedule). Hệ thống chưa có trường `day_of_week`, `scheduled_date`, hoặc `week_structure`.

---

## 3. Frontend Providers & Repositories

### 3.1. Hợp đồng Tầng Data & Domain Clean Architecture
- Interface: [`frontend/lib/features/workout/domain/repositories/workout_repository.dart`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/frontend/lib/features/workout/domain/repositories/workout_repository.dart)
  - `Future<List<WorkoutPlan>> getWorkoutPlans()`
  - `Future<void> createWorkoutPlan(WorkoutPlan plan)`
  - `Future<void> deleteWorkoutPlan(String planId)`
- Entity: [`frontend/lib/features/workout/domain/entities/workout_plan.dart`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/frontend/lib/features/workout/domain/entities/workout_plan.dart)
  - Các trường: `id`, `title`, `category`, `level`, `duration`, `kcal`, `exercises: List<WorkoutExercise>`.
- Model DTO: [`frontend/lib/features/workout/data/models/workout_plan_model.dart`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/frontend/lib/features/workout/data/models/workout_plan_model.dart)
  - Phương thức `.toJson()` serialize đúng format backend yêu cầu:
    - `name: title`
    - `difficulty: level.toLowerCase()`
    - `duration_minutes: duration`
    - `target_muscles: [category]`
    - `exercises: exercises.map(...)`
- Implementation: [`frontend/lib/features/workout/data/repositories/workout_repository_impl.dart`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/frontend/lib/features/workout/data/repositories/workout_repository_impl.dart#L126-L157)
  - Gọi HTTP `ApiClient.dio.post(ApiConfig.createPlanEndpoint, data: model.toJson())`.

### 3.2. Màn hình Tạo Giáo án & Mock Provider Hiện tại
- Provider UI: [`frontend/lib/presentation/providers/create_plan_providers.dart`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/frontend/lib/presentation/providers/create_plan_providers.dart#L44-L62)
  ```dart
  Future<bool> savePlan({String? planId}) async {
    ...
    await ref.read(workoutDemoRepositoryProvider).savePlan(
      id: planId,
      name: state.name.trim(),
      exerciseIds: state.exercises.map((e) => e.id).toList(),
    );
    ...
  }
  ```
- Nhận xét: `create_plan_providers.dart` đang kết nối với `workoutDemoRepositoryProvider` (sử dụng in-memory mock repository `MockExerciseRepository`), chứ chưa nối sang `WorkoutRepositoryImpl` để đẩy lên backend MongoDB.

---

## 4. Đánh giá Năng lực AI Engine (`workout_recommendation.py`)

### 4.1. File nguồn
[`backend/app/services/workout_recommendation.py`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/backend/app/services/workout_recommendation.py)

### 4.2. Khả năng hiện tại
1. **Chỉ sinh 1 buổi tập duy nhất**:
   - Hàm `recommend_workouts(...)` giới hạn tối đa `MAX_RECOMMENDATIONS = 5` bài tập.
   - Thuật toán chấm điểm cơ bắp (`_MUSCLE_SCORES`), ưu tiên nhóm cơ mục tiêu (`requested_muscle_groups`), trừ điểm các bài đã tập gần đây trong vòng 90 ngày (`HISTORY_WINDOW_DAYS = 90`, `_RECENT_SESSION_PENALTY = 10`).
   - Kết quả trả về là một danh sách phẳng các bài tập cho một phiên duy nhất.
2. **Trạng thái Context**:
   - Dòng 111 ghi rõ:
     ```python
     "unknown_profile_fields": {
         "training_experience": "not_persisted",
         "available_equipment": "not_persisted",
         "injuries": "not_persisted",
         "schedule": "not_persisted",
     }
     ```
   - Trường `"schedule"` hiện chưa được lưu hay phân tích trong hồ sơ người dùng.
3. **Chưa hỗ trợ Kế hoạch Nhiều ngày (Multi-day Plan)**:
   - Không có hàm sinh lịch tập theo tuần (chưa có split logic: Push/Pull/Legs, Upper/Lower, 3-day split, 4-day split).
   - Không có logic phân phối bài tập qua các ngày khác nhau để đảm bảo thời gian phục hồi cơ (muscle recovery period).

---

## 5. Hiện trạng hiển thị Lịch tập trên UI (`workout_home_providers.dart`)

Tại [`frontend/lib/presentation/providers/workout_home_providers.dart`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/frontend/lib/presentation/providers/workout_home_providers.dart):

1. **`scheduledWorkoutProvider`**:
   - Cung cấp `ScheduledSessionInfo` tĩnh: `"Upper Body Strength"`, 50 phút, 5 bài tập, status: `"Planned"`.
   - Chưa kết nối với API hay cơ sở dữ liệu thực.
2. **`upcomingPlansProvider`**:
   - Cung cấp danh sách `UpcomingPlanSession` tĩnh cho 2 ngày:
     - Thứ 4: `"Lower Body Strength"` (45 min · 5 exercises).
     - Thứ 5: `"Active Recovery"` (25 min flow · Mobility, isRest: true).
   - Chưa có API backend hỗ trợ đọc lịch trình ngày này.
3. **`recentWorkoutSummaryProvider`**:
   - ĐÃ ĐƯỢC KẾT NỐI ĐỘNG với `workoutHistoryProvider`, tổng hợp từ các buổi tập thực tế đã hoàn thành (`finishedAt != null`).

---

## 6. Đề xuất Kiến trúc cho Giai đoạn tiếp theo (WC-P04b)

Từ các phát hiện trên, để hiện thực hóa việc đề xuất và lưu kế hoạch từ AI Chat sang module Lịch/Giáo án:

### Phương án 1 (Khuyến nghị - Khớp với kiến trúc hiện có): "Lưu Giáo án Tùy chỉnh (Save as Custom Plan)"
- AI Chat trả về action:
  ```json
  {
    "type": "save_custom_plan",
    "label": "Lưu vào Giáo án của tôi",
    "payload": {
      "name": "Giáo án Ngực - Tay sau từ AI",
      "exercise_ids": ["db-bench-press", "push-up", "pec-deck-fly"],
      "difficulty": "intermediate",
      "target_muscles": ["Chest", "Triceps"]
    }
  }
  ```
- Khi bấm nút trên Chat, Frontend gọi trực tiếp `WorkoutRepository.createWorkoutPlan(...)` để ghi vào MongoDB qua endpoint `POST /api/workouts/plans`.
- Ưu điểm: Tận dụng 100% hợp đồng backend `custom_plans` và frontend repository đã có sẵn, 0 rủi ro thay đổi schema DB.

### Phương án 2: "Mở rộng Multi-day Schedule Contract"
- Cần tạo bảng/collection mới `workout_schedules` tại Backend, lưu `user_id`, `schedule_days: [{"day_of_week": 1, "exercises": [...]}]`.
- Cần mở rộng `workout_recommendation.py` để sinh cấu trúc chia ngày (split).
- Cần cập nhật `scheduledWorkoutProvider` và `upcomingPlansProvider` trên Frontend để đọc từ API.
- Ưu điểm: Đầy đủ tính năng lịch tuần hoàn, nhưng cần nhiều sửa đổi trên cả Backend, Database và Frontend Home.

---

## 7. Kết luận
- **Hợp đồng Lịch/Giáo án hiện tại**: Đã có sẵn bộ API hoàn chỉnh (`/api/workouts/plans`) và Clean Architecture repository cho **Custom Workout Plans (Giáo án đơn lẻ)**.
- **AI Engine**: Hiện chỉ hỗ trợ gợi ý 1 buổi tập duy nhất (`recommend_workouts`).
- **Khuyến nghị cho WC-P04b**: Triển khai tính năng **"Lưu thành Giáo án (Save Plan)"** từ đề xuất của AI Chat để hoàn tất vòng lặp từ Chat sang Workout Plan một cách an toàn và nhỏ gọn nhất (Smallest Safe Diff).

