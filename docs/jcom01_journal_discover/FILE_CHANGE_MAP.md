# BẢN ĐỒ THAY ĐỔI TỆP TIN (FILE CHANGE MAP) — JCOM-01
## BUILD SAMAN JOURNAL DISCOVER (R01), SEARCH (R02) & HOME ENTRY

- **Mã checkpoint:** JCOM-01
- **Thời gian lập:** 01/11/2026
- **Kỹ sư thực hiện:** Senior Flutter Engineer

---

## 1. TỆP TIN HIỆN CÓ ĐƯỢC CHỈNH SỬA (3 TỆP)

| STT | Đường dẫn tệp | Loại thay đổi | Chi tiết nội dung thay đổi |
|---|---|---|---|
| 1 | `frontend/lib/config/routes.dart` | Modified | Khai báo 2 routes: `AppRoutes.journal` (`/journal`) và `AppRoutes.journalSearch` (`/journal/search`). Đăng ký builder cho `JournalDiscoverScreen` và `JournalSearchScreen` trong `onGenerateRoute`. |
| 2 | `frontend/lib/screens/home/widgets/saman_picks_carousel.dart` | Modified | Bổ sung hàm `SamanPicksCarousel.navigateToJournal(context)` có cơ chế throttle chống double-tap (<400ms). Bổ sung callback `onJournalTap`. Nối `onTap` của card `journal_recovery` vào điều hướng Journal. Bảo toàn 100% card `shop_recovery` và các thành phần khác. |
| 3 | `frontend/lib/config/app_translations.dart` | Modified | Khai báo các chuỗi bản địa hóa cho R01 và R02 (cả tiếng Anh `en` và tiếng Việt `vi`): tiêu đề `journal_title`, placeholder tìm kiếm, 3 tabs nội bộ, dải topic chips, category chips, tiến độ đọc, thư viện, cẩm nang, doorway card. |

---

## 2. TỆP TIN MỚI ĐƯỢC TẠO THUỘC FEATURE JOURNAL (14 TỆP)

### A. Tầng Domain (Domain Layer)
| STT | Đường dẫn tệp | Trách nhiệm kiến trúc |
|---|---|---|
| 1 | `frontend/lib/features/journal/domain/models/journal_article.dart` | Định nghĩa typed models: `JournalTopic`, `JournalArticle`, `JournalReadingProgress`, `JournalLibraryEntry`, `JournalGuidedSeries`. |
| 2 | `frontend/lib/features/journal/domain/models/journal_search_result.dart` | Định nghĩa typed models: `JournalSearchCategory`, `JournalSearchResultItem`, `JournalAdviceTip`. Cách ly hoàn toàn với bài viết mạng xã hội của Community. |
| 3 | `frontend/lib/features/journal/domain/repositories/journal_repository.dart` | Hợp đồng giao diện trừu tượng (`abstract class`) định nghĩa các phương thức async nạp bài viết, tìm kiếm, tiến độ đọc, thư viện. |

### B. Tầng Dữ liệu (Data Layer)
| STT | Đường dẫn tệp | Trách nhiệm kiến trúc |
|---|---|---|
| 4 | `frontend/lib/features/journal/data/datasources/journal_fake_datasource.dart` | Nguồn dữ liệu mẫu khoa học chuẩn hóa, bám sát bản thiết kế Obsidian Kinetic. Tích hợp cờ giả lập độ trễ, rỗng và lỗi phục vụ kiểm thử đơn vị tự động. |
| 5 | `frontend/lib/features/journal/data/repositories/journal_repository_impl.dart` | Triển khai cụ thể của `JournalRepository`, làm cầu nối chuyển tiếp dữ liệu từ datasource sang presentation layer. |

### C. Tầng Trình diễn (Presentation Layer)
| STT | Đường dẫn tệp | Trách nhiệm kiến trúc |
|---|---|---|
| 6 | `frontend/lib/features/journal/presentation/providers/journal_providers.dart` | Quản lý trạng thái bằng Riverpod: `journalDiscoverProvider`, `journalSearchProvider`. Xử lý debounce tìm kiếm 300ms, hủy bỏ/chống stale query race conditions, giữ bộ lọc khi retry. |
| 7 | `frontend/lib/features/journal/presentation/screens/journal_discover_screen.dart` | Màn hình Khám phá R01 hoàn chỉnh: 1 header duy nhất, 3 internal tabs, search trigger, hero card, topic chips, tiếp tục đọc, thư viện 2 cột, chuỗi bài nền tảng, doorway card sang Community, honest backlog notice cho Thư viện/Cẩm nang. |
| 8 | `frontend/lib/features/journal/presentation/screens/journal_search_screen.dart` | Màn hình Tìm kiếm R02: Search bar với nút Clear, filter chips, grouped result stream (Bài viết, Thực phẩm, Công thức, Bài tập), card lời khuyên Saman Advice, empty & error states. |
| 9 | `frontend/lib/features/journal/presentation/widgets/journal_hero_card.dart` | Thẻ bài viết nổi bật 16:10 với gradient và badge `PHỤC HỒI`, tiêu đề, mô tả và thời gian đọc. |
| 10 | `frontend/lib/features/journal/presentation/widgets/journal_topic_chips.dart` | Dải chip chủ đề cuộn ngang với animation chuyển trạng thái mượt mà. |
| 11 | `frontend/lib/features/journal/presentation/widgets/journal_reading_progress_card.dart` | Thẻ tiến độ đọc dở kèm thanh tiến độ xanh ngọc (40%, còn 3 phút). |
| 12 | `frontend/lib/features/journal/presentation/widgets/journal_library_entry_cards.dart` | Lưới 2 thẻ thư viện cân xứng (Bài tập & Lịch tập, Thực phẩm & Công thức) kèm icon và số lượng. |
| 13 | `frontend/lib/features/journal/presentation/widgets/journal_community_doorway_card.dart` | Thẻ cửa ngõ sang Saman Community kèm cluster avatar thành viên và thông báo preview thân thiện. |
| 14 | `frontend/lib/features/journal/presentation/widgets/journal_preview_sheet.dart` | Bottom sheet xem trước nội dung tối thiểu từ typed model, ngăn ngừa nút im lặng/dead route mà không tự ý build màn chi tiết ngoài phạm vi. |

---

## 3. TỆP TIN KIỂM THỬ MỚI (3 TỆP)

| STT | Đường dẫn tệp | Mục tiêu kiểm thử |
|---|---|---|
| 1 | `frontend/test/features/journal/journal_discover_flow_test.dart` | Kiểm thử Home entrypoint, throttle chống duplicate push trên rapid double-tap, các thành phần R01, chuyển tab backlog, mở preview doorway, và flow error/retry. |
| 2 | `frontend/test/features/journal/journal_search_test.dart` | Kiểm thử R02 search bar, nút clear, lọc category chips, guard chống stale query race condition, empty state, error state, nút `+` thực phẩm. |
| 3 | `frontend/test/features/journal/journal_ui_render_test.dart` | Kiểm thử render UI thực tế và xuất 13 ảnh screenshot chất lượng cao (Home entry, R01 full, R02 đầy đủ states, 360px viewport, 200% text scale, preview sheet, backlog notice). |

---

## 4. TÀI LIỆU BÀN GIAO VÀ BẰNG CHỨNG (7 TỆP)

Tất cả nằm trong `docs/jcom01_journal_discover/`:
1. `JCOM01_SCOPE.md`: Đặc tả phạm vi và allowlist đã xác nhận.
2. `JCOM01_REPORT.md`: Báo cáo hoàn thành checkpoint toàn diện.
3. `FILE_CHANGE_MAP.md`: Bản đồ thay đổi tệp tin này.
4. `UI_REVIEW.md`: Đánh giá giao diện thực tế đối chiếu bản thiết kế gốc.
5. `TEST_RESULTS.md`: Chi tiết kết quả kiểm thử và phân tích tĩnh.
6. `JCOM02_HANDOFF.md`: Kế hoạch và phạm vi đề xuất cho JCOM-02.
7. `screenshots/`: Thư mục chứa 13 ảnh chụp màn hình UI thực tế đã làm sạch dữ liệu.
