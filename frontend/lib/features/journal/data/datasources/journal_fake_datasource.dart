import 'package:flutter/material.dart';
import '../../domain/models/journal_article.dart';
import '../../domain/models/journal_search_result.dart';

/// In-memory fake data source for Saman Journal.
///
/// Provides verified, deterministic fixtures matching the approved Obsidian Kinetic design.
/// Includes hooks for simulated loading delay, empty results, and error triggers for testing.
class JournalFakeDatasource {
  JournalFakeDatasource({
    this.simulatedDelay = const Duration(milliseconds: 50),
    this.shouldSimulateError = false,
    this.shouldSimulateEmpty = false,
  });

  Duration simulatedDelay;
  bool shouldSimulateError;
  bool shouldSimulateEmpty;

  // ─── Default Sample Data ────────────────────────────────────────────────

  static const JournalArticle featuredStory = JournalArticle(
    id: 'article_leg_day_recovery',
    title: 'Phục hồi tốt hơn sau buổi tập chân',
    summary:
        'Chiến lược giảm đau nhức cơ bắp DOMS và bổ sung glycogen giúp cơ thể sẵn sàng cho chu kỳ tải lực tiếp theo.',
    topic: JournalTopic.recovery,
    readTimeMinutes: 4,
    coverImageAsset: 'assets/images/home_journal_recovery.jpg',
    badgeLabel: 'Phục hồi',
    isFeatured: true,
    contentBody:
        'Sau các bài tập cường độ cao như Squat hoặc Romanian Deadlift, các sợi cơ trải qua các vi tổn thương (microtrauma). '
        'Quá trình phục hồi yêu cầu kết hợp giữa dinh dưỡng đủ đạm (1.6 - 2.2g/kg), bổ sung nước và giấc ngủ sâu ít nhất 7-8 tiếng.',
  );

  static const List<JournalArticle> sampleArticles = [
    featuredStory,
    JournalArticle(
      id: 'article_protein_basics',
      title: 'Hiểu protein trong bữa ăn hằng ngày',
      summary: 'Cách tính lượng đạm tối ưu cho mục tiêu tăng cơ và phục hồi.',
      topic: JournalTopic.nutrition,
      readTimeMinutes: 5,
      coverImageAsset: 'assets/images/nutrition/food_uc_ga_luoc_hap.jpg',
      badgeLabel: 'Kiến thức',
      contentBody:
          'Protein đóng vai trò cấu trúc nền tảng cho sự tái tạo cơ bắp sau khi tập luyện. '
          'Chia đều lượng protein qua 3-4 bữa ăn giúp tối ưu hóa tổng hợp protein cơ bắp (MPS) suốt cả ngày.',
    ),
    JournalArticle(
      id: 'article_calories_and_macros',
      title: 'Hiểu calories và các chất dinh dưỡng',
      summary: 'Phân bổ tỷ lệ carb, đạm và chất béo theo chu kỳ luyện tập thể thao.',
      topic: JournalTopic.nutrition,
      readTimeMinutes: 6,
      coverImageAsset: 'assets/images/nutrition.jpg',
      badgeLabel: 'Dinh dưỡng',
    ),
    JournalArticle(
      id: 'article_progressive_overload',
      title: 'Nguyên lý quá tải tăng tiến (Progressive Overload)',
      summary: 'Cách tăng tạ và khối lượng tập luyện thông minh mà không gây chấn thương.',
      topic: JournalTopic.workout,
      readTimeMinutes: 7,
      coverImageAsset: 'assets/images/workout.jpg',
      badgeLabel: 'Tập luyện',
    ),
    JournalArticle(
      id: 'article_sleep_and_muscle',
      title: 'Tối ưu giấc ngủ cho hiệu suất tập luyện',
      summary: 'Khoa học về các giai đoạn giấc ngủ và sự phục hồi hệ thần kinh trung ương.',
      topic: JournalTopic.habits,
      readTimeMinutes: 4,
      coverImageAsset: 'assets/images/home_hero_leg_day.jpg',
      badgeLabel: 'Thói quen',
    ),
  ];

  static const JournalReadingProgress defaultReadingProgress =
      JournalReadingProgress(
    articleId: 'article_calories_and_macros',
    title: 'Hiểu calories và các chất dinh dưỡng',
    progressPercent: 0.40,
    remainingMinutes: 3,
    coverImageAsset: 'assets/images/nutrition.jpg',
    summary: 'Đã đọc 40% • Còn 3 phút',
  );

  static const List<JournalLibraryEntry> libraryEntries = [
    JournalLibraryEntry(
      id: 'library_exercises',
      title: 'Bài tập & lịch tập',
      itemCountLabel: '128 chuyển động',
      icon: Icons.fitness_center_rounded,
      coverImageAsset: 'assets/images/exercises/barbell-bench-press-poster.jpg',
      routeDescription: 'Khám phá giáo án và kỹ thuật chuyển động chuẩn xác.',
    ),
    JournalLibraryEntry(
      id: 'library_foods',
      title: 'Thực phẩm & công thức',
      itemCountLabel: '240+ dữ liệu chuẩn',
      icon: Icons.restaurant_rounded,
      coverImageAsset: 'assets/images/nutrition/food-hero.png',
      routeDescription: 'Cơ sở dữ liệu thực phẩm phong phú giàu dinh dưỡng.',
    ),
  ];

  static const JournalGuidedSeries guidedSeries = JournalGuidedSeries(
    id: 'series_foundation',
    title: 'Bắt đầu cùng Saman',
    subtitle: '5 bài hướng dẫn cơ bản xây dựng thói quen bền bỉ',
    badgeLabel: 'Lộ trình nền tảng',
    totalLessons: 5,
    coverImageAsset: 'assets/images/workout.jpg',
  );

  // ─── Search Pool Fixtures ──────────────────────────────────────────────

  static const List<JournalSearchResultItem> searchCatalog = [
    JournalSearchResultItem(
      id: 'search_article_protein',
      category: JournalSearchCategory.articles,
      title: 'Hiểu protein trong bữa ăn hằng ngày',
      subtitle: 'Cách tính lượng đạm tối ưu cho mục tiêu tăng cơ và phục hồi.',
      badgeText: 'Kiến thức',
      metricText: '5 phút đọc',
      readTimeMinutes: 5,
      imageAsset: 'assets/images/nutrition/food_uc_ga_luoc_hap.jpg',
      isVerified: true,
      detailDescription:
          'Bài viết phân tích các nguồn đạm hoàn chỉnh và cách tính lượng protein dựa trên thể trọng.',
    ),
    JournalSearchResultItem(
      id: 'search_food_chicken_breast',
      category: JournalSearchCategory.foods,
      title: 'Ức gà',
      subtitle: 'Thực phẩm tự nhiên • Đạm cao, ít chất béo',
      badgeText: 'Thực phẩm',
      metricText: '31g Protein / 100g • 165 kcal',
      imageAsset: 'assets/images/nutrition/food_uc_ga_luoc_hap.jpg',
      isVerified: true,
      detailDescription:
          'Ức gà là nguồn thực phẩm giàu protein hàng đầu cho người tập luyện thể thao.',
    ),
    JournalSearchResultItem(
      id: 'search_recipe_yogurt_oats',
      category: JournalSearchCategory.recipes,
      title: 'Sữa chua, yến mạch và trái cây',
      subtitle: 'Bữa sáng nhanh giàu đạm • 10 phút chuẩn bị',
      badgeText: 'Công thức',
      metricText: '24g Protein • 340 kcal',
      imageAsset: 'assets/images/nutrition/food_sua_chua_khong_duong.jpg',
      isVerified: false,
      detailDescription:
          'Món ăn nhẹ dễ chuẩn bị, cân bằng giữa carbs chậm từ yến mạch và protein từ sữa chua Hy Lạp.',
    ),
    JournalSearchResultItem(
      id: 'search_exercise_protein_synthesis',
      category: JournalSearchCategory.exercises,
      title: 'Tập tạ và tổng hợp protein cơ bắp',
      subtitle: 'Tối ưu cửa sổ dinh dưỡng xung quanh buổi tập',
      badgeText: 'Bài tập',
      metricText: 'Giáo án',
      icon: Icons.fitness_center_rounded,
      isVerified: true,
      detailDescription:
          'Chiến lược kích thích tổng hợp protein thông qua các bài tập tạ đa khớp.',
    ),
    JournalSearchResultItem(
      id: 'search_article_leg_day',
      category: JournalSearchCategory.articles,
      title: 'Phục hồi tốt hơn sau buổi tập chân',
      subtitle: 'Giảm đau nhức cơ bắp DOMS và nạp năng lượng hiệu quả.',
      badgeText: 'Phục hồi',
      metricText: '4 phút đọc',
      readTimeMinutes: 4,
      imageAsset: 'assets/images/home_journal_recovery.jpg',
      isVerified: true,
    ),
    JournalSearchResultItem(
      id: 'search_exercise_squat',
      category: JournalSearchCategory.exercises,
      title: 'Barbell Back Squat',
      subtitle: 'Bài tập chân kinh điển phát triển cơ tứ đầu và cơ mông',
      badgeText: 'Bài tập',
      metricText: 'Cơ đùi trước • Đùi sau',
      icon: Icons.fitness_center_rounded,
      isVerified: true,
    ),
    JournalSearchResultItem(
      id: 'search_food_salmon',
      category: JournalSearchCategory.foods,
      title: 'Cá hồi Na Uy',
      subtitle: 'Nguồn đạm cao kèm Omega-3 chống viêm',
      badgeText: 'Thực phẩm',
      metricText: '22g Protein / 100g • 208 kcal',
      imageAsset: 'assets/images/nutrition.jpg',
      isVerified: true,
    ),
  ];

  static const JournalAdviceTip defaultAdviceTip = JournalAdviceTip(
    id: 'tip_protein_window',
    title: 'Gợi ý từ Saman Journal',
    content:
        'Bổ sung từ 1.6 - 2.2g đạm trên mỗi kg thể trọng để hỗ trợ phục hồi mô cơ tối ưu nhất.',
    icon: Icons.tips_and_updates_outlined,
  );

  // ─── Query Normalization Helper ────────────────────────────────────────

  static String _normalize(String input) {
    var str = input.toLowerCase().trim();
    const withDia = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const noDia   = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    for (int i = 0; i < withDia.length; i++) {
      str = str.replaceAll(withDia[i], noDia[i]);
    }
    return str;
  }

  // ─── Async Retrieval Methods ───────────────────────────────────────────

  Future<void> _awaitDelay() async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    if (shouldSimulateError) {
      throw Exception('Lỗi nạp dữ liệu từ Saman Journal (Mô phỏng lỗi kết nối)');
    }
  }

  Future<List<JournalArticle>> getArticles({JournalTopic? topic}) async {
    await _awaitDelay();
    if (shouldSimulateEmpty) return [];
    if (topic == null || topic == JournalTopic.all) {
      return sampleArticles;
    }
    return sampleArticles.where((a) => a.topic == topic).toList();
  }

  Future<JournalArticle?> getFeaturedArticle() async {
    await _awaitDelay();
    if (shouldSimulateEmpty) return null;
    return featuredStory;
  }

  Future<JournalReadingProgress?> getReadingProgress() async {
    await _awaitDelay();
    if (shouldSimulateEmpty) return null;
    return defaultReadingProgress;
  }

  Future<List<JournalLibraryEntry>> getLibraryEntries() async {
    await _awaitDelay();
    if (shouldSimulateEmpty) return [];
    return libraryEntries;
  }

  Future<JournalGuidedSeries?> getGuidedSeries() async {
    await _awaitDelay();
    if (shouldSimulateEmpty) return null;
    return guidedSeries;
  }

  Future<List<JournalSearchResultItem>> search({
    required String query,
    JournalSearchCategory category = JournalSearchCategory.all,
  }) async {
    await _awaitDelay();
    if (shouldSimulateEmpty) return [];

    final cleanQuery = query.trim();
    final normalizedQuery = _normalize(cleanQuery);

    final filtered = searchCatalog.where((item) {
      // Category filter match
      if (category != JournalSearchCategory.all && item.category != category) {
        return false;
      }
      // If query is empty, show all items in this category
      if (normalizedQuery.isEmpty) {
        return true;
      }
      final titleNorm = _normalize(item.title);
      final subtitleNorm = _normalize(item.subtitle);
      final metricNorm = item.metricText != null ? _normalize(item.metricText!) : '';
      final badgeNorm = item.badgeText != null ? _normalize(item.badgeText!) : '';

      return titleNorm.contains(normalizedQuery) ||
          subtitleNorm.contains(normalizedQuery) ||
          metricNorm.contains(normalizedQuery) ||
          badgeNorm.contains(normalizedQuery);
    }).toList();

    return filtered;
  }

  Future<JournalAdviceTip?> getAdviceTipForQuery(String query) async {
    await _awaitDelay();
    if (shouldSimulateEmpty) return null;
    return defaultAdviceTip;
  }

  Future<JournalArticle?> getArticleById(String id) async {
    await _awaitDelay();
    final matches = sampleArticles.where((a) => a.id == id);
    return matches.isNotEmpty ? matches.first : null;
  }
}
