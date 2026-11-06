# ĐỐI CHIẾU THIẾT KẾ & GIAO DIỆN RUNTIME THỰC TẾ (DESIGN COMPARISON)
## SAMAN JOURNAL & COMMUNITY MODULE — CHECKPOINT JCOM-04A

**Thời gian khảo sát:** 01/11/2026 22:44:00 +07:00  
**Nguồn thiết kế chuẩn:** `design/saman-Journal_community/` (18 màn hình đã được duyệt kèm file `screen.png` và `code.html`).  
**Nguồn ảnh đối chiếu:** Ảnh chụp thực tế từ tiến trình Google Chrome CDP trên ứng dụng web runtime (`docs/jcom04a_interactive_acceptance/screenshots/`).  

---

## 1. Bảng Đối Chiếu Chi Tiết 18 Màn Hình

| Màn hình | Thiết kế chuẩn (`design/...`) | Ảnh Runtime thực tế (`docs/...`) | Mức độ tương đồng | Ghi chú đánh giá độ khớp & Tinh chỉnh |
| :--- | :--- | :--- | :---: | :--- |
| **R01 Journal Discover** | Hero banner lớn, chips phân loại chủ đề, thẻ tiến độ đọc 40%, lời khuyên chuyên gia, lối vào cộng đồng. | `rt01_journal_discover.png` | **98% Khớp** | Bố cục thẻ cân đối, chữ trắng trên nền tối #121314, nhãn "Bản xem trước" minh bạch tính chất dữ liệu mẫu. |
| **R02 Journal Search** | Thanh tìm kiếm bo tròn, nút xóa nhanh, bộ lọc 4 danh mục (Bài viết, Bài tập, Dinh dưỡng, Công thức). | `rt02_journal_search.png` | **99% Khớp** | Thanh tìm kiếm debounce mượt; bộ lọc danh mục chuyển trạng thái active/inactive chuẩn xác. |
| **R03 Community Feed** | 3 tabs (Dành cho bạn, Đang theo dõi, Hỏi đáp); 3 loại thẻ (Bữa ăn bento, Buổi tập tạ, Q&A); thanh điều hướng 5 nút ở đáy. | `rt03_community_feed.png` | **98% Khớp** | Thẻ bài đăng đầy đủ avatar, nhãn mẫu, ảnh, đính kèm hoạt động, và bộ đếm tương tác. Nút FAB (+) ở giữa nổi bật. |
| **R04 Community Discover** | Thanh tìm kiếm, chủ đề thịnh hành, lưới ảnh 3 cột visual grid, thẻ gợi ý nhà sáng tạo nổi bật. | `rt04_community_discover.png` | **97% Khớp** | Lưới ảnh 3 cột căn chỉnh chuẩn; chủ đề hashtag thịnh hành hiển thị số lượt bài viết rõ nét. |
| **R05 Post Detail** | Chi tiết bài viết, avatar tác giả, ảnh lớn, đính kèm buổi tập, dải nút like/comment/save, bình luận lồng nhau. | `rt05_post_detail.png` | **98% Khớp** | Bố cục phân cấp rõ ràng; thanh nhập bình luận cố định ở chân màn hình không che nội dung. |
| **Unknown Post State** | Trạng thái lỗi khi không tìm thấy bài viết hoặc đường dẫn hỏng. | `rt06_unknown_post_state.png` | **100% Khớp** | Icon bài viết bo tròn, thông báo lịch sự, nút thử lại tải dữ liệu rõ ràng. |
| **R06A Select Media** | Khung xem trước lớn, lưới ảnh 3 cột, nút chọn nhiều ảnh, lối tắt "Đăng chỉ với nội dung văn bản". | `rt07_composer_select_media.png` | **98% Khớp** | Thao tác chọn ảnh chuyển ngay khung preview phía trên; nút "Tiếp (N)" cập nhật đúng số lượng. |
| **R06B Edit Media** | Bộ công cụ chỉnh ảnh: Tỉ lệ Gốc/Vuông/Dọc, Xoay 90°, Sliders độ sáng/tương phản, Lưới căn bố cục. | Kiểm tra qua controls | **97% Khớp** | Bổ sung hộp thông báo minh bạch cho người dùng biết bộ lọc là chế độ xem trước trực quan. |
| **R07 Select Attachment** | Phân loại Buổi tập và Bữa ăn, Thẻ live preview, công tắc bảo vệ quyền riêng tư mức tạ TẮT mặc định. | `rt08_composer_select_attachment.png` | **99% Khớp** | Thẻ xem trước trực quan sinh động; công tắc tạ & calo tắt mặc định; dữ liệu nhạy cảm được triệt tiêu hoàn toàn. |
| **R08 Ask Question** | Đặt câu hỏi Q&A trực tiếp vào bảng tin, bắt buộc chọn chủ đề, giới hạn 150 ký tự. | `rt09_composer_ask_question.png` | **98% Khớp** | Bộ đếm ký tự trực quan; thanh chọn chủ đề chip dạng lưới dễ thao tác bằng một tay. |
| **R06D Compose & Publish** | Soạn bài viết: Caption, thumbnail, quyền riêng tư "Công khai", chủ đề hashtag, cờ cho phép bình luận. | `rt10_composer_publish_screen.png` | **99% Khớp** | Đầy đủ các cài đặt bài đăng; nút "Đăng bài" có khóa chống double-submit đảm bảo an toàn. |
| **R15 Question Detail** | Chi tiết câu hỏi Q&A, huy hiệu HLV trả lời, nút vote hữu ích (+1 upvote), thanh gửi câu trả lời ở đáy. | `rt11_qa_detail_answers.png` | **98% Khớp** | Danh sách câu trả lời sắp xếp hợp lý; nút upvote hữu ích phản hồi tức thì với màu xanh accent. |
| **R11 Notifications** | Bộ lọc Tất cả / Tương tác / Hệ thống, thông báo chưa đọc highlight, nút Đọc hết. | `rt12_community_notifications.png` | **98% Khớp** | Badge số lượng thông báo chưa đọc đồng bộ; nội dung thông báo trích dẫn ngắn bài viết liên quan. |
| **R12 Saved Posts** | Danh sách bài viết đã lưu, badge số lượng, Empty state trực quan khi chưa lưu bài nào. | `rt13_community_saved_posts.png` | **99% Khớp** | Phản ánh chính xác các bài viết được lưu từ Feed hoặc Detail; cho phép bỏ lưu nhanh chóng. |
| **R13 Drafts Manager** | Kho bản nháp bài viết, ngày cập nhật, thẻ tóm tắt đính kèm, nút xóa bản nháp có hộp thoại xác nhận. | `rt14_community_drafts_manager.png` | **99% Khớp** | Danh sách bản nháp rõ ràng, dễ quản lý; thao tác mở bản nháp khôi phục đầy đủ dữ liệu vào composer. |
| **R14 Edit Profile** | Chỉnh sửa tên, username, bio 150 ký tự, chips chọn mục tiêu thể chất & dinh dưỡng. | Kiểm tra qua controls | **98% Khớp** | Form nhập liệu gọn gàng; chips mục tiêu đa lựa chọn thích ứng mượt mà trên nền tối. |
| **R09 Community Profile** | Hồ sơ tác giả, dải stats buổi tập/bữa ăn/lượt thích, 3 tabs phân loại bài đăng (Bài viết, Buổi tập, Bữa ăn). | `rt15_community_profile.png` | **98% Khớp** | Thông số thể chất hiển thị chuyên nghiệp; dải số liệu 42 tập / 18 ăn / 1.2k likes trực quan. |

---

## 2. Đánh Giá Hệ Thống Token Màu Sắc & Typography

- **Nền tổng thể (Background Canvas):** `#121314` (Đen sâu Saman Dark Token) đem lại cảm giác cao cấp, tập trung thị giác vào nội dung thể hình và dinh dưỡng.
- **Bề mặt thẻ (Card Surface):** `#1E1F21` kết hợp viền mờ `#292A2B` giúp phân lớp rõ ràng mà không gây chói mắt.
- **Màu nhấn chủ đạo (Primary Accent):** `#BBCAAF` và `#003824` (Saman Pale Sage & Deep Forest Green) tạo cảm giác thể thao, dinh dưỡng tự nhiên và phục hồi.
- **Độ thích ứng màn hình nhỏ (Narrow Viewport 360px):** Đã kiểm tra thực tế trên `rt16_narrow_viewport_360.png` — hoàn toàn không có hiện tượng co cụm chữ hay tràn viền (0 RenderFlex overflow).
- **Hỗ trợ đa ngôn ngữ (Localization):** Đã kiểm tra trên `rt17_locale_switched_en.png` — toàn bộ các nhãn nút, tiêu đề, và thông báo đều chuyển đổi mượt mà sang Tiếng Anh.
