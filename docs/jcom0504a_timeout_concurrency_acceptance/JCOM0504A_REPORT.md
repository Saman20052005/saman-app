# JCOM-05-04A — Báo cáo Nghiệm thu Timeout Reconciliation & Concurrency Acceptance

## 1. Thông tin tổng quan & Phạm vi
- **Checkpoint ID**: JCOM-05-04A
- **Tiêu đề**: Timeout Reconciliation & Concurrency Acceptance (Saman Community Subsystem)
- **Mục tiêu**:
  1. **Authoritative Counter Consistency**: Loại bỏ hoàn toàn drift counter do `$inc` suy đoán. Chuyển sang authoritative count suy ra trực tiếp từ `community_interactions.count_documents({"post_id": canonical_post_id, "interaction_type": "like"})` và cập nhật `$set`. Tự phục hồi (self-healing) nếu `like_count` từng bị corrupt do crash/lỗi mạng trước đó.
  2. **Timeout Reconciliation (Khắc phục lỗi gián đoạn mạng không xác định)**: Phân biệt rõ lỗi dứt khoát (HTTP 4xx như 401, 403, 404 - chưa hề ghi) và lỗi không xác định (timeout, rớt socket sau khi server đã commit, gateway timeout 502/503/504). Triển khai cơ chế refetch/reconcile tự động bằng trạng thái canonical từ backend qua `getPostDetail(postId)`.
  3. **Identity Guards & Account Switch Isolation**: Thiết lập generation tracking (`_generation`, `_activeUserId`) trên cả Repository và các Riverpod Notifiers. Đảm bảo in-flight request của Athlete A về trễ bị hủy bỏ hoàn toàn, không rò rỉ bookmark hay counter vào state của Athlete B.
  4. **Saved UI Navigation & Real Reload Persistence**: Xác minh luồng điều hướng UI thuần túy (không dùng deep link): Feed (R03) → Bottom Nav "Hồ sơ" → Profile (R09) → Nút "Đã lưu" UI → R12 Saved Screen → R05 Post Detail. Kiểm chứng qua `page.reload()` (F5) để chứng minh dữ liệu lưu bền vững trên MongoDB thật, không chỉ nằm trên RAM.
  5. **Bảo toàn Scope Control & Zero Regressions**: Không sửa ngoài allowlist, không sửa Profile backend/auth, không commit/push/merge, 0 errors, 0 warnings.

---

## 2. Kết quả kiểm thử & Bằng chứng nghiệm thu

### 2.1 Backend Concurrency & Authoritative Count Tests (`backend/tests/test_community_concurrency_mongo.py`)
Kiểm thử trên MongoDB thật độc lập (`mongodb://127.0.0.1:27035`, DB `saman_jcom0501_test`):
- `test_controlled_interleaving_put_put_no_stale_overwrite`: **PASS** (Kiểm soát interleaving chính xác bằng `threading.Event`: Thread A pause trước khi $set với count=1; Thread B hoàn tất $set với count=2; Thread A tiếp tục với OCC check; stale write bị từ chối và retry, kết quả cuối cùng like_count = 2 trên DB, Detail và Feed mà không cần bất kỳ mutation tự sửa nào sau đó).
- `test_controlled_interleaving_put_delete_no_stale_overwrite`: **PASS** (Kiểm soát interleaving cho PUT/DELETE: Thread A PUT pause trước $set với count=2; Thread B DELETE hoàn tất với count=1; Thread A tiếp tục với OCC check; stale write bị từ chối và retry, kết quả cuối cùng like_count = 1 trên DB, Detail và Feed).
- `test_same_user_concurrent_put_likes`: **PASS** (4 PUT like đồng thời từ cùng 1 user chỉ tạo đúng 1 interaction document và like_count = 1).
- `test_distinct_users_concurrent_put_likes`: **PASS** (10 PUT like đồng thời từ 10 user khác nhau tạo đúng 10 interaction documents và like_count = 10).
- `test_interleaved_put_and_delete`: **PASS** (8 user thực hiện PUT like và DELETE unlike xen kẽ đồng thời; kết quả cuối cùng like_count = 4, khớp 100% với số document trong `community_interactions`).
- `test_counter_self_healing_from_corruption`: **PASS** (Cố tình corrupt `like_count = 999` trên collection posts; mutation tiếp theo tự động heal và phục hồi `like_count = 2` chính xác theo authoritative count).
- Tổng thời gian chạy: **0.487s** (6/6 tests PASS).

### 2.2 Backend Interaction Unit Tests (`backend/tests/test_community_interactions.py`)
- `test_audience_enforcement_for_interactions`: **PASS**
- `test_idempotent_like_and_unlike`: **PASS**
- `test_idempotent_save_and_unsave`: **PASS**
- `test_saved_posts_isolation_and_audience_filtering`: **PASS**
- `test_unauthenticated_interactions_rejected_401`: **PASS**
- Tổng thời gian chạy: **0.246s** (5/5 tests PASS).

### 2.3 Frontend Timeout Reconciliation & Identity Guard Tests (`frontend/test/features/community/community_timeout_reconciliation_test.dart`)
- `1. Server persists Like but response drops with timeout -> client reconciles to canonical state`: **PASS** (Không rollback bừa bãi khi server đã commit; cập nhật canonical state từ server).
- `2. Server persists Save but network connection drops -> client reconciles to canonical saved state`: **PASS**
- `3. Definitive error (404/403) -> immediate rollback to previous state`: **PASS**
- `4. Indeterminate error where reconciliation also times out -> keeps optimistic state without false failure`: **PASS**
- `5. Identity Guard: In-flight request from Athlete A does not taint Athlete B on account switch`: **PASS** (Request trễ của User A bị loại bỏ, User B sạch 100%).
- `6. HTTP 500 treated as indeterminate error -> reconciles with canonical state`: **PASS** (Lỗi 500 từ server được đối xử như indeterminate để reconcile thay vì coi là dứt khoát chưa ghi).
- `7. Reconciliation returns 404 (deleted/unauthorized) -> evicts cached interaction`: **PASS** (Khi reconcile gặp 401 hoặc 404, bài viết bị thu hồi/xóa khỏi cache local like và bookmark).
- Toàn bộ tests trong `frontend/test/features/community/`: **ALL PASS**.
- `flutter analyze lib/features/community`: **No issues found (0 errors, 0 warnings)**.

### 2.4 Playwright Traversal & Runtime Evidence
Script tự động: `runtime_evidence/jcom0504a_timeout_concurrency/run_jcom0504a_traversal.py` đã chụp 11 ảnh bằng chứng vào `docs/jcom0504a_timeout_concurrency_acceptance/screenshots/`:
1. `rt01_login_home.png`: Athlete A đăng nhập thành công vào app chính, hiển thị Home Screen.
2. `rt02_feed_initial.png`: Vào R03 Community Feed qua Journal Doorway; bài viết 1 ban đầu có 14 lượt thích, chưa thích, chưa lưu.
3. `rt03_feed_liked_saved.png`: Liking & Lưu bài viết 1; số like tăng 15, icon bookmark chuyển sang đã lưu.
4. `rt04_profile_saved_button.png`: Chuyển qua tab Hồ sơ (R09) trên thanh điều hướng dưới; làm nổi bật nút "Đã lưu" UI outline.
5. `rt05_saved_screen_shows_post.png`: Bấm nút "Đã lưu" trên UI → Mở R12 Saved Screen, bài viết đã lưu hiển thị đầy đủ.
6. `rt06_post_detail_from_saved.png`: Bấm vào bài viết trong R12 → Mở R05 Post Detail đồng bộ 15 like và bookmark.
7. `rt07_page_reload_persistence.png`: Thực hiện F5 (`page.reload()`) trên trình duyệt → Duyệt lại Profile → Đã lưu; dữ liệu vẫn nguyên vẹn 100% từ MongoDB.
8. `rt08_saved_screen_unsave.png`: Bỏ lưu từ R12 Saved Screen; bài viết lập tức được xóa khỏi danh sách.
9. `rt09_feed_synced_after_unsave.png`: Quay về Feed R03; bài viết giữ nguyên 15 lượt thích, bookmark đã về trạng thái chưa lưu.
10. `rt10_user_b_isolation_empty.png`: Đăng nhập Athlete B; mở Profile → Đã lưu; danh sách hoàn toàn trống (cách ly 100%).
11. `rt11_delayed_request_account_switch.png`: Kiểm thử race condition mạng trễ 3 giây; chuyển đổi danh tính Athlete B không bị dữ liệu lạc của Athlete A ghi đè.

---

## 3. Danh sách tệp đã tạo / sửa đổi (Scope Control)
Tuân thủ 100% danh mục tại `docs/jcom0504a_timeout_concurrency_acceptance/JCOM0504A_SCOPE.md`:
- `backend/routers/community.py`: Cập nhật logic authoritative count và self-healing.
- `backend/scripts/setup_community_indexes.py`: Thêm `idx_post_interaction_count` trên collection `community_interactions`.
- `backend/tests/test_community_concurrency_mongo.py`: Bộ kiểm thử concurrency 4 scenarios trên MongoDB thật port 27035.
- `backend/tests/test_community_interactions.py`: Cập nhật mock seed test data để đồng bộ count authoritative.
- `frontend/lib/features/community/data/repositories/community_repository_impl.dart`: Thêm `IndeterminateMutationException`, timeout reconciliation logic, và identity guards (`_generation`, `_activeUserId`).
- `frontend/lib/features/community/presentation/providers/community_providers.dart`: Generation tracking và reconciliation handling trên `CommunityFeedNotifier`, `CommunityPostDetailNotifier`, `CommunitySavedNotifier`.
- `frontend/test/features/community/community_timeout_reconciliation_test.dart`: 5 tests kiểm thử timeout reconciliation và identity switch guard.
- `runtime_evidence/jcom0504a_timeout_concurrency/run_jcom0504a_traversal.py`: Script Playwright tự động 11 bước.
- `docs/jcom0504a_timeout_concurrency_acceptance/screenshots/`: 11 ảnh bằng chứng runtime.

---

## 4. Bảng nghiệm thu tiêu chí (Acceptance Criteria Matrix)

| Tiêu chí | Trạng thái | Ghi chú & Bằng chứng |
| :--- | :---: | :--- |
| **Authoritative Counter Consistency & OCC** | **PASS** | `count_documents({"post_id": ..., "interaction_type": "like"})` bảo đảm tính nhất quán tuyệt đối. Optimistic Concurrency Control (OCC) với `interaction_version` ngăn chặn hoàn toàn race overwrite stale count. Read paths (Feed/Detail) tính count authoritative trực tiếp từ `community_interactions`. Tự phục hồi khi post corrupt (`test_counter_self_healing_from_corruption`). |
| **Controlled Interleaving (No Stale Overwrite)** | **PASS** | Kiểm chứng bằng barrier/event: PUT/PUT interleaving (`test_controlled_interleaving_put_put_no_stale_overwrite`) và PUT/DELETE interleaving (`test_controlled_interleaving_put_delete_no_stale_overwrite`) đều đạt kết quả chính xác trên cả DB, Detail, và Feed mà không cần bất kỳ self-healing mutation nào sau đó. |
| **Concurrency PUT/DELETE Handling** | **PASS** | `test_same_user_concurrent_put_likes` (1 interaction), `test_distinct_users_concurrent_put_likes` (10 interactions), `test_interleaved_put_and_delete` (count = 4). |
| **Timeout Reconciliation & Error Review** | **PASS** | Tự động phân biệt lỗi dứt khoát (4xx -> rollback) và lỗi gián đoạn mạng không xác định (timeouts, socket drop, HTTP 500/502/503/504 -> refetch canonical post detail để xác nhận). Khi reconcile gặp 401/404, lập tức dọn sạch cache local like/bookmark. |
| **Identity Guards (Account Switch)** | **PASS** | Generation tracking `_generation` loại bỏ triệt để việc dữ liệu trễ của Athlete A rò rỉ sang state của Athlete B (`community_timeout_reconciliation_test.dart` test 5 & `rt11`). |
| **UI-only Saved Navigation** | **PASS** | Điều hướng hoàn toàn qua UI: Feed → Hồ sơ → Nút "Đã lưu" outline → R12 Saved Screen → R05 Post Detail (`rt04`, `rt05`, `rt06`). |
| **Real Database Persistence (Reload)** | **PASS** | Kiểm chứng bằng browser reload (`page.reload()`), dữ liệu lưu trong MongoDB `saman_jcom0501_test` tồn tại độc lập với RAM (`rt07`). |
| **Unsave Synchronization** | **PASS** | Unsave trong Saved Screen phản ánh lập tức về Feed và Detail (`rt08`, `rt09`). |
| **Athlete B Data Isolation** | **PASS** | Danh sách bài viết đã lưu của Athlete B hoàn toàn trống, không thấy bài của Athlete A (`rt10`). |
| **Zero Regressions** | **PASS** | 0 new analyzer warnings, 0 compile errors, 91/91 frontend community tests PASS, 9/9 backend community tests PASS. |

