# WC-P05b: Cập nhật Logic Trích xuất Workout History Context (Report)

- **Ngày thực hiện**: 2026-11-04
- **Trạng thái**: PASS
- **Mục tiêu**: Cập nhật logic định dạng chuỗi (string formatting) ngữ cảnh lịch sử tập luyện trong Backend (`backend/routers/chat.py`), hiển thị rõ nhãn trạng thái session (`Active` vs `Completed`) và liệt kê các bài tập bị bỏ qua (`skipped`) để đưa vào LLM Prompt mà không thay đổi database schema.

---

## 1. Tóm tắt các Thay đổi

### 1.1. Cập nhật Trạng thái Session (`finished_at`)
- **Vị trí**:
  - [`_format_session_card`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/backend/routers/chat.py#L2418-L2505) (dùng cho grounding truy vấn ngày cụ thể / hôm nay / gần nhất).
  - [`_read_latest_workout_context`](file:///d:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/backend/routers/chat.py#L690-L865) (dùng cho ngữ cảnh tập luyện gần nhất trong lượt chat thông thường).
- **Logic triển khai**:
  ```python
  has_finished = bool(session.get("finished_at") or session.get("end_time"))
  status_label = "[Trạng thái: Đã hoàn thành (Completed)]" if has_finished else "[Trạng thái: Đang tập (Active)]"
  ```
- **Kết quả trên chuỗi**: Thêm dòng `- Trạng thái: [Trạng thái: Đang tập (Active)]` hoặc `- Trạng thái: [Trạng thái: Đã hoàn thành (Completed)]`.

### 1.2. Phân loại và Liệt kê Bài tập Bị bỏ qua (`skipped`)
- **Vị trí**: `_format_session_card` và `_read_latest_workout_context`.
- **Logic triển khai**:
  - Gom nhóm các hiệp (`exercise_logs`) theo từng bài tập (`exercise_slug` / `exercise_id` / `name`).
  - Phân loại bài tập thành 2 nhóm:
    1. **"Đã tập"**: Có ít nhất 1 hiệp hoàn thành (`is_completed == True` hoặc `completed_count > 0`).
    2. **"Đã bỏ qua"**: Không có hiệp nào hoàn thành (`completed_count == 0`).
  - Đối với các bài "Đã tập": Hiển thị chi tiết từng hiệp hoàn thành dưới mục `- Các bài tập đã hoàn thành:`.
  - Đối với các bài "Đã bỏ qua": Nếu danh sách không rỗng, bổ sung thêm dòng:
    ```
    - Các bài tập đã bỏ qua: {tên_bài_1}, {tên_bài_2}
    ```

---

## 2. Ví dụ Chuỗi History Context Mới Được Sinh Ra

### Ví dụ 1: Session Đang tập (Active) với bài tập bị bỏ qua
```text
Buổi tập #1: Upper Body Focus
- Trạng thái: [Trạng thái: Đang tập (Active)]
- Ngày: 2026-11-04
- Bắt đầu (giờ VN): 17:00 04/11/2026
- Hoàn thành (giờ VN): Chưa ghi nhận
- Thời lượng: 30 phút
- Tổng khối lượng tạ (volume): 160 kg
- Các bài tập đã hoàn thành:
  * Bài 1: Đẩy ngực với tạ đơn (Dumbbell Bench Press) [Nguồn: generated catalog (canonical_id+exact_slug)]
    + Hiệp 1: 8 reps, mức tạ 20 kg
- Các bài tập đã bỏ qua: Hít đất (Push-Up)
```

### Ví dụ 2: Session Đã hoàn thành (Completed) trong Ngữ cảnh Gần nhất (`_read_latest_workout_context`)
```text
TẬP LUYỆN GẦN NHẤT:
- Trạng thái: [Trạng thái: Đã hoàn thành (Completed)]
- Bản ghi truy vấn: 1 (toàn bộ kết quả; không có limit/phân trang).
- Ngày: 2026-11-02
- Thời lượng: 45 phút
- Tên buổi được lưu: Upper Body Protocol
- Bài tập đã xác minh: Dumbbell Bench Press (canonical ID=db-bench-press; history source=exercise_logs; identity resolution=canonical_id+exact_slug).
  Tên ghi nhận trong history: Recorded Bench Press.
  Catalog tham chiếu (không phải số liệu đã log): nhóm cơ=Chest; mục tiêu=Chest, Pectoralis Major; thiết bị=Dumbbells, Flat bench; độ khó=intermediate; prescription=4 sets x 8-10, nghỉ 90s; repType=reps; CV=False (không có module).
  Hiệp: 1 hoàn thành, 1 chưa hoàn thành, 0 trạng thái chưa rõ.
  - Hiệp 1: đã hoàn thành; 8 reps, 20 kg.
  - Volume các hiệp reps hoàn thành: 160 kg.
```

---

## 3. Kết quả Kiểm thử & Bằng chứng Xác minh

### 3.1. Unit Tests trong `test_ai03_workout_history_context.py`
- Bổ sung test case `test_workout_status_and_skipped_exercises_labels`:
  - Kiểm tra session có `finished_at: None` -> Xuất hiện `[Trạng thái: Đang tập (Active)]` và dòng `Các bài tập đã bỏ qua: Push-Up`.
  - Kiểm tra session có `finished_at: "..."` -> Xuất hiện `[Trạng thái: Đã hoàn thành (Completed)]` và không xuất hiện dòng bài tập bỏ qua.
- **Kết quả**: **14/14 tests PASS**.

### 3.2. Workout Grounding Tests trong `test_chat_workout_grounding.py`
- Chạy toàn bộ suite xác minh tính cách ly owner, metrics, ngày tháng, và catalog resolution:
- **Kết quả**: **13/13 tests PASS**.

Tổng cộng: **27/27 tests PASS** (0 regressions).

### 3.3. Frontend Analyzer
- Chạy `flutter analyze` trên các thành phần UI chat liên quan:
  ```bash
  cd frontend
  flutter analyze --no-fatal-infos --no-fatal-warnings lib/screens/chat_screen.dart lib/screens/chat/widgets/saman_assistant_response.dart
  ```
- **Kết quả**: `No issues found! (ran in 2.0s)`.

---

## 4. Đối chiếu Acceptance Checklist

| Tiêu chí | Trạng thái | Ghi chú |
| :--- | :--- | :--- |
| Chuỗi context sinh ra có chứa nhãn trạng thái session (`Đang tập` / `Đã hoàn thành`) | **PASS** | Đã triển khai và có test xác minh |
| Chuỗi context liệt kê rõ các bài tập bị bỏ qua (`skipped`) | **PASS** | Hiển thị dòng `- Các bài tập đã bỏ qua: ...` khi có bài không hoàn thành set nào |
| Các bài test backend liên quan đến history context đều PASS | **PASS** | 27/27 tests PASS (`test_ai03` và `test_chat_workout_grounding`) |
| Không làm thay đổi database schema | **PASS** | Chỉ sửa đổi logic format chuỗi (string formatting) |
| Phạm vi chỉnh sửa đúng Allowed Paths | **PASS** | Chỉ sửa `backend/routers/chat.py`, `backend/tests/test_ai03_workout_history_context.py`, và tạo file báo cáo |

