# PRODUCT REQUIREMENTS DOCUMENT (PRD) & PRODUCT BRIEF
## Dự án: Saman Journal & Standalone Saman Community (Mobile Experience)
**Trạng thái:** Hoàn thiện thiết kế & Đặc tả hệ thống (Toàn diện: CP-01, R01–R05, CP-02, CP-02 Polish)  
**Phiên bản:** v2.0 — Production Ready  
**Tác giả:** Senior Mobile Product Design Team  
**Nền tảng:** iOS & Android (Mobile App) — Tối ưu viewport 390px – 412px (Touch targets ≥ 44px)  
**Thiết kế chuẩn tham chiếu:** Saman Home, Saman Obsidian Kinetic Design System (#0c0d0e, #16171b, #087F66, #54C7A5)  

---

## 1. TỔNG QUAN DỰ ÁN (EXECUTIVE SUMMARY & BRIEF)

### 1.1. Bối cảnh & Tầm nhìn sản phẩm
**Saman** là ứng dụng cao cấp về tối ưu hóa thể lực, tập luyện và dinh dưỡng cá nhân hóa trên nền tảng AI (Aesthetic Athletic Minimalism & Dark Mode). Ứng dụng ban đầu tập trung vào trải nghiệm công cụ chuyên sâu (Utility-First): ghi chép buổi tập (Workout Log), tính toán Macro/Calories (Nutrition), theo dõi phục hồi và AI Coach Saman.

Tuy nhiên, người dùng chỉ mở app tại 2 thời điểm: lúc đang tập luyện tại gym và khi ghi chép bữa ăn. Dự án **Saman Journal & Standalone Saman Community** được phát triển nhằm giải quyết bài toán:
1. **Lấp đầy khoảng trống kiến thức (Knowledge Gap):** Cung cấp các cẩm nang, tài liệu phục hồi sau tập (DOMS recovery), kỹ thuật compound movements, hướng dẫn meal prep khoa học có kiểm duyệt.
2. **Thúc đẩy tính gắn kết & Giữ chân (Social Retention & DAU Growth):** Xây dựng một mạng xã hội thu nhỏ (Mini Social Network) lành mạnh, nơi các hội viên chia sẻ khoảnh khắc tập luyện, hình ảnh bữa ăn dinh dưỡng, học hỏi kinh nghiệm qua hỏi đáp cộng đồng.

### 1.2. Mục tiêu chiến lược (Objectives & Key Results - OKRs)
* **Objective 1 (Retention):** Tăng tỷ lệ giữ chân D30 thêm +18% thông qua thói quen đọc bài viết kiến thức và lướt tin tức cộng đồng ngoài giờ tập.
* **Objective 2 (Engagement):** Đạt trung bình 3.5 phiên mở app/ngày trên mỗi người dùng tích cực.
* **Objective 3 (Data Sharing Rate):** Ít nhất 25% người dùng hoàn thành buổi tập hoặc log bữa ăn chủ động chia sẻ tóm tắt lên Saman Community.
* **Objective 4 (Brand Cohesion):** Bảo toàn 100% nhận diện thương hiệu cao cấp từ Saman Home: tối giản, thanh lịch, trầm tĩnh, không giật gân, không quảng cáo rác hay các yếu tố mạng xã hội độc hại.

---

## 2. PHÂN TÁCH SẢN PHẨM & NGUYÊN TẮC CỐT LÕI (PRODUCT SEPARATION)

Hai phân hệ được thiết kế hoàn toàn riêng biệt về mặt kiến trúc và tương tác:

| Tiêu chí | SAMAN JOURNAL (Tri thức & Cẩm nang) | SAMAN COMMUNITY (Mạng xã hội thể thao & Lối sống) |
|---|---|---|
| **Bản chất nội dung** | Nội dung biên tập tĩnh (Curated & Editorial Content) có thẩm định khoa học. | Nội dung do người dùng tạo (UGC - User Generated Content), tương tác 2 chiều. |
| **Vai trò người dùng** | Đọc, tra cứu, học tập, lưu trữ kiến thức (Consumer). | Đăng bài, khoe bữa ăn, thảo luận, theo dõi bạn tập (Creator & Collaborator). |
| **Cấu trúc Tab** | 3 tab tĩnh: **Khám phá / Thư viện / Cẩm nang**. (Tuyệt đối không có tab Cộng đồng). | Bộ lọc Feed: **Dành cho bạn / Đang theo dõi / Hỏi đáp**. |
| **Hệ thống điều hướng** | Độc lập toàn màn hình, có nút Back (`←`) về Saman Home. Tạm ẩn Bottom Nav chính để tối đa diện tích đọc. | Kích hoạt thanh **Community Bottom Navigation** riêng biệt (5 tabs: Bảng tin, Khám phá, Tạo bài [+], Thông báo, Cá nhân). |
| **Tìm kiếm** | `R02_Journal_Search`: Chỉ tra cứu bài viết, bài tập, thực phẩm, công thức (không ra post/thành viên). | `R04_Community_Discover`: Khám phá bài post, hashtag cộng đồng (#) và profile thành viên. |
| **Cửa ngõ liên kết** | Card cửa ngõ duy nhất (*"Saman Community Entry Doorway"*) đặt ở cuối trang Journal Discover. | Header có nút Back (`←`) quay lại Journal bất cứ lúc nào. |

---

## 3. KIẾN TRÚC THÔNG TIN & SƠ ĐỒ ĐIỀU HƯỚNG (INFORMATION ARCHITECTURE)

```
[SAMAN HOME (Main App)]
       │
       ├──> [Saman Picks: Card "Saman Journal"]
       │             │
       │             ▼
       │    ┌─────────────────────────────────────────────────────────────┐
       │    │               SAMAN JOURNAL (Full Screen)                   │
       │    │  Header: [Back to Home] [Title: Saman Journal] [Bookmark]   │
       │    │  Tabs: [Khám phá] | [Thư viện] | [Cẩm nang]                 │
       │    │                                                             │
       │    │  - Hero Editorial Card (Phục hồi sau Leg Day)               │
       │    │  - Topic Navigation Chips (Tập luyện, Dinh dưỡng,...)       │
       │    │  - Tiếp tục đọc (Reading Progress Resume 40%)               │
       │    │  - Thư viện kiến thức (Bài tập & Lịch / Thực phẩm & Recipe) │
       │    │  - Chuỗi bài nền tảng (Bắt đầu cùng Saman - 5 bài)          │
       │    │  - Doorway Card: "Saman Community — Chia sẻ hành trình" ────┼─────┐
       │    └─────────────────────────────┬───────────────────────────────┘     │
       │                                  ▼                                     │
       │                         [R02_Journal_Search]                           │
       │                         - Query: "protein"                             │
       │                         - Filters: Tất cả / Bài viết / Bài tập /...    │
       │                                                                        │
       └────────────────────────────────────────────────────────────────────────┘
                                                                                │
                                                                                ▼
       ┌──────────────────────────────────────────────────────────────────────────────┐
       │                     SAMAN COMMUNITY (Mini Social Network)                    │
       │  Header: [Back to Journal] [Title: Saman Community] [DM Future Icon]         │
       │  Feed Filters: [Dành cho bạn] | [Đang theo dõi] | [Hỏi đáp]                  │
       │                                                                              │
       │  Feed Content (R03):                                                         │
       │  ├── Post 1 (Photo / Meal): Linh Nguyễn ─────────> [R05_Community_Post_Detail│
       │  ├── Post 2 (Workout Attachment): Minh Khang                                 │
       │  └── Post 3 (Discussion / Q&A): Thu Hà                                       │
       │                                                                              │
       │  Dedicated Community Bottom Navigation:                                      │
       │  [Bảng tin (R03)] [Khám phá (R04)] [(+) Tạo bài] [Thông báo] [Cá nhân (R09)]  │
       └───────────────────────────────┬──────────────────────────────────────────────┘
                                       │
                ┌──────────────────────┴──────────────────────┐
                ▼                                             ▼
        [R04_Community_Discover]                      [Bottom Sheet: Tạo nội dung]
        - Search: Posts, Topics, Members              ├── "Bài viết" ─────────────┐
        - 3-Column Photo Grid (Masonry)               ├── "Chia sẻ buổi tập" ──┐  │
        - Trending Hashtags (#MealPrepCuoiTuan)       ├── "Chia sẻ bữa ăn" ──┐  │  │
        - Who to Follow (HLV Hoàng Long, Thảo Mai)    └── "Đặt câu hỏi" ───┐ │  │  │
                                                                           │ │  │  │
   ┌───────────────────────────────────────────────────────────────────────┘ │  │  │
   │                                                                         │  │  │
   ▼ [R08_Community_Ask_Question]                                            │  │  │
   - Tiêu đề câu hỏi / Mô tả bối cảnh                                        │  │  │
   - Chọn chủ đề bắt buộc (Dinh dưỡng / Tập luyện)                           │  │  │
   - Đính kèm ảnh hoặc dữ liệu tham khảo                                      │  │  │
                                                                             │  │  │
   ┌─────────────────────────────────────────────────────────────────────────┘  │  │
   │                                                                            │  │
   ▼ [R07_Community_Select_Attachment_Refined]                                  │  │
   - 2 Tab: [Buổi tập] | [Bữa ăn]                                               │  │
   - Danh sách theo ngày (Upper Body / 45 phút / 5 bài)                         │  │
   - Tùy chọn bảo mật: Tắt mặc định khối lượng tạ, ẩn số đo cơ thể cá nhân     │  │
   - Nút "Đính kèm vào bài viết" ─────────────────────────────────────────┐     │  │
                                                                          │     │  │
   ┌──────────────────────────────────────────────────────────────────────┼─────┘  │
   │                                                                      │        │
   │  ┌───────────────────────────────────────────────────────────────────┼────────┘
   │  │
   ▼  ▼
   LUỒNG TẠO BÀI VIẾT MEDIA-FIRST (CP-02 REVISION):
   ├── R06A_Post_Select_Media: Lưới ảnh 3 cột, Chọn nhiều, Preview tỷ lệ lớn, Đăng text-only
   │      │
   │      ▼
   ├── R06B_Post_Edit_Media: Chỉnh tỉ lệ (Gốc / Vuông / Dọc), Xoay, Độ sáng & Tương phản
   │      │
   │      ▼
   ├── R06C_Post_Album_Order: Kéo thả đổi thứ tự album, Xóa ảnh, Thêm ảnh, Đặt ảnh bìa
   │      │
   │      ▼
   └── R06D_Post_Compose_Publish: Composer tinh giản, Thumbnail ảnh cạnh ô text,
          Cài đặt hiển thị (Công khai / Chủ đề / Cài đặt bình luận), Nút "Chia sẻ" góc trên
```

---

## 4. CHI TIẾT ĐẶC TẢ TÍNH NĂNG TOÀN DIỆN (SYSTEM SPECIFICATIONS)

### 4.1. Phân hệ 1: Saman Journal

#### Màn hình: `R01_Journal_Discover` (Khám phá tri thức)
* **Header:**
  - Nút Back (`<`): Quay lại màn hình Saman Home.
  - Title: `Saman Journal` (Font sans, semi-bold, white).
  - Bookmark Action: Mở danh sách bài viết/công thức đã lưu.
* **Internal Tabs (3 tab duy nhất):** *Khám phá* (Active indicator gạch xanh emerald `#087F66`), *Thư viện*, *Cẩm nang*.
* **Search Trigger Input:** Read-only bar, placeholder *"Tìm kiến thức, bài tập, món ăn…"*, chạm vào chuyển mượt sang `R02`.
* **Hero Editorial Card:**
  - Ảnh chân thực tỷ lệ 16:10 phong cách moody fitness recovery.
  - Tag phân loại: `PHỤC HỒI` (Pill màu xanh ngọc Saman).
  - Tiêu đề: *"Phục hồi tốt hơn sau buổi tập chân"*.
  - Tóm tắt: *"Chiến lược giảm đau nhức cơ bắp DOMS và bổ sung glycogen..."*.
  - Metadata: `4 phút đọc`. Toàn bộ card có touch target lớn.
* **Topic Navigation:** Dải chip cuộn ngang: *Tất cả*, *Tập luyện*, *Dinh dưỡng*, *Phục hồi*, *Thói quen*.
* **Reading Progress:** Card ngang cho bài đọc dở *"Hiểu calories và các chất dinh dưỡng"*, thanh tiến độ `Đã đọc 40% • Còn 3 phút`.
* **Thư viện kiến thức:** 2 card cân xứng: *“Bài tập & lịch tập”* (128 chuyển động) và *“Thực phẩm & công thức”* (240+ dữ liệu chuẩn).
* **Chuỗi bài nền tảng:** Card *"Bắt đầu cùng Saman"* (5 bài hướng dẫn thói quen bền bỉ).
* **Cửa ngõ Saman Community:** Card entry nổi bật với cụm avatar thành viên và slogan *"Chia sẻ hành trình. Cùng nhau tiến bộ"*, CTA *"Khám phá cộng đồng ↓"* dẫn vào `R03`.

#### Màn hình: `R02_Journal_Search` (Tìm kiếm chuyên sâu)
* **Header:** Nút Back về `R01`, Input đang có từ khóa `"protein"`, nút `X` (Clear), nút Filter chuyên sâu.
* **Bộ lọc định dạng:** *Tất cả* (Active), *Bài viết*, *Bài tập*, *Thực phẩm*, *Công thức* (Không có kết quả mạng xã hội).
* **Kết quả phân nhóm rõ ràng:**
  - *Bài viết:* *"Hiểu protein trong bữa ăn hằng ngày"* (Kiến thức • 5 phút đọc).
  - *Thực phẩm chuẩn:* *"Ức gà"* (Official tick, 31g Protein/100g • 165 kcal, nút `+` nhanh vào Nutrition).
  - *Công thức:* *"Sữa chua, yến mạch & quả mọng"* (24g Protein • 340 kcal, nút bookmark).
  - *Bài tập:* *"Tập tạ và tổng hợp protein"* (Cửa sổ dinh dưỡng đồng hóa cơ).
  - *Saman Advice Callout:* Gợi ý bổ sung 1.6 - 2.2g protein/kg trọng lượng cơ thể.

---

### 4.2. Phân hệ 2: Saman Community (Feed, Discover, Post Detail & Profile)

#### Màn hình: `R03_Community_Feed` (Bảng tin cộng đồng)
* **Header:** Nút Back về Journal, tiêu đề `Saman Community` có đèn xanh online, icon Direct Message góc phải.
* **Feed Filters:** 3 tab: *Dành cho bạn* (Active), *Đang theo dõi*, *Hỏi đáp*.
* **3 Archetypes bài đăng chính:**
  1. **Photo / Meal Log (Linh Nguyễn):** Caption bữa trưa healthy ức gà áp chảo, ảnh món ăn 4:3 hấp dẫn, chỉ số macro badge (`42g Protein`, `480 kcal`), thanh tương tác (Like 142, Comment 18, Share, Bookmark), dòng engagement tự nhiên.
  2. **Shared Workout Attachment (Minh Khang):** Caption hoàn thành buổi tập, đính kèm thẻ **Saman Kinetic Workout Card** (`BUỔI TẬP ĐÃ HOÀN THÀNH`, *Upper Body Hypertrophy*, 45 phút • 5 bài • 12 hiệp, 3 thumbnail động tác, CTA *"Xem buổi tập →"*).
  3. **Discussion / Q&A (Thu Hà):** Badge `HỎI ĐÁP • MEAL PREP`, câu hỏi lớn *"Bạn thường chuẩn bị bữa ăn cho cả tuần như thế nào?"*, tóm tắt câu trả lời từ 25 thành viên, CTA *"Tham gia thảo luận →"*.
* **Community Bottom Navigation:** 5 tab cố định (*Bảng tin*, *Khám phá*, *[+] Đăng bài*, *Thông báo*, *Cá nhân*).

#### Màn hình: `R04_Community_Discover` (Khám phá cộng đồng)
* **Header & Search:** Ô tìm kiếm *"Tìm bài viết, chủ đề, thành viên…"*, hàng chip phân loại (*Tất cả, Tập luyện, Bữa ăn, Công thức, Hỏi đáp*).
* **Lưới ảnh tiêu biểu (3-Column Photo Grid):** Trưng bày các khoảnh khắc gym, bữa ăn, calisthenics, kèm icon album nhiều ảnh.
* **Chủ đề đang quan tâm (Trending Hashtags):** `#MealPrepCuoiTuan` (+28%), `#TangCoGiamMo` (+45%), `#HoiDapDinhDuong`.
* **Gợi ý theo dõi:** Card HLV Hoàng Long (HLV Thể lực & Sức bền), Thảo Mai (Lối sống lành mạnh) kèm nút CTA `+ Theo dõi`.

#### Màn hình: `R05_Community_Post_Detail` (Chi tiết bài viết & Thảo luận)
* **Cấu trúc:** Header có nút Back về Feed. Hiển thị toàn bộ nội dung bài viết gốc của Linh Nguyễn kèm ảnh hộp cơm lớn.
* **Discussion Thread (18 bình luận):**
  - Bình luận Minh Khang hỏi về nhiệt độ nướng khoai lang bằng nồi chiên không dầu.
  - Phản hồi từ Linh Nguyễn (Badge `Tác giả` xanh ngọc): hướng dẫn set 180 độ trong 15 phút.
  - Bình luận Thu Hà chia sẻ cảm ơn.
* **Thanh nhập bình luận ghim đáy (Pinned Composer):** Tự động đệm an toàn Home indicator, ô *"Viết bình luận…"*, icon emoji, nút gửi (Send) kích hoạt xanh Saman. Ẩn toàn bộ bottom nav để tập trung thảo luận.

#### Màn hình: `R09_Community_Profile` (Hồ sơ cộng đồng)
* **Header:** Nút Back, menu ba chấm, switch xem thử giữa **Khách xem** (hồ sơ thành viên khác) và **Chính mình**.
* **Thông tin:** Avatar Linh Nguyễn, Username `@linhnguyen.fit`, Bio đam mê dinh dưỡng và tập luyện bền bỉ cùng Saman Kinetic.
* **Số liệu:** `38` Bài viết, `2.4k` Người theo dõi (nhấn mở R10), `186` Đang theo dõi.
* **Nút hành động:** Nút chính *“Theo dõi”* (xanh `#087F66`) / *“Chỉnh sửa hồ sơ”* (khi là chính mình); nút phụ *“Chia sẻ”*.
* **Lưới nội dung:** 2 tab *Bài viết (32)* và *Hỏi đáp (6)*. Lưới ảnh 3 cột đồng bộ.

#### Màn hình: `R10_Community_Follow_List` (Danh sách theo dõi)
* **Header & Tabs:** 2 tab *Người theo dõi (2.4k)* và *Đang theo dõi (186)*.
* **Search:** Ô tra cứu thành viên theo tên hoặc `@handle`.
* **Danh sách 7 thành viên thực tế:** Minh Khang, Thu Hà, HLV Hoàng Long, Thảo Mai, Quốc Bảo, Lan Phương, Tiến Đạt. Hàng của chính mình có badge *“Hồ sơ của bạn”* và **không hiện nút tự theo dõi chính mình**.

---

### 4.3. Phân hệ 3: Luồng Tạo bài viết Media-First (CP-02 Revision & Polish)

#### Luồng điều hướng tổng quát:
Nhấn nút **(+)** tại Community Bottom Nav → Mở Bottom Sheet *"Tạo nội dung"*:
1. *"Bài viết"* → `R06A_Post_Select_Media` (Chọn ảnh).
2. *"Chia sẻ buổi tập"* → `R07` (Tab Buổi tập) → `R06D` (Xem trước & Đăng).
3. *"Chia sẻ bữa ăn"* → `R07` (Tab Bữa ăn) → `R06D` (Xem trước & Đăng).
4. *"Đặt câu hỏi"* → `R08_Community_Ask_Question`.

#### Màn hình: `R06A_Post_Select_Media` (Chọn ảnh & Thư viện)
* **Header tinh giản duy nhất:** `Đóng (✕)` | `Bài viết mới` | text action `Tiếp` (`#54C7A5` - bật khi đã chọn ≥ 1 ảnh).
* **Vùng Preview lớn:** Hiển thị ảnh đang chọn tỷ lệ vuông/dọc ở nửa trên với icon crop tròn nhỏ.
* **Điều khiển album:** Dropdown *"Gần đây"* bên trái, nút *"Chọn nhiều"* nền tối bên phải.
* **Lưới thư viện 3 cột:** Ô Camera chụp ảnh, các ô ảnh tiếp theo có vòng tròn số thứ tự album (`1`, `2`) nền emerald trầm `#087F66`.
* **Lối thoát văn bản:** Dòng link *"Đăng chỉ với nội dung văn bản →"* ở chân trang cho phép bỏ qua ảnh để sang thẳng R06D.

#### Màn hình: `R06B_Post_Edit_Media` (Chỉnh ảnh & Cắt góc)
* **Header:** `Back (←)` | `Chỉnh ảnh` | text action `Tiếp` (`#54C7A5`).
* **Khung chỉnh ảnh:** Ảnh trung tâm sắc nét, dải thumbnail nhỏ bên dưới để chuyển giữa các ảnh trong album.
* **Crop Controls:** 3 chế độ: *"Gốc"*, *"Vuông"* (1:1), *"Dọc"* (4:5) và nút xoay ảnh 90°.
* **Thanh tinh chỉnh:** Slider *"Độ sáng"* và *"Độ tương phản"* thanh lịch, nút *"Đặt lại"* xuất hiện khi có thay đổi.

#### Màn hình: `R06C_Post_Album_Order` (Quản lý thứ tự Album)
* **Header:** `Back (←)` | `Sắp xếp ảnh` | text action `Xong` (`#54C7A5`).
* **Lưới Thumbnail trực quan:** Đánh số thứ tự từng ảnh trong album, icon kéo thả (drag handle) để tráo đổi vị trí, nút gỡ bỏ ảnh (`✕`) và ô nét đứt *"+ Thêm ảnh"*.
* **Ảnh bìa:** Ảnh số 1 tự động gắn badge nhãn `Ảnh bìa` đại diện cho post trên Feed.

#### Màn hình: `R06D_Post_Compose_Publish` (Soạn nội dung & Chia sẻ)
* **Header:** `Back (←)` | `Bài viết mới` | text action chính `Chia sẻ` (`#54C7A5` hoặc `#087F66`) ở góc trên bên phải. **Tuyệt đối không có nút đăng lớn trùng lặp ở đáy màn hình.**
* **Soạn thảo tinh gọn:**
  - Avatar & Tên tác giả Linh Nguyễn.
  - Ô nhập văn bản tự nhiên: *"Hôm nay chuẩn bị hộp cơm trưa nhanh gọn: ức gà áp chảo sốt tiêu..."*.
  - Thumbnail ảnh vuông nhỏ gọn đặt cạnh trường viết kèm badge đếm số ảnh `2 ảnh` (chạm vào để mở `R06C`).
* **Hàng cài đặt tinh giản (Lightweight Settings Rows):**
  - *Ai có thể xem?* → `Công khai` (mở sheet chọn Công khai / Người theo dõi).
  - *Chủ đề* → `#BữaĂn` (mở sheet chọn chủ đề).
  - *Đính kèm hoạt động* → `Chưa đính kèm` (mở `R07`).
  - *Cài đặt bình luận* → `Bật`.
* **Biến thể chia sẻ buổi tập:** Khi chia sẻ workout, composer hiển thị thẻ tóm tắt buổi tập nhỏ gọn (có nút chỉnh sửa/xóa), không đính kèm ảnh meal prep và không có macro thức ăn không liên quan.

#### Màn hình: `R07_Community_Select_Attachment_Refined` (Đính kèm hoạt động)
* **Header:** `Back (←)` | `Đính kèm hoạt động`.
* **2 Tab dữ liệu:** *Buổi tập* (Mặc định) và *Bữa ăn*.
* **Danh sách phẳng theo ngày:** Nhóm buổi tập gần đây với radio checkmark xanh ngọc xác nhận.
* **Khu vực Thông tin hiển thị (Privacy Controls):**
  - *Tên buổi tập & Thời lượng:* Text tĩnh, nhãn `Bắt buộc`.
  - *Danh sách bài tập chính:* Switch bật/tắt (mặc định Bật).
  - *Khối lượng tạ & Số hiệp đấu:* Switch bật/tắt (mặc định Tắt).
  - *Bảo mật dữ liệu cá nhân:* Thông báo cam kết: *"Saman không bao giờ tự động chia sẻ cân nặng, chỉ số đo cơ thể hoặc dữ liệu sức khỏe riêng tư."*
* **CTA cố định chân trang:** Nút nền xanh emerald trầm `#087F66`, chữ trắng: *"Đính kèm vào bài viết →"*. Bấm vào sẽ đưa dữ liệu về bản nháp R06D mà không tự ý đăng bài.

#### Màn hình: `R08_Community_Ask_Question` (Đặt câu hỏi thảo luận)
* **Header:** `Đóng (✕)` | `Đặt câu hỏi` | Nút `Đăng câu hỏi` (`#087F66`).
* **Chủ đề thảo luận:** Hàng chip bắt buộc chọn 1: *Dinh dưỡng* (Active), *Tập luyện*, *Phục hồi*.
* **Nội dung câu hỏi:** Ô nhập tiêu đề câu hỏi (bộ đếm ký tự `63/150`), ô mô tả bối cảnh chi tiết.
* **Đính kèm hỗ trợ:** Nút thêm ảnh minh họa hoặc gắn nhật ký bữa ăn tham khảo.

---

## 5. DESIGN SYSTEM & DESIGN TOKENS (SAMAN OBSIDIAN KINETIC)

Hệ thống token kế thừa chuẩn xác từ mã nguồn gốc Saman Home và được chuẩn hóa sau vòng Polish CP-02:

| Token Category | Token Name / Key | Mã Màu HEX / CSS | Quy chuẩn áp dụng |
|---|---|---|---|
| **Canvas Background** | `surface-base` | `#0c0d0e` | Nền canvas toàn màn hình, status bar, bottom nav |
| **Card Surface** | `surface-card` | `#16171b` (hoặc `#16171a`) | Bề mặt container các card bài viết, feed item, settings box |
| **Elevated Surface** | `surface-elevated` | `#212329` / `#1c1d22` | Bề mặt dropdown, popover, bottom sheet |
| **Subtle Border** | `border-subtle` | `#23252a` / `#272930` | Đường viền mảnh ngăn cách section, viền ảnh |
| **Primary CTA (Solid)** | `brand-emerald-deep` | `#087F66` | Nút nền đặc chính (Đính kèm, Đăng, Radio checked, Badge 1, 2) |
| **Action Accent (Text/Icon)** | `brand-emerald-action` | `#54C7A5` | Chữ text action header (Tiếp, Xong, Chia sẻ), icon active |
| **Subtle Accent Pill** | `brand-emerald-subtle` | `rgba(8, 127, 102, 0.15)` | Nền chip chủ đề active, nhãn tag bài viết |
| **Macro Warning/Carbs** | `macro-carbs` | `#f59e0b` (Amber 500) | Thanh chỉ số carbs trong nhật ký |
| **Macro Secondary/Fat** | `macro-fat` | `#a855f7` (Purple 500) | Thanh chỉ số fat trong nhật ký |
| **Typography - Primary** | `text-primary` | `#ffffff` / `#f3f4f6` | Tiêu đề H1, H2, tên tác giả, con số thống kê |
| **Typography - Muted** | `text-secondary` | `#94979e` / `#9ca3af` | Chữ phụ đề, timestamp, nhãn thông số phụ |
| **Corner Radius - Large** | `rounded-2xl` | `16px` | Bo góc card bài viết, hero card, bottom sheet |
| **Corner Radius - Medium** | `rounded-xl` | `12px` | Bo góc thumbnail ảnh, action pill button |
| **Corner Radius - Small** | `rounded-lg` | `8px` | Bo góc chip phân loại, input field, micro badge |
| **Touch Target** | `min-touch-target` | `44px` – `48px` | Vùng chạm tối thiểu trên mọi thiết bị di động |

---

## 6. QUY TẮC BẢO MẬT & DỮ LIỆU SỨC KHỎE (PRIVACY & ETHICAL RULES)

1. **Không tự động công khai (Explicit Opt-in Only):**
   - Đăng bài và đính kèm dữ liệu là hành động hoàn toàn chủ động của người dùng. Không bao giờ tự động đăng kết quả buổi tập hoặc bữa ăn ngay khi kết thúc log.
2. **Cô lập dữ liệu y tế & sức khỏe riêng tư (Strict Privacy Boundary):**
   - Không chia sẻ: Cân nặng hiện tại, số đo vòng eo/vòng cơ, ảnh tiến độ cơ thể (Body progress photos), nhịp tim nghỉ, calo ước tính nhạy cảm.
   - Khi chia sẻ buổi tập: Tên bài và số bài là thông tin cơ bản; khối lượng tạ (Weights) và số lần tập (Reps) luôn ở trạng thái **TẮT mặc định**, chỉ hiển thị khi người dùng chủ động gạt bật.
3. **Không y tế hóa & Không đưa ra chẩn đoán y khoa giả:**
   - Mọi thông tin trong bài viết Journal đều gắn nhãn tham khảo lối sống lành mạnh; không đưa ra phác đồ điều trị hay chẩn đoán thay thế bác sĩ.
   - Trên Community: Nghiêm cấm các huy hiệu "Bác sĩ kiểm duyệt" hoặc cam kết "AI chẩn đoán" không có cơ sở xác thực.

---

## 7. LỘ TRÌNH TRIỂN KHAI KỸ THUẬT (DEVELOPMENT ROADMAP)

```
[Sprint 1 - 2: Journal & Editorial CMS]
├── CMS tích hợp bài viết chuẩn khoa học & chuyên mục
├── Module tìm kiếm R02 liên kết DB thực phẩm & bài tập
└── Tích hợp Entry Card chuyển cảnh từ Home vào Journal

[Sprint 3 - 4: Community Core & Media-First Composer]
├── Bảng tin R03 & Khám phá R04
├── Luồng tạo bài 4 bước: R06A (Select) ➔ R06B (Edit) ➔ R06C (Order) ➔ R06D (Publish)
└── Bộ chọn dữ liệu đính kèm R07 (Workout & Nutrition Data Adapter)

[Sprint 5 - 6: Social Interactions & Profiles]
├── Threaded Comments & Pinned Composer (R05)
├── Profile cộng đồng R09 & Mối quan hệ theo dõi R10
└── Push Notifications (Bình luận, Thích, Nhắc tên @mention)
```

---

## 8. TIÊU CHÍ NGHIỆM THU CHẤT LƯỢNG (ACCEPTANCE CRITERIA)

1. **Hiển thị giao diện (Visual Fidelity):**
   - 100% màn hình hiển thị chuẩn tỷ lệ 390px – 412px, không tràn viền ngang, không co kéo tỷ lệ ảnh.
   - Tông màu tối trầm tĩnh chuẩn Saman, độ tương phản chữ trên nút nền đặc đạt tối thiểu 4.5:1 (WCAG AA).
2. **Ngôn ngữ & Nội dung (UX Copywriting):**
   - 100% giao diện, nhãn nút, placeholder và thông báo lỗi sử dụng tiếng Việt tự nhiên, chuẩn văn phong thể thao và dinh dưỡng.
3. **Tính toàn vẹn điều hướng (Zero Dead Clicks):**
   - Mọi nút Back (`←`), Đóng (`✕`), Tiếp, Xong, Chia sẻ đều được định tuyến đến đúng màn hình kế tiếp hoặc quay về màn hình trước đó mà không làm mất bản nháp dở dang.
   - Không xuất hiện bất kỳ header kép hay thanh bottom navigation xung đột nào trên các màn hình con.
4. **Hiệu năng & Tối ưu hóa (Performance):**
   - Thao tác chuyển giữa các ảnh trong album và tráo đổi thứ tự (R06C) đạt 60fps mượt mà trên các thiết bị di động tầm trung trở lên.
