# BÁO CÁO HIỆU CHỈNH & PHỤC HỒI NGHIỆM THU JCOM-01B
## RECONCILIATION OF RUNTIME ACCEPTANCE & BASELINE CALIBRATION

- **Mã checkpoint:** JCOM-01B (Hiệu chỉnh kết luận nghiệm thu JCOM-01A & Rà soát tính trung thực)
- **Trạng thái Checkpoint JCOM-01:** **PARTIAL**
  - *Frontend Implementation, Fake Repository, Unit & Widget Tests:* **PASS (100%)**
  - *Live Backend Runtime Traversal qua MainScreen:* **BLOCKED (Do hợp đồng Profile của remote backend HuggingFace)**
- **Thời gian lập báo cáo:** 01/11/2026
- **Kỹ sư thực thi:** Senior Flutter Engineer

---

## 1. MỤC ĐÍCH HIỆU CHỈNH CỦA JCOM-01B

Trong báo cáo JCOM-01A trước đó, tiêu đề trạng thái ghi nhận **PASS** cho toàn bộ checkpoint. Tuy nhiên, qua đối chiếu bằng chứng kỹ thuật khách quan và các quy định nghiêm ngặt của `AGENTS.md`:
1. Quá trình kiểm tra runtime trên ứng dụng web chạy thực tế (CDP port 9222 qua browser thật) đã bị chặn tại cổng `MainScreen` do remote backend HuggingFace (`GET /api/user/profile`) không trả về trường `user_id`.
2. Theo `AGENTS.md` và quy tắc an toàn kho mã, Kỹ sư KHÔNG được phép sửa backend, KHÔNG được sửa module `profile` ngoài allowlist, và KHÔNG được bypass cơ chế xác thực để tự nhận PASS hoàn toàn.
3. Vì vậy, kết luận nghiệm thu runtime trên môi trường live backend phải được định danh chính xác là **BLOCKED**, kéo theo trạng thái tổng thể của JCOM-01 là **PARTIAL**.
4. Báo cáo này minh định rõ ràng nguồn gốc bằng chứng: phân biệt rạch ròi giữa **Ảnh chụp trình duyệt thật (Runtime CDP Captures)** và **Ảnh kết xuất kiểm thử có kiểm soát (Widget-Test Renders)**.

---

## 2. PHÂN LOẠI & MINH BẠCH BẰNG CHỨNG HÌNH ẢNH

Nhóm kỹ sư minh định hai nhóm bằng chứng thu thập được như sau:

### A. Nhóm ảnh Runtime CDP thật (Browser Captures trên cổng 9222)
Được chụp thông qua tiến trình Microsoft Edge / Chrome kết nối qua giao thức Chrome DevTools Protocol (CDP) tại `http://127.0.0.1:8089` (bản build production web):
- `test_r01_runtime.png`: Màn hình khởi động ứng dụng chuyển vào Login khi chưa có phiên.
- `login_filled.png`: Form đăng nhập với email test athlete.
- `login_correctly_filled.png`: Form đăng nhập đã nhập đầy đủ mật khẩu chuẩn bị gửi request.
- `01_home_runtime_live.png`: Màn hình thông báo lỗi hồ sơ sức khỏe (`MainScreen` ném `FormatException` do profile response thiếu `user_id`).

### B. Nhóm ảnh Widget-Test Render thật (2.0x DPI trong môi trường Riverpod có kiểm soát)
Gồm 21 ảnh chụp màn hình độ nét cao được tạo bởi `frontend/test/features/journal/journal_ui_render_test.dart`:
- Khảo sát toàn diện R01 Journal Discover: Hero Banner, Topic Chips, Reading Progress Card, Advice Section, Library Entry Cards, Community Doorway Card.
- Khảo sát R02 Journal Search: Empty query, populated search results (Articles, Exercises, Foods, Recipes), active filter tabs, network error state with Retry.
- Khảo sát Responsive & Accessibility: Màn hình hẹp 360px, phóng to chữ 200% (TextScaler 2.0).
- Khảo sát Đa ngôn ngữ (i18n): Giao diện Tiếng Anh (English Locale).
- Chuỗi điều hướng 5 bước: Chạm card Home Saman Picks -> Mở R01 -> Chạm search bar -> Mở R02 -> Bấm back quay về R01 -> Bấm back quay về Home.

---

## 3. NGUYÊN NHÂN GỐC CỦA RÀO CẢN RUNTIME PROFILE (ROOT-CAUSE TRACING)

1. **FACT (Sự thật khách quan):**
   - Tài khoản test đăng nhập thành công vào endpoint auth:
     `POST https://nguyenvananan2005-saman-backend.hf.space/api/auth/login` -> Trả về `200 OK` kèm `access_token` hợp lệ.
   - Ứng dụng lưu token vào `FlutterSecureStorageWeb` và điều hướng đến route `AppRoutes.main` (`MainScreen`).
   - `MainScreen` kích hoạt `profileProvider`, gửi request:
     `GET https://nguyenvananan2005-saman-backend.hf.space/api/user/profile`.
2. **OBSERVATION (Quan sát phản hồi):**
   - Backend HuggingFace phản hồi `HTTP 200 OK` với body:
     ```json
     {"email": "test_athlete_jcom01@example.com", "profile": {...}, "health_stats": {...}}
     ```
     Phản hồi hoàn toàn thiếu trường `user_id` (hoặc `userId`) ở root level.
3. **HYPOTHESIS & TRACE:**
   - Trong `frontend/lib/features/profile/data/datasources/profile_remote_data_source.dart`:
     ```dart
     final rawUserId = data['user_id'] ?? data['userId'];
     if (rawUserId == null) {
       throw const FormatException('Missing or invalid user_id in profile response');
     }
     ```
   - Do `rawUserId == null`, mã nguồn ném ngoại lệ `FormatException`. `MainScreen` bắt ngoại lệ và render màn hình lỗi "Không thể tải hồ sơ sức khỏe", chặn người dùng nhìn thấy Home và Saman Picks Carousel trên môi trường web live.
4. **CONCLUSION & SAFE BEHAVIOR:**
   - Để mở khóa `MainScreen` trên môi trường live backend, cần cập nhật backend HuggingFace trả đúng `user_id` hoặc cập nhật `ProfileRemoteDataSourceImpl`.
   - Cả hai thao tác trên đều nằm NGOÀI allowlist của JCOM-01 (`backend/` và `features/profile/` bị đóng băng nghiêm ngặt).
   - Theo Điều 1 & Điều 6 của `AGENTS.md`: Kỹ sư **DỪNG LẠI VÀ BÁO CÁO RÀO CẢN (STOP AND REPORT BLOCKER)**, không được lén lút sửa file ngoài phạm vi.
   - Do đó, phần kiểm thử thao tác qua `MainScreen` trên live backend ghi nhận **BLOCKED**.

---

## 4. TỔNG HỢP KIỂM THỬ HỒI QUY & BASELINE

- **Static Analyzer (`flutter analyze --no-fatal-infos --no-fatal-warnings`):**
  - Kết quả: **PASS** (0 lỗi compile, 0 lỗi cảnh báo mới).
  - Có 74 issues cảnh báo là pre-existing baseline đã tồn tại từ trước phiên làm việc.
- **Journal Test Suite:**
  - `test/features/journal/journal_discover_flow_test.dart`
  - `test/features/journal/journal_search_test.dart`
  - `test/features/journal/journal_ui_render_test.dart`
  - Kết quả: **28/28 tests PASS (100%)**.
- **Workout Regression Test Suite:**
  - `test/workout_session_flow_test.dart`
  - Kết quả: **63/63 tests PASS (100%)**.

---

## 5. BẢNG HIỆU CHỈNH TRẠNG THÁI CUỐI CÙNG CHO JCOM-01

| Hạng mục kiểm tra | Tiêu chí | Kết quả JCOM-01A cũ | Hiệu chỉnh JCOM-01B | Ghi chú kỹ thuật |
|---|---|---|---|---|
| Màn hình R01 Discover | Chuẩn thiết kế Obsidian Kinetic | PASS | **PASS** | 21 widget render captures |
| Màn hình R02 Search | Tìm kiếm đa danh mục, debounce, retry | PASS | **PASS** | Đã bao phủ ca lỗi mạng |
| Điểm vào Home Saman Picks | Nối route `/journal` | PASS | **PASS** | Khớp route và chuyển cảnh |
| Dữ liệu Fake Data Honesty | Gắn nhãn DỮ LIỆU MẪU, nút + không ghi meal | PASS | **PASS** | Không ghi persistent state |
| Runtime App Traversal qua Live Backend | Traversal Home -> R01 -> R02 trên live web | PASS (Tự nhận) | **BLOCKED** | Bị chặn bởi Profile backend contract |
| **KẾT LUẬN TOÀN BỘ JCOM-01** | | **PASS** | **PARTIAL** | Phục vụ tiếp nối an toàn sang JCOM-02 |
