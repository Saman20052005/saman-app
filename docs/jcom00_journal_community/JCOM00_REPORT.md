# BÁO CÁO KHẢO SÁT TOÀN DIỆN & LẬP KẾ HOẠCH BUILD SAMAN JOURNAL / COMMUNITY
## CHECKPOINT JCOM-00 — READ-ONLY AUDIT & IMPLEMENTATION ROADMAP

- **Mã checkpoint:** JCOM-00
- **Trạng thái:** **PASS** (Đủ điều kiện & căn cứ kiến trúc/thiết kế để chuyển sang build JCOM-01)
- **Thời gian thực hiện:** 01/11/2026
- **Kỹ sư thực hiện:** Senior Flutter / FastAPI Engineer
- **Chế độ thực thi:** READ-ONLY tuyệt đối đối với source code, cấu hình, dependencies và cơ sở dữ liệu.

---

## 1. XÁC MINH WORKSPACE & MÔI TRƯỜNG THỰC TẾ

| Tiêu chí | Giá trị xác minh thực tế | Ghi chú / Trạng thái |
|---|---|---|
| **Active Workspace** | `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840` | Khớp 100% với môi trường làm việc chính |
| **Git Branch** | `agent/nutrition-active-localhost-f02` | Giữ nguyên branch, không checkout/chuyển branch |
| **Git HEAD Commit** | `10be1ab sync(active): snapshot verified features, membership catalog, report revamp, and nutrition updates` | Trạng thái commit gần nhất của repo |
| **Git Status / WIP** | Có các file modified & untracked thuộc luồng Nutrition, Membership, Shop, Journey | **Bảo toàn 100% WIP**, không reset, không stash, không clean, không can thiệp |
| **Repository Rules** | Tuân thủ `AGENTS.md` (Clean Architecture, Feature-First, Zero regression, Allowed paths nghiêm ngặt) | Áp dụng đầy đủ quy tắc governance |
| **Flutter SDK** | `Flutter 3.22.0` (channel stable, revision `5dcb86f68f`) | Khớp chuẩn quy định repo |
| **Dart SDK** | `Dart 3.4.0` | Khớp chuẩn quy định repo |
| **Python Runtime** | `Python 3.11.9` | Khớp chuẩn quy định repo |
| **Thiết bị / Runtimes** | Không có emulator, không có process backend/frontend đang chạy nền; không tác động điện thoại Sony | Không khởi động/dừng runtime ngoài phiên |

---

## 2. KẾT QUẢ KHẢO SÁT TÀI LIỆU & THIẾT KẾ ĐÃ CHỐT

### 2.1. Vị trí thiết kế
- Thư mục thiết kế thực tế đã được tìm thấy tại: `design/saman-Journal_community/` (viết hoa chữ `J`).
- Thư mục chứa đầy đủ 3 bộ ghi chú bàn giao:
  1. `CP1/SAMAN_JOURNAL_COMMUNITY_5_SCREENS_BUILD_NOTES.md` (R01–R05)
  2. `CP2/SAMAN_CP02_8_SCREENS_BUILD_NOTES.md` (R06A–R06D, R07, R08–R10)
  3. `CP3/SAMAN_CP03_R11_R15_BUILD_NOTES.md` (R11–R15)
- Đặc tả yêu cầu sản phẩm đầy đủ và mới nhất:
  - `CP3/prd_saman_journal_community_master_specification_v3.0.md` (v3.0 — Production-Ready Master Specification).
- Hệ thống thiết kế tham chiếu:
  - `obsidian_kinetic/DESIGN.md` (Obsidian Kinetic Theme).
- Toàn bộ **18 màn hình** đều có thư mục export độc lập, chứa đầy đủ `code.html` và `screen.png`.

### 2.2. Phiên bản thiết kế được chọn làm chuẩn
- **R06 cũ** (đơn màn) đã được thay thế hoàn toàn bằng **R06A–R06D** (Luồng tạo bài Media-First 4 bước).
- **R07** sử dụng **bản refined cuối cùng** (`r07_community_select_attachment_refined`), với các switch quyền riêng tư (Khối lượng tạ & Số hiệp) **TẮT mặc định**.
- **R11–R15** sử dụng phiên bản cuối cùng: nút trung tính (`#24272B`), chữ sáng, primary solid emerald (`#08664F`), text action header (`#8AD8BD` / `#54C7A5`), R14 có nút *Lưu* trên header thay vì nút mint lớn ở đáy.
- Bỏ toàn bộ header lặp, tên frame, công cụ giả lập ("Chế độ xem: Khách / Chính mình", "Mô phỏng rỗng"), branding mẫu (Kinetic, Pro Coach) và badge xác minh giả.

---

## 3. HIỆN TRẠNG IMPLEMENTATION TRONG MÃ NGUỒN

> [!IMPORTANT]
> **Kết luận khảo sát mã nguồn thực tế (Khách quan, không suy diễn):**
> 1. **Frontend (`frontend/lib/`):** Chưa có bất kỳ màn hình, widget, model hay provider nào cho Saman Journal (R01, R02) hoặc Saman Community (R03–R15).
>    - Điểm chạm duy nhất hiện có là thẻ card tĩnh `SAMAN JOURNAL` (`id: 'journal_recovery'`) trong `SamanPicksCarousel` (`frontend/lib/screens/home/widgets/saman_picks_carousel.dart`), nhưng sự kiện `onTap` hiện tại đang trả về `null`.
> 2. **Backend (`backend/`):** Chưa có bất kỳ router, schema hay collection nào phục vụ Saman Journal hoặc Saman Community.
>    - Danh sách router hiện có trong `backend/main.py`: `auth`, `user`, `chat`, `food_analysis`, `nutrition`, `workout`, `health`, `journey`, `revenue`, `shop`.
>    - Chưa có `journal_router` hay `community_router`.

---

## 4. TÀI NGUYÊN HIỆN CÓ CÓ THỂ TÁI SỬ DỤNG NGAY

Mặc dù Journal và Community chưa được build, codebase Saman sở hữu nền tảng kiến trúc rất vững chắc có thể tái sử dụng trực tiếp:

1. **Kiến trúc Clean Architecture & State Management:**
   - Cấu trúc thư mục theo Feature-First: `frontend/lib/features/[feature]/` với `data/`, `domain/`, `presentation/`.
   - Quản lý trạng thái bằng Flutter Riverpod (`StateNotifierProvider`, `FutureProvider`, `@riverpod`).
2. **Hệ thống Design Tokens & Theme:**
   - `SamanHomeTokens` (`frontend/lib/screens/home/tokens/saman_home_tokens.dart`) chứa đầy đủ các mã màu chuẩn Obsidian: Canvas `#0C0D0E`, Card `#16171B`, Hairline border `#23252A` / `#26282F`, Accent emerald `#10B981` / `#08664F`.
3. **Localization Engine:**
   - `AppTranslations` (`frontend/lib/config/app_translations.dart`) với extension `context.tr('key')`, hỗ trợ đầy đủ `vi` và `en`. Dễ dàng bổ sung key mới.
4. **Hạ tầng Avatar & Hồ sơ:**
   - Backend đã có sẵn `POST /user/avatar/upload` và `POST /user/avatar/use-google` (`backend/routers/user.py`).
   - Frontend đã có `AvatarRepository`, `AvatarRepositoryImpl`, và widget dùng chung `SamanAvatar` (`frontend/lib/widgets/saman_avatar.dart`), tái sử dụng hoàn hảo cho R14.
5. **Nguồn dữ liệu Workout & Nutrition (Để làm R07 attachment picker):**
   - Workout: `ExerciseRepositoryImpl` với `getWorkoutHistory()` trả về `List<WorkoutSession>`.
   - Nutrition: `NutritionService` / `nutritionProvider` lấy danh sách bữa ăn đã log theo ngày.
6. **Cơ chế Điều hướng & Bảo mật Auth:**
   - `ProfileGate` và `AppRoutes.onGenerateRoute`.
   - `AuthHelper.logout()` với cơ chế dọn dẹp cache, epoch bump, và xóa token an toàn.

---

## 5. CÁC RỦI RO, KHOẢNG TRỐNG & QUYẾT ĐỊNH CẦN LƯU Ý

1. **Rủi ro rò rỉ dữ liệu sức khỏe riêng tư (Health Data Quarantine):**
   - Khi chia sẻ buổi tập hoặc bữa ăn lên Community (R07), dữ liệu đính kèm **bắt buộc phải là Snapshot bất biến** (`SharedWorkoutAttachmentSnapshot`, `SharedMealAttachmentSnapshot`) được lưu trực tiếp trong Post model.
   - Tuyệt đối không cho phép client của người dùng khác gọi trực tiếp endpoint riêng tư `/workout/sessions/{session_id}` hoặc `/nutrition/logs/{date}` của tác giả.
   - Hành động đính kèm và đăng bài không được tự ý ghi, sửa hoặc xóa nhật ký Workout/Nutrition của người dùng.
2. **Quản lý Bản nháp (Drafts) & Chuyển tài khoản (Account Switch):**
   - Bản nháp (R13) phải được lưu trữ riêng biệt theo `userId` (ví dụ: `community_drafts_${userId}`). Khi người dùng đăng xuất hoặc đổi tài khoản, bản nháp của tài khoản cũ phải được cách ly tuyệt đối, không hiển thị cho tài khoản mới.
3. **Media Upload & Stitch Expiring URLs:**
   - Các file `code.html` trong thiết kế đang sử dụng các đường dẫn tạm thời từ Google Stitch (`lh3.googleusercontent.com/aida-public/...`). Các URL này sẽ hết hạn.
   - Ở các checkpoint UI / Fake integration, phải sử dụng local assets hoặc mock placeholder ổn định, không dựa vào Stitch URLs.
   - Khi bước vào Live Integration, cần thiết kế endpoint upload media cho bài viết `POST /community/media/upload`.

---

## 6. LỘ TRÌNH TRIỂN KHAI ĐỀ XUẤT (CHECKPOINTS)

Để đảm bảo mỗi checkpoint tạo ra luồng chạy được, review được, không dựng 18 màn rỗng:

- **JCOM-01:** Nền tảng điều hướng & Luồng Saman Journal (R01, R02, điểm vào Home, doorway card sang Community, Fake Journal Repository).
- **JCOM-02:** Trải nghiệm cốt lõi Community — Bảng tin & Chi tiết (R03, R04, R05, R15 cơ bản, Shell điều hướng Community Bottom Nav, Fake Community Repository).
- **JCOM-03:** Luồng Tạo nội dung Media-First & Đính kèm hoạt động (R06A, R06B, R06C, R06D, R07, R08, bộ máy quản lý draft và snapshot đính kèm).
- **JCOM-04:** Hồ sơ thành viên, Tương tác xã hội & Bản nháp (R09, R10, R11, R12, R13, R14, tích hợp upload avatar thật qua AvatarRepository).
- **JCOM-05:** Tích hợp Backend Live & Kiểm thử xuyên suốt hệ thống (Xây dựng FastAPI routers, MongoDB collections, idempotency key, regression testing 0 errors).

---

## 7. BỘ TÀI LIỆU BÀN GIAO CHECKPOINT JCOM-00

Tất cả tài liệu khảo sát được lưu trữ tại thư mục evidence riêng: `docs/jcom00_journal_community/`:
1. `JCOM00_REPORT.md` (Báo cáo tổng kết khảo sát này)
2. `DESIGN_SCREEN_INVENTORY.md` (Kiểm kê chi tiết 18 màn hình và sheet đi kèm)
3. `CURRENT_ARCHITECTURE_AND_API_MAP.md` (Bản đồ kiến trúc Flutter, Theme, Auth và API hiện hữu/đề xuất)
4. `NAVIGATION_AND_STATE_MATRIX.md` (Sơ đồ điều hướng, back behavior và ma trận state/lỗi)
5. `DATA_PRIVACY_AND_RECOVERY_GAPS.md` (Khoảng trống bảo mật dữ liệu sức khỏe, draft lifecycle và idempotency)
6. `IMPLEMENTATION_CHECKPOINT_PLAN.md` (Kế hoạch triển khai chi tiết từ JCOM-01 đến JCOM-05)
7. `JCOM01_PROPOSED_SCOPE.md` (Đặc tả chi tiết phạm vi và allowlist cho checkpoint JCOM-01)

---

## 8. THAO TÁC KHÔNG THỰC HIỆN TRONG PHIÊN NÀY & NGUYÊN NHÂN

- **Không chạy migration/seed database:** Checkpoint JCOM-00 là READ-ONLY.
- **Không khởi động backend hoặc Flutter devserver:** Tránh xung đột runtime và thay đổi cấu hình môi trường.
- **Không kết nối hoặc can thiệp điện thoại Sony:** Tuân thủ quy định an toàn thiết bị ngoại vi của người dùng.
- **Không sửa đổi source code ứng dụng hoặc dependencies:** Giữ nguyên trạng thái để người dùng phê duyệt kết quả khảo sát trước khi bắt đầu JCOM-01.

**KẾT LUẬN:** Checkpoint JCOM-00 hoàn thành khảo sát xuất sắc. Mọi dữ liệu đã sẵn sàng để bắt đầu **JCOM-01**. Dừng phiên và chờ chỉ đạo tiếp theo từ người dùng.
