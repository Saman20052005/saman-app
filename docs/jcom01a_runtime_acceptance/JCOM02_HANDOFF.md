# TÀI LIỆU BÀN GIAO KỸ THUẬT SANG CHECKPOINT JCOM-02 (JCOM-02 HANDOFF)

**Dự án:** Saman App — Module Journal & Community  
**Thời điểm bàn giao:** 01/11/2026  
**Trạng thái đầu vào từ JCOM-01 & JCOM-01A:** **Sẵn sàng (Ready for JCOM-02 on Human Approval)**

---

## 1. CÁC ĐIỂM KẾT NỐI ĐÃ HOÀN THIỆN TRONG JCOM-01/01A

1. **Card Community Doorway (`JournalCommunityDoorwayCard`):**
   - Đang nằm ở cuối trang R01 Journal Discover.
   - Hiện tại mở `JournalPreviewSheet` thông báo tính năng Community đang phát triển.
   - **Điểm tích hợp JCOM-02:** Thay thế callback `onTap` bằng `Navigator.pushNamed(context, AppRoutes.communityFeed)` khi R03 sẵn sàng.

2. **Kiến trúc dữ liệu & Phân loại nội dung:**
   - Hợp đồng `JournalRepository` và Fake Datasource đã phân loại nghiêm ngặt:
     - `JournalSearchCategory.articles`
     - `JournalSearchCategory.exercises`
     - `JournalSearchCategory.foods`
     - `JournalSearchCategory.recipes`
   - Bộ lọc tìm kiếm R02 đã được kiểm chứng độc lập, không lẫn bài viết xã hội của người dùng.

3. **Riverpod Dependency Injection:**
   - `journalRepositoryProvider` hỗ trợ ghi đè linh hoạt qua `overrideWithValue`.
   - Các controller `journalDiscoverNotifierProvider` và `journalSearchNotifierProvider` đã có cơ chế debounce 300ms và bộ đếm query ID chống race condition.

4. **Tránh xung đột Bottom Navigation:**
   - R01 và R02 là các màn hình con độc lập, không dựng bottom navigation bar Community riêng.

---

## 2. PHẠM VI DỰ KIẾN CỦA CHECKPOINT JCOM-02

Khi người dùng cấp quyền thực hiện JCOM-02, các màn hình và tính năng cần triển khai bao gồm:
1. **R03 — Community Feed (Bảng tin cộng đồng):**
   - Danh sách bài chia sẻ hành trình luyện tập, dinh dưỡng của các thành viên.
   - Thẻ bài viết (Ảnh trước/sau, bài tập đã hoàn thành, nhật ký ăn uống public).
2. **R04 — Community Discover (Khám phá cộng đồng):**
   - Tìm kiếm người dùng, nhóm thử thách, chủ đề thịnh hành.
3. **R05 — Post Detail (Chi tiết bài viết cộng đồng):**
   - Xem chi tiết hình ảnh, số rep/set, bình luận, tương tác cổ vũ.

---

## 3. CÁC QUY TẮC AN TOÀN BẮT BUỘC TIẾP TỤC DUY TRÌ CHO JCOM-02

- **Bảo mật dữ liệu cá nhân:** Không tự động publish bài tập hoặc bữa ăn riêng tư khi người dùng chưa bấm xác nhận đăng bài công khai.
- **Không tự ý sửa Backend/Database:** Tiếp tục sử dụng Fake Repository và in-memory datasource cho đến khi có API contract chính thức.
- **Không xâm lấn các module khác:** Giữ nguyên các feature `workout`, `nutrition`, `membership`, `shop`, `profile`.
