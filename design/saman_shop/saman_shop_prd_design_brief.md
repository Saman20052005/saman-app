# PRODUCT REQUIREMENT DOCUMENT (PRD) & DESIGN SPECIFICATION
## SAMAN SHOP — Premium Sport & Lifestyle Boutique

---

### 1. TỔNG QUAN DỰ ÁN (PROJECT OVERVIEW)

- **Tên module:** Saman Shop
- **Hệ sinh thái:** Saman AI Fitness & Nutrition Ecosystem
- **Định vị sản phẩm:** Tuyển chọn dụng cụ thể thao, thiết bị hỗ trợ phục hồi và phụ kiện chuẩn bị bữa ăn cao cấp (*Premium Sport & Lifestyle Boutique*).
- **Mô hình kinh doanh & Vận hành:** 
  - Module native phụ trợ bên trong ứng dụng di động Saman (truy cập từ *Home → Saman Picks*).
  - Không nhúng giỏ hàng nội bộ, không cổng thanh toán, không xử lý vận chuyển nội sàn.
  - Sử dụng cơ chế **Deep Link / Referral chuyển tiếp minh bạch sang Shopee** để người dùng hoàn tất giao dịch.
- **Mục tiêu trải nghiệm người dùng (UX Goal):** 
  - Mang lại cảm giác tin cậy, được tuyển chọn kỹ lưỡng bởi chuyên gia thể thao (*Curated by Fitness Enthusiasts*).
  - Loại bỏ hoàn toàn sự ồn ào của sàn thương mại điện tử đại trà (không banner flash sale, không voucher pop-up, không số lượng đã bán / review giả mạo).
  - Tối ưu cho thao tác khám phá nhanh hằng ngày, xem thông số cần thiết và lưu sản phẩm yêu thích.

---

### 2. PHẠM VI CHỨC NĂNG & LUỒNG NGƯỜI DÙNG (SCOPE & USER FLOWS)

```
[Saman Home] 
      │ (Chạm vào Saman Picks: Khám phá đồ tập)
      ▼
[Screen 01: Saman Shop Landing] 
      ├── A. Tìm kiếm sản phẩm (Search instant)
      ├── B. Lọc theo danh mục (Tất cả / Tập luyện / Phục hồi / Bữa ăn)
      ├── C. Bộ sưu tập mục đích tập (Tập tại nhà / Phục hồi / Bữa ăn)
      ├── D. Điều hướng sang [Screen 03: Đã lưu (Saved Products)]
      └── E. Chạm vào Product Card
            │
            ▼
[Screen 02: Product Detail (Chi tiết sản phẩm)]
      ├── Xem bộ sưu tập hình ảnh thực tế chất lượng cao
      ├── Đọc khối biên tập: "Vì sao Saman chọn"
      ├── Xem bảng thông số kỹ thuật tối giản
      ├── Lưu / Bỏ lưu sản phẩm (Bookmark)
      └── Chạm CTA chính "Mua trên Shopee ↗"
            │
            ├── [Production]: Mở Deep Link ứng dụng Shopee (hoặc Web Shopee)
            └── [Demo/Preview]: Mở Bottom Sheet thông báo "Sản phẩm minh họa"
```

#### Các giới hạn chức năng nghiêm ngặt (Hard Constraints):
1. **Không** tạo thêm Tab thứ 6 ở Bottom Navigation toàn ứng dụng.
2. **Không** xây dựng tính năng Cart (Giỏ hàng), Checkout (Thanh toán), Order Tracking (Đơn hàng).
3. **Không** tích hợp hệ thống đánh giá sao (Rating/Review) hay bộ đếm lượt mua giả lập.
4. **Không** hứa hẹn công dụng y khoa, chữa bệnh hay đưa ra chứng nhận chưa kiểm chứng.

---

### 3. KIẾN TRÚC MÀN HÌNH CHI TIẾT (SCREEN SPECIFICATIONS)

#### 3.1. SCREEN 01 — SAMAN SHOP (LANDING)
- **Header:**
  - Nút Quay lại (`Back` icon outline 20px) bên trái.
  - Tiêu đề trung tâm: `Saman Shop` (Font Manrope SemiBold 18px).
  - Nút `Bookmark` góc phải dẫn thẳng tới màn hình "Đã lưu".
- **Thanh tìm kiếm (Search Bar):**
  - Chiều cao 44px, viền mỏng `#26282F`, nền `#16171B`.
  - Placeholder: *"Tìm sản phẩm"*.
  - Icon Search mảnh bên trái, có nút xóa nhanh (Clear) khi có ký tự.
- **Hero Editorial (Commercial Banner):**
  - Chiều cao cân đối: 180–200px (chiếm ~22% viewport).
  - Bố cục bất đối xứng: Text bên trái (*"Đồ tốt cho nhịp tập của bạn."*), ảnh lifestyle dụng cụ tập cao cấp bên phải.
  - Text link tinh tế: *"Khám phá →"*.
- **Hàng Tab Danh mục (Category Tabs):**
  - Dạng Text Tabs lướt ngang: *Tất cả* · *Tập luyện* · *Phục hồi* · *Bữa ăn*.
  - Tab Active: Chữ sáng `#F3F4F6` kèm đường underline mảnh; tab Inactive: Màu `#94979E`.
- **Lưới sản phẩm tuyển chọn (Curated Catalog):**
  - Grid 2 cột đối xứng, tỷ lệ ảnh sản phẩm 4:5.
  - Borderless card, nền ảnh xám slate studio giúp nổi bật chất liệu sản phẩm.
  - Tên sản phẩm (tối đa 2 dòng), giá tham khảo VND dạng rõ ràng.
  - Nút Bookmark viền nổi nhẹ ở góc trên bên phải của ảnh.
- **Bộ sưu tập theo mục đích (Editorial Strip):**
  - Đặt sau hàng sản phẩm đầu tiên: *"Bắt đầu tập tại nhà"*, *"Dụng cụ phục hồi"*, *"Chuẩn bị bữa ăn"*.

#### 3.2. SCREEN 02 — CHI TIẾT SẢN PHẨM (PRODUCT DETAIL)
*(Sản phẩm mẫu định danh: Bình shaker thép 750 ml)*
- **Hero Gallery:**
  - Chiếm 35–40% viewport, chụp studio cận cảnh độ hoàn thiện thép không gỉ 304 và nắp ren.
  - Floating action buttons: Nút Back tròn mờ bên trái, Bookmark bên phải.
  - Dải chấm tròn phân trang ảnh (Pagination dots).
- **Thông tin cơ bản:**
  - Nhãn thương hiệu phân phối: `Shopee Mall · Cập nhật hôm nay`.
  - Tên sản phẩm: `Bình shaker thép 750 ml` (Font Manrope 24px, SemiBold).
  - Giá tham khảo: `350.000 đ` kèm nhãn phụ mờ `Sản phẩm minh họa`.
- **Khối "Vì sao Saman chọn":**
  - Định dạng văn bản biên tập không bọc hộp viền thô.
  - Nêu rõ 3 lợi ích thực tế: Thép 304 không gỉ giữ lạnh 24h, triệt tiêu mùi whey chua, nắp chống tràn tuyệt đối khi xách di chuyển.
- **Bảng thông số kỹ thuật (Specifications):**
  - Danh sách hai cột (Nhãn / Giá trị) ngăn cách bởi đường line mảnh: Dung tích (750 ml), Chất liệu (Thép không gỉ 304), Khóa nắp (Chống rò rỉ 100%).
- **Sticky Bottom Action Bar:**
  - Nút CTA chính màu trắng ngà (`#F3F4F6`), chữ đen tương phản: `Mua trên Shopee ↗`.
  - Dòng giải thích minh bạch: *"Tiếp tục mua hàng trên Shopee"*.

#### 3.3. SCREEN 03 — DANH SÁCH ĐÃ LƯU (SAVED PRODUCTS)
- **Header:**
  - Nút Back, Tiêu đề `Đã lưu`, đính kèm số lượng nhỏ trang nhã `3 sản phẩm`.
- **Cấu trúc danh sách (Horizontal List Items):**
  - Thumbnail ảnh vuông tỉ lệ lớn (88–96px) bên trái, bo góc 12px.
  - Khối thông tin ở giữa: Tên món hàng, giá tham khảo, nguồn mua.
  - Nút Bookmark màu Emerald góc phải: Chạm để bỏ lưu với hiệu ứng mượt.
- **Xử lý trạng thái sản phẩm hết liên kết (Unavailable):**
  - Ảnh phủ lớp tối nhẹ, nhãn cảnh báo cam dịu: *"Tạm hết liên kết"*. Vẫn cho phép người dùng xem thông tin và gỡ khỏi danh sách đã lưu.
- **Empty State:**
  - Icon bookmark outline thanh lịch, tiêu đề *"Chưa có sản phẩm đã lưu"*, phụ đề hướng dẫn và nút dẫn về Catalog khám phá.

---

### 4. DESIGN SYSTEM TOKENS (HỆ THỐNG THIẾT KẾ)

| Danh mục | Token / Giá trị | Ứng dụng thực tế |
| :--- | :--- | :--- |
| **Canvas Background** | `#0C0D0E` | Nền chính toàn bộ ứng dụng |
| **Card Surface** | `#16171B` / `#16171A` | Bề mặt thanh search, card nền |
| **Elevated Surface** | `#212329` | Bottom sheet, nút phụ |
| **Border Subtle** | `#26282F` / `rgba(255,255,255,0.07)` | Đường ngăn cách nhẹ |
| **Primary Text** | `#F3F4F6` | Tiêu đề, tên sản phẩm, nút CTA |
| **Secondary Text** | `#94979E` | Thông số kỹ thuật, ghi chú, giá tham khảo |
| **Accent Emerald** | `#10B981` | Điểm nhấn active, đã bookmark |
| **Primary CTA Surface**| `#F3F4F6` (Off-white) | Nút bấm "Mua trên Shopee" |
| **Primary CTA Text** | `#0C0D0E` (Near-black) | Chữ trên nút CTA chính |
| **Typography** | `Manrope` (Google Fonts) | Tích hợp full ký tự tiếng Việt có dấu |
| **Border Radius** | 12px (Cards/Images) · 14px (Buttons) · 20px (Modal/Sheet) | Hệ thống bo góc nhất quán |
| **Touch Targets** | 44px – 52px | Đảm bảo chuẩn thao tác ngón cái trên mobile |

---

### 5. YÊU CẦU BÀN GIAO KỸ THUẬT (FLUTTER TECHNICAL HAND-OFF)

1. **Kiến trúc Widget Flutter khuyên dùng:**
   - `CustomScrollView` kết hợp `SliverAppBar` cho trang Chi tiết sản phẩm để có hiệu ứng co giãn ảnh mượt mà.
   - `GridView.builder` với `SliverGridDelegateWithFixedCrossAxisCount` cho Catalog 2 cột.
   - Tối ưu cache hình ảnh bằng `cached_network_image` với shimmer skeleton khi đang tải.
2. **Quản lý trạng thái (State Management):**
   - Bookmark State: Đồng bộ realtime giữa Landing, Detail và Saved thông qua Provider/Riverpod/Bloc.
   - Deep Linking: Sử dụng `url_launcher` mở scheme Shopee app (`shopee://...`), tự động fallback về HTTPS web nếu thiết bị chưa cài đặt app.
3. **Typography & Assets:**
   - Khai báo Google Fonts trong `pubspec.yaml` với font Manrope.
   - Icon hệ thống đồng bộ theo chuẩn Outline nét 1.5–2px (CupertinoIcons hoặc Phosphor Icons).
