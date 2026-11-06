# BÁO CÁO NGHIỆM THU JCOM-04 — COMMUNITY PROFILE, NOTIFICATIONS, SAVED, DRAFTS & Q&A

**Dự án:** Saman App — Community Module  
**Checkpoint:** JCOM-04 (Profile, Notifications, Saved, Drafts & Q&A)  
**Thời gian thực thi:** 01/11/2026  
**Trạng thái nghiệm thu:** **PASS (Frontend Verified & Test-Rendered)**  
**Dữ liệu thực thi:** Fake Datasource (In-memory storage) — 0 live backend routes  

---

## 1. Mục tiêu và Phạm vi thực thi

JCOM-04 hoàn tất toàn bộ các màn hình chức năng còn lại của phân hệ Community (`R09`–`R15`), liên kết chặt chẽ với hệ sinh thái Saman (Kèm Riverpod Notifiers, Adaptive Text Scaling, Data Protection):

1. **R09 — Community Profile (`CommunityProfileScreen`)**:
   - Header thông tin tác giả: Avatar chữ/ảnh, Tên, Chức danh, Huy hiệu xác thực verified.
   - Thống kê người theo dõi: Đang theo dõi (128) • Người theo dõi (1.4k).
   - Dải thông số hoạt động thể chất (`_buildStatsStrip`):
     - `42` Buổi tập chia sẻ (Kinetic logs).
     - `18` Bữa ăn dinh dưỡng (Nutrition logs).
     - `1.2k` Lượt thích nhận được từ cộng đồng.
   - 3 Tab nội dung: "Bài viết", "Buổi tập", "Bữa ăn" hiển thị bài đăng tương ứng của tác giả.
   - Nút hành động: "Chỉnh sửa hồ sơ" (nếu là chính chủ) hoặc "Theo dõi" / "Đã theo dõi" (nếu xem tác giả khác).
2. **R10 — Community Follow List (`CommunityFollowListScreen`)**:
   - TabBar 2 phân loại: "Người theo dõi" và "Đang theo dõi" kèm số lượng.
   - Danh sách thành viên kèm avatar, tên, bio/chức danh và nút tương tác "Theo dõi" / "Bỏ theo dõi".
   - Tối ưu hóa tải bất đồng bộ an toàn qua `CommunityRepository`.
3. **R14 — Community Edit Profile (`CommunityEditProfileScreen`)**:
   - Chỉnh sửa thông tin cá nhân trong cộng đồng: Tên hiển thị, Tên người dùng (@username), Chức danh.
   - Phần giới thiệu (Bio) với bộ đếm 150 ký tự.
   - Bộ chọn mục tiêu thể chất & dinh dưỡng đa lựa chọn (Tăng cơ, Giảm mỡ, Ăn sạch, Tăng sức bền, Phục hồi cơ bắp).
   - Nút "Lưu" kèm chỉ báo `_isSaving` và thông báo SnackBar.
4. **R11 — Community Notifications (`CommunityNotificationsScreen`)**:
   - Thanh bộ lọc nhanh phân loại: "Tất cả", "Tương tác", "Hệ thống".
   - Danh sách thông báo tương tác (thích, bình luận, nhắc đến, câu trả lời Q&A).
   - Nhận diện trạng thái chưa đọc (nền highlight xanh nhẹ kèm bộ đếm badge).
   - Nút "Đọc hết" đánh dấu toàn bộ thông báo đã đọc.
   - Nhấn vào thông báo điều hướng tới bài viết liên quan.
5. **R12 — Community Saved (`CommunitySavedScreen`)**:
   - Quản lý danh sách các bài viết thể hình, thực đơn dinh dưỡng và chia sẻ đã lưu (`communitySavedProvider`).
   - Huy hiệu đếm số lượng bài viết đã lưu trên AppBar.
   - Trạng thái trống (Empty State) trực quan khi chưa lưu bài viết nào.
   - Thao tác bỏ lưu trực tiếp hoặc điều hướng vào chi tiết bài viết.
6. **R13 — Community Drafts (`CommunityDraftsScreen`)**:
   - Quản lý kho bản nháp bài viết đang soạn dở (`communityDraftsProvider`).
   - Hiển thị ngày lưu gần nhất, trích đoạn văn bản, và nhãn đính kèm (Ảnh / Buổi tập / Bữa ăn).
   - Thao tác xóa bản nháp an toàn qua hộp thoại xác nhận.
   - Thao tác mở bản nháp để tiếp tục chỉnh sửa trên `PostComposePublishScreen`.
7. **R15 — Community Question Detail (`CommunityQuestionDetailScreen`)**:
   - Thẻ câu hỏi chi tiết: Huy hiệu "Hỏi đáp", tác giả, thời gian, câu hỏi, mô tả chi tiết, hashtag.
   - Danh sách câu trả lời từ cộng đồng kèm huy hiệu "HLV trả lời", số lượt upvote.
   - Chức năng vote hữu ích (+1 upvote) tương tác tức thời.
   - Thanh nhập câu trả lời cố định ở cuối màn hình kèm nút gửi câu trả lời.
8. **Navigation & Routes Wiring**:
   - Đăng ký 5 routes mới trong `frontend/lib/config/routes.dart`:
     - `/community/profile` -> `CommunityProfileScreen`
     - `/community/notifications` -> `CommunityNotificationsScreen`
     - `/community/saved` -> `CommunitySavedScreen`
     - `/community/drafts` -> `CommunityDraftsScreen`
     - `/community/qa/detail` -> `CommunityQuestionDetailScreen`
   - Gắn kết `CommunityNavTab.notifications` và `CommunityNavTab.profile` trên `CommunityBottomNavigationBar`.

---

## 2. Bảng bằng chứng Render Screenshot (JCOM-04)

Toàn bộ ảnh chụp giao diện được lưu trữ tại `docs/jcom04_profile_notifications/screenshots/`:

| Tên ảnh | Màn hình | Mô tả chi tiết giao diện |
| :--- | :--- | :--- |
| `c22_r09_community_profile.png` | R09 | Hồ sơ cá nhân cộng đồng, dải stats buổi tập/bữa ăn/lượt thích, 3 tabs phân loại |
| `c23_r10_community_follow_list.png` | R10 | Danh sách Người theo dõi / Đang theo dõi, nút tương tác theo dõi thành viên |
| `c24_r14_community_edit_profile.png` | R14 | Chỉnh sửa hồ sơ, bio 150 ký tự, chips mục tiêu thể chất & dinh dưỡng |
| `c25_r11_community_notifications.png` | R11 | Bộ lọc Tất cả/Tương tác/Hệ thống, thông báo chưa đọc, nút Đọc hết |
| `c26_r12_community_saved.png` | R12 | Danh sách bài viết đã lưu, badge số lượng, Empty state trực quan |
| `c27_r13_community_drafts.png` | R13 | Kho bản nháp bài viết, thẻ tóm tắt đính kèm, nút xóa bản nháp |
| `c28_r15_community_question_detail.png` | R15 | Chi tiết câu hỏi Q&A, câu trả lời từ cộng đồng, upvote, thanh gửi câu trả lời |

---

## 3. Kết quả Kiểm thử & Analyzer Baseline

1. **JCOM-04 Feature Unit & Widget Test Suite**:
   - File: `frontend/test/features/community/community_features_test.dart`
   - Kết quả: **10/10 PASS** (0 test failures).
   - Nội dung kiểm tra:
     - Logic: Notifications fetch and mark read (`PASS`).
     - Logic: Followers and following lists fetch (`PASS`).
     - Logic: Question answers fetch, add answer, upvote toggle (`PASS`).
     - Widget R09: `CommunityProfileScreen` render header, bio, stats strip (`PASS`).
     - Widget R10: `CommunityFollowListScreen` switch tabs & render items (`PASS`).
     - Widget R14: `CommunityEditProfileScreen` update bio & goal chips (`PASS`).
     - Widget R11: `CommunityNotificationsScreen` filter & mark read (`PASS`).
     - Widget R12: `CommunitySavedScreen` empty & populated states (`PASS`).
     - Widget R13: `CommunityDraftsScreen` list & delete dialog (`PASS`).
     - Widget R15: `CommunityQuestionDetailScreen` submit answer & upvote (`PASS`).

2. **Screenshot Render Test Suite**:
   - File: `frontend/test/features/community/community_ui_render_test.dart`
   - Nhóm: `JCOM-04 UI Render Screenshot Captures`
   - Kết quả: **7/7 PASS** (0 render overflows).

3. **Flutter Analyzer Check**:
   - Lệnh thực thi: `flutter analyze lib/features/community test/features/community lib/config/routes.dart`
   - Kết quả: **0 issues found** (0 warnings, 0 errors).

---

## 4. Phân định dữ liệu Fake vs Live

- **Fake / In-Memory (100% Client-Side)**:
  - Tất cả danh sách bài viết đã lưu (`savedPostIds`), bản nháp (`communityDrafts`), thông báo (`communityNotifications`), câu trả lời Q&A (`communityQuestionDetail`), danh sách người theo dõi (`followers`/`following`) hiện được lưu trữ trên bộ nhớ RAM qua `CommunityFakeDatasource`.
  - Chưa kết nối backend live. Không có dữ liệu nào bị đồng bộ sai lệch với cloud.
- **Tuân thủ AGENTS.md**:
  - Không sửa đổi `backend/`, không thay đổi cấu hình server live, không chỉnh sửa cơ chế xác thực hoặc session.
