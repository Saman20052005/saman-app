# XÁC NHẬN PHẠM VI & ALLOWLIST — CHECKPOINT JCOM-01
## BUILD SAMAN JOURNAL DISCOVER (R01), SEARCH (R02) & HOME ENTRY

- **Mã checkpoint:** JCOM-01
- **Thời gian lập:** 01/11/2026
- **Trạng thái:** IN_PROGRESS
- **Kỹ sư thực hiện:** Senior Flutter Engineer

---

## 1. MÔI TRƯỜNG & BASELINE THỰC TẾ

| Thông số | Giá trị xác minh thực tế | Ghi chú |
|---|---|---|
| **Repository Root** | `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840` | Không thay đổi |
| **Git Branch** | `agent/nutrition-active-localhost-f02` | Làm việc trực tiếp trên branch quy định |
| **Git HEAD** | `10be1ab sync(active): snapshot verified features, membership catalog, report revamp, and nutrition updates` | Snapshot commit cơ sở |
| **Flutter SDK** | `Flutter 3.22.0` (channel stable, revision `5dcb86f68f`) | Khớp chuẩn AGENTS.md |
| **Dart SDK** | `Dart 3.4.0` | Khớp chuẩn AGENTS.md |
| **DevTools** | `DevTools 2.34.3` | Sẵn sàng |
| **Pre-existing WIP** | Toàn bộ modified & untracked files thuộc Nutrition, Membership, Shop, Journey, Avatar | **Bảo toàn 100%**, không reset, không clean, không can thiệp |
| **Pre-existing Analyzer Baseline** | 74 issues (info & warning có sẵn trong repo), **0 compile errors** | Giữ vững zero regression |
| **Pre-existing Test Baseline** | `test/workout_session_flow_test.dart`: 63/63 tests PASS | Xác minh luồng Home/Workout hoạt động tốt |
| **Runtimes & Ports** | Không có devserver hay emulator nào chạy ngoài phiên; không can thiệp điện thoại Sony | Sạch sẽ |

---

## 2. PHẠM VI TỆP TIN ĐƯỢC PHÉP SỬA & TẠO MỚI

### 2.1. Tệp tin hiện có được phép sửa đổi tối thiểu (3 tệp)
1. `frontend/lib/config/routes.dart`
   - *Phần sửa:* Đăng ký 2 routes `AppRoutes.journal` (`/journal`) và `AppRoutes.journalSearch` (`/journal/search`) trong `AppRoutes.onGenerateRoute`.
2. `frontend/lib/screens/home/widgets/saman_picks_carousel.dart`
   - *Phần sửa:* Gắn sự kiện `onTap` cho card `journal_recovery` gọi `SamanPicksCarousel.navigateToJournal(context)` với cơ chế throttle chống duplicate push trên rapid double-tap, bổ sung callback `onJournalTap`. Giữ nguyên 100% cấu trúc carousel, card `shop_recovery` và các thành phần khác.
3. `frontend/lib/config/app_translations.dart`
   - *Phần sửa:* Bổ sung các translation keys cho Journal Discover (R01), Journal Search (R02), Community doorway, category chips, reading progress, libraries, search filters, empty/error/retry states (cả tiếng Việt `vi` và tiếng Anh `en`).

### 2.2. Tệp tin mới tạo thuộc feature Journal (Hoàn toàn nằm trong `frontend/lib/features/journal/`)
- **Domain Layer:**
  1. `frontend/lib/features/journal/domain/models/journal_article.dart`
  2. `frontend/lib/features/journal/domain/models/journal_search_result.dart`
  3. `frontend/lib/features/journal/domain/repositories/journal_repository.dart`
- **Data Layer:**
  4. `frontend/lib/features/journal/data/datasources/journal_fake_datasource.dart`
  5. `frontend/lib/features/journal/data/repositories/journal_repository_impl.dart`
- **Presentation Layer:**
  6. `frontend/lib/features/journal/presentation/providers/journal_providers.dart`
  7. `frontend/lib/features/journal/presentation/screens/journal_discover_screen.dart`
  8. `frontend/lib/features/journal/presentation/screens/journal_search_screen.dart`
  9. `frontend/lib/features/journal/presentation/widgets/journal_hero_card.dart`
  10. `frontend/lib/features/journal/presentation/widgets/journal_topic_chips.dart`
  11. `frontend/lib/features/journal/presentation/widgets/journal_reading_progress_card.dart`
  12. `frontend/lib/features/journal/presentation/widgets/journal_library_entry_cards.dart`
  13. `frontend/lib/features/journal/presentation/widgets/journal_community_doorway_card.dart`
  14. `frontend/lib/features/journal/presentation/widgets/journal_preview_sheet.dart`

### 2.3. Tệp tin kiểm thử mới (Nằm trong `frontend/test/features/journal/`)
1. `frontend/test/features/journal/journal_discover_flow_test.dart`
2. `frontend/test/features/journal/journal_search_test.dart`
3. `frontend/test/features/journal/journal_ui_render_test.dart`

---

## 3. CÁC ĐIỀU CẤM TUYỆT ĐỐI (FORBIDDEN CHANGES)

- CẤM sửa bất kỳ file nào trong `backend/`.
- CẤM sửa `AGENTS.md`.
- CẤM nâng cấp / sửa `frontend/pubspec.yaml` và `frontend/pubspec.lock`.
- CẤM can thiệp vào các feature khác: `workout`, `nutrition`, `membership`, `shop`, `journey`, `profile`.
- CẤM sửa theme toàn cục ngoài phạm vi hai màn Journal.
- CẤM tạo route giả cho Community R03 hoặc 14 màn backlog chưa duyệt.
- CẤM thực hiện git reset/clean/checkout/merge.

---

## 4. QUY CÁCH DỮ LIỆU & HÀNH VI
- Dữ liệu sử dụng **Fake Repository qua Riverpod DI**.
- Không gọi API backend live trong JCOM-01.
- Tuyệt đối không giả lập tác giả có thật, chứng nhận y khoa hay số liệu sức khỏe cá nhân thật.
- Khám phá (R01) và Tìm kiếm (R02) hỗ trợ đủ các trạng thái: Loading, Populated, Empty, Error, Retry.
- Search xử lý debounce 300ms, hủy/bỏ qua kết quả query cũ đè query mới, retry giữ nguyên query/filter hiện hành.
