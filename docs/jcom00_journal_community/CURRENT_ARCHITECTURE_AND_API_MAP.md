# BẢN ĐỒ KIẾN TRÚC FLUTTER & NGUỒN DỮ LIỆU / API BACKEND
## SAMAN JOURNAL & COMMUNITY SYSTEM AUDIT

Tài liệu này phản ánh trung thực kiến trúc Flutter hiện hữu, hệ thống điều hướng, cơ chế xác thực, design tokens và phân loại toàn diện trạng thái API backend phục vụ xây dựng Saman Journal & Community.

---

## 1. TỔNG QUAN KIẾN TRÚC FLUTTER HIỆN TẠI

Codebase Flutter của ứng dụng Saman tuân thủ nghiêm ngặt **Feature-First Clean Architecture** kết hợp với **Riverpod State Management**:

```
frontend/lib/
├── config/                  # App constants, routes, translations, themes
│   ├── app_translations.dart# Hệ thống đa ngôn ngữ tiếng Việt / tiếng Anh
│   ├── routes.dart          # AppRoutes.onGenerateRoute tập trung
│   └── api_config.dart      # Cấu hình BASE_URL và endpoints
├── features/                # Phân rã theo nghiệp vụ độc lập (Feature-First)
│   ├── profile/             # ProfileGate, onboarding, avatar repository
│   ├── workout/             # Quản lý giáo án & thực thi bài tập
│   ├── nutrition/           # Quản lý bữa ăn, food image attribution
│   ├── shop/                # Saman Shop (Catalog, Product detail, Cart)
│   └── journey/             # Hành trình rèn luyện & phần thưởng
├── screens/                 # Shell màn hình chính và widget cấp cao
│   ├── main_screen.dart     # IndexedStack 5 tabs chính của ứng dụng
│   ├── home_screen.dart     # Bảng điều khiển Home tổng hợp
│   └── home/widgets/        # SamanPicksCarousel (Cửa ngõ Journal)
├── presentation/            # Shared viewmodels, providers & tokens
├── services/                # Network clients (Dio / ApiClient)
├── theme/                   # Theme mở rộng (ThemeExtension)
└── utils/                   # AuthHelper, Token storage, Validator
```

---

## 2. HỆ THỐNG ĐIỀU HƯỚNG & APP SHELL

### 2.1. Cấu trúc Route hiện hữu (`frontend/lib/config/routes.dart`)
Hệ thống sử dụng `Navigator 1.0` tập trung qua `AppRoutes.onGenerateRoute`:
- `/`: `SplashScreen`
- `/login`: `LoginScreen`
- `/main`: `ProfileGate` → `MainScreen`
- `/settings`: `AppSettingsScreen`
- `/shop`, `/shop/detail`, `/shop/saved`: `ShopScreens`
- `/journey/create`, `/journey/my`, `/journey/wallet`: `JourneyScreens`

> [!IMPORTANT]
> **Hiện trạng:** Chưa có bất kỳ route nào cho Journal hay Community được đăng ký trong `AppRoutes`.

### 2.2. Shell chính `MainScreen` (`frontend/lib/screens/main_screen.dart`)
Ứng dụng sử dụng `IndexedStack` quản lý 5 tab cơ sở:
1. `Index 0`: `HomeScreen`
2. `Index 1`: `WorkoutHomeScreen`
3. `Index 2`: `ChatScreen` (Saman AI Coach)
4. `Index 3`: `NutritionScreen` (Nhật ký dinh dưỡng)
5. `Index 4`: `ProfileScreen` (Hồ sơ thể lực)

Thanh điều hướng chính `SamanBottomNavigationBar` cố định ở đáy.

### 2.3. Cửa ngõ Journal từ Home (`saman_picks_carousel.dart`)
Trong `HomeScreen`, widget `SamanPicksCarousel` (`frontend/lib/screens/home/widgets/saman_picks_carousel.dart`) hiển thị 2 thẻ gợi ý:
1. `id: 'journal_recovery'`: Thẻ `SAMAN JOURNAL` (*"Recover better after Leg Day"*).
   - **Thực tế mã nguồn (Dòng 203–207):**
     ```dart
     final effectiveTap = item.onTap ??
         (item.id == 'shop_recovery'
             ? (onShopTap ?? () => SamanPicksCarousel.navigateToShop(context))
             : null);
     ```
     Sự kiện `onTap` của `journal_recovery` hiện đang trả về `null` vì chưa có màn Journal để điều hướng tới!

---

## 3. UI FOUNDATION, DESIGN TOKENS & LOCALIZATION

### 3.1. Hệ thống Design Tokens (`saman_home_tokens.dart`)
Ứng dụng sử dụng chuẩn màu Obsidian Athletic Precision rất đồng nhất:
- **Canvas / Background:** `Color(0xFF0C0D0E)`
- **Card Surface:** `Color(0xFF16171B)`
- **Card Elevated / Input:** `Color(0xFF1B1D22)` / `Color(0xFF26282F)`
- **Hairline Borders:** `Color(0xFF23252A)` và `Color(0xFF26282F)`
- **Text Hierarchy:**
  - Primary: `Color(0xFFFFFFFF)` / `Color(0xFFF3F4F6)`
  - Secondary: `Color(0xFF94979E)`
  - Muted: `Color(0xFF71717A)`
- **Đặc tả bổ sung cho Community (PRD v3.0):**
  - Nút chính đặc (Primary Solid): `#08664F`
  - Text action header / unread dot: `#8AD8BD` (hoặc `#54C7A5`)
  - Nút phụ trung tính (Secondary Action): `#24272B`

### 3.2. Đa ngôn ngữ (`frontend/lib/config/app_translations.dart`)
- Quản lý qua `LanguageNotifier` (hỗ trợ `system`, `vi`, `en`).
- Widget gọi dịch ngắn gọn qua extension: `context.tr('key')`.
- Thêm từ khóa mới bằng cách khai báo vào map `_localizedValues` trong `app_translations.dart`.

---

## 4. AUTH VÀ VÒNG ĐỜI TÀI KHOẢN (`AuthHelper.dart`)

Hệ thống quản lý phiên đăng nhập và cô lập dữ liệu người dùng rất chặt chẽ:
- Lưu token an toàn qua `FlutterSecureStorage` (`auth_token`, `jwt_token`, `user_email`, `user_fullname`).
- `ProfileGate` kiểm soát quyền truy cập: 401 tự động kích hoạt quy trình logout và chuyển về màn `/login`.
- **Quy trình dọn dẹp khi Logout (`AuthHelper.logout()`):**
  1. Xóa toàn bộ token xác thực trong secure storage.
  2. Tăng `sessionEpoch` trong `ProfileNotifier` và `workoutAuthScopeNotifier` để hủy bỏ tức thì các request bất đồng bộ đang bay.
  3. Xóa cache SharedPreferences theo `userId` (`cached_profile_snapshot_v2_${currentUserId}`, `onboarding_draft_${currentUserId}`).
  4. Invalidate toàn bộ providers phụ thuộc: `profileProvider`, `nutritionProvider`, `workoutHistoryProvider`, `journeyControllerProvider`...

> [!CAUTION]
> **Yêu cầu đối với Journal & Community:**
> Khi xây dựng Community, các provider như `communityDraftsProvider`, `communitySavedProvider`, `communityNotificationsProvider` phải được đăng ký vào luồng dọn dẹp này để tránh rò rỉ dữ liệu khi người dùng đăng xuất hoặc chuyển tài khoản.

---

## 5. BẢN ĐỒ CAPABILITIES & PHÂN LOẠI API HIỆN HỮU

Dưới đây là bảng phân loại khách quan toàn bộ các capability liên quan giữa mã nguồn frontend và backend:

| Capability | Phân loại trạng thái | Endpoint Backend / Method | Symbol Frontend tương ứng | Đánh giá & Ranh giới kỹ thuật |
|---|---|---|---|---|
| **Workout Catalog (Bài tập)** | **Live / Có sẵn** | `GET /workout/exercises` | `ExerciseRepositoryImpl.getExercises()` | Tái sử dụng để tra cứu bài tập trong R02. |
| **Workout History (Lịch sử tập)** | **Live / Có sẵn** | `GET /workout/history` | `workoutHistoryProvider` | Tái sử dụng làm danh mục chọn đính kèm trong R07. |
| **Workout Session Detail** | **Live / Có sẵn (Private)** | `GET /workout/sessions/{session_id}` | `sessionDetailProvider` | **Private theo userId**. Không cho phép người xem bên ngoài gọi endpoint này. |
| **Nutrition Search (Thực phẩm)** | **Live / Có sẵn** | `GET /nutrition/foods/search` | `NutritionService.searchFoods()` | Tái sử dụng để tra cứu thực phẩm trong R02. |
| **Nutrition Logs (Bữa ăn đã log)** | **Live / Có sẵn** | `GET /nutrition/{date}` | `nutritionProvider` | Tái sử dụng làm danh mục chọn đính kèm bữa ăn trong R07. |
| **Avatar Upload / Google Sync** | **Live / Có sẵn** | `POST /user/avatar/upload`<br>`POST /user/avatar/use-google` | `AvatarRepositoryImpl`<br>`SamanAvatar` | Tái sử dụng trực tiếp cho chức năng đổi avatar trong R14. |
| **Journal Discovery & Search** | **Chưa tìm thấy (Not Found)** | Chưa có trong backend | Chưa có trong frontend | Cần tạo `JournalRepository` + Fake/Mock cho JCOM-01. |
| **Community Feed & Post Detail** | **Chưa tìm thấy (Not Found)** | Chưa có trong backend | Chưa có trong frontend | Cần tạo `CommunityRepository` + Fake/Mock cho JCOM-02. |
| **Like / Save / Follow** | **Chưa tìm thấy (Not Found)** | Chưa có trong backend | Chưa có trong frontend | Cần tạo state machine đồng bộ giữa Feed, Detail, Profile, Saved. |
| **Community Profile & Follow List** | **Chưa tìm thấy (Not Found)** | Chưa có trong backend | Chưa có trong frontend | Hồ sơ cộng đồng độc lập với Profile sức khỏe thể chất. |
| **Community Notifications** | **Chưa tìm thấy (Not Found)** | Chưa có trong backend | Chưa có trong frontend | Cần quản lý unread badge và phân nhóm Hôm nay / Trước đó. |
| **Post Drafts Management** | **Chưa tìm thấy (Not Found)** | Chưa có trong backend | Chưa có trong frontend | Lưu trữ cục bộ (Local SharedPreferences) phân tách theo `userId`. |
| **Post Media Upload (Album)** | **Chưa tìm thấy (Not Found)** | Chưa có trong backend | Chưa có trong frontend | Giai đoạn đầu dùng file cục bộ; giai đoạn Live cần API upload riêng. |
| **Publish Post / Ask Question** | **Chưa tìm thấy (Not Found)** | Chưa có trong backend | Chưa có trong frontend | Cần có cơ chế Idempotency Key chống đăng trùng. |

---

## 6. ĐỀ XUẤT CONTRACT KỸ THUẬT & TYPED REPOSITORY BOUNDARY

Vì API backend cho Journal và Community chưa tồn tại, chúng tôi đề xuất kiến trúc ranh giới Interface rõ ràng để frontend có thể phát triển độc lập với dữ liệu giả lập (Fake Repository qua Dependency Injection):

### 6.1. Typed Contract cho Saman Journal
```dart
abstract class JournalRepository {
  Future<List<JournalArticle>> getFeaturedArticles();
  Future<List<JournalArticle>> getArticlesByTopic(String topic);
  Future<ReadingProgress?> getReadingProgress();
  Future<JournalSearchResult> search({
    required String query,
    String? categoryFilter,
  });
  Future<void> bookmarkArticle(String articleId, bool isBookmarked);
}
```

### 6.2. Typed Contract cho Saman Community
```dart
abstract class CommunityRepository {
  // Feed & Discover
  Future<List<CommunityPost>> getFeed({
    required CommunityFeedFilter filter,
    String? cursor,
    int limit = 10,
  });
  Future<List<CommunityPost>> getDiscoverGrid({String? tag, int page = 1});
  Future<CommunityPost> getPostDetail(String postId);
  
  // Interactions
  Future<void> toggleLike(String postId);
  Future<void> toggleSave(String postId);
  Future<void> toggleFollow(String targetUserId);
  
  // Comments & Q&A
  Future<List<CommunityComment>> getComments(String postId, {String? cursor});
  Future<CommunityComment> addComment(String postId, String content, {String? parentId});
  Future<QuestionDetail> getQuestionDetail(String questionId);
  Future<void> voteUseful(String questionId, String answerId);
  Future<void> selectAskerChoice(String questionId, String answerId);
  
  // Composer & Publish
  Future<CommunityPost> publishPost(DraftPost post, {required String idempotencyKey});
  Future<CommunityQuestion> publishQuestion(DraftQuestion question, {required String idempotencyKey});
  
  // Profile & Saved
  Future<CommunityProfile> getProfile(String userId);
  Future<List<CommunityPost>> getSavedPosts({String? filter});
  Future<List<CommunityNotification>> getNotifications();
}
```

### 6.3. Mô hình Snapshot Hoạt động Đính kèm (Bảo vệ dữ liệu riêng tư)
```dart
class SharedWorkoutAttachmentSnapshot {
  final String sessionName;
  final int durationMinutes;
  final int totalExercises;
  final List<String> exerciseNames;
  // Các trường nhạy cảm chỉ có giá trị khi tác giả bật switch
  final bool includesWeightsAndReps;
  final int? totalVolumeKg;
  final int? totalSets;
}

class SharedMealAttachmentSnapshot {
  final String foodName;
  final String mealType;
  final String? imageUrl;
  // Chỉ có giá trị khi tác giả bật switch
  final bool includesMacros;
  final int? calories;
  final double? protein;
  final double? carbs;
  final double? fat;
}
```
Mô hình snapshot này đảm bảo nội dung chia sẻ cộng đồng hoàn toàn độc lập với nhật ký gốc, không làm lộ dữ liệu sức khỏe riêng tư và không bị hỏng nếu người dùng xóa nhật ký gốc trong app.
