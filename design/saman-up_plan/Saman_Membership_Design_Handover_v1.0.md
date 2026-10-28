# Saman Membership Demo — Design Handover
Version: 1.0  
Date: 2026-10-27  
Audience: Product Designer / Flutter Developer  
Scope: Membership UI demo, English first, Vietnamese-ready.

## 1. Mục tiêu và giới hạn
Thiết kế luồng khám phá bốn gói Free / Plus / Pro / Ultra, đồng bộ với Profile và Calm Athleticism. Nội dung trả phí là roadmap; giá là demo.

Tài liệu này tổng hợp quyết định thiết kế trong phiên làm việc, không xác nhận tính năng đã triển khai. Không mở rộng sang Post-Workout, wearable hoặc export diary theo roadmap tổng thể.

Không tích hợp payment, subscription, quota, API hoặc backend thật. Không đổi quyền truy cập Nutrition hay Workout CV hiện có. Không sửa auth/onboarding, database hoặc cơ chế lưu workout.

## 2. Danh sách màn và trạng thái
Bộ UI có 7 màn khi tính riêng ba Plan Details, cùng 2 bottom sheet. Monthly/Yearly và selected-plan là biến thể, không phải màn mới.

| ID | Màn / thành phần | Trạng thái bằng chứng trong phiên |
| --- | --- | --- |
| 01 | Membership Overview | Đã review ảnh và HTML bản đầu; phần đầu Monthly/Yearly sau chỉnh đã được chấp nhận làm tham chiếu. Chưa review đầy đủ các paid card của bản cuối. |
| 02 | Compare All Plans | Đã chốt bố cục và dữ liệu từ ảnh; badge MEMBERSHIP PREVIEW còn ghi chú sửa để chữ nằm trong khung. |
| 03A | Plus Detail | Người dùng báo hoàn thành; chưa review ảnh cuối trong phiên. |
| 03B | Pro Detail | Người dùng báo hoàn thành; chưa review ảnh cuối trong phiên. |
| 03C | Ultra Detail | Người dùng báo hoàn thành; chưa review ảnh cuối trong phiên. |
| 04 | Manage Membership | Đã giao prompt; chưa có ảnh nghiệm thu. |
| 05 | Membership Coming Soon | Đã review ba biến thể. HTML export xác nhận màu nút trắng/chữ tối; ảnh preview vẫn xám, chưa xác minh render thực tế. |
| P01 | Nutrition AI Upgrade | Đã review ảnh làm mẫu cấu trúc sheet. Màu CTA trên ảnh khác token trắng; cần đối chiếu source/bản render khi triển khai. |
| P02 | Workout CV Upgrade | Đã review bản đầu; đã giao prompt đồng bộ Nutrition và bỏ cắt chữ. Chưa nhận ảnh sau chỉnh. |

Không gọi toàn bộ bộ thiết kế là PASS cuối cùng khi các mục còn thiếu bằng chứng chưa được kiểm tra.

## 3. Product contract
| Gói | Quyền lợi |
| --- | --- |
| Free | Nutrition logging; manual workout tracking; existing free food photo analysis model; basic health metrics. |
| Plus — Nutrition AI | Kế thừa Free; planned Gemini food photo analysis; planned monthly AI allowance. |
| Pro — Workout Intelligence | Kế thừa Plus; planned Workout CV AI; movement analysis and rep counting; separate Workout CV allowance. Gói được đề xuất. |
| Ultra — Personalized Intelligence | Kế thừa Pro; planned AI allowance 5× Pro; Advanced Thinking; extended history and personalized memory. |

Không tự đặt số quota, danh sách bài hỗ trợ, độ chính xác, dung lượng bộ nhớ hoặc thời hạn lưu trữ. Chưa rõ hạn mức thì ghi “Limits to be announced” / “To be announced”.

5× áp dụng cho AI allowance; không tự áp dụng cho Workout CV allowance riêng.

## 4. Giá demo — USD
| Gói | Monthly | Yearly — tổng tiền trước | Quy đổi tháng |
| --- | ---: | ---: | ---: |
| Free | $0 | $0 | $0 |
| Plus | $10 / month | $60 / year | $5 / month |
| Pro | $15 / month | $120 / year | $10 / month |
| Ultra | $30 / month | $240 / year | $20 / month |

Yearly: tổng tiền năm là số chính; “Equivalent to $X / month” là thông tin phụ. Giữ nhãn “Demo pricing · Subject to change”. Không thêm giảm giá, gạch giá, countdown, trial hoặc ngày gia hạn.

## 5. Navigation
| Điểm vào / hành động | Đích |
| --- | --- |
| Profile: card giới thiệu Membership | Overview |
| Profile: Manage membership | Manage Membership |
| Manage Membership: Explore Plans | Overview |
| Overview: Compare all plans | Compare All Plans |
| Overview / Compare: Explore Plus / Pro / Ultra | Detail đúng gói |
| Detail: Coming Soon | Coming Soon với selected plan đúng |
| Detail: Back to Membership | Overview |
| Coming Soon: header Back | Detail trước đó |
| Coming Soon: Back to Membership | Overview |
| Nutrition sheet: Explore Plus | Plus Detail |
| Workout sheet: Explore Pro | Pro Detail |
| Back từ Detail mở qua sheet | Trả về Nutrition / Workout gốc |
| Close / secondary action / Back / backdrop tap / swipe-down của sheet | Đóng sheet, giữ nguyên trạng thái màn gốc |

Giữ lựa chọn Monthly/Yearly khi đi giữa Overview, Compare và Detail; khi chưa có lựa chọn, mặc định Monthly.

Không thêm Membership vào bottom navigation chính. Các màn Membership có app bar Back và không có tab bar. Bottom sheet phủ trên màn gốc, không thay đổi cấu trúc navigation toàn app.

**Chú ý source export:** ba HTML Coming Soon đang dùng history.back() cho nút Back to Membership. Đây chỉ là hành vi placeholder của export, không phải contract đúng cho Flutter. Nút đó phải về Overview; không chỉ pop một lần về Detail.

## 6. Design tokens
| Thành phần | Token |
| --- | --- |
| Canvas | #0C0D0E |
| Card / sheet | #16171B |
| Border | #26282F, 1px |
| Icon tile / secondary surface | #212328 |
| Chữ chính | #F3F4F6 |
| Chữ phụ | #94979E |
| Accent | #10B981; link và điểm nhấn Pro tinh tế |
| Primary CTA background | #F9FAFB |
| Primary CTA text | #0C0D0E |
| Primary CTA pressed | #E5E7EB |
| Headings | Space Grotesk |
| Body / interface | Inter |
| Giá / metadata | JetBrains Mono; giá dùng tabular numerals |
| Icon | Material Symbols Outlined |
| Screen gutter / card padding | 16px |
| Card corners | 16px |
| Sheet top corners | 16px |
| Primary CTA corners | 12px |
| Spacing grid | 4px; ưu tiên 8 / 12 / 16 / 24 / 32px |
| Body | 14px / 20px |
| Supporting text | 12px trở lên |
| Compact labels | 11px trở lên |
| Primary CTA | Inter 15px, weight 600; min height 52px |
| Touch target | Min 48 × 48px |
| Device reference | Android 390 × 844 logical pixels |

Không gradient neon, glow hoặc shadow trang trí. Không tạo màu riêng rực rỡ cho từng gói. Pro dùng viền xanh mảnh, badge Recommended và phân cấp CTA.

### CTA và lưu ý ảnh/source
Mẫu CTA chính đã chốt: nền trắng ngà, chữ tối, opacity 100%, không mũi tên trên Coming Soon và hai sheet.

Coming Soon export code(3).html / code(4).html / code(5).html có inline background-color rgb(249,250,251) và color rgb(12,13,14), dù ảnh preview hiển thị nền xám. Không kết luận nguyên nhân là cache khi chưa có bằng chứng.

Yêu cầu “Workout giống Nutrition” ưu tiên cấu trúc, spacing và feature card chung; mẫu sheet trong ảnh đang có CTA tối. Khi triển khai dùng token CTA trắng làm chuẩn và review render hai sheet cạnh nhau để thống nhất.

## 7. Thành phần tái sử dụng
| Component | Vai trò / biến thể |
| --- | --- |
| MembershipAppBar | Title và Back theo ngữ cảnh |
| BillingPeriodSelector | Monthly / Yearly |
| PlanPrice | Monthly hoặc annual total + monthly equivalent |
| PlanStatusBadge | Current / Coming Soon / Recommended / Planned |
| MembershipPlanCard | Free / Plus / Pro / Ultra |
| FeatureRow | Icon, title, description tùy chọn; multiline |
| ComparisonMatrix | Feature + 4 cột gói; section divider và legend |
| PlanDetailTemplate | Dùng chung Plus / Pro / Ultra |
| AllowanceSummary | TBA hoặc 5× Pro theo contract |
| InheritedBenefits | Expand / collapse, phân biệt Free và planned |
| CurrentMembershipCard | Demo current plan: Free |
| MembershipFAQ | Expand / collapse, height tự nhiên |
| ComingSoonTemplate | Selected plan: Plus / Pro / Ultra |
| UpgradeBottomSheet | Nutrition / Workout; cùng cấu trúc |
| PrimaryMembershipButton | Trắng ngà, chữ tối |
| MembershipNotice | Demo / roadmap notice |

Các tên component là gợi ý bàn giao; tái sử dụng thành phần phù hợp đang có trong app. Không yêu cầu refactor hoặc tạo lớp kiến trúc mới.

## 8. Trạng thái và tương tác
- Demo account luôn Free; khám phá gói không đổi trạng thái tài khoản.
- Current Plan là thông tin, không tạo nút giả có thể mua Free.
- Coming Soon trong Detail là hành động điều hướng được bật, không phải nút disabled.
- Planned benefit dùng schedule icon; check chỉ cho Free inclusions trong contract demo, kể cả phần được kế thừa ở gói cao.
- Dấu dash trong bảng nghĩa là không thuộc tier, khác với tính năng planned.
- FAQ và inherited benefits mở rộng phải đẩy nội dung bên dưới, không che hoặc cắt chữ.
- Không cần tự tạo network loading/error/quota-exceeded state khi demo không gọi mạng.
- Không tự hiển thị sheet khi đang tập hoặc camera đang phân tích. Chỉ mở từ thao tác khám phá chủ động.
- Dismiss sheet giữ form, set, bộ đếm, camera và trạng thái màn gốc.
- Không giả lập dữ liệu scan món ăn, góc khớp, điểm form hoặc rep count trong preview quảng bá.

## 9. Contract riêng cho bottom sheets
Nutrition:
- Badge: PLUS · COMING SOON.
- Title: Explore Nutrition AI.
- Gemini food photo analysis; Monthly AI allowance.
- CTA: Explore Plus.
- Secondary: Continue with Free.

Workout:
- Badge: PRO · COMING SOON.
- Title: Explore Workout Intelligence.
- Workout CV AI; Movement analysis and rep counting; Separate Workout CV allowance.
- CTA: Explore Pro.
- Secondary: Back to Workout.

Dùng cùng drag handle, Close, icon tile, surface, button và spacing.
Trong feature card, đặt “Limits to be announced.” bên trái footer và một badge “PLANNED” bên phải. Không thêm Planned ở từng dòng.
Không ellipsis cho quyền lợi. Cho phép xuống dòng và tăng chiều cao sheet theo nội dung, không ép hai sheet cao bằng nhau.

## 10. Ghi chú triển khai Flutter
1. Dùng theme/tokens và typography hiện có nếu khớp; không chép toàn bộ Tailwind config từ HTML vì export có token lệch với Profile.
2. Dùng SafeArea, layout linh hoạt và scroll khi cần; 390 × 844 là viewport tham chiếu, không là kích thước màn hardcode.
3. Giữ nguyên data flow hiện có của Nutrition / Workout. Tách dữ liệu catalog demo khỏi entitlement thực tế; không dùng selected plan làm quyền truy cập.
4. Nội dung UI tiếng Anh trước; chuẩn bị localization keys, không ép một dòng cho chuỗi có thể dài khi dịch.
5. Routing phải phân biệt Back theo stack và Back to Membership có đích rõ ràng.
6. Không tạo backend mới, gọi payment, ghi subscription hoặc thay schema cho demo.
7. Không tự commit/push/merge khi chưa có lệnh triển khai riêng.
8. Tài liệu này bàn giao thiết kế, không tự cấp phạm vi sửa code; xác minh workspace và allowed paths trước checkpoint triển khai.

## 11. Kiểm tra trước bàn giao cuối
- [ ] Có đủ export/ảnh cuối cho 7 màn và 2 sheet.
- [ ] Overview: review đủ Plus / Pro / Ultra sau chỉnh và giá Yearly.
- [ ] Compare: badge không overflow; bảng đúng 4 tier và 4 nhóm.
- [ ] Detail: ba biến thể cùng template, giá và allowance đúng.
- [ ] Manage Membership: review ảnh thực tế.
- [ ] Coming Soon: xác minh màu CTA ở render, không chỉ source.
- [ ] Workout sheet: xác minh ảnh sau đồng bộ Nutrition, không cắt chữ.
- [ ] Back, Overview destination, billing selection và sheet dismiss đúng contract.
- [ ] Không tạo cảm giác đã thanh toán, kích hoạt hoặc có quota thật.
- [ ] Kiểm tra 390px, thiết bị nhỏ hơn và text scale lớn để tránh overlap.

## 12. Tài liệu tham chiếu trong phiên
- Profile: screen(1).png, code(1).html, DESIGN(1).md.
- Overview: code(2).html, screen(2).png; các ảnh phần đầu screen(3).png và screen(4).png.
- Compare: screen(8).png, screen(9).png, screen(10).png.
- Coming Soon: code(3).html = Plus; code(4).html = Pro; code(5).html = Ultra. Ảnh đối chiếu: image(9).png.
- Nutrition sheet: image(20261027-025343).png.
- Workout sheet trước chỉnh: image(10).png.

Tên file trên dùng để đối chiếu nguồn; một số ảnh là bản trước chỉnh. Không coi toàn bộ ảnh này là bản nghiệm thu cuối.

