import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/api_config.dart';
import 'package:health_ai_app/features/community/data/datasources/community_remote_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_author.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_discover_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/profile/community_profile_screen.dart';
import 'package:health_ai_app/features/community/presentation/widgets/post_card_view.dart';

class Wave3MockTransport {
  final Dio dio = Dio();
  final List<Map<String, dynamic>> discoverQueries = [];
  final List<Map<String, dynamic>> postBodies = [];
  int uploadCount = 0;
  Completer<void>? holdNextDiscover;

  Wave3MockTransport() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.path == '/api/community/discover') {
            final qp = Map<String, dynamic>.from(options.queryParameters);
            discoverQueries.add(qp);
            if (holdNextDiscover != null) {
              final completer = holdNextDiscover!;
              holdNextDiscover = null;
              await completer.future;
            }
            final q = (qp['q'] as String? ?? '').toLowerCase();
            final gridItems = q == 'empty_xyz'
                ? <Map<String, dynamic>>[]
                : [
                    {
                      'id': 'grid_1',
                      'post_id': 'post_remote_1',
                      'image_url': '/static/community/grid_1.jpg',
                      'like_count': 42,
                      'has_multi_photo': true,
                      'has_video': false,
                      'alt_text': 'Morning leg day',
                    },
                  ];
            final topics = q == 'empty_xyz'
                ? <Map<String, dynamic>>[]
                : [
                    {
                      'id': 'topic_1',
                      'hashtag': '#TậpLuyện',
                      'post_count_formatted': '12 bài viết thảo luận',
                      'growth_percent': 'Ổn định',
                      'is_stable': true,
                      'icon_name': 'tag',
                    },
                  ];
            final creators = q == 'empty_xyz'
                ? <Map<String, dynamic>>[]
                : [
                    {
                      'id': 'creator_1',
                      'name': 'Coach Minh',
                      'title': 'Strength Coach',
                      'is_verified': true,
                      'follower_count': 1250,
                      'is_following': false,
                    },
                  ];
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'topic_chips': ['all', 'workout', 'meal', 'recipe', 'qna', 'journey'],
                  'active_topic': qp['topic'] ?? 'all',
                  'grid_items': gridItems,
                  'trending_topics': topics,
                  'recommended_creators': creators,
                },
              ),
            );
            return;
          }

          if (options.path == '/api/community/media/upload') {
            uploadCount++;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'media_url': '/static/community/uploaded_$uploadCount.jpg',
                  'content_type': 'image/jpeg',
                  'file_name': 'uploaded_$uploadCount.jpg',
                },
              ),
            );
            return;
          }

          if (options.path == '/api/community/posts' && options.method == 'POST') {
            final body = Map<String, dynamic>.from(options.data as Map);
            postBodies.add(body);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'id': 'post_multi_1',
                  'type': body['type'],
                  'caption': body['content'] ?? '',
                  'photo_urls': body['photo_urls'] ?? [],
                  'privacy': body['privacy'],
                  'topic': body['topic'],
                  'author': {'id': 'me', 'name': 'Linh Nguyễn'},
                  'time_ago': 'Vừa xong',
                  'like_count': 0,
                  'comment_count': 0,
                },
              ),
            );
            return;
          }

          if (options.path.startsWith('/api/community/authors/')) {
            if (options.path.endsWith('/posts')) {
              handler.resolve(
                Response(requestOptions: options, statusCode: 200, data: {'items': []}),
              );
              return;
            }
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'id': 'creator_1',
                  'name': 'Coach Minh',
                  'title': 'Strength Coach',
                  'is_verified': true,
                  'follower_count': 1250,
                  'following_count': 10,
                  'post_count': 5,
                  'is_following': false,
                },
              ),
            );
            return;
          }

          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: {'items': []}),
          );
        },
      ),
    );
  }
}

class _TestImageHttpOverrides extends HttpOverrides {
  static final Uint8List _transparentPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockPngHttpClient(_transparentPng);
  }
}

class _MockPngHttpClient implements HttpClient {
  final Uint8List bytes;
  _MockPngHttpClient(this.bytes);

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _MockPngHttpClientRequest(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockPngHttpClientRequest implements HttpClientRequest {
  final Uint8List bytes;
  _MockPngHttpClientRequest(this.bytes);

  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockPngHttpClientResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockPngHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final Uint8List bytes;
  _MockPngHttpClientResponse(this.bytes);

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wave 3: Discover & Multi-Photo Integration', () {
    test('1. CommunityRemoteDatasourceImpl.getDiscoverData parses grid, topics, creators & query params', () async {
      final transport = Wave3MockTransport();
      final ds = CommunityRemoteDatasourceImpl(dio: transport.dio);

      final data = await ds.getDiscoverData(topic: 'workout', searchQuery: '  leg day  ');

      expect(transport.discoverQueries.single['topic'], 'workout');
      expect(transport.discoverQueries.single['q'], 'leg day');
      expect(data.activeTopic, 'workout');
      expect(data.gridItems.length, 1);
      expect(
        data.gridItems.first.imageUrl,
        '${ApiConfig.baseUrl}/api/community/static/community/grid_1.jpg',
      );
      expect(data.gridItems.first.hasMultiPhoto, isTrue);
      expect(data.trendingTopics.single.hashtag, '#TậpLuyện');
      expect(data.recommendedCreators.single.id, 'creator_1');
      expect(data.recommendedCreators.single.name, 'Coach Minh');
    });

    test('2. CommunityRepositoryImpl.publishPost uploads 3 local photos and rejects >10 photos', () async {
      final transport = Wave3MockTransport();
      final ds = CommunityRemoteDatasourceImpl(dio: transport.dio);
      final repo = CommunityRepositoryImpl(remoteDatasource: ds, useRemote: true);

      final tempDir = Directory.systemTemp.createTempSync('wave3_photos_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final localPaths = List.generate(3, (i) {
        final f = File('${tempDir.path}/img_$i.jpg');
        f.writeAsBytesSync([1, 2, 3, i]);
        return f.path;
      });

      final post = await repo.publishPost(
        caption: '3-photo workout carousel',
        requestKey: 'req_wave3_3photos_001',
        mediaUrls: localPaths,
        audience: 'Công khai',
        topic: '#TậpLuyện',
      );

      expect(transport.uploadCount, 3);
      expect(transport.postBodies.single['photo_urls'], [
        '/static/community/uploaded_1.jpg',
        '/static/community/uploaded_2.jpg',
        '/static/community/uploaded_3.jpg',
      ]);
      expect(post.photoUrls.length, 3);

      expect(
        () => repo.publishPost(
          caption: 'Too many photos',
          requestKey: 'req_wave3_11photos_002',
          mediaUrls: List.generate(11, (i) => '/static/community/p_$i.jpg'),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    testWidgets('3. CommunityDiscoverScreen renders Image.network, hides banner in remote mode, debounces search, opens creator profile', (tester) async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = _TestImageHttpOverrides();
      addTearDown(() => HttpOverrides.global = previousOverrides);

      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final transport = Wave3MockTransport();
      final ds = CommunityRemoteDatasourceImpl(dio: transport.dio);
      final repo = CommunityRepositoryImpl(remoteDatasource: ds, useRemote: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            useRemoteCommunityProvider.overrideWith((ref) => true),
            communityRemoteDatasourceProvider.overrideWithValue(ds),
            communityRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            locale: Locale('vi'),
            supportedLocales: [Locale('vi'), Locale('en')],
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: CommunityDiscoverScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Preview banner is hidden when remote mode is active
      expect(find.text('Bản xem trước giao diện • Dữ liệu mẫu thử nghiệm'), findsNothing);

      // Grid renders real Image.network
      expect(find.byType(Image), findsWidgets);
      expect(find.text('Coach Minh'), findsOneWidget);

      // Debounce search: typing does not immediately fire API, fires after 300ms
      final initialQueryCount = transport.discoverQueries.length;
      await tester.enterText(find.byType(TextField), 'squat');
      await tester.pump(const Duration(milliseconds: 100));
      expect(transport.discoverQueries.length, initialQueryCount);

      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(transport.discoverQueries.length, initialQueryCount + 1);
      expect(transport.discoverQueries.last['q'], 'squat');

      // Clear search button resets query
      await tester.tap(find.byKey(const ValueKey('discover-search-clear-button')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(transport.discoverQueries.last.containsKey('q'), isFalse);

      // Tap creator opens CommunityProfileScreen
      await tester.ensureVisible(find.text('Coach Minh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coach Minh'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityProfileScreen), findsOneWidget);
    });

    testWidgets('4. PostCardView renders PageView and 1/3 counter for 3 photos', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const multiPost = CommunityPost(
        id: 'post_carousel_3',
        type: CommunityPostType.photo,
        author: CommunityAuthor(id: 'u1', name: 'Linh Nguyễn'),
        timeAgo: 'Vừa xong',
        caption: 'Carousel test',
        photoUrls: [
          'https://example.com/1.jpg',
          'https://example.com/2.jpg',
          'https://example.com/3.jpg',
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PostCardView(
                  post: multiPost,
                  onLikeToggle: () {},
                  onBookmarkToggle: () {},
                  onOpenDetail: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);
    });
  });
}
