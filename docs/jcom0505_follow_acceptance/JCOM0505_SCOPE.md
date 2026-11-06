# JCOM-05-05 — PHẠM VI & DANH MỤC TỆP SỬA ĐỔI (SCOPE CONTROL)

## 1. Thông tin Checkpoint
- **Mã Checkpoint**: JCOM-05-05
- **Tiêu đề**: Follow Relationships, Following Feed, Profile R09 & Follow List R10
- **Phân hệ**: Saman Community Subsystem
- **Trạng thái thực thi**: Local / Isolated Test Target (`http://127.0.0.1:18090`, `mongodb://127.0.0.1:27035`, DB `saman_jcom0501_test`)

---

## 2. Danh mục tệp được phép sửa đổi tối thiểu (Allowlist)

### 2.1 Backend Models & Routers
- `backend/app/models/community.py`:
  - Thêm `CommunityAuthorProfileResponse`: profile công khai tối thiểu (id, name, avatar_url, title, is_verified, follower_count, following_count, post_count, is_following).
  - Thêm `FollowResponse`: kết quả mutation follow/unfollow (author_id, is_following, follower_count, following_count).
  - Thêm `CommunityFollowListResponse`: danh sách người theo dõi / đang theo dõi có phân trang ổn định và tổng số.
- `backend/routers/community.py`:
  - Thêm `get_community_follows_collection()` kết nối collection `community_follows`.
  - Triển khai `PUT /api/community/authors/{author_id}/follow`:
    - Yêu cầu Auth (JWT bearer canonical `follower_id = current_user["_id"]`).
    - Chống tự follow bản thân (`follower_id == author_id` -> HTTP 400).
    - Xác thực `author_id` tồn tại trong hệ thống.
    - Idempotent upsert / insert bắt `DuplicateKeyError`.
    - Authoritative counter từ `count_documents({"following_id": author_id})`.
  - Triển khai `DELETE /api/community/authors/{author_id}/follow`:
    - Yêu cầu Auth.
    - Idempotent delete (`delete_one`).
    - Authoritative counter.
  - Triển khai `GET /api/community/authors/{author_id}`:
    - Projection công khai tối thiểu, không rò rỉ email/pass/health/credentials.
    - Trả về `is_following` dựa trên canonical viewer.
  - Triển khai `GET /api/community/authors/{author_id}/followers` & `GET /api/community/authors/{author_id}/following`:
    - Phân trang ổn định, bảo mật projection, `is_following` của viewer hiện tại.
  - Cập nhật `GET /api/community/feed`:
    - Tab `following`: trả về bài viết từ các tác giả mà current user đang follow.
    - Audience filter: bài viết public và followers_only của người được follow hiển thị; private post của người khác tuyệt đối 404/ẩn.
    - Batch lookup `is_following` cho các bài viết trong Feed.
- `backend/scripts/setup_community_indexes.py`:
  - Tạo compound unique index `{ "follower_id": 1, "following_id": 1 }` trên `community_follows`.
  - Tạo index `{ "follower_id": 1, "created_at": -1 }` và `{ "following_id": 1, "created_at": -1 }`.

### 2.2 Backend Tests
- `backend/tests/test_community_follow_api.py`:
  - Kiểm thử 401 unauthenticated.
  - Kiểm thử self-follow rejection (400).
  - Kiểm thử invalid target rejection (404).
  - Kiểm thử idempotent PUT & DELETE và concurrency.
  - Kiểm thử Author Profile & Follow Lists projection bảo mật (không rò rỉ dữ liệu nhạy cảm).
  - Kiểm thử Following feed chỉ trả bài của người được follow.
  - Kiểm thử Audience trước và sau khi Follow/Unfollow (followers_only).
  - Kiểm thử không xem được private post của người khác.

### 2.3 Frontend Remote Datasource & Repositories
- `frontend/lib/features/community/data/datasources/community_remote_datasource.dart`:
  - Bổ sung `followAuthor`, `unfollowAuthor`, `getAuthorProfile`, `getFollowers`, `getFollowing`.
- `frontend/lib/features/community/data/repositories/community_repository_impl.dart`:
  - Quản lý `_remoteFollowedAuthorIds`.
  - Triển khai `toggleFollow`, `getAuthorProfile`, `getFollowers`, `getFollowing` ở chế độ Remote.
  - Timeout reconciliation & in-flight lock cho follow mutations.
  - Identity guard & generation isolation khi đổi tài khoản (`resetForUser`).

### 2.4 Frontend Presentation & Screens
- `frontend/lib/features/community/presentation/providers/community_providers.dart`:
  - Bổ sung `updateAuthorFollow` trên `CommunityFeedNotifier` và `CommunityPostDetailNotifier`.
  - Khi unfollow, tự động cập nhật Following tab loại bỏ bài của tác giả không còn follow.
  - Bổ sung `communityAuthorProfileProvider` hoặc state sync trên Profile.
- `frontend/lib/features/community/presentation/screens/profile/community_profile_screen.dart` (R09):
  - Hiển thị counts `followerCount`, `followingCount` từ backend thật.
  - Kích hoạt nút "Theo dõi" / "Đang theo dõi" khi xem profile người khác (`!_isMe`).
  - Điều hướng sang R10 Follow List đúng tab và đúng author.
- `frontend/lib/features/community/presentation/screens/profile/community_follow_list_screen.dart` (R10):
  - Nhận `authorId` động thay vì hardcode `'me'`.
  - Tải danh sách người theo dõi và đang theo dõi thật.
  - Kích hoạt nút toggle follow trên từng user tile và đồng bộ tức thời.
- `frontend/lib/features/community/presentation/screens/community_feed_screen.dart` (R03):
  - Hỗ trợ tải tab "Đang theo dõi" từ backend remote.
  - Tự động làm mới khi thay đổi quan hệ follow.
- `frontend/lib/features/community/presentation/widgets/post_card_view.dart`:
  - Cho phép click vào tác giả để mở màn hình Profile R09 tương ứng.

### 2.5 Frontend Tests
- `frontend/test/features/community/community_follow_test.dart`:
  - Kiểm thử đồng bộ Follow state giữa Profile R09, Follow List R10 và Feed R03.
  - Kiểm thử Timeout reconciliation và error rollback.
  - Kiểm thử Identity Guard (response cũ không nhiễm sang tài khoản mới).
  - Kiểm thử Following feed cập nhật sau khi follow/unfollow.

### 2.6 Docs & Runtime Evidence
- `docs/jcom0505_follow_acceptance/JCOM0505_SCOPE.md` (tệp này).
- `docs/jcom0505_follow_acceptance/JCOM0505_REPORT.md`.
- `docs/jcom0505_follow_acceptance/screenshots/`: các ảnh chụp nghiệm thu Playwright.
- `runtime_evidence/jcom0505_follow/run_jcom0505_traversal.py`.
- `docs/CONTINUOUS_RUN_STATUS.md`.

---

## 3. Danh mục tệp tuyệt đối KHÔNG sửa đổi (Forbidden Paths)
- Toàn bộ `frontend/lib/features/journal/` và `backend/routers/journal.py`.
- Toàn bộ Workout (`frontend/lib/features/workout/`, `backend/routers/workout.py`).
- Toàn bộ Nutrition (`frontend/lib/features/nutrition/`, `backend/routers/nutrition.py`).
- `backend/routers/auth.py`, `backend/routers/user.py` (Profile tài khoản gốc).
- `frontend/pubspec.yaml`, `backend/requirements.txt`, lockfiles.
- `AGENTS.md`.
