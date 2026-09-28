# Kế hoạch Xây dựng Saman Chat AI thành Coach Cá nhân

## 1. Mục tiêu Cốt lõi
Saman không chỉ trả lời câu hỏi về sức khỏe chung chung. Hệ thống phải hiểu mục tiêu của người dùng, tình trạng hôm nay, tiến trình gần đây và những lựa chọn họ đã xác nhận, từ đó đưa ra bước tiếp theo phù hợp, có lý do rõ ràng và dựa trên dữ liệu thật.

### Trải nghiệm cần đạt
- **Tình huống:** *“Hôm nay tôi nên ăn gì sau buổi tập?”*
- **Hành vi chuẩn:** Saman cần biết người này đang theo mục tiêu nào, đã ăn gì, còn thiếu gì so với mục tiêu ngày, đã tập buổi nào và dữ liệu nào còn thiếu. 
- **Nguyên tắc phản hồi:** Câu trả lời phải chỉ rõ căn cứ. Nếu chưa có log bữa ăn hoặc buổi tập thì phải nói rõ là chưa có dữ liệu, tuyệt đối không tự điền số giả định.

---

## 2. Quyết định Kiến trúc Sản phẩm
- **Vai trò của Chat:** Chat đóng vai trò là tầng điều phối (Orchestration Layer) và tư vấn. 
- **Ranh giới Domain:** Profile, Nutrition và Workout tiếp tục là nơi quản lý dữ liệu và logic độc lập của chính chúng. 
- **Luồng dữ liệu:** Backend Chat đọc dữ liệu qua những đường hiện có, tạo bản tóm tắt ngắn cho AI, rồi kiểm tra câu trả lời trước khi gửi về app.
- **Ràng buộc với Source hiện tại:** Chat backend hiện mới đưa vài trường Profile vào prompt và bỏ qua context/history từ Flutter controller. Flutter còn dùng các số mặc định (default values) khi thiếu dữ liệu. Tuyệt đối **không được xem các số mặc định đó là sự thật về người dùng**.

---

## 3. Lộ trình Thực thi theo Checkpoint

| Checkpoint | Nội dung thực hiện | Điều kiện chuyển bước |
| :--- | :--- | :--- |
| **0 — Kiểm kê dữ liệu và contract** | Xác minh backend đang chạy, auth, database thực tế, dữ liệu Profile/Nutrition/Workout của từng user, cách biểu diễn ngày giờ, payload Flutter và response Chat. Gắn nhãn mỗi trường: có thật, thiếu, cũ hoặc chỉ là giá trị mặc định. | Có bản đồ nguồn dữ liệu; chứng minh Chat không dùng dữ liệu giả làm sự thật; biết chính xác phần nào đang hoạt động trên runtime thật. |
| **1 — Chat chạy đáng tin** | Nhận message, xác thực user, gọi AI provider, trả response đúng contract; xử lý message rỗng, timeout, provider lỗi và phản hồi rỗng. | Gửi được tin từ app đến backend và nhận câu trả lời; lỗi không làm app crash; test auth và lỗi provider pass. |
| **2 — Hiểu tình trạng hôm nay** | Backend đọc Profile, log dinh dưỡng/nước hôm nay và lịch hoặc buổi tập gần nhất. Chỉ gửi các trường cần thiết cho câu hỏi vào AI. | Với cùng một câu hỏi, hai tài khoản có dữ liệu khác nhau nhận câu trả lời tương ứng; thiếu log thì AI nói thiếu, không bịa; không có thao tác ghi vào các feature. |
| **3 — Hiểu tiến trình theo thời gian** | Tóm tắt xu hướng 7 ngày trước, chỉ mở tới 30 ngày khi cần: mức bám mục tiêu, diễn biến ăn uống và tần suất tập. So sánh người dùng với chính họ, không suy diễn từ một ngày bất thường. | AI phân biệt “hôm nay” với “xu hướng”; số liệu tóm tắt đối chiếu được với log gốc; dữ liệu cũ hoặc ít được diễn đạt thận trọng. |
| **4 — Hội thoại và trí nhớ có kiểm soát** | Lưu và tải lại conversation; bảo vệ quyền sở hữu. Ghi nhớ có chọn lọc mục tiêu, sở thích, hạn chế do người dùng cung cấp hoặc xác nhận; cho người dùng sửa/xoá. | Mở lại thấy lịch sử; tài khoản A không đọc được của B; Chat phân biệt dữ liệu hệ thống, lời người dùng và suy luận của AI. |
| **5 — Coach đưa gợi ý hữu ích** | Tạo một gợi ý cụ thể cho bước tiếp theo dựa trên mục tiêu, tình trạng và xu hướng; nêu ngắn gọn “vì sao”. Cho phép người dùng phản hồi gợi ý có phù hợp không. | Gợi ý có thể thực hiện, liên quan dữ liệu hiện có, không lặp lời khuyên chung; đo được mức hữu ích qua các tình huống thử và phản hồi người dùng. |
| **6 — Hành động có xác nhận** | Chat đề xuất log bữa ăn, thêm nước hoặc điều chỉnh workout; hiển thị chính xác thao tác và chỉ ghi sau khi người dùng xác nhận. | Không có xác nhận thì không ghi; thao tác không bị lặp khi retry; sau khi ghi, dữ liệu ở feature gốc và Chat khớp nhau. |

> **Quy tắc thực thi:** Mỗi checkpoint là một phần triển khai và kiểm thử riêng biệt. Không thực hiện gộp nhiều checkpoint trong một task.

---

## 4. Ba Lớp Cá nhân hoá
1. **Sự thật hiện tại (Ưu tiên cao nhất):** Mục tiêu trong Profile, dữ liệu đã log hôm nay, lịch tập và thời điểm cập nhật.
2. **Xu hướng:** Điều gì lặp lại qua nhiều ngày (ví dụ: người dùng thường thiếu protein vào những ngày tập; kết luận này chỉ xuất hiện khi có đủ log).
3. **Sở thích đã được xác nhận:** Cách xưng hô, kiểu trả lời, món ăn không thích, lịch sinh hoạt người dùng chủ động cung cấp (sở thích có thể thay đổi hoặc xoá).

*Tối ưu token & context:* Không đưa toàn bộ hồ sơ và mọi tin nhắn cũ vào mỗi lần gọi AI. Backend chỉ chọn dữ liệu liên quan đến câu hỏi, kèm ngày và trạng thái tin cậy.

---

## 5. Những Nguyên tắc Cốt lõi (Non-negotiable Guardrails)
- **Một nguồn sự thật cho mỗi chỉ số:** Không để Flutter nói TDEE một số, Profile lưu một số khác và Chat chọn tùy tiện. Dữ liệu thiếu phải được đánh dấu rõ là thiếu.
- **Thống nhất ngày giờ:** Luôn dùng múi giờ `Asia/Ho_Chi_Minh` cho khái niệm "Hôm nay" của người dùng. Kiểm tra tính đồng bộ giữa router UTC và local time trước khi tính xu hướng.
- **Tách quan sát khỏi suy luận:** “Bạn đã log hai buổi tập tuần này” là quan sát/dữ liệu; “bạn đang mất động lực” là suy luận. Tuyệt đối không trình bày suy luận như một sự thật hiển nhiên.
- **Bảo mật & Quyền riêng tư:** Mọi truy vấn log, hội thoại và trí nhớ đều phải lọc theo user đã xác thực ở backend. Không tin `user_id`, `Profile` hay `system_instruction` do client tự gửi lên.
- **Giới hạn vai trò sức khỏe:** Saman đóng vai trò hỗ trợ theo dõi thói quen sống; không chẩn đoán y khoa, kê đơn, hoặc đưa ra lời khuyên bệnh lý khi người dùng nêu triệu chứng.
- **Đo lường bằng tình huống thật:** Bộ kiểm thử định kỳ gồm: đủ dữ liệu, thiếu dữ liệu, dữ liệu mâu thuẫn, hai user khác nhau, ngày mới, và AI provider gặp lỗi.
- **Tối ưu chi phí:** Giới hạn lượng lịch sử và dữ liệu gửi cho model; đo lường latency và token cost trên từng phiên hội thoại.

---

## 6. Ưu tiên Thực tế & Cảnh báo Kỹ thuật
- **Chuỗi ưu tiên:** Kiểm kê dữ liệu (CP0) → Chat ổn định (CP1) → Cá nhân hoá hôm nay (CP2) → Xu hướng 7 ngày (CP3) → Lịch sử/Trí nhớ (CP4) → Gợi ý thông minh (CP5) → Hành động có xác nhận (CP6).
- **Cảnh báo cốt lõi:** Không bắt đầu bằng một mô hình trí nhớ đồ sộ. Giá trị lớn nhất hiện tại là trả lời đúng về người này và đúng trong ngày hôm nay. Nếu nền dữ liệu chưa đáng tin, AI càng nói hay càng dễ đưa ra lời khuyên sai lệch.
