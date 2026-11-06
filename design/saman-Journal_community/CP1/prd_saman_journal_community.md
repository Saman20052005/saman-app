# PRODUCT REQUIREMENTS DOCUMENT (PRD) & PRODUCT BRIEF
## Dự án: Saman Journal & Standalone Saman Community (Mobile Experience)
**Trạng thái:** Hoàn thiện thiết kế giai đoạn 1 (Checkpoint CP-01 & Redesign R01–R05)  
**Tác giả:** Senior Mobile Product Design Team  
**Nền tảng:** iOS & Android (Mobile App) — Tối ưu viewport 390px – 412px  
**Thiết kế tham chiếu:** Saman Home, Saman Obsidian Kinetic Design System  

---

## 1. TỔNG QUAN DỰ ÁN (PROJECT BRIEF)

### 1.1. Bối cảnh sản phẩm
Saman là ứng dụng chăm sóc sức khỏe, tập luyện và dinh dưỡng AI cao cấp (Dark Mode Athletic Minimalism). Hệ sinh thái gốc bao gồm 5 trụ cột:
1. **Home:** Bảng điều khiển tổng hợp cá nhân hóa, AI Coach daily line, tóm tắt bài tập trong ngày, mục tiêu dinh dưỡng hàng ngày (Daily Targets), tính nhất quán theo tuần (Consistency) và gợi ý Saman Picks.
2. **Workout:** Không gian thực thi giáo án, ghi nhận tạ/reps và theo dõi tiến trình tập.
3. **Saman (AI Coach):** Trợ lý thông minh hướng dẫn phục hồi, kỹ thuật và cá nhân hóa lộ trình.
4. **Nutrition:** Nhật ký ghi nhận calories, macro và lập kế hoạch bữa ăn.
5. **Profile:** Quản lý thông tin chỉ số cơ thể, cài đặt tài khoản và đăng ký gói hội viên.

### 1.2. Vấn đề cần giải quyết
Trước đây, người dùng chỉ vào Saman để log bài tập hoặc xem số calo. Ứng dụng thiếu:
- **Kiến thức chuẩn hóa (Knowledge Gap):** Người dùng thiếu cẩm nang khoa học về kỹ thuật tập, cách giải quyết đau mỏi cơ (DOMS), meal prep, tính macro chuẩn.
- **Tính gắn kết & Cộng đồng (Social Retention):** Thiếu không gian chia sẻ thành tựu, học hỏi từ bạn tập và đặt câu hỏi thực tế trong sinh hoạt hàng ngày.

### 1.3. Mục tiêu chiến lược (Objectives & Key Results)
- **Tăng DAU/MAU và Retention Rate (D30):** Tăng tỷ lệ mở app ngoài giờ tập thông qua thói quen đọc bài viết kiến thức và lướt tin tức cộng đồng.
- **Tách bạch rõ ràng 2 luồng trải nghiệm:**
  - **Saman Journal:** Điểm đến tri thức tĩnh, biên tập có kiểm duyệt (Curated & Editorial Content).
  - **Saman Community:** Điểm đến xã hội động, do người dùng tạo (UGC - User Generated Content), tương tác 2 chiều.
- **Giữ trọn tính nhất quán nhận diện thương hiệu:** Kế thừa 100% ngôn ngữ thiết kế tối giản, cao cấp, thanh lịch từ Saman Home.

---

## 2. KIẾN TRÚC THÔNG TIN & CẤU TRÚC ĐIỀU HƯỚNG (INFORMATION ARCHITECTURE)

```
[SAMAN HOME]
      │
      ├──> [Saman Picks: Card "Saman Journal"]
      │            │
      │            ▼
      │   ┌───────────────────────────────────────────────┐
      │   │             SAMAN JOURNAL (Full Screen)       │
      │   │  Header: [Back to Home] [Title] [Bookmark]    │
      │   │  Tabs: [Khám phá] | [Thư viện] | [Cẩm nang]   │
      │   │                                               │
      │   │  - Hero Editorial Card (Phục hồi sau Leg Day) │
      │   │  - Topic Navigation Chips                     │
      │   │  - Continue Reading Progress                  │
      │   │  - Knowledge Libraries (Bài tập / Dinh dưỡng) │
      │   │  - Guided Learning (Bắt đầu cùng Saman)       │
      │   │  - Entry Card: "Saman Community Doorway" ─────┼──────┐
      │   └───────────────────────┬───────────────────────┘      │
      │                           ▼                              │
      │                  [Journal Search]                        │
      │                  - Query: "protein"                      │
      │                  - Filters: Tất cả/Bài/Tập/Món           │
      │                                                          │
      └──────────────────────────────────────────────────────────┘
                                                                 │
                                                                 ▼
      ┌──────────────────────────────────────────────────────────────┐
      │            SAMAN COMMUNITY (Mini Social Network)             │
      │  Header: [Back to Journal] [Title: Saman Community] [DM]    │
      │  Feed Filters: [Dành cho bạn] | [Đang theo dõi] | [Hỏi đáp]  │
      │                                                              │
      │  Feed Content:                                               │
      │  - Post 1: Chia sẻ bữa ăn (Linh Nguyễn) ──> [Post Detail]    │
      │  - Post 2: Workout Summary Attachment (Minh Khang)           │
      │  - Post 3: Hỏi đáp tương tác Meal Prep (Thu Hà)              │
      │                                                              │
      │  Dedicated Community Bottom Navigation:                      │
      │  [Bảng tin] [Khám phá] [(+) Đăng bài] [Thông báo] [Cá nhân]  │
      └──────────────────────────────────────────────────────────────┘
```

### 2.1. Quy tắc phân tầng điều hướng (Navigation Hierarchy Rules)
1. **Không trùng lặp Bottom Navigation Bar:**
   - Khi vào **Saman Journal**, thanh bottom navigation chính của app (Home/Workout/Saman/Nutrition/Profile) tạm ẩn để tối ưu diện tích đọc toàn màn hình; Journal có nút Back (`←`) về Home.
   - Khi vào **Saman Community**, ứng dụng kích hoạt **Community Bottom Navigation** riêng biệt (5 tabs: Bảng tin, Khám phá, Tạo bài (+), Thông báo, Cá nhân).
   - Khi vào **Post Detail**, toàn bộ bottom navigation được ẩn để nhường chỗ cho thanh ghim bình luận (**Pinned Comment Composer**).
2. **Không trộn lẫn dữ liệu:**
   - Thanh tìm kiếm Journal (`R02_Journal_Search`) chỉ tìm kiếm nội dung biên tập, bài tập, thực phẩm và công thức; không hiển thị kết quả bài post hay thành viên mạng xã hội.
   - Tìm kiếm bài post, chủ đề hashtag (#) và thành viên diễn ra độc lập trong `R04_Community_Discover`.

---

## 3. ĐẶC TẢ TÍNH NĂNG CHI TIẾT (FEATURE SPECIFICATIONS)

### 3.1. Phân hệ 1: Saman Journal (Tri thức & Cẩm nang)

#### Màn hình: `R01_Journal_Discover`
* **Mục tiêu:** Giúp hội viên tiếp cận kiến thức thể thao, bài tập và dinh dưỡng khoa học một cách tinh tế, không bị ngợp thông tin.
* **Các thành phần UI & Hành vi:**
  1. **Header:**
     - Nút icon `Back` (`<`): Quay lại màn hình Home gốc.
     - Brand mark: Chữ `Saman Journal` (Font sans, semi-bold, white).
     - Action Bookmark: Mở danh sách bài viết / công thức mà người dùng đã bấm lưu.
  2. **Internal Tab Bar:**
     - 3 tab tinh gọn: *Khám phá* (Active - có chỉ báo gạch xanh emerald `#10b981`), *Thư viện*, *Cẩm nang*.
     - Tap để chuyển view nội bộ mà không cần load lại toàn trang.
  3. **Search Trigger Bar:**
     - Input dạng read-only button với placeholder: *"Tìm kiến thức, bài tập, món ăn…"*.
     - Tap vào trường này kích hoạt chuyển cảnh mượt mà sang màn hình `R02_Journal_Search`.
  4. **Hero Editorial Card:**
     - Ảnh tỷ lệ 16:10 phong cách moody fitness recovery.
     - Tag chuyên mục: `PHỤC HỒI` (Pill màu xanh ngọc Saman).
     - Tiêu đề: *"Phục hồi tốt hơn sau buổi tập chân"*.
     - Subtitle: *"Chiến lược giảm đau nhức cơ bắp DOMS và bổ sung glycogen giúp cơ thể sẵn sàng cho chu kỳ tiếp theo."*
     - Metadata: `4 phút đọc`.
     - Tap target: Toàn bộ card có thể nhấn để mở bài viết chi tiết.
  5. **Topic Navigation (Chủ đề quan tâm):**
     - Dải chip cuộn ngang: *Tất cả*, *Tập luyện*, *Dinh dưỡng*, *Phục hồi*, *Thói quen*.
  6. **Tiếp tục đọc (Reading Resume):**
     - Card ngang nhỏ gọn cho bài viết đang đọc dở: *"Hiểu calories và các chất dinh dưỡng"*.
     - Thanh tiến độ mảnh và chỉ số `Đã đọc 40% • Còn 3 phút`.
  7. **Thư viện kiến thức (Knowledge Libraries):**
     - 2 thẻ card cân bằng: *“Bài tập & lịch tập”* (128 chuyển động) và *“Thực phẩm & công thức”* (240+ dữ liệu chuẩn).
  8. **Chuỗi bài nền tảng (Guided Learning):**
     - Series card: *"Bắt đầu cùng Saman"* (5 bài hướng dẫn cơ bản xây dựng thói quen bền bỉ).
  9. **Cổng vào Saman Community (Community Entry Doorway):**
     - Card entry với biểu tượng chat icon và cụm avatar cộng đồng.
     - Tiêu đề: *"Saman Community — Chia sẻ hành trình. Cùng nhau tiến bộ."*
     - CTA text: *"Khám phá cộng đồng ↓"*. Nhấn vào sẽ điều hướng đến `R03_Community_Feed`.

#### Màn hình: `R02_Journal_Search`
* **Mục tiêu:** Cung cấp trải nghiệm tra cứu tức thời, đa danh mục có hệ thống cho kho tri thức Saman.
* **Các thành phần UI & Hành vi:**
  1. **Search Header:**
     - Nút back về `R01_Journal_Discover`.
     - Input field đang có giá trị query `"protein"` kèm nút `X` (Clear text).
     - Nút Filter settings ở bên phải.
  2. **Content Type Filter Chips:**
     - Hàng chip cuộn ngang: *Tất cả*, *Bài viết*, *Bài tập*, *Thực phẩm*, *Công thức*.
  3. **Kết quả tìm kiếm nhóm "Tất cả":**
     - **Bài viết:** Card ngang có ảnh món ăn/bài tập, tag `Kiến thức • 5 phút đọc`, tiêu đề *"Hiểu protein trong bữa ăn hằng ngày"*.
     - **Thực phẩm (Cơ sở dữ liệu dinh dưỡng):** Card thực phẩm *"Ức gà"*, badge tick xanh chính thức, metadata `31g Protein / 100g • 165 kcal`, nút `+` nhanh để đưa vào nhật ký Nutrition.
     - **Công thức (Thực đơn):** Card *"Sữa chua, yến mạch & quả mọng"*, metadata `24g Protein • 340 kcal`, nút bookmark nhanh.
     - **Bài tập (Giáo án):** Card *"Tập tạ và tổng hợp protein"*, biểu tượng tạ, mô tả cửa sổ đồng hóa cơ bắp.
     - **Gợi ý từ Saman Journal:** Callout card chia sẻ mẹo nạp đạm tối ưu (1.6 - 2.2g/kg thể trọng).

---

### 3.2. Phân hệ 2: Saman Community (Mạng xã hội thể thao & lối sống lành mạnh)

#### Màn hình: `R03_Community_Feed`
* **Mục tiêu:** Tạo nguồn động lực hàng ngày thông qua bảng tin chia sẻ hình ảnh bữa ăn, kết quả bài tập và câu hỏi thảo luận từ cộng đồng.
* **Các thành phần UI & Hành vi:**
  1. **Community Top Bar:**
     - Nút Back (`←`) quay lại Journal.
     - Title `Saman Community` kèm trạng thái active indicator.
     - Icon tin nhắn trực tiếp (Direct Message) cho giai đoạn phát triển tương lai.
  2. **Feed Filter Tabs:**
     - 3 tab chọn nguồn cấp: *Dành cho bạn* (Active), *Đang theo dõi*, *Hỏi đáp*.
  3. **Cấu trúc các định dạng bài đăng (Feed Post Archetypes):**
     - **Post 1 (Photo / Meal Log - Linh Nguyễn):**
       - Avatar + Tên + Tick xác nhận + Thời gian (`2 giờ trước`).
       - Nội dung chia sẻ hộp cơm trưa healthy, mẹo ướp ức gà áp chảo và phân bổ macros (`42g Protein`, `480 kcal`, `38g Carbs`, `11g Fat`).
       - Ảnh món ăn sắc nét, tỷ lệ 4:3.
       - Thanh action: Like (142), Comment (18), Share, Bookmark. Dòng engagement: *"Được thích bởi Minh Khang và 141 người khác"*.
     - **Post 2 (Shared Workout Attachment - Minh Khang):**
       - Caption: *"Hoàn thành buổi tập hôm nay. Tăng mức tạ bài bench press thêm 2.5kg..."*.
       - **Saman Kinetic Workout Card:** Badge `BUỔI TẬP ĐÃ HOÀN THÀNH`, tựa đề *“Upper Body Hypertrophy”*, thông số buổi tập `45 phút • 5 bài tập • 12 hiệp tập`, 3 ảnh thumbnail động tác (DB Bench Press, Pull-up, Shoulder Press), nút CTA *"Xem buổi tập →"*.
     - **Post 3 (Community Discussion / Q&A - Thu Hà):**
       - Badge chủ đề `HỎI ĐÁP • MEAL PREP`.
       - Câu hỏi lớn nổi bật: *"Bạn thường chuẩn bị bữa ăn cho cả tuần như thế nào?"*.
       - Gợi ý câu trả lời từ 25 người dùng, nút CTA xanh emerald *"Tham gia thảo luận →"*.
  4. **Community Bottom Navigation:**
     - 5 tab cố định: `Bảng tin` (Active), `Khám phá`, `[+] Đăng bài` (Floating action pill), `Thông báo`, `Cá nhân`.

#### Màn hình: `R04_Community_Discover`
* **Mục tiêu:** Khám phá thành viên truyền cảm hứng, chủ đề thảo luận thịnh hành và thư viện ảnh cộng đồng.
* **Các thành phần UI & Hành vi:**
  1. **Explore Search Bar & Topic Chips:**
     - Tìm kiếm bài viết, chủ đề, thành viên.
     - Chips lọc: *Tất cả*, *Tập luyện*, *Bữa ăn*, *Công thức*, *Hỏi đáp*.
  2. **Khoảnh khắc tiêu biểu (3-Column Masonry/Grid):**
     - Lưới ảnh vuông 3 cột hiển thị ảnh tập gym, smoothie, meal prep hộp cơm, calisthenics.
     - Lượt thích đè lên ảnh (Overlay badges), biểu tượng album bài đăng nhiều ảnh.
  3. **Chủ đề đang được quan tâm (Trending Hashtags):**
     - List các hashtag thể thao thịnh hành: `#MealPrepCuoiTuan` (+28% bài viết), `#TangCoGiamMo` (+45% bài viết), `#HoiDapDinhDuong`.
  4. **Gợi ý theo dõi (Who to Follow):**
     - Card HLV Hoàng Long (HLV Thể lực & Sức bền), Thảo Mai (Nấu ăn lành mạnh) kèm nút CTA `+ Theo dõi`.

#### Màn hình: `R05_Community_Post_Detail`
* **Mục tiêu:** Không gian thảo luận chuyên sâu từng bài đăng, tối ưu hóa trải nghiệm đọc và tương tác bình luận nhiều cấp (Threaded comments).
* **Các thành phần UI & Hành vi:**
  1. **Header:**
     - Nút back về `R03_Community_Feed`.
     - Tựa đề `Detail Stack`, icon bookmark và profile cá nhân.
  2. **Toàn bộ nội dung bài viết gốc:**
     - Đầy đủ text, callout mẹo vặt, pill macros (`42g Protein`, `480 kcal`...), hình ảnh món ăn hộp cơm full size và lượt thích/chia sẻ.
  3. **Khu vực Bình luận & Thảo luận (Discussion Thread):**
     - Đếm tổng số bình luận (`18`).
     - Bộ lọc sắp xếp: `Mới nhất` / `Hàng đầu`.
     - Bình luận cấp 1 (Minh Khang): Hỏi về nhiệt độ và thời gian nướng khoai lang.
     - Bình luận phản hồi tác giả (Linh Nguyễn - Badge `Tác giả` xanh ngọc): Trả lời chi tiết 180 độ 15 phút.
     - Bình luận cấp 1 (Thu Hà).
     - Nút mở rộng: *"Xem thêm 15 phản hồi khác..."*.
  4. **Thanh nhập bình luận ghim chân trang (Pinned Composer):**
     - Tự động đệm an toàn iOS/Android home indicator.
     - Avatar người dùng hiện tại + Input field *"Viết bình luận..."* + Emoji icon + Nút gửi (Send button) kích hoạt màu xanh Saman khi có ký tự.

---

## 4. HỆ THỐNG DESIGN SYSTEM & DESIGN TOKENS (OBSIDIAN KINETIC)

Hệ thống kế thừa chuẩn xác từ mã nguồn và hình ảnh của Saman Home:

| Token Category | Token Name / Key | Giá trị HEX / CSS | Mục đích sử dụng |
|---|---|---|---|
| **Background** | `surface-base` | `#0c0d0e` | Nền canvas toàn màn hình, thanh trạng thái, bottom nav |
| **Card Surface** | `surface-card` | `#16171b` (hoặc `#121314` container) | Bề mặt các card bài viết, card dinh dưỡng, feed post |
| **Card Hover** | `surface-card-hover` | `#1c1d22` | Trạng thái bấm/hover trên danh sách |
| **Elevated Surface** | `surface-elevated` | `#212329` | Bề mặt popover, modal, dropdown menu |
| **Subtle Border** | `border-subtle` | `#23252a` (hoặc `#272930`) | Viền mảnh ngăn cách giữa các section, viền card |
| **Primary Accent** | `brand-emerald` | `#10b981` (Emerald 500) | Điểm nhấn tab active, nút CTA quan trọng, tiến độ hoàn thành |
| **Accent Subtle** | `brand-emerald-subtle` | `rgba(16, 185, 129, 0.12)` | Nền chip active, badge trạng thái |
| **Warning/Carbs** | `macro-carbs` | `#f59e0b` (Amber 500) | Thanh macro carbs |
| **Secondary/Fat** | `macro-fat` | `#a855f7` (Purple 500) | Thanh macro fat |
| **Typography - Head** | `text-primary` | `#ffffff` / `#f3f4f6` | Tiêu đề H1, H2, tên người dùng, con số nổi bật |
| **Typography - Body** | `text-secondary` | `#94979e` / `#9ca3af` | Nội dung mô tả, phụ đề, metadata, timestamp |
| **Border Radius** | `rounded-2xl` | `16px` | Bo góc card chính, hero card, post containers |
| **Border Radius** | `rounded-xl` | `12px` | Bo góc thumbnail ảnh, action pill button |
| **Border Radius** | `rounded-lg` | `8px` | Bo góc tag, micro badges, input box |
| **Touch Target** | `min-touch-target` | `44px` – `48px` | Vùng chạm tối thiểu trên màn hình cảm ứng |

---

## 5. LỘ TRÌNH KỸ THUẬT & GIAI ĐOÀN TRIỂN KHAI (ROADMAP)

### Giai đoạn 1: Mở rộng Saman Journal (Sprint 1 - 2)
- Triển khai UI/UX `R01_Journal_Discover` và `R02_Journal_Search`.
- Tích hợp CMS quản lý bài viết cẩm nang và liên kết thư viện động tác có sẵn từ module Workout.
- Thử nghiệm tìm kiếm kết hợp Elasticsearch cho thư viện thực phẩm & công thức dinh dưỡng.

### Giai đoạn 2: Khởi động Saman Community MVP (Sprint 3 - 4)
- Triển khai `R03_Community_Feed`, `R04_Community_Discover`, `R05_Community_Post_Detail`.
- Xây dựng API chia sẻ tóm tắt buổi tập (**Workout Attachment Card**) từ module Workout sang Community.
- Xây dựng luồng tạo bài viết cơ bản (Đăng ảnh món ăn, hỏi đáp text).

### Giai đoạn 3: Tối ưu tương tác & Thông báo (Sprint 5)
- Hệ thống thông báo đẩy (Push notifications) khi có ai đó trả lời bình luận hoặc thích bài viết.
- Tab Tin nhắn trực tiếp (Direct Message) và hồ sơ cá nhân nâng cao (Community Member Profile).

---

## 6. TIÊU CHÍ NGHIỆM THU (ACCEPTANCE CRITERIA)
1. **Fidelity:** Các màn hình hiển thị chính xác theo mockup mobile tỉ lệ 390px, không bị co kéo hay tràn viền trên các thiết bị iPhone/Android hiện đại.
2. **Language:** 100% giao diện, nhãn, nút bấm và nội dung mẫu sử dụng tiếng Việt tự nhiên, chuẩn mực thể thao và dinh dưỡng.
3. **No Dead Clicks:** Mọi nút Back, Tab, Input và CTA card đều có định tuyến rõ ràng, không xuất hiện các nút chức năng mồ côi hay thông tin debug/QA trên giao diện người dùng.
4. **Visual Cohesion:** Sự chuyển tiếp giữa Home → Journal → Community mượt mà, đồng nhất về tông màu tối, font chữ và phong cách tối giản.
