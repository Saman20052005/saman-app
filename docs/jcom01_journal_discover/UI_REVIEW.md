# ĐÁNH GIÁ GIAO DIỆN THỰC TẾ (UI REVIEW) — JCOM-01
## ĐỐI CHIẾU MÀN HÌNH R01, R02 VỚI BẢN THIẾT KẾ OBSIDIAN KINETIC

- **Mã checkpoint:** JCOM-01
- **Thời gian thực hiện:** 01/11/2026
- **Thiết kế đối chiếu gốc:**
  - `design/saman-Journal_community/r01_journal_discover/screen.png` & `code.html`
  - `design/saman-Journal_community/r02_journal_search/screen.png` & `code.html`
- **Ảnh chụp UI thực tế:** Được tạo tại `docs/jcom01_journal_discover/screenshots/`

---

## 1. TỔNG QUAN ĐỐI CHIẾU BẢN THIẾT KẾ (DESIGN FIDELITY)

| Thành phần thiết kế | Đặc tả thiết kế Obsidian Kinetic | Kết quả triển khai Flutter thực tế | Đánh giá |
|---|---|---|---|
| **Màu nền tảng (Foundation)** | Canvas Pitch `#0C0D0E`, Card Matte `#16171B`, Card Elevated `#1B1D22` | Khớp 100% qua `SamanHomeTokens.canvas`, `cardSurface`, `cardSurfaceElevated` | **KHỚP CHUẨN** |
| **Đường viền (Hairline borders)** | `#23252A` và `#26282F`, độ dày 1px tinh tế | Sử dụng `SamanHomeTokens.borderSubtle` và `border` 1px đồng nhất | **KHỚP CHUẨN** |
| **Màu điểm nhấn (Accent Emerald)** | `#10B981` cho badge, tiến độ, indicator tab | Sử dụng `SamanHomeTokens.greenAccent` (`#10B981`), không lạm dụng fill mảng lớn | **KHỚP CHUẨN** |
| **Phân cấp tiêu đề (Single Header)** | Chỉ 1 header duy nhất trên mỗi màn; loại bỏ hoàn toàn frame labels và công cụ Stitch | `JournalDiscoverScreen` và `JournalSearchScreen` mỗi màn chỉ có 1 header 56px chuẩn mobile | **KHỚP CHUẨN** |
| **Bản địa hóa (Localization)** | Hỗ trợ đầy đủ tiếng Việt (`vi`) và tiếng Anh (`en`) | Mọi chuỗi giao diện đều đi qua `AppTranslations` (`context.tr`), không hardcode chuỗi trần | **KHỚP CHUẨN** |

---

## 2. ĐỐI CHIẾU CHI TIẾT MÀN HÌNH R01 — JOURNAL DISCOVER

Dựa trên ảnh chụp thực tế: `02_r01_journal_discover_top.png` và `03_r01_journal_discover_bottom.png`.

### 2.1. Header & Điều hướng nội bộ
- **Header:** Nút Back (`←`) góc trái đưa người dùng quay lại Home; tiêu đề `Saman Journal` đậm 18px; nút Bookmark và Avatar người dùng góc phải.
- **Internal Tabs:** Gồm 3 tab duy nhất: *Khám phá* (active kèm vạch xanh ngọc), *Thư viện*, *Cẩm nang*.
  - Tuyệt đối không có tab Community (tuân thủ cấu trúc sản phẩm mới).
  - Khi người dùng chạm vào tab *Thư viện* hoặc *Cẩm nang*, hệ thống hiển thị màn hình thông báo giới hạn minh bạch (`13_r01_backlog_library_tab.png`), có nút *"Quay lại Khám phá"*. Không giả hiển thị danh sách rỗng hay dựng 14 màn backlog chưa duyệt.

### 2.2. Điểm chạm tìm kiếm (Search Bar Trigger)
- Nằm dưới hàng tab với icon kính lúp, placeholder *"Tìm kiến thức, bài tập, món ăn…"*.
- Khi chạm, kích hoạt chuyển cảnh mượt sang `R02_Journal_Search`.

### 2.3. Bài viết nổi bật (Hero Editorial Story)
- Tỷ lệ khung hình 16:10, ảnh nền phục hồi cơ bắp (`assets/images/home_journal_recovery.jpg`).
- Badge `PHỤC HỒI` màu xanh ngọc, tiêu đề *"Phục hồi tốt hơn sau buổi tập chân"*, thời lượng `4 phút đọc`.
- Khi chạm, mở bottom sheet xem trước nội dung khoa học tóm tắt từ model.

### 2.4. Dải chip chủ đề (Topic Navigation Chips)
- 4 chip chủ đề: *Tập luyện*, *Dinh dưỡng*, *Phục hồi*, *Thói quen*.
- Chip active hiển thị nền sẫm `#1F2021` kèm chữ xanh ngọc. Khi chọn, danh sách bài viết cập nhật tức thì qua Riverpod StateNotifier.

### 2.5. Tiếp tục đọc (Resume Reading Card)
- Tiêu đề nhóm `TIẾP TỤC ĐỌC`.
- Card hiển thị thumbnail 58x58 (`assets/images/nutrition.jpg`), tiêu đề *"Hiểu calories và các chất dinh dưỡng"*, thông số *"Đã đọc 40% • Còn 3 phút"*.
- Thanh tiến độ `LinearProgressIndicator` màu xanh ngọc với độ dày 3.5px.

### 2.6. Thư viện tri thức (Knowledge Libraries)
- 2 thẻ cân xứng 2 cột:
  1. *Bài tập & lịch tập* (Icon `fitness_center`, nhãn `128 chuyển động`, ảnh nền tập tạ).
  2. *Thực phẩm & công thức* (Icon `restaurant`, nhãn `240+ dữ liệu chuẩn`, ảnh nền món ăn dinh dưỡng).

### 2.7. Lộ trình nền tảng ("Bắt đầu cùng Saman")
- Badge chấm tròn xanh ngọc `LỘ TRÌNH NỀN TẢNG`.
- Tiêu đề *"Bắt đầu cùng Saman"*, mô tả *"5 bài hướng dẫn cơ bản xây dựng thói quen bền bỉ"*, kèm thumbnail 76x76.

### 2.8. Cửa ngõ sang Community (Doorway Card)
- Header card: Icon forum xanh ngọc, tiêu đề `Saman Community`, cụm 3 avatar thành viên xếp chồng.
- Nội dung: *"Chia sẻ hành trình. Cùng nhau tiến bộ."*.
- Link hành động: *"Khám phá cộng đồng →"*.
- Khi chạm: Kích hoạt preview sheet (`12_r01_community_doorway_sheet.png`) thông báo rõ ràng Community sẽ có trong checkpoint JCOM-02, không dẫn sang route không tồn tại, không để nút chết.

---

## 3. ĐỐI CHIẾU CHI TIẾT MÀN HÌNH R02 — JOURNAL SEARCH

Dựa trên ảnh chụp thực tế: `04_r02_journal_search_empty_query.png`, `05_r02_journal_search_populated_protein.png`, `06_r02_journal_search_filter_exercises.png`, `07_r02_journal_search_filter_foods.png`, `08_r02_journal_search_no_results.png`, `09_r02_journal_search_error_state.png`.

### 3.1. Header & Ô tìm kiếm
- Nút Back (`←`) quay lại R01 mà không làm mất vị trí cuộn trang của R01.
- Ô nhập từ khóa bo tròn, icon search xanh ngọc.
- Nút Clear (`✕`) xuất hiện khi có văn bản, chạm vào xóa sạch từ khóa và trả về kết quả tìm kiếm rỗng.
- Nút Lọc nâng cao (`tune`) mở sheet giới thiệu bộ lọc chuyên sâu.

### 3.2. Thanh chip lọc phân loại (Filter Chips)
- Gồm: *Tất cả*, *Bài viết*, *Bài tập*, *Thực phẩm*, *Công thức*.
- **Cách ly tuyệt đối:** Không chứa bất kỳ bài đăng mạng xã hội nào của Saman Community.
- Chạm vào chip nào sẽ kích hoạt lọc dữ liệu tức thì theo danh mục tương ứng.

### 3.3. Dòng kết quả phân nhóm (Grouped Results Stream)
- **Nhóm Bài viết:** Card bài viết kiến thức, thời gian đọc `5 phút đọc`, nhãn `Kiến thức`, link `Đọc tiếp →`.
- **Nhóm Thực phẩm:** Card thực phẩm có tick xanh chính thức `Ức gà`, mô tả đạm cao/ít béo, chỉ số `31g Protein / 100g • 165 kcal`, nút `+` mở xem chi tiết khẩu phần (không tự ý ghi log vào database).
- **Nhóm Công thức:** Card bữa ăn mẫu `Sữa chua, yến mạch và trái cây`, `24g Protein • 340 kcal`, nút bookmark công thức.
- **Nhóm Bài tập:** Card giáo án tập tạ `Tập tạ và tổng hợp protein cơ bắp` kèm icon tạ.

### 3.4. Saman Advice Tip Card
- Nằm ở chân trang kết quả: Icon bóng đèn xanh ngọc, tiêu đề *Gợi ý từ Saman Journal*, lời khuyên bổ sung 1.6 - 2.2g đạm/kg thể trọng.

### 3.5. Trạng thái Tìm kiếm Rỗng & Xử lý Lỗi
- **Query rỗng:** Hiển thị danh mục gợi ý ban đầu.
- **Không tìm thấy kết quả:** Hiển thị thông báo *"Không tìm thấy kết quả phù hợp cho [query]"* kèm gợi ý từ khóa thay thế.
- **Lỗi mạng / datasource:** Hiển thị thông báo lỗi kèm nút *"Thử lại"*. Nhấn thử lại giữ nguyên query và filter của người dùng.

---

## 4. KIỂM THỬ KHẢ NĂNG THÍCH ỨNG (RESPONSIVE & ACCESSIBILITY)

1. **Màn hình hẹp (360px Viewport):**
   - Đã kiểm thử tại kích thước 360 × 780 logical pixels (`10_r01_narrow_360px_viewport.png`).
   - **Kết quả:** Layout co giãn mượt mà, tiêu đề tự truncate khi cần, hàng chip cuộn ngang không gây vỡ giao diện. Đạt **0 overflow errors**.
2. **Độ phóng đại chữ lớn (200% Text Scaling):**
   - Đã kiểm thử tại TextScaler 2.0 (`11_r01_large_text_scaling_200.png`).
   - **Kết quả:** Sử dụng `Wrap` và `Flexible` cho các dòng chỉ số và tiêu đề. Chữ phóng to gấp đôi vẫn hiển thị rõ ràng, không bị cắt cụt hay gây RenderFlex overflow.
3. **Safe Area & Bàn phím:**
   - Cả 2 màn hình đều tôn trọng `SafeArea(top: true, bottom: false)` và tính toán `MediaQuery.paddingOf(context).bottom` cho padding cuối danh sách. Bàn phím mở trong R02 đẩy giao diện tự nhiên, không che khuất ô nhập liệu.

---

## 5. KẾT LUẬN ĐÁNH GIÁ GIAO DIỆN

Giao diện R01 và R02 được chuyển đổi từ bản thiết kế Obsidian Kinetic sang Flutter với độ chính xác cao (pixel-level fidelity), tôn trọng tuyệt đối màu sắc, spacing, và typographic tokens của ứng dụng Saman. Các trạng thái rỗng, lỗi, giới hạn tính năng đều được xử lý chân thực, không có thành công giả hay nút chết.
