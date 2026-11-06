# KIỂM KÊ TOÀN DIỆN 18 MÀN HÌNH THIẾT KẾ ĐÃ DUYỆT
## SAMAN JOURNAL & STANDALONE SAMAN COMMUNITY

Tài liệu này tổng hợp chi tiết hiện trạng thiết kế, phiên bản chuẩn, thành phần giao diện, luồng vào/ra, yêu cầu dữ liệu và tình trạng mã nguồn cho toàn bộ 18 màn hình đã được phê duyệt.

---

## 1. BẢNG TỔNG HỢP KIỂM KÊ 18 MÀN HÌNH

| ID | Tên màn hình / Chức năng | Thư mục thiết kế thực tế | Phiên bản chuẩn được duyệt | Tình trạng mã nguồn hiện tại |
|---|---|---|---|---|
| **R01** | Journal Discover (Trang chủ Journal) | `r01_journal_discover` | Bản CP-01 (3 tab, hero card, doorway sang Community) | **Chưa có** (Chỉ có card tĩnh ở Home) |
| **R02** | Journal Search (Tìm kiếm kiến thức) | `r02_journal_search` | Bản CP-01 (Tìm bài viết, bài tập, món ăn; không ra post) | **Chưa có** |
| **R03** | Community Feed (Bảng tin mạng xã hội) | `r03_community_feed` | Bản CP-01 / CP-03 (Feed 3 tabs, 3 định dạng post, bottom nav) | **Chưa có** |
| **R04** | Community Discover (Khám phá mạng xã hội) | `r04_community_discover` | Bản CP-01 (Search UGC, grid 3 cột, trending hashtag, follow) | **Chưa có** |
| **R05** | Community Post Detail (Chi tiết bài viết & bình luận) | `r05_community_post_detail` | Bản CP-01 (Pinned composer, thread thảo luận, badge Tác giả) | **Chưa có** |
| **R06A** | Chọn ảnh & Media (Media Picker) | `r06a_post_select_media` | Bản CP-02 Polish (Màu dịu, số thứ tự album, thoát văn bản) | **Chưa có** |
| **R06B** | Chỉnh ảnh & Cắt góc (Media Editor) | `r06b_post_edit_media` | Bản CP-02 Polish (Preview lớn, 3 tỉ lệ crop, slider sáng/tương phản) | **Chưa có** |
| **R06C** | Sắp xếp album (Album Reorder) | `r06c_post_album_order` | Bản CP-02 Polish (Kéo thả, đặt ảnh bìa số 1, xóa/thêm ảnh) | **Chưa có** |
| **R06D** | Soạn nội dung & Chia sẻ (Post Compose) | `r06d_post_compose_publish` | Bản CP-02 Polish (Header Chia sẻ duy nhất, thumbnail nhỏ, settings) | **Chưa có** |
| **R07** | Chọn hoạt động đính kèm (Attachment Picker) | `r07_community_select_attachment_refined` | Bản CP-02 Refined cuối (2 tab Buổi tập/Bữa ăn, tạ/hiệp tắt mặc định) | **Chưa có** (Có nguồn workout/meal riêng) |
| **R08** | Đặt câu hỏi thảo luận (Ask Question) | `r08_community_ask_question` | Bản CP-02 Polish (Header duy nhất, chọn 1 chủ đề, đếm ký tự) | **Chưa có** |
| **R09** | Hồ sơ cộng đồng (Community Profile) | `r09_community_profile` | Bản CP-02 / CP-03 (Stats, bài viết/hỏi đáp, menu Đã lưu/Bản nháp) | **Chưa có** (Chỉ có Profile sức khỏe chính) |
| **R10** | Danh sách theo dõi (Followers & Following) | `r10_community_follow_list` | Bản CP-02 Polish (2 tab Follower/Following, search, quan hệ viewer) | **Chưa có** |
| **R11** | Thông báo cộng đồng (Notifications) | `r11_community_notifications` | Bản CP-03 Polish (Nhóm Hôm nay/Trước đó, 3 filter, unread state) | **Chưa có** |
| **R12** | Bài viết đã lưu (Community Saved) | `r12_community_saved` | Bản CP-03 Polish (Riêng tư, grid 2 cột, không trộn bài Journal) | **Chưa có** |
| **R13** | Quản lý bản nháp (Private Drafts) | `r13_community_drafts` | Bản CP-03 Polish (Riêng tư theo user, phục hồi R06D/R08, xóa nháp) | **Chưa có** |
| **R14** | Chỉnh sửa hồ sơ cộng đồng (Edit Profile) | `r14_community_edit_profile` | Bản CP-03 Polish (Nút Lưu trên header, đổi avatar, username check) | **Chưa có** (Tái sử dụng Avatar upload) |
| **R15** | Thảo luận / Chi tiết hỏi đáp (Q&A Detail) | `r15_community_question_detail` | Bản CP-03 Polish (Bình chọn hữu ích, câu trả lời được người hỏi chọn) | **Chưa có** |

---

## 2. CHI TIẾT ĐẶC TẢ TỪNG MÀN HÌNH (R01 — R15)

### R01 — Journal Discover (Khám phá tri thức Saman)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r01_journal_discover/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-01 Note §5 & PRD v3.0 §4.1.
- **Thành phần chính:**
  - Header: Nút Quay lại (`←`) về Home, Tiêu đề `Saman Journal`, Nút Bookmark bài viết đã lưu, Avatar người dùng.
  - Thanh tab điều hướng nội bộ: 3 tab duy nhất (`Khám phá` [active], `Thư viện`, `Cẩm nang`). Tuyệt đối không có tab Community.
  - Search trigger input dạng nút bấm: Placeholder *"Tìm kiến thức, bài tập, món ăn…"*, chạm vào mở mượt sang R02.
  - Hero Editorial Card: Ảnh 16:10 phục hồi cơ bắp, badge `PHỤC HỒI`, tiêu đề *"Phục hồi tốt hơn sau buổi tập chân"*, `4 phút đọc`.
  - Topic chips: Dải cuộn ngang (*Tất cả, Tập luyện, Dinh dưỡng, Phục hồi, Thói quen*).
  - Tiếp tục đọc (Resume Reading): Card tiến độ đọc dở (*"Hiểu calories và các chất dinh dưỡng"*, 40%, còn 3 phút).
  - Thư viện tri thức: 2 card đại diện (*"Bài tập & lịch tập"* [128 chuyển động], *"Thực phẩm & công thức"* [240+ dữ liệu]).
  - Cửa ngõ sang Community (*Community Doorway Card*): *"Chia sẻ hành trình. Cùng nhau tiến bộ"* kèm nút CTA mở R03.
- **Điểm vào / Điểm ra:**
  - Điểm vào: Chạm card Saman Journal ở Home Screen (Carousel `saman_picks_carousel.dart`).
  - Điểm ra: Chạm ô Search → R02; Chạm Doorway card → R03; Chạm nút Back → Quay lại Home.
- **Sheets & Dialogs:** Bottom sheet danh mục chủ đề khi cuộn sâu (nếu cần).
- **Yêu cầu dữ liệu & State:**
  - `JournalArticle` (id, title, summary, topic, readTimeMinutes, coverImageUrl, isBookmarked).
  - `ReadingHistory` (articleId, progressPercent, remainingMinutes).
  - State: Loading, Loaded, Error/Retry.
- **Tình trạng mã nguồn:** Chưa có.

---

### R02 — Journal Search (Tìm kiếm kiến thức, bài tập & thực phẩm)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r02_journal_search/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-01 Note §6 & PRD v3.0 §4.1.
- **Thành phần chính:**
  - Header: Nút Quay lại về R01, Ô nhập từ khóa (có nút Clear `✕`), nút Lọc nâng cao.
  - Thanh chip phân loại: *Tất cả*, *Bài viết*, *Bài tập*, *Thực phẩm*, *Công thức*.
  - Kết quả phân nhóm:
    - Nhóm Bài viết: hiển thị tiêu đề, thời lượng đọc, tag.
    - Nhóm Thực phẩm: hiển thị tên thực phẩm, tick chính thức, chỉ số đạm/calo trên 100g. Nút `+` mở xem chi tiết hoặc xác nhận khẩu phần, không tự ý ghi nhật ký bằng một chạm.
    - Nhóm Bài tập: hiển thị bài tập chuẩn hóa, cơ bắp tác động.
    - Saman Advice Card: Lời khuyên khoa học ngữ cảnh theo từ khóa.
- **Điểm vào / Điểm ra:**
  - Điểm vào: Chạm thanh tìm kiếm tại R01.
  - Điểm ra: Chạm kết quả bài tập → mở chi tiết bài tập hiện có; Chạm kết quả thực phẩm → mở chi tiết thực phẩm hiện có; Nút Back → về R01 (giữ nguyên scroll).
- **Sheets & Dialogs:** Sheet lọc chuyên sâu (calo, nhóm cơ, thời gian đọc).
- **Yêu cầu dữ liệu & State:**
  - Query state, Debounce timer (300ms), Active category filter.
  - State: Initial/Recent searches, Searching/Loading, Results, Empty ("Không tìm thấy kết quả phù hợp"), Error/Retry.
- **Tình trạng mã nguồn:** Chưa có.

---

### R03 — Community Feed (Bảng tin mạng xã hội thể thao)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r03_community_feed/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-01 Note §7 & PRD v3.0 §4.2.
- **Thành phần chính:**
  - Header: Nút Back (`←`) về Journal, Tiêu đề `Saman Community` có chỉ báo online tinh tế, Icon Direct Message (tương lai, không active).
  - Feed Tabs: 3 tab (*Dành cho bạn*, *Đang theo dõi*, *Hỏi đáp*).
  - 3 Archetypes bài đăng:
    1. Post Bữa ăn / Ảnh: Tác giả, avatar, timestamp, ảnh 4:3, macro badge (`42g Protein`, `480 kcal`), text caption, Like/Comment/Save bar.
    2. Post Thẻ buổi tập: Thẻ **Saman Kinetic Workout Card** (`BUỔI TẬP ĐÃ HOÀN THÀNH`, *Upper Body Hypertrophy*, 45 phút, 5 bài, 12 hiệp).
    3. Post Câu hỏi cộng đồng: Tiêu đề câu hỏi, tag chủ đề, đếm phản hồi, nút *"Tham gia thảo luận →"* dẫn sang R15.
  - Thanh **Community Bottom Navigation** (5 tabs: Bảng tin [active], Khám phá, [+] Tạo bài, Thông báo, Cá nhân).
- **Điểm vào / Điểm ra:**
  - Điểm vào: Doorway card từ R01.
  - Điểm ra: Chạm bài post → R05; Chạm bài câu hỏi → R15; Chạm avatar/tác giả → R09; Chạm tab Nav → R04, sheet (+), R11, R09; Back → về R01.
- **Sheets & Dialogs:** Bottom sheet (+) Tạo nội dung; Sheet báo cáo bài viết.
- **Yêu cầu dữ liệu & State:**
  - `CommunityPost` (id, author, type, content, mediaUrls, attachmentSnapshot, likeCount, isLiked, commentCount, saveCount, isSaved, audience).
  - State: Pull-to-refresh, Paging (cursor/page), Empty state ("Chưa có bài viết mới"), Error/Retry.
- **Tình trạng mã nguồn:** Chưa có.

---

### R04 — Community Discover (Khám phá bài viết, chủ đề & thành viên)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r04_community_discover/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-01 Note §8 & PRD v3.0 §4.2.
- **Thành phần chính:**
  - Ô tìm kiếm: *"Tìm bài viết, chủ đề, thành viên…"*, hàng chip danh mục (*Tất cả, Tập luyện, Bữa ăn, Công thức, Hỏi đáp*).
  - Lưới ảnh 3 cột (Photo Grid): Hiển thị khoảnh khắc thể thao, ảnh bữa ăn, icon indicator nếu bài có album nhiều ảnh.
  - Chủ đề thịnh hành (Trending Hashtags): Danh sách hashtag có tỷ lệ quan tâm (`#MealPrepCuoiTuan`, `#TangCoGiamMo`).
  - Gợi ý theo dõi (Who to follow): Card thành viên kèm nút `+ Theo dõi` / `Đang theo dõi`.
  - Giữ nguyên Community Bottom Nav (Tab Khám phá active).
- **Điểm vào / Điểm ra:**
  - Điểm vào: Tab Khám phá trên thanh Community Bottom Nav.
  - Điểm ra: Chạm ô ảnh trong lưới → R05 đúng postId; Chạm thành viên → R09 đúng userId; Chạm hashtag → Lọc bài theo hashtag.
- **Sheets & Dialogs:** Sheet bộ lọc tìm kiếm.
- **Yêu cầu dữ liệu & State:**
  - Search query, Grid posts paging, Trending topics list, Follow recommendations list.
- **Tình trạng mã nguồn:** Chưa có.

---

### R05 — Community Post Detail (Chi tiết bài viết & Bình luận)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r05_community_post_detail/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-01 Note §9 & PRD v3.0 §4.2.
- **Thành phần chính:**
  - Header: Nút Back, Bookmark icon, Menu ba chấm (chia sẻ, báo cáo). Không có bottom navigation.
  - Nội dung bài viết đầy đủ: Tác giả, avatar, caption đầy đủ, ảnh/album hiển thị sắc nét, macro badge hoặc workout attachment.
  - Danh sách bình luận phân cấp: Bình luận gốc, phản hồi lồng 1 cấp, badge `Tác giả` xanh ngọc cho chủ bài viết.
  - Pinned Composer ở đáy: Nhập bình luận, nút emoji, nút gửi (tự disable khi rỗng hoặc đang submit). Tôn trọng bàn phím và safe area.
- **Điểm vào / Điểm ra:**
  - Điểm vào: Chạm card bài viết từ R03, R04, R09, R11, R12.
  - Điểm ra: Chạm avatar → R09; Back → Quay lại đúng màn hình và vị trí cuộn đã gọi.
- **Sheets & Dialogs:** Sheet menu bình luận (Xóa/Báo cáo), Sheet xác nhận xóa.
- **Yêu cầu dữ liệu & State:**
  - `PostDetail` kèm `List<Comment>` (id, author, content, createdAt, parentId, replies).
  - State: Paging comments, Submit comment in-flight, Optimistic like/save, Rollback on failure.
- **Tình trạng mã nguồn:** Chưa có.

---

### R06A — Chọn ảnh & Media (Media Picker)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r06a_post_select_media/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-02 Note §5 & PRD v3.0 §4.3 (Bản cuối màu dịu, 1 header).
- **Thành phần chính:**
  - Header: Nút Đóng (`✕`), Tiêu đề `Bài viết mới`, Text action `Tiếp` (sáng ngọc `#8AD8BD`, chỉ bật khi chọn ≥ 1 ảnh).
  - Vùng Preview lớn ở nửa trên: Hiển thị ảnh đang chọn hiện tại.
  - Thanh công cụ giữa: Dropdown album *"Gần đây"*, nút *"Chọn nhiều"*.
  - Lưới thư viện ảnh 3 cột: Ô đầu tiên là Camera chụp ảnh mới; các ô tiếp theo có huy hiệu số thứ tự album (`1`, `2`) nền emerald `#08664F`.
  - Lối thoát văn bản chân trang: Link *"Đăng chỉ với nội dung văn bản →"* chuyển thẳng sang R06D mà không bắt buộc chọn ảnh.
- **Điểm vào / Điểm ra:**
  - Điểm vào: Chọn "Bài viết" từ sheet (+) Tạo nội dung.
  - Điểm ra: Nhấn "Tiếp" → R06B; Nhấn "Đăng chỉ với văn bản" → R06D; Nhấn "Đóng" → Hỏi lưu nháp hoặc hủy.
- **Sheets & Dialogs:** Dialog xin quyền truy cập ảnh/camera, Sheet lưu bản nháp khi đóng.
- **Yêu cầu dữ liệu & State:**
  - `DraftPost` (draftId, selectedMediaList, isMultiSelect, textOnlyMode).
- **Tình trạng mã nguồn:** Chưa có.

---

### R06B — Chỉnh ảnh & Cắt góc (Media Editor)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r06b_post_edit_media/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-02 Note §6 & PRD v3.0 §4.3 (Bản cuối màu dịu, 1 header).
- **Thành phần chính:**
  - Header: Nút Back (`←`), Tiêu đề `Chỉnh ảnh`, Text action `Tiếp`.
  - Khung ảnh trung tâm: Hiển thị ảnh đang chỉnh sửa với tỷ lệ crop trực quan.
  - Dải thumbnail album bên dưới: Chạm thumbnail để đổi ảnh đang chỉnh.
  - Bộ công cụ Crop: 3 chế độ cố định (*Gốc*, *Vuông 1:1*, *Dọc 4:5*) và nút xoay ảnh 90°.
  - Slider điều chỉnh: Thanh trượt *"Độ sáng"* và *"Độ tương phản"*, nút *"Đặt lại"* xuất hiện khi có chỉnh sửa.
- **Điểm vào / Điểm ra:**
  - Điểm vào: Nhấn "Tiếp" từ R06A.
  - Điểm ra: Nhấn "Tiếp" → R06D; Chạm nút album reorder → R06C; Back → về R06A (giữ selections).
- **Sheets & Dialogs:** Cảnh báo khi reset ảnh.
- **Yêu cầu dữ liệu & State:**
  - `MediaEditState` (mediaId, cropMode, rotationAngle, brightness, contrast).
- **Tình trạng mã nguồn:** Chưa có.

---

### R06C — Sắp xếp album (Album Reorder)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r06c_post_album_order/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-02 Note §7 & PRD v3.0 §4.3.
- **Thành phần chính:**
  - Header: Nút Back, Tiêu đề `Sắp xếp ảnh`, Text action `Xong`.
  - Lưới thumbnail kéo thả (Drag & Drop): Đánh số thứ tự từng ảnh trong album.
  - Huy hiệu Ảnh bìa: Ảnh số 1 tự động gắn nhãn `Ảnh bìa`.
  - Thao tác phụ: Nút gỡ bỏ (`✕`) trên từng ảnh, ô viền đứt nét `+ Thêm ảnh`.
- **Điểm vào / Điểm ra:**
  - Điểm vào: Mở từ R06B hoặc mở từ thumbnail tại R06D.
  - Điểm ra: Nhấn "Xong" → Áp dụng thứ tự và quay lại màn hình gọi; Back → Hủy thay đổi thứ tự chưa lưu.
- **Sheets & Dialogs:** Xác nhận xóa ảnh nếu ảnh bị xóa là ảnh cuối cùng.
- **Yêu cầu dữ liệu & State:**
  - `List<MediaItem>` với thứ tự index được cập nhật.
- **Tình trạng mã nguồn:** Chưa có.

---

### R06D — Soạn nội dung & Chia sẻ (Post Compose & Publish)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r06d_post_compose_publish/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-02 Note §8 & PRD v3.0 §4.3 (Header Chia sẻ duy nhất, không lặp CTA).
- **Thành phần chính:**
  - Header: Nút Back, Tiêu đề `Bài viết mới`, Text action chính `Chia sẻ` (`#8AD8BD` / `#54C7A5`).
  - Vùng soạn thảo: Avatar tác giả, Tên tác giả, Ô nhập caption tự do.
  - Thumbnail album nhỏ gọn đặt cạnh caption: Có badge số lượng ảnh (chạm mở R06C). Nếu bài chỉ có chữ, ẩn vùng thumbnail.
  - Lightweight Settings Rows (Hàng cài đặt tinh gọn):
    - *Ai có thể xem?* → `Công khai` / `Người theo dõi` (chạm mở sheet).
    - *Chủ đề* → `#BữaĂn`, `#TậpLuyện` (tùy chọn).
    - *Đính kèm hoạt động* → Hiển thị buổi tập hoặc bữa ăn đã chọn (mở R07).
    - *Cài đặt bình luận* → `Bật` / `Tắt`.
- **Điểm vào / Điểm ra:**
  - Điểm vào: Từ R06B, hoặc từ R06A (đăng chữ), hoặc khôi phục từ bản nháp R13.
  - Điểm ra: Chạm đính kèm → R07; Chạm ảnh → R06C; Nhấn "Chia sẻ" → Submit bài viết lên feed; Back → Xác nhận lưu bản nháp.
- **Sheets & Dialogs:** Sheet đối tượng xem, Sheet chọn chủ đề, Sheet lưu bản nháp, Dialog xác nhận đăng bài.
- **Yêu cầu dữ liệu & State:**
  - `DraftPost` hoàn chỉnh (caption, mediaList, attachmentSnapshot, audience, topic, allowComments).
  - State: Submitting in-flight, Idempotency key, Clear draft on success, Retry on failure.
- **Tình trạng mã nguồn:** Chưa có.

---

### R07 — Chọn hoạt động đính kèm (Attachment Picker — Refined)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r07_community_select_attachment_refined/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-02 Note §9, CP-02 Refined & PRD v3.0 §4.3.
- **Thành phần chính:**
  - Header: Nút Back, Tiêu đề `Đính kèm hoạt động`.
  - 2 Tab dữ liệu: *Buổi tập* (Mặc định) và *Bữa ăn*.
  - Danh sách hoạt động gần đây nhóm theo ngày, radio selection indicator xanh ngọc.
  - Privacy Controls (Thông tin hiển thị):
    - Tên buổi tập / bữa ăn & Thời lượng: Text tĩnh, bắt buộc.
    - Danh sách bài tập / món ăn: Switch bật/tắt (Mặc định Bật).
    - Khối lượng tạ & Số hiệp / Calories & Macros: Switch bật/tắt (**Mặc định Tắt** để bảo vệ quyền riêng tư).
  - Cam kết bảo mật: Dòng giải thích *"Saman không bao giờ tự động chia sẻ cân nặng, chỉ số đo cơ thể hoặc dữ liệu sức khỏe riêng tư."*
  - CTA cố định chân trang: Nút nền `#08664F`, chữ trắng: *"Đính kèm vào bài viết"*.
- **Điểm vào / Điểm ra:**
  - Điểm vào: Mở từ hàng cài đặt đính kèm tại R06D hoặc R08; hoặc từ sheet (+) Tạo nội dung.
  - Điểm ra: Nhấn "Đính kèm vào bài viết" → Trả snapshot về R06D/R08; Back → Giữ nguyên đính kèm cũ.
- **Sheets & Dialogs:** Empty state nếu chưa có buổi tập hoặc bữa ăn nào hoàn thành.
- **Yêu cầu dữ liệu & State:**
  - Đọc từ `ExerciseRepository.getWorkoutHistory()` và `NutritionService.getLoggedMeals()`.
  - Tạo ra `SharedWorkoutAttachmentSnapshot` hoặc `SharedMealAttachmentSnapshot`.
- **Tình trạng mã nguồn:** Nguồn dữ liệu workout/nutrition có sẵn trong repo, nhưng màn R07 picker chưa được viết.

---

### R08 — Đặt câu hỏi thảo luận (Ask Question)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r08_community_ask_question/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-02 Note §10 & PRD v3.0 §4.3 (Header duy nhất, bỏ header lặp).
- **Thành phần chính:**
  - Header: Nút Đóng (`✕`), Tiêu đề `Đặt câu hỏi`, Nút `Đăng câu hỏi` nền `#08664F`, chữ trắng.
  - Dải chip chọn chủ đề bắt buộc (Chọn 1): *Dinh dưỡng* (Active), *Tập luyện*, *Phục hồi*.
  - Ô Tiêu đề câu hỏi: Bộ đếm ký tự `63/150`, validate không chỉ có khoảng trắng.
  - Ô Mô tả chi tiết: Nhập bối cảnh thắc mắc.
  - Tùy chọn đính kèm ảnh minh họa hoặc hoạt động (mở R07 nếu cần).
- **Điểm vào / Điểm ra:**
  - Điểm vào: Chọn "Đặt câu hỏi" từ sheet (+) Tạo nội dung; hoặc từ R13 (bản nháp câu hỏi).
  - Điểm ra: Nhấn "Đăng câu hỏi" → Tạo câu hỏi mới trên feed Hỏi đáp (R03/R15); Đóng → Xác nhận lưu bản nháp.
- **Sheets & Dialogs:** Sheet xác nhận lưu nháp.
- **Yêu cầu dữ liệu & State:**
  - `DraftQuestion` (title, details, topic, mediaUrl, attachmentSnapshot).
- **Tình trạng mã nguồn:** Chưa có.

---

### R09 — Hồ sơ cộng đồng (Public Community Profile)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r09_community_profile/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-02 Note §11, CP-03 Note §4 & PRD v3.0 §4.2.
- **Thành phần chính:**
  - Header: Nút Back, Menu ba chấm (nếu hồ sơ chính mình: *Đã lưu*, *Bản nháp*; nếu hồ sơ người khác: *Chia sẻ*, *Báo cáo*, *Chặn*).
  - Thẻ thông tin cá nhân: Avatar, Tên hiển thị, Username (`@handle`), Bio ngắn. Tuyệt đối không hiện cân nặng hay chỉ số y tế.
  - Thống kê tương tác: Số Bài viết, Số Người theo dõi (nhấn mở R10), Số Đang theo dõi.
  - Nút hành động:
    - Hồ sơ chính mình: Nút *"Chỉnh sửa hồ sơ"* (mở R14) và *"Chia sẻ hồ sơ"*.
    - Hồ sơ người khác: Nút `Theo dõi` / `Đang theo dõi` và *"Chia sẻ"*. Không hiện nút tự theo dõi chính mình.
  - 2 Tab nội dung: *Bài viết* và *Hỏi đáp* (hỗ trợ chuyển đổi grid/list).
  - Bottom Navigation: Nếu đang ở Tab Cá nhân của Community thì hiện thanh nav Community; nếu mở từ bài viết thì ẩn bottom nav và dùng nút Back.
- **Điểm vào / Điểm ra:**
  - Điểm vào: Tab Cá nhân trên Community Nav; hoặc chạm avatar/tác giả từ feed, comment, search, follow list.
  - Điểm ra: Chạm "Chỉnh sửa" → R14; Chạm follower/following → R10; Chạm menu Đã lưu → R12; Chạm menu Bản nháp → R13; Chạm bài post → R05/R15.
- **Sheets & Dialogs:** Sheet menu ba chấm, Dialog xác nhận chặn người dùng.
- **Yêu cầu dữ liệu & State:**
  - `CommunityProfile` (userId, displayName, username, bio, avatarUrl, postCount, followerCount, followingCount, isFollowing, isSelf).
- **Tình trạng mã nguồn:** Chưa có (Khác hoàn toàn với `ProfileScreen` quản lý số đo thể hình hiện tại).

---

### R10 — Danh sách theo dõi (Followers & Following)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r10_community_follow_list/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-02 Note §12 & PRD v3.0 §4.2.
- **Thành phần chính:**
  - Header: Nút Back, Tiêu đề tên người dùng đang xem.
  - 2 Tab danh sách: *Người theo dõi* và *Đang theo dõi*.
  - Ô tìm kiếm thành viên: Lọc danh sách theo tên hoặc username.
  - Từng hàng thành viên: Avatar, Tên, Username/bio, và nút quan hệ với viewer (`Theo dõi` / `Đang theo dõi` nền `#24272B`, chữ sáng).
  - Hàng tài khoản của chính mình hiển thị nhãn *"Hồ sơ của bạn"*, không có nút tự follow.
- **Điểm vào / Điểm ra:**
  - Điểm vào: Chạm vào số follower hoặc following tại R09.
  - Điểm ra: Chạm hàng thành viên → R09 đúng userId; Back → về R09.
- **Sheets & Dialogs:** Xác nhận bỏ theo dõi.
- **Yêu cầu dữ liệu & State:**
  - `FollowUserItem` (userId, displayName, username, avatarUrl, isFollowing, isSelf).
  - Optimistic toggle follow, Rollback on error.
- **Tình trạng mã nguồn:** Chưa có.

---

### R11 — Thông báo cộng đồng (Community Notifications)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r11_community_notifications/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-03 Note §5 & PRD v3.0 §4.4 (Bản polish, nút trung tính, chấm unread ngọc).
- **Thành phần chính:**
  - Header: Tiêu đề `Thông báo`, Icon Cài đặt thông báo góc phải, Thao tác *"Đã đọc"* (đánh dấu tất cả đã đọc).
  - Bộ lọc: 3 chip tinh gọn (*Tất cả*, *Bình luận*, *Theo dõi*).
  - Danh sách phân nhóm theo thời gian:
    - *Hôm nay:* Thông báo bình luận bài viết (kèm thumbnail ảnh, chấm chưa đọc `#8AD8BD`), Lượt thích, Câu trả lời mới cho câu hỏi, Thông báo người theo dõi mới kèm nút *"Theo dõi lại"* nền `#24272B`.
    - *Trước đó:* Các thông báo cũ đã đọc.
  - Community Bottom Navigation (Tab Thông báo active).
- **Điểm vào / Điểm ra:**
  - Điểm vào: Tab Thông báo trên thanh Community Nav.
  - Điểm ra: Chạm thông báo bài viết → R05; Chạm thông báo câu hỏi → R15; Chạm avatar người tạo sự kiện → R09; Chạm icon Cài đặt → Sheet tùy chọn thông báo.
- **Sheets & Dialogs:** Sheet tùy chọn nhận thông báo.
- **Yêu cầu dữ liệu & State:**
  - `NotificationItem` (id, type, actor, targetPostId, targetQuestionId, snippet, timestamp, isRead, thumbnail).
  - Unread badge counter, Mark as read.
- **Tình trạng mã nguồn:** Chưa có.

---

### R12 — Bài viết đã lưu (Community Saved Posts)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r12_community_saved/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-03 Note §6 & PRD v3.0 §4.4.
- **Thành phần chính:**
  - Header: Nút Back, Tiêu đề `Đã lưu`, Dòng giải thích *"Chỉ bạn nhìn thấy nội dung đã lưu"* màu `#9399A1`, Icon chuyển đổi grid/list. Ẩn bottom nav.
  - Bộ lọc: *Tất cả*, *Bài viết*, *Hỏi đáp*. Tuyệt đối không trộn bài viết Journal vào màn này.
  - Lưới 2 cột trực quan: Hiển thị bài viết bữa ăn, thẻ bài tập, thẻ câu hỏi đã lưu.
  - Nút Bookmark trên từng tile: Cho phép gỡ lưu nhanh, hiển thị Snackbar Hoàn tác khi gỡ nhầm.
- **Điểm vào / Điểm ra:**
  - Điểm vào: Menu ba chấm trên R09 của chính mình → "Đã lưu".
  - Điểm ra: Chạm bài post → R05; Chạm câu hỏi → R15; Back → về R09.
- **Sheets & Dialogs:** Snackbar thông báo gỡ lưu và nút Hoàn tác.
- **Yêu cầu dữ liệu & State:**
  - Danh sách saved post IDs theo account hiện tại.
  - Xử lý khi bài gốc bị xóa hoặc bị giới hạn quyền truy cập.
- **Tình trạng mã nguồn:** Chưa có.

---

### R13 — Quản lý bản nháp (Private Drafts Management)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r13_community_drafts/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-03 Note §7 & PRD v3.0 §4.4.
- **Thành phần chính:**
  - Header: Nút Back, Tiêu đề `Bản nháp`, Chỉ báo riêng tư an toàn.
  - Danh sách hàng thoáng đãng:
    - Hiển thị từng bản nháp với loại nội dung (Album ảnh, Chia sẻ buổi tập, Câu hỏi dở, Bài viết chỉ có chữ), trích dẫn nội dung, thumbnail và thời gian chỉnh sửa gần nhất.
  - Menu ba chấm trên từng hàng: *"Tiếp tục chỉnh sửa"* và *"Xóa bản nháp"*.
  - Empty state: *"Chưa có bản nháp"* kèm nút tạo bài mới.
- **Điểm vào / Điểm ra:**
  - Điểm vào: Menu ba chấm trên R09 của chính mình → "Bản nháp".
  - Điểm ra: Chạm vào bản nháp bài viết → R06D khôi phục đầy đủ dữ liệu; Chạm bản nháp câu hỏi → R08; Back → về R09.
- **Sheets & Dialogs:** Dialog popup xác nhận xóa bản nháp.
- **Yêu cầu dữ liệu & State:**
  - Danh sách `DraftItem` lưu cục bộ theo `userId`.
  - Phục hồi chính xác: caption, danh sách ảnh, attachment, topic, audience.
- **Tình trạng mã nguồn:** Chưa có.

---

### R14 — Chỉnh sửa hồ sơ cộng đồng (Edit Community Profile)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r14_community_edit_profile/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-03 Note §8 & PRD v3.0 §4.4 (Nút Lưu trên header, không nút mint đáy).
- **Thành phần chính:**
  - Header: Nút Back, Tiêu đề `Chỉnh sửa hồ sơ`, Text action `Lưu` (`#8AD8BD`, chỉ bật khi có thay đổi hợp lệ).
  - Avatar đại diện: Khung tròn với icon camera; dòng chú thích rõ: *"Ảnh đại diện cũng được cập nhật đồng bộ trong ứng dụng Saman"*.
  - Các trường nhập liệu:
    - Tên hiển thị (Display Name).
    - Tên người dùng (Username/@handle): Kèm icon check và dòng kiểm tra khả dụng `✓ Tên người dùng khả dụng`.
    - Giới thiệu bản thân (Bio): Bộ đếm ký tự `98/150`.
    - Chủ đề quan tâm: Dạng chip chọn tối đa 3 (*Tập luyện, Dinh dưỡng, Nấu ăn, Phục hồi, Thói quen*) nền `#24272B` + chữ trắng + icon check.
  - Dòng bảo mật dữ liệu: *"Những thông tin này hiển thị trên hồ sơ cộng đồng của bạn."* Tuyệt đối không chứa cân nặng, số đo hay bệnh sử.
- **Điểm vào / Điểm ra:**
  - Điểm vào: Nhấn "Chỉnh sửa hồ sơ" tại R09 của chính mình.
  - Điểm ra: Nhấn "Lưu" → Lưu hồ sơ và quay về R09 (đồng bộ dữ liệu); Back khi có thay đổi chưa lưu → Popup cảnh báo bỏ thay đổi.
- **Sheets & Dialogs:** Sheet đổi ảnh đại diện (Chụp ảnh mới / Chọn từ thư viện / Dùng ảnh Google / Xóa ảnh), Dialog xác nhận hủy thay đổi.
- **Yêu cầu dữ liệu & State:**
  - Tái sử dụng `AvatarRepository` (`POST /user/avatar/upload`, `POST /user/avatar/use-google`).
  - Username debounce check uniqueness.
- **Tình trạng mã nguồn:** Đã có hạ tầng avatar ở Profile chính, nhưng màn R14 chỉnh sửa hồ sơ cộng đồng chưa được viết.

---

### R15 — Thảo luận / Chi tiết hỏi đáp (Q&A Discussion Detail)
- **Đường dẫn tài liệu:** `design/saman-Journal_community/r15_community_question_detail/` (`code.html`, `screen.png`).
- **Phiên bản chuẩn:** CP-03 Note §9 & PRD v3.0 §4.4 (Phân biệt vote hữu ích và lựa chọn của người hỏi).
- **Thành phần chính:**
  - Header: Nút Back, Tiêu đề `Thảo luận`, Menu ba chấm. Ẩn bottom navigation.
  - Phần câu hỏi gốc:
    - Tác giả, avatar, thời gian đăng, badge chủ đề (`MEAL PREP`).
    - Tiêu đề câu hỏi lớn nổi bật, mô tả chi tiết, ảnh minh họa (nếu có).
    - Hàng nút hành động: *Theo dõi câu hỏi*, *Đã lưu*, *Chia sẻ* (nền `#24272B`, chữ sáng `#F2F4F5`).
  - Danh sách câu trả lời:
    - Bộ lọc sắp xếp: *Hữu ích nhất* / *Mới nhất*.
    - **Câu trả lời hữu ích nhất (Được người hỏi lựa chọn):** Card nổi bật với nhãn trung tính `✓ Người hỏi lựa chọn là câu trả lời hữu ích`, số lượt hữu ích (ví dụ: 48), reply thread cảm ơn từ người hỏi.
    - Các câu trả lời khác từ cộng đồng.
  - Pinned Composer ở đáy: *"Chia sẻ câu trả lời của bạn..."*, nút gửi nền `#08664F`, icon trắng (≥ 44px).
- **Điểm vào / Điểm ra:**
  - Điểm vào: Chạm bài câu hỏi từ R03, R09, R11, R12.
  - Điểm ra: Chạm tác giả → R09; Back → Quay lại màn hình trước.
- **Sheets & Dialogs:** Sheet menu câu trả lời, Sheet chọn câu trả lời hữu ích (chỉ dành cho chủ câu hỏi).
- **Yêu cầu dữ liệu & State:**
  - `QuestionDetail` kèm `List<Answer>` (id, author, content, usefulCount, isUsefulVoted, isAskerAccepted, replies).
  - Submit answer in-flight, Useful vote optimistic toggle & rollback.
- **Tình trạng mã nguồn:** Chưa có.

---

## 3. KIỂM KÊ CÁC BOTTOM SHEET & DIALOG DÙNG CHUNG BẮT BUỘC

| Tên Sheet / Dialog | Điểm kích hoạt | Hành vi & Trách nhiệm | Tình trạng |
|---|---|---|---|
| **Sheet (+) Tạo nội dung** | Nút (+) trên Community Nav | 4 lựa chọn: Bài viết (→ R06A), Chia sẻ buổi tập (→ R07), Chia sẻ bữa ăn (→ R07), Đặt câu hỏi (→ R08). | Chưa có |
| **Sheet Đối tượng xem bài** | Hàng "Ai có thể xem?" trong R06D | 2 lựa chọn: Công khai / Người theo dõi. Kèm giải thích quyền riêng tư. | Chưa có |
| **Sheet Chọn chủ đề bài** | Hàng "Chủ đề" trong R06D | Danh sách chủ đề (`#TapLuyen`, `#BuaAn`, `#PhucHoi`...). Cho phép chọn tối đa 3. | Chưa có |
| **Sheet Lưu bản nháp** | Khi nhấn Back/Đóng tại R06A, R06D, R08 | 3 lựa chọn: "Lưu bản nháp" / "Bỏ thay đổi" / "Tiếp tục viết". | Chưa có |
| **Sheet Đổi Avatar** | Icon camera tại R14 | 4 tùy chọn: Chọn từ thư viện / Chụp ảnh / Dùng ảnh Google / Xóa ảnh. | Tái sử dụng từ Profile |
| **Dialog Xác nhận xóa nháp** | Menu trên R13 | Cảnh báo xóa vĩnh viễn bản nháp cục bộ. | Chưa có |
| **Sheet Sắp xếp câu trả lời** | Dropdown tại R15 | 2 tùy chọn: Hữu ích nhất / Mới nhất. | Chưa có |
