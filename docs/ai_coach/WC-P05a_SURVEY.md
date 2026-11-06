# WC-P05a: Khảo sát Context Lịch sử & Sở thích Người dùng (History Context & User Profile Preferences Survey)

- **Ngày thực hiện**: 2026-11-04
- **Trạng thái**: PASS (Read-only khảo sát & lập bản đồ dữ liệu)
- **Mục tiêu**: Khảo sát mã nguồn Backend để làm rõ cách hệ thống Saman trích xuất lịch sử tập luyện (Workout History Context), cấu trúc dữ liệu hồ sơ người dùng (User Profile Preferences), và khả năng xử lý các phản hồi/sở thích dài hạn từ giao diện Chat.

---

## 1. Bản đồ Dữ liệu & Luồng Xử lý

```
+-----------------------------------------------------------------------------------------+
| WORKOUT HISTORY (MongoDB: "workout_history")                                            |
|                                                                                         |
|  Doc fields: started_at, finished_at, total_duration_minutes, total_volume_kg,          |
|              exercise_logs: [ { exercise_id, exercise_slug, is_completed, reps, ... } ]  |
+-----------------------------------------------------------------------------------------+
                                 |
                                 v
+-----------------------------------------------------------------------------------------+
| CHAT CONTEXT BUILDERS (backend/routers/chat.py)                                         |
|                                                                                         |
|  1. _read_latest_workout_context (General Chat):                                        |
|     - Quét timestamp s.get("start_time" | "started_at" | "created_at" | ...)              |
|     - Normalize canonical logs: đếm completed_sets, incomplete_sets                     |
|     - In ra text: "Hiệp: X hoàn thành, Y chưa hoàn thành"                               |
|     - KHÔNG phân biệt trạng thái session (đang tập vs đã xong)                          |
|                                                                                         |
|  2. build_workout_grounding_context (Date Query / Recent Grounding):                     |
|     - Lọc qua is_session_completed(s): BẮT BUỘC finished_at hợp lệ & >= started_at       |
|     - LOẠI BỎ HOÀN TOÀN các session dở dang (finished_at is None)                       |
|     - _format_session_card: CHỈ LỌC các set có is_completed == True                     |
|     - Bài tập bị bỏ qua (skipped / is_completed == False) KHÔNG xuất hiện                |
+-----------------------------------------------------------------------------------------+

+-----------------------------------------------------------------------------------------+
| USER PROFILE & PREFERENCES (backend/app/models/user.py & backend/routers/user.py)       |
|                                                                                         |
|  UserDB / UserProfileInput:                                                             |
|     - Chỉ có 8 trường cơ bản: full_name, age, gender, height, weight,                   |
|                               activity_level, goal, health_stats                        |
|     - KHÔNG CÓ TRƯỜNG SỞ THÍCH: equipment_available, avoid_exercises, preferences, ...   |
|     - workout_recommendation.py context: "schedule": "not_persisted",                   |
|       "training_experience": "not_persisted", "available_equipment": "not_persisted"    |
+-----------------------------------------------------------------------------------------+

+-----------------------------------------------------------------------------------------+
| CHAT ACTION CAPABILITIES (backend/routers/chat.py)                                      |
|                                                                                         |
|  Server Actions (confirm/cancel): log_water, log_meal, adjust_workout                   |
|  Client Actions: preview_workout, save_plan                                             |
|  KHÔNG CÓ ACTION NÀO ĐỂ UPDATE PROFILE HAY LƯU SỞ THÍCH (update_profile)                |
+-----------------------------------------------------------------------------------------+
```

---

## 2. Chi tiết Khảo sát theo 3 Trọng tâm

### 2.1. Workout History Context: Phân biệt Hoàn thành / Bỏ qua & Trạng thái Session

Trong hệ thống backend, việc xây dựng ngữ cảnh lịch sử tập luyện được thực hiện qua hai cơ chế riêng biệt tại [`backend/routers/chat.py`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/backend/routers/chat.py):

#### A. Trạng thái Session (Đang tập vs Đã xong)
1. **Trong `build_workout_grounding_context`** (khi người dùng hỏi về buổi tập hôm nay, ngày cụ thể, hoặc buổi gần nhất):
   - Sử dụng hàm kiểm tra nghiêm ngặt:
     ```python
     def is_session_completed(doc: dict) -> bool:
         fin = doc.get("finished_at") or doc.get("end_time")
         if fin is None:
             return False
         fin_dt = _parse_valid_datetime(fin)
         if fin_dt is None:
             return False
         start = doc.get("started_at") or doc.get("start_time") or doc.get("created_at")
         start_dt = _parse_valid_datetime(start)
         if start_dt and fin_dt < start_dt:
             return False
         return True
     ```
   - **Hệ quả**: Bất kỳ session nào đang diễn ra (`finished_at` là `None` hoặc chưa kết thúc) bị **loại bỏ hoàn toàn** (`completed_sessions = [s for s in all_sessions if is_session_completed(s)]`). AI sẽ phản hồi: *"Chưa có dữ liệu buổi tập hoàn tất được ghi nhận"*.
2. **Trong `_read_latest_workout_context`** (khi đưa ngữ cảnh buổi gần nhất vào câu hỏi chung):
   - Quét tìm timestamp lớn nhất từ danh sách các trường: `start_time`, `started_at`, `created_at`, `date`, `end_time`, `finished_at`.
   - **Hệ quả**: Không kiểm tra `finished_at`, có thể chọn phải session chưa kết thúc, nhưng chuỗi context **không hề có nhãn** để báo cho LLM biết đây là session "đang tập" hay "đã hoàn thành".

#### B. Phân biệt Bài tập Hoàn thành (`completed_sets > 0`) vs Bị bỏ qua (`skipped` / `completed_sets == 0`)
1. **Trong `_read_latest_workout_context` / `_normalize_canonical_logs`**:
   - Từng set được phân loại dựa trên `is_completed` (`isCompleted`):
     - `completion = "completed"` nếu `True`.
     - `completion = "incomplete"` nếu `False`.
   - Chuỗi text đưa vào LLM ghi rõ:
     ```
     Hiệp: X hoàn thành, Y chưa hoàn thành, Z trạng thái chưa rõ.
       + Hiệp 1: 10 reps, mức tạ 20 kg (đã hoàn thành)
       + Hiệp 2: 8 reps, mức tạ 20 kg (chưa hoàn thành)
     ```
   - Tuy nhiên: Nếu người dùng **bỏ qua hoàn toàn một bài tập** mà không lưu log set nào cho bài đó vào `exercise_logs`, hệ thống hoàn toàn không biết bài tập đó từng tồn tại trong kế hoạch để đánh dấu là "bị bỏ qua" (skipped).
2. **Trong `_format_session_card` (Grounding Context)**:
   - Chỉ lọc các set hoàn thành:
     ```python
     completed_sets = []
     for item in raw_logs:
         is_comp = item.get("is_completed") if item.get("is_completed") is not None else item.get("isCompleted", True)
         if is_comp:
             completed_sets.append(item)
     ```
   - **Hệ quả**: Nếu một bài tập có tất cả các set bị bỏ qua (`is_completed == False`), bài tập đó **hoàn toàn biến mất** khỏi danh sách `- Các bài tập đã hoàn thành:`. Context không có dòng nào thông báo về "Các bài tập bị bỏ qua".

---

### 2.2. User Profile Preferences: Trường Lưu trữ Sở thích Dài hạn

Khảo sát schema tại [`backend/app/models/user.py`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/backend/app/models/user.py) và logic update tại [`backend/routers/user.py`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/backend/routers/user.py):

1. **Schema hiện tại**:
   - `UserDB`, `UserProfileInput`, `ProfileUpdateRequest` chỉ có các trường sinh trắc học và mục tiêu cơ bản:
     - `full_name`: Họ tên
     - `age`, `gender`, `height`, `weight`: Thông số thể chất
     - `activity_level`: Mức độ vận động (Sedentary, Light, Moderate, Very Active, Extra Active)
     - `goal`: Mục tiêu thể hình (Lose Weight, Maintain, Gain Muscle, v.v.)
     - `health_stats`: BMR, TDEE, calories, macronutrients
2. **Trường sở thích dài hạn**:
   - **HOÀN TOÀN CHƯA CÓ**: Không có trường nào như `equipment_available`, `available_equipment`, `avoid_exercises`, `preferred_split`, `injuries`, hay `preferences`.
   - File [`backend/app/services/workout_recommendation.py`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/backend/app/services/workout_recommendation.py#L107-L114) ghi nhận tường minh:
     ```python
     "unknown_profile_fields": {
         "training_experience": "not_persisted",
         "available_equipment": "not_persisted",
         "injuries": "not_persisted",
         "schedule": "not_persisted",
     }
     ```
   - Khi người dùng trò chuyện với AI, mọi thông tin về thiết bị tập (ví dụ "tôi chỉ có tạ đơn") hay chấn thương chỉ được parse tạm thời trong lượt chat đó (`turn-level transient`), sau đó bị mất đi chứ không được lưu vào Profile.

---

### 2.3. Feedback Action: Khả năng Cập nhật Profile từ Chat

Khảo sát router [`backend/routers/chat.py`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/backend/routers/chat.py):

1. **Danh sách Action được hỗ trợ hiện tại**:
   - **Server-side pending actions** (yêu cầu gọi `POST /api/chat/actions/confirm` hoặc `POST /api/chat/actions/cancel`):
     - `log_water`: Tự động thêm 250 ml nước vào collection `water`.
     - `log_meal`: Ghi nhận món ăn và calories vào collection `nutrition`.
     - `adjust_workout`: Điều chỉnh `duration_minutes` hoặc `difficulty` của một giáo án tùy chỉnh trong `custom_plans`.
   - **Client-side instant actions** (hiển thị nút tương tác trực tiếp trên giao diện Chat):
     - `preview_workout`: Xem trước danh sách bài tập và bắt đầu buổi tập.
     - `save_plan`: Lưu các bài tập gợi ý thành custom plan mới.
2. **Khả năng cập nhật Profile**:
   - **HOÀN TOÀN CHƯA CÓ**: Không có action `update_profile`, `save_preference`, hay bất kỳ endpoint nào trong Chat cho phép AI đề xuất: *"Bạn có muốn lưu sở thích dùng tạ đơn vào hồ sơ không?"*.
   - Hàm `_process_action_decision` sẽ trả về lỗi `HTTP 400 Unsupported action type` nếu gặp bất kỳ action nào ngoài `("log_water", "log_meal", "adjust_workout")`.

---

## 3. Tổng hợp Nhận định & Khoảng cách (Gap Analysis)

| Hạng mục | Hiện trạng hệ thống | Khoảng cách cần giải quyết (Gap) |
| :--- | :--- | :--- |
| **Trạng thái Session** | Lọc chặt `finished_at != None` trong grounding; bỏ qua session đang tập. | Chưa thể hiện cho LLM biết người dùng đang có một buổi tập dở dang hay vừa hoàn thành. |
| **Bài tập Bỏ qua (Skipped)** | Chỉ hiển thị các bài/hiệp có `is_completed == True`. Các bài không tập bị ẩn hoàn toàn. | AI không biết người dùng đã bỏ qua bài nào để hỏi lý do (ví dụ: đau khớp, thiếu thiết bị). |
| **Sở thích dài hạn** | Không lưu trữ trong DB (`not_persisted`). Chỉ parse tạm theo từng câu hỏi. | Người dùng phải lặp lại thiết bị có sẵn ("tôi tập ở nhà chỉ có dumbell") mỗi khi xin gợi ý. |
| **Feedback Action** | Chỉ hỗ trợ `log_water`, `log_meal`, `adjust_workout`. | Thiếu action cho phép người dùng xác nhận lưu sở thích/thiết bị vào Profile trực tiếp từ Chat. |

---

## 4. Kết luận cho Bước tiếp theo (WC-P05b)

- Để AI Coach có khả năng ghi nhớ sở thích cá nhân hóa thông minh:
  1. Cần bổ sung cấu trúc lưu trữ sở thích (`preferences`: ví dụ `available_equipment`, `avoid_exercises`) vào schema `User` hoặc bảng phụ trợ.
  2. Cần xây dựng cơ chế đề xuất action mới từ Chat (ví dụ: `update_preference`) để người dùng có thể bấm "Lưu vào hồ sơ" khi AI phát hiện sở thích mới trong hội thoại.
  3. Cần làm giàu context lịch sử để phân biệt rõ ràng giữa bài tập đã hoàn thành và bài tập bị bỏ qua.

