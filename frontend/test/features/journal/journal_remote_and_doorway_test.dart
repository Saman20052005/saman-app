import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/journal/data/datasources/journal_fake_datasource.dart';
import 'package:health_ai_app/features/journal/data/datasources/journal_remote_datasource.dart';
import 'package:health_ai_app/features/journal/data/repositories/journal_repository_impl.dart';
import 'package:health_ai_app/features/journal/domain/models/journal_article.dart';
import 'package:health_ai_app/features/journal/domain/models/journal_search_result.dart';
import 'package:health_ai_app/features/journal/presentation/widgets/journal_community_doorway_card.dart';

class MockDio extends Fake implements Dio {
  MockDio({required this.handler});

  final Future<Response<dynamic>> Function(RequestOptions options) handler;

  @override
  BaseOptions options = BaseOptions(baseUrl: 'http://127.0.0.1:18090');

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    final reqOptions = RequestOptions(
      path: path,
      queryParameters: queryParameters,
      baseUrl: this.options.baseUrl,
    );
    final res = await handler(reqOptions);
    return Response<T>(
      data: res.data as T,
      statusCode: res.statusCode,
      requestOptions: reqOptions,
    );
  }
}

void main() {
  group('JCOM-05-02 — Journal Remote Datasource Unit Tests', () {
    test('getFeaturedArticle parses response correctly', () async {
      final mockDio = MockDio(
        handler: (options) async {
          expect(options.path, '/api/journal/featured');
          return Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'article': {
                'id': 'art_01',
                'title': 'Test Featured Article',
                'summary': 'Summary of featured article',
                'topic': 'recovery',
                'read_time_minutes': 4,
                'cover_image_asset': 'assets/test.jpg',
                'badge_label': 'Phục hồi',
                'is_featured': true,
              }
            },
          );
        },
      );

      final ds = JournalRemoteDatasourceImpl(dio: mockDio);
      final article = await ds.getFeaturedArticle();

      expect(article, isNotNull);
      expect(article!.id, 'art_01');
      expect(article.title, 'Test Featured Article');
      expect(article.topic, JournalTopic.recovery);
      expect(article.isFeatured, isTrue);
    });

    test('getArticles passes topic and cursor parameters', () async {
      final mockDio = MockDio(
        handler: (options) async {
          expect(options.path, '/api/journal/articles');
          expect(options.queryParameters['topic'], 'nutrition');
          expect(options.queryParameters['limit'], 5);
          return Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'articles': [
                {
                  'id': 'art_nutrition_01',
                  'title': 'Nutrition Basics',
                  'summary': 'Guide to macros',
                  'topic': 'nutrition',
                  'read_time_minutes': 6,
                  'cover_image_asset': 'assets/nutrition.jpg',
                }
              ],
              'total': 1,
              'next_cursor': null,
            },
          );
        },
      );

      final ds = JournalRemoteDatasourceImpl(dio: mockDio);
      final articles = await ds.getArticles(topic: JournalTopic.nutrition, limit: 5);

      expect(articles.length, 1);
      expect(articles.first.id, 'art_nutrition_01');
      expect(articles.first.topic, JournalTopic.nutrition);
    });

    test('search parses multi-entity items and advice tip', () async {
      final mockDio = MockDio(
        handler: (options) async {
          expect(options.path, '/api/journal/search');
          expect(options.queryParameters['q'], 'protein');
          expect(options.queryParameters['category'], 'all');
          return Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'query': 'protein',
              'category': 'all',
              'items': [
                {
                  'id': 'item_article_01',
                  'category': 'articles',
                  'title': 'Protein Science',
                  'subtitle': 'MPS window',
                  'badge_text': 'Kiến thức',
                  'is_verified': true,
                },
                {
                  'id': 'item_exercise_01',
                  'category': 'exercises',
                  'title': 'Bench Press',
                  'subtitle': 'Ngực • Barbell',
                  'badge_text': 'Bài tập',
                  'metric_text': 'Giáo án',
                  'is_verified': true,
                },
                {
                  'id': 'item_food_01',
                  'category': 'foods',
                  'title': 'Ức gà',
                  'subtitle': 'Thực phẩm tự nhiên',
                  'badge_text': 'Thực phẩm',
                  'metric_text': '31g Protein',
                  'is_verified': true,
                }
              ],
              'total': 3,
              'advice_tip': {
                'id': 'tip_protein',
                'title': 'Lời khuyên dinh dưỡng',
                'content': 'Cơ thể cần 25-40g protein.',
              }
            },
          );
        },
      );

      final ds = JournalRemoteDatasourceImpl(dio: mockDio);
      final result = await ds.search(query: 'protein', category: JournalSearchCategory.all);

      expect(result.items.length, 3);
      expect(result.items[0].category, JournalSearchCategory.articles);
      expect(result.items[1].category, JournalSearchCategory.exercises);
      expect(result.items[2].category, JournalSearchCategory.foods);
      expect(result.adviceTip, isNotNull);
      expect(result.adviceTip!.id, 'tip_protein');
    });

    test('remote error strictly throws DioException without silent swallow', () async {
      final mockDio = MockDio(
        handler: (options) async {
          throw DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 503,
              data: {'detail': 'Service Unavailable'},
            ),
          );
        },
      );

      final ds = JournalRemoteDatasourceImpl(dio: mockDio);
      expect(
        () => ds.getFeaturedArticle(),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('JCOM-05-02 — JournalRepositoryImpl Remote Invariant Tests', () {
    test('when remote fails, strictly rethrows and DOES NOT fall back to fake', () async {
      final mockDio = MockDio(
        handler: (options) async {
          throw DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 500,
              data: {'detail': 'Database down'},
            ),
          );
        },
      );

      final remoteDs = JournalRemoteDatasourceImpl(dio: mockDio);
      final fakeDs = JournalFakeDatasource(); // Contains sample articles
      final repo = JournalRepositoryImpl(
        remoteDatasource: remoteDs,
        fakeDatasource: fakeDs,
      );

      expect(repo.isRemoteMode, isTrue);

      // Must throw rather than returning fake article
      expect(
        () => repo.getFeaturedArticle(),
        throwsA(isA<DioException>()),
      );

      expect(
        () => repo.search(query: 'protein'),
        throwsA(isA<DioException>()),
      );
    });

    test('when in fake mode, delegates safely to fake datasource', () async {
      final fakeDs = JournalFakeDatasource();
      final repo = JournalRepositoryImpl(fakeDatasource: fakeDs);

      expect(repo.isRemoteMode, isFalse);
      final featured = await repo.getFeaturedArticle();
      expect(featured, isNotNull);
      expect(featured!.id, 'article_leg_day_recovery');
    });
  });

  group('JCOM-05-02 — Community Doorway Navigation & Throttling Tests', () {
    setUp(() {
      JournalCommunityDoorwayCard.resetNavigationState();
    });

    testWidgets('Doorway card navigates to AppRoutes.communityFeed', (tester) async {
      String? pushedRoute;

      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (settings) {
            pushedRoute = settings.name;
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => Scaffold(body: Text('Destination: ${settings.name}')),
            );
          },
          home: const Scaffold(
            body: JournalCommunityDoorwayCard(),
          ),
        ),
      );

      await tester.tap(find.byType(JournalCommunityDoorwayCard));
      await tester.pumpAndSettle();

      expect(pushedRoute, AppRoutes.communityFeed);
      expect(find.text('Destination: /community/feed'), findsOneWidget);
    });

    testWidgets('Double-tap within 400ms is throttled to exactly 1 push', (tester) async {
      int pushCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (settings) {
            pushCount++;
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => Scaffold(
                body: Text('Push #$pushCount'),
              ),
            );
          },
          home: const Scaffold(
            body: JournalCommunityDoorwayCard(),
          ),
        ),
      );

      // Rapid double tap
      await tester.tap(find.byType(JournalCommunityDoorwayCard));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(JournalCommunityDoorwayCard), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Only 1 navigation push should have occurred
      expect(pushCount, 1);
    });
  });
}
