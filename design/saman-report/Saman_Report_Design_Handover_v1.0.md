# Saman — Ghi chú bàn giao redesign Report

- **Phiên bản:** 1.0 — 27/10/2026
- **Trạng thái:** Đã chốt hướng thiết kế; triển khai lại bằng Flutter trong ứng dụng hiện có.
- **Phạm vi:** Màn Report và ba tab nội bộ Overview / Nutrition / Activity.

## 1. Tài liệu tham chiếu và thứ tự ưu tiên

Đặt file ghi chú này cạnh các tài liệu thiết kế Report:

| File | Vai trò |
| --- | --- |
| `screen(1).png` | Bản thiết kế người dùng đã chốt; tham chiếu bố cục, phong cách, thứ tự nội dung. |
| `code(1).html` | Tham khảo chi tiết màu, khoảng cách, card và nội dung của cả ba tab. Không phải mã production. |
| `saman_product_requirements_document_prd.md` | Bối cảnh sản phẩm và nguyên tắc biểu đồ; không phải yêu cầu triển khai toàn bộ sản phẩm trong lần này. |
| `home-screen.png` / `home-screen.html` nếu có | Kiểm tra tính đồng bộ với Home. |

**Quyết định triển khai:** Giữ thiết kế Report đã chốt; sửa lỗi hiển thị và sai lệch dữ liệu trong bản xuất mẫu. Giữ logic nghiệp vụ, nguồn dữ liệu và điều hướng đang hoạt động trong app. Nếu PRD hoặc HTML mâu thuẫn với phạm vi trên, áp dụng ghi chú này cho lần redesign này và ghi rõ khác biệt trong báo cáo.

Không lấy bản preview trước đó trong hội thoại làm mẫu thay thế cho `screen(1).png` và `code(1).html` vừa được chốt.

## 2. Phạm vi cần thực hiện

### Overview

Giữ thứ tự chính:

1. Header Report, nút quay lại và action phụ theo khả năng hiện có.
2. Điều hướng tuần: tuần trước / khoảng ngày / tuần sau và chọn ngày.
3. Tab Overview / Nutrition / Activity; Overview mở mặc định.
4. Khối “Your week, at a glance”: số ngày ghi nhận, protein trung bình và số ngày hoạt động.
5. Calories Consumed: số trung bình lớn, mục tiêu và biểu đồ cột trắng/xám.
6. Protein Intake: đường emerald, các điểm dữ liệu và vùng tô nhẹ.
7. Calories Burned: cột amber, mục tiêu và phân biệt ngày nghỉ với ngày chưa ghi nhận.
8. Weekly takeaway ngắn, có căn cứ dữ liệu.
9. “View daily breakdown”.

### Nutrition

- Tham khảo `pane-nutrition` trong HTML: tổng quan protein/carbs/fat, calo nạp, protein và nước.
- Dùng cùng dữ liệu, cùng khoảng thời gian và cùng component với Overview.
- Nội dung phân tích thời điểm ăn chỉ hiển thị nếu nguồn dữ liệu hiện có hỗ trợ; không sao chép đoạn nhận định mẫu về post-workout, dinner hoặc phục hồi cơ.

### Activity

- Tham khảo `pane-activity` trong HTML: tổng calo đốt, số buổi tập, biểu đồ theo ngày và danh sách buổi tập đã hoàn thành.
- Chỉ hiển thị RPE, kế hoạch tập, tỷ lệ hoàn thành khi có dữ liệu tương ứng. Thiếu thì dùng “—” hoặc ẩn phần phụ đó có chủ đích.
- Danh sách và số tổng hợp phải dùng cùng bộ lọc tuần, cùng định nghĩa trạng thái hoàn thành.

## 3. Style cần giữ

| Thành phần | Giá trị tham chiếu |
| --- | --- |
| Nền màn hình | `#0C0D0E` |
| Card | `#16171A` |
| Surface nâng | `#1C1D22` / `#212329` |
| Viền mảnh | `#26282F` |
| Chữ chính | `#F3F4F6` |
| Chữ phụ | `#A1A1AA` / `#94979E`; bảo đảm đọc được trên nền tối |
| Protein | `#10B981` |
| Calo đốt / carbs | `#F59E0B`, phân biệt bằng nhãn và đơn vị |
| Fat | `#A855F7` |
| Tab đang chọn | Nền đặc `#F9FAFB`, chữ `#0C0D0E` |
| Bo góc | Khoảng 12px cho nút, 16–20px cho card |

- Giữ phong cách tối, gọn, icon nét mảnh và khoảng cách như mẫu.
- Dùng typography/token hiện có nếu tương đương; không thay font toàn ứng dụng chỉ để giống HTML.
- Không thêm ảnh nền, vòng điểm sức khỏe, gradient đậm hay viền dày vào Report.
- Kích thước bản mẫu chỉ là tham chiếu; layout phải co giãn theo thiết bị và cỡ chữ hệ thống.

## 4. Những lỗi của mẫu cần sửa khi triển khai

**Người dùng chốt hướng thiết kế, không yêu cầu tái tạo các lỗi sau.**

### 4.1. Cột biểu đồ bị mất

Ảnh xuất hiện gần như chỉ có lưới và nhãn ở hai biểu đồ cột. Trong HTML, chiều cao cột dùng phần trăm trong các wrapper không có chiều cao xác định. Không sao chép cách dựng này sang Flutter.

- Vẽ cột từ giá trị thật trên một vùng plot có kích thước xác định.
- Cột phải hiện rõ, thẳng baseline và khớp ngày trên trục X.
- Không dùng chiều cao cột hoặc tọa độ vẽ cố định để mô phỏng dữ liệu.

### 4.2. Chữ xuống dòng, đè nhau

Ảnh có đơn vị `g / day`, nhãn Calories Consumed, khoảng ngày và footer bị xuống dòng chật hoặc chạm vùng khác.

- Cho phép header/footer reflow hợp lý; ưu tiên số liệu và đơn vị dễ đọc.
- Tách hàng nếu cần thay vì thu nhỏ chữ quá mức.
- Không dùng chiều cao card cố định làm cắt chữ; không ép text scale về 1.
- Tăng hit area nút nhỏ bằng vùng chạm, không cần làm icon quá lớn.

### 4.3. Trục và đường xu hướng

- Khoảng cách tick phải tỷ lệ đúng với giá trị: 3.000 → 2.500 không thể chiếm cùng khoảng cách với 2.000 → 1.000.
- Dữ liệu mẫu có ngày đốt 610 kcal nhưng trục minh họa chỉ tới 600. Domain phải chứa cả điểm lớn nhất và mục tiêu, có khoảng thở; không cắt điểm hoặc kẹp về 600.
- Đường protein dùng đoạn thẳng hoặc nội suy giữ hình dạng, không tạo đỉnh/đáy giả giữa hai điểm để trang trí.

### 4.4. Số liệu minh họa chưa nhất quán

- Dãy calo đốt trong HTML: `520, 610, 0, 480, 550, 380, missing` có tổng **2.540 kcal**, trung bình trên 6 ngày ghi nhận khoảng **423 kcal/ngày**. Mẫu lại ghi 2.610 và 435. Không giữ các số tổng hợp này trong production.
- Nếu định nghĩa active day là ngày có calo hoạt động > 0, dãy trên có **5 ngày**, không phải 4. Nếu app dùng định nghĩa khác, giữ định nghĩa nghiệp vụ hiện có và ghi rõ.
- RPE 8.2, “100% plan adherence”, “high consistency” và takeaway chỉ là nội dung mẫu, cần tính lại hoặc ẩn khi thiếu căn cứ.
- Khi chọn ngày khác, ngày, số liệu, highlight và phần chênh lệch với mục tiêu phải đổi cùng nhau. Script mẫu chỉ đổi nhãn/ngày calo và còn giữ cứng `+80 over goal`.

### 4.5. Không sao chép thanh điều hướng của mẫu

- HTML thay nhãn Nutrition thành Report ở thanh đáy; PRD lại mô tả Report ở vị trí khác. Đây chưa phải quyết định thay đổi điều hướng toàn app.
- **Giữ app shell, các tab Nutrition/Profile và đường vào Report đang có trong source thực tế.** Không thêm thanh đáy thứ hai hoặc tạo route trùng.
- Không vẽ giả status bar 9:41, sóng, pin hoặc home indicator trong Flutter; dùng SafeArea và hệ thống.

## 5. Quy tắc dữ liệu bắt buộc

1. **Không hardcode số mẫu:** 2.500 kcal, 160 g, 400 kcal, ngày tháng và tên buổi tập không phải thay đổi mục tiêu thật của người dùng. Đọc từ nguồn hiện có.
2. **Thiếu dữ liệu khác số 0:** missing/null hiện “—” hoặc “Chưa ghi nhận”; không tự chuyển thành 0. Chỉ gọi “Ngày nghỉ” khi có trạng thái nghỉ rõ ràng, không suy từ việc thiếu buổi tập hoặc giá trị 0.
3. **Trung bình minh bạch:** với chỉ số trung bình trên ngày ghi nhận, lấy tổng / số ngày có dữ liệu hợp lệ của chính chỉ số đó; số 0 hợp lệ được tính, missing không được tính. Nếu app đang có công thức nghiệp vụ khác, xác minh và ghi rõ trước khi đổi, không âm thầm thay công thức.
4. **Coverage có định nghĩa:** số ngày ghi nhận dinh dưỡng có thể khác hoạt động. Không lấy coverage của meals áp cho mọi biểu đồ; chỉ dùng một badge tổng khi có quy tắc tổng đã xác định.
5. **Biểu đồ trung thực:** cột bắt đầu từ 0; nhãn có đơn vị; mục tiêu nét đứt; đường protein ngắt tại ngày thiếu, kể cả thiếu ở giữa tuần. Không ghép kcal và g lên cùng một trục.
6. **Mục tiêu không có:** dùng “Chưa đặt mục tiêu”; không vẽ đường mục tiêu mặc định. Tránh chia cho 0 khi tính phần trăm.
7. **Thống nhất các tab:** Overview/Nutrition/Activity phải cho cùng giá trị đối với cùng chỉ số, ngày và filter. Không dùng ba bộ mock riêng.
8. **Ngày tháng động:** dùng timezone và quy tắc bắt đầu tuần của app. “This week” chỉ hiện đúng tuần hiện tại; Oct 19–25 không phải tuần hiện tại vào ngày 27/10/2026. Tuần đang diễn ra: ngày tương lai không tính là bỏ ghi nhận.
9. **Takeaway có căn cứ:** lấy từ dữ liệu/logic hiện có; không thêm tích hợp AI mới chỉ để sinh một câu nhận xét. Thiếu dữ liệu thì dùng lời nhắc trung tính, không tự hiện “Needs attention”.
10. **Phạm vi calo đốt:** giữ định nghĩa hiện có (active energy hay ước tính từ buổi tập), nhãn rõ ràng; không cộng hai nguồn gây trùng.

## 6. Logic và tương tác

| Thành phần | Hành vi cần giữ/hoàn thiện trong phạm vi |
| --- | --- |
| Back | Trở lại màn trước theo router hiện có. |
| Ba tab nội bộ | Đổi nội dung, giữ khoảng thời gian; active state rõ ràng. |
| Tuần trước/sau | Đổi khoảng ngày và toàn bộ số liệu; trạng thái disabled thật nếu bị giới hạn. |
| Calendar | Dùng date picker/flow hiện có; chọn ngày cập nhật đúng tuần. |
| Cột/điểm dữ liệu | Chọn ngày bằng chạm; cập nhật highlight, giá trị, đơn vị và chênh lệch nếu có mục tiêu. |
| Daily breakdown | Dùng màn/chi tiết dữ liệu hiện có; nếu chưa có thì sheet đơn giản từ cùng repository, không bịa dữ liệu. |
| Share / Export | Giữ chức năng hiện có nếu đã hỗ trợ; nếu chưa hỗ trợ thì ẩn action hoặc disabled có giải thích. Không để nút bấm im lặng và không tự mở rộng thành dự án export PDF. |
| Retry | Thử tải lại đúng tab/khoảng ngày sau lỗi, không reset filter vô cớ. |

- Loading: phản hồi rõ, skeleton/spinner phù hợp; tránh nhảy layout.
- Empty: bình tĩnh, có giải thích, không giả đường dữ liệu bằng 0.
- Error: thông báo dễ hiểu và retry; không trình bày lỗi tải thành “không có dữ liệu”.
- Ngăn thao tác lặp gây request trùng; phản hồi cũ không được ghi đè kết quả tuần vừa chọn.
- PRD có week/month và nhiều phân tích nâng cao: **giữ nếu source đã hỗ trợ; không tự thêm month, meal timing hoặc RPE analytics mới trong đợt này.**

## 7. Nguyên tắc triển khai trong workspace

- Trước khi sửa, xác định đúng repo/frontend đang được workspace Active dùng, file Report, route, state manager và repository hiện tại. Không giả định tên folder là source đang chạy.
- Kiểm tra git status; bảo toàn thay đổi đang có và tránh sửa các file tính năng khác đang được agent khác xử lý.
- Tái sử dụng API/repository/model/state management hiện có. Không thay backend thật bằng mock để làm giao diện khớp mẫu.
- Nếu cần fixture cho preview/loading/error, đặt riêng qua interface/service; không hardcode data hoặc logic tổng hợp trong Widget.
- Tái sử dụng thư viện chart đang có. Không thêm package lớn hay đổi kiến trúc nếu không cần thiết.
- Không sửa mục tiêu dinh dưỡng, database, API contract, auth, Membership, Workout-CV hay flow ghi log chỉ vì redesign Report.
- Không merge/push, build APK toàn app hoặc triển khai ra ngoài nếu chưa nằm trong yêu cầu triển khai tiếp theo.

## 8. Checklist nghiệm thu gọn

1. **Có dữ liệu:** ba tab đúng mẫu, cột hiện rõ, số trung bình/tổng/mục tiêu khớp; chọn ngày cập nhật đủ thông tin.
2. **Thiếu và 0:** thử ngày nghỉ rõ ràng, ngày 0 hợp lệ, ngày missing giữa tuần và cả tuần trống; không nối đường qua khoảng thiếu, không cảnh báo sai.
3. **Đổi tuần và lỗi tải:** đổi nhanh qua lại, chuyển tab, back, lỗi rồi retry; không nhảy về tuần cũ do phản hồi chậm.
4. **Responsive:** kiểm tra khoảng 320/393/430px và cỡ chữ hệ thống lớn hơn; không overflow, đè chữ, mất đơn vị, footer hoặc nội dung bị app shell che.
5. **Hồi quy:** Nutrition/Profile và đường vào Report vẫn hoạt động; loading/empty/error đúng; không đổi số liệu đã ghi hay mục tiêu tài khoản.

Chạy analyzer và test liên quan phần đã sửa, bổ sung test tính toán chỉ khi thay logic. Chụp bằng chứng các tab và ít nhất một trạng thái thiếu dữ liệu. Không chạy audit toàn repo hoặc nhiều vòng test không liên quan.

## 9. Kết quả bàn giao sau triển khai

- Liệt kê file đã sửa, logic được giữ và khác biệt có chủ đích so với mẫu.
- Ảnh chạy thực tế Overview / Nutrition / Activity và trạng thái empty.
- Kết quả kiểm tra phù hợp, kèm hạn chế còn lại nếu thiếu dữ liệu nguồn.
- Nêu rõ những trường đang ẩn/disabled vì chưa có dữ liệu hoặc chức năng, thay vì báo hoàn tất giả.

**Mục tiêu chốt:** Report nhìn đúng bản thiết kế đã duyệt, biểu đồ hiển thị đúng dữ liệu và hoạt động trong app hiện có; không mở rộng phạm vi sản phẩm.
