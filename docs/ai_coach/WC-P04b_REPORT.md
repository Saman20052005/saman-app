# WC-P04b: Triển khai Tính năng Lưu thành Giáo án (Save Plan Report)

- **Ngày thực hiện**: 2026-11-04
- **Trạng thái**: PASS
- **Mục tiêu**: Thêm hành động `save_plan` ("Lưu thành Giáo án") vào gợi ý bài tập của AI Chat, kết nối với `WorkoutRepository.createWorkoutPlan` để lưu giáo án vào MongoDB (`custom_plans`), hoàn tất chu trình từ Chat sang Custom Workout Plan.

---

## 1. Tóm tắt Thay đổi

### 1.1. Backend (`backend/routers/chat.py`)
- **Vị trí sửa đổi**: Trong logic xử lý đề xuất bài tập (`_detect_workout_recommendation_intent`):
  - Khi có danh sách bài tập đề xuất (`recommended_exercise_ids`), backend sinh 2 action objects:
    1. `preview_workout`: Xem trước buổi tập.
    2. `save_plan`: Lưu thành Giáo án.
       ```python
       save_action = {
           "id": str(ObjectId()),
           "type": "save_plan",
           "label": "Lưu thành Giáo án",
           "status": "pending",
           "payload": {
               "exercise_ids": recommended_exercise_ids,
           },
           "exercise_ids": recommended_exercise_ids,
       }
       ```
  - Cả 2 action được đóng gói vào `action_data["actions"] = [preview_action, save_action]` và trả về đồng thời ở cả trường `"action"` và top-level `"actions"`.

### 1.2. Frontend (`frontend/lib/screens/chat_screen.dart`)
- **Import mới**:
  - `WorkoutPlan`, `WorkoutExercise` từ [`frontend/lib/features/workout/domain/entities/workout_plan.dart`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/frontend/lib/features/workout/domain/entities/workout_plan.dart).
  - `workoutRepositoryProvider` từ [`frontend/lib/features/workout/data/repositories/workout_repository_impl.dart`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/frontend/lib/features/workout/data/repositories/workout_repository_impl.dart).
- **Cập nhật `_buildAssistantActions`**:
  - Duyệt mảng `action['actions']` để render đồng thời 2 nút bấm trợ lý:
    1. "Xem trước buổi tập" (icon: `Icons.fitness_center_rounded`, `isPrimary: true`).
    2. "Lưu thành Giáo án" (icon: `Icons.save`, `isPrimary: false`).
- **Thêm hàm xử lý sự kiện `_handleSavePlan(List<String> exerciseIds)`**:
  - Tra cứu các đối tượng `Exercise` từ `exerciseLibraryListProvider` (hoặc fallback `curatedExerciseLibrary`).
  - Tạo thực thể `WorkoutPlan`:
    - `title`: `AI Workout - YYYY-MM-DD HH:mm`.
    - `category`: Nhóm cơ mục tiêu của bài tập đầu tiên (mặc định `'Full Body'`).
    - `level`: Độ khó của bài tập (mặc định `'Intermediate'`).
    - `duration`: `exercises.length * 10` phút.
    - `kcal`: `exercises.length * 50` kcal.
    - `exercises`: Danh sách `WorkoutExercise(name, reps, setCount)`.
  - Gọi `ref.read(workoutRepositoryProvider).createWorkoutPlan(plan)` (gửi request `POST /api/workouts/plans` lên MongoDB).
  - Hiển thị thông báo `SnackBar`: "Đã lưu giáo án thành công!" (hoặc thông báo lỗi nếu thất bại).

---

## 2. Kết quả Kiểm thử & Bằng chứng Xác minh

### 2.1. Backend Unit & Integration Tests
- **Test File**: `test_chat_workout_grounding.py`
  - **Kết quả**: 13/13 tests PASS (0 regressions).
- **Integration Test Action Payload**:
  - Test case: `TestWCP04bSavePlan.test_chat_returns_preview_and_save_plan_actions`
  - **Kết quả**: PASS.
  - Payload xác minh:
    - `action["actions"][0]["type"] == "preview_workout"`
    - `action["actions"][1]["type"] == "save_plan"`
    - `actions[0]["type"] == "preview_workout"`
    - `actions[1]["type"] == "save_plan"`

### 2.2. Frontend Analyzer & Widget Tests
- **Flutter Analyzer**:
  ```bash
  cd frontend
  flutter analyze --no-fatal-infos --no-fatal-warnings lib/screens/chat_screen.dart lib/screens/chat/widgets/saman_assistant_response.dart
  ```
  - **Kết quả**: `No issues found! (ran in 3.8s)`.
- **Targeted Widget Test**:
  ```bash
  cd frontend
  flutter test test/chat_loading_and_recovery_test.dart
  ```
  - **Kết quả**: 12/12 tests PASS.

---

## 3. Đối chiếu Acceptance Criteria

| Tiêu chí | Trạng thái | Ghi chú |
| :--- | :--- | :--- |
| Backend trả về 2 actions: `preview_workout` và `save_plan` | **PASS** | Đã xác minh qua test API integration |
| Frontend hiển thị nút "Lưu thành Giáo án" (icon `Icons.save`) | **PASS** | Đã cấu hình trong `_buildAssistantActions` |
| Bấm nút gọi thành công hàm tạo Plan qua `WorkoutRepository` | **PASS** | `_handleSavePlan` gọi `WorkoutRepository.createWorkoutPlan` |
| `flutter analyze` không báo lỗi | **PASS** | 0 lỗi, 0 cảnh báo mới |

---

## 4. Danh sách File Sửa đổi

- `backend/routers/chat.py`
- `frontend/lib/screens/chat_screen.dart`
- `docs/ai_coach/WC-P04b_REPORT.md` (Tài liệu báo cáo này)

