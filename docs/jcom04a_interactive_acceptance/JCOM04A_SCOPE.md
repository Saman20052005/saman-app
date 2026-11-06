# XÁC LẬP PHẠM VI THỰC THI JCOM-04A — INTERACTIVE FRONTEND ACCEPTANCE

**Workspace Root:** `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840`  
**Git Branch:** `agent/nutrition-active-localhost-f02`  
**Git HEAD:** `10be1ab sync(active): snapshot verified features, membership catalog, report revamp, and nutrition updates`  
**Thời gian lập:** 01/11/2026 22:31:00 +07:00  

---

## 1. Xác minh Trạng thái Kho Mã & WIP

- **Nhánh thực thi:** `agent/nutrition-active-localhost-f02` (Không được chuyển nhánh, không commit/push/merge).
- **Trạng thái WIP hiện hữu:**
  - 100% các file sửa đổi trước đó thuộc `backend/`, `frontend/lib/presentation/`, `frontend/lib/features/membership/`, `frontend/lib/features/nutrition/`, `frontend/lib/features/profile/` được giữ nguyên vẹn.
  - Các thay đổi của phân hệ Journal & Community nằm chính xác trong `allowed_paths`:
    - `frontend/lib/features/community/`
    - `frontend/lib/features/journal/`
    - `frontend/test/features/community/`
    - `frontend/test/features/journal/`
    - `frontend/lib/config/routes.dart`
    - `frontend/lib/config/app_translations.dart`
    - `docs/`

---

## 2. Đường dẫn Thực tế & 18 Màn hình Phân hệ Journal & Community

| Mã màn hình | Tên màn hình | Đường dẫn file thực tế | Trạng thái Implementation |
| :--- | :--- | :--- | :--- |
| **R01** | Journal Discover | `frontend/lib/features/journal/presentation/screens/journal_discover_screen.dart` | Hoàn thành |
| **R02** | Journal Search | `frontend/lib/features/journal/presentation/screens/journal_search_screen.dart` | Hoàn thành |
| **R03** | Community Feed | `frontend/lib/features/community/presentation/screens/community_feed_screen.dart` | Hoàn thành |
| **R04** | Community Discover | `frontend/lib/features/community/presentation/screens/community_discover_screen.dart` | Hoàn thành |
| **R05** | Community Post Detail | `frontend/lib/features/community/presentation/screens/community_post_detail_screen.dart` | Hoàn thành |
| **R06A** | Post Select Media | `frontend/lib/features/community/presentation/screens/compose/post_select_media_screen.dart` | Hoàn thành |
| **R06B** | Post Edit Media | `frontend/lib/features/community/presentation/screens/compose/post_edit_media_screen.dart` | Hoàn thành |
| **R06C** | Post Album Order | `frontend/lib/features/community/presentation/screens/compose/post_album_order_screen.dart` | Hoàn thành |
| **R06D** | Post Compose & Publish | `frontend/lib/features/community/presentation/screens/compose/post_compose_publish_screen.dart` | Hoàn thành |
| **R07** | Activity Attachment | `frontend/lib/features/community/presentation/screens/compose/community_select_attachment_screen.dart` | Hoàn thành |
| **R08** | Ask Question | `frontend/lib/features/community/presentation/screens/compose/community_ask_question_screen.dart` | Hoàn thành |
| **R09** | Community Profile | `frontend/lib/features/community/presentation/screens/profile/community_profile_screen.dart` | Hoàn thành |
| **R10** | Community Follow List | `frontend/lib/features/community/presentation/screens/profile/community_follow_list_screen.dart` | Hoàn thành |
| **R11** | Community Notifications | `frontend/lib/features/community/presentation/screens/notifications/community_notifications_screen.dart` | Hoàn thành |
| **R12** | Community Saved | `frontend/lib/features/community/presentation/screens/saved/community_saved_screen.dart` | Hoàn thành |
| **R13** | Community Drafts | `frontend/lib/features/community/presentation/screens/drafts/community_drafts_screen.dart` | Hoàn thành |
| **R14** | Community Edit Profile | `frontend/lib/features/community/presentation/screens/profile/community_edit_profile_screen.dart` | Hoàn thành |
| **R15** | Community Question Detail | `frontend/lib/features/community/presentation/screens/qa/community_question_detail_screen.dart` | Hoàn thành |

---

## 3. Phân định Hiện trạng Kiểm tra (Evidence Classification)

### A. Đã kiểm tra trực tiếp (Direct Verification)
- **Static Analyzer**: `flutter analyze lib/features/community test/features/community lib/features/journal test/features/journal lib/config/routes.dart` -> **0 issues found**.
- **Community Suite**: `flutter test test/features/community/` -> **61/61 PASS** (13 flow, 15 compose, 10 features, 23 render suites).
- **Journal Suite**: `flutter test test/features/journal/` -> **28/28 PASS** (Flow, search race condition, UI renders).
- **App-wide Regression Suite**: `flutter test test/workout_session_flow_test.dart` -> **63/63 PASS**.
- **Render Screenshots**: Đã sinh đầy đủ 28 ảnh chụp màn hình kiểm thử trong `docs/jcom02_community_feed/screenshots/` (`c01`–`c13`), `docs/jcom03_media_composer/screenshots/` (`c14`–`c21`), và `docs/jcom04_profile_notifications/screenshots/` (`c22`–`c28`).

### B. Chỉ kế thừa từ báo cáo trước (Inherited from Previous Reports)
- **Profile Blocker**: Sự cố backend thiếu trường `user_id` trong `/api/user/profile` khiến `MainScreen` ném `FormatException` khi chạy production web app (ghi nhận tại JCOM-01A và JCOM-01B).
- **CDP Port 8089**: Trình duyệt từng chạy qua port 8089 trong phiên kiểm thử JCOM-01A.

### C. Chưa có bằng chứng runtime tương tác thật (Pending Evidence in JCOM-04A)
- Chuỗi thao tác tương tác liên tục giữa các màn hình trên ứng dụng thực thi (Navigation loop, Like/Save/Follow state reflection trên detail/profile, Commenting/Answering submit, Composer 4 bước, Draft lifecycle mở/sửa/xóa, Edit profile identity reflection).
- Bằng chứng kiểm tra xem Media Editing (crop/rotate/brightness/contrast) là metadata/preview hay raster transform.
- Bằng chứng kiểm tra nguồn dữ liệu Activity Attachment (R07) là fixture hay service thật.
