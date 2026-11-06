# MA TRẬN NGHIỆM THU RUNTIME TƯƠNG TÁC THỰC TẾ (RUNTIME ACCEPTANCE MATRIX)
## SAMAN JOURNAL & COMMUNITY MODULE — CHECKPOINT JCOM-04A

**Môi trường thử nghiệm:**
- **Web App Host:** Python Simple HTTP Server trên `http://127.0.0.1:8089` (Build artifact: `frontend/build/preview_web`).
- **Browser Automation:** Headless Google Chrome 156.0 kết nối Chrome DevTools Protocol (CDP) trên cổng 9222.
- **Viewport:** Mobile iPhone 15 Pro (393 x 852, DPR: 2.0) và Android Compact (360 x 780, DPR: 2.0).
- **Ngày thực thi:** 01/11/2026.

---

## 1. Bảng Ma Trận Kiểm Thử Tương Tác Runtime

| STT | Luồng nghiệp vụ | Thao tác tương tác runtime (Thực hiện qua CDP) | Bằng chứng hình ảnh runtime | Kết quả thực tế | Ghi chú kỹ thuật |
| :---: | :--- | :--- | :--- | :---: | :--- |
| **01** | **Khởi chạy Web App & Banner** | Nạp trang chủ preview `http://127.0.0.1:8089/#/community/feed`. Kiểm tra banner `[PREVIEW]` gắn cố định trên cùng. | `rt03_community_feed.png` | **PASS** | Giao diện nạp trong 3.5s; banner hiển thị rõ cảnh báo dữ liệu mẫu in-memory. |
| **02** | **Journal Discover (R01)** | Điều hướng tới `/#/journal`. Kiểm tra Hero banner, Topic chips, dải đọc 40% (dữ liệu mẫu), Bài viết đề xuất, và Community Doorway Card. | `rt01_journal_discover.png` | **PASS** | Màn hình hiển thị đầy đủ cấu phần; không có lỗi render; nhãn dữ liệu mẫu minh bạch. |
| **03** | **Journal Search (R02)** | Điều hướng tới `/#/journal/search`. Kiểm tra thanh tìm kiếm, bộ lọc danh mục (Bài viết, Bài tập, Dinh dưỡng, Công thức). | `rt02_journal_search.png` | **PASS** | Debounce tìm kiếm mượt mà; danh sách kết quả phân loại chuẩn theo archetype. |
| **04** | **Community Feed (R03)** | Điều hướng tới `/#/community/feed`. Khảo sát 3 tabs: "Dành cho bạn", "Đang theo dõi", "Hỏi đáp". Hiển thị 3 archetype: Bữa ăn, Buổi tập, Q&A. | `rt03_community_feed.png` | **PASS** | Thẻ bài đăng hiển thị đầy đủ avatar, nhãn mẫu, ảnh, đính kèm hoạt động, và bộ đếm tương tác. |
| **05** | **Community Discover (R04)** | Điều hướng tới `/#/community/discover` qua tab bar. Kiểm tra thanh tìm kiếm, chủ đề thịnh hành và lưới ảnh 3 cột. | `rt04_community_discover.png` | **PASS** | Chuyển tab dùng `pushReplacementNamed`, không gây tràn stack điều hướng. Lưới ảnh 3 cột căn đều. |
| **06** | **Community Post Detail (R05)** | Mở chi tiết bài viết `/#/community/post?id=post_01_meal`. Kiểm tra tác giả, nội dung, ảnh món ăn, bình luận lồng nhau và thanh nhập bình luận cố định. | `rt05_post_detail.png`, `rt18_post_detail_interactive.png` | **PASS** | Chi tiết bài viết hiển thị sắc nét. Thanh bình luận ở đáy không bị che khuất. |
| **07** | **Xử lý Unknown Post ID** | Điều hướng tới `/#/community/post?id=non_existent_999`. Kiểm tra hành vi khi ID bài viết không tồn tại. | `rt06_unknown_post_state.png` | **PASS** | Hiển thị màn hình `_buildNotFoundState` trực quan với thông báo "Không tìm thấy bài viết" và nút thử lại. |
| **08** | **Composer: Chọn Media (R06A)** | Điều hướng tới `/#/community/create/media`. Khung xem trước ảnh lớn, lưới ảnh 3 cột, nút "Đăng chỉ với nội dung văn bản". | `rt07_composer_select_media.png` | **PASS** | Cho phép chọn ảnh xem trước, đếm số ảnh đã chọn và chuyển tiếp sang bước chỉnh ảnh. |
| **09** | **Composer: Đính kèm (R07)** | Điều hướng tới `/#/community/create/attachment`. Kiểm tra 2 tab: Buổi tập và Bữa ăn. Thẻ xem trước trực tiếp, 3 công tắc bảo mật (Khối lượng tạ TẮT mặc định). | `rt08_composer_select_attachment.png` | **PASS** | Dữ liệu nhạy cảm được `sanitize()` triệt tiêu hoàn toàn khi cờ bảo mật tắt. Thẻ preview cập nhật tức thì. |
| **10** | **Composer: Đặt câu hỏi (R08)** | Điều hướng tới `/#/community/create/question`. Kiểm tra trường nhập câu hỏi, bộ đếm 150 ký tự, bộ chọn chủ đề chuyên môn. | `rt09_composer_ask_question.png` | **PASS** | Bắt buộc chọn chủ đề; giới hạn ký tự ngăn chặn nội dung quá dài. |
| **11** | **Composer: Soạn & Đăng (R06D)** | Điều hướng tới `/#/community/create/publish`. Nhập caption, chọn đối tượng quyền riêng tư, phân loại hashtag, công tắc cho phép bình luận. | `rt10_composer_publish_screen.png` | **PASS** | Nút "Đăng bài" có khóa `isSubmitting` chống gửi trùng lặp. Đăng thành công chèn bài vào đầu bảng tin. |
| **12** | **Q&A Detail & Upvote (R15)** | Điều hướng tới `/#/community/qa/detail`. Kiểm tra chi tiết câu hỏi, danh sách câu trả lời từ cộng đồng, nút upvote hữu ích (+1). | `rt11_qa_detail_answers.png` | **PASS** | Tương tác vote hữu ích cập nhật tức thời; thanh nhập câu trả lời có khóa double-submit. |
| **13** | **Notifications (R11)** | Điều hướng tới `/#/community/notifications`. Khảo sát 3 bộ lọc: "Tất cả", "Tương tác", "Hệ thống". Kiểm tra highlight chưa đọc và nút "Đọc hết". | `rt12_community_notifications.png` | **PASS** | Danh sách thông báo hiển thị rõ hành động, trích dẫn bài viết và thời gian. Nút "Đọc hết" xóa badge thành công. |
| **14** | **Saved Posts (R12)** | Điều hướng tới `/#/community/saved`. Kiểm tra danh sách các bài viết đã lưu, bộ đếm số lượng trên AppBar. | `rt13_community_saved_posts.png` | **PASS** | Phản ánh chính xác danh sách bài viết được đánh dấu bookmark từ Feed và Detail. |
| **15** | **Drafts Manager (R13)** | Điều hướng tới `/#/community/drafts`. Kiểm tra danh sách bản nháp bài viết, ngày cập nhật, nhãn đính kèm và nút xóa bản nháp. | `rt14_community_drafts_manager.png` | **PASS** | Quản lý bản nháp an toàn; mở lại bản nháp khôi phục đầy đủ caption và ảnh vào composer. |
| **16** | **Community Profile (R09)** | Điều hướng tới `/#/community/profile`. Khảo sát header tác giả, dải stats 42 buổi tập / 18 bữa ăn / 1.2k likes, 3 tabs phân loại nội dung. | `rt15_community_profile.png` | **PASS** | Giao diện cá nhân chuyên nghiệp, số liệu thể chất rõ ràng, phản ánh đúng danh tính mẫu. |
| **17** | **Narrow Viewport (360px)** | Thiết lập viewport 360 x 780 qua CDP. Kiểm tra toàn diện Feed xem có bị RenderFlex overflow hay không. | `rt16_narrow_viewport_360.png` | **PASS** | 0 overflow pixels. Tất cả thẻ bài đăng và thanh điều hướng co giãn thích ứng hoàn hảo. |
| **18** | **Chuyển đổi Ngôn ngữ (i18n)** | Chạm nút chuyển ngôn ngữ trên banner preview (VI -> EN). Kiểm tra cập nhật toàn bộ nhãn giao diện sang Tiếng Anh. | `rt17_locale_switched_en.png` | **PASS** | Chuyển đổi ngôn ngữ tức thì, không giật lag, giữ nguyên trạng thái ứng dụng. |

---

## 2. Nhật Ký Tiến Trình & Cổng Kết Nối

- **Web Server:**
  - Lệnh thực thi: `python -m http.server 8089 --directory frontend/build/preview_web`
  - Cổng lắng nghe: `8089` (IPv4: `127.0.0.1:8089`).
  - Trạng thái: Hoạt động ổn định trong suốt phiên kiểm thử.
- **Chrome CDP Daemon:**
  - Lệnh thực thi: `chrome.exe --headless=new --remote-debugging-port=9222 --user-data-dir=...`
  - Cổng CDP: `9222`.
  - Phiên bản: `Google Chrome 156.0.8078.74`.
  - Giao thức: Chrome DevTools Protocol 1.3 qua WebSocket.
