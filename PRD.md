# PRD — Saman Fitness

> **Nguồn sự thật về sản phẩm.**
> Mọi thay đổi hướng sản phẩm → cập nhật file này trước khi implement.

---

## 1. Overview

| Field | Detail |
|---|---|
| **Tên app** | Saman Fitness |
| **Mô tả** | Ứng dụng mobile AI giúp người dùng theo dõi dinh dưỡng và tập luyện, cá nhân hóa theo mục tiêu sức khỏe cá nhân |
| **Domain** | Fitness / Nutrition / AI Health |
| **Platform** | Mobile — iOS & Android (Flutter) |
| **Backend** | FastAPI (Python) + MongoDB |
| **AI** | PyTorch EfficientNet-B3 (food recognition) + Gemini/OpenAI (chat) |

---

## 2. Problem

### Người dùng đang gặp vấn đề gì?

**Dinh dưỡng:**
- Không biết bữa ăn hằng ngày chứa bao nhiêu calo, protein, carb, fat
- Nhập thực phẩm thủ công vào app tốn thời gian → người dùng bỏ cuộc sau vài ngày
- Không có kế hoạch ăn uống phù hợp với mục tiêu cá nhân (giảm cân / tăng cơ / duy trì)

**Tập luyện:**
- Không biết bài tập nào phù hợp với trình độ và mục tiêu
- Không theo dõi được tiến trình tập luyện theo thời gian
- Thiếu hướng dẫn trực quan (video / GIF) về cách thực hiện động tác

**Tổng thể:**
- Thiếu một nơi tập trung quản lý cả dinh dưỡng lẫn tập luyện
- Không có AI assistant tư vấn theo ngữ cảnh cá nhân của từng user

---

## 3. Target Users

### Primary
- **Người mới bắt đầu tập gym** (18–30 tuổi): cần hướng dẫn cơ bản, track tiến trình
- **Người muốn giảm cân / tăng cơ**: cần theo dõi calo và macro hằng ngày
- **Người bận rộn**: muốn log dinh dưỡng nhanh bằng chụp ảnh

### Secondary
- Người tập luyện trung cấp muốn tối ưu hóa chế độ ăn
- Người quan tâm sức khỏe tổng thể, muốn có insight từ dữ liệu cá nhân

### Không phải target (MVP)
- Vận động viên chuyên nghiệp cần tracking nâng cao
- Người cần chế độ ăn y tế (phải do chuyên gia tư vấn)

---

## 4. Core Features (MVP)

### F1 — Food Recognition (AI)
- User chụp ảnh món ăn → AI nhận dạng (101 loại, Food-101 dataset)
- Tự động tính: calories, protein, carb, fat, fiber
- User review và confirm trước khi lưu

### F2 — Nutrition Tracking
- Nhật ký ăn uống hằng ngày (breakfast / lunch / dinner / snack)
- Tổng macro trong ngày so với mục tiêu
- Theo dõi lượng nước uống
- Kế hoạch bữa ăn AI cá nhân hóa theo goal

### F3 — Workout Tracking
- Thư viện bài tập theo nhóm cơ và độ khó
- Video / GIF demo bài tập
- Log buổi tập: sets, reps, weight
- Lịch sử tập luyện

### F4 — AI Chat Assistant
- Chat với AI nhận lời khuyên về fitness / nutrition
- AI có context: profile + nutrition log + workout log của user
- Tư vấn theo mục tiêu cá nhân

### F5 — Progress Reports
- Báo cáo dinh dưỡng / tập luyện theo ngày / tuần / tháng
- Biểu đồ trực quan các chỉ số sức khỏe

### F6 — Authentication & Profile
- Đăng nhập: Google / Facebook / Apple OAuth
- Profile: tuổi, cân nặng, chiều cao, mục tiêu, activity level

---

## 5. Non-goals (MVP)

- **Không** build social / community features (feed, follow, share)
- **Không** build marketplace (bán thực phẩm, supplement)
- **Không** tích hợp wearables / smartwatch
- **Không** build web app — tập trung mobile trước
- **Không** cung cấp tư vấn y tế — app không thay thế bác sĩ / chuyên gia dinh dưỡng
- **Không** hỗ trợ full offline mode ở giai đoạn đầu

---

## 6. Success Metrics

| Metric | Target |
|---|---|
| Daily active logging | User nhập ≥ 1 bữa ăn / ngày |
| Weekly retention | User quay lại ≥ 3 ngày / tuần trong tháng đầu |
| Photo feature adoption | ≥ 60% bữa ăn log bằng ảnh (không nhập tay) |
| Day-7 retention | ≥ 40% |
| Day-30 retention | ≥ 20% |
| Food recognition accuracy | ≥ 80% trên tập test |
| AI Chat response time | < 3 giây |

---

## 7. Constraints & Assumptions

- App yêu cầu kết nối internet — AI inference chạy trên server
- Dữ liệu dinh dưỡng từ USDA / OpenFoodFacts — có thể sai lệch với món Việt Nam
- Food-101 dataset chủ yếu là món Tây → cần mở rộng dataset cho món Việt trong tương lai
- AI Chat không thay thế tư vấn y tế — phải có disclaimer rõ ràng trong app

---
