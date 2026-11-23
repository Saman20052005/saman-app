import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../domain/models/journal_article.dart';
import '../../domain/models/journal_search_result.dart';

class JournalSearchResponseDto {
  const JournalSearchResponseDto({
    required this.query,
    required this.category,
    required this.items,
    required this.total,
    this.adviceTip,
  });

  final String query;
  final JournalSearchCategory category;
  final List<JournalSearchResultItem> items;
  final int total;
  final JournalAdviceTip? adviceTip;
}

abstract class JournalRemoteDatasource {
  Future<List<JournalArticle>> getArticles({
    JournalTopic? topic,
    int limit = 10,
    String? cursor,
  });

  Future<JournalArticle?> getFeaturedArticle();

  Future<JournalArticle?> getArticleById(String id);

  Future<JournalSearchResponseDto> search({
    required String query,
    JournalSearchCategory category = JournalSearchCategory.all,
    int limit = 20,
  });

  Future<JournalReadingProgress?> getReadingProgress();

  Future<void> saveReadingProgress({
    required String articleId,
    required double progressPercent,
    required int remainingMinutes,
  });

  Future<List<JournalArticle>> getBookmarkedArticles();

  Future<bool> toggleBookmark({
    required String articleId,
    required bool desiredState,
  });

  Future<List<JournalLibraryEntry>> getLibrarySummary();

  Future<JournalGuidedSeries?> getGuidedSeries();
}

class JournalRemoteDatasourceImpl implements JournalRemoteDatasource {
  JournalRemoteDatasourceImpl({required this.dio});

  final Dio dio;

  @override
  Future<List<JournalArticle>> getArticles({
    JournalTopic? topic,
    int limit = 10,
    String? cursor,
  }) async {
    final queryParams = <String, dynamic>{
      'limit': limit,
    };
    if (topic != null && topic != JournalTopic.all) {
      queryParams['topic'] = topic.id;
    }
    if (cursor != null) {
      queryParams['cursor'] = cursor;
    }

    final response = await dio.get(
      '/api/journal/articles',
      queryParameters: queryParams,
    );

    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to fetch journal articles: HTTP ${response.statusCode}',
      );
    }

    final data = response.data as Map<String, dynamic>;
    final rawArticles = (data['articles'] as List<dynamic>?) ?? [];

    return rawArticles
        .map((a) => _parseArticle(a as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<JournalArticle?> getFeaturedArticle() async {
    final response = await dio.get('/api/journal/featured');

    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to fetch featured article: HTTP ${response.statusCode}',
      );
    }

    final data = response.data as Map<String, dynamic>;
    final rawArticle = data['article'] as Map<String, dynamic>?;
    if (rawArticle == null) return null;

    return _parseArticle(rawArticle);
  }

  @override
  Future<JournalArticle?> getArticleById(String id) async {
    try {
      final response = await dio.get('/api/journal/articles/$id');
      if (response.statusCode == 200) {
        return _parseArticle(response.data as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<JournalSearchResponseDto> search({
    required String query,
    JournalSearchCategory category = JournalSearchCategory.all,
    int limit = 20,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return JournalSearchResponseDto(
        query: '',
        category: category,
        items: const [],
        total: 0,
        adviceTip: null,
      );
    }

    final response = await dio.get(
      '/api/journal/search',
      queryParameters: {
        'q': cleanQuery,
        'category': category.id,
        'limit': limit,
      },
    );

    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Journal search failed: HTTP ${response.statusCode}',
      );
    }

    final data = response.data as Map<String, dynamic>;
    final rawItems = (data['items'] as List<dynamic>?) ?? [];
    final items = rawItems
        .map((item) => _parseSearchItem(item as Map<String, dynamic>))
        .toList();

    JournalAdviceTip? adviceTip;
    final rawTip = data['advice_tip'] as Map<String, dynamic>?;
    if (rawTip != null) {
      adviceTip = JournalAdviceTip(
        id: (rawTip['id'] as String?) ?? 'tip_default',
        title: (rawTip['title'] as String?) ?? 'Lời khuyên Saman',
        content: (rawTip['content'] as String?) ?? '',
        icon: Icons.tips_and_updates_outlined,
      );
    }

    return JournalSearchResponseDto(
      query: (data['query'] as String?) ?? cleanQuery,
      category: JournalSearchCategory.fromId((data['category'] as String?) ?? category.id),
      items: items,
      total: (data['total'] as int?) ?? items.length,
      adviceTip: adviceTip,
    );
  }

  @override
  Future<JournalReadingProgress?> getReadingProgress() async {
    final response = await dio.get('/api/journal/reading-progress');
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to fetch reading progress: HTTP ${response.statusCode}',
      );
    }
    final data = response.data as Map<String, dynamic>;
    final rawProgress = data['progress'] as Map<String, dynamic>?;
    if (rawProgress == null) return null;

    final progressVal = (rawProgress['progress_percent'] as num?)?.toDouble() ?? 0.0;
    final remainingMin = (rawProgress['remaining_minutes'] as int?) ?? 0;
    return JournalReadingProgress(
      articleId: (rawProgress['article_id'] as String?) ?? '',
      title: (rawProgress['title'] as String?) ?? '',
      progressPercent: progressVal,
      remainingMinutes: remainingMin,
      coverImageAsset: (rawProgress['cover_image_asset'] as String?) ??
          'assets/images/home_journal_recovery.jpg',
      summary: (rawProgress['summary'] as String?) ??
          'Đã đọc ${(progressVal * 100).round()}% • Còn $remainingMin phút',
    );
  }

  @override
  Future<void> saveReadingProgress({
    required String articleId,
    required double progressPercent,
    required int remainingMinutes,
  }) async {
    final response = await dio.put(
      '/api/journal/reading-progress/$articleId',
      data: {
        'progress_percent': progressPercent,
        'remaining_minutes': remainingMinutes,
      },
    );
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to update reading progress: HTTP ${response.statusCode}',
      );
    }
  }

  @override
  Future<List<JournalArticle>> getBookmarkedArticles() async {
    final response = await dio.get('/api/journal/bookmarks');
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to fetch bookmarks: HTTP ${response.statusCode}',
      );
    }
    final data = response.data as Map<String, dynamic>;
    final rawArticles = (data['articles'] as List<dynamic>?) ?? [];
    return rawArticles
        .map((a) => _parseArticle(a as Map<String, dynamic>).copyWith(isBookmarked: true))
        .toList();
  }

  @override
  Future<bool> toggleBookmark({
    required String articleId,
    required bool desiredState,
  }) async {
    final Response response;
    if (desiredState) {
      response = await dio.put('/api/journal/bookmarks/$articleId');
    } else {
      response = await dio.delete('/api/journal/bookmarks/$articleId');
    }
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to toggle bookmark: HTTP ${response.statusCode}',
      );
    }
    final data = response.data as Map<String, dynamic>;
    return (data['is_bookmarked'] as bool?) ?? desiredState;
  }

  @override
  Future<List<JournalLibraryEntry>> getLibrarySummary() async {
    final response = await dio.get('/api/journal/library-summary');
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to fetch library summary: HTTP ${response.statusCode}',
      );
    }
    final data = response.data as Map<String, dynamic>;
    final rawEntries = (data['entries'] as List<dynamic>?) ?? [];
    return rawEntries.map((e) {
      final map = e as Map<String, dynamic>;
      final cat = (map['category'] as String?) ?? 'all';
      final count = (map['count'] as int?) ?? 0;
      final icon = cat == 'exercises'
          ? Icons.fitness_center_rounded
          : Icons.restaurant_rounded;
      return JournalLibraryEntry(
        id: (map['id'] as String?) ?? '',
        title: (map['title'] as String?) ?? '',
        itemCountLabel: (map['item_count_label'] as String?) ?? '$count mục',
        icon: icon,
        coverImageAsset: (map['cover_image_asset'] as String?) ??
            (cat == 'exercises'
                ? 'assets/images/workout.jpg'
                : 'assets/images/nutrition.jpg'),
        routeDescription: map['route_description'] as String?,
        count: count,
        category: cat,
      );
    }).toList();
  }

  @override
  Future<JournalGuidedSeries?> getGuidedSeries() async {
    final response = await dio.get('/api/journal/guided-series');
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to fetch guided series: HTTP ${response.statusCode}',
      );
    }
    final data = response.data as Map<String, dynamic>;
    final rawSeries = data['series'] as Map<String, dynamic>?;
    if (rawSeries == null) return null;

    final rawLessons = (rawSeries['lessons'] as List<dynamic>?) ?? [];
    final lessons = rawLessons
        .map((l) => _parseArticle(l as Map<String, dynamic>))
        .toList();

    return JournalGuidedSeries(
      id: (rawSeries['id'] as String?) ?? 'series_foundation',
      title: (rawSeries['title'] as String?) ?? 'Bắt đầu cùng Saman',
      subtitle: (rawSeries['subtitle'] as String?) ?? '',
      badgeLabel: (rawSeries['badge_label'] as String?) ?? 'Chuỗi hướng dẫn',
      totalLessons: (rawSeries['total_lessons'] as int?) ?? lessons.length,
      coverImageAsset: (rawSeries['cover_image_asset'] as String?) ??
          'assets/images/home_hero_leg_day.jpg',
      lessons: lessons,
    );
  }

  JournalArticle _parseArticle(Map<String, dynamic> json) {
    return JournalArticle(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      summary: (json['summary'] as String?) ?? '',
      topic: JournalTopic.fromId((json['topic'] as String?) ?? 'recovery'),
      readTimeMinutes: (json['read_time_minutes'] as int?) ?? 5,
      coverImageAsset: (json['cover_image_asset'] as String?) ??
          'assets/images/home_journal_recovery.jpg',
      badgeLabel: json['badge_label'] as String?,
      isFeatured: (json['is_featured'] as bool?) ?? false,
      contentBody: json['content_body'] as String?,
      isBookmarked: (json['is_bookmarked'] as bool?) ?? false,
    );
  }

  JournalSearchResultItem _parseSearchItem(Map<String, dynamic> json) {
    final catId = (json['category'] as String?) ?? 'all';
    final category = JournalSearchCategory.fromId(catId);

    IconData? icon;
    switch (category) {
      case JournalSearchCategory.articles:
        icon = Icons.menu_book_rounded;
        break;
      case JournalSearchCategory.exercises:
        icon = Icons.fitness_center_rounded;
        break;
      case JournalSearchCategory.foods:
        icon = Icons.restaurant_rounded;
        break;
      case JournalSearchCategory.recipes:
        icon = Icons.receipt_long_rounded;
        break;
      case JournalSearchCategory.all:
        icon = Icons.search_rounded;
        break;
    }

    return JournalSearchResultItem(
      id: (json['id'] as String?) ?? '',
      category: category,
      title: (json['title'] as String?) ?? '',
      subtitle: (json['subtitle'] as String?) ?? '',
      badgeText: json['badge_text'] as String?,
      metricText: json['metric_text'] as String?,
      readTimeMinutes: json['read_time_minutes'] as int?,
      imageAsset: json['image_asset'] as String?,
      icon: icon,
      isVerified: (json['is_verified'] as bool?) ?? false,
      detailDescription: json['detail_description'] as String?,
    );
  }
}
