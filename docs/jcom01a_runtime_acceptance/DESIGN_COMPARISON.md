# ĐỐI CHIẾU THIẾT KẾ & BẰNG CHỨNG HÌNH ẢNH (DESIGN COMPARISON)

Tài liệu so sánh chi tiết giữa bản thiết kế chuẩn (`design/saman-Journal_community/`) và kết quả kiểm thử thực tế thu thập được trong checkpoint JCOM-01A.

---

## 1. NGUỒN VÀ PHÂN LOẠI CÁC ẢNH CHỤP BẰNG CHỨNG

Toàn bộ ảnh bằng chứng được lưu trữ tại `docs/jcom01a_runtime_acceptance/screenshots/`:

| Tên tệp ảnh | Nguồn gốc chụp | Mục đích kiểm chứng |
|---|---|---|
| `01_home_runtime_live.png` | **Runtime Capture (Browser CDP)** | Xác minh phản hồi auth live, token lưu trữ, và profile health gate. |
| `login_correctly_filled.png` | **Runtime Capture (Browser CDP)** | Thao tác nhập liệu tự động thật bằng pointer/keyboard qua Chrome DevTools Protocol. |
| `login_filled.png` | **Runtime Capture (Browser CDP)** | Tương tác form đăng nhập trên browser runtime. |
| `test_r01_runtime.png` | **Runtime Capture (Browser CDP)** | Khởi động ban đầu của ứng dụng web thật từ build production. |
| `01_home_journal_entry.png` | **Widget-Test Render (2.0x DPI)** | Thẻ SAMAN JOURNAL nằm trong Saman Picks Carousel trên Home. |
| `02_r01_journal_discover_top.png` | **Widget-Test Render (2.0x DPI)** | R01 phần trên: Header, 3 Tabs, Search Trigger, Hero Story, Topic Chips, Thẻ đọc dở có badge `DỮ LIỆU MẪU`. |
| `03_r01_journal_discover_bottom.png` | **Widget-Test Render (2.0x DPI)** | R01 phần dưới: Thư viện 2 cột, Lộ trình nền tảng, Thẻ Gateway sang Community. |
| `04_r02_journal_search_empty_query.png` | **Widget-Test Render (2.0x DPI)** | R02 khi query rỗng (đã bấm nút Clear `✕`). |
| `05_r02_journal_search_populated_protein.png` | **Widget-Test Render (2.0x DPI)** | R02 hiển thị kết quả phân nhóm cho từ khóa `"protein"`. |
| `06_r02_journal_search_filter_exercises.png` | **Widget-Test Render (2.0x DPI)** | R02 khi bấm chip lọc danh mục "Bài tập". |
| `07_r02_journal_search_filter_foods.png` | **Widget-Test Render (2.0x DPI)** | R02 khi bấm chip lọc danh mục "Thực phẩm" (có tick verified). |
| `08_r02_journal_search_no_results.png` | **Widget-Test Render (2.0x DPI)** | R02 hiển thị empty state khi tìm từ khóa không có kết quả. |
| `09_r02_journal_search_error_state.png` | **Widget-Test Render (2.0x DPI)** | R02 hiển thị trạng thái lỗi mạng kèm nút "Thử lại". |
| `10_r01_narrow_360px_viewport.png` | **Widget-Test Render (2.0x DPI)** | R01 tại màn hình hẹp (360 logical px), đạt 0 overflow. |
| `11_r01_large_text_scaling_200.png` | **Widget-Test Render (2.0x DPI)** | R01 tại hệ số phóng to chữ 200% (TextScaler 2.0), không tràn viền. |
| `12_r01_community_doorway_sheet.png` | **Widget-Test Render (2.0x DPI)** | Bottom sheet xem trước khi bấm card Community Doorway. |
| `13_r01_backlog_library_tab.png` | **Widget-Test Render (2.0x DPI)** | Trạng thái giới hạn minh bạch khi bấm tab backlog "Thư viện". |
| `14_r01_english_locale.png` | **Widget-Test Render (2.0x DPI)** | R01 hiển thị đầy đủ giao diện tiếng Anh (`en`). |
| `15_r02_food_preview_sheet.png` | **Widget-Test Render (2.0x DPI)** | Bottom sheet thông tin khẩu phần khi bấm nút `+` trên thực phẩm. |
| `16_r01_reading_progress_preview_sheet.png` | **Widget-Test Render (2.0x DPI)** | Bottom sheet giải thích dữ liệu mẫu khi bấm thẻ tiến độ đọc. |
| `step1_home_carousel.png` | **Widget-Test Render (2.0x DPI)** | Bước 1 trong chuỗi navigation: Home Screen. |
| `step2_r01_discover_entered.png` | **Widget-Test Render (2.0x DPI)** | Bước 2 trong chuỗi navigation: Vào màn hình R01 Discover. |
| `step3_r02_search_opened.png` | **Widget-Test Render (2.0x DPI)** | Bước 3 trong chuỗi navigation: Vào màn hình R02 Search. |
| `step4_r02_back_to_r01.png` | **Widget-Test Render (2.0x DPI)** | Bước 4 trong chuỗi navigation: Bấm Back trên R02 quay lại R01. |
| `step5_r01_back_to_home.png` | **Widget-Test Render (2.0x DPI)** | Bước 5 trong chuỗi navigation: Bấm Back trên R01 quay lại Home. |

---

## 2. BẢNG SO SÁNH THIẾT KẾ CHI TIẾT (DESIGN FIDELITY AUDIT)

### 2.1. R01 — Journal Discover Screen

| Thành phần thiết kế | Bản vẽ thiết kế (`r01_journal_discover/screen.png`) | Thực thi JCOM-01A | Mức độ khớp | Đánh giá / Ghi chú |
|---|---|---|---|---|
| **Top App Bar** | Back button (`←`), Title "Saman Journal", Action icon Bookmark, Avatar | Đầy đủ 4 phần tử; nút Back pop về đúng Home; Bookmark và Avatar chuẩn vị trí | **100% Khớp** | Không lặp lại shell navigation hoặc duplicated headers. |
| **Internal Tab Bar** | 3 tab: Khám phá (active), Thư viện, Cẩm nang | Đầy đủ 3 tab có indicator xanh ngọc dưới tab active; có thanh cuộn ngang chống overflow | **100% Khớp** | Tab Thư viện và Cẩm nang hiển thị màn hình thông báo backlog minh bạch kèm nút quay lại. |
| **Search Trigger Bar** | Thanh tìm kiếm bo góc lớn, icon kính lúp, placeholder "Tìm kiến thức, bài tập, món ăn…" | Bấm vào mở mượt mà sang `AppRoutes.journalSearch` | **100% Khớp** | Chuyển cảnh native MaterialPageRoute. |
| **Hero Editorial Story** | Tỷ lệ 16:10, ảnh vận động viên phục hồi cơ bắp, badge "PHỤC HỒI", tiêu đề "Phục hồi tốt hơn sau buổi tập chân", "4 phút đọc" | Bo góc `radiusLg` (16px), gradient phủ mờ đọc chữ rõ, gradient overlay chuẩn | **100% Khớp** | Bấm vào mở preview sheet nội dung tóm tắt khoa học. |
| **Topic Chips** | Dải chip ngang: Tập luyện, Dinh dưỡng, Phục hồi, Thói quen | Bo góc `radiusFull`, trạng thái active màu `actionButtonSurface`, đổi topic lọc tức thì | **100% Khớp** | Tương tác nhanh, không giật lag. |
| **Tiếp tục đọc (Resume)** | Thẻ đọc dở: thumbnail vuông, tiêu đề "Hiểu calories và các chất dinh dưỡng", tiến độ 40%, thời gian còn lại 3 phút, progress bar xanh ngọc | Đầy đủ chi tiết; **đã gắn thêm badge `DỮ LIỆU MẪU`** minh bạch; thanh tiến độ mượt mà | **100% Khớp + Cải tiến tính trung thực** | Không gây ảo tưởng là tiến độ đã đồng bộ lên cloud. |
| **Thư viện tri thức (2 cột)** | 2 thẻ cột đối xứng: "Bài tập & lịch tập" (128 chuyển động), "Thực phẩm & công thức" (240+ dữ liệu) | Tỷ lệ 2 cột đối xứng `Row + Expanded`, ảnh nền mờ tinh tế, icon thể thao & ẩm thực | **100% Khớp** | Tương tác mở preview sheet thông tin số liệu. |
| **Lộ trình nền tảng** | Thẻ ngang "Bắt đầu cùng Saman", badge "LỘ TRÌNH NỀN TẢNG", mô tả "5 bài hướng dẫn cơ bản...", ảnh tập luyện | Bo góc chuẩn, chấm tròn xanh ngọc cạnh badge, layout ngang cân xứng | **100% Khớp** | Mở preview sheet giải thích khóa học nền tảng. |
| **Community Doorway Card** | Thẻ chuyển tiếp: Tiêu đề "Saman Community", khẩu hiệu "Chia sẻ hành trình. Cùng nhau tiến bộ.", nút CTA "Khám phá cộng đồng" | Viền xám mảnh, icon cộng đồng, nút CTA nổi bật bo góc | **100% Khớp** | Bấm vào mở preview sheet giải thích tính năng Community đang phát triển. |

---

### 2.2. R02 — Journal Search Screen

| Thành phần thiết kế | Bản vẽ thiết kế (`r02_journal_search/screen.png`) | Thực thi JCOM-01A | Mức độ khớp | Đánh giá / Ghi chú |
|---|---|---|---|---|
| **Top App Bar & Search Input** | Nút Back (`←`), Ô nhập liệu có viền bo góc, placeholder xám, nút Clear (`✕`) khi có chữ | Nút Back pop về R01 giữ nguyên state cuộn; nút Clear xóa query và đưa về empty state | **100% Khớp** | Có debounce 300ms và bộ đếm `_activeQueryId` chống race condition. |
| **Category Chips** | Dải chip ngang: *Tất cả*, *Bài viết*, *Bài tập*, *Thực phẩm*, *Công thức* | Chip bo tròn, cuộn ngang mượt mà, lọc dữ liệu tức thì theo danh mục | **100% Khớp** | Cách ly 100% khỏi bài đăng mạng xã hội Community. |
| **Kết quả phân nhóm** | Tiêu đề nhóm (BÀI VIẾT, THỰC PHẨM, CÔNG THỨC), badge xanh, icon verified trên thực phẩm chuẩn | Hiển thị đúng card ứng với từng loại: ảnh đại diện, số phút đọc, kcal & protein | **100% Khớp** | Tỷ lệ thumbnail 76x76 cho bài viết, 56x56 cho thực phẩm/công thức. |
| **Nút "+" trên Thực phẩm** | Nút `+` màu trắng bo tròn ở bên phải card thực phẩm | Bấm vào mở bottom sheet khẩu phần dinh dưỡng | **100% Khớp + An toàn dữ liệu** | Không tự ý ghi nhật ký vào database khi chưa qua luồng xác nhận Nutrition. |
| **Card Saman Advice** | Thẻ gợi ý dinh dưỡng: icon bóng đèn, tiêu đề "Lời khuyên từ Saman", khuyến nghị nạp đạm 1.6 - 2.2g/kg | Nằm ở cuối danh sách kết quả, nền xám tối, text dễ đọc | **100% Khớp** | Khuyến nghị khoa học thể thao chuẩn xác. |
| **Empty & Error States** | Trạng thái không tìm thấy kết quả hoặc lỗi mạng | Icon minh họa, thông báo rõ ràng kèm từ khóa đang tìm, nút "Thử lại" giữ nguyên query/filter | **100% Khớp** | Đã được kiểm thử đầy đủ qua unit/widget tests. |

---

## 3. KẾT LUẬN VỀ ĐỘ TRUNG THỰC THIẾT KẾ

1. **Hierarchy và Spacing:** Khớp hoàn toàn các hằng số thiết kế từ `SamanHomeTokens` (`spacingSm: 8`, `spacingMd: 16`, `spacingLg: 24`, `radiusSm: 8`, `radiusMd: 12`, `radiusLg: 16`).
2. **Typography & Màu sắc:** Màu nền tối `#0C0D0E`, thẻ card `#16181A`, màu nhấn xanh ngọc lục bảo `#00E599` (emerald), màu chữ trắng `#FFFFFF` và phụ `#8E9297`.
3. **Responsive:** Thử nghiệm tại 360 logical px và TextScaler 2.0 (phóng to chữ 200%) đạt 0 lỗi overflow sau khi tối ưu thẻ đọc dở bằng `Wrap`.
