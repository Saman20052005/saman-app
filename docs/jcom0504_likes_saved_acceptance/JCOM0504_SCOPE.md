# PHẠM VI CHECKPOINT JCOM-05-04 (JCOM-05-04 SCOPE DEFINITION)
**Triển khai Persistent Likes & Saved Posts (Đồng bộ Feed R03, Post Detail R05, Saved R12)**

---

## 1. Mục Tiêu Checkpoint
- Triển khai API và lưu trữ thực tế cho tương tác Like/Unlike và Save/Unsave trên backend.
- Đảm bảo tính idempotent: Sử dụng HTTP `PUT` (kích hoạt) và `DELETE` (hủy kích hoạt), loại bỏ rủi ro blind toggle khi retry.
- Thiết lập unique compound index trên database test: `user_id + interaction_type + post_id`.
- Kiểm soát đối tượng xem (Audience Enforcement) chặt chẽ trên mọi mutation và tại thời điểm đọc danh sách bài viết đã lưu (`GET /api/community/saved`).
- Đồng bộ trạng thái tức thời và nhất quán giữa:
  - Bảng tin R03 (`CommunityFeedScreen`).
  - Chi tiết bài viết R05 (`CommunityPostDetailScreen`).
  - Màn hình Đã lưu R12 (`CommunitySavedScreen`).
- Xử lý tap nhanh (fast tap), race conditions, optimistic update rollback và timeout reconciliation trên frontend.
- Nghiệm thu tự động Playwright trên ứng dụng web chính với hai phiên Athlete A và Athlete B, kiểm tra khôi phục lỗi mạng có kiểm soát.

---

## 2. Danh Sách Tệp Được Phép Tạo / Sửa (Allowed Paths)

### A. Backend
1. `backend/app/models/community.py` (Sửa đổi: Bổ sung Interaction Response models nếu cần)
2. `backend/routers/community.py` (Sửa đổi: Triển khai PUT/DELETE Like & Save, GET /saved, gắn cờ is_liked/is_bookmarked từ DB)
3. `backend/tests/test_community_interactions.py` (Tạo mới: Unit & contract test suite cho Persistent Likes & Saved)
4. `backend/scripts/setup_community_indexes.py` (Tạo mới: Script tạo unique compound index trên DB test)

### B. Frontend
1. `frontend/lib/features/community/data/datasources/community_remote_datasource.dart` (Sửa đổi: Thêm `likePost`, `unlikePost`, `savePost`, `unsavePost`, `getSavedPosts`)
2. `frontend/lib/features/community/data/repositories/community_repository_impl.dart` (Sửa đổi: Nối remote like/bookmark/getSavedPosts, giữ an toàn các mutations chưa có backend)
3. `frontend/lib/features/community/presentation/providers/community_providers.dart` (Sửa đổi: Đồng bộ trạng thái Feed ↔ Detail ↔ Saved, optimistic updates & rollback, timeout reconciliation)
4. `frontend/lib/features/community/presentation/screens/community_feed_screen.dart` (Sửa đổi: Đồng bộ sự kiện Like/Save với state remote)
5. `frontend/lib/features/community/presentation/screens/community_post_detail_screen.dart` (Sửa đổi: Đồng bộ sự kiện Like/Save với state remote)
6. `frontend/lib/features/community/presentation/screens/saved/community_saved_screen.dart` (Sửa đổi: Đọc từ remote datasource, hỗ trợ bỏ lưu và hoàn tác đồng bộ)
7. `frontend/test/features/community/community_interactions_test.dart` (Tạo mới: Unit & widget tests kiểm tra đồng bộ Feed/Detail/Saved và rollback)

### C. Tài liệu & Nghiệm thu
1. `docs/jcom0504_likes_saved_acceptance/JCOM0504_SCOPE.md` (Tài liệu ranh giới phạm vi)
2. `docs/jcom0504_likes_saved_acceptance/JCOM0504_REPORT.md` (Báo cáo nghiệm thu hoàn tất)
3. `docs/jcom0504_likes_saved_acceptance/screenshots/*` (Bằng chứng runtime screenshots)
4. `runtime_evidence/jcom0504_likes_saved/*` (Scripts seed & Playwright traversal)
5. `docs/CONTINUOUS_RUN_STATUS.md` (Cập nhật tiến độ)

---

## 3. Ranh Giới Nghiêm Ngặt (Prohibited Scope)
- KHÔNG sửa logic Auth/Profile hoặc can thiệp thông tin User ngoài việc xác thực JWT principal.
- KHÔNG sửa logic Workout/Nutrition hoặc Journal.
- KHÔNG triển khai Notifications, Follow graph, Comment mutations, hoặc Publish bài viết.
- KHÔNG deploy remote (HuggingFace) hoặc sửa đổi ngoài thư mục test đã định danh.
- KHÔNG thực hiện git commit, push hoặc merge.

