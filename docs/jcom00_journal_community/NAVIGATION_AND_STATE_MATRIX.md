# MA TRẬN ĐIỀU HƯỚNG, BACK BEHAVIOR & TRẠNG THÁI HỆ THỐNG
## SAMAN JOURNAL & COMMUNITY NAVIGATION & STATE SPECIFICATION

Tài liệu này xác định chi tiết sơ đồ điều hướng, nguyên tắc xử lý ngăn xếp (Route Stack), hành vi quay lui (Back Behavior), và ma trận quản lý trạng thái tải/lỗi cho toàn bộ 18 màn hình.

---

## 1. SƠ ĐỒ ĐIỀU HƯỚNG TỔNG THỂ (NAVIGATION FLOW)

```
[SAMAN HOME (Main App Shell)]
       │
       ├──> Chạm Card "Saman Journal" trong Saman Picks Carousel
       │             │
       │             ▼
       │    ┌─────────────────────────────────────────────────────────────┐
       │    │               SAMAN JOURNAL (Full Screen Stack)             │
       │    │  Header: [← Quay lại Home] [Saman Journal] [Bookmark]       │
       │    │  Tabs: [Khám phá] | [Thư viện] | [Cẩm nang]                 │
       │    │                                                             │
       │    │  - Hero Editorial Card                                      │
       │    │  - Topic Chips (Tập luyện, Dinh dưỡng, Phục hồi, Thói quen) │
       │    │  - Tiếp tục đọc (Resume Reading)                            │
       │    │  - Thư viện kiến thức (Bài tập / Thực phẩm)                 │
       │    │  - Doorway Card: "Saman Community — Chia sẻ hành trình" ────┼─────┐
       │    └─────────────────────────────┬───────────────────────────────┘     │
       │                                  ▼                                     │
       │                         [R02_Journal_Search]                           │
       │                         - Header: [← Quay lại R01] [Input] [Filter]    │
       │                         - Tìm: Bài viết, bài tập, thực phẩm            │
       │                                                                        │
       └────────────────────────────────────────────────────────────────────────┘
                                                                                │
                                                                                ▼
       ┌──────────────────────────────────────────────────────────────────────────────┐
       │                     SAMAN COMMUNITY (Mini Social Shell)                      │
       │  Header: [← Quay lại Journal] [Saman Community]                              │
       │  Feed Filters: [Dành cho bạn] | [Đang theo dõi] | [Hỏi đáp]                  │
       │                                                                              │
       │  Bảng tin Feed (R03):                                                        │
       │  ├── Bài post ảnh/bữa ăn ─────────────────────────> [R05_Community_Post_     │
       │  ├── Thẻ buổi tập chia sẻ ────────────────────────>  Detail] (Header Back)  │
       │  └── Bài câu hỏi thảo luận ───────────────────────> [R15_Community_Question_ │
       │                                                       Detail] (Header Back)  │
       │  Thanh Community Bottom Navigation (5 tabs):                                 │
       │  [Bảng tin (R03)] [Khám phá (R04)] [(+) Tạo bài] [Thông báo (R11)] [Cá nhân  │
       │                                                                      (R09)]  │
       └───────────────────────────────┬──────────────────────┬───────────────┬───────┘
                                       │                      │               │
                ┌──────────────────────┴────────┐             │               ▼
                ▼                               ▼             │      [R09_Community_Profile]
        [R04_Community_Discover]     [Bottom Sheet: Tạo bài]  │      - Stats, Posts, Q&A
        - Tìm UGC, bài viết          ├── "Bài viết" ───────┐  │      - Nút [Chỉnh sửa hồ sơ]
        - Grid ảnh 3 cột             ├── "Chia sẻ bài tập" ─┐ │      │    └──> [R14_Edit_Profile]
        - Hashtags thịnh hành        ├── "Chia sẻ bữa ăn" ──┐ │      - Menu cá nhân:
        - Gợi ý theo dõi             └── "Đặt câu hỏi" ──┐│ │ │           ├──> [R12_Community_Saved]
                                                         ││ │ │           └──> [R13_Community_Drafts]
                                                         ││ │ │
   ┌─────────────────────────────────────────────────────┘│ │ │
   │                                                      │ │ │
   ▼ [R08_Community_Ask_Question]                         │ │ │
   - Tiêu đề câu hỏi / Mô tả bối cảnh                     │ │ │
   - Chọn chủ đề (Dinh dưỡng / Tập luyện)                 │ │ │
   - Header: [✕ Đóng] [Đăng câu hỏi]                      │ │ │
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
   ├── R06A_Post_Select_Media (Chọn ảnh, Tiếp)        │       │
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
                                                   - Grouped: Hôm nay / Trước đó
                                                   - Click Post ➔ R05 | Question ➔ R15
```

---

## 2. BẢN ĐỒ ROUTE HIỆN HỮU VS ROUTE ĐỀ XUẤT

| Tên màn hình | Route hiện có | Route đề xuất (Chưa tồn tại) | Kiểu màn hình / Ngăn xếp | Thanh Bottom Navigation hiển thị |
|---|---|---|---|---|
| **Saman Home** | `/main` | `/main` (Tab 0) | Shell gốc | Thanh chính Saman |
| **R01 — Journal Discover** | *Chưa có* | `/journal` | Push toàn màn hình | **Ẩn toàn bộ** bottom nav |
| **R02 — Journal Search** | *Chưa có* | `/journal/search` | Push toàn màn hình | **Ẩn toàn bộ** bottom nav |
| **R03 — Community Feed** | *Chưa có* | `/community` | Shell con Community | **Thanh Community Nav** (Tab Bảng tin) |
| **R04 — Community Discover** | *Chưa có* | `/community/discover` | Tab trong Shell Community | **Thanh Community Nav** (Tab Khám phá) |
| **R05 — Post Detail** | *Chưa có* | `/community/post/:id` | Push toàn màn hình | **Ẩn toàn bộ** bottom nav (Ưu tiên composer đáy) |
| **R06A — Select Media** | *Chưa có* | `/community/compose/media` | Modal full screen | **Ẩn toàn bộ** bottom nav |
| **R06B — Edit Media** | *Chưa có* | `/community/compose/edit` | Push trong luồng tạo | **Ẩn toàn bộ** bottom nav |
| **R06C — Album Order** | *Chưa có* | `/community/compose/album` | Sub-modal reorder | **Ẩn toàn bộ** bottom nav |
| **R06D — Post Compose** | *Chưa có* | `/community/compose/publish`| Push trong luồng tạo | **Ẩn toàn bộ** bottom nav |
| **R07 — Attachment Picker** | *Chưa có* | `/community/attachment` | Modal / Push | **Ẩn toàn bộ** bottom nav |
| **R08 — Ask Question** | *Chưa có* | `/community/ask` | Modal full screen | **Ẩn toàn bộ** bottom nav |
| **R09 — Community Profile** | *Chưa có* | `/community/profile/:id` | Tab hoặc Push | Nếu là tab Cá nhân: Community Nav; Nếu mở từ bài: Ẩn nav |
| **R10 — Follow List** | *Chưa có* | `/community/user/:id/follows`| Push toàn màn hình | **Ẩn toàn bộ** bottom nav |
| **R11 — Notifications** | *Chưa có* | `/community/notifications` | Tab trong Shell Community | **Thanh Community Nav** (Tab Thông báo) |
| **R12 — Saved Posts** | *Chưa có* | `/community/saved` | Push từ Profile | **Ẩn toàn bộ** bottom nav |
| **R13 — Drafts** | *Chưa có* | `/community/drafts` | Push từ Profile | **Ẩn toàn bộ** bottom nav |
| **R14 — Edit Profile** | *Chưa có* | `/community/profile/edit` | Push từ Profile | **Ẩn toàn bộ** bottom nav |
| **R15 — Question Detail** | *Chưa có* | `/community/question/:id` | Push toàn màn hình | **Ẩn toàn bộ** bottom nav (Ưu tiên composer đáy) |

> [!IMPORTANT]
> **Quy tắc ngăn cách Navigation Shell:**
> Tuyệt đối không bao giờ hiển thị đồng thời thanh điều hướng chính của Saman và thanh điều hướng Community. Khi vào Journal hoặc Community, thanh nav của app chính được che đi bởi Route Stack mới.

---

## 3. QUY TẮC BACK BEHAVIOR & BẢO TOÀN TRẠNG THÁI (STATE RETENTION)

1. **Từ R02 về R01:**
   - Nhấn nút Back trên header hoặc Back hệ điều hành: quay về R01, **giữ nguyên vị trí cuộn trang (scroll position)** và tab đang chọn của R01.
2. **Từ R03 về R01:**
   - Nút Back (`←`) trên header Community Feed đưa người dùng quay lại trang R01 Journal tại vị trí thẻ Doorway Card.
3. **Từ R05 / R15 về Feed / Discover:**
   - Quay về đúng vị trí bài viết trong danh sách cuộn, giữ nguyên bộ lọc (ví dụ: đang ở filter "Hỏi đáp" thì quay lại vẫn ở "Hỏi đáp").
   - Nếu trong R05/R15 người dùng bấm Like hoặc Save, trạng thái hiển thị trên Feed ngoài phải được đồng bộ ngay tức thì.
4. **Quay lui trong luồng tạo bài (R06A → R06B → R06C → R06D):**
   - R06D Back về R06B: giữ nguyên caption đã nhập trong bộ nhớ đệm (Draft state).
   - R06B Back về R06A: giữ nguyên các ảnh đã chọn trước đó.
   - Khi nhấn nút Đóng (`✕`) tại R06A, R06D hoặc R08: kích hoạt Bottom Sheet hỏi người dùng: *"Lưu bản nháp"* / *"Bỏ thay đổi"* / *"Tiếp tục viết"*.
5. **Từ R07 về R06D / R08:**
   - Nhấn nút "Đính kèm": cập nhật snapshot vào bản nháp và quay lại đúng màn hình đã gọi.
   - Nhấn nút Back: không thay đổi đính kèm cũ, không làm mất văn bản hay ảnh trong composer.
6. **Từ R14 về R09:**
   - Nếu form chưa chỉnh sửa (not dirty): Back ngay lập tức.
   - Nếu form đã thay đổi (dirty): hiển thị dialog xác nhận *"Hủy các thay đổi?"*.

---

## 4. MA TRẬN TRẠNG THÁI DỮ LIỆU & XỬ LÝ LỖI (STATE & RISK MATRIX)

| Màn hình / Tính năng | Loading State | Populated State | Empty State | Error State & Retry | Optimistic Update & Rollback |
|---|---|---|---|---|---|
| **R01 Journal Discover** | Shimmer skeleton hero card và topic chips | Hiển thị bài viết, dải chip, tiến độ đọc dở | "Chưa có bài viết mới" | Báo lỗi tải tri thức + nút "Thử lại" | Không áp dụng |
| **R02 Journal Search** | Vòng xoay spinner nhỏ trong search bar | Danh sách kết quả phân theo nhóm bài viết, món ăn, bài tập | "Không tìm thấy kết quả phù hợp cho [query]" | Báo lỗi kết nối + giữ lại từ khóa tìm kiếm | Không áp dụng |
| **R03 Community Feed** | Skeleton các card bài viết 4:3 | Cuộn vô tận các bài viết, phân trang cursor mượt mà | "Chưa có bài viết nào trong chủ đề này" | Thông báo mất mạng + nút "Tải lại bảng tin" | Like / Save: đổi màu icon và tăng counter ngay; nếu API lỗi thì rollback và hiện toast |
| **R05 Post Detail & Comments** | Spinner trung tâm | Chi tiết bài viết + danh sách bình luận lồng nhau | "Chưa có bình luận nào. Hãy là người đầu tiên chia sẻ!" | Giữ nguyên nội dung bình luận đã gõ dở, hiện nút "Thử gửi lại" | Bình luận mới hiện tạm với trạng thái "Đang gửi"; nếu thất bại cho phép thử lại, không mất chữ |
| **R06D Post Submit** | Nút "Chia sẻ" chuyển sang spinner, disable toàn màn hình | Bài viết xuất hiện trên đầu feed, dọn sạch bản nháp | N/A (Không cho submit khi trống) | Báo lỗi đăng bài; giữ nguyên bản nháp trong composer để người dùng submit lại | Chống double submit bằng idempotency key; chỉ thông báo thành công khi server xác nhận |
| **R07 Attachment Picker** | Shimmer danh sách ngày gần đây | Danh sách buổi tập / bữa ăn kèm switch privacy | "Chưa có buổi tập nào hoàn thành trong tuần này" | Báo lỗi tải lịch sử + nút thử lại | Không áp dụng |
| **R09 Community Profile** | Skeleton avatar, stats và lưới bài viết | Profile hoàn chỉnh, số follower, bài viết và hỏi đáp | "Người dùng này chưa có bài viết nào" | Báo lỗi tải hồ sơ hoặc "Hồ sơ không tồn tại" | Follow / Unfollow: đổi trạng thái nút tức thì; nếu request lỗi thì đảo ngược lại |
| **R10 Follow List** | Shimmer danh sách hàng | Danh sách thành viên kèm avatar và nút quan hệ | "Chưa có người theo dõi nào" | Báo lỗi tải danh sách + nút thử lại | Follow toggle: cập nhật tức thì trên từng hàng |
| **R11 Notifications** | Shimmer nhóm Hôm nay / Trước đó | Danh sách thông báo, chấm unread ngọc `#8AD8BD` | "Bạn không có thông báo mới nào" | Báo lỗi kết nối | Đánh dấu đã đọc: xóa chấm unread ngay lập tức |
| **R12 Community Saved** | Skeleton grid 2 cột | Lưới bài viết, bài tập, câu hỏi đã bookmark | "Chưa có bài viết nào được lưu" | Báo lỗi tải danh sách | Bỏ lưu (Unsave): xóa tile khỏi grid kèm snackbar "Đã gỡ khỏi Đã lưu" có nút Hoàn tác |
| **R13 Community Drafts** | Skeleton danh sách hàng | Danh sách bản nháp dở kèm thumbnail | "Chưa có bản nháp nào" kèm nút "Tạo bài viết" | Lỗi đọc storage cục bộ | Xóa bản nháp: xóa khỏi danh sách sau khi popup xác nhận |
| **R14 Edit Profile** | Nút "Lưu" hiển thị spinner | Form thông tin, avatar tròn, username check | N/A | Báo lỗi trùng username hoặc lỗi cập nhật; giữ nguyên form | Avatar preview cập nhật ngay; chỉ lưu chính thức khi nhấn nút Lưu |
| **R15 Question Detail** | Spinner thread câu hỏi | Câu hỏi lớn, câu trả lời hữu ích, thread phản hồi | "Chưa có câu trả lời nào" | Giữ nguyên câu trả lời đang soạn khi lỗi mạng | Bình chọn hữu ích (Useful vote): đổi state ngay; nếu lỗi thì rollback |
