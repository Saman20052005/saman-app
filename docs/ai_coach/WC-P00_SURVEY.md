# KHẢO SÁT KIẾN TRÚC MÃ NGUỒN: KẾT NỐI CHAT & WORKOUT MODULE (WC-P00)

- **Mã khảo sát**: WC-P00
- **Thời gian lập**: 2026-11-04 15:47 +07:00
- **Workspace**: `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840`
- **Mục tiêu**: Khảo sát kiến trúc read-only, lập bản đồ kết nối kỹ thuật giữa module Chat và module Workout cho chặng "Saman AI Coach — Cá nhân hóa buổi tập".

---

## 1. Trạng thái Git Hiện tại (Git State)

| Hạng mục | Giá trị quan sát |
|---|---|
| **Branch hiện tại** | `agent/nutrition-active-localhost-f02` |
| **HEAD commit** | `10be1ab1971214acd2487ef893df3fcc80212fc9` |
| **Số lượng file WIP** | **267 mục** (uncommitted porcelain entries được giữ nguyên vẹn) |
| **Tính an toàn mã nguồn** | **Read-only**: Tuyệt đối không sửa code, không ghi DB, không chạy migration |

---

## 2. Nguồn dữ liệu Ngữ cảnh (Context Sources: Profile, History, Schedule)

### 2.1. Dữ liệu Hồ sơ người dùng (Profile)
- **MongoDB Collection**: `users` (`users_collection` tại `backend/app/database.py`).
- **Backend Model / Repo**:
  - Model: `backend/app/models/user.py` (`User`, `UserProfile`, `DietaryRestrictions`, `Allergy`).
  - Router: `backend/routers/user.py`.
- **Frontend Model / Provider**:
  - Model: `frontend/lib/features/profile/data/models/profile_model.dart`, `profile_snapshot_model.dart`.
  - Provider: `profileProvider` tại `frontend/lib/providers/profile_provider.dart`.

### 2.2. Dữ liệu Lịch sử tập luyện (Workout History)
- **MongoDB Collection**: `workout_history` (`workout_history_collection` tại `backend/app/database.py`).
- **Backend Model / Handler**:
  - Model: `backend/app/models/workout.py` (`WorkoutSession`, `ExerciseLog`, `ExerciseSet`).
  - Context Normalizer: `_read_recommendation_context()` & `_normalize_canonical_logs()` tại `backend/routers/chat.py`.
- **Frontend Model / Provider**:
  - Provider: `workoutHistoryProvider`, `workoutAuthScopeProvider` tại `frontend/lib/presentation/providers/workout_history_providers.dart`.
  - Router/UI: `frontend/lib/presentation/screens/workout_history_screen.dart`.

### 2.3. Lịch tập & Kế hoạch (Schedule / Plans)
- **MongoDB Collection**: `custom_plans` (`custom_plans_collection` tại `backend/app/database.py`).
- **Backend Model**:
  - Model: `backend/app/models/workout.py` (`CustomWorkoutPlan`).
- **Frontend Model / Provider**:
  - Provider: `scheduledWorkoutProvider` tại `frontend/lib/presentation/providers/workout_home_providers.dart` (cung cấp `ScheduledSessionInfo` hiển thị trên WorkoutHomeScreen).
  - Entity: `frontend/lib/features/workout/domain/entities/workout_plan.dart`.

---

## 3. Cơ chế Bàn giao Chat sang Workout (Chat to Workout Handoff)

### Hiện trạng luồng hiển thị trong Chat UI:
1. **Dữ liệu trả về từ Backend**:
   - Khi có ý định gợi ý bài tập (`_detect_workout_recommendation_intent`), backend gọi `workout_recommendation_service.recommend_workouts()`.
   - Kết quả được format thành dạng văn bản cấu trúc markdown tiếng Việt thông qua hàm `_format_workout_recommendation_reply()` trong `backend/routers/chat.py`.
   - Danh sách bài tập được chèn trực tiếp vào nội dung trường văn bản `content` của message phản hồi (chưa bóc tách thành payload action riêng).
2. **Widget hiển thị trong Chat**:
   - Danh sách tin nhắn sử dụng `SamanMessageList` (`frontend/lib/screens/chat/widgets/saman_message_list.dart`).
   - Phản hồi từ trợ lý được hiển thị bởi `SamanAssistantResponse` (`frontend/lib/screens/chat/widgets/saman_assistant_response.dart`), render text Markdown.
   - Hàng nút hành động dưới tin nhắn: Dùng `actions: List<SamanAssistantAction>` (hiện hỗ trợ các action type: `log_water`, `log_meal`, `adjust_workout` với `_ActionPill`). Hiện tại **chưa có Action Button riêng để bấm trực tiếp "Bắt đầu buổi tập từ gợi ý" (Start Workout from Recommendation)**.

---

## 4. Điểm khởi động Buổi tập (Workout Entry Point)

Để bắt đầu một buổi tập (`Active Session`) trong module Workout hiện có của ứng dụng:

### 4.1. Màn hình & Router
- **Screen**: `ActiveWorkoutScreen` (`frontend/lib/presentation/screens/active_workout_screen.dart`).
- **Factory Entry Point**:
  ```dart
  ActiveWorkoutScreen.fromExercises({
    Key? key,
    required List<Exercise> exercises,
    String heroTag = 'hero_default',
    String title = 'Custom Workout',
  })
  ```
- **Cách điều hướng (Navigation)**:
  ```dart
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ActiveWorkoutScreen.fromExercises(
      exercises: targetExercises,
      title: 'AI Recommended Workout',
    ),
  ));
  ```

### 4.2. State & Provider quản trị Session
- **Provider chính**: `activeWorkoutSessionProvider` (`frontend/lib/presentation/providers/active_workout_providers.dart`).
- **Hàm khởi động**:
  - Khởi tạo từ danh sách Exercise: `ref.read(activeWorkoutSessionProvider.notifier).startSession(List<Exercise> exercises, {String title})`.
  - Khởi tạo từ WorkoutPlan: `ref.read(activeWorkoutSessionProvider.notifier).startSessionFromPlan(domain.WorkoutPlan plan)`.

### 4.3. Cấu trúc Payload yêu cầu
Mỗi phần tử trong danh sách `List<Exercise>` phải tuân thủ model `Exercise` (`frontend/lib/data/models/exercise.dart`), bao gồm:
- `id` (canonical ID, ví dụ: `"db-bench-press"`, `"push-up"`).
- `slug` (ví dụ: `"dumbbell-bench-press"`).
- `name` / `nameVi` (Tên bài tập tiếng Anh & tiếng Việt).
- `muscleGroup`, `targetMuscles`, `secondaryMuscles`, `equipment`.
- `difficulty`, `thumbnailUrl`, `defaultSets`, `defaultReps`, `restSeconds`, `repType`.

---

## 5. Định danh Bài tập Chuẩn (Canonical ID)

- **Trường ID chính**: **`exercise.id`** (kết hợp ánh xạ qua `exercise.slug`).
- **Định dạng chuẩn hóa**: Kebab-case ngắn gọn (ví dụ: `db-bench-press`, `barbell-bench-press`, `ab-wheel-rollout`, `push-up`).
- **Cơ chế phân giải**:
  - File catalog chuẩn hóa: `backend/app/data/ai_exercise_catalog.generated.json` (chứa 49 bài tập).
  - Trình phân giải `ExerciseCatalogResolver` (`backend/app/services/exercise_catalog_resolver.py`):
    - Khóa định danh chính: `canonical_id` (trùng khớp với trường `id` trong catalog).
    - Khóa phụ: `slug` hoặc tên bài tập chuẩn hóa không dấu (`normalized_name`).
- **Trong Flutter Workout Library**:
  - Danh sách bài tập được tải qua `exerciseLibraryListProvider` (`frontend/lib/presentation/providers/exercise_providers.dart`).
  - Giao diện thẻ bài tập định danh theo `exercise.id` (`ValueKey('exercise_row_${exercise.id}')`).

---

## 6. Kết luận & Đề xuất Hướng kết nối (Handover Recommendations)

1. **Khả thi kết nối**: Module Workout (`ActiveWorkoutScreen`) đã có sẵn phương thức nhận `List<Exercise>` hoàn chỉnh qua `ActiveWorkoutScreen.fromExercises(...)`.
2. **Cầu nối cần bổ sung ở chặng tiếp theo**:
   - Backend Chat: Trả thêm cấu trúc danh sách `canonical_ids` hoặc payload action trong phản hồi gợi ý bài tập.
   - Frontend Chat: Thêm nút hành động (ví dụ: `Bắt đầu tập luyện`) trên tin nhắn gợi ý để trích xuất danh sách bài tập từ `exerciseLibraryListProvider` dựa theo `canonical_ids` và `Navigator.push` sang `ActiveWorkoutScreen`.
3. **Bảo toàn hiện trạng**: Không có thay đổi nào đối với logic nghiệp vụ hay mã nguồn trong đợt khảo sát WC-P00 này.

