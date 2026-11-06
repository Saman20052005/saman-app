# KẾ HOẠCH TRIỂN KHAI TOÀN DIỆN TỪNG CHECKPOINT
## SAMAN JOURNAL & COMMUNITY IMPLEMENTATION ROADMAP (JCOM-01 ĐẾN JCOM-05)

Tài liệu này xác lập lộ trình triển khai chi tiết dựa trên phụ thuộc kỹ thuật thực tế của codebase Saman. Mỗi checkpoint tạo ra một luồng người dùng hoàn chỉnh, có thể chạy và nghiệm thu độc lập mà không dựng hàng loạt màn hình rỗng.

---

## 1. TỔNG QUAN LỘ TRÌNH 5 CHECKPOINT

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ JCOM-01: NỀN TẢNG ĐIỀU HƯỚNG & PHÂN HỆ SAMAN JOURNAL (R01, R02)             │
│ - Mở card Journal từ Home Saman Picks; Khám phá kiến thức 3 tab (R01)       │
│ - Tìm kiếm bài viết, bài tập & thực phẩm có debounce (R02)                  │
│ - Doorway card dẫn vào Community; Dữ liệu Fake Journal Repository           │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ JCOM-02: BẢNG TIN CỘNG ĐỒNG, KHÁM PHÁ & CHI TIẾT BÀI VIẾT (R03, R04, R05)   │
│ - Kích hoạt Shell điều hướng con Community Bottom Navigation                │
│ - Bảng tin Feed 3 định dạng post (R03), Khám phá lưới ảnh & hashtag (R04)    │
│ - Chi tiết bài viết & composer bình luận (R05); Đồng bộ Like/Save/Follow    │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ JCOM-03: LUỒNG TẠO NỘI DUNG MEDIA-FIRST & ĐÍNH KÈM HOẠT ĐỘNG                │
│ (R06A, R06B, R06C, R06D, R07, R08)                                          │
│ - Sheet (+) Tạo nội dung; Chọn ảnh (R06A), Chỉnh sửa (R06B), Album (R06C)    │
│ - Bộ chọn hoạt động đính kèm (R07) với privacy switches tắt mức tạ mặc định │
│ - Soạn bài & chia sẻ (R06D); Đặt câu hỏi (R08); Máy trạng thái bản nháp      │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ JCOM-04: HỒ SƠ THÀNH VIÊN, THÔNG BÁO, LƯU TRỮ, BẢN NHÁP & HỎI ĐÁP            │
│ (R09, R10, R11, R12, R13, R14, R15)                                         │
│ - Hồ sơ cộng đồng (R09), Danh sách follow (R10), Thông báo unread badge (R11)│
│ - Danh sách bài đã lưu (R12), Quản lý bản nháp (R13)                         │
│ - Chỉnh sửa hồ sơ R14 (Tái sử dụng upload avatar thật); Thảo luận Q&A (R15) │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ JCOM-05: TÍCH HỢP BACKEND LIVE, AN TOÀN DỮ LIỆU & KIỂM THỬ XUYÊN SUỐT       │
│ - Xây dựng các router FastAPI (`journal.py`, `community.py`)                │
│ - Xử lý idempotency key chống đăng trùng, phân quyền audience tại server     │
│ - Kiểm thử tích hợp toàn hệ thống, xác minh 0 lỗi compile/analyzer/test     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. CHI TIẾT TỪNG CHECKPOINT

### CHECKPOINT JCOM-01 — NỀN TẢNG ĐIỀU HƯỚNG & LUỒNG SAMAN JOURNAL
- **Mục tiêu & User Journey:**
  - Người dùng từ Saman Home lướt đến Saman Picks Carousel → Chạm vào card `SAMAN JOURNAL` → Mở mượt mà trang `R01_Journal_Discover`.
  - Người dùng có thể lướt xem bài viết nổi bật, các chủ đề, xem card tiếp tục đọc, khám phá thư viện bài tập/dinh dưỡng.
  - Người dùng chạm thanh tìm kiếm → Mở `R02_Journal_Search` → Gõ từ khóa tìm kiếm (bài viết, bài tập, món ăn) với bộ lọc chuyên mục.
  - Người dùng lướt xuống cuối R01 thấy card Doorway Saman Community → Chạm vào mở preview màn hình Community Feed.
  - Bấm nút Back quay về đúng màn hình trước, giữ nguyên vị trí cuộn trang.
- **Màn hình trong phạm vi:** `R01_Journal_Discover`, `R02_Journal_Search`, và stub chuyển cảnh `R03_Community_Feed`.
- **Dependencies & Blockers:**
  - Không có blocker. Cần nối sự kiện `onTap` hiện đang rỗng trong `saman_picks_carousel.dart`.
- **File hiện có cần sửa đổi:**
  - `frontend/lib/config/routes.dart` (Thêm route `/journal` và `/journal/search`).
  - `frontend/lib/screens/home/widgets/saman_picks_carousel.dart` (Gắn navigation cho `journal_recovery`).
  - `frontend/lib/config/app_translations.dart` (Thêm các key dịch thuật cho Journal).
- **File mới đề xuất tạo:**
  - `frontend/lib/features/journal/domain/models/journal_article.dart`
  - `frontend/lib/features/journal/domain/models/journal_search_result.dart`
  - `frontend/lib/features/journal/domain/repositories/journal_repository.dart`
  - `frontend/lib/features/journal/data/datasources/journal_fake_datasource.dart`
  - `frontend/lib/features/journal/data/repositories/journal_repository_impl.dart`
  - `frontend/lib/features/journal/presentation/providers/journal_providers.dart`
  - `frontend/lib/features/journal/presentation/screens/journal_discover_screen.dart` (R01)
  - `frontend/lib/features/journal/presentation/screens/journal_search_screen.dart` (R02)
  - `frontend/lib/features/journal/presentation/widgets/journal_hero_card.dart`
  - `frontend/lib/features/journal/presentation/widgets/journal_topic_chips.dart`
  - `frontend/lib/features/journal/presentation/widgets/journal_community_doorway_card.dart`
- **Data Mode:** **Fake Integration qua Riverpod DI**. Sử dụng dữ liệu khoa học chuẩn hóa về phục hồi và dinh dưỡng, không gọi API backend chưa có.
- **Chiến lược kiểm thử:**
  - Unit test cho `JournalRepository` và `JournalSearchNotifier`.
  - Widget test kiểm tra luồng Home → R01 → R02 → Back.
  - Phân tích mã nguồn `flutter analyze` đạt 0 lỗi, 0 cảnh báo.
- **Điều kiện hoàn thành (Exit Criteria):**
  - Đạt toàn bộ nghiệm thu R01 và R02 theo PRD v3.0.
  - Không gây regression lên các màn hình Home, Nutrition, Workout hiện có.

---

### CHECKPOINT JCOM-02 — BẢNG TIN CỘNG ĐỒNG, KHÁM PHÁ & CHI TIẾT BÀI VIẾT
- **Mục tiêu & User Journey:**
  - Người dùng vào Saman Community từ card R01 → Kích hoạt Shell riêng với **Community Bottom Navigation** 5 tabs.
  - Bảng tin `R03_Community_Feed` hiển thị 3 bộ lọc (*Dành cho bạn*, *Đang theo dõi*, *Hỏi đáp*) và 3 archetype bài đăng (Post ảnh/bữa ăn, Thẻ buổi tập Kinetic, Câu hỏi cộng đồng).
  - Người dùng tương tác Like, Save trực quan với hiệu ứng mượt mà và cập nhật counter ngay lập tức.
  - Chạm vào bài post → Mở `R05_Community_Post_Detail` toàn màn hình (ẩn bottom nav) với thread bình luận lồng nhau và ô nhập bình luận cố định ở chân trang.
  - Chạm tab Khám phá trên nav → Mở `R04_Community_Discover` với lưới ảnh 3 cột, hashtag thịnh hành và danh sách gợi ý theo dõi.
- **Màn hình trong phạm vi:** `R03_Community_Feed`, `R04_Community_Discover`, `R05_Community_Post_Detail`, và `CommunityBottomNavigationBar`.
- **Dependencies & Blockers:**
  - Phụ thuộc vào JCOM-01 (cần điểm vào từ Doorway card của R01).
- **File hiện có cần sửa đổi:**
  - `frontend/lib/config/routes.dart` (Đăng ký route Community).
  - `frontend/lib/config/app_translations.dart` (Bổ sung key dịch thuật Community Feed).
- **File mới đề xuất tạo:**
  - `frontend/lib/features/community/domain/models/community_post.dart`
  - `frontend/lib/features/community/domain/models/community_comment.dart`
  - `frontend/lib/features/community/domain/repositories/community_repository.dart`
  - `frontend/lib/features/community/data/datasources/community_fake_datasource.dart`
  - `frontend/lib/features/community/data/repositories/community_repository_impl.dart`
  - `frontend/lib/features/community/presentation/providers/community_feed_provider.dart`
  - `frontend/lib/features/community/presentation/providers/post_detail_provider.dart`
  - `frontend/lib/features/community/presentation/screens/community_feed_screen.dart` (R03)
  - `frontend/lib/features/community/presentation/screens/community_discover_screen.dart` (R04)
  - `frontend/lib/features/community/presentation/screens/community_post_detail_screen.dart` (R05)
  - `frontend/lib/features/community/presentation/widgets/community_bottom_navigation_bar.dart`
  - `frontend/lib/features/community/presentation/widgets/post_card_view.dart`
  - `frontend/lib/features/community/presentation/widgets/kinetic_workout_attachment_card.dart`
- **Data Mode:** **Fake Integration qua Riverpod DI**. State machine đồng bộ Like/Save/Follow giữa Feed và Detail.
- **Chiến lược kiểm thử:**
  - Widget test kiểm tra đồng bộ Like giữa R03 và R05.
  - Test gửi bình luận rỗng bị vô hiệu hóa; test cuộn phân trang.
- **Điều kiện hoàn thành:** R03, R04, R05 hoạt động trơn tru; Back behavior chính xác.

---

### CHECKPOINT JCOM-03 — LUỒNG TẠO NỘI DUNG MEDIA-FIRST & ĐÍNH KÈM HOẠT ĐỘNG
- **Mục tiêu & User Journey:**
  - Chạm nút **(+)** trên thanh Community Nav → Mở Bottom Sheet *"Tạo nội dung"*.
  - Luồng tạo bài viết ảnh: Chọn ảnh thư viện hoặc camera (`R06A`) → Chỉnh sửa crop 1:1, 4:5, xoay, chỉnh sáng (`R06B`) → Đổi thứ tự album kéo thả và đặt ảnh bìa (`R06C`) → Soạn caption, cấu hình audience/topic/bình luận và bấm "Chia sẻ" (`R06D`).
  - Lối thoát văn bản: Tại R06A chạm "Đăng chỉ với văn bản" → Mở thẳng R06D không có ảnh.
  - Đính kèm hoạt động: Từ R06D hoặc sheet (+) mở `R07_Community_Select_Attachment_Refined`:
    - Tab Buổi tập: Chọn buổi tập đã hoàn thành từ `workoutHistoryProvider`, hiển thị tên và thời lượng, **khối lượng tạ và số hiệp TẮT mặc định**.
    - Tab Bữa ăn: Chọn bữa ăn từ `nutritionProvider`, **calo và macros TẮT mặc định**.
    - Bấm "Đính kèm vào bài viết" → Trả snapshot về composer R06D.
  - Đặt câu hỏi: Chọn "Đặt câu hỏi" từ sheet (+) → Mở `R08_Community_Ask_Question` với dải chip chủ đề bắt buộc và bộ đếm ký tự.
  - Cơ chế bản nháp: Nhấn Đóng bất kỳ lúc nào đều có sheet hỏi lưu nháp an toàn.
- **Màn hình trong phạm vi:** `R06A`, `R06B`, `R06C`, `R06D`, `R07`, `R08`, và Sheet Tạo nội dung.
- **Dependencies & Blockers:**
  - Tích hợp với `ExerciseRepository` (Workout) và `NutritionService` (Nutrition) để lấy danh sách hoạt động thật của người dùng.
- **File hiện có cần sửa đổi:**
  - Không sửa đổi mã nguồn nghiệp vụ của Workout và Nutrition, chỉ gọi provider đọc (Read-only).
- **File mới đề xuất tạo:**
  - `frontend/lib/features/community/domain/models/draft_post.dart`
  - `frontend/lib/features/community/domain/models/attachment_snapshot.dart`
  - `frontend/lib/features/community/presentation/providers/composer_provider.dart`
  - `frontend/lib/features/community/presentation/providers/attachment_picker_provider.dart`
  - `frontend/lib/features/community/presentation/screens/compose/post_select_media_screen.dart` (R06A)
  - `frontend/lib/features/community/presentation/screens/compose/post_edit_media_screen.dart` (R06B)
  - `frontend/lib/features/community/presentation/screens/compose/post_album_order_screen.dart` (R06C)
  - `frontend/lib/features/community/presentation/screens/compose/post_compose_publish_screen.dart` (R06D)
  - `frontend/lib/features/community/presentation/screens/compose/community_select_attachment_screen.dart` (R07)
  - `frontend/lib/features/community/presentation/screens/compose/community_ask_question_screen.dart` (R08)
  - `frontend/lib/features/community/presentation/widgets/create_content_bottom_sheet.dart`
- **Data Mode:** **Fake Publishing + Real Local Attachment Reading**. Đọc dữ liệu workout/meal thật từ local session, lưu bài đăng vào bộ nhớ Feed giả lập.
- **Chiến lược kiểm thử:**
  - Test bảo vệ dữ liệu: Xác minh khi switch tạ tắt, snapshot không chứa weights/reps.
  - Test phục hồi bản nháp: Back và mở lại giữ nguyên caption và ảnh.
- **Điều kiện hoàn thành:** Toàn bộ quy trình tạo bài 4 bước và đính kèm hoạt động không lỗi.

---

### CHECKPOINT JCOM-04 — HỒ SƠ THÀNH VIÊN, THÔNG BÁO, LƯU TRỮ, BẢN NHÁP & HỎI ĐÁP
- **Mục tiêu & User Journey:**
  - Tab Cá nhân trên Community Nav mở `R09_Community_Profile` của chính mình (có nút Chỉnh sửa hồ sơ, menu Đã lưu, Bản nháp).
  - Chạm vào người dùng khác trên feed mở R09 của họ (có nút Theo dõi, Chia sẻ, menu Báo cáo).
  - Chạm vào số Người theo dõi / Đang theo dõi mở `R10_Community_Follow_List`.
  - Tab Thông báo trên Community Nav mở `R11_Community_Notifications` với chấm unread xanh ngọc và bộ lọc thông minh.
  - Menu cá nhân mở `R12_Community_Saved` (bài viết đã bookmark, hoàn tác khi gỡ lưu) và `R13_Community_Drafts` (quản lý bản nháp dở, chạm tiếp tục viết).
  - Nhấn "Chỉnh sửa hồ sơ" mở `R14_Community_Edit_Profile`: đổi avatar (tái sử dụng `AvatarRepository` thật), kiểm tra username khả dụng, cập nhật bio.
  - Chạm vào bài câu hỏi từ Feed hoặc Thông báo mở `R15_Community_Question_Detail`: bình chọn câu trả lời hữu ích, hiển thị câu trả lời được người hỏi lựa chọn, gửi câu trả lời qua composer đáy.
- **Màn hình trong phạm vi:** `R09`, `R10`, `R11`, `R12`, `R13`, `R14`, `R15`.
- **Dependencies & Blockers:**
  - Tái sử dụng `AvatarRepositoryImpl` và backend avatar endpoints đã có sẵn.
- **File mới đề xuất tạo:**
  - `frontend/lib/features/community/presentation/screens/profile/community_profile_screen.dart` (R09)
  - `frontend/lib/features/community/presentation/screens/profile/community_follow_list_screen.dart` (R10)
  - `frontend/lib/features/community/presentation/screens/notifications/community_notifications_screen.dart` (R11)
  - `frontend/lib/features/community/presentation/screens/profile/community_saved_screen.dart` (R12)
  - `frontend/lib/features/community/presentation/screens/profile/community_drafts_screen.dart` (R13)
  - `frontend/lib/features/community/presentation/screens/profile/community_edit_profile_screen.dart` (R14)
  - `frontend/lib/features/community/presentation/screens/qa/community_question_detail_screen.dart` (R15)
- **Data Mode:** Fake Social Store + Live Avatar Service.
- **Chiến lược kiểm thử:**
  - Test cô lập bản nháp R13 theo tài khoản.
  - Test cập nhật avatar R14 đồng bộ toàn app.
- **Điều kiện hoàn thành:** Hoàn tất 18 màn hình giao diện chuẩn thiết kế đã duyệt.

---

### CHECKPOINT JCOM-05 — TÍCH HỢP BACKEND LIVE & KIỂM THỬ XUYÊN SUỐT
- **Mục tiêu:**
  - Xây dựng backend routers trong `backend/routers/journal.py` và `backend/routers/community.py`.
  - Thiết kế collections MongoDB: `journal_articles`, `community_posts`, `community_comments`, `community_interactions`, `community_notifications`.
  - Triển khai middleware kiểm tra `Idempotency-Key` chống tạo bài trùng lặp.
  - Kiểm soát phân quyền `audience: followers` tại database query level.
  - Chuyển đổi Frontend Repository từ Fake sang Live HTTP Client (Dio).
  - Chạy toàn bộ regression test suite: 0 compile errors, 0 analyzer warnings, 0 test failures.
- **Điều kiện hoàn thành:** Hệ thống hoạt động live end-to-end với cơ sở dữ liệu thật.
