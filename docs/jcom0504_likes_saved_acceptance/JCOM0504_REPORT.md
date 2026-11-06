# JCOM-05-04 — Báo cáo Nghiệm thu Persistent Likes & Saved Posts

## 1. Thông tin tổng quan & Phạm vi
- **Checkpoint ID**: JCOM-05-04
- **Tiêu đề**: Persistent Likes & Saved Posts (Saman Community Subsystem)
- **Mục tiêu**:
  1. Triển khai API và persistence thực tế cho Like/Unlike và Save/Unsave trên backend local/test (`mongodb://127.0.0.1:27035`, DB `saman_jcom0501_test`, port `18090`).
  2. Idempotent API design:
     - `PUT /api/community/posts/{post_id}/like` & `DELETE /api/community/posts/{post_id}/like`
     - `PUT /api/community/posts/{post_id}/save` & `DELETE /api/community/posts/{post_id}/save`
     - `GET /api/community/saved` (Saved list lọc audience tại thời điểm đọc).
  3. Unique compound index trên collection `community_interactions`: `("user_id", 1), ("interaction_type", 1), ("post_id", 1)`.
  4. Quyền xem (Audience Enforcement):
     - Không cho tương tác với post private của người khác, post bị xóa hoặc unpublished (fail-closed HTTP 404).
     - `GET /api/community/saved`: Tự động ẩn bài viết bị xóa hoặc bị tác giả chuyển thành private tại thời điểm đọc.
  5. Đồng bộ trạng thái 3 màn hình: Feed R03, Post Detail R05, và Saved R12.
     - Fast-tap lock (chống duplicate in-flight requests), optimistic update với cơ chế rollback khi lỗi hoặc timeout.
     - Chuyển đổi tài khoản (Athlete A vs Athlete B) cách ly 100% dữ liệu đã lưu.
  6. Các mutation chưa triển khai backend (Follow, Comment, Answer, Publish, Drafts) tiếp tục bị giới hạn an toàn với phản hồi trung thực.

---

## 2. Kết quả kiểm thử & Bằng chứng nghiệm thu

### 2.1 Backend Tests (`backend/tests/test_community_interactions.py` & `test_community_read_api.py`)
- `test_unauthenticated_interactions_rejected_401`: PASS (401 cho like, unlike, save, unsave, saved list).
- `test_audience_enforcement_for_interactions`: PASS (User B nhận 404 khi like/save bài private của User A hoặc bài bị xóa; User A like được bài private của chính mình).
- `test_idempotent_like_and_unlike`: PASS (Gửi lại PUT like không tăng like_count quá 1 lần; gửi lại DELETE like không làm like_count âm).
- `test_idempotent_save_and_unsave`: PASS (Gửi lại PUT/DELETE save giữ nguyên trạng thái idempotent).
- `test_saved_posts_isolation_and_audience_filtering`: PASS (Danh sách đã lưu của Athlete A và B độc lập; khi bài viết bị tác giả chuyển thành private, bài viết biến mất khỏi danh sách đã lưu của người xem khác tại thời điểm đọc).
- `test_community_read_api.py`: 11/11 tests PASS (Zero regressions trên hợp đồng đọc).

### 2.2 Frontend Unit & Widget Tests
- `test/features/community/community_interactions_test.dart`: 5/5 tests PASS.
  - Like/unlike cập nhật đúng state và count.
  - Save/unsave cập nhật bookmark state và danh sách đã lưu.
  - Đồng bộ tức thì giữa Feed provider và PostDetail provider.
  - Optimistic rollback khi remote gặp sự cố.
  - Đồng bộ giữa Feed và Saved Screen khi unbookmark.
- `test/features/community/community_remote_read_test.dart`: 6/6 tests PASS.
- Toàn bộ 75 tests suite hiện hữu trong `test/features/community/`: PASS (Tổng cộng 86 community tests passing).
- `flutter analyze lib/features/community`: **No issues found (0 errors, 0 warnings)**.

### 2.3 Runtime Evidence Playwright Traversal (`--dart-define=USE_REMOTE_COMMUNITY=true`)
Playwright script `runtime_evidence/jcom0504_likes_saved/run_jcom0504_traversal.py` đã thực hiện phiên tương tác hoàn chỉnh và chụp 9 ảnh bằng chứng vào thư mục `docs/jcom0504_likes_saved_acceptance/screenshots/`:
1. `rt01_login_home.png`: Athlete A đăng nhập thành công vào app chính, hiển thị Home Screen.
2. `rt02_community_feed_before_like_save.png`: Vào R03 Community Feed qua Journal Doorway; bài viết 1 ban đầu có 14 lượt thích, chưa thích, chưa lưu.
3. `rt03_community_feed_after_like_save.png`: Thao tác Like & Lưu bài viết 1; icon thích sáng đỏ, số like tăng lên 15, icon bookmark chuyển sang đã lưu.
4. `rt04_post_detail_synced_state.png`: Mở R05 Chi tiết bài viết; hiển thị đồng bộ chính xác 15 lượt thích, trạng thái đã thích và đã lưu.
5. `rt05_saved_screen_shows_saved_post.png`: Chuyển qua Profile -> R12 Bài viết đã lưu; bài viết 1 xuất hiện đầy đủ trong danh sách.
6. `rt06_saved_screen_after_unsave.png`: Bấm bỏ lưu trong R12; bài viết lập tức biến mất khỏi danh sách, hiển thị snackbar "Đã bỏ lưu bài viết. Hoàn tác".
7. `rt07_community_feed_reflects_unsave.png`: Quay lại Feed R03; bài viết 1 vẫn giữ nguyên 15 lượt thích, nhưng icon bookmark đã trở về trạng thái chưa lưu.
8. `rt08_user_b_isolation_empty_saved.png`: Đăng nhập tài khoản Athlete B; vào R12 Bài viết đã lưu, danh sách hoàn toàn trống (cách ly tuyệt đối).
9. `rt09_controlled_network_error_rollback.png`: Thử nghiệm môi trường lỗi mạng giả lập; thao tác like lập tức rollback về trạng thái trước đó kèm snackbar cảnh báo trung thực.

---

## 3. Danh sách tệp đã tạo / sửa đổi (Tuân thủ Scope Control)
Tất cả các tệp sửa đổi nằm 100% trong danh sách được cấp phép tại `docs/jcom0504_likes_saved_acceptance/JCOM0504_SCOPE.md`:
- `backend/app/models/community.py`
- `backend/routers/community.py`
- `backend/scripts/setup_community_indexes.py`
- `backend/tests/test_community_interactions.py`
- `frontend/lib/features/community/data/datasources/community_remote_datasource.dart`
- `frontend/lib/features/community/data/repositories/community_repository_impl.dart`
- `frontend/lib/features/community/presentation/providers/community_providers.dart`
- `frontend/lib/features/community/presentation/screens/community_feed_screen.dart`
- `frontend/lib/features/community/presentation/screens/community_post_detail_screen.dart`
- `frontend/lib/features/community/presentation/screens/saved/community_saved_screen.dart`
- `frontend/test/features/community/community_interactions_test.dart`
- `frontend/test/features/community/community_remote_read_test.dart`
- `runtime_evidence/jcom0504_likes_saved/`
- `docs/jcom0504_likes_saved_acceptance/`

Không chỉnh sửa bất kỳ tệp ngoài phạm vi nào (Auth/Profile core, Workout/Nutrition, Journal, AGENTS.md, dependencies). Không commit, không push, không merge.

