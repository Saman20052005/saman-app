# JCOM-02A — AUDIT, RUNTIME RECONCILIATION & TARGETED REFINEMENTS

**Checkpoint**: JCOM-02A  
**Status**: **PARTIAL (Frontend Components, State Machine & Widget Suites PASS; Live E2E Traversal BLOCKED by Profile Contract)**  
**Branch**: `agent/nutrition-active-localhost-f02`  
**Date**: 2026-11-01  
**Author**: Senior Flutter Engineer (Antigravity Agent)

---

## 1. Bằng Chứng & Kết Luận Nghiệm Thu (Evidence & Acceptance Calibration)

### 1.1 Phân Loại Bằng Chứng Rõ Ràng
Nhằm tuân thủ tuyệt đối tính trung thực kỹ thuật và hướng dẫn của `AGENTS.md`:
- **Bằng chứng Runtime thực tế (CDP Chrome trên môi trường chạy live)**:
  - 4 ảnh chụp CDP tại `docs/jcom01b_reconciliation/` ghi nhận chính xác phản hồi thực tế từ remote backend HuggingFace Spaces.
  - Phản hồi `GET /api/user/profile` thiếu trường bắt buộc `user_id`, khiến `ProfileRemoteDataSourceImpl` ném `FormatException`.
  - Kết quả: Ứng dụng dừng tại màn hình Splash/Loading, không thể điều hướng tới `MainScreen`.
  - **Kết luận**: Nghiệm thu tích hợp runtime live end-to-end của cả Journal (JCOM-01) và Community (JCOM-02) đều ở trạng thái **PARTIAL / BLOCKED** bởi hợp đồng Profile backend.
- **Bằng chứng Widget-Test Renders (Kiểm thử giao diện cục bộ)**:
  - Toàn bộ 13 ảnh chụp tại `docs/jcom02_community_feed/screenshots/` (`c01` đến `c13`) được sinh ra từ Flutter test runner (`community_ui_render_test.dart`).
  - Phản ánh chính xác 100% bố cục widget, font chữ, màu sắc tokens, co giãn 360px và chữ lớn 200%, nhưng chạy trên bộ nhớ cục bộ (In-Memory Fake Datasource).

### 1.2 Phân Biệt Phạm Vi Kiểm Thử Hồi Quy
- Bộ kiểm thử `frontend/test/workout_session_flow_test.dart` (63/63 PASS) là kiểm thử hồi quy nội bộ của phân hệ Tập luyện (Workout), chứng minh việc bổ sung Community không làm hỏng tính năng tập luyện hiện có.
- **Không suy diễn** việc 63 bài test Workout đạt là bằng chứng hệ thống backend live đã hoạt động hoặc đã kiểm thử toàn bộ ứng dụng.

### 1.3 Phân Tích Hiện Trạng Analyzer (Baseline vs Giới Hạn)
- Phân tích mã nguồn toàn dự án (`flutter analyze --no-fatal-infos --no-fatal-warnings`) ghi nhận 81–83 issues.
- **Toàn bộ 81–83 issues này thuộc về các module nghiệp vụ cũ chưa được giao sửa**:
  - `lib/config/app_theme.dart`: prefer_const_constructors (20 issues).
  - `lib/data/repositories/muscle_group_repository.dart`: prefer_const_constructors (6 issues).
  - `lib/presentation/providers/`: deprecated_member_use, unused_import (18 issues).
  - `lib/providers/nutrition_provider.dart`: unused_import, unused_field (10 issues).
  - `lib/screens/food_log_screen.dart`, `nutrition_screen.dart`: use_build_context_synchronously (4 issues).
- **Phân hệ Community mới (`lib/features/community/` và `test/features/community/`)**:
  - Đạt **0 compile errors, 0 warnings, 0 infos** (`Analyzing 2 items... No issues found!`).

---

## 2. Kiểm Tra & Tối Ưu Trợ Năng Chữ Lớn (Text Scaling & Adaptive Layout)

### 2.1 Loại Bỏ Giới Hạn Ép Cứng (TextScaler Clamp Removal)
- **Vấn đề phát hiện**: Trước đây, `CommunityBottomNavigationBar` áp dụng `clamp(maxScaleFactor: 1.15)` để tránh tràn 60px chiều cao cố định. Việc này vi phạm nguyên tắc trợ năng nếu người khiếm thị cần phóng to 200%.
- **Giải pháp thích ứng**:
  - Bỏ hoàn toàn `textScaler clamp`.
  - Bọc nhãn văn bản trong `Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(...)))`.
  - Cho phép container điều hướng co giãn chiều cao linh hoạt với `BoxConstraints(minHeight: 60)`.
  - Khi người dùng cài đặt text scale 200%, kích thước chữ tự động co giãn tối đa trong khoảng không khả dụng mà không gây vỡ giao diện (0 RenderFlex overflow) và vẫn bảo đảm vùng chạm tối thiểu 48x48dp per item.

### 2.2 Đánh Giá Độc Lập R03 / R04 / R05
- **R03 (Bảng tin)**:
  - Bỏ `height: 52` cố định tại `_buildCategoryTabs`. Thay bằng padding dọc để các tab tự động giãn theo cỡ chữ.
  - Action bar của bài viết dùng `Wrap` thay vì `Row` đơn thuần, tránh tràn ngang khi nút bấm nở to.
- **R04 (Khám phá)**:
  - Thanh tìm kiếm và chip danh mục đặt trong `SingleChildScrollView` cuộn ngang. Lưới ảnh 3x3 giữ tỉ lệ vuông chuẩn.
- **R05 (Chi tiết bài viết)**:
  - Các thẻ chỉ số dinh dưỡng (Kcal, Protein, Carbs, Fat) sử dụng layout linh hoạt có thể xuống dòng khi chữ phóng đại.

---

## 3. Ma Trận Hành Vi & Mọi Điểm Chạm (CTA Matrix)

| Màn Hình | Tên Nút / Điểm Chạm (CTA) | Điểm Đến / Hành Vi | Thay Đổi Trạng Thái (State Mutation) | Phân Loại (Fake / Live) | Bằng Chứng Kiểm Thử / Render |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **R03** | Nút Back (<-) trên Top Bar | Quay về màn trước (Journal R01 hoặc Home) | Pop Navigation Route | Live UI Navigation | `journal_ui_render_test.dart` (c17-c21) |
| **R03** | 3 Filter Chips (Dành cho bạn, Đang theo dõi, Hỏi đáp) | Chuyển đổi bộ lọc bảng tin | Cập nhật `activeFilter`, load danh sách bài tương ứng | Fake Repository (In-Memory) | `community_flow_test.dart` (Test 1, 2, 8) |
| **R03** | Nút Tim (Like) trên Post Card | Đổi màu tim, tăng/giảm số lượng thích | `isLiked = !isLiked`, `likeCount +/- 1` | Fake Repository (In-Memory) | `community_flow_test.dart` (Test 3) |
| **R03** | Nút Bookmark (Lưu) trên Post Card | Đổi màu bookmark | `isBookmarked = !isBookmarked` | Fake Repository (In-Memory) | `community_flow_test.dart` (Test 4) |
| **R03** | Chạm vào thẻ Post | Mở màn hình R05 Chi tiết bài viết | Push route `CommunityPostDetailScreen(postId)` | Live UI Navigation | `community_flow_test.dart` (Test 12) |
| **R03** | Tab "Khám phá" trên Bottom Bar | Chuyển sang R04 Khám phá | `Navigator.pushReplacementNamed('/community/discover')` (Chống phình stack) | Live UI Navigation | `community_bottom_navigation_bar.dart` |
| **R04** | Ô tìm kiếm (Search bar) | Nhập từ khóa tìm kiếm | Cập nhật `searchQuery` trong `CommunityDiscoverState` | Fake Repository (In-Memory) | `community_discover_screen.dart` |
| **R04** | Dải chip chủ đề (Tất cả, Giảm mỡ...) | Lọc nội dung theo chủ đề | Cập nhật `activeTopic`, lọc lưới ảnh | Fake Repository (In-Memory) | `community_flow_test.dart` (Test 7) |
| **R04** | Nút "Theo dõi" trên gợi ý Creator | Bật/tắt trạng thái theo dõi | `isFollowing = !isFollowing` | Fake Repository (In-Memory) | `community_flow_test.dart` (Test 5) |
| **R04** | Tab "Bảng tin" trên Bottom Bar | Chuyển về R03 Bảng tin | `Navigator.pushReplacementNamed('/community/feed')` | Live UI Navigation | `community_bottom_navigation_bar.dart` |
| **R05** | Nút Back (<-) trên Top Bar | Đóng chi tiết bài viết, về lại bảng tin | Pop Navigation Route | Live UI Navigation | `community_flow_test.dart` (Test 12) |
| **R05** | Nút Tim / Bookmark | Đồng bộ trạng thái với Bảng tin | Đồng bộ state qua `communityRepositoryProvider` | Fake Repository (In-Memory) | `community_flow_test.dart` (Test 3, 4) |
| **R05** | Nút "Trả lời" trên bình luận | Đặt mục tiêu phản hồi | `replyToAuthorName = [Tên]`, `replyToCommentId = [ID]` | Fake Repository (In-Memory) | `community_flow_test.dart` (Test 7) |
| **R05** | Nút (X) trên banner phản hồi | Hủy phản hồi lồng nhau | `clearReply = true` | Fake Repository (In-Memory) | `community_providers.dart` |
| **R05** | Nút Gửi bình luận | Thêm bình luận vào danh sách, tăng counter | Tạo `CommunityComment`, tăng `commentCount + 1`, clear text, disable duplicate tap | Fake Repository (In-Memory) | `community_flow_test.dart` (Test 6, 7, 9) |
| **R05** | ID bài viết không tồn tại | Hiển thị màn hình lỗi thân thiện | Hiển thị `_buildNotFoundState` kèm nút Quay lại và Thử lại | Fake Repository (In-Memory) | `community_post_detail_screen.dart` |

---

## 4. Bảo Vệ Ổn Định Trạng Thái (State Lifecycle & Safety)

1. **Chống Gọi State Sau Khi Dispose (`!mounted` Guard)**:
   - Toàn bộ phương thức bất đồng bộ trong `CommunityFeedNotifier`, `CommunityDiscoverNotifier`, và `CommunityPostDetailNotifier` được bổ sung kiểm tra `if (!mounted) return;` ngay sau các điểm `await`.
   - Ngăn ngừa hoàn toàn lỗi memory leak hoặc "setState() called after dispose()".
2. **Chống Gửi Bình Luận Trùng Lặp (Double Submit Prevention)**:
   - Bổ sung cờ `isSubmitting` vào `CommunityPostDetailState`.
   - Khi đang gửi, nút gửi bị vô hiệu hóa và phương thức `submitComment` từ chối các lượt chạm tiếp theo cho đến khi hoàn tất.
3. **Chống Phình Ngăn Xếp Điều Hướng (Navigation Stack Overflow Prevention)**:
   - Chuyển đổi giữa Bảng tin (Feed) và Khám phá (Discover) sử dụng `pushReplacementNamed`, đồng thời kiểm tra `if (tab == currentTab) return;`.

---

## 5. Tính Minh Bạch & Chống Giả Mạo (Data Transparency)

- **Banner Cảnh Báo Bản Thử Nghiệm**:
  - Bổ sung banner cố định dưới Top Bar trên cả 3 màn hình R03, R04, R05:
    `"Bản xem trước giao diện • Dữ liệu mẫu thử nghiệm"`
- **Chuẩn Hóa Danh Tính Tác Giả Mẫu**:
  - Đã loại bỏ hoàn toàn các danh xưng chức danh chuyên gia/bác sĩ.
  - Chuyển thành các nhãn minh bạch: `"Thành viên chia sẻ (Mẫu)"`, `"Thành viên tập luyện (Mẫu)"`, `"Yêu thích nấu ăn lành mạnh (Mẫu)"`.
  - Huy hiệu tích xanh (Verified) được giải thích là thành viên tích cực mẫu, không đại diện cho chứng nhận y khoa.
- **Không Thông Báo Thành Công Giả**:
  - Các thao tác Like/Bookmark/Comment diễn ra trực quan trong bộ nhớ, không hiển thị snackbar gây hiểu lầm là đã lưu vĩnh viễn lên máy chủ đám mây.
