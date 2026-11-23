import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/api_config.dart';
import 'package:health_ai_app/config/app_translations.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/community/data/datasources/community_dm_ws_service.dart';
import 'package:health_ai_app/features/community/data/datasources/community_fake_datasource.dart';
import 'package:health_ai_app/features/community/data/datasources/community_remote_datasource.dart';
import 'package:health_ai_app/features/community/data/repositories/community_repository_impl.dart';
import 'package:health_ai_app/features/community/domain/models/community_settings.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_dm_provider.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_social_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/settings/community_settings_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/stories/community_story_archive_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/stories/community_story_viewer_screen.dart';
import 'package:health_ai_app/features/community/presentation/widgets/community_blocked_muted_sheet.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDio extends Mock implements Dio {}

class _TestHttpOverrides extends HttpOverrides {
  static final List<int> _transparentPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _FakeHttpClient(_transparentPng);
  }
}

class _FakeHttpClient implements HttpClient {
  final List<int> _bytes;
  _FakeHttpClient(this._bytes);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(_bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientRequest implements HttpClientRequest {
  final List<int> _bytes;
  _FakeHttpClientRequest(this._bytes);

  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse(_bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final List<int> _bytes;
  _FakeHttpClientResponse(this._bytes);

  @override
  int get statusCode => 200;

  @override
  int get contentLength => _bytes.length;

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
    return Stream<List<int>>.fromIterable([_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoopDmWsService extends CommunityDmWsService {
  @override
  Future<void> connect({String? token}) async {}

  @override
  void sendTyping(String conversationId, bool isTyping) {}

  @override
  Future<void> disconnect() async {}
}

Widget _wrapTestApp({
  required Widget child,
  required CommunityFakeDatasource fakeDatasource,
  ThemeMode themeMode = ThemeMode.dark,
  Locale locale = const Locale('vi'),
}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: [
      useRemoteCommunityProvider.overrideWith((ref) => false),
      communityFakeDatasourceProvider.overrideWithValue(fakeDatasource),
      communityDmWsServiceProvider.overrideWithValue(_NoopDmWsService()),
    ],
    child: MaterialApp(
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      onGenerateRoute: AppRoutes.onGenerateRoute,
      home: child,
    ),
  );
}

void main() {
  HttpOverrides? previousOverrides;

  setUpAll(() {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _TestHttpOverrides();
    registerFallbackValue(RequestOptions(path: ''));
    registerFallbackValue(Options());
  });

  tearDownAll(() {
    HttpOverrides.global = previousOverrides;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'language_mode': 'vi',
      'language_code': 'vi',
    });
    CommunityFakeDatasource.resetStorage();
  });

  group('Phase 3 Domain & API Contract', () {
    test('CommunitySettings.fromJson is backward-compatible with legacy payload', () {
      final legacy = CommunitySettings.fromJson({
        'is_private_account': true,
        'who_can_dm': 'followers',
        'who_can_comment': 'nobody',
        'hide_like_counts': true,
        'show_activity_status': false,
      });

      expect(legacy.isPrivateAccount, isTrue);
      expect(legacy.whoCanDm, 'followers');
      expect(legacy.whoCanComment, 'nobody');
      expect(legacy.whoCanReplyStory, 'everyone');
      expect(legacy.allowMentions, 'everyone');
      expect(legacy.hideLikeCounts, isTrue);
      expect(legacy.showActivityStatus, isFalse);
      expect(legacy.autoPromptShareWorkout, isTrue);
      expect(legacy.autoPromptShareMeal, isTrue);
      expect(legacy.mutedKeywords, isEmpty);

      final full = CommunitySettings.fromJson({
        'is_private_account': false,
        'who_can_dm': 'everyone',
        'who_can_comment': 'followers',
        'who_can_reply_story': 'nobody',
        'allow_mentions': 'followers',
        'hide_like_counts': false,
        'show_activity_status': true,
        'auto_prompt_share_workout': false,
        'auto_prompt_share_meal': false,
        'muted_keywords': ['spam'],
      });
      expect(full.whoCanReplyStory, 'nobody');
      expect(full.allowMentions, 'followers');
      expect(full.autoPromptShareWorkout, isFalse);
      expect(full.autoPromptShareMeal, isFalse);
      expect(full.mutedKeywords, ['spam']);

      final serialized = full.toJson();
      expect(serialized['who_can_reply_story'], 'nobody');
      expect(serialized['allow_mentions'], 'followers');
      expect(serialized['auto_prompt_share_workout'], isFalse);
      expect(serialized['auto_prompt_share_meal'], isFalse);
    });

    test('PATCH /api/community/settings & GET /api/community/stories/archive via Mock Dio', () async {
      final mockDio = _MockDio();
      final ds = CommunityRemoteDatasourceImpl(dio: mockDio);
      final repo = CommunityRepositoryImpl(
        remoteDatasource: ds,
        useRemote: true,
        activeUserId: 'user_me',
      );

      when(
        () => mockDio.patch(
          '/api/community/settings',
          data: {
            'who_can_reply_story': 'followers',
            'allow_mentions': 'nobody',
            'auto_prompt_share_workout': false,
            'auto_prompt_share_meal': true,
          },
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/community/settings'),
          statusCode: 200,
          data: {
            'is_private_account': false,
            'who_can_dm': 'everyone',
            'who_can_comment': 'everyone',
            'who_can_reply_story': 'followers',
            'allow_mentions': 'nobody',
            'hide_like_counts': false,
            'show_activity_status': true,
            'auto_prompt_share_workout': false,
            'auto_prompt_share_meal': true,
            'muted_keywords': <String>[],
          },
        ),
      );

      final updated = await repo.updateSettings(
        whoCanReplyStory: 'followers',
        allowMentions: 'nobody',
        autoPromptShareWorkout: false,
        autoPromptShareMeal: true,
      );
      expect(updated.whoCanReplyStory, 'followers');
      expect(updated.allowMentions, 'nobody');
      expect(updated.autoPromptShareWorkout, isFalse);
      expect(updated.autoPromptShareMeal, isTrue);

      when(
        () => mockDio.get(
          '/api/community/stories/archive',
          queryParameters: {
            'include_active': true,
            'limit': 30,
          },
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/community/stories/archive'),
          statusCode: 200,
          data: {
            'items': [
              {
                'id': 'arch_1',
                'author_id': 'user_me',
                'media_type': 'photo',
                'media_url': '/static/community/arch1.jpg',
                'caption': 'Leg Day PR',
                'privacy': 'public',
                'created_at': '2026-11-20T08:00:00Z',
                'expires_at': '2026-11-21T08:00:00Z',
                'time_ago': '3 ngày trước',
                'view_count': 24,
                'is_viewed': true,
                'is_expired': true,
              },
            ],
            'next_cursor': 'cursor_2',
            'total_count': 1,
          },
        ),
      );

      final archive = await repo.getArchivedStories(includeActive: true);
      expect(archive.items.length, 1);
      expect(archive.items.first.id, 'arch_1');
      expect(archive.items.first.isExpired, isTrue);
      expect(archive.items.first.viewCount, 24);
      expect(
        archive.items.first.mediaUrl,
        '${ApiConfig.baseUrl}/static/community/arch1.jpg',
      );
      expect(archive.nextCursor, 'cursor_2');
      expect(archive.totalCount, 1);
    });

    test('AppTranslations provides EN & VI keys for Phase 3 Settings & Story Archive', () {
      const keys = [
        'community_settings_section_interactions',
        'community_settings_section_what_you_see',
        'community_settings_section_archive_activity',
        'community_settings_section_saman_sync',
        'community_settings_section_safety',
        'community_settings_who_can_reply_story',
        'community_settings_allow_mentions',
        'community_settings_auto_prompt_workout',
        'community_settings_auto_prompt_meal',
        'community_settings_privacy_by_design',
        'community_story_archive_title',
        'community_story_archive_empty_title',
      ];
      for (final k in keys) {
        final en = AppTranslations.text(k, const Locale('en'));
        final vi = AppTranslations.text(k, const Locale('vi'));
        expect(en, isNotEmpty);
        expect(vi, isNotEmpty);
        expect(en, isNot(equals(k)));
        expect(vi, isNot(equals(k)));
      }
    });
  });

  group('Phase 3 CommunitySettingsScreen (Instagram Dark/Light)', () {
    testWidgets(
      'Renders all 5 IG sections in Light & Dark and syncs Saman toggles',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          final fake = CommunityFakeDatasource(currentUserId: 'author_linh');
          await tester.pumpWidget(
            _wrapTestApp(
              fakeDatasource: fake,
              themeMode: mode,
              child: const CommunitySettingsScreen(),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          // Section 1
          expect(
            find.text('CÁCH NGƯỜI KHÁC TƯƠNG TÁC VỚI BẠN'),
            findsOneWidget,
          );
          expect(find.text('Ai có thể trả lời Story'), findsOneWidget);
          expect(find.text('Gắn thẻ & Nhắc tên'), findsOneWidget);

          // Section 2
          expect(find.text('NỘI DUNG BẠN NHÌN THẤY'), findsOneWidget);

          // Scroll down to inspect Sections 3, 4, 5
          final scrollable = find.byType(Scrollable).first;
          await tester.scrollUntilVisible(
            find.text('KHO LƯU TRỮ & HOẠT ĐỘNG CỦA BẠN'),
            220,
            scrollable: scrollable,
          );
          expect(find.text('KHO LƯU TRỮ & HOẠT ĐỘNG CỦA BẠN'), findsOneWidget);
          expect(find.text('Kho lưu trữ Tin 24h'), findsOneWidget);

          await tester.scrollUntilVisible(
            find.text('ĐỒNG BỘ HỆ SINH THÁI SAMAN'),
            220,
            scrollable: scrollable,
          );
          expect(find.text('ĐỒNG BỘ HỆ SINH THÁI SAMAN'), findsOneWidget);

          await tester.scrollUntilVisible(
            find.text('Gợi ý chia sẻ bữa ăn'),
            220,
            scrollable: scrollable,
          );
          expect(find.text('Gợi ý chia sẻ sau buổi tập'), findsOneWidget);
          expect(find.text('Gợi ý chia sẻ bữa ăn'), findsOneWidget);

          await tester.scrollUntilVisible(
            find.text('Tài khoản đã chặn'),
            220,
            scrollable: scrollable,
          );
          expect(find.text('AN TOÀN'), findsOneWidget);
          expect(find.text('Tài khoản đã chặn'), findsOneWidget);

          // Toggle Saman workout auto-prompt switch
          final workoutSwitch = find.byKey(
            const ValueKey('settings-auto-workout-switch'),
          );
          await tester.scrollUntilVisible(
            workoutSwitch,
            -200,
            scrollable: scrollable,
          );
          await tester.ensureVisible(workoutSwitch);
          await tester.pumpAndSettle();
          await tester.tap(workoutSwitch);
          await tester.pumpAndSettle();
          expect(fake.getSettings().autoPromptShareWorkout, isFalse);

          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'Adds & removes muted keyword (max 50) and updates fake datasource',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fake = CommunityFakeDatasource(currentUserId: 'author_linh');
        await tester.pumpWidget(
          _wrapTestApp(
            fakeDatasource: fake,
            themeMode: ThemeMode.dark,
            child: const CommunitySettingsScreen(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final addBtn = find.byKey(const ValueKey('add-muted-keyword-btn'));
        await tester.scrollUntilVisible(
          addBtn,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(addBtn);
        await tester.pumpAndSettle();
        expect(find.text('0/50'), findsOneWidget);

        await tester.tap(addBtn);
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'quảng cáo');
        await tester.tap(find.text('Thêm'));
        await tester.pumpAndSettle();

        expect(find.text('1/50'), findsOneWidget);
        expect(find.text('quảng cáo'), findsOneWidget);
        expect(fake.getSettings().mutedKeywords, ['quảng cáo']);

        final removeBtn = find.byKey(const ValueKey('remove-keyword-quảng cáo'));
        await tester.ensureVisible(removeBtn);
        await tester.pumpAndSettle();
        await tester.tap(removeBtn);
        await tester.pumpAndSettle();

        expect(find.text('0/50'), findsOneWidget);
        expect(fake.getSettings().mutedKeywords, isEmpty);
      },
    );

    testWidgets(
      'Navigates to CommunityStoryArchiveScreen and opens Blocked sheet',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fake = CommunityFakeDatasource(currentUserId: 'author_linh');
        await tester.pumpWidget(
          _wrapTestApp(
            fakeDatasource: fake,
            themeMode: ThemeMode.dark,
            child: const CommunitySettingsScreen(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Open Blocked sheet first
        await tester.scrollUntilVisible(
          find.text('Tài khoản đã chặn'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Tài khoản đã chặn'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tài khoản đã chặn'));
        await tester.pumpAndSettle();
        expect(find.byType(CommunityBlockedMutedSheet), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        // Navigate to Story Archive via AppRoutes.communityStoryArchive
        await tester.scrollUntilVisible(
          find.text('Kho lưu trữ Tin 24h'),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Kho lưu trữ Tin 24h'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kho lưu trữ Tin 24h'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(CommunityStoryArchiveScreen), findsOneWidget);
      },
    );
  });

  group('Phase 3 CommunityStoryArchiveScreen (Dark/Light)', () {
    testWidgets(
      'Renders 3-column grid with viewCount, supports includeActive toggle & opens viewer',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          final fake = CommunityFakeDatasource(currentUserId: 'author_linh');
          fake.createStory(mediaType: 'text', caption: 'Active 24h run');

          await tester.pumpWidget(
            _wrapTestApp(
              fakeDatasource: fake,
              themeMode: mode,
              child: const CommunityStoryArchiveScreen(),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.text('Kho lưu trữ Tin 24h'), findsOneWidget);
          expect(find.text('42'), findsOneWidget);
          expect(find.text('19'), findsOneWidget);
          expect(find.text('68'), findsOneWidget);
          expect(find.text('Active 24h run'), findsNothing);

          // Toggle includeActive to see active story
          await tester.tap(find.byType(Switch));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.text('Active 24h run'), findsOneWidget);
          expect(find.text('Đang hiện'), findsOneWidget);

          // Tap first tile to open CommunityStoryViewerScreen
          await tester.tap(find.text('Active 24h run'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(CommunityStoryViewerScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'Renders empty state when no archived stories exist',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fake = CommunityFakeDatasource(currentUserId: 'author_linh')
          ..clearArchivedStories();

        await tester.pumpWidget(
          _wrapTestApp(
            fakeDatasource: fake,
            themeMode: ThemeMode.dark,
            child: const CommunityStoryArchiveScreen(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Chưa có Tin nào được lưu trữ'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
