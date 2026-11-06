# BÁO CÁO NGHIỆM THU JCOM-05-02 — JOURNAL REMOTE READ & COMMUNITY ENTRY

## 1. Thông Tin Tổng Quan
- **Mã Checkpoint**: `JCOM-05-02`
- **Mục tiêu hoàn thành**:
  1. Khép đường vào Community từ Journal trên app chính (`JournalCommunityDoorwayCard` R01 -> `AppRoutes.communityFeed` R03, có throttle/double-tap protection; Back từ R03 quay về R01; Back từ R01 quay về Home).
  2. Triển khai Journal Public Read API backend theo chuẩn FastAPI/MongoDB (`/api/journal/topics`, `/api/journal/featured`, `/api/journal/articles`, `/api/journal/articles/{article_id}`, `/api/journal/search`). Search tái sử dụng catalog Workout (`exercises_collection`) và Nutrition (`foods_collection`).
  3. Kết nối frontend qua Remote Datasource (`JournalRemoteDatasourceImpl`) và Repository (`JournalRepositoryImpl`), cho phép chọn Fake hoặc Remote qua DI. Khi Remote lỗi, hiển thị error/retry thật, giữ trạng thái người dùng, KHÔNG tự động fallback ngầm sang Fake fixture.
  4. Thực thi kiểm thử tự động, crawl test app release build trên backend/database test độc lập, thu thập đầy đủ 11 ảnh chụp màn hình chứng cứ và kiểm tra fault injection/retry recovery.
- **Môi trường Test**:
  - MongoDB Test Daemon: `127.0.0.1:27035` (`saman_jcom0501_test`)
  - FastAPI Test Instance: `http://127.0.0.1:18090`
  - Flutter Web App: `http://127.0.0.1:8095` (Build release từ `lib/main.dart` với `--dart-define=USE_REMOTE_JOURNAL=true`)

---

## 2. Kết Quả Kiểm Thử Tự Động (100% Pass)

| Suite | Phạm vi | Số test | Kết quả | Ghi chú |
| :--- | :--- | :--- | :--- | :--- |
| **Backend Unit & Contract** | `backend/tests/test_journal_api.py` | **12 / 12** | **PASS** | Kiểm tra toàn bộ 5 endpoints, query validation, cursor pagination, search aggregation, advice tips, privacy invariant |
| **Frontend Journal Unit & Widget** | `frontend/test/features/journal/` | **36 / 36** | **PASS** | Bao gồm 8 test mới trong `journal_remote_and_doorway_test.dart` (doorway nav, 400ms throttle, remote datasource error propagation) |
| **Frontend Community Suite** | `frontend/test/features/community/` | **75 / 75** | **PASS** | Bảo toàn 100% các màn hình R03 - R15, composer, draft, profile, saved |
| **Dart Analyzer** | `lib/features/journal` + `test/features/journal` | — | **0 errors, 0 warnings** | Tuân thủ tuyệt đối quy định không để lại warning |

---

## 3. Danh Sách Tệp Thay Đổi & Tuân Thủ Phạm Vi (Allowed Paths)

Mọi thay đổi đều nằm trong danh sách đã khai báo tại `docs/jcom0502_journal_remote_acceptance/JCOM0502_SCOPE.md`:

| File | Hành động | Mục đích |
| :--- | :--- | :--- |
| `backend/app/models/journal.py` | Tạo mới | Pydantic models cho Journal API request/response |
| `backend/routers/journal.py` | Tạo mới | Router FastAPI triển khai 5 endpoint đọc công khai |
| `backend/routers/__init__.py` | Sửa đổi | Export `journal_router` theo convention |
| `backend/main.py` | Sửa đổi | Include `journal_router` vào FastAPI app |
| `backend/tests/test_journal_api.py` | Tạo mới | Unit/contract test suite cho Journal backend |
| `frontend/lib/features/journal/data/datasources/journal_remote_datasource.dart` | Tạo mới | Remote datasource gọi REST API Journal qua Dio |
| `frontend/lib/features/journal/data/repositories/journal_repository_impl.dart` | Tạo mới | Triển khai `JournalRepository` hỗ trợ remote & fake qua DI |
| `frontend/lib/features/journal/presentation/providers/journal_providers.dart` | Cập nhật | Khai báo `useRemoteJournalProvider`, `journalRemoteDatasourceProvider` |
| `frontend/lib/features/journal/presentation/widgets/journal_community_doorway_card.dart` | Cập nhật | Điều hướng R01 -> R03 với throttle 400ms |
| `frontend/test/features/journal/journal_remote_and_doorway_test.dart` | Tạo mới | Widget & unit tests cho doorway navigation, throttling và remote datasource |
| `frontend/test/features/journal/journal_discover_flow_test.dart` | Cập nhật | Cập nhật test doorway card theo route Community thật |
| `frontend/test/features/journal/journal_ui_render_test.dart` | Cập nhật | Cập nhật render test phù hợp doorway navigation |
| `docs/jcom0502_journal_remote_acceptance/JCOM0502_SCOPE.md` | Tạo mới | Tài liệu ranh giới phạm vi được duyệt |
| `docs/jcom0502_journal_remote_acceptance/JCOM0502_REPORT.md` | Tạo mới | Báo cáo nghiệm thu hoàn tất |
| `runtime_evidence/jcom0502_journal_remote/*` | Tạo mới | Script chạy và bằng chứng crawl runtime Playwright |

---

## 4. Bảng Đối Chiếu Hợp Đồng API Journal (Contract Map)

| Endpoint Backend | HTTP Method | Frontend Caller / Provider | Input Parameters | Dữ liệu Nguồn | Quy tắc An toàn & Quyền riêng tư |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `/api/journal/topics` | `GET` | `JournalRepository.getTopics()` | Không | Cấu hình hằng số tĩnh (`all`, `workout`, `nutrition`, `recovery`, `habits`) | Public, không yêu cầu auth |
| `/api/journal/featured` | `GET` | `featuredArticleProvider` | Không | `journal_articles` (`is_featured: true`) | Public, trả `null` nếu database trống |
| `/api/journal/articles` | `GET` | `articlesByTopicProvider` | `topic`, `cursor`, `limit` (max 50) | `journal_articles` | Lọc theo topic; cursor ổn định `created_at` DESC + `_id` DESC; validate topic hợp lệ |
| `/api/journal/articles/{article_id}` | `GET` | `JournalRepository.getArticleById()` | `article_id` | `journal_articles` (`_id`) | Trả 404 chuẩn nếu không tồn tại |
| `/api/journal/search` | `GET` | `journalSearchNotifierProvider` | `q` (max 100), `category`, `cursor`, `limit` | `journal_articles`, `exercises_collection`, `foods_collection`, `recipes_collection` | Tái sử dụng catalog Workout và Nutrition thật; category không có nguồn trả empty theo contract; thêm tips lời khuyên ngữ cảnh; public, không lộ nhật ký cá nhân |

---

## 5. Hành Vi Doorway Community (R01 -> R03 -> Back)

1. **Điều hướng trực tiếp**:
   - Khi người dùng nhấn vào `JournalCommunityDoorwayCard` tại màn hình R01 (Journal Discover), ứng dụng gọi `Navigator.of(context).pushNamed(AppRoutes.communityFeed)`.
   - Màn hình R03 (Community Feed) hiển thị với banner thông báo minh bạch: *"Saman Community • Bản xem trước giao diện • Dữ liệu mẫu thử nghiệm"*.
2. **Double-tap Throttling**:
   - `JournalCommunityDoorwayCard` sở hữu biến cờ `_isNavigating` với thời gian throttle 400ms. Các thao tác tap lặp lại liên tục trong 400ms bị chặn hoàn toàn, đảm bảo chỉ có duy nhất 1 route `AppRoutes.communityFeed` được đẩy lên stack.
3. **Back Stack Chuẩn**:
   - Nhấn nút Back trên AppBar của R03 -> Trở về chính xác màn hình R01 (Journal Discover).
   - Nhấn nút Back trên AppBar của R01 -> Trở về chính xác màn hình Home.

---

## 6. Mô Phỏng Lỗi & Cơ Chế Khôi Phục (Fault Injection & Recovery)

- **Nguyên tắc**: Khi bật chế độ `USE_REMOTE_JOURNAL=true`, nếu backend trả về HTTP 500 hoặc mất kết nối mạng, ứng dụng **tuyệt đối không** âm thầm tráo đổi sang fake fixture.
- **Thực nghiệm**:
  1. Script test can thiệp route mạng trả về HTTP 500 cho API `/api/journal/featured`.
  2. Màn hình R01 hiển thị State Lỗi chuẩn: *"Không thể tải bài viết nổi bật. Vui lòng kiểm tra kết nối."* cùng nút bấm **"Thử lại"**.
  3. Bỏ chặn lỗi mạng và nhấn nút **"Thử lại"**.
  4. Ứng dụng thực hiện re-fetch thành công từ backend live (`http://127.0.0.1:18090/api/journal/featured`), phục hồi đầy đủ nội dung bài viết nổi bật mà không cần reload trang hoặc mất context.

---

## 7. Danh Mục Bằng Chứng Chụp Màn Hình Runtime

Tất cả ảnh chụp đã được tự động ghi lại tại `docs/jcom0502_journal_remote_acceptance/screenshots/`:

| Tên File | Mô tả chứng cứ | Trạng thái |
| :--- | :--- | :--- |
| `rt01_login_home.png` | Đăng nhập tài khoản test athlete, màn hình Home sẵn sàng | Đạt |
| `rt02_journal_r01_remote.png` | Vào R01 Journal Discover, tải thành công bài viết Featured & List từ Remote API | Đạt |
| `rt03_journal_search_r02_remote.png` | Vào R02 Journal Search, kết quả tìm kiếm 'protein' trả về từ database live | Đạt |
| `rt04_journal_search_filter_category.png` | Lọc kết quả tìm kiếm theo danh mục (Bài tập/Exercises) từ catalog backend | Đạt |
| `rt05_back_to_r01.png` | Nhấn Back từ R02 quay lại an toàn R01 Journal Discover | Đạt |
| `rt06_community_doorway_visible.png` | Cuộn xuống chân trang R01, hiển thị rõ `JournalCommunityDoorwayCard` | Đạt |
| `rt07_community_feed_from_doorway.png` | Nhấn Doorway Card, điều hướng trực tiếp sang R03 Community Feed (hiển thị preview banner) | Đạt |
| `rt08_back_from_community_to_r01.png` | Nhấn Back trên R03, quay trở về an toàn R01 Journal Discover | Đạt |
| `rt09_back_from_journal_to_home.png` | Nhấn Back trên R01, quay trở về an toàn Home Screen | Đạt |
| `rt10_journal_error_state.png` | Fault injection: API trả 500, giao diện hiển thị thông báo lỗi và nút "Thử lại" | Đạt |
| `rt11_journal_retry_recovered.png` | Nhấn "Thử lại", ứng dụng gọi lại API và hiển thị bài viết thành công | Đạt |

---

## 8. Tuyên Bố Trạng Thái Dữ Liệu & Ranh Giới Kiến Trúc

1. **Dữ liệu tổng hợp (Synthetic Data Provenance)**:
   - Toàn bộ bài viết Journal phục vụ thử nghiệm được gắn nhãn `provenance: "synthetic_test_data"`.
   - Không chứa bất kỳ thông tin cá nhân hay dữ liệu nhạy cảm nào.
2. **Community Backend**:
   - Tính năng Community ở checkpoint này **vẫn sử dụng Fake Repository** và hiển thị banner xem trước giao diện.
   - Chưa mở backend live hay triển khai media upload cho Community trong checkpoint này.
3. **Triển khai Remote (HuggingFace)**:
   - Checkpoint này hoàn toàn thực thi và nghiệm thu trên môi trường local test độc lập đã được chứng minh an toàn.
   - Không kết luận hoặc giả định môi trường HuggingFace đã sửa drift khi chưa được cấp phép deploy.

---

## 9. Kết Luận & Đề Xuất Bước Tiếp Theo
- **Trạng thái**: **HOÀN THÀNH TOÀN DIỆN (PASS)**.
- **Bước tiếp theo (JCOM-05-03)**:
  - Chuẩn bị hợp đồng Community Backend (Feed, Post Detail, Question Detail, Reactions).
  - Xác lập cơ chế phân quyền (ownership), idempotency và snapshot dữ liệu đính kèm (Workout / Meal) tuân thủ triệt để nguyên tắc bảo mật thông tin cá nhân.
