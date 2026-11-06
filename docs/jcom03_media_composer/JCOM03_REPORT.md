# BÁO CÁO NGHIỆM THU JCOM-03 — MEDIA-FIRST COMPOSE & ACTIVITY ATTACHMENTS

**Dự án:** Saman App — Community Module  
**Checkpoint:** JCOM-03 (Media-First Compose & Activity Attachments)  
**Thời gian thực thi:** 01/11/2026  
**Trạng thái nghiệm thu:** **PASS (Frontend Verified & Test-Rendered)**  
**Dữ liệu thực thi:** Fake Datasource (In-memory storage) — 0 live backend routes  

---

## 1. Mục tiêu và Phạm vi thực thi

JCOM-03 triển khai bộ công cụ soạn thảo nội dung thể hình media-first, đính kèm hoạt động và bảo vệ dữ liệu riêng tư (R06A–R06D, R07 Refined, R08, Bottom Sheet & State Machine):

1. **R06A — Post Select Media (`PostSelectMediaScreen`)**:
   - Khung xem trước media kích thước lớn (interactive aspect ratio switch).
   - Chọn album / folder ("Gần đây"), chuyển chế độ chọn nhiều ảnh.
   - Lưới ảnh 3 cột với bộ đếm chọn nhiều `Tiếp (N)`.
   - Lối tắt "Đăng chỉ với nội dung văn bản" chuyển thẳng tới R06D mà không cần chọn ảnh.
2. **R06B — Post Edit Media (`PostEditMediaScreen`)**:
   - Tỉ lệ khung hình: Gốc (`orig`), Vuông (`1:1`), Dọc (`4:5`).
   - Xoay ảnh 90° từng lần nhấn (`rotation % 360`).
   - Bảng điều khiển ánh sáng: Thanh trượt Độ sáng & Tương phản (-50 đến +50) qua `ColorFilter.matrix`.
   - Lưới căn bố cục một phần ba (Rule of Thirds 3x3 overlay) bật/tắt linh hoạt.
3. **R06C — Post Album Order (`PostAlbumOrderScreen`)**:
   - Lưới sắp xếp thứ tự ảnh trong album 2 cột.
   - Huy hiệu "Ảnh bìa" cố định trên ảnh đầu tiên.
   - Thao tác di chuyển lên/xuống và gỡ bỏ từng ảnh khỏi album.
4. **R07 Refined — Activity Attachment (`CommunitySelectAttachmentScreen`)**:
   - Hai tab phân loại: Buổi tập (`workout`) và Bữa ăn (`meal`).
   - Danh sách hoạt động gần đây đồng bộ từ Kinetic (Workout) và Nutrition (Meal).
   - Thẻ xem trước trực tiếp cấu trúc bài đăng (Live Feed Card Preview).
   - **Bảo mật & Quyền riêng tư bắt buộc (Privacy-by-Default)**:
     - Tắt mặc định công khai khối lượng tạ, số hiệp (`includeLoadOrMacros = false`).
     - Tắt mặc định chi tiết calories & macros dinh dưỡng.
     - Người dùng phải chủ động bật mới xuất hiện trong payload đăng bài.
5. **R06D — Post Compose & Publish (`PostComposePublishScreen`)**:
   - Nhập chú thích (caption) kèm thanh đếm ký tự.
   - Thumbnail ảnh kèm thẻ đính kèm hoạt động có thể gỡ bỏ.
   - Lựa chọn quyền riêng tư đối tượng: "Công khai", "Người theo dõi", "Chỉ mình tôi".
   - Phân loại chủ đề hashtag: `#BữaĂn`, `#TậpLuyện`, `#PhụcHồi`, `#ChiaSẻ`, `#KỷLuật`.
   - Bật/tắt cho phép bình luận.
   - Khóa double-submit (`isSubmitting` guard) chống tạo bài trùng lặp.
6. **R08 — Community Ask Question (`CommunityAskQuestionScreen`)**:
   - Đặt câu hỏi Q&A trực tiếp vào bảng tin cộng đồng.
   - Bắt buộc chọn 1 chủ đề chuyên môn (Tập luyện, Dinh dưỡng, Phục hồi,...).
   - Tiêu đề câu hỏi giới hạn 150 ký tự kèm cảnh báo amber.
   - Phân loại đúng `CommunityPostType.qa` và hiển thị trên tab "Hỏi đáp" của Feed.
7. **CreateContentBottomSheet (`create_content_bottom_sheet.dart`)**:
   - 4 ô lựa chọn theo chuẩn Material 3: Bài viết, Buổi tập, Bữa ăn, Đặt câu hỏi.
   - Tích hợp trực tiếp vào nút trung tâm `+` của `CommunityBottomNavigationBar`.
8. **Draft State Machine & Discard Dialog (`DraftDiscardDialog`)**:
   - Hộp thoại xác nhận khi người dùng thoát màn hình có nội dung chưa lưu.
   - Ba lựa chọn an toàn: "Lưu bản nháp", "Hủy bỏ thay đổi", "Tiếp tục chỉnh sửa".

---

## 2. Bảng bằng chứng Render Screenshot (JCOM-03)

Toàn bộ ảnh chụp giao diện được lưu trữ tại `docs/jcom03_media_composer/screenshots/`:

| Tên ảnh | Màn hình | Mô tả chi tiết giao diện |
| :--- | :--- | :--- |
| `c14_r06a_select_media.png` | R06A | Khung xem trước lớn, lưới ảnh 3 cột, nút "Đăng chỉ với nội dung văn bản" |
| `c15_r06b_edit_media.png` | R06B | Công cụ chỉnh ảnh: Tỉ lệ Gốc/Vuông/Dọc, Xoay 90°, Sliders độ sáng/tương phản |
| `c16_r06c_album_order.png` | R06C | Sắp xếp thứ tự album, huy hiệu "Ảnh bìa", hướng dẫn bố cục |
| `c17_r07_select_attachment_workout.png` | R07 | Tab Buổi tập: Thẻ live preview, công tắc bảo vệ quyền riêng tư mức tạ TẮT mặc định |
| `c18_r07_select_attachment_meal.png` | R07 | Tab Bữa ăn: Danh sách Bento/Matcha, công tắc calo & macros TẮT mặc định |
| `c19_r06d_compose_publish.png` | R06D | Soạn bài viết: Caption, thumbnail, quyền riêng tư "Công khai", chủ đề bài viết |
| `c20_r08_ask_question.png` | R08 | Đặt câu hỏi Q&A: Bắt buộc chọn chủ đề, giới hạn 150 ký tự |
| `c21_create_content_bottom_sheet.png` | Modal | Bottom sheet 4 lựa chọn tạo nội dung, layout thích ứng không tràn |

---

## 3. Kết quả Kiểm thử Tự động (15/15 PASS)

Bộ kiểm thử `frontend/test/features/community/community_compose_flow_test.dart` đã thực thi và vượt qua toàn bộ 15 trường hợp kiểm thử:

1. `Recent activities are fetched correctly for Workout and Meal` — PASS
2. `Privacy toggles in AttachmentSnapshot default to private` — PASS
3. `Publishing post creates record in repository` — PASS
4. `Publishing question creates record in repository with QA tag` — PASS
5. `Draft saving and deletion cycle works properly` — PASS
6. `Composer state transitions: aspect ratio, rotation, and reset` — PASS
7. `Double submission lock prevents concurrent publishes` — PASS
8. `CreateContentBottomSheet renders 4 action items` — PASS
9. `PostSelectMediaScreen allows toggling media selection` — PASS
10. `PostEditMediaScreen rotates image on rotate button click` — PASS
11. `PostAlbumOrderScreen renders order slots and instructions` — PASS
12. `CommunitySelectAttachmentScreen switches tabs and updates privacy toggles` — PASS
13. `PostComposePublishScreen inputs caption and shows privacy sheet` — PASS
14. `CommunityAskQuestionScreen validates required topic before publishing` — PASS
15. `DraftDiscardDialog renders all 3 actions` — PASS

**Analyzer Result:**
- `flutter analyze lib/features/community test/features/community`: **0 issues found**!

---

## 4. Xác nhận Tính trung thực (Honesty & Privacy Compliance)

- **Banner dữ liệu mẫu**: Màn hình R06A hiển thị rõ banner: *"Bản xem trước giao diện • Thư viện ảnh mẫu"*.
- **Quyền riêng tư mặc định (Privacy-by-Default)**:
  - Trường `includeLoadOrMacros` trên `PostAttachmentSnapshot` luôn được khởi tạo là `false`.
  - Nếu người dùng không chủ động gạt bật công tắc, các trường thông tin nhạy cảm (mức tạ, số set, calo, macro) hoàn toàn không được gửi lên payload bài đăng.
- **Data Mode**: Toàn bộ luồng đăng bài, lưu nháp, đính kèm hoạt động chạy độc lập trên `CommunityFakeDatasource`. Không kết nối live database hoặc FastAPI backend trong checkpoint này.
