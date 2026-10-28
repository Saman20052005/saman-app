# Workout Plans — Design Handover

## 1. Thiết kế đã chốt
- my-plans.html + my-plans.png: màn My Plans.
- create-plan.html + create-plan.png: màn Create Plan.
- Chỉ triển khai hai màn trên. Nếu tên file thực tế khác, đối chiếu nội dung để xác định đúng mẫu.
- PNG là chuẩn đối chiếu giao diện; HTML tham chiếu màu, font, khoảng cách, kích thước và ảnh nền.
- Nếu HTML và PNG khác nhau đáng kể, báo lại trước khi tự chỉnh.

## 2. Phạm vi
- Áp dụng thiết kế đã chốt vào hai màn Flutter hiện có.
- Đồng bộ nền tối, typography, ảnh nền, card và button theo mẫu.
- Giữ nguyên logic, dữ liệu, điều hướng và các chức năng hiện có.
- Các trạng thái chưa có mẫu tiếp tục dùng chung style đã chốt, không cần tạo thêm màn độc lập.
- Không sửa màn Workout chính hoặc tính năng Workout-CV.

## 3. Lưu ý triển khai
- Tận dụng theme và component có sẵn; giới hạn thay đổi trong phạm vi hai màn.
- Đưa ảnh nền vào assets của app, không phụ thuộc link ảnh bên ngoài. Nếu thiếu ảnh gốc, báo rõ.
- Giữ lớp phủ tối để chữ và nút dễ đọc; giữ cách crop ảnh theo mẫu.
- Button bo mềm theo mẫu; tránh viền dày, viền kép hoặc hiệu ứng phát sáng.
- Nút chính nền trắng nhạt, chữ tối; nút phụ nền tối với viền nhẹ hoặc không viền theo mẫu.
- Không đưa dữ liệu giả hoặc logic xử lý vào Widget.
- Giữ nguyên Service/Repository và cơ chế lưu Plan hiện có; không tuyên bố đã lưu bền vững hoặc đồng bộ nếu chưa hỗ trợ.
- Đảm bảo bàn phím không che input và nút lưu; nội dung cuộn được trên màn nhỏ.
- Nút lưu thể hiện rõ trạng thái disabled/loading; ngăn bấm lặp khi đang lưu.
- Không dựng lại toàn bộ màn thành ảnh hoặc nhúng HTML thay cho giao diện Flutter.

## 4. Kiểm tra hoàn thành
1. Workout → My Plans → Create Plan hoạt động bình thường.
2. Nhập tên, thêm bài tập và lưu Plan vẫn hoạt động theo logic hiện có.
3. Quay lại/đóng màn đúng luồng; không mất hành vi bảo vệ dữ liệu đang sửa nếu đã có.
4. Không tràn chữ, vỡ layout hoặc bị che bởi bàn phím/safe area.
5. Chụp lại hai màn thực tế để đối chiếu mẫu đã chốt; báo ngắn gọn các file sửa và kết quả kiểm tra.
