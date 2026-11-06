# KẾ HOẠCH BÀN GIAO & ĐỀ XUẤT CHO CHECKPOINT JCOM-02
## TRANSITION FROM SAMAN JOURNAL TO CORE COMMUNITY EXPERIENCE (R03, R04, R05)

- **Mã checkpoint hoàn thành:** JCOM-01
- **Mã checkpoint kế tiếp:** JCOM-02 (Đề xuất)
- **Thời gian lập:** 01/11/2026
- **Trạng thái:** READY FOR HUMAN REVIEW

---

## 1. KẾ THỪA NỀN TẢNG TỪ CHECKPOINT JCOM-01

Checkpoint JCOM-01 đã hoàn thành xuất sắc toàn bộ nền tảng điều hướng và tri thức của Saman Journal, tạo tiền đề vững chắc cho việc mở rộng sang Saman Community:

1. **Điểm nối điều hướng sẵn sàng (Doorway Bridge):**
   - Thẻ `JournalCommunityDoorwayCard` đã được bố trí ở chân trang Khám phá R01.
   - Khi bước vào JCOM-02, sự kiện `onTap` của thẻ này chỉ cần chuyển từ việc hiển thị preview sheet sang gọi `Navigator.of(context).pushNamed(AppRoutes.community)`.
2. **Hệ thống Design Tokens & Theme Obsidian Kinetic:**
   - Hệ thống màu Canvas `#0C0D0E`, Card `#16171B`, Emerald `#10B981` / `#08664F`, Border Hairline `#23252A` đã được chuẩn hóa và kiểm chứng không gây overflow.
3. **Cơ chế Fake Repository & DI:**
   - Kiến trúc Riverpod DI đã được chứng minh hiệu quả cao trong việc cô lập mock data khỏi Presentation layer, dễ dàng tái sử dụng pattern này cho `CommunityRepository` và `CommunityFakeDatasource`.

---

## 2. MỤC TIÊU VÀ PHẠM VI ĐỀ XUẤT CHO CHECKPOINT JCOM-02

### 2.1. Mục tiêu cốt lõi
Xây dựng trải nghiệm cốt lõi của mạng xã hội mini Saman Community:
- **R03 — Community Feed (Bảng tin):** 3 tabs (*Dành cho bạn*, *Đang theo dõi*, *Hỏi đáp*), 3 định dạng bài đăng (Bữa ăn, Thẻ buổi tập Kinetic, Câu hỏi thảo luận), thanh Community Bottom Navigation.
- **R04 — Community Discover (Khám phá):** Thanh tìm kiếm UGC, lưới ảnh 3 cột (Photo Grid), trending hashtags, danh sách gợi ý theo dõi (*Who to follow*).
- **R05 — Community Post Detail (Chi tiết bài viết & Thảo luận):** Mở bài viết từ postId, hiển thị nội dung/ảnh đầy đủ, danh sách bình luận lồng nhau, badge Tác giả xanh ngọc, pinned composer ở đáy.

### 2.2. Điểm tích hợp dự kiến
- Bổ sung routes vào `frontend/lib/config/routes.dart`:
  - `AppRoutes.community` (`/community`)
  - `AppRoutes.communityDiscover` (`/community/discover`)
  - `AppRoutes.communityPostDetail` (`/community/post/:id`)
- Nối thẻ `JournalCommunityDoorwayCard` sang `/community`.
- Nút Back (`←`) trên header R03 đưa người dùng trở lại R01 tại vị trí thẻ Doorway.

### 2.3. Dữ liệu (Data Mode)
- Sử dụng `CommunityFakeDatasource` và `CommunityRepositoryImpl` qua Riverpod DI.
- Hỗ trợ optimistic like và save, rollback khi lỗi.
- Chưa kết nối backend live (dành cho JCOM-05).

### 2.4. Ranh giới ngoài phạm vi (Out of Scope for JCOM-02)
- Chưa build luồng composer tạo bài đa bước R06A–R06D (dành cho JCOM-03).
- Chưa build attachment picker R07 (dành cho JCOM-03).
- Chưa build màn hồ sơ R09–R14 (dành cho JCOM-04).
- Chưa tạo database backend hoặc live APIs (dành cho JCOM-05).

---

## 3. KHUYẾN NGHỊ KỸ THUẬT CHO KỸ SƯ THỰC HIỆN JCOM-02

1. **Ngăn cách Navigation Shell:**
   - Khi vào Community, thanh điều hướng chính của Saman phải được ẩn đi bởi route stack mới. Tuyệt đối không hiển thị đồng thời 2 thanh điều hướng dưới đáy.
2. **Pinned Composer Safe Area:**
   - Tại màn R05 Post Detail, ô nhập bình luận ở đáy cần lắng nghe `MediaQuery.viewInsetsOf(context).bottom` để nổi tự nhiên lên trên bàn phím mà không bị che khuất.
3. **Bảo mật dữ liệu sức khỏe (Health Data Isolation):**
   - Thẻ buổi tập hoặc bữa ăn chia sẻ trên Feed phải là immutable snapshot thuộc post, không được gọi trực tiếp endpoint session cá nhân của tác giả.
