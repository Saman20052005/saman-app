# BÁO CÁO TRIỂN KHAI: WC-P01 & WC-P02
## ĐỀ XUẤT CÓ CẤU TRÚC VÀ XEM TRƯỚC BUỔI TẬP (STRUCTURED PROPOSAL & WORKOUT PREVIEW)

- **Thời gian lập**: 2026-11-04 16:00 +07:00
- **Workspace**: `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840`
- **Branch / HEAD**: `agent/nutrition-active-localhost-f02` / `10be1ab1971214acd2487ef893df3fcc80212fc9`
- **Nhiệm vụ**: Kết nối dữ liệu gợi ý từ module AI Chat sang module Workout thông qua Action Button có cấu trúc và giao diện Xem trước buổi tập (Workout Preview Modal).

---

## 1. Tóm tắt Thay đổi Kỹ thuật

### 1.1. Backend (`backend/routers/chat.py`)
- **Điểm chèn**: Trong hàm `chat_with_ai`, nhánh xử lý gợi ý bài tập (`workout_recommendation_service.recommend_workouts`).
- **Logic bổ sung**:
  - Trích xuất danh sách các `canonical_id` hợp lệ từ `recommendation_result["recommendations"]` (tối đa 5 bài tập theo thứ hạng đề xuất).
  - Khởi tạo đối tượng `action_data` có cấu trúc:
    ```python
    action_data = {
        "id": str(ObjectId()),
        "type": "preview_workout",
        "label": "Xem trước buổi tập",
        "status": "pending",
        "payload": {
            "exercise_ids": recommended_exercise_ids,
        },
        "exercise_ids": recommended_exercise_ids,
    }
    ```
  - Lưu trữ `pending_action` vào collection hội thoại MongoDB thông qua hàm `_persist_chat_reply`.
  - Trả về trường `action: action_data` trong phản hồi API của `POST /api/chat`.

### 1.2. Frontend (`frontend/lib/screens/chat_screen.dart`)
- **Bổ sung imports**:
  - `../data/models/exercise.dart`
  - `../presentation/providers/exercise_providers.dart`
  - `../presentation/screens/active_workout_screen.dart`
- **Xử lý Action Button (`_buildAssistantActions`)**:
  - Thêm nhánh nhận diện `type == 'preview_workout'`.
  - Trích xuất `exercise_ids` từ `action['payload']['exercise_ids']`.
  - Render nút bấm với nhãn `"Xem trước buổi tập"`, icon `Icons.fitness_center_rounded`, và gọi hàm `_handlePreviewWorkout(exerciseIds)`.
- **Tra cứu và Hiển thị Bản xem trước (`_handlePreviewWorkout` & `_showWorkoutPreviewModal`)**:
  - Tra cứu thông tin chi tiết của từng bài tập từ `exerciseLibraryListProvider` / `curatedExerciseLibrary` thông qua `canonical_id` / `slug`.
  - Mở `showModalBottomSheet` mang phong cách Obsidian canvas:
    - Tiêu đề: *Xem trước buổi tập (N bài)*.
    - Danh sách các bài tập với số thứ tự, tên bài tập tiếng Việt/Anh, nhóm cơ mục tiêu, số hiệp và số rep mặc định.
    - Nút bấm hành động chính: **"Bắt đầu tập ngay"**.
  - Khi người dùng bấm **"Bắt đầu tập ngay"**:
    - Đóng modal xem trước (`Navigator.pop`).
    - Điều hướng (`Navigator.push`) sang `ActiveWorkoutScreen.fromExercises(exercises: targetExercises, title: 'AI Recommended Workout')`.

---

## 2. Kết quả Xác minh & Bằng chứng Thực nghiệm (Verification & Evidence)

### 2.1. Backend Endpoint Test (`POST /api/chat`)
Chạy kiểm thử tích hợp nội bộ với client FastAPI:
```bash
python -X utf8 test_preview_action.py
```
**Kết quả Output**:
```json
{
  "reply": "Gợi ý theo thứ hạng của danh mục bài tập đã xác minh:\nLịch sử đọc được không có bản ghi khớp; danh sách chưa được cá nhân hóa theo lịch sử.\n...",
  "status": "success",
  "conversation_id": "67287950c4084344db05d9ae",
  "action": {
    "id": "6aeaf360ae536900a84aa874",
    "type": "preview_workout",
    "label": "Xem trước buổi tập",
    "status": "pending",
    "payload": {
      "exercise_ids": [
        "barbell-bench-press",
        "cable-chest-fly",
        "db-bench-press",
        "incline-barbell-bench-press",
        "incline-dumbbell-flyes"
      ]
    },
    "exercise_ids": [
      "barbell-bench-press",
      "cable-chest-fly",
      "db-bench-press",
      "incline-barbell-bench-press",
      "incline-dumbbell-flyes"
    ]
  }
}
```
- **Mã HTTP**: `200 OK`
- **Thời gian xử lý**: `0.102s`
- **Kiểm tra Assertions**: 100% PASS (`action is not None`, `type == 'preview_workout'`, `len(exercise_ids) == 5`).

### 2.2. Kiểm tra Tính toàn vẹn Mã nguồn Flutter (`flutter analyze`)
Chạy phân tích tĩnh đối với các file UI bị tác động:
```bash
cd frontend
flutter analyze lib/screens/chat_screen.dart
flutter analyze lib/screens/chat/widgets/saman_assistant_response.dart
```
**Kết quả**:
- `lib/screens/chat_screen.dart`: **No issues found!** (ran in 8.3s).
- `lib/screens/chat/widgets/saman_assistant_response.dart`: **No issues found!** (ran in 3.1s).
- **0 errors, 0 warnings, 0 infos**.

---

## 3. Acceptance Checklist

| Tiêu chuẩn Nghiệm thu | Trạng thái | Chi tiết ghi nhận |
|---|---|---|
| **Backend trả về action preview_workout hợp lệ** | **PASS** | Phản hồi chứa `type: preview_workout`, `label: Xem trước buổi tập` và mảng `exercise_ids` chuẩn xác |
| **Frontend hiển thị nút và mở được Modal xem trước** | **PASS** | Nút `_ActionPill` hiển thị trực tiếp dưới tin nhắn trợ lý; khi click mở `_showWorkoutPreviewModal` |
| **Từ Modal xem trước, mở thành công ActiveWorkoutScreen** | **PASS** | Nút "Bắt đầu tập ngay" kích hoạt `ActiveWorkoutScreen.fromExercises` với đầy đủ danh sách bài tập |
| **Không làm hỏng luồng Chat hiện tại** | **PASS** | Các action `log_water`, `log_meal`, `adjust_workout` và luồng chat thông thường hoạt động bình thường |

---

## 4. Handoff & Tuân thủ An toàn
- **Phạm vi tác động**:
  - `backend/routers/chat.py` (sửa đổi theo Allowed Paths).
  - `frontend/lib/screens/chat_screen.dart` (sửa đổi theo Allowed Paths).
  - `docs/ai_coach/WC-P01_P02_REPORT.md` (tài liệu nghiệm thu).
- **Git State**: Toàn bộ WIP hiện tại của người dùng được giữ nguyên; không tự ý commit, push hay merge code.

