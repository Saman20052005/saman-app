# BÁO CÁO NGHIỆM THU JCOM-05-03 — COMMUNITY REMOTE READ & AUDIENCE ENFORCEMENT

## 1. Thông Tin Tổng Quan
- **Mã Checkpoint**: `JCOM-05-03`
- **Mục tiêu hoàn thành**:
  1. Triển khai API đọc Community và kết nối frontend trên môi trường local/test độc lập:
     - Feed R03 (`GET /api/community/feed`).
     - Post Detail R05 (`GET /api/community/posts/{post_id}`).
     - Question Detail R15 (`GET /api/community/questions/{question_id}/answers` và `/api/community/posts/{post_id}/answers`).
  2. Thực thi chính sách Audience Enforcement nghiêm ngặt trên backend:
     - Danh tính canonical trích xuất từ JWT Bearer token trên máy chủ (`get_optional_current_user`).
     - Bài viết `public` hiển thị công khai cho mọi đối tượng (kể cả viewer chưa đăng nhập).
     - Bài viết `private` chỉ chủ sở hữu (`author_id == current_user["_id"]`) mới xem được trên Feed và Detail; người dùng khác khi yêu cầu Detail nhận HTTP 404 (Fail-closed để tránh lộ sự tồn tại của tài nguyên riêng tư).
     - Bài viết bị xóa (`is_deleted: true`) hoặc chưa xuất bản không hiển thị công khai (Detail nhận 404).
     - Tab `following` và bài viết `followers_only`: Fail-closed (do chưa triển khai quan hệ followers trong checkpoint này, tab `following` trả về mảng rỗng `[]` trung thực).
     - Public author projection: Tuyệt đối không serialize User document nhạy cảm (không lộ email, password hash, health stats, tokens).
     - Attachments: Chỉ đọc snapshot đính kèm trong bài viết theo cờ riêng tư (`include_load_or_macros`, `include_duration`, `include_exercises_or_foods`), không truy ngược database riêng của tác giả.
  3. Kết nối Frontend Remote Repository & Xử lý Mutations Chưa Có Backend:
     - Triển khai `CommunityRemoteDatasourceImpl` và `CommunityRepositoryImpl` hỗ trợ chuyển đổi Fake/Remote qua Riverpod DI (`useRemoteCommunityProvider`).
     - Tuyệt đối không thực hiện fake mutation lên bài viết remote; các hành động tương tác (Like, Save, Follow, Comment, Answer Upvote, Publish) hiển thị thông báo giới hạn rõ ràng: *"Tính năng tương tác đang hoàn thiện trên máy chủ."*
     - Màn hình R03 và R05 hiển thị banner trung thực: *"Saman Community (Chế độ máy chủ) • Tính năng tương tác chưa kích hoạt"*.
     - Xử lý trạng thái lỗi mạng và nút "Thử lại" đầy đủ trên R03, R05, R15.
  4. Nghiệm thu tự động Playwright trên ứng dụng web chính (release build với `--dart-define=USE_REMOTE_COMMUNITY=true`) kết nối backend FastAPI/MongoDB test độc lập. Thu thập đầy đủ 9 ảnh chụp màn hình chứng cứ.

---

## 2. Kết Quả Kiểm Thử Tự Động (100% Pass)

| Suite | Phạm vi | Số test | Kết quả | Ghi chú |
| :--- | :--- | :--- | :--- | :--- |
| **Backend Community Read API** | `backend/tests/test_community_read_api.py` | **11 / 11** | **PASS** | Kiểm tra audience enforcement, anonymous viewer, owner private view, non-owner 404, following tab empty, projection security, cursor pagination |
| **Frontend Community Suite** | `frontend/test/features/community/` | **81 / 81** | **PASS** | Bao gồm 6 test mới trong `community_remote_read_test.dart` (remote datasource, error propagation, mutation rejection, R03/R15 render & retry) + 75 tests hiện hữu |
| **Frontend Journal Suite** | `frontend/test/features/journal/` | **36 / 36** | **PASS** | Bảo toàn 100% các luồng Journal từ checkpoint JCOM-05-02 |
| **Tổng kiểm thử Journal & Community** | — | **117 / 117** | **PASS** | 0 regressions introduced |
| **Dart Analyzer** | `lib/features/community` + `test/features/community` | — | **0 errors, 0 warnings** | Tuân thủ tuyệt đối quy tắc sạch mã nguồn |

---

## 3. Danh Sách Tệp Thay Đổi & Tuân Thủ Phạm Vi (Allowed Paths)

| File | Hành động | Mục đích |
| :--- | :--- | :--- |
| `backend/app/models/community.py` | Tạo mới | Pydantic models cho Community Read API |
| `backend/routers/community.py` | Tạo mới | FastAPI router cho Feed R03, Detail R05, Answers R15 với Audience Enforcement |
| `backend/routers/__init__.py` | Sửa đổi | Export `community_router` |
| `backend/main.py` | Sửa đổi | Include `community_router` vào FastAPI app |
| `backend/tests/test_community_read_api.py` | Tạo mới | 11 unit & contract tests cho Community backend |
| `frontend/lib/features/community/data/datasources/community_remote_datasource.dart` | Tạo mới | Remote datasource gọi REST API Community qua Dio |
| `frontend/lib/features/community/data/repositories/community_repository_impl.dart` | Sửa đổi | Triển khai `CommunityRepository` hỗ trợ Remote & Fake qua DI, chặn fake mutations |
| `frontend/lib/features/community/presentation/providers/community_providers.dart` | Sửa đổi | Khai báo `useRemoteCommunityProvider`, remote DI wiring, error/retry handling |
| `frontend/lib/features/community/presentation/screens/community_feed_screen.dart` | Sửa đổi | QA card routing sang R15, preview banner mode máy chủ, chặn fake mutation |
| `frontend/lib/features/community/presentation/screens/community_post_detail_screen.dart` | Sửa đổi | Preview banner mode máy chủ, chặn fake mutation |
| `frontend/lib/features/community/presentation/screens/qa/community_question_detail_screen.dart` | Sửa đổi | Remote answers loading, error state với "Thử lại", chặn fake upvote |
| `frontend/test/features/community/community_remote_read_test.dart` | Tạo mới | 6 unit & widget tests cho Community Remote Read |
| `docs/jcom0503_community_remote_read_acceptance/JCOM0503_SCOPE.md` | Tạo mới | Tài liệu ranh giới phạm vi được duyệt |
| `docs/jcom0503_community_remote_read_acceptance/JCOM0503_REPORT.md` | Tạo mới | Báo cáo nghiệm thu hoàn tất |
| `runtime_evidence/jcom0503_community_remote/*` | Tạo mới | Scripts seed dữ liệu test và Playwright crawl runtime |

---

## 4. Ma Trận Quyền Xem (Audience Permission Matrix)

| Loại bài viết / Đối tượng | Viewer Chưa Đăng Nhập | Athlete B (Người dùng khác) | Athlete A (Chủ sở hữu) | Hành vi Backend |
| :--- | :--- | :--- | :--- | :--- |
| **Bài viết Công khai (`public`)** | Xem được | Xem được | Xem được | Trả về trong Feed và Detail 200 OK |
| **Bài viết Riêng tư (`private` của A)** | **Ẩn** (Không thấy) | **Ẩn** (Không thấy) | **Xem được** | Feed: Chỉ xuất hiện với chủ bài.<br>Detail: Non-owner nhận **404 Not Found** (Fail-closed). |
| **Bài viết Đang theo dõi (`followers_only`)** | **Ẩn** | **Ẩn** (Do chưa có graph) | **Xem được** | Fail-closed: Chỉ tác giả xem được do chưa kích hoạt mạng lưới theo dõi. |
| **Bài viết Bị xóa (`is_deleted: true`)** | **Ẩn** | **Ẩn** | **Ẩn** | Không xuất hiện trong Feed; Detail trả về **404 Not Found**. |
| **Tab Đang theo dõi (`tab=following`)** | Rỗng (`[]`) | Rỗng (`[]`) | Rỗng (`[]`) | Trả về danh sách rỗng minh bạch, không giả lập dữ liệu theo dõi. |

---

## 5. Bảng Đối Chiếu Trường Hồ Sơ Công Khai (Public Author Projection)

| Trường trong MongoDB User Document | Được Phép Xuất Sang Community? | Lý Do Kỹ Thuật & Quyền Riêng Tư |
| :--- | :--- | :--- |
| `_id` / `id` | **CÓ** (Chuỗi) | Định danh tác giả công khai |
| `full_name` / `name` | **CÓ** (Chuỗi) | Tên hiển thị công khai trên bài viết |
| `profile.avatar_url` | **CÓ** (Chuỗi / Null) | Ảnh đại diện công khai |
| `profile.title` | **CÓ** (Chuỗi / Null) | Danh hiệu vận động viên (VD: Kip 2 Athlete) |
| `is_verified` | **CÓ** (Boolean) | Huy hiệu xác thực |
| `follower_count` | **CÓ** (Integer) | Số lượng người theo dõi công khai |
| `email` | **TUYỆT ĐỐI KHÔNG** | Thông tin cá nhân nhạy cảm, chặn triệt để |
| `password` / `hashed_password` | **TUYỆT ĐỐI KHÔNG** | Thông tin bảo mật cốt lõi, không bao giờ serialize |
| `health_stats` / `medical_conditions` | **TUYỆT ĐỐI KHÔNG** | Dữ liệu y tế và sức khỏe cá nhân, bảo vệ theo GDPR/HIPAA |
| `auth_provider` / `google_id` | **TUYỆT ĐỐI KHÔNG** | Thông tin định danh nhà cung cấp |

---

## 6. Ma Trận Khả Năng Thực Tế (Capability Matrix)

| Khả năng | Trạng thái hiện tại | Phân loại dữ liệu | Hành vi người dùng trên giao diện |
| :--- | :--- | :--- | :--- |
| **Community Feed (R03)** | **Live Remote** | REST API (`/api/community/feed`) | Tải bài viết thật từ backend; hỗ trợ phân trang cursor; lọc tab QA; tab Following rỗng chuẩn. |
| **Post Detail (R05)** | **Live Remote** | REST API (`/api/community/posts/{id}`) | Tải chi tiết bài viết thật; kiểm soát quyền riêng tư (404 nếu không có quyền); hiển thị bình luận công khai. |
| **Question Detail (R15)** | **Live Remote** | REST API (`/api/community/questions/{id}/answers`) | Tải câu hỏi và danh sách câu trả lời từ cộng đồng; hiển thị huy hiệu câu trả lời hữu ích nhất. |
| **Tương tác Like / Bookmark / Follow** | **Chưa có Backend** | Bị từ chối an toàn | Nhấn nút hiển thị thông báo SnackBar trung thực; **0 fake success**. |
| **Gửi Bình luận / Trả lời Q&A** | **Chưa có Backend** | Bị từ chối an toàn | Bấm gửi hiển thị thông báo tính năng đang hoàn thiện; không ghi đè dữ liệu cục bộ. |
| **Đăng bài (R06D) / Soạn câu hỏi (R08)** | **Preview Mode** | Bản xem trước | Chỉ hoạt động ở chế độ thử nghiệm cục bộ; không xuất bản lên máy chủ remote. |
| **Khám phá (R04) / Hồ sơ (R09) / Thông báo (R11)** | **Preview Mode** | Fake Datasource | Thể hiện rõ chế độ xem trước giao diện. |

---

## 7. Danh Mục Bằng Chứng Chụp Màn Hình Runtime

Tất cả ảnh chụp đã được tự động lưu trữ tại `docs/jcom0503_community_remote_read_acceptance/screenshots/`:

| Tên File | Mô tả chứng cứ | Kết quả |
| :--- | :--- | :--- |
| `rt01_login_home.png` | Đăng nhập tài khoản Athlete A, màn hình Home sẵn sàng | Đạt |
| `rt02_community_feed_remote_user_a.png` | R03 Community Feed hiển thị bài viết Remote; Athlete A thấy bài công khai và bài riêng tư của A | Đạt |
| `rt03_post_detail_allowed.png` | Mở chi tiết bài viết từ R03 sang R05, dữ liệu đính kèm Saman Kinetic hiển thị đầy đủ | Đạt |
| `rt04_community_feed_qa_tab.png` | Chuyển sang tab "Hỏi đáp" trên R03, chỉ hiển thị các câu hỏi thảo luận Q&A | Đạt |
| `rt05_question_detail_remote.png` | Nhấn vào thẻ câu hỏi, chuyển hướng sang R15 Question Detail, tải câu trả lời live từ API | Đạt |
| `rt06_community_following_empty_state.png` | Chuyển sang tab "Đang theo dõi" trên R03, hiển thị trạng thái rỗng minh bạch (Fail-closed) | Đạt |
| `rt07_community_feed_user_b.png` | Đăng nhập phiên Athlete B: Bảng tin hiển thị bài riêng tư của B, KHÔNG hiển thị bài riêng tư của A | Đạt |
| `rt08_community_feed_error_state.png` | Mô phỏng lỗi HTTP 500 mạng: Giao diện hiển thị thông báo lỗi và nút "Thử lại" | Đạt |
| `rt09_community_feed_retry_recovered.png` | Nhấn "Thử lại": Khôi phục kết nối thành công, hiển thị lại bài viết từ máy chủ | Đạt |
| **Audience 404 Test** | Athlete B yêu cầu xem bài riêng tư của Athlete A nhận HTTP 404 Not Found từ backend | Đạt (Verified) |

---

## 8. Kết Luận & Đề Xuất
- **Trạng thái**: **HOÀN THÀNH TOÀN DIỆN (PASS)**.
- **Tuân thủ AGENTS.md**:
  - Không có commit, push, hay merge tự động.
  - Không tác động production hay môi trường HuggingFace.
  - Toàn bộ tiến trình nền kiểm thử đã được đóng an toàn.

