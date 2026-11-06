# BIÊN BẢN BÀN GIAO MILESTONE: SAMAN AI COACH (BASELINE RULE-BASED)

- **Thời gian lập**: 2026-11-04 15:10 +07:00
- **Workspace**: `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840`
- **Branch / HEAD**: `agent/nutrition-active-localhost-f02` / `10be1ab1971214acd2487ef893df3fcc80212fc9`
- **Đối tượng bàn giao**: Cụm tính năng AI Coach — Workout Recommendation Baseline (CP-AI-07, CP-AI-08, CP-AI-09) phục vụ nghiệm thu môn học.

---

## 1. Mục tiêu Milestone
- Tích hợp luồng gợi ý bài tập cá nhân hóa vào Saman AI Chat trên nền tảng Clean Architecture và FastAPI Backend.
- Vận hành thuật toán trích xuất ngữ cảnh lịch sử tập luyện và bộ quy tắc xếp hạng xác định (Deterministic Rule-based Baseline) phân giải trên Exercise Catalog chuẩn hóa gồm 49 bài tập (`backend/app/data/ai_exercise_catalog.generated.json`).
- Đảm bảo tính an toàn dữ liệu: Read-only đối với lịch sử/hồ sơ/kế hoạch người dùng khi chat; tách biệt dữ liệu giữa các tài khoản; cách ly hoàn toàn các cuộc gọi AI provider bên ngoài trong môi trường kiểm thử; kiểm thử giao diện Flutter Web đầu cuối.

---

## 2. Trạng thái Nghiệm thu Tổng thể

| Checkpoint | Phạm vi / Trọng tâm | Trạng thái | Báo cáo chi tiết |
|---|---|---|---|
| **CP-AI-07** | E2E Acceptance trên Flutter Web, MongoDB test cô lập, kiểm tra phân tách ngữ cảnh A/B, Read-only mixed request, bảo toàn dữ liệu | **PASS** | `docs/ai_coach/CP-AI-07/REPORT.md` |
| **CP-AI-08** | Offline Evaluation hợp đồng gợi ý bài tập (Offline Contract Evaluation), 6/6 kịch bản hành vi tổng hợp (synthetic cases), 41 baseline tests | **PASS** | `docs/ai_coach/CP-AI-08/REPORT.md` |
| **CP-AI-09** | Nghiệm thu tổng hợp cục bộ: 3 ca Flutter Web (Empty history, Injected history-read failure, Recovery) PASS; Đóng gói Docker image backend & resolver smoke test | **PARTIAL** | `docs/ai_coach/CP-AI-09/REPORT.md` |

> [!NOTE]
> Trạng thái tổng kết chặng AI Coach Baseline là **PARTIAL** do bước kiểm thử đóng gói Docker container bị gián đoạn vì môi trường máy host hiện tại chưa cài đặt Docker Engine / CLI. Toàn bộ logic ứng dụng trên Flutter Web và Backend Python cục bộ đã đạt yêu cầu nghiệm thu chức năng.

---

## 3. Hạng mục Đã xác minh (VERIFIED)
- **Giao diện & Luồng E2E Flutter Web (CP-AI-07 & CP-AI-09)**:
  - Xác thực thực tế qua UI Chat composer, flow đăng nhập chuẩn thành công (HTTP 200).
  - Phân tách rõ ràng giữa 3 trạng thái lịch sử: Lịch sử trống (Empty history), Lỗi đọc lịch sử được giả lập (Injected history read error), và Phục hồi hiển thị gợi ý sau khi gỡ lỗi (Recovery).
  - Tách biệt dữ liệu và cuộc hội thoại độc lập giữa các tài khoản người dùng khác nhau (A, B, C).
  - Xử lý mixed request an toàn: Không ghi đè hoặc tạo mới workout plan, profile snapshot hay workout history trái phép khi tương tác chat.
  - 0 cuộc gọi AI provider bên ngoài trái phép (cách ly hoàn toàn outbound API keys).
- **Kiểm thử Offline & Hợp đồng Baseline (CP-AI-08)**:
  - 41/41 unit/integration baseline tests PASS (`test_ai05_workout_recommendation`, `test_ai04_catalog_resolver`, `test_ai03_workout_history_context`).
  - 6/6 kịch bản offline evaluation (Cold start, History/Equipment/Muscle filter, Unresolved history ID, Filter exclusion, Synthetic temporal holdout) đạt tỷ lệ PASS 100%.
  - Luôn đảm bảo tối đa 5 bài tập trả về, tất cả canonical ID/slug đều phân giải được trong catalog.
- **Tính toàn vẹn của Exercise Catalog cục bộ (Source-tree)**:
  - File catalog nguồn: `backend/app/data/ai_exercise_catalog.generated.json`.
  - SHA-256 fingerprint: `FB955CB9F2DFE962952C6FA9FBCA0E2DE65D19480584BBD2A715FDECA0221C33`.
  - Số lượng bài tập: **Chính xác 49 bài tập**.
- **Lưu trữ bằng chứng Runtime (Runtime Evidence)**:
  - Bằng chứng runtime của từng checkpoint được lưu đầy đủ tại:
    - CP-AI-07: `D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-07\`
    - CP-AI-08: `D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-08\`
    - CP-AI-09: `D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-09\`

---

## 4. Hạng mục Chưa xác minh / Còn thiếu (UNVERIFIED / MISSING)
- **Đóng gói Docker Image & Smoke Test Container Cô lập (CP-AI-09)**:
  - **Trạng thái**: **BLOCKED do môi trường host**.
  - **Nguyên nhân**: Máy trạm Windows hiện tại không có Docker CLI (`docker`), Docker daemon (named pipe `\\.\pipe\docker_engine` vắng mặt), và không có container builder tương thích (`podman`, `nerdctl`).
  - **Hệ quả**: Chưa tạo được Image ID `saman-backend-ai:cp-ai-09`; chưa trích xuất đối soát SHA-256 và số lượng 49 bản ghi của catalog từ bên trong artifact image; chưa thực thi smoke test resolver độc lập từ container với cờ `--network none` và không mount source.
- **Chất lượng gợi ý trên người dùng thực tế (Real-User Quality)**:
  - **Trạng thái**: **UNVERIFIED / MISSING**.
  - **Nguyên nhân**: Toàn bộ kiểm thử hiện tại sử dụng dữ liệu giả lập (synthetic fixtures). Chưa có tập dữ liệu lịch sử người dùng thực tế được chuẩn hóa danh tính và bảo mật, cũng như chưa có nhãn đánh giá mức độ liên quan (human-graded relevance / NDCG@5).
  - Thuật toán hiện tại là **Baseline Heuristic/Rule-based xác định**, không phải mô hình ML học máy đã huấn luyện.

---

## 5. Điều kiện tiếp tục & Kế hoạch tiếp theo (Next Steps)
1. **Hoàn tất CP-AI-09 (Docker Packaging)**:
   - Chuyển workspace sang môi trường đã cài đặt Docker Desktop / Docker Engine sẵn sàng.
   - Chạy lệnh build: `docker build -t saman-backend-ai:cp-ai-09 -f Dockerfile .`
   - Xác minh SHA-256 của catalog bên trong container khớp với `FB955CB9F2DFE962952C6FA9FBCA0E2DE65D19480584BBD2A715FDECA0221C33` và chứa đủ 49 bài tập.
   - Chạy smoke test resolver trong container với `--network none` và ghi nhận kết quả chuyển trạng thái CP-AI-09 từ PARTIAL sang PASS.
2. **CP-AI-10 (Nghiên cứu & Huấn luyện Model Học máy - ML Training)**:
   - **Quy tắc kích hoạt**: Chỉ mở khi có yêu cầu cụ thể từ giảng viên hướng dẫn môn học và khi đã có tập dữ liệu thực tế được cấp phép, làm sạch thông tin cá nhân (privacy-cleared) và có bộ nhãn đánh giá chất lượng chuẩn.
   - Không tự ý điều chỉnh trọng số baseline hay gán nhãn mô hình học máy cho thuật toán heuristic hiện tại khi chưa có chỉ đạo chính thức.

---

## 6. Cam kết Tuân thủ Quy tắc Dự án (Governance & Safety Compliance)
- **Không sửa source code ứng dụng**: Toàn bộ source code frontend và backend không bị thay đổi.
- **Không thay đổi Dockerfile**: Giữ nguyên cấu hình Dockerfile gốc của kho lưu trữ.
- **Không tự động commit/push/merge**: Bảo toàn nguyên trạng 263 mục Git WIP hiện có.

