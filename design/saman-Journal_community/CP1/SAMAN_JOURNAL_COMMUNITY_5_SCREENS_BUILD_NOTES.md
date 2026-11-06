# SAMAN JOURNAL & COMMUNITY — Ghi chú bàn giao 5 màn hình

Ngày: 01/11/2026  
Đối tượng: Anti / agent triển khai Flutter  
Trạng thái: Người dùng đã chốt hướng thiết kế 5 màn R01–R05. Chưa đồng nghĩa đã triển khai hoặc kiểm thử.

## 1. Đọc trước khi triển khai

Đặt tài liệu này cùng bộ export Stitch của 5 màn. Đọc ảnh, HTML/code và assets thực tế trong bộ export trước khi sửa code. Tài liệu được lập từ yêu cầu và ảnh tổng quan đã duyệt; chưa kiểm tra nội dung HTML/assets xuất ra và chưa khảo sát repository hiện tại.

- Giữ hướng thiết kế đã chốt; không tự redesign toàn bộ.
- Ảnh/code Stitch mô tả giao diện. Tài liệu này giải thích hành vi, ranh giới tính năng và lưu ý khi build.
- Khi có khác biệt: giữ ý định sản phẩm trong tài liệu, style từ thiết kế đã duyệt; ghi rõ khác biệt quan trọng cần giải quyết.
- Khảo sát workspace, branch, git status, AGENTS.md, router, theme, localization, auth và các thay đổi đang dở trước khi sửa.
- Không giả định branch, đường dẫn file, thư viện hay API từ tên trong tài liệu. Xác minh trong repo.
- Bảo toàn WIP của các luồng khác; không reset/clean, không tự merge hoặc phát hành.
- Đây là ghi chú sản phẩm, không thay thế quy định phạm vi sửa trong repository. Lập danh sách file cần sửa theo quy trình đang áp dụng.

## 2. Cấu trúc sản phẩm đã chốt

**Saman Journal** là khu vực kiến thức: Khám phá, Thư viện, Cẩm nang.

**Saman Community** là khu vực mạng xã hội mini độc lập: bảng tin, khám phá nội dung/thành viên, đăng bài, thảo luận, hồ sơ và thông báo.

- Community không còn là tab thứ tư của Journal.
- Journal có một card dẫn vào Community.
- Journal search không trộn bài cộng đồng vào kết quả.
- Community có điều hướng nội bộ riêng, không thêm tab chính mới cho toàn app trong phạm vi này.
- Bộ 5 màn chỉ là nền tảng; các màn chức năng chưa có thiết kế được liệt kê riêng bên dưới.

## 3. Danh mục 5 màn

| ID export | Vai trò | Nhãn hiển thị đề xuất |
| --- | --- | --- |
| R01_Journal_Discover | Trang đầu Journal | Saman Journal |
| R02_Journal_Search | Tìm nội dung kiến thức | Tìm kiếm |
| R03_Community_Feed | Bảng tin mạng xã hội mini | Saman Community |
| R04_Community_Discover | Tìm bài, chủ đề và thành viên | Khám phá cộng đồng |
| R05_Community_Post_Detail | Bài cộng đồng và bình luận | Bài viết |

Tên frame có thể giữ để đối chiếu. Các chữ “Community Feed”, “Community Explore”, “Detail Stack” trong mẫu cần chuyển thành nhãn giao diện đúng nghĩa qua localization.

## 4. Điều hướng

| Điểm chạm | Đích/hành vi |
| --- | --- |
| Card Saman Journal ở Home | R01 |
| Search trong R01 | R02 |
| Card Saman Community trong R01 | R03, mở khu vực Community riêng |
| Tab Khám phá của Community | R04 |
| Card bài cộng đồng / nút bình luận | R05 bằng đúng postId |
| Quay lại R02 | Về R01, giữ vị trí cuộn |
| Quay lại R05 | Về feed/discover đã mở bài, giữ bộ lọc và vị trí |
| Quay lại từ màn gốc Community | Trở lại Journal khi vào từ Journal |

Tích hợp router theo kiến trúc hiện có; không tự dựng một cây navigation song song gây trùng shell.

- Journal có 3 tab: Khám phá / Thư viện / Cẩm nang. Hai tab sau chưa được bao phủ đầy đủ bởi bộ này.
- Community có thanh dưới: Bảng tin / Khám phá / Đăng bài (+) / Thông báo / Cá nhân.
- Đăng bài là hành động mở composer, không phải tab nội dung lưu trạng thái chọn.
- R05 ưu tiên ô bình luận ở đáy; không hiện thanh điều hướng Community tại đây.
- Không hiển thị đồng thời thanh điều hướng chính Saman và thanh điều hướng Community.
- Nếu export có thêm thanh header/browser, nhãn frame, thanh công cụ Stitch hoặc header lặp, loại phần công cụ khi chuyển sang app.
- Xử lý cả nút Back trên giao diện và Back hệ thống, không tạo vòng lặp route.

## 5. R01 — Journal Discover

- Header gọn, nút quay lại, tên Journal và lối vào nội dung đã lưu theo thiết kế.
- Bài nổi bật: ảnh thật, nhãn chủ đề, tiêu đề, mô tả ngắn, thời gian đọc.
- Các chủ đề: Tập luyện / Dinh dưỡng / Phục hồi / Thói quen.
- Tiếp tục đọc: chỉ hiện khi có lịch sử; không gán cứng 40% cho mọi tài khoản.
- Thư viện: hai lối vào Bài tập & lịch tập; Thực phẩm & công thức.
- Chuỗi Bắt đầu cùng Saman và card vào Community.
- Card bài nổi bật phải dùng articleId. Màn bài Journal chưa có trong 5 màn; không dùng R05 thay thế vì R05 là bài cộng đồng.
- Không khẳng định bài do huấn luyện viên/chuyên gia biên soạn nếu chưa có người và quy trình xác minh thật.

## 6. R02 — Journal Search

- Tìm bài viết, bài tập, thực phẩm và công thức; không tìm bài Community ở màn này.
- Query và bộ lọc là state; clear query hoạt động; xử lý tiếng Việt theo khả năng nguồn dữ liệu.
- Debounce và xử lý kết quả trả về sai thứ tự để query cũ không đè query mới.
- Chỉ hiện số lượng nếu nguồn dữ liệu có cung cấp chính xác. Không dùng số lượng minh họa làm số liệu thật.
- Nhãn kết quả, thời gian đọc, ảnh, đơn vị dinh dưỡng phải rõ ràng.
- Nút “+” ở thực phẩm trong mẫu không được tự ghi bữa ăn bằng một lần chạm: mở chọn khẩu phần/bữa/ngày và yêu cầu xác nhận qua luồng Nutrition hiện có. Nếu chưa có luồng, dùng hành động xem chi tiết.
- Có trạng thái trước khi tìm, đang tải, không có kết quả, lỗi và thử lại. Không đưa nút chuyển state demo vào UI sản phẩm.

## 7. R03 — Community Feed

- Bộ lọc: Dành cho bạn / Đang theo dõi / Hỏi đáp.
- Các loại nội dung đầu tiên: bài văn bản/ảnh, thẻ buổi tập chia sẻ, câu hỏi.
- Avatar, tác giả, thời gian, nội dung, ảnh và số tương tác lấy từ model.
- Like/unlike, save/unsave, comment và follow có trạng thái rõ; chống bấm lặp khi request đang xử lý.
- Nếu dùng cập nhật lạc quan, rollback và báo lỗi khi thất bại; feed và detail phải đồng bộ.
- Phân trang, chống trùng postId, làm mới và tải tiếp; không tải toàn bộ ảnh/feed cùng lúc.
- “Đã xem hết bài mới” chỉ hiện khi thực sự hết dữ liệu.
- Filter Đang theo dõi có empty state và lối khám phá thành viên.
- Hỏi đáp có thể lọc trên feed nhưng màn câu hỏi chuyên sâu chưa thuộc 5 màn đã duyệt.
- Không tự tạo thuật toán cá nhân hóa hoặc xu hướng giả; fake data phải được quản lý ở tầng dữ liệu.

## 8. R04 — Community Discover

- Search riêng cho bài cộng đồng, chủ đề và thành viên.
- Lưới ảnh bấm mở đúng bài R05; album có chỉ báo khi thật sự nhiều ảnh.
- Chủ đề mở nội dung theo chủ đề; danh sách gợi ý theo dõi phản ánh đúng follow state.
- Tỷ lệ tăng trưởng, số lượt hoạt động, nhãn xác minh và số follower trong mẫu đều là dữ liệu minh họa, không được tự xem là thật.
- Không làm ô ảnh quá nhỏ để nhét thêm nội dung. Crop ảnh nhất quán, tải lazy và có fallback.
- Giữ query/filter và vị trí cuộn khi quay lại từ chi tiết.

## 9. R05 — Community Post Detail

- Mở đúng bài từ ID, không hardcode bài mẫu Linh Nguyễn cho mọi điểm vào.
- Hiện tác giả, nội dung, ảnh/album hoặc attachment, tương tác và bình luận.
- Tái sử dụng renderer của feed để hiển thị được bài ảnh, văn bản, thẻ buổi tập và câu hỏi ở mức cơ bản; không giả định mọi bài đều có ảnh bữa ăn.
- Bình luận có phân trang; hỗ trợ trả lời, hiện người đang được trả lời và hủy trả lời.
- Ô nhập tôn trọng safe area/keyboard; nút gửi tắt nếu chỉ có khoảng trắng.
- Đang gửi có feedback; lỗi giữ lại nội dung và cho thử lại; không gửi trùng do double tap/retry.
- Phân biệt quyền tác giả bài và tác giả bình luận. Không để user sửa/xóa nội dung người khác bằng kiểm tra UI đơn thuần.
- Khi bài bị gỡ/không tồn tại/hạn chế truy cập, có trạng thái phù hợp và lối quay lại.

## 10. Tái sử dụng Workout và Nutrition

| Nội dung | Liên kết cần giữ |
| --- | --- |
| Kết quả bài tập Journal | exerciseId → chi tiết bài tập hiện có |
| Lịch tập mẫu | Xem trước → xác nhận thêm theo luồng Workout |
| Thực phẩm | foodId → chi tiết thực phẩm hiện có |
| Công thức | recipeId → chi tiết; chỉ ghi bữa sau khi chọn khẩu phần/xác nhận |
| Workout attachment | Bản tóm tắt được chủ sở hữu chủ động chia sẻ, không lộ toàn bộ session riêng tư |
| Meal attachment | Thông tin người dùng chủ động chọn chia sẻ, không tự công khai nhật ký Nutrition |

- Không tạo catalog bài tập/thực phẩm độc lập gây lệch dữ liệu.
- Bài của người khác không được đọc bằng endpoint session cá nhân của họ. Cần public/shared representation phù hợp.
- Số liệu bữa ăn do user nhập không tự trở thành dữ liệu dinh dưỡng đã kiểm chứng.
- Không tự đăng bài sau khi hoàn thành workout hoặc ghi bữa ăn.
- Xem/đọc bài không tự thay đổi lịch tập, bữa ăn hoặc chỉ số cá nhân.

## 11. Kiến trúc và dữ liệu

- Xác minh backend thật và contract đang có. Không mặc định toàn dự án chưa có backend.
- Với phần Journal/Community chưa có API: dùng interface + Fake/Mock Repository, tách khỏi Widget; nối qua DI/state management của dự án (ưu tiên tái sử dụng Riverpod nếu repo đang dùng).
- Không hardcode danh sách bài, interaction counts hoặc logic mạng trong Widget.
- Fake Repository giả lập loading/success/empty/error và độ trễ; cấu hình mô phỏng ở môi trường dev, không đặt nút điều khiển trong UI người dùng.
- Model có type: article, author, community post, attachment, comment, follow state, search result và paging khi cần. Phân biệt rõ articleId và postId.
- Lưu/bỏ lưu và follow phải đúng tài khoản; xóa state/cache riêng tư khi logout/chuyển tài khoản.
- Không hiển thị dữ liệu mock như đã được server xác nhận. Báo cáo bàn giao phải nêu rõ phần fake và phần live.
- Tránh thêm package nếu kiến trúc hiện có đã đáp ứng.

## 12. Quy chuẩn chuyển thiết kế sang Flutter

- Dùng theme/design tokens của app; không rải mã màu và TextStyle khắp màn.
- Giữ nền tối, card charcoal, viền nhẹ, xanh Saman và icon mảnh như mẫu chốt.
- Không bê HTML vào WebView để thay màn Flutter nếu dự án đang triển khai native Flutter.
- Ảnh tổng quan bị thu nhỏ không phải thông số font. Kiểm tra ở chiều rộng 390–412 logical pixels và màn hẹp hơn; body khoảng 15–16, secondary 12–14 là điểm khởi đầu để đối chiếu theme.
- Hỗ trợ text scaling đến 200% và không cắt CTA, tab, tên tác giả hoặc ô bình luận.
- Vùng chạm tối thiểu khoảng 44–48; semantics/tooltip cho icon; không chỉ dùng màu biểu thị trạng thái.
- Tối ưu ảnh theo vùng hiển thị, có loading/error placeholder; không để ảnh lỗi, alt text HTML hoặc khoảng trống hero lớn.
- Không bundle ảnh không rõ quyền sử dụng hoặc hotlink URL tạm từ Stitch. Kiểm kê assets đã xuất và xác minh cách cấp phát phù hợp.
- Tất cả chuỗi qua localization; chuẩn hóa nhãn Anh/Việt và định dạng ngày, số, đơn vị theo locale hiện có.
- Không đưa số frame, chữ checkpoint, trạng thái developer hoặc thông số build lên UI sản phẩm.

## 13. Các điểm chưa đủ màn thiết kế

Bộ này chưa bao gồm: chi tiết bài Journal; trang Thư viện/Cẩm nang đầy đủ; chuỗi bài; tạo/sửa bài; chọn attachment; đặt câu hỏi/chi tiết hỏi đáp chuyên sâu; hồ sơ; thông báo; saved; danh sách follower; nhắn tin; báo cáo/chặn và các màn quyền riêng tư.

- Ghi rõ các điểm đến còn thiếu trong navigation map/backlog trước khi build.
- Nếu repo có màn phù hợp, tái sử dụng. Nếu chưa có, gắn với phạm vi checkpoint kế tiếp; không tự triển khai toàn mạng xã hội từ tài liệu này.
- Nếu cần bản demo của 5 màn trước, có thể dùng thông báo chưa khả dụng rõ ràng hoặc trạng thái disabled cho đích chưa làm; không điều hướng sang màn sai nghĩa và không dùng nút chết.
- Nhắn tin trên header là tính năng tương lai; không tự xây chat/realtime trong phạm vi 5 màn.
- Báo cáo/chặn, phân quyền và xử lý nội dung là phần cần hoàn thiện trước khi mở Community thật cho người dùng công khai; UI prototype không được báo cáo là social production-ready.

## 14. Checklist nghiệm thu

- [ ] 5 màn đối chiếu đúng frame/asset, giữ style Home và không có nhãn công cụ Stitch.
- [ ] Home → Journal → Community → bài → Back đúng; giữ state khi quay lại.
- [ ] Search Journal và search Community tách phạm vi; kết quả cũ không đè query mới.
- [ ] Feed/detail đồng bộ like/save; lỗi mạng có feedback và rollback phù hợp.
- [ ] Bình luận rỗng bị chặn; lỗi không mất draft; bấm lặp không tạo bản sao.
- [ ] Workout/Nutrition mở đúng đối tượng; không ghi dữ liệu hoặc công khai dữ liệu ngoài ý muốn.
- [ ] Loading/empty/error/retry/deleted-content hoạt động; ảnh lỗi có fallback.
- [ ] Không overflow ở màn hẹp, text 200%, bàn phím mở và vùng safe area.
- [ ] Không lộ dữ liệu tài khoản cũ khi logout/chuyển tài khoản.
- [ ] Các đích chưa triển khai được liệt kê minh bạch; không báo hoàn thành tính năng chưa làm.

## 15. Báo cáo Anti cần bàn giao

1. Repo/branch/HEAD và phạm vi file thực tế đã sửa.
2. Mapping 5 frame → màn Flutter/route thực tế.
3. Các component dùng chung và điểm tích hợp Workout/Nutrition.
4. Danh sách tính năng live, fake, chưa làm; các khác biệt so với export.
5. Kết quả analyze/test phù hợp, ảnh UI thực tế và các lỗi tồn tại.
6. Navigation map và backlog màn tiếp theo.

Không tuyên bố PASS chỉ từ build thành công. Nghiệm thu cần kiểm tra giao diện và các hành vi trong phạm vi thực tế đã triển khai.
