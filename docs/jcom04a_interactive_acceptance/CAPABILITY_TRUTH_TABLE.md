# BẢNG MA TRẬN MINH BẠCH NĂNG LỰC HỆ THỐNG (CAPABILITY TRUTH TABLE)
## SAMAN JOURNAL & COMMUNITY FRONTEND RUNTIME (JCOM-04A)

**Thời gian khảo sát & lập bảng:** 01/11/2026 22:43:00 +07:00  
**Môi trường thực thi:** Google Chrome 156.0 (Headless CDP) trên Web Runtime `http://127.0.0.1:8089/`  
**Cơ chế lưu trữ:** In-memory Riverpod State & Fake Repository DI (0 live backend routes)  

---

## 1. Bảng Ma Trận Năng Lực Chi Tiết (Capability Truth Matrix)

| Capability (Năng lực) | Implementation thực tế | Nguồn dữ liệu | Memory / Persistent | Bằng chứng thực tế | Giới hạn & Điểm dừng kỹ thuật |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Media Editing (Crop, Rotate, Filter)** | Bộ điều khiển giao diện: tỉ lệ 1:1, 4:5, orig; `Transform.rotate` xoay 90°; `ColorFiltered.matrix` thanh trượt Độ sáng & Tương phản (-50 đến +50); Lưới căn chỉnh 3x3. | `CommunityComposerState` (In-memory URL list) | **Memory-only** (Trạng thái soạn thảo) | `rt07_composer_select_media.png`, `post_edit_media_screen.dart`, test suite composer | **Chỉ hỗ trợ preview trực quan:** Không thực hiện raster image processing để render file JPEG mới ra đĩa (do đóng băng dependency). Đã gắn thông báo minh bạch cho người dùng tại màn hình chỉnh ảnh. |
| **Activity Attachment (R07)** | Chọn hoạt động Buổi tập (Kinetic) hoặc Bữa ăn (Meal). Hỗ trợ xem trước thẻ bài đăng và 3 công tắc bảo mật (`includeDuration`, `includeExercises`, `includeLoadOrMacros` - mặc định TẮT). | Fake Fixtures qua `CommunityRepository` (`getRecentWorkoutActivities()`, `getRecentMealActivities()`) | **Memory-only** (Mẫu fixtures) | `rt08_composer_select_attachment.png`, `post_attachment_snapshot.dart:sanitize()` | **Không đọc trực tiếp từ database thật:** Dữ liệu là fixtures mô phỏng. Hàm `sanitize()` đã triệt tiêu hoàn toàn các trường nhạy cảm khỏi snapshot khi cờ tắt, không chỉ ẩn Widget. Không ghi vào nhật ký nguồn. |
| **Draft Lifecycle & Isolation** | Lưu bản nháp (Save draft), mở tiếp tục chỉnh sửa, xóa bản nháp khỏi kho (`CommunityDraftsScreen`). Hộp thoại xác nhận an toàn khi thoát (`DraftDiscardDialog`). | In-memory `List<DraftPost>` trong `CommunityFakeDatasource` có trường `userId` | **Memory-only** (RAM) | `rt14_community_drafts_manager.png`, test unit `Draft saving and deletion cycle` | **Chưa lưu persistent ra đĩa:** Bản nháp sẽ mất khi người dùng reload trang hoặc kill app. Phạm vi dữ liệu gắn với `userId` trong model, không được gọi là logout thật khi đổi DI container. |
| **Social Interactions (Like, Bookmark, Follow)** | Nhấn Thích (+1 count), Lưu bài viết vào kho Saved, Theo dõi tác giả. Trạng thái cập nhật tức thời và phản ánh chéo giữa Feed, Post Detail, Saved và Profile. | In-memory data store qua `communityFeedProvider`, `communityPostDetailProvider`, `communitySavedProvider` | **Memory-only** (RAM) | `rt03_community_feed.png`, `rt05_post_detail.png`, `rt13_community_saved_posts.png`, `rt15_community_profile.png` | **Không đồng bộ Cloud:** Dữ liệu lưu trong RAM của phiên chạy web hiện tại, không gửi request HTTP tới remote backend. |
| **Q&A Ask, Answer & Upvote** | Đặt câu hỏi chuyên đề (R08), hiển thị trên tab Hỏi đáp của Feed, mở màn hình R15, gửi câu trả lời và vote hữu ích (+1 upvote). Khóa double-submit `isSubmitting`. | In-memory `_questionAnswers` map trong `CommunityFakeDatasource` | **Memory-only** (RAM) | `rt09_composer_ask_question.png`, `rt11_qa_detail_answers.png`, `community_providers.dart:submitAnswer` | **Không đồng bộ Cloud:** Toàn bộ câu hỏi và câu trả lời mới sinh chỉ tồn tại trong runtime preview. |
| **Comments & Threaded Replies** | Soạn bình luận ở thanh cố định cuối màn hình R05, hỗ trợ phản hồi lồng nhau (`replyToCommentId`), khóa `isSubmitting` chống gửi trùng lặp khi tap nhanh. | In-memory `CommunityComment` list của từng bài viết | **Memory-only** (RAM) | `rt05_post_detail.png`, `rt18_post_detail_interactive.png`, `community_providers.dart:submitComment` | **Không gửi request live:** Khóa `isSubmitting` ngăn chặn hoàn toàn việc nhân đôi bình luận khi người dùng bấm liên tục. |
| **Data Honesty & Identity** | Hiển thị banner preview cố định `[PREVIEW]`, danh tính mẫu "Linh Nguyễn - Bản xem trước", tất cả chức danh tác giả đều có nhãn `(Mẫu)`, dải stats 42 tập / 18 ăn / 1.2k likes. | In-memory preview identity & fixtures | **Memory-only** (RAM) | `rt15_community_profile.png`, top preview banner trên tất cả màn hình | **Trung thực dữ liệu:** Tuyệt đối không tạo cảm giác đây là tài khoản thật, chứng nhận huấn luyện viên thực tế hay tương tác mạng xã hội thật. |

---

## 2. Kết luận Phân định Bốn Khía Cạnh (Four-Aspect Verdict)

1. **Frontend Preview Runtime:** **PASS (Đạt)**
   - 100% 18 màn hình và luồng tương tác hoạt động mượt mà, đầy đủ logic, phản ánh state chéo tức thì, không crash, không render overflow trên viewport 360px và 393px.
2. **Tích hợp từ Home qua Auth / Profile:** **BLOCKED (Bị chặn bởi Backend Profile)**
   - Endpoint `/api/user/profile` của backend thiếu trường `user_id`, khiến `ProfileRemoteDataSourceImpl` ném `FormatException` khi tải màn hình Home của app chính.
3. **Backend Journal / Community:** **NOT IMPLEMENTED (Đóng băng theo AGENTS.md)**
   - Toàn bộ backend được giữ nguyên 100% trạng thái đóng băng; đã lập tài liệu bàn giao kỹ thuật chi tiết tại `JCOM05_HANDOFF.md`.
4. **Media Processing & Attachment Source:** **PREVIEW CONTROLS & REPOSITORY FIXTURES**
   - Media editing vận hành bằng Flutter visual controls (Transform/ColorFilter), không rasterize ra file ảnh mới. Attachment source là fixtures mô phỏng được cô lập an toàn bằng hàm `sanitize()`.
