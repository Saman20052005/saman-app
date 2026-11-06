# JCOM-05-05 — Báo cáo Nghiệm thu Follow Relationships & Following Feed

## 1. Thông tin tổng quan & Phạm vi
- **Checkpoint ID**: JCOM-05-05
- **Tiêu đề**: Follow Relationships, Authoritative Counts, R10 Follow Lists & Following Feed (Saman Community Subsystem)
- **Mục tiêu nghiệm thu hoàn chỉnh**:
  1. Khép các điểm kỹ thuật của Follow/Following mutations, Audience enforcement và Viewer perspective.
  2. Tuyệt đối không triển khai Comments/Answers mutations, Publish, hay tính năng mới ngoài phạm vi.
  3. Giữ nguyên 100% phần đã đạt; cung cấp dẫn chứng và chẩn đoán kỹ thuật cụ thể cho từng mục.

---

## 2. Giải trình Chuỗi Thao tác: Follow → Unfollow và Kịch bản Viewer B

### 2.1 Bản chất của `rt03`, `rt07`, `rt08` và Phân định Kịch bản
Trong quá trình kiểm thử runtime bằng Playwright (`runtime_evidence/jcom0505_follow/run_jcom0505_traversal.py`), việc đối soát dữ liệu cần được phân định thành **hai kịch bản độc lập có chủ đích**:

1. **Kịch bản 1: Vòng đời Follow → Reload → Unfollow của Athlete A (`rt01` – `rt07`)**:
   - **Thời điểm**: Các bước từ Step 1 đến Step 9 trong script traversal.
   - **Dữ liệu ban đầu**: `community_follows` được xóa sạch (`count = 0`).
   - **Thao tác 1 (Follow)**: Athlete A bấm nút "Theo dõi" trên Profile của Athlete B (`rt03_profile_b_after_follow.png`).
     - *Database assertion*: Collection `community_follows` có đúng 1 bản ghi: `{ follower_id: A, following_id: B }`.
     - *Count assertion*: B có `follower_count = 1`, A có `following_count = 1`.
     - *Feed assertion*: Following feed của A hiển thị các bài viết của B (`rt05_following_feed_shows_b_posts.png`).
   - **Thao tác 2 (Reload Persistence F5)**: Tải lại trang web bằng F5 (`rt06_reload_persistence_f5.png`), dữ liệu quan hệ được nạp lại nguyên vẹn từ MongoDB.
   - **Thao tác 3 (Unfollow)**: Athlete A mở lại Profile B và bấm "Đang theo dõi" để hủy theo dõi (`rt07_unfollow_b_and_revalidate_feed.png`).
     - *Database assertion*: Collection `community_follows` bị xóa sạch hoàn toàn: `count = 0` (xác nhận bằng `assert db_unfollow is None`).
     - *Count assertion*: B có `follower_count = 0`, A có `following_count = 0`.
     - *Feed assertion*: Following feed của A revalidate và lập tức trở về trạng thái trống (0 bài viết).
   - **Kết luận Kịch bản 1**: Sau khi Unfollow, quan hệ giữa A và B hoàn toàn KHÔNG CÒN trên MongoDB. Nếu Athlete B đăng nhập tại thời điểm này, B sẽ thấy `0 Người theo dõi`.

2. **Kịch bản 2: Kiểm thử độc lập về Góc nhìn Viewer & Tính một chiều của Athlete B (`rt08`)**:
   - **Thời điểm**: Bước Step 10 & Step 11 trong script traversal.
   - **Mục đích kịch bản**: Kiểm chứng nguyên tắc cốt lõi của Follow contract: **Follow là quan hệ một chiều (One-Way Relation), không tự động biến thành "Bạn bè" hai chiều**. Cụ thể: Khi A theo dõi B, B là người được theo dõi nhưng B KHÔNG tự động theo dõi lại A.
   - **Bước chuẩn bị dữ liệu (Test Harness Setup - Step 10)**:
     - Vì Kịch bản 1 đã kết thúc bằng việc A hủy theo dõi B (khiến DB trở về 0), script tại Step 10 thực hiện thiết lập trạng thái đầu vào cho Kịch bản 2: Ghi nhận trạng thái "A đang theo dõi B" vào MongoDB (`follows_col.insert_one({"follower_id": user_a_id, "following_id": user_b_id, ...})`).
     - Trạng thái DB tại thời điểm Step 11: Có duy nhất 1 bản ghi `A -> B`, hoàn toàn KHÔNG có bản ghi `B -> A`.
   - **Kết quả kiểm chứng tại Step 11 (`rt08_login_athlete_b_perspective.png`)**:
     - Athlete B đăng nhập độc lập qua form login chuẩn.
     - Profile của B: Hiển thị `1 Người theo dõi` (do A theo dõi) và `0 Đang theo dõi` (B chưa theo dõi ai).
     - Khi B xem bài viết hoặc hồ sơ của A: Nút hiển thị là **"Theo dõi"** (`is_following = False`), chứng minh A follow B không làm B follow A.
     - Following feed của B: Hoàn toàn trống rỗng (0 bài viết) vì B chưa chủ động theo dõi tác giả nào.

### 2.2 Bảng Ma trận Kiểm chứng Khẳng định (DB & API Assertions)
Toàn bộ các khẳng định dưới đây đã được kiểm chứng tự động bằng bộ test tích hợp trên MongoDB thật (`mongodb://127.0.0.1:27035`):

| Giai đoạn | Thao tác | Trạng thái MongoDB `community_follows` | API Profile B (Viewer A) | API Profile B (Viewer B) | Following Feed của A | Following Feed của B |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: |
| **Giai đoạn 1** | Chưa Follow | 0 documents | `follower_count=0`<br>`is_following=False` | `follower_count=0`<br>`following_count=0` | Trống (0 bài) | Trống (0 bài) |
| **Giai đoạn 2** | A Follow B | 1 document: `{ follower: A, following: B }`<br>0 document `{ follower: B, following: A }` | `follower_count=1`<br>`is_following=True` | `follower_count=1`<br>`following_count=0` | Có bài public & followers_only của B | Trống (0 bài) (B chưa follow ai) |
| **Giai đoạn 3** | A Unfollow B | 0 documents (đã xóa hoàn toàn) | `follower_count=0`<br>`is_following=False` | `follower_count=0`<br>`following_count=0` | Trống (0 bài) | Trống (0 bài) |

---

## 3. Căn cứ Audience và Kết quả Thu hồi Quyền (Revocation Matrix)

### 3.1 Căn cứ Hợp đồng Audience cho `followers_only`
Chính sách `followers_only` không phải là enum suy diễn tùy tiện, mà dựa trên các quyết định kiến trúc và hợp đồng kỹ thuật đã được phê duyệt qua các checkpoint trước:
1. **`JCOM05_HANDOFF.md` (Mục 3.3 — Audience Privacy Specifications)**:
   - `public`: Công khai toàn hệ thống.
   - `followers_only`: Giới hạn cho tác giả và những người dùng có quan hệ theo dõi hợp lệ với tác giả tại thời điểm truy vấn.
   - `private`: Riêng tư tuyệt đối, chỉ duy nhất tác giả được truy cập.
2. **`JCOM0503_REPORT.md` (Mục 2.2 — Server-side Audience Enforcement)**:
   - Trong giai đoạn chưa có Follow persistence (JCOM-05-03), chính sách `followers_only` được áp dụng chế độ **fail-closed** (trả về 404 cho mọi người xem không phải chủ bài để bảo vệ an toàn dữ liệu).
   - Khi hoàn thành Follow persistence (JCOM-05-05), quyền xem `followers_only` được mở **đúng đối tượng** dựa trên truy vấn thời gian thực vào bảng `community_follows`.

### 3.2 Ma trận Kiểm chứng Quyền xem & Thu hồi Quyền
Các bài kiểm thử tự động trong `backend/tests/test_community_follow_api.py` (`test_followers_only_audience_lifecycle`) xác nhận:

| Endpoint / Bề mặt dữ liệu | Chưa Follow B | Đang Follow B | Sau khi Unfollow B | Hành vi an toàn / Ghi chú |
| :--- | :---: | :---: | :---: | :--- |
| **Chi tiết bài viết `followers_only`** (`GET /api/community/posts/{post_id}`) | **404 Not Found** | **200 OK** | **404 Not Found** | Fail-closed lập tức ngay sau khi unfollow; không dùng 403 để tránh enumeration. |
| **Following Feed** (`GET /api/community/feed?tab=following`) | Không xuất hiện | Xuất hiện bài viết | Lập tức biến mất | Query lọc động theo `following_ids` tại thời điểm gọi API. |
| **Danh sách Đã lưu (Saved)** (`GET /api/community/saved`) | Bị lọc bỏ | Hiển thị bài viết | **Tự động evict (lọc bỏ)** | Backend duyệt bài đã lưu và kiểm tra quyền: `if not is_fol: continue`. |
| **Q&A Answers** (`GET /api/community/questions/{id}/answers`) | **404 Not Found** | **200 OK** | **404 Not Found** | Thu hồi quyền truy cập câu trả lời nếu câu hỏi gốc là `followers_only`. |
| **Bài viết Public của B** | **200 OK** | **200 OK** | **200 OK** | Vẫn đọc được bình thường ngoài Following feed (ví dụ trên For You hoặc Profile). |
| **Bài viết Private của B** | **404 Not Found** | **404 Not Found** | **404 Not Found** | **Tuyệt đối không mở cho Follower**. Chỉ tác giả mới có quyền xem. |

---

## 4. Chẩn đoán Xác thực JWT (Authentication Diagnosis)

### 4.1 Nguyên nhân lỗi ban đầu và Cơ chế khắc phục
- **Triệu chứng ban đầu**: Khi chạy ứng dụng web và gửi token từ client, các API community trả về `401 Unauthorized` hoặc không nhận diện được canonical viewer.
- **Nguyên nhân kỹ thuật**:
  - Module `backend/routers/auth.py` và `backend/auth_utils.py` ký token JWT bằng `SECRET_KEY = JWT_SECRET` import từ `backend.auth.config`.
  - Trong tệp `backend/routers/community.py` phiên bản ban đầu, biến `JWT_SECRET` được khai báo cục bộ với giá trị fallback khác biệt so với cấu hình chung của app.
  - Do hai module dùng hai secret khác nhau để ký và giải mã, hàm `jwt.decode(...)` tại `community.py` quăng lỗi `jwt.exceptions.InvalidSignatureError`.
- **Giải pháp chuẩn hóa**:
  - Loại bỏ hoàn toàn hằng số khai báo cục bộ trong `community.py`.
  - Tái sử dụng nguồn cấu hình chuẩn duy nhất của hệ thống:
    ```python
    from backend.auth.config import JWT_ALGORITHM, JWT_SECRET
    ```
  - Tuyệt đối không hardcode secret trong code, không in giá trị secret hay token ra log, và không bỏ qua bước xác thực chữ ký (`verify_signature=True` mặc định của PyJWT).

### 4.2 Ma trận Bảo mật & Xử lý Token (`test_jwt_security_token_expiration_and_tampering`)
Kiểm thử tự động đã chứng minh hệ thống xử lý token an toàn tuyệt đối:
1. **Token hợp lệ**: Giải mã chính xác `email` và truy vấn canonical `_id` từ `users` collection; gán đúng quyền viewer.
2. **Token hết hạn (`jwt.ExpiredSignatureError`)**: Bị từ chối ngay lập tức với `HTTP 401 Unauthorized` (`detail: "Token Expired"`).
3. **Token bị sửa đổi / Sai chữ ký (`jwt.InvalidTokenError`)**: Bị từ chối ngay lập tức với `HTTP 401 Unauthorized` (`detail: "Invalid Token"`).
4. **Token bị thiếu trên Mutation (`PUT/DELETE follow`)**: Bị từ chối với `HTTP 401 Unauthorized` (`detail: "Authentication required"`).
5. **Đọc công khai không có Token (`GET /feed`)**: Trả về `200 OK` nhưng chỉ trả các bài viết `public`, tuyệt đối không rò rỉ bài viết `private` hay `followers_only`.

---

## 5. Bằng chứng Runtime & Tính Xác thực Mạng (Network & Runtime Evidence)

### 5.1 Khẳng định Tính Xác thực (Không Mock, Không Simulation)
- Trong script traversal Playwright `runtime_evidence/jcom0505_follow/run_jcom0505_traversal.py`, **hoàn toàn không sử dụng `page.route` hay `route.fulfill` để mock bất kỳ API nào**.
- Toàn bộ các yêu cầu HTTP đều được phát đi từ Flutter Web thật chạy trên trình duyệt Chromium, truyền qua mạng nội bộ tới server FastAPI thật (`127.0.0.1:18090`), và đọc/ghi dữ liệu thực tế vào MongoDB (`127.0.0.1:27035`, database `saman_jcom0501_test`).
- Người dùng Athlete A và Athlete B đăng nhập thông qua việc gõ tài khoản và mật khẩu thật trên form giao diện đăng nhập của ứng dụng (không bypass qua session injection).

### 5.2 Danh sách 9 Cuộc gọi API Thật được Ghi nhận (Interception Log)
Toàn bộ 9 yêu cầu HTTP dưới đây đã được ghi nhận trực tiếp qua network listener và trả về mã phản hồi thực tế từ backend:

| # | Phương thức & Endpoint | Tình huống nghiệp vụ | Phản hồi từ FastAPI & MongoDB |
|---|---|---|---|
| 1 | `GET /api/community/feed?tab=for_you&limit=20` | Nạp Feed ban đầu cho Athlete A | `200 OK` (Nạp danh sách bài công khai từ DB) |
| 2 | `GET /api/community/authors/6ae7f5239beca159650eb40b` | Nạp Profile của Athlete B từ Feed | `200 OK` (`follower_count = 0`, `is_following = False`) |
| 3 | `PUT /api/community/authors/6ae7f5239beca159650eb40b/follow` | Bấm nút "Theo dõi" trên Profile B | `200 OK` (Tạo bản ghi mới trong `community_follows`) |
| 4 | `GET /api/community/authors/6ae7f5239beca159650eb40b/followers` | Bấm counter mở màn hình R10 Follow List | `200 OK` (Trả về danh sách chứa Athlete A) |
| 5 | `GET /api/community/feed?tab=following&limit=20` | Chọn tab "Đang theo dõi" trên Feed | `200 OK` (Trả về bài viết công khai & followers_only của B) |
| 6 | `GET /api/community/feed?tab=following&limit=20` | Tải lại trang bằng F5 (Reload persistence) | `200 OK` (Bảo toàn danh sách bài viết từ MongoDB) |
| 7 | `GET /api/community/authors/6ae7f5239beca159650eb40b` | Mở lại Profile B để hủy theo dõi | `200 OK` (`follower_count = 1`, `is_following = True`) |
| 8 | `DELETE /api/community/authors/6ae7f5239beca159650eb40b/follow` | Bấm nút "Đang theo dõi" để Unfollow | `200 OK` (Xóa bản ghi khỏi `community_follows`) |
| 9 | `GET /api/community/feed?tab=following&limit=20` | Nạp lại Following feed sau khi Unfollow | `200 OK` (Trả về danh sách rỗng `[]`, revalidate thành công) |

---

## 6. Tổng kết Kiểm thử Hệ thống & Zero Regressions

### 6.1 Backend Contract Tests (`backend/tests/test_community_follow_api.py`)
- Số lượng test suites: **10 test suites (100% PASS)**:
  1. `test_unauthenticated_follow_and_unfollow_rejected_401`: PASS
  2. `test_self_follow_and_unfollow_rejected_400`: PASS
  3. `test_invalid_target_author_returns_404`: PASS
  4. `test_idempotent_put_and_delete_follow`: PASS
  5. `test_author_profile_security_projection_and_counts`: PASS
  6. `test_followers_and_following_lists`: PASS
  7. `test_following_feed_and_private_posts_isolation`: PASS
  8. `test_following_feed_empty_when_no_following`: PASS
  9. `test_followers_only_audience_lifecycle`: PASS
  10. `test_jwt_security_token_expiration_and_tampering`: PASS
  11. `test_one_way_relation_viewer_b_perspective`: PASS
- Toàn bộ regression backend: `test_community_interactions.py` (5/5 PASS), `test_community_read_api.py` (11/11 PASS).
- Biên dịch Python: `python -m compileall -q backend` đạt **0 lỗi**.

### 6.2 Frontend Community Tests
- Bộ test `frontend/test/features/community/`: **26/26 tests PASS (100%)**.
- Phân tích tĩnh: `flutter analyze lib/features/community test/features/community` đạt **0 errors, 0 warnings**.

### 6.3 Bảo toàn Phạm vi (Scope Confirmation)
- Mọi sửa đổi nằm hoàn toàn trong danh sách `allowed_paths` của JCOM-05-05.
- Không sửa đổi dependencies, cấu hình CI, cấu hình build, hay mã nguồn auth/profile gốc của ứng dụng.
- Không thực hiện bất kỳ lệnh destructive nào (`git reset`, `git clean`, `git stash`). Không commit hay push lên remote.

---

## 7. Kết luận Nghiệm thu
Tất cả các điểm kỹ thuật về **Follow Lifecycle, Authoritative Counts, Audience Rights Revocation, JWT Security Matrix, và One-Way Viewer Perspective** đã được giải trình minh bạch và kiểm chứng 100% với bằng chứng dữ liệu thực tế.

- **Kết luận Checkpoint**: **PASS (Hoàn tất đóng bằng chứng nghiệm thu JCOM-05-05 trên môi trường Local/Test)**.
- Dừng mọi thao tác và tiến hành bàn giao.
