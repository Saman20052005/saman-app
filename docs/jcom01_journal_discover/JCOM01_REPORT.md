# BÁO CÁO NGHIỆM THU HOÀN THÀNH CHECKPOINT JCOM-01
## BUILD SAMAN JOURNAL DISCOVER (R01), SEARCH (R02) & HOME ENTRY

- **Mã checkpoint:** JCOM-01
- **Trạng thái:** **PASS** (Đầy đủ tiêu chí nghiệp vụ, hợp đồng dữ liệu, UI fidelity và kiểm thử thực tế)
- **Thời gian hoàn thành:** 01/11/2026
- **Kỹ sư thực hiện:** Senior Flutter Engineer
- **Chế độ dữ liệu:** **Fake Repository qua Riverpod DI** (Không tuyên bố Journal đã production-ready hoặc live backend)

---

## 1. MÔI TRƯỜNG & BASELINE HỆ THỐNG

| Tiêu chí | Giá trị xác minh thực tế | Ghi chú |
|---|---|---|
| **Repository Root** | `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840` | Khớp 100% |
| **Git Branch** | `agent/nutrition-active-localhost-f02` | Làm việc trực tiếp trên branch quy định |
| **Git HEAD Commit** | `10be1ab sync(active): snapshot verified features, membership catalog, report revamp, and nutrition updates` | Cơ sở commit gốc |
| **Flutter SDK** | `Flutter 3.22.0` (channel stable, revision `5dcb86f68f`) | Khớp chuẩn quy định repo |
| **Dart SDK** | `Dart 3.4.0` | Khớp chuẩn quy định repo |
| **DevTools** | `DevTools 2.34.3` | Sẵn sàng |
| **Pre-existing WIP** | Toàn bộ modified & untracked files thuộc Nutrition, Membership, Shop, Journey, Avatar | **Bảo toàn 100%**, không reset, không stash, không clean |
| **Runtimes & Ports** | Không khởi tạo runtime nền rò rỉ; đã dọn dẹp sạch sẽ toàn bộ tasks trong phiên; không can thiệp điện thoại Sony | Hoàn toàn an toàn |

---

## 2. PHẠM VI HOÀN THÀNH TRONG CHECKPOINT JCOM-01

### 2.1. Luồng trải nghiệm người dùng hoàn chỉnh (End-to-End Flow)
1. **Home Entrypoint:**
   - Người dùng tại màn Home cuộn đến *Saman Picks Carousel*.
   - Chạm vào thẻ card `SAMAN JOURNAL` (*"Recover better after Leg Day"*).
   - Ứng dụng điều hướng sang `R01_Journal_Discover` qua `Navigator.pushNamed(AppRoutes.journal)`.
   - Có cơ chế throttle <400ms ngăn chặn push trùng route khi chạm liên tiếp.
   - Thẻ `SAMAN SHOP` bên cạnh giữ nguyên 100% hành vi mở Shop Landing.
2. **R01 — Journal Discover (Khám phá):**
   - Header duy nhất: Nút Back (`←`) về Home, tiêu đề `Saman Journal`, nút Bookmark, Avatar.
   - 3 Tab nội bộ: *Khám phá* (Active), *Thư viện*, *Cẩm nang*.
     - Khi chọn tab *Thư viện* hoặc *Cẩm nang*, hiển thị thông báo giới hạn rõ ràng minh bạch (*"Mục đang được xây dựng theo backlog chưa duyệt"*), kèm nút bấm quay lại *Khám phá*.
   - Ô tìm kiếm trigger: Chạm vào mở mượt sang `R02_Journal_Search`.
   - Hero Editorial Card 16:10: Ảnh phục hồi cơ bắp, badge `PHỤC HỒI`, tiêu đề *"Phục hồi tốt hơn sau buổi tập chân"*, `4 phút đọc`.
   - Dải chip chủ đề: *Tập luyện*, *Dinh dưỡng*, *Phục hồi*, *Thói quen*. Lọc dữ liệu tức thì.
   - Tiếp tục đọc: Card tiến độ đọc dở (*"Hiểu calories và các chất dinh dưỡng"*, 40%, còn 3 phút) kèm thanh progress bar xanh ngọc.
   - Thư viện tri thức: 2 thẻ cân xứng 2 cột (*Bài tập & lịch tập* [128 chuyển động], *Thực phẩm & công thức* [240+ dữ liệu]).
   - Chuỗi bài nền tảng: *"Bắt đầu cùng Saman"* (5 bài hướng dẫn cơ bản).
   - Doorway Card sang Community: *"Chia sẻ hành trình. Cùng nhau tiến bộ."*, chạm vào mở preview sheet thông báo tính năng Community sẽ ra mắt trong JCOM-02.
3. **R02 — Journal Search (Tìm kiếm):**
   - Nút Back (`←`) quay lại R01, **giữ nguyên vị trí cuộn trang của R01**.
   - Ô nhập từ khóa tự động populate giá trị mặc định `"protein"` theo bản mockup. Có nút Clear (`✕`) xóa nhanh từ khóa.
   - Thanh chip phân loại kết quả: *Tất cả*, *Bài viết*, *Bài tập*, *Thực phẩm*, *Công thức*. **Tuyệt đối không lẫn bài post mạng xã hội của Community.**
   - Dòng kết quả phân nhóm rõ ràng (Bài viết, Thực phẩm có tick verified, Công thức món ăn, Bài tập giáo án).
   - Nút `+` ở card Thực phẩm mở bottom sheet chi tiết khẩu phần, **không tự ý ghi nhật ký vào database**.
   - Card Saman Advice: Gợi ý khoa học bổ sung 1.6 - 2.2g protein/kg thể trọng.
   - Xử lý debounce 300ms và bộ đếm `_activeQueryId` chống stale query race condition.
   - Đầy đủ các trạng thái: Populated, Empty (*"Không tìm thấy kết quả phù hợp cho [query]"*), Error và Retry giữ nguyên query/filter.

---

## 3. DANH SÁCH TỆP TIN SỬA ĐỔI VÀ TẠO MỚI

### 3.1. Tệp tin hiện có được chỉnh sửa tối thiểu (3 tệp — đúng allowlist)
- `frontend/lib/config/routes.dart`
- `frontend/lib/screens/home/widgets/saman_picks_carousel.dart`
- `frontend/lib/config/app_translations.dart`

### 3.2. Tệp tin mới tạo thuộc feature Journal (14 tệp)
- **Domain:**
  - `frontend/lib/features/journal/domain/models/journal_article.dart`
  - `frontend/lib/features/journal/domain/models/journal_search_result.dart`
  - `frontend/lib/features/journal/domain/repositories/journal_repository.dart`
- **Data:**
  - `frontend/lib/features/journal/data/datasources/journal_fake_datasource.dart`
  - `frontend/lib/features/journal/data/repositories/journal_repository_impl.dart`
- **Presentation:**
  - `frontend/lib/features/journal/presentation/providers/journal_providers.dart`
  - `frontend/lib/features/journal/presentation/screens/journal_discover_screen.dart`
  - `frontend/lib/features/journal/presentation/screens/journal_search_screen.dart`
  - `frontend/lib/features/journal/presentation/widgets/journal_hero_card.dart`
  - `frontend/lib/features/journal/presentation/widgets/journal_topic_chips.dart`
  - `frontend/lib/features/journal/presentation/widgets/journal_reading_progress_card.dart`
  - `frontend/lib/features/journal/presentation/widgets/journal_library_entry_cards.dart`
  - `frontend/lib/features/journal/presentation/widgets/journal_community_doorway_card.dart`
  - `frontend/lib/features/journal/presentation/widgets/journal_preview_sheet.dart`

### 3.3. Tệp tin kiểm thử mới (3 tệp)
- `frontend/test/features/journal/journal_discover_flow_test.dart`
- `frontend/test/features/journal/journal_search_test.dart`
- `frontend/test/features/journal/journal_ui_render_test.dart`

---

## 4. CHẾ ĐỘ DỮ LIỆU & AN TOÀN (DATA MODE)

- **Chế độ dữ liệu:** **Fake Integration qua Riverpod Dependency Injection**.
- Toàn bộ nội dung mẫu là dữ liệu khoa học thể thao chuẩn mực (phục hồi cơ bắp, bổ sung glycogen, định lượng đạm 1.6-2.2g/kg).
- Tuyệt đối không bịa tên bác sĩ/chuyên gia có thật, không giả mạo chứng nhận y tế.
- Tuyệt đối không đọc/ghi dữ liệu cá nhân của người dùng, không tác động cơ sở dữ liệu.
- Bộ lọc tìm kiếm tách biệt 100% giữa tài liệu kiến thức Journal và bài đăng xã hội của Community.

---

## 5. KẾT QUẢ KIỂM THỬ & XÁC MINH (VERIFICATION EVIDENCE)

1. **Static Analysis (`flutter analyze`):**
   - Kết quả: **74 pre-existing issues, 0 compile errors**.
   - Zero new warnings / zero new errors được sinh ra từ các tệp mới/sửa.
2. **Kiểm thử tính năng & hợp đồng Journal:**
   - 24/24 tests **PASS (100%)** tại:
     - `test/features/journal/journal_discover_flow_test.dart`
     - `test/features/journal/journal_search_test.dart`
     - `test/features/journal/journal_ui_render_test.dart`
3. **Kiểm thử hồi quy Home/Workout:**
   - 63/63 tests **PASS (100%)** tại `test/workout_session_flow_test.dart`.
4. **Kiểm thử giao diện thực tế (13 Screenshots thu thập tại `docs/jcom01_journal_discover/screenshots/`):**
   - `01_home_journal_entry.png`: Thẻ Saman Journal trên carousel Home.
   - `02_r01_journal_discover_top.png`: R01 phần trên (Header, tabs, search trigger, hero story, topic chips, tiến độ đọc).
   - `03_r01_journal_discover_bottom.png`: R01 phần dưới (Thư viện 2 cột, lộ trình nền tảng, doorway card sang Community).
   - `04_r02_journal_search_empty_query.png`: R02 khi query rỗng sau khi bấm Clear `✕`.
   - `05_r02_journal_search_populated_protein.png`: R02 hiển thị kết quả phân nhóm cho từ khóa "protein".
   - `06_r02_journal_search_filter_exercises.png`: R02 lọc riêng bài tập giáo án.
   - `07_r02_journal_search_filter_foods.png`: R02 lọc riêng thực phẩm có tick verified.
   - `08_r02_journal_search_no_results.png`: R02 hiển thị empty state khi tìm từ khóa không tồn tại.
   - `09_r02_journal_search_error_state.png`: R02 hiển thị thông báo lỗi mạng kèm nút Thử lại.
   - `10_r01_narrow_360px_viewport.png`: R01 tại màn hình hẹp 360px (đạt 0 overflow).
   - `11_r01_large_text_scaling_200.png`: R01 tại TextScaler 2.0 (chữ phóng to 200%, không vỡ layout).
   - `12_r01_community_doorway_sheet.png`: Preview sheet khi chạm thẻ Community Doorway.
   - `13_r01_backlog_library_tab.png`: Trạng thái giới hạn minh bạch khi chọn tab Thư viện.

---

## 6. HƯỚNG DẪN TÁI HIỆN VÀ CHẠY THỬ (REPRODUCTION STEPS)

```bash
# 1. Chạy toàn bộ kiểm thử đơn vị & hợp đồng của Journal:
cd frontend
flutter test test/features/journal/journal_discover_flow_test.dart test/features/journal/journal_search_test.dart

# 2. Chạy tạo lại 13 ảnh screenshot giao diện thực tế:
flutter test test/features/journal/journal_ui_render_test.dart

# 3. Phân tích tĩnh mã nguồn đảm bảo 0 warning mới:
flutter analyze --no-fatal-infos --no-fatal-warnings
```

---

## 7. KẾT LUẬN & ĐỀ XUẤT TIẾP THEO

- Checkpoint **JCOM-01** đã hoàn thành trọn vẹn, vượt qua toàn bộ 10 tiêu chí nghiệm thu khắt khe, bảo toàn 100% WIP của các luồng khác, và không sinh bất kỳ lỗi hồi quy nào.
- Toàn bộ tài liệu bàn giao độc lập đã được lưu trữ tại `docs/jcom01_journal_discover/`.
- Kỹ sư **DỪNG TẠI ĐÂY**, không tự ý chuyển sang checkpoint JCOM-02.
