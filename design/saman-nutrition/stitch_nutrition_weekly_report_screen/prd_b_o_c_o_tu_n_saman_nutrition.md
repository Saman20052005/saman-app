# PRODUCT REQUIREMENTS DOCUMENT (PRD)
## Tính năng: Báo cáo dinh dưỡng theo tuần (Weekly Nutrition Report)
### Ứng dụng: Saman Fitness & Nutrition

---

### 1. Tổng quan dự án (Executive Summary)
- **Tên tính năng:** Báo cáo tuần - Saman Nutrition (Weekly Nutrition Report).
- **Mục tiêu sản phẩm:** Cung cấp cho hội viên góc nhìn tổng thể, khách quan và khoa học về lượng calo cùng các chất đa lượng (protein, carb, fat) đã nạp trong chu kỳ tuần, giúp họ theo dõi sát sao lộ trình dinh dưỡng mà không tạo áp lực hay đánh giá tiêu cực khi dữ liệu còn thưa thớt (sparse data).
- **Đối tượng người dùng:** Người tập luyện thể thao, vận động viên, người theo dõi cân nặng và vóc dáng đang sử dụng ứng dụng Saman.
- **Nguyên lý thiết kế cốt lõi:** *"Calm Athleticism"* — Trầm tĩnh, kiềm chế, đề cao tính chính xác và sự minh bạch của dữ liệu, giảm thiểu visual noise (nhiễu thị giác).

---

### 2. Bối cảnh & Vấn đề giải quyết (Problem Statement)
- **Vấn đề của các ứng dụng thông thường:** Thường áp đặt đánh giá cảm tính (điểm số, vạch cảnh báo đỏ, lời khen thái quá) hoặc phóng đại dữ liệu khi người dùng mới chỉ log 1-2 ngày trong tuần.
- **Giải pháp của Saman:** 
  1. Thể hiện trung thực tỷ lệ nạp calo và macro so với mục tiêu thực tế.
  2. Phân biệt rõ ràng giữa "chưa ghi dữ liệu" (unlogged days) và "0 kcal" (fasting / ăn 0 kcal).
  3. Duy trì tâm lý ổn định, tích cực và khách quan với thông điệp trung tính khi dữ liệu chưa đủ 7/7 ngày.

---

### 3. Thông số kỹ thuật & Thiết kế giao diện (UI / UX Specifications)

#### 3.1. Thiết kế nền tảng & Bảng màu (Design System)
- **Thiết bị mục tiêu:** Mobile Native (Viewport chuẩn 390px, hỗ trợ cuộn dọc liền mạch).
- **Typography:** Inter (San-serif).
  - Page Title: 26px / Semibold.
  - Section Title: 16px / Semibold.
  - Primary Metric: 24–28px với `tabular-nums` căn lề chuẩn xác.
  - Body copy: 14px / Regular.
  - Microcopy & Labels: 12–13px / Medium.
- **Color Palette (Calm Dark Palette):**
  - `Background`: `#0F0F0F`
  - `Surface Cards`: `#191B1D`
  - `Inner Containers / Active Elements`: `#24272B`
  - `Subtle Borders / Dividers`: `#272A30`
  - `Primary Text`: `#F4F4F5`
  - `Secondary / Muted Text`: `#9CA3AF`
  - `Brand Accent (Emerald)`: `#10B981` (Tập trung điểm nhấn thị giác)
  - `Protein Accent`: `#4D96FF` (Muted Blue dot marker)
  - `Carbs Accent`: `#FFD93D` (Muted Amber dot marker)
  - `Fat Accent`: `#A78BFA` (Muted Lavender dot marker)

---

### 4. Chi tiết cấu trúc các Module màn hình (Information Architecture)

#### Module 1: Header & Điều hướng (App Bar & Week Selector)
- **Top Bar:** 
  - Nút Back tinh giản (touch target ≥ 44x44px).
  - Tiêu đề: *Báo cáo tuần*.
  - Phụ đề: *Nhìn lại dinh dưỡng của bạn*.
  - Không hiển thị Bottom Navigation (màn hình chế độ xem chi tiết).
- **Week Selector Card:**
  - Điều hướng tiến/lùi chu kỳ tuần bằng chevron icon.
  - Khoảng thời gian: `26 thg 10 – 1 thg 11, 2026`.
  - Huy hiệu trạng thái (Status badge): `1/7 ngày đã ghi`.

#### Module 2: Biểu đồ năng lượng theo ngày (Daily Calorie Chart)
- **Tiêu đề khối:** *Năng lượng theo ngày* — Phụ đề: *Lượng đã ghi so với mục tiêu*.
- **Trục & Cột hiển thị:**
  - 7 cột tương ứng Thứ Hai đến Chủ Nhật (`T2, T3, T4, T5, T6, T7, CN`).
  - Baseline & đường mục tiêu đứt nét (`Mục tiêu · 3.129 kcal`) màu xám dịu `#52525B`.
  - Hiển thị cột màu Emerald `#10B981` cho ngày có dữ liệu (Ví dụ T3: 125 kcal) theo đúng tỷ lệ thật, không kéo giãn phóng đại.
  - Ngày chưa ghi nhật ký hiển thị ký hiệu gạch ngang trung tính trên baseline, tách biệt hoàn toàn với số 0.
- **Selected Day Footer:**
  - Tích hợp liền khối dưới biểu đồ bằng đường kẻ mỏng: `Thứ Ba, 27/10 — 125 kcal` kèm chỉ số macro `Đạm 17 g · Carb 4 g · Béo 4 g`.

#### Module 3: Khối đa lượng tuần (Macro trong tuần)
- **Tiêu đề khối:** *Macro trong tuần*.
- **Danh sách 3 chất dinh dưỡng:**
  - **Đạm (Protein):** Chấm xanh dương · Đã nạp `17 g` / Mục tiêu `952 g`.
  - **Tinh bột (Carb):** Chấm vàng hổ phách · Đã nạp `4 g` / Mục tiêu `3.157 g`.
  - **Chất béo (Fat):** Chấm tím lavender · Đã nạp `4 g` / Mục tiêu `609 g`.
- **Thanh tiến độ (Progress Track):** Thanh siêu mỏng 4px bo tròn, thể hiện tiến độ thực tế, không dùng dữ liệu giả để trang trí.

#### Module 4: Tóm tắt & Thông báo khách quan (Summary Metrics)
- **Hai chỉ số cốt lõi:**
  - `Trung bình / ngày`: **18 kcal** (Tính trung bình trên 7 ngày của tuần).
  - `So với mục tiêu`: **−3.111 kcal** (Hiển thị bằng màu text trung tính, không tô màu xanh chúc mừng để tránh cổ súy nhịn ăn cực đoan).
- **Thông báo khách quan (Data Notice):**
  - *"Bạn mới ghi 1/7 ngày. Báo cáo chưa phản ánh đầy đủ lượng ăn thực tế."*

#### Module 5: Chi tiết từng ngày (Daily Breakdown List)
- **Tiêu đề khối:** *Chi tiết từng ngày*.
- **Cấu trúc hàng danh sách (7 hàng tuần tự):**
  - Cột trái: Thứ & ngày tháng (`T2 · 26/10`, `T3 · 27/10`,...).
  - Cột giữa: Macro chi tiết hoặc thông báo *"Chưa có dữ liệu"*.
  - Cột phải: Lượng calo nạp (`125 kcal`) hoặc dấu gạch ngang (`—`).
  - Hàng ngày Thứ Ba được làm nổi bật với dải nền xanh Emerald dịu (`bg-[#10B981]/10`).

---

### 5. Yêu cầu phi chức năng & Quy tắc nghiệp vụ (Non-Functional Requirements)
1. **Bảo toàn dữ liệu thực tế (Data Integrity):** Không được tự ý nội suy (interpolate) số liệu ngày trống; phân biệt rõ trạng thái *null/unlogged* và *zero*.
2. **Khả năng tiếp cận (Accessibility):** Độ tương phản văn bản đạt chuẩn WCAG AA trên nền tối `#0F0F0F`.
3. **Bản địa hóa (Localization):** Toàn bộ giao diện sử dụng tiếng Việt tự nhiên, chuẩn mực thể thao và khoa học dinh dưỡng.
4. **Hiệu năng giao diện:** Tối ưu hóa render DOM, không dùng thư viện biểu đồ quá nặng; ưu tiên layout Flex/Grid và SVG thuần cho biểu đồ.

---

### 6. Roadmap & Hướng phát triển tiếp theo (Next Steps)
- [ ] Tích hợp tính năng chạm chọn ngày trên biểu đồ để xem chi tiết bữa ăn (Meal breakdown: Bữa sáng, trưa, tối, phụ).
- [ ] Bổ sung trạng thái so sánh tuần này với tuần trước (Week-over-week trends) khi có đủ dữ liệu ≥ 5 ngày.
- [ ] Chế độ xem vi chất (Micronutrients: Chất xơ, Natri, Nước, Đường).
