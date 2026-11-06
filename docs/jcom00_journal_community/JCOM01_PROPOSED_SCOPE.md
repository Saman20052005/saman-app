# ĐẶC TẢ PHẠM VI & ALLOWLIST ĐỀ XUẤT CHO CHECKPOINT JCOM-01
## CHECKPOINT JCOM-01: FOUNDATION, NAVIGATION SHELL & SAMAN JOURNAL (R01, R02)

Tài liệu này xác định ranh giới phạm vi nghiêm ngặt, danh sách tệp được phép sửa (`allowed_paths`), danh sách tệp mới tạo, và tiêu chí nghiệm thu cho bước triển khai mã nguồn đầu tiên: **JCOM-01**.

---

## 1. MỤC TIÊU VÀ TRẢI NGHIỆM NGƯỜI DÙNG (USER JOURNEY)

1. **Điểm vào từ Saman Home:**
   - Người dùng đang ở màn hình chính Home, cuộn đến phần *Saman Picks Carousel*.
   - Chạm vào thẻ card `SAMAN JOURNAL` (*"Recover better after Leg Day"*).
   - Ứng dụng chuyển cảnh mượt mà toàn màn hình sang `R01_Journal_Discover` (tạm ẩn thanh bottom navigation của app chính).
2. **Khám phá Tri thức Saman Journal (`R01_Journal_Discover`):**
   - Header: Nút Quay lại (`←`), Tiêu đề `Saman Journal`, Nút Bookmark, Avatar người dùng.
   - 3 Tab nội bộ: *Khám phá* (Active), *Thư viện*, *Cẩm nang*.
   - Thanh tìm kiếm trigger: Chạm vào chuyển sang `R02_Journal_Search`.
   - Hero Editorial Card: Hiển thị bài viết phục hồi sau Leg Day với tag `PHỤC HỒI`, `4 phút đọc`.
   - Dải chip chủ đề: *Tất cả*, *Tập luyện*, *Dinh dưỡng*, *Phục hồi*, *Thói quen*.
   - Card tiếp tục đọc: Hiển thị tiến độ đọc dở (40%, còn 3 phút).
   - Card Thư viện tri thức: 2 thẻ cân xứng (Bài tập & Lịch tập; Thực phẩm & Công thức).
   - Card Cửa ngõ Saman Community (*Doorway Card*): *"Chia sẻ hành trình. Cùng nhau tiến bộ"*, chạm vào kích hoạt preview chuyển sang Community Feed.
3. **Tìm kiếm Kiến thức & Tra cứu (`R02_Journal_Search`):**
   - Header: Nút Quay lại về R01, Ô nhập từ khóa có nút Clear (`✕`), nút Lọc nâng cao.
   - Thanh chip phân loại kết quả: *Tất cả*, *Bài viết*, *Bài tập*, *Thực phẩm*, *Công thức* (Tuyệt đối không hiển thị bài post mạng xã hội).
   - Hiển thị kết quả tìm kiếm phân nhóm rõ ràng; nút `+` ở thực phẩm mở xem chi tiết, không tự ý ghi nhật ký.
   - Xử lý debounce 300ms, hủy bỏ kết quả query cũ đè query mới.
   - Trạng thái rỗng: *"Không tìm thấy kết quả phù hợp cho [query]"*.
4. **Hành vi Quay lui (Back Behavior):**
   - Từ R02 quay lại R01: Giữ nguyên vị trí cuộn trang của R01.
   - Từ R01 quay lại Home: Đưa người dùng về đúng vị trí carousel trên Home Screen, khôi phục thanh bottom navigation chính của app.

---

## 2. PHẠM VI TỆP TIN ĐƯỢC PHÉP SỬA ĐỔI (`allowed_paths`)

Tuân thủ nghiêm ngặt quy định tại `AGENTS.md` (Scope Control & Smallest Safe Diff), checkpoint JCOM-01 chỉ được phép chạm vào các tệp tin dưới đây:

### 2.1. Tệp tin hiện có cần chỉnh sửa (3 tệp)
```
frontend/lib/config/routes.dart
frontend/lib/screens/home/widgets/saman_picks_carousel.dart
frontend/lib/config/app_translations.dart
```
- **Chi tiết sửa đổi:**
  - `routes.dart`: Đăng ký 2 hằng số route mới `AppRoutes.journal` (`/journal`) và `AppRoutes.journalSearch` (`/journal/search`) trong hàm `onGenerateRoute`.
  - `saman_picks_carousel.dart`: Bổ sung điều hướng `Navigator.of(context).pushNamed(AppRoutes.journal)` khi người dùng chạm vào thẻ `journal_recovery` (thay thế giá trị `null` hiện tại).
  - `app_translations.dart`: Bổ sung các chuỗi bản địa hóa cho giao diện R01 và R02 (cả tiếng Việt và tiếng Anh).

### 2.2. Tệp tin mới đề xuất tạo (Nằm hoàn toàn trong `features/journal/`)
```
frontend/lib/features/journal/domain/models/journal_article.dart
frontend/lib/features/journal/domain/models/journal_search_result.dart
frontend/lib/features/journal/domain/repositories/journal_repository.dart
frontend/lib/features/journal/data/datasources/journal_fake_datasource.dart
frontend/lib/features/journal/data/repositories/journal_repository_impl.dart
frontend/lib/features/journal/presentation/providers/journal_providers.dart
frontend/lib/features/journal/presentation/screens/journal_discover_screen.dart
frontend/lib/features/journal/presentation/screens/journal_search_screen.dart
frontend/lib/features/journal/presentation/widgets/journal_hero_card.dart
frontend/lib/features/journal/presentation/widgets/journal_topic_chips.dart
frontend/lib/features/journal/presentation/widgets/journal_reading_progress_card.dart
frontend/lib/features/journal/presentation/widgets/journal_library_entry_cards.dart
frontend/lib/features/journal/presentation/widgets/journal_community_doorway_card.dart
```

### 2.3. Tệp tin kiểm thử mới
```
frontend/test/features/journal/journal_discover_flow_test.dart
frontend/test/features/journal/journal_search_test.dart
```

> [!CAUTION]
> **Các tệp tuyệt đối CẤM sửa trong JCOM-01:**
> - Tuyệt đối không sửa `frontend/pubspec.yaml` hay `pubspec.lock`.
> - Tuyệt đối không sửa các router hay model trong `backend/`.
> - Tuyệt đối không sửa logic của `WorkoutHomeScreen`, `NutritionScreen`, `ProfileScreen`, `ChatScreen`.
> - Tuyệt đối không sửa `AGENTS.md`.

---

## 3. CHẾ ĐỘ DỮ LIỆU (DATA MODE)

- **Chế độ dữ liệu:** **Fake Integration qua Riverpod Dependency Injection**.
- `JournalRepositoryImpl` sử dụng `JournalFakeDatasource` chứa các bài viết khoa học chuẩn hóa về phục hồi cơ bắp, dinh dưỡng đa lượng và thói quen thể thao.
- Không hardcode dữ liệu trong Widget; toàn bộ UI tiêu thụ dữ liệu qua `journalArticlesProvider` và `journalSearchProvider`.
- Dễ dàng thay thế bằng Live HTTP Client trong checkpoint JCOM-05 mà không phải sửa lại tầng giao diện (Presentation Layer).

---

## 4. TIÊU CHÍ NGHIỆM THU (ACCEPTANCE CRITERIA)

- [ ] **Home Entrypoint:** Chạm vào card `SAMAN JOURNAL` tại Home mở đúng màn hình `R01_Journal_Discover`.
- [ ] **R01 Visual Fidelity:** 100% khớp thiết kế đã duyệt trong `design/saman-Journal_community/r01_journal_discover/`.
- [ ] **R01 Tabs:** Hiển thị đúng 3 tab (*Khám phá*, *Thư viện*, *Cẩm nang*). Tuyệt đối không có tab Community.
- [ ] **R01 Doorway Card:** Thẻ giới thiệu Community ở chân trang hiển thị đẹp mắt, chạm vào mở thông báo preview hoặc màn hình Community stub an toàn.
- [ ] **R02 Search Flow:** Chạm thanh tìm kiếm tại R01 chuyển sang R02; gõ từ khóa hiển thị kết quả phân nhóm (Bài viết, Bài tập, Thực phẩm).
- [ ] **R02 Search Isolation:** Tuyệt đối không trộn bài viết mạng xã hội của Community vào kết quả tìm kiếm của Journal.
- [ ] **Zero Regressions:**
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` đạt **0 errors, 0 new warnings**.
  - Toàn bộ test suite liên quan chạy thành công.
- [ ] **Back Behavior:** Nút Back trên header và nút Back của thiết bị hoạt động chính xác, không tạo vòng lặp navigation, giữ nguyên vị trí cuộn.

---

## 5. LỆNH XÁC MINH CẦN CHẠY KHI THỰC THI JCOM-01

```bash
# 1. Phân tích tĩnh mã nguồn
cd frontend
flutter analyze --no-fatal-infos --no-fatal-warnings

# 2. Chạy targeted unit & widget test cho Journal
flutter test test/features/journal/journal_discover_flow_test.dart
flutter test test/features/journal/journal_search_test.dart

# 3. Chạy regression test cho màn Home
flutter test test/workout_session_flow_test.dart
```
