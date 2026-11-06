# SAMAN COMMUNITY — CP-02: Ghi chú triển khai 8 màn hình

Ngày: 01/11/2026  
Đối tượng: Anti / agent triển khai Flutter  
Phạm vi: R06A, R06B, R06C, R06D, R07, R08, R09, R10.

## 1. Mục đích và trạng thái

Tài liệu đặt cùng bộ export Stitch CP-02 để giải thích ý định sản phẩm, workflow click, phiên bản thiết kế và tiêu chí nghiệm thu.

- Người dùng đã chốt hướng bộ đăng bài sau vòng giảm màu xanh và bỏ header lặp.
- R08–R10 lấy từ lượt thiết kế trước, không bị thay thế bởi vòng chỉnh composer.
- Ghi chú dựa trên yêu cầu và ảnh đã cung cấp; chưa kiểm tra HTML/assets export hoặc mã nguồn hiện tại. Không coi đây là báo cáo đã build/test.
- Đọc cùng `SAMAN_JOURNAL_COMMUNITY_5_SCREENS_BUILD_NOTES.md` của CP-01. File này bổ sung CP-02, không thay thế toàn bộ note CP-01.
- Tổng hiện tại: CP-01 có 5 màn, CP-02 có 8 màn, cộng 13 màn chính; các sheet và state không tính thành màn chính riêng.

## 2. Danh mục và phiên bản phải dùng

| ID | Vai trò | Phiên bản dùng |
| --- | --- | --- |
| R06A_Post_Select_Media | Chọn ảnh | Bản cuối màu dịu, một header |
| R06B_Post_Edit_Media | Chỉnh ảnh | Bản cuối màu dịu, một header |
| R06C_Post_Album_Order | Sắp xếp album | Bản cuối màu dịu, một header |
| R06D_Post_Compose_Publish | Nội dung và xác nhận chia sẻ | Bản cuối màu dịu, một header |
| R07_Community_Select_Attachment_Refined | Chọn buổi tập/bữa ăn | Bản refined cuối cùng |
| R08_Community_Ask_Question | Đặt câu hỏi | Bản lượt trước; áp dụng quy tắc polish chung trong file này |
| R09_Community_Profile | Hồ sơ cộng đồng | Bản lượt trước; áp dụng quy tắc polish chung |
| R10_Community_Follow_List | Người theo dõi / Đang theo dõi | Bản lượt trước; áp dụng quy tắc polish chung |

R06 đơn màn cũ đã được thay bằng R06A–R06D: không build song song hai composer. R07 cũ được thay bằng bản refined cuối, không xuất/triển khai nhầm phiên bản.

Tên export có thể khác đôi chút: đối chiếu ID và nội dung, ghi mapping sang file Flutter/route thực tế trong báo cáo; không tự giả định đường dẫn repo.

## 3. Quy tắc hình ảnh và nội dung chung

- Giữ style Community đã chốt: nền gần đen, bề mặt charcoal, border nhẹ, ảnh lớn, icon outline mảnh.
- Xanh chỉ làm điểm nhấn; tránh phủ xanh đồng thời icon, text, chip, badge và CTA.
- Nút nền đặc có thể tham khảo emerald trầm `#087F66`, chữ trắng; accent chữ trên nền tối tham khảo `#54C7A5`. Ưu tiên token thực tế của app sau khi kiểm tra tương phản.
- Không giảm opacity toàn bộ nút enabled để làm dịu màu. Disabled cần có trạng thái riêng rõ ràng.
- Mỗi màn có một header chức năng. Bỏ header lặp “New Fitness Post”, “Share”, avatar công cụ và tên frame R06/R07.
- Không hiển thị công cụ mô phỏng như “Chế độ xem: Khách xem / Chính mình”, “Mô phỏng rỗng”, checkpoint hoặc frame ID trong sản phẩm.
- Tiếng Việt qua localization; không trộn nhãn tiếng Anh tùy tiện.
- Không giữ nhãn Kinetic/Kinetic Tracker/Kinetic 360 hoặc thương hiệu mẫu không thuộc Saman.
- Huy hiệu chuyên gia, xác minh, online status, số follower và tương tác trong mẫu không được mặc nhiên coi là thật.
- Không thu nhỏ font theo ảnh tổng quan. Kiểm tra màn hẹp, chữ lớn, safe area và bàn phím.
- Dùng ảnh export/nguồn hợp lệ, không hotlink URL tạm; có fallback và giới hạn tài nguyên.

## 4. Điểm vào và workflow tổng

Nút (+) Community là hành động mở sheet “Tạo nội dung”, không phải tab có nội dung riêng:

| Lựa chọn | Luồng |
| --- | --- |
| Bài viết | R06A → R06B → R06D → người dùng Chia sẻ |
| Đăng chỉ với nội dung | Từ R06A → R06D không có ảnh |
| Chia sẻ buổi tập | R07 tab Buổi tập → Đính kèm → R06D |
| Chia sẻ bữa ăn | R07 tab Bữa ăn → Đính kèm → R06D |
| Đặt câu hỏi | R08 → người dùng Đăng |

- R06C là bước phụ quản lý album, có thể mở từ bước chỉnh ảnh hoặc preview composer; Xong trả về đúng nơi đã mở.
- R06D mở R07 để thêm/thay attachment, rồi trở lại nguyên bản nháp.
- Avatar/tên tác giả trong feed, detail và danh sách mở R09 theo đúng userId.
- Tab Cá nhân mở R09 cho tài khoản hiện tại; số follower/following mở R10 đúng tab.
- Ẩn bottom navigation trong R06A–R08 và R10. R09 của chính mình ở tab Cá nhân có Community bottom navigation; hồ sơ người khác mở từ một bài dùng Back.
- Không hiện hai thanh navigation của Community và app chính cùng lúc.
- Back và nút đóng phải bảo toàn state theo quy tắc draft, không làm mất nội dung ngoài ý muốn.

## 5. R06A — Chọn ảnh

Header: Đóng / “Bài viết mới” / “Tiếp”.

- Preview ảnh đang chọn ở trên; bộ sưu tập “Gần đây”, control “Chọn nhiều” và lưới ảnh ở dưới.
- Ảnh được chọn có số thứ tự album; thứ tự ban đầu là thứ tự người dùng chọn.
- Tiếp disabled khi chưa chọn ảnh; chọn ảnh → Tiếp → R06B.
- “Đăng chỉ với nội dung” mở R06D, không bắt buộc xin quyền ảnh để đăng chữ.
- “Chụp ảnh” dùng khả năng nền tảng; chỉ xin quyền khi người dùng chủ động chọn hành động đó.
- Có trường hợp quyền bị từ chối, quyền giới hạn, không có ảnh và lỗi đọc file. Cho quay lại hoặc đăng chữ.
- Giới hạn album phải có cấu hình thống nhất frontend/backend. Mẫu đang gợi ý tối đa 10 ảnh; xác minh contract trước khi khóa giới hạn thực tế.
- Chỉ thiết kế ảnh trong checkpoint này; không tự mở rộng sang reels/video/livestream.
- Không để chọn lại ảnh làm mất caption hay attachment đã có khi quay lại từ composer.

## 6. R06B — Chỉnh ảnh

Header: Back / “Chỉnh ảnh” / “Tiếp”.

- Preview lớn, crop Gốc/Vuông/Dọc, xoay, điều chỉnh độ sáng và tương phản.
- Album có thumbnail strip để chọn ảnh đang chỉnh; chỉnh theo từng mediaId.
- Thay đổi không phá file gốc; giữ ảnh gốc và edit state riêng.
- Đặt lại chỉ reset ảnh đang chỉnh; không xóa toàn album.
- Back giữ selections và edit state. Tiếp mở R06D.
- Các công cụ crop/slider phải có kết quả thật trong preview và ảnh xuất; nếu chỉ làm preview UI, báo rõ chưa hỗ trợ xử lý ảnh, không làm control giả.
- Xử lý EXIF orientation, tỷ lệ ảnh, dung lượng, vòng đời tài nguyên và giới hạn upload theo hạ tầng đang có.

## 7. R06C — Sắp xếp album

Header: Back / “Sắp xếp ảnh” / “Xong”.

- Đổi vị trí bằng drag; hỗ trợ thao tác thay thế có nhãn nếu nền tảng/accessibility cần.
- Xóa ảnh, thêm ảnh, cập nhật thứ tự và preview nhất quán.
- Ảnh đầu tiên là ảnh bìa album; không hardcode thumbnail khác làm bìa.
- Mỗi ảnh có ID ổn định để edit không bị gắn nhầm sau reorder.
- Xong áp dụng và quay về bước gọi. Quy định rõ Back hủy hay giữ thay đổi và dùng nhất quán; đề xuất Back hủy chỉnh thứ tự chưa xác nhận.
- Xóa ảnh cuối: nếu còn caption/attachment thì có thể tiếp tục bài không ảnh; nếu bài trống thì trở lại chọn ảnh, Chia sẻ vẫn disabled.
- Đổi thứ tự/xóa ảnh không được xóa caption hoặc attachment.

## 8. R06D — Viết nội dung và chia sẻ

Header: Back / “Bài viết mới” / “Chia sẻ”. Chỉ một hành động publish, không lặp CTA Share ở đầu hoặc đáy khác.

- Avatar/tên tài khoản hiện tại; caption; thumbnail ảnh hoặc album; tap preview mở quản lý ảnh.
- Bài chỉ có chữ không xuất hiện khung ảnh trống.
- Các hàng nhẹ: Ai có thể xem? / Chủ đề / Đính kèm hoạt động / Cài đặt bình luận.
- Chủ đề là tùy chọn với bài thông thường.
- Một attachment hoạt động tại một thời điểm trong phạm vi này: buổi tập hoặc bữa ăn. Cho chỉnh, thay hoặc gỡ; thay cần rõ ràng với người dùng.
- Preview gọn, không đưa toàn dashboard/chi tiết workout vào composer.
- Bản mẫu chính dùng ảnh bữa ăn + chủ đề Bữa ăn; workout-sharing là biến thể riêng. Không tự gắn workout không liên quan.
- Xóa dòng tự động lưu bài vào nhật ký/hành trình thể thao: đăng bài chỉ tạo nội dung Community.
- Nội dung hợp lệ khi có text không chỉ khoảng trắng, media hợp lệ hoặc attachment hợp lệ. Lọc chủ đề/quyền xem đơn thuần không tạo thành bài hợp lệ.
- Chia sẻ disabled khi trống, media còn lỗi/chưa sẵn sàng hoặc đang submit.
- Không cho bấm lặp tạo bài trùng. Khi thành công, clear draft và hiển thị bài mới đúng dữ liệu trên feed.
- Nếu đối tượng xem là Người theo dõi, publish phải được backend kiểm soát; không chỉ ẩn UI phía client.

## 9. R07 — Chọn dữ liệu đính kèm

Header: Back / “Đính kèm hoạt động”. Hai tab Buổi tập / Bữa ăn.

- Chỉ lấy buổi tập hoàn thành hoặc bữa ăn thuộc tài khoản hiện tại.
- Nhóm theo ngày, chọn một mục, hiện preview và phần “Thông tin hiển thị” có thể mở rộng.
- Buổi tập: tên/ngày làm định danh; thời lượng và danh sách bài tùy chọn; sets/reps/weights tắt mặc định.
- Bữa ăn: tên/ảnh theo dữ liệu có sẵn; danh sách món tùy chọn; calories/macros tắt mặc định.
- Mẫu cuối có thể khác trạng thái mặc định của switch: triển khai theo chính sách tối thiểu dữ liệu ở trên, giữ layout đã chốt.
- Field bắt buộc hiển thị bằng text, không dùng switch không thể tắt.
- CTA Đính kèm disabled khi chưa chọn; bấm chỉ cập nhật draft R06D/R08 đã mở picker.
- Back không đính kèm mới, giữ attachment trước đó.
- Không tự tính hoặc thêm calories tiêu hao, RPE hay metrics không có dữ liệu thật.
- Không tự chia sẻ cân nặng, số đo, nhật ký đầy đủ hoặc thông tin sức khỏe riêng tư.
- Empty/error state phải rõ. Không có dữ liệu vẫn được tiếp tục bài text/ảnh.

## 10. R08 — Đặt câu hỏi

- Header duy nhất: Đóng / “Đặt câu hỏi” / “Đăng”. Bỏ hàng trạng thái và nút Đăng bị lặp trong export nếu có.
- Người đăng, quyền xem, câu hỏi bắt buộc, mô tả tùy chọn, chủ đề và ảnh/attachment hỗ trợ.
- Chọn ít nhất một chủ đề cho hỏi đáp theo thiết kế; giới hạn ký tự/số chủ đề cần thống nhất trong contract, không dựa tùy tiện vào số mẫu Stitch.
- Validator trim khoảng trắng; hiển thị lỗi tại trường, giữ nội dung khi lỗi submit.
- Ảnh và attachment dùng chung draft/media components với composer, không tạo luồng upload khác.
- R07 trả kết quả về R08 nếu picker được mở từ câu hỏi, không ép quay R06D.
- Không gắn nhãn chuyên gia hoặc hứa thời gian được trả lời.
- Publish thành công → bài câu hỏi trong feed Hỏi đáp; có thể dùng renderer câu hỏi trong R05 cho bản cơ bản. Màn hỏi đáp chuyên sâu chưa có trong bộ này.

## 11. R09 — Hồ sơ cộng đồng

- Đây là hồ sơ công khai trong Community, không phải hồ sơ sức khỏe của Profile chính.
- Tên, username, avatar, bio, số bài/follower/following lấy từ dữ liệu.
- Hồ sơ thành viên khác: Theo dõi/Đang theo dõi và Chia sẻ hồ sơ; menu báo cáo/chặn theo khả năng đã triển khai.
- Hồ sơ chính mình: Chỉnh sửa hồ sơ, lối vào Đã lưu/Bản nháp riêng tư.
- Không hiển thị nút theo dõi chính mình.
- Bài viết và Hỏi đáp; chế độ grid/list; tile phù hợp cho bài chữ/attachment không ảnh.
- Bấm bài → đúng postId tại R05; avatar/username không hardcode thành Linh Nguyễn.
- Hồ sơ private/unavailable/blocked cần state phù hợp; không tải bài bị hạn chế chỉ vì biết ID.
- Không suy ra user đã được xác minh từ badge mẫu; không tạo trạng thái online giả.
- Chỉnh sửa hồ sơ, saved và bản nháp là điểm đến chưa có màn đầy đủ; dùng màn có sẵn nếu phù hợp, hoặc ghi backlog, không tự coi đã hoàn tất.

## 12. R10 — Người theo dõi / Đang theo dõi

- Back, tên người được xem và hai tab tương ứng.
- Mở từ số thống kê R09 phải chọn đúng tab và userId.
- Search lọc/tìm theo contract; có phân trang, empty/error/retry.
- Mỗi hàng có avatar, tên, username/bio và trạng thái quan hệ với tài khoản hiện tại.
- Nút Theo dõi/Đang theo dõi không được suy ra chỉ từ tab. Đây là quan hệ của viewer với user tại hàng đó.
- Follow/unfollow cập nhật nhất quán ở R09, R10, gợi ý R04 và feed Đang theo dõi; rollback nếu request lỗi.
- Không follow chính mình; bấm tên/avatar mở hồ sơ đúng người.
- Không hiển thị “7 vận động viên”, “Mô phỏng rỗng” hay nút developer từ bản export.

## 13. Bottom sheet và thành phần phụ phải có

| Thành phần | Hành vi chính |
| --- | --- |
| Tạo nội dung | Chọn Bài viết / Buổi tập / Bữa ăn / Câu hỏi |
| Đối tượng xem | Công khai / Người theo dõi; giải thích ngắn và giữ lựa chọn |
| Chủ đề | Chọn/bỏ chọn; xác nhận; quy tắc khác nhau cho bài thường và hỏi đáp |
| Bình luận | Cho phép bình luận bật/tắt |
| Lưu bản nháp | Lưu nháp / Bỏ thay đổi / Tiếp tục viết |
| Xác nhận bỏ theo dõi/chặn | Nêu đúng người, đúng tác động |
| Upload lỗi | Thử lại / Gỡ ảnh; giữ draft |

Không tính các sheet này là màn R mới. Báo cáo/chặn không được là nút giả; nếu backend chưa có, ghi rõ phần chưa hỗ trợ và giới hạn bản demo.

## 14. Draft, upload và chống đăng trùng

- Một draft state xuyên suốt media, edit, album, caption, attachment, topic, audience và comment setting.
- Có draftId ổn định; chuyển bước không tạo draft/bài mới ngoài ý muốn.
- Lưu nháp chỉ lưu riêng tư, không publish. Nếu UI ghi “Tự động lưu”, phải có cơ chế thật và phạm vi lưu được định nghĩa; nếu chưa có thì bỏ nhãn đó.
- Draft/cache tách theo userId; logout/chuyển tài khoản không lộ dữ liệu tài khoản trước.
- Upload chỉ khi cần theo pipeline đã chọn; có progress/cancel/retry, xử lý file quá lớn/không hỗ trợ và file tạm không còn tồn tại.
- Sau timeout publish, trạng thái có thể chưa rõ: kiểm tra kết quả bằng định danh request/idempotency trước khi gửi lại. Không tạo duplicate do bấm thử lại.
- UI hỗ trợ retry là cần thiết; chống trùng thực sự phải có contract/backend phù hợp khi triển khai live.
- Chỉ báo đã đăng khi có kết quả xác nhận. Thất bại giữ draft; thành công đồng bộ feed, profile và số bài.
- Nội dung followers-only và attachment phải được bảo vệ tại API/media access, không chỉ tại màn hình.

## 15. Ranh giới với Workout/Nutrition và kiến trúc

- Dùng dữ liệu và ID đang có, không tạo catalog/session/bữa ăn thứ hai trong Community.
- Post attachment là bản chia sẻ có trường dữ liệu được chọn, không mở quyền truy cập trực tiếp toàn session/log riêng tư.
- Phải quyết định contract snapshot: dữ liệu đã chia sẻ thay đổi ra sao khi nguồn sửa/xóa. Chưa quyết định thì ghi rõ trong backlog, không âm thầm đọc nguồn riêng tư mỗi lần render.
- Đọc, đính kèm, đăng hay xóa bài không tự ghi/xóa Workout hoặc Nutrition.
- Khảo sát API thực tế. Phần chưa có dùng typed interface + Fake Repository, DI/state management hiện có; không nhét mock vào Widget.
- Tách logic media edit/upload, draft, publish, follow khỏi UI. Reuse post/attachment renderer giữa feed/detail/composer khi phù hợp.
- Không mặc định dự án chưa có backend; không tự thay kiến trúc/auth đang hoạt động.
- Rà AGENTS.md, workspace, git status, allowed scope và WIP trước sửa. Tài liệu này không thay thế quy tắc repository.

## 16. Các phần ngoài phạm vi

Không tự thêm reels, story, livestream, chat riêng, tagging nâng cao, vị trí, âm nhạc, mua hàng hoặc AI chẩn đoán.

Chỉnh sửa hồ sơ, thông báo, danh sách saved, quản lý draft đầy đủ, hỏi đáp chuyên sâu và moderation cần checkpoint tiếp theo. Các sheet được mô tả vẫn phải được xử lý trong luồng tương ứng. Bộ màn thiết kế không đồng nghĩa Community đã sẵn sàng phát hành.

## 17. Checklist nghiệm thu

- [ ] Đúng 8 màn, R06 cũ/R07 cũ không được dùng nhầm.
- [ ] Một header mỗi màn, màu xanh dịu, chữ/nút đủ tương phản; không có công cụ demo.
- [ ] Ảnh đơn/album/text-only/workout-sharing/meal-sharing đi đúng luồng.
- [ ] R06C giữ đúng ảnh và edit sau reorder/xóa/thêm.
- [ ] Back giữa các bước giữ nội dung; đóng có lựa chọn draft đúng.
- [ ] Chọn R07 quay về đúng R06D hoặc R08 đã gọi.
- [ ] Không tự công khai dữ liệu hoặc ghi nhật ký khi đính kèm/đăng.
- [ ] Lỗi upload/publish không mất draft; double tap/retry không sinh bài trùng.
- [ ] Phân quyền và audience áp dụng thật khi dùng backend live.
- [ ] R09/R10 mở đúng user; follow state và counts đồng bộ phù hợp.
- [ ] Màn hẹp, chữ 200%, keyboard và safe area không che hành động.
- [ ] Logout/chuyển user không lộ draft/media hoặc dữ liệu riêng tư cũ.

## 18. Anti cần bàn giao

1. Mapping 8 frame → file Flutter/route thực tế, phiên bản export đã dùng.
2. File đã sửa, component dùng chung và điểm nối CP-01/Workout/Nutrition.
3. Navigation map, state/draft contract và quy tắc upload/publish.
4. Phần live, fake, chỉ UI và chưa triển khai được phân biệt rõ.
5. Kết quả analyze/test phù hợp và ảnh app thật cho các luồng chính.
6. Backlog màn/API còn thiếu và khác biệt quan trọng so với mẫu.

Không báo PASS toàn tính năng chỉ từ build thành công hoặc từ ảnh Stitch. Nghiệm thu phải dựa trên hành vi và dữ liệu của phạm vi thực tế đã triển khai.
