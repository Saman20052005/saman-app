# QUY CHUẨN BẢO VỆ DỮ LIỆU SỨC KHỎE, BẢN NHÁP & PHỤC HỒI SỰ CỐ
## HEALTH DATA QUARANTINE, DRAFT LIFECYCLE & FAILURE RECOVERY SPECIFICATION

Tài liệu này xác lập các nguyên tắc kiến trúc mang tính sống còn về đạo đức dữ liệu thể chất, an toàn quyền riêng tư y tế, cơ chế lưu trữ bản nháp cục bộ và các giải pháp phục hồi lỗi mạng khi đăng bài.

---

## 1. NGUYÊN TẮC CÔ LẬP DỮ LIỆU SỨC KHỎE (HEALTH DATA QUARANTINE)

> [!CAUTION]
> **Ranh giới bất khả xâm phạm giữa Công cụ Cá nhân (Utility) và Mạng xã hội (Community):**
> Ứng dụng Saman lưu trữ nhiều dữ liệu thể hình và thói quen nhạy cảm (Cân nặng, Tỷ lệ mỡ, Số đo vòng eo, Lịch sử nâng tạ, Nhật ký bữa ăn chi tiết, Nhịp tim, Bệnh sử chấn thương). 
> Tuyệt đối không để tính năng Community làm rò rỉ các thông tin này ra công chúng!

### 1.1. Cam kết Chủ động Công khai (Explicit User Opt-in)
1. **Không tự động đăng bài:** Việc hoàn thành một bài tập trong phòng gym hoặc bấm lưu một bữa ăn trong tab Nutrition tuyệt đối **không được tự động kích hoạt đăng bài** lên Community.
2. **Cơ chế Snapshot thay vì Tham chiếu sống (Immutable Snapshot Architecture):**
   - Khi người dùng chọn một buổi tập hoặc bữa ăn tại màn hình R07 để đính kèm vào bài viết, ứng dụng phải trích xuất một **Snapshot bất biến** (`SharedWorkoutAttachmentSnapshot` hoặc `SharedMealAttachmentSnapshot`) và đóng gói trực tiếp vào nội dung bài đăng.
   - **Lý do kỹ thuật bắt buộc:**
     - Endpoint `/workout/sessions/{session_id}` và `/nutrition/logs/{date}` trong backend được bảo vệ nghiêm ngặt theo `user_id` của chủ sở hữu. Nếu người dùng khác bấm vào xem bài đăng, client của họ không có quyền gọi vào endpoint riêng tư của tác giả (sẽ bị lỗi 403/404).
     - Nếu tác giả sau này chỉnh sửa hoặc xóa buổi tập/bữa ăn trong nhật ký cá nhân, bài đăng trên Community không được phép bị lỗi hiển thị hay mất dữ liệu.
3. **Không ghi ngược vào nhật ký (Zero Side-Effects):**
   - Thao tác đính kèm, soạn bài, đăng bài, xóa bài hoặc hủy bản nháp trong Community **tuyệt đối không được ghi đè, chỉnh sửa hoặc xóa bỏ** bất kỳ dữ liệu nào trong cơ sở dữ liệu Workout hay Nutrition của người dùng.

### 1.2. Chính sách Mặc định An toàn tại Bộ chọn R07 (Privacy Switches)
Khi người dùng mở bộ chọn hoạt động đính kèm `R07_Community_Select_Attachment_Refined`:
- **Buổi tập (Workout):**
  - Tên buổi tập (`planName`) và Thời lượng (`totalDurationMinutes`): Hiển thị dạng text tĩnh, **Bắt buộc**.
  - Danh sách bài tập (`exerciseNames`): Switch bật/tắt (Mặc định: **Bật**).
  - Khối lượng tạ (`weights`) và Số hiệp (`reps/sets`): Switch bật/tắt (Mặc định: **TẮT**). Chỉ hiển thị khi tác giả chủ động gạt switch cho phép chia sẻ mức tạ.
- **Bữa ăn (Meal):**
  - Tên món ăn (`foodName`) và Loại bữa (`mealType`): Bắt buộc.
  - Danh sách thực phẩm thành phần: Switch bật/tắt (Mặc định: **Bật**).
  - Chỉ số Calo & Đa lượng (Protein, Carbs, Fat): Switch bật/tắt (Mặc định: **TẮT**).
- **Dữ liệu tuyệt đối cấm chia sẻ lên Community:**
  - Cân nặng hiện tại, chiều cao, BMI, BMR, TDEE.
  - Số đo cơ thể (vòng ngực, vòng eo, vòng đùi).
  - Hình ảnh tiến độ thể hình riêng tư (Body progress photos).
  - Ghi chú y tế hoặc tiền sử chấn thương.

---

## 2. VÒNG ĐỜI BẢN NHÁP (DRAFT LIFECYCLE & STORAGE SPECIFICATION)

### 2.1. Phân loại Bản nháp
Hệ thống quản lý 2 loại bản nháp chính:
1. **Bản nháp bài viết (Post Draft):** Chứa caption, danh sách ảnh/media cục bộ, chỉnh sửa crop/sáng tối, thứ tự album, snapshot đính kèm workout/meal, thiết lập đối tượng xem (audience), chủ đề (topic), cài đặt bình luận.
2. **Bản nháp câu hỏi (Question Draft):** Chứa tiêu đề câu hỏi, mô tả chi tiết, chủ đề bắt buộc, ảnh đính kèm.

### 2.2. Cơ chế Lưu trữ & Phục hồi Bản nháp
- **Lưu trữ cục bộ an toàn:** Bản nháp được lưu tại local client (sử dụng SharedPreferences hoặc Hive) và **bắt buộc phải gắn liền với ID tài khoản hiện tại**:
  ```
  key = "community_draft_${currentUserId}_${draftId}"
  ```
- **Hành vi khi ứng dụng tắt đột ngột (App Kill / Crash Recovery):**
  - Khi mở lại ứng dụng, bản nháp vẫn được bảo toàn nguyên vẹn.
  - Khi vào màn hình `R13_Community_Drafts`, danh sách hiển thị đầy đủ các bản nháp chưa hoàn thành. Chạm vào bản nháp bài viết sẽ mở thẳng `R06D` với đầy đủ caption và ảnh; chạm vào bản nháp câu hỏi sẽ mở `R08`.
- **Hành vi khi file ảnh gốc trong máy bị xóa:**
  - Nếu ảnh local không còn tồn tại hoặc hết quyền truy cập, ô ảnh hiển thị nhãn cảnh báo: *"Ảnh không còn khả dụng trên máy. Vui lòng chọn lại ảnh"*. Hệ thống giữ nguyên 100% caption và các thiết lập khác, không xóa sạch bản nháp của người dùng.

### 2.3. Cách ly Bản nháp khi Đăng xuất & Đổi tài khoản (Account Switch Quarantine)
- Khi người dùng đăng xuất (`AuthHelper.logout()`):
  - Cache và provider của bản nháp bị xóa khỏi bộ nhớ RAM (`container.invalidate(communityDraftsProvider)`).
  - Bản nháp lưu trên máy được mã hóa hoặc đặt tiền tố theo `userId`. Khi tài khoản B đăng nhập vào cùng thiết bị, tài khoản B **tuyệt đối không nhìn thấy** bản nháp của tài khoản A.
  - Khi tài khoản A đăng nhập lại, bản nháp của tài khoản A được phục hồi chính xác.

---

## 3. PHỤC HỒI LỖI MẠNG, IDEMPOTENCY & CHỐNG ĐĂNG BÀI TRÙNG

### 3.1. Nguy cơ Đăng bài Trùng lặp (Duplicate Submission Risk)
Khi người dùng bấm nút "Chia sẻ" tại R06D hoặc "Đăng câu hỏi" tại R08 trong điều kiện sóng yếu (3G/4G chập chờn hoặc phòng gym tầng hầm):
1. Người dùng có thể sốt ruột bấm nút liên tiếp nhiều lần (Double Tap).
2. Request gửi lên server bị timeout phía client, nhưng thực tế server backend đã nhận được và tạo bài xong trong database. Nếu client tự động thử lại mà không có định danh duy nhất, server sẽ tạo ra bài viết thứ hai giống hệt.

### 3.2. Cơ chế Idempotency Key Bắt buộc
Để giải quyết triệt để vấn đề này, mọi request tạo bài viết (`POST /community/posts`) hoặc tạo câu hỏi (`POST /community/questions`) bắt buộc phải đính kèm một `Idempotency-Key` (UUIDv4) do client sinh ra ngay khi bắt đầu phiên soạn thảo:
```http
POST /community/posts HTTP/1.1
Authorization: Bearer <token>
Idempotency-Key: 9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d
Content-Type: application/json

{
  "caption": "Buổi tập ngực hôm nay rất đã...",
  "media_urls": [...],
  "attachment": {...}
}
```
- **Xử lý phía Server:**
  - Server lưu `Idempotency-Key` trong cache (Redis hoặc MongoDB index với TTL 24 giờ).
  - Nếu nhận được cùng một key từ cùng một `user_id`, server không tạo bản ghi mới mà trả về ngay kết quả của bài viết đã tạo trước đó.
- **Xử lý phía Client:**
  - Khi người dùng bấm "Chia sẻ": vô hiệu hóa (disable) ngay lập tức nút bấm và hiển thị spinner.
  - Nếu request bị timeout: client giữ nguyên bản nháp trong màn hình soạn thảo, hiển thị thông báo lỗi mạng kèm nút *"Thử gửi lại"* (sử dụng lại đúng `Idempotency-Key` cũ).

---

## 4. KIỂM SOÁT PHÂN QUYỀN ĐỐI TƯỢNG XEM (AUDIENCE ENFORCEMENT)

Tại R06D, người dùng có thể chọn đối tượng xem:
1. `Công khai` (Public): Hiển thị cho toàn bộ cộng đồng trên feed Dành cho bạn và Discover.
2. `Người theo dõi` (Followers Only): Chỉ những thành viên đang theo dõi tác giả mới nhìn thấy bài viết.

> [!IMPORTANT]
> **Quy tắc Kiểm soát Phân quyền tại Server:**
> - Quyền xem không được quản lý đơn thuần bằng cách ẩn/hiện widget trên màn hình Flutter.
> - Server backend khi truy vấn Feed (`GET /community/feed`) bắt buộc phải lọc dữ liệu theo mối quan hệ theo dõi giữa `viewer_id` và `author_id`.
> - Nếu một người dùng chưa theo dõi tác giả cố tình gọi trực tiếp `GET /community/posts/{post_id}` của một bài viết Followers-only, server phải trả về mã lỗi `403 Forbidden` hoặc `404 Not Found`.
