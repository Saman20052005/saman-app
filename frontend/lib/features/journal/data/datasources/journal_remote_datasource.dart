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
