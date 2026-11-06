# SAMAN COMMUNITY — CP-03: Ghi chú triển khai R11–R15

Ngày: 01/11/2026  
Đối tượng: Anti / agent triển khai Flutter  
Trạng thái: Chốt hướng thiết kế sau vòng polish màu nút và header. Chưa triển khai/kiểm thử mã nguồn.

## 1. Đọc trước khi build

Đặt file này cùng ảnh, HTML/code và assets export của bộ CP-03. Đây là tài liệu bổ sung cho note CP-01 và CP-02, không thay thế hai tài liệu đó.

- Dùng phiên bản R11–R15 cuối cùng: header tiếng Việt, nút trung tính, xanh dịu, R14 có Lưu trên header. Không dùng bản cũ có nút mint lớn ở đáy hoặc header lặp.
- Người dùng chốt hướng giao diện; các quy tắc dữ liệu, lỗi, quyền và state dưới đây vẫn cần triển khai đầy đủ trong phạm vi checkpoint được giao.
- Note dựa trên ảnh tổng quan và yêu cầu đã thống nhất, chưa kiểm tra HTML/assets hoặc repository. Không coi kích thước chữ trong ảnh overview là thông số Flutter.
- Khảo sát repo/branch/HEAD, git status, AGENTS.md, allowed scope, router, theme, localization, auth và WIP trước sửa. Bảo toàn công việc khác; không reset/clean hoặc tự merge/phát hành.
- Không tự redesign, mở rộng sang chat/reels hoặc thay kiến trúc toàn app.

## 2. Danh sách màn

| ID | Nhãn giao diện | Điểm vào |
| --- | --- | --- |
| R11_Community_Notifications | Thông báo | Tab Thông báo của Community |
| R12_Community_Saved | Đã lưu | Menu riêng trong R09 của chính mình |
| R13_Community_Drafts | Bản nháp | Menu riêng trong R09 của chính mình |
| R14_Community_Edit_Profile | Chỉnh sửa hồ sơ | Nút chỉnh sửa tại R09 của chính mình |
| R15_Community_Question_Detail | Thảo luận | Câu hỏi từ feed, profile, saved hoặc thông báo |

Mapping file/route thực tế do Anti khảo sát và ghi trong báo cáo; không giả định filename từ tên frame.

Tổng thiết kế hiện tại: CP-01 5 màn + CP-02 8 màn + CP-03 5 màn = **18 màn chính**. R06A–R06D thay R06 cũ; không đếm cả bản cũ.

## 3. Style và những chi tiết cần chuẩn hóa khi build

- Giữ nền gần đen, bề mặt charcoal, viền nhẹ, chữ trắng/xám và icon mảnh theo bộ đã duyệt.
- Hành động phụ dùng nền trung tính hoặc text; tránh phủ xanh mọi metadata/badge/icon.
- Primary solid tham khảo #08664F + chữ/icon trắng; text action trên nền tối tham khảo #8AD8BD. Tái sử dụng theme app khi phù hợp và kiểm tra tương phản màu render thực tế.
- Mỗi màn chỉ một header. Loại bỏ nhãn frame, công cụ Stitch, đường viền chọn màu tím, thanh trạng thái developer và nút mô phỏng.
- R14 Lưu ở góc phải, không thêm lại nút mint lớn ở đáy.
- Ảnh overview có chữ nhỏ và một số vùng bị mờ: không sao chép độ mờ/cỡ chữ đó vào sản phẩm. Kiểm tra trực tiếp trên chiều rộng 390–412 và màn hẹp hơn.
- Body khoảng 15–16, metadata khoảng 12–14 là điểm khởi đầu; điều chỉnh theo token và text scaling. Vùng chạm khoảng 44–48.
- Nội dung dài được cuộn, không thu nhỏ chữ để nhét toàn thread vào một viewport.
- Tất cả nhãn qua localization. Nhãn tiếng Anh trong nội dung mẫu không biến thành chuỗi hệ thống hardcode.
- Các tên Kinetic/brand mẫu, huy hiệu chuyên gia/xác minh, online status, follower/interaction counts phải được thay hoặc bỏ nếu không có dữ liệu/cơ chế thật.
- Bio ở R14 và nội dung bài có thể còn thương hiệu mẫu: chuẩn hóa về Saman hoặc câu chữ trung tính trong fixture, không làm sai thông tin user thật.

## 4. Navigation và state chung

| Hành động | Kết quả |
| --- | --- |
| Tab Thông báo | R11 |
| Thông báo bài thông thường | R05 bằng postId |
| Thông báo câu hỏi/câu trả lời | R15 bằng questionId và answer/commentId nếu có |
| Avatar/tên người | R09 theo userId |
| R09 menu Đã lưu / Bản nháp | R12 / R13 |
| R09 chỉnh sửa | R14, chỉ tài khoản chính mình |
| R12 mở bài / câu hỏi | R05 / R15 |
| R13 tiếp tục bài / câu hỏi | R06D / R08, khôi phục đúng draft |
| R14 lưu thành công | Trở lại R09 và đồng bộ profile |

- Back về đúng điểm vào, giữ vị trí cuộn, bộ lọc và query khi phù hợp.
- R11 có Community bottom navigation, tab Thông báo active. R12–R15 là màn phụ, không hiện bottom navigation.
- Không hiện đồng thời Community navigation và navigation chính của Saman.
- R15 là màn hỏi đáp chuyên sâu mới, không thay R05 cho bài cộng đồng thông thường.
- Trước đây câu hỏi có thể dùng renderer cơ bản R05; khi R15 được triển khai, cập nhật các entry point câu hỏi thống nhất sang R15.

## 5. R11 — Thông báo

### Hiển thị

- Một header “Thông báo”, control cài đặt; thao tác Đã đọc/đánh dấu tất cả đã đọc phải rõ nghĩa, có tooltip/nhãn accessibility.
- Filter Tất cả / Bình luận / Theo dõi; nhóm Hôm nay / Trước đó theo múi giờ người dùng.
- Loại sự kiện: like bài, comment, reply, câu trả lời mới, follower mới.
- Avatar, tên, snippet, timestamp, thumbnail nếu phù hợp. Unread có dấu hiệu nhỏ, không tô cả card xanh.
- Không hiện nút theo dõi lại nếu đã theo dõi hoặc là chính mình.

### Hành vi

- Mở đúng đối tượng và nếu có, cuộn/highlight đúng comment hoặc answer, hỗ trợ tải trang chứa target.
- Tap avatar đi hồ sơ, tap follow thay đổi quan hệ; không kích hoạt nhầm tap cả hàng.
- Unread state và unread count cập nhật khi đọc theo contract; đánh dấu tất cả không được chỉ đổi màu tạm rồi reset khi mở lại.
- Read/unread và filter không làm mất thông báo hoặc tạo duplicate khi paging.
- Nếu đối tượng gốc bị gỡ/không còn quyền xem, hiện thông báo ngắn và cho quay lại, không bypass quyền truy cập.
- Follow state dùng chung R04/R09/R10; rollback khi lỗi.

### Cài đặt

Sheet phân nhóm Thích / Bình luận & trả lời / Người theo dõi mới / Câu hỏi đang theo dõi. Ghi rõ preference có tác động đến inbox trong app hay push; contract phải quyết định rõ, không âm thầm xóa lịch sử thông báo.

Quyền push hệ điều hành là cơ chế riêng, không dựng dialog custom giả làm quyền hệ thống và không tự xin quyền ngay khi mở R11.

## 6. R12 — Bài Community đã lưu

- Chỉ hiện nội dung tài khoản hiện tại đã lưu; dòng “Chỉ bạn nhìn thấy nội dung đã lưu” phải đúng cả API.
- Không trộn bài editorial Journal vào đây; Journal saved là loại nội dung riêng.
- Filter Tất cả / Bài viết / Hỏi đáp. Nếu export còn filter thừa ngoài phạm vi, chỉ giữ khi được backend/contract hỗ trợ và ghi rõ.
- Lưới 2 cột, có tile phù hợp bài text, câu hỏi, workout attachment không ảnh; không để ô trắng/lỗi ảnh.
- Caption ngắn, đủ đọc; giảm metrics không phục vụ tìm lại bài.
- Mở postId/questionId tương ứng, không mở tất cả tile thành một bài mẫu.
- Save/unsave dùng chung state với feed/detail; bỏ lưu cập nhật danh sách, có snackbar Hoàn tác nếu được triển khai.
- Undo phải phản ánh thao tác thật, xử lý request race khi bỏ lưu rồi lưu lại nhanh.
- Bài bị xóa/hạn chế: không hiển thị preview riêng tư từ cache; có trạng thái không khả dụng và thao tác gỡ khỏi saved.
- Saved riêng tư không làm bài gốc vốn private trở thành public.
- Không tự thêm collections tùy chỉnh trong checkpoint này.

## 7. R13 — Bản nháp

- Danh sách riêng tư theo tài khoản, mỗi draft có draftId, loại, preview, thời điểm sửa.
- Loại: bài thường, câu hỏi, chia sẻ workout, chia sẻ meal. Row mở draft; menu có Tiếp tục chỉnh sửa / Xóa.
- Text/ảnh/album edit/attachment/audience/topic/comment setting phải được khôi phục theo draft contract CP-02.
- Bài thường mở R06D; câu hỏi mở R08. Có thể từ composer quay lại media editor mà giữ toàn bộ state.
- Không dùng nội dung đã publish làm draft nếu backend đang kiểm tra kết quả publish sau timeout.
- Xóa cần xác nhận đúng draft; không xóa bài đã xuất bản hay nguồn Workout/Nutrition.
- Xóa media tạm theo ownership/reference, tránh xóa file còn được draft/bài khác dùng.
- Media local mất hoặc hết quyền: nhãn Cần chọn lại ảnh, giữ caption và các phần còn lại.
- Empty: Chưa có bản nháp, CTA tạo bài mở sheet tạo nội dung.
- Không ghi “Tự động lưu” nếu chưa có cơ chế thật. Phải nêu trong báo cáo draft lưu local hay server, có qua restart hay không.
- Logout/chuyển tài khoản không làm lộ draft cũ.

## 8. R14 — Chỉnh sửa hồ sơ cộng đồng

- Header Back / Chỉnh sửa hồ sơ / Lưu; Lưu disabled khi chưa đổi, không hợp lệ hoặc đang gửi.
- Fields: avatar, tên hiển thị, username, bio, sở thích tùy chọn.
- Không đưa cân nặng, số đo, bệnh sử, mục tiêu calories, email hoặc số điện thoại lên form công khai này.
- Tên và avatar nào đang dùng chung với Profile chính phải theo model tài khoản hiện tại, không âm thầm tạo bản thứ hai hoặc sửa trường sức khỏe.
- Avatar dùng chung với Saman theo thiết kế đã thống nhất. Trước đổi phải có mô tả “Ảnh đại diện cũng được cập nhật trong Saman”.
- Sheet đổi avatar: thư viện/chụp nếu hỗ trợ/xóa ảnh. Chỉ xin quyền khi người dùng chọn thao tác; có fallback khi từ chối.
- Upload/crop/preview có state lỗi; chỉ cập nhật chính thức theo quy trình save đã chọn. Nếu upload trước, giữ temporary state, không khiến avatar toàn app đổi dù user đã hủy form.
- Username validation theo contract: ký tự, trim/normalize, độ dài, tên đã dùng. Check bất đồng bộ phải debounce và tránh kết quả query cũ đè query mới.
- Server quyết định uniqueness cuối cùng; xử lý conflict khi Save dù trước đó hiện khả dụng.
- Hạn chế ký tự bio/tên theo contract, không tự coi con số demo Stitch là giới hạn thật.
- Save thành công cập nhật R09, avatar/header, feed/comment theo contract hiện có. Lỗi giữ dữ liệu đã nhập.
- Back khi dirty có Bỏ thay đổi / Tiếp tục chỉnh sửa. Không mất form do Back hệ thống.
- Không cho người dùng tự cấp badge chuyên gia/xác minh.

## 9. R15 — Thảo luận / chi tiết hỏi đáp

### Nội dung và cấu trúc

- Header Back / Thảo luận / menu theo quyền.
- Tác giả, thời gian, chủ đề, câu hỏi lớn, mô tả và ảnh hỗ trợ nếu có.
- Hiển thị questionId đúng, không hardcode câu hỏi meal prep.
- Save, chia sẻ và theo dõi câu hỏi là ba hành động riêng. Theo dõi câu hỏi không tự follow tác giả.
- Chỉ dùng từ Đang thảo luận / Đã có câu trả lời hữu ích nếu backend có trạng thái đó.

### Câu trả lời

- Danh sách có paging; sort Mới nhất / Hữu ích dựa dữ liệu thật. Đổi sort không nhân đôi hoặc bỏ sót items.
- Mỗi answer có author, text, timestamp, useful state/count, reply và menu phù hợp quyền.
- Thread hiển thị lồng một mức rõ ràng, có Xem thêm phản hồi; không thu nhỏ hoặc lồng sâu vô hạn.
- Hữu ích là vote/toggle của viewer; đồng bộ count và rollback nếu request lỗi.
- Người hỏi có thể chọn một câu trả lời hữu ích; nhãn “Người hỏi lựa chọn”. User khác không có quyền chọn thay.
- Có thể bỏ lựa chọn; khi đổi câu được chọn, UI/server phải giữ một lựa chọn duy nhất theo quy tắc này.
- Vote nhiều hoặc được người hỏi chọn không có nghĩa là chuyên gia đã kiểm chứng; bỏ nhãn PRO COACH/verified tự sinh từ mẫu.
- Nếu answer được chọn bị xóa, state câu hỏi cần cập nhật theo contract; không tiếp tục render answer đã bị gỡ.

### Composer

- Ô đáy “Chia sẻ câu trả lời của bạn…”, send disabled khi trim rỗng hoặc đang gửi.
- Reply có đối tượng đang trả lời và hủy reply; giữ text khi mở bàn phím/đổi layout.
- Error giữ nội dung, cho retry, chống double tap và duplicate theo request contract.
- Tôn trọng keyboard/safe area; nội dung cuối không bị composer che.
- Chủ bài tắt bình luận → thay composer bằng giải thích. Backend vẫn phải từ chối reply nếu quyền thay đổi trong khi đang mở màn.
- Bài bị gỡ/mất quyền xem → ngừng truy cập nội dung/ảnh riêng tư; hiển thị state phù hợp và Back.

## 10. Sheet và state phụ cần bàn giao

| Thành phần | Điểm sử dụng |
| --- | --- |
| Tùy chọn thông báo | R11 |
| Menu Đã lưu / Bản nháp của chính mình | R09 |
| Xác nhận xóa draft | R13 |
| Đổi avatar + từ chối quyền/lỗi upload | R14 |
| Bỏ thay đổi form | R14 |
| Sort câu trả lời | R15 |
| Chọn/bỏ câu trả lời hữu ích | R15, chủ câu hỏi |
| Loading / empty / error / retry | Mọi danh sách/màn cần fetch |
| Nội dung không còn khả dụng | R11/R12/R15 |

Không cần gán R mới cho sheet/state. Không đưa các nút toggle state demo vào sản phẩm.

## 11. Dữ liệu, kiến trúc và giới hạn phạm vi

- Khảo sát API thật; phần chưa có dùng typed Repository interface + Fake implementation qua DI hiện có. Không mặc định toàn app chưa có backend.
- Không hardcode list, counters, username availability hoặc xử lý mạng trong Widget.
- Dùng chung state/store/repository cho profile, follow, save, draft và post/question giữa các checkpoint.
- ID cần phân biệt rõ userId/postId/questionId/answerId/commentId/draftId; không route dựa caption.
- Quyền author/owner/audience, saved/draft riêng tư phải được backend kiểm soát khi live. UI ẩn nút không thay kiểm tra quyền.
- Không lưu dữ liệu nhạy cảm vào log/fixture hoặc lộ cache khi chuyển tài khoản.
- Public sharing không được bypass quyền followers-only. Nếu chưa có deep link public phù hợp, ghi rõ khả năng chia sẻ thực tế, không tạo URL giả.
- Bộ CP-03 không tự bổ sung moderation dashboard, chat, push infrastructure đầy đủ hay màn cẩm nang. Những phụ thuộc chưa có cần ghi backlog và trạng thái chưa hỗ trợ rõ ràng.
- Nội dung người dùng chỉ là chia sẻ cộng đồng, không tự nâng thành bài cẩm nang đã duyệt hoặc dữ liệu Nutrition kiểm chứng.

## 12. Checklist nghiệm thu

- [ ] Dùng bản cuối R11–R15; không header lặp, label tool, badge/brand mẫu sai.
- [ ] Nút, icon và chữ dễ đọc ở màn thực tế; keyboard/text 200% không gây overflow/che action.
- [ ] R11 đọc/unread/filter/paging đúng; mở đúng bài/câu trả lời.
- [ ] R12 save/unsave/undo đồng bộ; không lộ bài mất quyền xem.
- [ ] R13 khôi phục đúng toàn bộ draft; thiếu ảnh không mất text; xóa không tác động bài đã publish.
- [ ] R14 dirty/validation/username race/conflict/avatar/lưu lỗi/Back hoạt động.
- [ ] Avatar/name đồng bộ đúng với hồ sơ và app; không sửa ngoài ý muốn khi hủy.
- [ ] R15 vote hữu ích và lựa chọn của người hỏi là hai state/quyền khác nhau.
- [ ] Reply/retry không duplicate; tắt bình luận/mất quyền được xử lý cả client và server khi live.
- [ ] Back giữ đúng context; R11 có navigation, R12–R15 không có bottom nav thừa.
- [ ] Logout/chuyển tài khoản không lộ saved/drafts/profile form của user trước.
- [ ] Mọi tính năng chưa có API được báo rõ fake/UI-only/pending, không báo PASS toàn mạng xã hội.

## 13. Báo cáo Anti cần bàn giao

1. Repo/branch/HEAD, file sửa và phiên bản export đã dùng.
2. Mapping 5 frame → Flutter screen/route, navigation map nối R01–R10.
3. Component và state dùng chung; API thật/Fake/khả năng chưa có.
4. Kết quả analyze/test phù hợp, ảnh app thật và kiểm tra text/keyboard.
5. Sai khác so với thiết kế đã chốt và các hạn chế còn lại.
6. Backlog phụ thuộc trước khi phát hành Community thật.

Chỉ báo hoàn thành các hành vi đã kiểm tra trong phạm vi được giao; build thành công không đồng nghĩa toàn bộ chức năng đã đạt.
