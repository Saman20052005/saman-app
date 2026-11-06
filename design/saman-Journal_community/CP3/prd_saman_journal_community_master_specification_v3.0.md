# PRODUCT REQUIREMENTS DOCUMENT (PRD) & PRODUCT BRIEF
## Dự án: Saman Journal & Standalone Saman Community (Mobile Experience)
**Trạng thái:** Hoàn thiện Đặc tả Hệ thống Toàn diện (Full System Specification: CP-01, CP-02, CP-02 Polish, CP-03 & CP-03 Readability Polish)  
**Phiên bản:** v3.0 — Production-Ready Master Specification  
**Tác giả:** Senior Mobile Product Design Team  
**Nền tảng:** iOS & Android (Mobile Native App) — Viewport chuẩn 390px – 412px (Touch Target ≥ 44px)  
**Hệ thống thiết kế tham chiếu:** Saman Home, Saman Obsidian Kinetic Design System (Chế độ tối thể thao cao cấp: `#0c0d0e`, `#16171b`, `#08664F`, `#8AD8BD`, `#24272B`)  

---

## 1. TỔNG QUAN DỰ ÁN & BỐI CẢNH CHIẾN LƯỢC (PROJECT BRIEF & EXECUTIVE SUMMARY)

### 1.1. Bối cảnh sản phẩm
**Saman** là ứng dụng di động cao cấp hướng đến tối ưu hóa thể lực, giáo án tập luyện và dinh dưỡng khoa học cá nhân hóa trên nền tảng AI (Aesthetic Athletic Minimalism & Dark Mode). Ứng dụng ban đầu tập trung vào các công cụ tiện ích cốt lõi (Utility-First):
- **Home:** Bảng điều khiển tổng hợp cá nhân hóa, AI Coach daily line, tóm tắt bài tập trong ngày, mục tiêu dinh dưỡng hàng ngày (Daily Targets), tính nhất quán theo tuần (Consistency) và gợi ý Saman Picks.
- **Workout:** Quản lý và thực thi giáo án tập luyện, ghi chép khối lượng tạ/reps và phân tích tiến độ nâng tạ.
- **Saman AI Coach:** Trợ lý ảo phản hồi thông minh về kỹ thuật, giấc ngủ và phục hồi thần kinh - cơ.
- **Nutrition:** Nhật ký ghi nhận calo, chỉ số đa lượng (Protein, Carbs, Fat) và nước.
- **Profile:** Quản lý số đo cá nhân, gói hội viên và thiết bị ngoại vi.

### 1.2. Vấn đề giải quyết & Khoảng trống trải nghiệm
Người dùng truyền thống chỉ mở Saman tại 2 thời điểm: khi đang tập tại phòng gym và khi kết thúc bữa ăn để log dinh dưỡng. Sản phẩm thiếu:
1. **Khoảng trống tri thức (Knowledge Gap):** Người dùng cần tài liệu chuẩn hóa về phục hồi sau đau mỏi cơ bắp (DOMS recovery), kỹ thuật chuyển động phức hợp (Compound lifts), hướng dẫn chuẩn bị bữa ăn (Meal prep) lành mạnh có kiểm duyệt khoa học.
2. **Tính gắn kết & Giữ chân (Social Retention & Engagement):** Cần một không gian tương tác lành mạnh, nơi các hội viên chia sẻ khoảnh khắc nỗ lực, đĩa thức ăn dinh dưỡng, thảo luận kinh nghiệm thực tế mà không bị nhiễu loạn bởi quảng cáo hay các yếu tố mạng xã hội giật gân, độc hại.

### 1.3. Mục tiêu chiến lược (Objectives & Key Results - OKRs)
* **Objective 1 (Retention):** Tăng tỷ lệ giữ chân D30 thêm **+18%** nhờ thói quen đọc bài viết Journal và theo dõi cộng đồng ngoài giờ tập.
* **Objective 2 (Session Frequency):** Đạt trung bình **3.5 phiên mở app/ngày** trên mỗi người dùng tích cực (DAU).
* **Objective 3 (Data Sharing Rate):** Ít nhất **25%** người dùng sau khi hoàn thành buổi tập hoặc bữa ăn chủ động chia sẻ tóm tắt lên Saman Community.
* **Objective 4 (Brand Cohesion):** Bảo toàn **100%** nhận diện thương hiệu cao cấp từ Saman Home: tối giản, trầm tĩnh, thanh lịch, chuẩn mực thể thao và bảo vệ dữ liệu riêng tư tuyệt đối.

---

## 2. PHÂN TÁCH PHÂN HỆ & NGUYÊN TẮC CỐT LÕI (PRODUCT SEPARATION)

Hệ thống được kiến trúc phân tách rành mạch thành hai phân hệ độc lập:

| Tiêu chí | SAMAN JOURNAL (Tri thức & Cẩm nang) | SAMAN COMMUNITY (Mạng xã hội thể thao & Lối sống) |
|---|---|---|
| **Bản chất nội dung** | Nội dung biên tập tĩnh (Curated & Editorial Content) có thẩm định khoa học. | Nội dung do người dùng tạo (UGC - User Generated Content), tương tác 2 chiều. |
| **Vai trò người dùng** | Đọc, tra cứu, lưu trữ kiến thức khoa học (Consumer). | Đăng bài, hỏi đáp, theo dõi bạn tập, lưu bản nháp (Creator & Collaborator). |
| **Cấu trúc Tab** | 3 tab nội bộ: **Khám phá / Thư viện / Cẩm nang**. (Tuyệt đối không có tab Cộng đồng). | Bộ lọc Feed: **Dành cho bạn / Đang theo dõi / Hỏi đáp**. |
| **Hệ thống điều hướng** | Độc lập toàn màn hình, nút Back (`←`) về Saman Home. Tạm ẩn Bottom Nav chính để tối đa diện tích đọc. | Kích hoạt thanh **Community Bottom Navigation** riêng biệt (5 tabs: Bảng tin, Khám phá, Tạo bài [+], Thông báo, Cá nhân). |
| **Phạm vi tìm kiếm** | `R02_Journal_Search`: Chỉ tra cứu bài viết, bài tập, thực phẩm, công thức (không ra post/thành viên). | `R04_Community_Discover`: Khám phá bài post, hashtag cộng đồng (#) và hồ sơ thành viên. |
| **Cửa ngõ liên kết** | Card cửa ngõ duy nhất (*"Saman Community Entry Doorway"*) đặt ở cuối trang Journal Discover. | Header có nút Back (`←`) quay lại Journal bất cứ lúc nào. |

---

## 3. KIẾN TRÚC THÔNG TIN & SƠ ĐỒ ĐIỀU HƯỚNG TỔNG THỂ (INFORMATION ARCHITECTURE)

```
[SAMAN HOME (Main App)]
       │
       ├──> [Saman Picks: Card "Saman Journal"]
       │             │
       │             ▼
       │    ┌─────────────────────────────────────────────────────────────┐
       │    │               SAMAN JOURNAL (Full Screen Stack)             │
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
       │  └── Post 3 (Discussion / Q&A): Thu Hà ──────────> [R15_Community_Question_  │
       │                                                                      Detail] │
       │  Dedicated Community Bottom Navigation:                                      │
       │  [Bảng tin (R03)] [Khám phá (R04)] [(+) Tạo bài] [Thông báo (R11)] [Cá nhân  │
       │                                                                       (R09)] │
       └───────────────────────────────┬──────────────────────┬───────────────┬───────┘
                                       │                      │               │
                ┌──────────────────────┴────────┐             │               ▼
                ▼                               ▼             │      [R09_Community_Profile]
        [R04_Community_Discover]     [Bottom Sheet: Tạo bài]  │      - Stats, Posts, Q&A
        - Search: Posts, Topics      ├── "Bài viết" ───────┐  │      - Nút [Chỉnh sửa hồ sơ]
        - 3-Column Photo Grid        ├── "Chia sẻ bài tập" ─┐ │      │    └──> [R14_Edit_Profile]
        - Trending Hashtags (#)      ├── "Chia sẻ bữa ăn" ──┐ │      - Menu cá nhân:
        - Who to Follow              └── "Đặt câu hỏi" ──┐│ │ │           ├──> [R12_Community_Saved]
                                                         ││ │ │           └──> [R13_Community_Drafts]
                                                         ││ │ │
   ┌─────────────────────────────────────────────────────┘│ │ │
   │                                                      │ │ │
   ▼ [R08_Community_Ask_Question]                         │ │ │
   - Tiêu đề câu hỏi / Mô tả bối cảnh                     │ │ │
   - Chọn chủ đề bắt buộc (Dinh dưỡng / Tập luyện)        │ │ │
   - Nút "Đăng câu hỏi"                                   │ │ │
                                                          │ │ │
   ┌──────────────────────────────────────────────────────┘ │ │
   │                                                        │ │
   ▼ [R07_Community_Select_Attachment_Refined]              │ │
   - 2 Tab: [Buổi tập] | [Bữa ăn]                           │ │
   - Privacy Switches: Khối lượng tạ tắt mặc định          │ │
   - Nút "Đính kèm vào bài viết" ─────────────────────┐     │ │
                                                      │     │ │
   ┌──────────────────────────────────────────────────┼─────┘ │
   │                                                  │       │
   ▼ LUỒNG TẠO BÀI MEDIA-FIRST:                       │       │
   ├── R06A_Post_Select_Media (Chọn ảnh, tiếp tục)    │       │
   │      │                                           │       │
   │      ▼                                           │       │
   ├── R06B_Post_Edit_Media (Cắt góc, chỉnh sáng)     │       │
   │      │                                           │       │
   │      ▼                                           │       │
   ├── R06C_Post_Album_Order (Sắp xếp thứ tự ảnh)     │       │
   │      │                                           │       │
   │      ▼                                           │       │
   └── R06D_Post_Compose_Publish (Thumbnail + Caption)│       │
          └── [Header Action: Chia sẻ] ───────────────┘       │
                                                              ▼
                                                   [R11_Community_Notifications]
                                                   - Filters: Tất cả / Bình luận / Theo dõi
                                                   - Grouped: Hôm nay / Trước đó
                                                   - Click Post ➔ R05 | Click Question ➔ R15
```

---

## 4. ĐẶC TẢ CHI TIẾT TỪNG MÀN HÌNH (DETAILED SCREEN SPECIFICATIONS)

### 4.1. Phân hệ 1: Saman Journal (Tri thức & Cẩm nang)

#### `R01_Journal_Discover` — Khám phá tri thức
- **Header:** Nút Back (`<`) về Saman Home, Tiêu đề `Saman Journal`, nút Bookmark bài viết đã lưu.
- **Tabs (3 tab duy nhất):** *Khám phá* (Active với gạch chỉ báo), *Thư viện*, *Cẩm nang*.
- **Search Trigger Bar:** Input dạng button read-only với placeholder *"Tìm kiến thức, bài tập, món ăn…"*, chạm vào mở mượt sang `R02`.
- **Hero Editorial Card:** Ảnh tỷ lệ 16:10 moody gym recovery, tag `PHỤC HỒI`, tiêu đề *"Phục hồi tốt hơn sau buổi tập chân"*, metadata `4 phút đọc`.
- **Topic Navigation:** Dải chip cuộn ngang: *Tất cả*, *Tập luyện*, *Dinh dưỡng*, *Phục hồi*, *Thói quen*.
- **Tiếp tục đọc (Resume Reading):** Card ngang bài viết dở *"Hiểu calories và các chất dinh dưỡng"*, tiến độ `Đã đọc 40% • Còn 3 phút`.
- **Thư viện tri thức:** 2 card cân xứng: *“Bài tập & lịch tập”* (128 chuyển động) và *“Thực phẩm & công thức”* (240+ dữ liệu chuẩn).
- **Cửa ngõ Saman Community:** Card entry nổi bật với cụm avatar thành viên và thông điệp *"Chia sẻ hành trình. Cùng nhau tiến bộ"*, CTA dẫn vào `R03`.

#### `R02_Journal_Search` — Tìm kiếm cẩm nang & dinh dưỡng
- **Header:** Nút Back về `R01`, Input tìm kiếm đang có từ khóa `"protein"`, nút Clear (`X`), nút Filter chuyên sâu.
- **Bộ lọc chuyên mục:** *Tất cả* (Active), *Bài viết*, *Bài tập*, *Thực phẩm*, *Công thức* (Tuyệt đối không hiển thị bài post mạng xã hội).
- **Kết quả phân nhóm:**
  - *Bài viết:* *"Hiểu protein trong bữa ăn hằng ngày"* (5 phút đọc).
  - *Thực phẩm:* *"Ức gà"* (Tick chính thức, 31g Protein/100g, nút `+` nhanh vào Nutrition).
  - *Công thức:* *"Sữa chua, yến mạch & quả mọng"* (24g Protein, nút bookmark).
  - *Bài tập:* *"Tập tạ và tổng hợp protein"*.
  - *Saman Advice Card:* Khuyến nghị nạp 1.6 – 2.2g protein/kg trọng lượng cơ thể.

---

### 4.2. Phân hệ 2: Saman Community (Feed, Discover, Post Detail & Profiles)

#### `R03_Community_Feed` — Bảng tin cộng đồng
- **Header:** Nút Back về Journal, tiêu đề `Saman Community` có đèn trạng thái online, icon Direct Message góc phải.
- **Bộ lọc Feed:** 3 tab: *Dành cho bạn* (Active), *Đang theo dõi*, *Hỏi đáp*.
- **3 Định dạng bài đăng mẫu (Archetypes):**
  1. *Bữa ăn / Photo:* Linh Nguyễn chia sẻ hộp cơm ức gà, ảnh 4:3, chỉ số macro badge (`42g Protein`, `480 kcal`), thanh tương tác Like/Bình luận/Lưu.
  2. *Đính kèm bài tập:* Minh Khang đính kèm thẻ **Saman Kinetic Workout Card** (`BUỔI TẬP ĐÃ HOÀN THÀNH`, *Upper Body Hypertrophy*, 45 phút, 5 bài tập, 12 hiệp, CTA *"Xem buổi tập →"*).
  3. *Hỏi đáp cộng đồng:* Thu Hà đặt câu hỏi chuẩn bị bữa ăn, đếm 25 phản hồi, CTA *"Tham gia thảo luận →"* (dẫn sang `R15`).
- **Community Bottom Navigation:** 5 tab cố định (*Bảng tin*, *Khám phá*, *[+] Tạo bài*, *Thông báo*, *Cá nhân*).

#### `R04_Community_Discover` — Khám phá cộng đồng
- **Header & Search:** Ô tìm kiếm *"Tìm bài viết, chủ đề, thành viên…"*, hàng chip phân loại (*Tất cả, Tập luyện, Bữa ăn, Công thức, Hỏi đáp*).
- **Lưới ảnh 3 cột (Photo Grid):** Khoảnh khắc gym, bữa ăn, calisthenics, kèm icon album nhiều ảnh.
- **Chủ đề thịnh hành (Trending Hashtags):** `#MealPrepCuoiTuan` (+28%), `#TangCoGiamMo` (+45%), `#HoiDapDinhDuong`.
- **Gợi ý theo dõi:** Card HLV Hoàng Long, Thảo Mai kèm nút CTA `+ Theo dõi`.

#### `R05_Community_Post_Detail` — Chi tiết bài viết & Luồng thảo luận
- **Header:** Nút Back về Feed, icon bookmark, không có bottom nav.
- **Nội dung:** Toàn bộ nội dung bài viết gốc Linh Nguyễn kèm ảnh hộp cơm lớn.
- **Thread thảo luận (18 bình luận):** Bình luận từ Minh Khang, câu trả lời từ tác giả Linh Nguyễn (Badge `Tác giả` xanh ngọc), bình luận từ Thu Hà.
- **Pinned Composer:** Cố định đáy màn hình với an toàn Safe Area, ô *"Viết bình luận…"*, icon emoji và nút gửi kích hoạt nhanh.

#### `R09_Community_Profile` — Hồ sơ cộng đồng
- **Header:** Nút Back, menu ba chấm (chứa menu: *Đã lưu*, *Bản nháp*).
- **Thông tin:** Avatar, Tên Linh Nguyễn, Username `@linhnguyen.fit`, Bio tập luyện bền bỉ cùng Saman.
- **Số liệu:** `38` Bài viết, `2.4k` Người theo dõi (nhấn mở `R10`), `186` Đang theo dõi.
- **Hành động:** Nút *"Chỉnh sửa hồ sơ"* (mở `R14`) và *"Chia sẻ"*.
- **Lưới nội dung:** 2 tab *Bài viết (32)* và *Hỏi đáp (6)*.

#### `R10_Community_Follow_List` — Danh sách theo dõi
- **Header & Tabs:** 2 tab *Người theo dõi (2.4k)* và *Đang theo dõi (186)*.
- **Tìm kiếm:** Ô tra cứu thành viên theo tên hoặc `@handle`.
- **Danh sách thành viên:** Danh sách người theo dõi thực tế; hàng tài khoản của chính mình có nhãn *"Hồ sơ của bạn"* và không hiển thị nút tự theo dõi chính mình.

---

### 4.3. Phân hệ 3: Luồng Tạo bài viết Media-First (CP-02 & Polish)

#### Quy trình tạo nội dung tổng thể:
Nhấn nút **(+)** tại Community Bottom Nav mở Bottom Sheet *"Tạo nội dung"*:
1. *"Bài viết"* → `R06A` (Chọn ảnh).
2. *"Chia sẻ buổi tập"* → `R07` (Tab Buổi tập) → `R06D` (Xem trước & Đăng).
3. *"Chia sẻ bữa ăn"* → `R07` (Tab Bữa ăn) → `R06D` (Xem trước & Đăng).
4. *"Đặt câu hỏi"* → `R08_Community_Ask_Question`.

#### `R06A_Post_Select_Media` — Chọn ảnh & Media
- **Header:** `Đóng (✕)` | `Bài viết mới` | text action `Tiếp` (`#8AD8BD` / `#54C7A5` - bật khi chọn ≥ 1 ảnh).
- **Preview lớn:** Vùng ảnh đang chọn ở nửa trên với icon crop/fit tròn nhỏ.
- **Điều khiển:** Dropdown album *"Gần đây"* bên trái, nút *"Chọn nhiều"* nền charcoal bên phải.
- **Lưới thư viện 3 cột:** Ô Camera chụp ảnh, các ô ảnh tiếp theo có vòng tròn số thứ tự album (`1`, `2`) nền emerald trầm `#08664F`.
- **Lối thoát văn bản:** Link chân trang *"Đăng chỉ với nội dung văn bản →"* chuyển thẳng sang R06D mà không cần chọn ảnh.

#### `R06B_Post_Edit_Media` — Chỉnh ảnh & Cắt góc
- **Header:** `Back (←)` | `Chỉnh ảnh` | text action `Tiếp`.
- **Khung chỉnh ảnh:** Ảnh trung tâm sắc nét, dải thumbnail nhỏ bên dưới để chuyển giữa các ảnh trong album.
- **Crop Controls:** 3 chế độ: *"Gốc"*, *"Vuông"* (1:1), *"Dọc"* (4:5) và nút xoay ảnh 90°.
- **Slider tinh chỉnh:** Thanh trượt *"Độ sáng"* và *"Độ tương phản"* thanh lịch, nút *"Đặt lại"* xuất hiện khi có thay đổi.

#### `R06C_Post_Album_Order` — Sắp xếp thứ tự Album
- **Header:** `Back (←)` | `Sắp xếp ảnh` | text action `Xong`.
- **Lưới Thumbnail:** Đánh số thứ tự từng ảnh trong album, icon kéo thả (drag handle) để tráo đổi vị trí, nút gỡ bỏ ảnh (`✕`) và ô viền đứt nét *"+ Thêm ảnh"*.
- **Ảnh bìa:** Ảnh số 1 tự động gắn badge nhãn `Ảnh bìa` đại diện trên Feed.

#### `R06D_Post_Compose_Publish` — Soạn nội dung & Chia sẻ
- **Header:** `Back (←)` | `Bài viết mới` | text action chính `Chia sẻ` (`#8AD8BD` / `#54C7A5`) góc trên bên phải. Không lặp nút đăng ở đáy màn hình.
- **Soạn thảo:** Avatar & Tên tác giả Linh Nguyễn, ô nhập văn bản tự nhiên kèm theo **Thumbnail ảnh vuông nhỏ gọn** đặt cạnh trường viết (có badge đếm số ảnh `2 ảnh` - bấm vào để mở R06C).
- **Hàng cài đặt tinh giản (Lightweight Settings Rows):**
  - *Ai có thể xem?* → `Công khai`.
  - *Chủ đề* → `#BữaĂn`.
  - *Đính kèm hoạt động* → `Chưa đính kèm` (mở R07).
  - *Cài đặt bình luận* → `Bật`.

#### `R07_Community_Select_Attachment_Refined` — Đính kèm hoạt động
- **Header:** `Back (←)` | `Đính kèm hoạt động`.
- **2 Tab dữ liệu:** *Buổi tập* (Mặc định) và *Bữa ăn*.
- **Danh sách theo ngày:** Các buổi tập gần đây với radio checkmark xanh ngọc.
- **Thông tin hiển thị (Privacy Controls):**
  - Tên buổi tập & Thời lượng: Text tĩnh, nhãn `Bắt buộc`.
  - Danh sách bài tập: Switch bật/tắt (Mặc định Bật).
  - Khối lượng tạ & Số hiệp: Switch bật/tắt (**Mặc định Tắt** để bảo vệ quyền riêng tư).
  - Cam kết bảo mật: *"Saman không bao giờ tự động chia sẻ cân nặng, chỉ số đo cơ thể hoặc dữ liệu sức khỏe riêng tư."*
- **CTA cố định chân trang:** Nút nền `#08664F`, chữ trắng: *"Đính kèm vào bài viết"*.

#### `R08_Community_Ask_Question` — Đặt câu hỏi thảo luận
- **Header:** `Đóng (✕)` | `Đặt câu hỏi` | Nút `Đăng câu hỏi` (`#08664F`).
- **Chủ đề thảo luận:** Hàng chip chọn 1: *Dinh dưỡng* (Active), *Tập luyện*, *Phục hồi*.
- **Nội dung:** Ô tiêu đề câu hỏi (bộ đếm ký tự `63/150`), ô mô tả bối cảnh chi tiết, tùy chọn đính kèm ảnh minh họa.

---

### 4.4. Phân hệ 4: Thông báo, Lưu trữ, Bản nháp & Thảo luận (CP-03 & Polish)

#### `R11_Community_Notifications` — Thông báo cộng đồng
- **Điểm vào:** Tab *"Thông báo"* trên thanh điều hướng Community (Active, có bottom nav 5 tabs).
- **Header:** Tiêu đề duy nhất *"Thông báo"*, icon Cài đặt thông báo góc phải, thao tác *"Đã đọc"*.
- **Bộ lọc:** 3 chip tinh gọn: *Tất cả*, *Bình luận*, *Theo dõi*.
- **Danh sách theo nhóm thời gian:**
  - *Hôm nay:* Bình luận bài viết hộp cơm (có thumbnail ảnh, chấm chưa đọc `#8AD8BD`), Lượt thích bữa ăn, Câu trả lời cho câu hỏi (nhấn mở sang `R15`), Thông báo theo dõi kèm nút *"Theo dõi lại"* nền `#24272B`, chữ sáng.
  - *Trước đó:* Nhắc tên @mention và lượt thích buổi tập (đã đọc).
- **Điều hướng:** Click thông báo bài post → `R05`; Click thông báo câu hỏi → `R15`; Click avatar → `R09`.

#### `R12_Community_Saved` — Bài cộng đồng đã lưu
- **Điểm vào:** Mở từ menu hồ sơ của chính mình trong `R09`. Màn hình Stack (Back arrow, không bottom nav).
- **Header & Quyền riêng tư:** Nút Back, Tiêu đề *"Đã lưu"*, dòng giải thích trung tính *"Chỉ bạn nhìn thấy nội dung đã lưu"* màu `#9399A1`, icon chuyển đổi grid/list.
- **Bộ lọc:** *Tất cả*, *Bài viết*, *Hỏi đáp*.
- **Lưới 2 cột trực quan có ảnh lớn:** Bài bữa ăn của Thu Hà, Thẻ buổi tập của Minh Khang, Thẻ câu hỏi chuẩn bị bữa ăn (mở `R15`), Bài hành trình của Tiến Đạt.
- **Tương tác:** Icon bookmark rõ nét, hỗ trợ hoàn tác nhanh qua snackbar khi gỡ lưu. Tuyệt đối không trộn bài viết Journal vào màn này.

#### `R13_Community_Drafts` — Bản nháp riêng tư
- **Điểm vào:** Mở từ menu hồ sơ của chính mình trong `R09`. Màn hình Stack phụ.
- **Header:** Nút Back, Tiêu đề *"Bản nháp"*, chỉ báo riêng tư an toàn.
- **Danh sách hàng thoáng đãng (Row layout):**
  - *Bản nháp 1:* Album bài viết 2 ảnh bữa ăn (nhấn mở thẳng `R06D`).
  - *Bản nháp 2:* Chia sẻ buổi tập PR Deadlift (nhấn mở `R06D`).
  - *Bản nháp 3:* Câu hỏi dở về Creatine (nhấn mở `R08`).
  - *Bản nháp 4:* Bài viết chỉ có văn bản về phục hồi cơ.
- **Tương tác:** Toàn bộ hàng có thể nhấn để tiếp tục soạn thảo; menu ba chấm chứa tùy chọn *"Tiếp tục chỉnh sửa"* và *"Xóa bản nháp"* (kèm popup xác nhận).

#### `R14_Community_Edit_Profile` — Chỉnh sửa hồ sơ cộng đồng
- **Điểm vào:** Nút *"Chỉnh sửa hồ sơ"* trong `R09` của chính mình.
- **Header:** Nút Back, Tiêu đề *"Chỉnh sửa hồ sơ"*, text action *"Lưu"* (`#8AD8BD`) ở góc trên bên phải (bị disabled khi chưa có thay đổi). Không có nút lớn ở đáy.
- **Ảnh đại diện:** Avatar tròn trung tâm với nút camera, đồng bộ tài khoản (*"Ảnh đại diện cũng được cập nhật đồng bộ trong ứng dụng Saman"*), sheet đổi ảnh (chụp mới, thư viện, xóa ảnh).
- **Trường nhập liệu:**
  - Tên hiển thị: *Linh Nguyễn*.
  - Tên người dùng: *@linhnguyen.fit* với icon check nhỏ và dòng ngắn `✓ Tên người dùng khả dụng`.
  - Giới thiệu bản thân: Bộ đếm ký tự `98/150`.
  - Chủ đề quan tâm: Dạng chip chọn tối đa 3 (*Tập luyện, Dinh dưỡng, Nấu ăn, Phục hồi, Thói quen*) dùng nền charcoal `#24272B` + chữ trắng + icon check.
- **Bảo mật:** Dòng giải thích ngắn gọn: *"Những thông tin này hiển thị trên hồ sơ cộng đồng của bạn."* Tuyệt đối không chứa số đo cơ thể, cân nặng hay mục tiêu calo.

#### `R15_Community_Question_Detail` — Chi tiết hỏi đáp & Thảo luận
- **Điểm vào:** Feed Hỏi đáp (`R03`), tab Hỏi đáp trong `R09`, thông báo `R11` hoặc danh sách đã lưu `R12`.
- **Header:** Nút Back, Tiêu đề *"Thảo luận"*, menu ba chấm.
- **Phần câu hỏi gốc:**
  - Tác giả Thu Hà, thời gian `3 giờ trước`, badge chủ đề `MEAL PREP`.
  - Tiêu đề câu hỏi lớn nổi bật: *"Bạn thường chuẩn bị bữa ăn (meal prep) cho cả tuần như thế nào để giữ độ tươi ngon?"*.
  - Mô tả bối cảnh và ảnh hộp thực phẩm tủ lạnh ngăn nắp.
  - Nút hành động: *Theo dõi câu hỏi*, *Đã lưu*, *Chia sẻ* (nền `#24272B`, chữ sáng `#F2F4F5`).
- **Phần câu trả lời & Thread thảo luận:**
  - Sắp xếp: *Hữu ích nhất* / *Mới nhất*.
  - **Câu trả lời hữu ích nhất (Được người hỏi lựa chọn):** HLV Hoàng Long với nhãn trung tính `Người hỏi lựa chọn là câu trả lời hữu ích` (kèm icon check nhỏ), 48 lượt hữu ích, kèm reply thread cảm ơn từ tác giả Thu Hà.
  - Câu trả lời từ Minh Khang về hộp thủy tinh ron cao su.
- **Pinned Composer:** Cố định đáy màn hình, ô *"Chia sẻ câu trả lời của bạn..."*, nút gửi nền `#08664F`, icon trắng `#FFFFFF` (touch target ≥ 44px). Ẩn bottom nav để tập trung thảo luận.

---

## 5. DESIGN SYSTEM & DESIGN TOKENS (SAMAN OBSIDIAN KINETIC)

Hệ thống token sau khi hoàn thiện vòng tinh chỉnh Final Readability & Button Polish (đạt 100% chuẩn WCAG AA Contrast):

| Phân loại Token | Tên Token / CSS Variable | Mã Màu HEX / Quy chuẩn | Phạm vi & Ngữ cảnh áp dụng |
|---|---|---|---|
| **Canvas Background** | `surface-base` | `#0c0d0e` | Nền canvas toàn màn hình, Status bar, Bottom Nav |
| **Card Surface** | `surface-card` | `#16171b` / `#16171a` | Bề mặt container các card bài viết, feed item, settings box |
| **Secondary Button** | `button-secondary` | `#24272B` | Nút phụ: Theo dõi lại, Hữu ích, Trả lời, Lưu, Chia sẻ |
| **Subtle Border** | `border-subtle` | `#23252a` / `#272930` | Đường viền mảnh ngăn cách section, viền ảnh |
| **Primary Solid Button** | `brand-emerald-solid` | `#08664F` | Nút nền đặc chính: Đính kèm, Đăng, Gửi, (+) Bottom Nav |
| **Text Action Accent** | `brand-emerald-action` | `#8AD8BD` (hoặc `#54C7A5`) | Chữ hành động header (Tiếp, Xong, Chia sẻ, Lưu), chấm chưa đọc |
| **Chip Active** | `chip-active` | Nền `#24272B` + Chữ `#FFFFFF` | Chip bộ lọc và chủ đề đang chọn (kèm check nhỏ) |
| **Disabled Surface** | `surface-disabled` | Nền `#25282C` + Chữ `#9399A1` | Trạng thái nút chưa đủ điều kiện nhấn |
| **Typography - Primary** | `text-primary` | `#FFFFFF` / `#F2F4F5` | Tiêu đề H1, H2, câu hỏi lớn, tên tác giả, nhãn nút chính |
| **Typography - Muted** | `text-muted` | `#9399A1` / `#94979e` | Phụ đề, timestamp, nhãn ghi chú bảo mật |
| **Typography Size** | `font-body-regular` | `15px` – `16px` | Cỡ chữ nội dung đọc chuẩn mobile (không co nhỏ chữ) |
| **Corner Radius - LG** | `rounded-2xl` | `16px` | Bo góc card bài viết, hero card, bottom sheet |
| **Corner Radius - MD** | `rounded-xl` | `12px` | Bo góc thumbnail ảnh, action pill button |
| **Touch Target** | `touch-target-min` | `≥ 44px × 44px` | Vùng chạm tối thiểu trên mọi nút bấm cảm ứng |

---

## 6. NGUYÊN TẮC BẢO MẬT & ĐẠO ĐỨC DỮ LIỆU SỨC KHỎE (PRIVACY & ETHICAL RULES)

1. **Chủ động công khai (Explicit User Opt-in):**
   - Đăng bài và đính kèm dữ liệu là hành động hoàn toàn chủ động của người dùng. Ứng dụng không bao giờ tự động đăng kết quả buổi tập hoặc bữa ăn ngay khi hoàn thành bài tập.
2. **Cô lập dữ liệu sức khỏe & cơ thể nhạy cảm (Health Data Quarantine):**
   - Nghiêm cấm chia sẻ lên Community: Cân nặng hiện tại, số đo vòng eo/vòng cơ, ảnh tiến độ cơ thể (Body progress photos), nhịp tim nghỉ, calo tiêu hao nhạy cảm.
   - Khi chia sẻ buổi tập qua R07: Khối lượng tạ (Weights) và số hiệp (Reps) luôn ở trạng thái **TẮT mặc định**, chỉ hiển thị khi người dùng chủ động gạt switch bật.
3. **Không tạo huy hiệu giả & Không y tế hóa thông tin:**
   - Không gắn nhãn "Chuyên gia y khoa", "Bác sĩ kiểm duyệt" hay "AI chẩn đoán" lên các bài đăng UGC.
   - Các câu trả lời hữu ích trong R15 chỉ thể hiện sự đồng thuận của cộng đồng và người hỏi, không có giá trị thay thế phác đồ điều trị y khoa.

---

## 7. MA TRẬN LIÊN KẾT NGUYÊN MẪU (PROTOTYPE INTERACTION MATRIX)

| Thao tác người dùng | Màn hình bắt đầu | Màn hình đích đến | Ghi chú chuyển cảnh & Trạng thái |
|---|---|---|---|
| Chạm card Saman Journal tại Home | `Home` | `R01_Journal_Discover` | Ẩn main bottom nav, hiện header Back |
| Chạm ô tìm kiếm Journal | `R01_Journal_Discover` | `R02_Journal_Search` | Chuyển cảnh tức thời, focus input |
| Chạm Doorway Card cuối Journal | `R01_Journal_Discover` | `R03_Community_Feed` | Kích hoạt Community Bottom Nav |
| Chạm bài post của Linh Nguyễn | `R03_Community_Feed` | `R05_Community_Post_Detail` | Ẩn bottom nav, hiện pinned composer |
| Chạm câu hỏi của Thu Hà | `R03_Community_Feed` | `R15_Community_Question_Detail`| Mở thread hỏi đáp, câu trả lời hữu ích |
| Chạm nút (+) tại Community Nav | `R03` / `R04` / `R11` | Bottom Sheet "Tạo nội dung" | Sheet chọn: Bài viết / Buổi tập / Bữa ăn / Câu hỏi |
| Chọn "Bài viết" từ (+) Sheet | Bottom Sheet | `R06A_Post_Select_Media` | Chọn ảnh trong thư viện ➔ Nhấn "Tiếp" |
| Nhấn "Tiếp" sau khi chọn ảnh | `R06A_Post_Select_Media` | `R06B_Post_Edit_Media` | Cắt tỉ lệ (1:1, 4:5), chỉnh sáng/tương phản |
| Chạm vào ảnh thumbnail album | `R06B` hoặc `R06D` | `R06C_Post_Album_Order` | Đổi thứ tự kéo thả, đặt ảnh bìa ➔ "Xong" |
| Nhấn "Tiếp" từ màn chỉnh ảnh | `R06B_Post_Edit_Media` | `R06D_Post_Compose_Publish` | Soạn caption, cài đặt ➔ Nhấn "Chia sẻ" |
| Chọn "Chia sẻ buổi tập/bữa ăn" | Bottom Sheet | `R07_Community_Select_Attachment`| Chọn dữ liệu ➔ "Đính kèm" về bản nháp R06D |
| Chọn "Đặt câu hỏi" | Bottom Sheet | `R08_Community_Ask_Question` | Soạn câu hỏi ➔ "Đăng câu hỏi" |
| Chạm Tab "Thông báo" trên Nav | Community Nav | `R11_Community_Notifications` | Tab Thông báo active, phân nhóm Hôm nay |
| Mở Menu cá nhân ➔ "Đã lưu" | `R09_Community_Profile` | `R12_Community_Saved` | Lưới 2 cột nội dung đã bookmark |
| Mở Menu cá nhân ➔ "Bản nháp" | `R09_Community_Profile` | `R13_Community_Drafts` | Danh sách bản nháp dở ➔ Chạm mở lại R06D/R08 |
| Nhấn "Chỉnh sửa hồ sơ" | `R09_Community_Profile` | `R14_Community_Edit_Profile` | Đổi avatar, bio ➔ Nhấn "Lưu" trên header |
| Nhấn vào số Người theo dõi | `R09_Community_Profile` | `R10_Community_Follow_List` | Danh sách 2 tabs: Người theo dõi & Đang theo dõi |

---

## 8. LỘ TRÌNH TRIỂN KHAI KỸ THUẬT & TIÊU CHÍ NGHIỆM THU (ROADMAP & ACCEPTANCE CRITERIA)

### 8.1. Lộ trình phát triển (6 Sprints)
- **Sprint 1 & 2 (Journal & Search Engine):** Triển khai giao diện đọc `R01`, tích hợp full-text search `R02` liên kết database dinh dưỡng và bài tập.
- **Sprint 3 & 4 (Community Core & Media Composer):** Xây dựng Bảng tin `R03`, Khám phá `R04`, quy trình tạo bài 4 bước `R06A–R06D` và bộ chọn dữ liệu `R07`.
- **Sprint 5 & 6 (Social Engagement, Profiles & Q&A):** Triển khai Post Detail `R05`, Question Detail `R15`, Profile `R09`, Follow List `R10`, Thông báo `R11`, Lưu trữ `R12`, Bản nháp `R13` và Chỉnh sửa hồ sơ `R14`.

### 8.2. Tiêu chí nghiệm thu sản phẩm (Acceptance Criteria)
1. **Visual Fidelity & Typography:**
   - 100% màn hình hiển thị chuẩn xác viewport mobile 390px – 412px, body text 15–16px dễ đọc, khoảng cách thoáng đãng.
   - Hệ thống nút đồng nhất: Nút chính `#08664F`, nút phụ `#24272B`, text action `#8AD8BD`, không còn bất kỳ nút mint sáng neon nào.
   - Tỷ lệ tương phản chữ trên nền tối đạt tối thiểu **4.5:1** (chuẩn WCAG AA).
2. **Ngôn ngữ & Nội dung (UX Copywriting):**
   - 100% giao diện, nhãn nút, thông báo trạng thái và placeholder sử dụng tiếng Việt tự nhiên, chuẩn văn phong thể thao và dinh dưỡng.
3. **Tính toàn vẹn điều hướng (Zero Dead Clicks):**
   - Mỗi màn hình chỉ sở hữu **duy nhất 1 header chức năng**.
   - Mọi nút Back (`←`), Đóng (`✕`), Tiếp, Xong, Chia sẻ, Lưu đều có tuyến điều hướng chính xác, bảo toàn dữ liệu bản nháp khi quay lui.
4. **Hiệu năng & Trải nghiệm (Performance):**
   - Thao tác tráo đổi thứ tự ảnh trong album (R06C), cuộn feed và chuyển đổi bộ lọc đạt tốc độ khung hình 60fps mượt mà trên thiết bị di động.
