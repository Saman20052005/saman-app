# WC-P05c: Lưu Sở thích/Điều kiện dài hạn (Long-term Preferences) vào User Profile & Tương tác Chat

- **Ngày thực hiện**: 2026-11-04
- **Trạng thái**: PASS
- **Mục tiêu**: Triển khai luồng lưu "Sở thích/Điều kiện dài hạn" (Long-term Preferences) từ đề xuất bài tập trong Chat vào Hồ sơ người dùng (User Profile), đưa ngữ cảnh sở thích vào LLM Prompt của các lượt chat tiếp theo, và hiển thị nút hành động "Lưu điều kiện này làm mặc định" trên giao diện Chat Flutter.

---

## 1. Tóm tắt các Thay đổi Triển khai

### 1.1. Backend Data Models ([`backend/app/models/user.py`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/backend/app/models/user.py))
- Bổ sung trường `preferences: Optional[Dict[str, Any]] = Field(default_factory=dict)` vào các Pydantic schema:
  - `UserProfileInput`: Hỗ trợ nhận `preferences` khi cập nhật profile qua API.
  - `ProfileUpdateRequest`: Hỗ trợ cập nhật sở thích theo schema update.
  - `UserDB`: Đảm bảo mapping dữ liệu người dùng từ MongoDB có trường `preferences`.

### 1.2. Backend Profile API ([`backend/routers/user.py`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/backend/routers/user.py))
- Mở rộng `ALLOWED_PROFILE_FIELDS` thêm trường `"preferences"`.
- Bổ sung `preferences` vào `existing_data` khi đọc snapshot người dùng hiện tại từ DB.
- Cập nhật hàm `update_profile` (`POST/PUT /api/user/update-profile`):
  - Khi payload gửi lên có `preferences`, hệ thống cập nhật đồng thời vào MongoDB (`$set: {"preferences": ..., "profile.preferences": ...}`).
  - Cho phép lưu riêng `preferences` ngay cả khi các chỉ số tính toán sức khỏe (chiều cao, cân nặng, v.v.) chưa được hoàn thiện.
  - Bảo toàn hợp đồng phản hồi cấp cao (`user_id`, `email`, `full_name`, `avatar`, `avatar_source`, `can_use_google_avatar`, `profile`, `health_stats`), trong đó `preferences` được trả về an toàn trong `profile["preferences"]`.
- Cập nhật hàm `get_profile` (`GET /api/user/profile`):
  - Trả về `preferences` bên trong đối tượng `profile` của user.

### 1.3. Backend Chat & Recommendation Engine ([`backend/routers/chat.py`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/backend/routers/chat.py))
- **Sinh Action `save_preference`**:
  - Trong logic xử lý đề xuất bài tập (`_detect_workout_recommendation_intent`), khi phát hiện người dùng có đưa ra các điều kiện/ràng buộc về thiết bị (`equipment`) hoặc nhóm cơ mục tiêu (`requested_muscles`), hệ thống tự động sinh thêm action `save_preference`:
    ```json
    {
      "id": "<ObjectId>",
      "type": "save_preference",
      "label": "Lưu điều kiện này làm mặc định",
      "status": "pending",
      "payload": {
        "preferences": {
          "equipment": "...",
          "target_muscles": [...]
        }
      }
    }
    ```
  - Action này được đóng gói cùng `preview_workout` ("Xem trước buổi tập") và `save_plan` ("Lưu thành Giáo án") trong danh sách `action_data["actions"]`.
- **System Prompt & Context Grounding**:
  - Cập nhật `_build_preferences_context`: Đọc `user.get("preferences")` hoặc `user.get("profile", {}).get("preferences")`, trích xuất thiết bị ưu tiên (`equipment`) và nhóm cơ ưu tiên (`target_muscles`), định dạng thành chỉ dẫn cho AI:
    - `- Thiết bị tập luyện ưu tiên / điều kiện tập: {equipment}`
    - `- Nhóm cơ ưu tiên: {target_muscles}`
  - Cập nhật `build_workout_grounding_context`: Khi người dùng tra cứu lịch sử buổi tập, nếu trong hồ sơ đã lưu sở thích, hệ thống tự động bổ sung dòng `[SỞ THÍCH & ĐIỀU KIỆN TẬP LUYỆN ĐÃ LƯU]: ...` vào DB TRUTH context.

### 1.4. Frontend Chat UI ([`frontend/lib/screens/chat_screen.dart`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/frontend/lib/screens/chat_screen.dart))
- Import `ApiClient` từ [`frontend/lib/services/api_client.dart`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/frontend/lib/services/api_client.dart).
- Trong `_buildAssistantActions`:
  - Bắt action type `save_preference`.
  - Hiển thị nút hành động "Lưu điều kiện này làm mặc định" với icon `Icons.bookmark`.
- Thêm hàm xử lý sự kiện `_handleSavePreference(Map<String, dynamic> preferences)`:
  - Gửi request `PUT /api/user/update-profile` với body `{"preferences": preferences}` thông qua `ApiClient.dio`.
  - Hiển thị SnackBar thông báo thành công: *"Đã lưu điều kiện tập luyện làm mặc định!"* (màu xanh lục).
  - Bắt lỗi mạng và hiển thị SnackBar lỗi nếu thất bại (màu đỏ).

---

## 2. Kết quả Xác minh & Kiểm thử (Verification Evidence)

### 2.1. Backend Unit & Contract Tests
- **Test Suite 1: History Context Formatting & Statuses**
  - Lệnh: `python -X utf8 -m unittest backend.tests.test_ai03_workout_history_context`
  - Kết quả: **14/14 tests PASS** (0 regressions).
- **Test Suite 2: Chat Workout Grounding**
  - Lệnh: `python -X utf8 -m unittest backend.tests.test_chat_workout_grounding`
  - Kết quả: **13/13 tests PASS** (0 regressions).
- **Test Suite 3: User Profile Identity Contract & Keys**
  - Lệnh: `python -X utf8 -m unittest backend.tests.test_user_profile_identity`
  - Kết quả: **9/9 tests PASS** (0 regressions).
- **Test Suite 4: Save Preferences Flow & Action Generation**
  - Lệnh: `python -X utf8 verify_save_preference.py`
  - Kết quả: **4/4 tests PASS**.
    - `test_user_models_support_preferences`: PASS.
    - `test_preferences_prompt_context_formatting`: PASS.
    - `test_user_router_update_profile_saves_preferences`: PASS.
    - `test_chat_returns_save_preference_action_when_constraints_detected`: PASS (sinh đủ 3 actions: `preview_workout`, `save_plan`, `save_preference`).

### 2.2. Frontend Analyzer & Widget Tests
- **Flutter Analyzer**:
  - Lệnh: `cd frontend; flutter analyze --no-fatal-infos --no-fatal-warnings lib/screens/chat_screen.dart`
  - Kết quả: `No issues found! (ran in 8.5s)`.
- **Flutter Widget Test**:
  - Lệnh: `cd frontend; flutter test test/chat_loading_and_recovery_test.dart`
  - Kết quả: **12/12 tests PASS**.

---

## 3. Đối chiếu Acceptance Criteria

| Tiêu chí | Trạng thái | Ghi chú |
| :--- | :--- | :--- |
| Model `UserProfileInput`, `ProfileUpdateRequest`, `UserDB` có trường `preferences` | **PASS** | Đã cấu hình `default_factory=dict` tương thích ngược |
| API `PUT /api/user/update-profile` lưu được `preferences` vào MongoDB | **PASS** | Đã xác minh qua unit test và repository mock |
| AI Chat sinh action `save_preference` (icon `Icons.bookmark`) khi phát hiện điều kiện | **PASS** | Đã xác minh action payload với `target_muscles` / `equipment` |
| Bấm nút hiển thị SnackBar: "Đã lưu điều kiện tập luyện làm mặc định!" | **PASS** | `_handleSavePreference` tích hợp gọi API qua `ApiClient.dio` |
| `_build_preferences_context` & grounding đưa preferences vào LLM prompt | **PASS** | Định dạng chi tiết thiết bị và nhóm cơ ưu tiên |
| Không làm phát sinh lỗi/cảnh báo mới trên backend và frontend | **PASS** | 0 new warnings, 0 new analyzer errors, 0 test regressions |

---

## 4. Danh sách File Sửa đổi

- `backend/app/models/user.py`
- `backend/routers/user.py`
- `backend/routers/chat.py`
- `frontend/lib/screens/chat_screen.dart`
- `docs/ai_coach/WC-P05c_REPORT.md` (Tài liệu báo cáo này)

