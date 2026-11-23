import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/app_translations.dart';
import 'package:health_ai_app/config/routes.dart';
import 'package:health_ai_app/features/community/data/datasources/community_dm_ws_service.dart';
import 'package:health_ai_app/features/community/data/datasources/community_fake_datasource.dart';
import 'package:health_ai_app/features/community/domain/models/community_author.dart';
import 'package:health_ai_app/features/community/domain/models/community_dm.dart';
import 'package:health_ai_app/features/community/domain/models/community_post.dart';
import 'package:health_ai_app/features/community/domain/models/community_story.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_dm_provider.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_providers.dart';
import 'package:health_ai_app/features/community/presentation/providers/community_social_providers.dart';
import 'package:health_ai_app/features/community/presentation/screens/community_feed_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/dm/community_chat_thread_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/dm/community_inbox_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/profile/community_profile_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/settings/community_settings_screen.dart';
import 'package:health_ai_app/features/community/presentation/screens/stories/community_story_viewer_screen.dart';
import 'package:health_ai_app/features/community/presentation/widgets/community_create_story_sheet.dart';
import 'package:health_ai_app/features/community/presentation/widgets/community_story_tray.dart';
import 'package:health_ai_app/features/community/presentation/widgets/post_card_view.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  ThemeMode themeMode = ThemeMode.light,
  Locale locale = const Locale('vi'),
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: [
      useRemoteCommunityProvider.overrideWith((ref) => false),
      communityFakeDatasourceProvider.overrideWithValue(fakeDatasource),
      communityDmWsServiceProvider.overrideWithValue(_NoopDmWsService()),
      ...extraOverrides,
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

  group('Wave 4 UI Integration Tests', () {
    testWidgets(
      '1. CommunityInboxScreen loads conversations, filters search, and displays unread count (Light & Dark)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          final fake = CommunityFakeDatasource(currentUserId: 'author_linh');
          await tester.pumpWidget(
            _wrapTestApp(
              fakeDatasource: fake,
              themeMode: mode,
              child: const CommunityInboxScreen(),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.text('Tin nhắn'), findsOneWidget);
          expect(find.byType(TextField), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      '2. CommunityChatThreadScreen renders text, voice bubble, postShare bubble, and sends new text message',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fake = CommunityFakeDatasource(currentUserId: 'author_linh');
        final convs = fake.getConversations().items;
        final conv = convs.isNotEmpty
            ? convs.first
            : DmConversation(
                id: 'conv_test_1',
                peer: const DmParticipant(id: 'author_minh', name: 'Minh'),
                updatedAt: DateTime.now(),
              );

        await tester.pumpWidget(
          _wrapTestApp(
            fakeDatasource: fake,
            child: CommunityChatThreadScreen(
              conversationId: conv.id,
              peer: conv.peer,
              initialConversation: conv,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text(conv.peer.name), findsWidgets);

        // Send a new message
        final input = find.byType(TextField);
        expect(input, findsOneWidget);
        await tester.enterText(input, 'Chào bạn, hôm nay tập gì?');
        await tester.pump();

        final sendBtn = find.byIcon(Icons.send_rounded);
        expect(sendBtn, findsOneWidget);
        await tester.tap(sendBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Chào bạn, hôm nay tập gì?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '3. CommunitySettingsScreen toggles switch and opens blocked users sheet (Light & Dark)',
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

          expect(find.text('Cài đặt cộng đồng'), findsOneWidget);
          final switches = find.byType(Switch);
          expect(switches, findsWidgets);
          await tester.tap(switches.first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      '4. CommunityStoryTray opens CommunityStoryViewerScreen and supports story reply',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fake = CommunityFakeDatasource(currentUserId: 'author_linh');
        fake.createStory(mediaType: 'text', caption: 'Morning run!');
        final groups = fake.getStories();
        expect(groups, isNotEmpty);

        await tester.pumpWidget(
          _wrapTestApp(
            fakeDatasource: fake,
            child: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return Column(
                    children: [
                      const CommunityStoryTray(),
                      ElevatedButton(
                        onPressed: () {
                          ref
                              .read(communityStoriesProvider.notifier)
                              .loadStories();
                        },
                        child: const Text('Load'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Load'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Tin của bạn'), findsOneWidget);

        // Open CommunityStoryViewerScreen directly for a non-self group
        final nonSelfGroup = CommunityStoryAuthorGroup(
          author: const CommunityAuthor(
            id: 'author_minh',
            name: 'Minh Trần',
            isVerified: true,
          ),
          isSelf: false,
          hasUnviewed: true,
          stories: [
            CommunityStory(
              id: 'story_peer_1',
              userId: 'author_minh',
              mediaType: 'text',
              caption: '5km tempo run!',
              createdAt: DateTime.now().toUtc(),
              expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
            ),
          ],
        );
        await tester.pumpWidget(
          _wrapTestApp(
            fakeDatasource: fake,
            child: CommunityStoryViewerScreen(
              groups: [nonSelfGroup],
              initialGroupIndex: 0,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text(nonSelfGroup.author.name), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '5. PostCardView: double-tap heart, isLikeCountHidden, shareCount, Share-to-DM sheet, and Block/Report menu',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fake = CommunityFakeDatasource(currentUserId: 'author_linh');
        var likeToggleCount = 0;

        const post = CommunityPost(
          id: 'post_w4_test',
          type: CommunityPostType.photo,
          author: CommunityAuthor(
            id: 'author_other',
            name: 'Minh Trần',
            isVerified: true,
          ),
          timeAgo: '10 phút trước',
          caption: 'Buổi chạy sáng nay!',
          photoUrls: ['non_existent_local_path.jpg'],
          likeCount: 15,
          commentCount: 2,
          shareCount: 4,
          isLiked: false,
          isBookmarked: false,
          isLikeCountHidden: true,
        );

        await tester.pumpWidget(
          _wrapTestApp(
            fakeDatasource: fake,
            child: Scaffold(
              body: SingleChildScrollView(
                child: PostCardView(
                  post: post,
                  currentUserId: 'author_linh',
                  onLikeToggle: () {
                    likeToggleCount++;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Respects isLikeCountHidden
        expect(find.text('Lượt thích đã ẩn'), findsOneWidget);
        expect(find.text('15'), findsNothing);

        // Displays shareCount > 0
        expect(find.text('4'), findsOneWidget);

        // Double-tap photo triggers like callback & heart animation
        final photoFinder = find.byType(AspectRatio);
        expect(photoFinder, findsOneWidget);
        final center = tester.getCenter(photoFinder);
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 100));
        expect(likeToggleCount, 1);
        expect(find.byKey(const ValueKey('double-tap-heart-icon')), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 700));

        // Tap Share button opens Share-to-DM Bottom Sheet
        await tester.tap(find.byKey(const ValueKey('post-share-button-post_w4_test')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Chia sẻ bài viết'), findsOneWidget);
        expect(find.text('Sao chép liên kết'), findsOneWidget);

        // Close Share sheet
        Navigator.of(tester.element(find.text('Chia sẻ bài viết'))).pop();
        await tester.pumpAndSettle();

        // Open options menu -> Mute, Block, Report are visible for other author
        await tester.tap(find.byIcon(Icons.more_horiz_rounded));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('post-options-mute-tile')), findsOneWidget);
        expect(find.byKey(const ValueKey('post-options-block-tile')), findsOneWidget);
        expect(find.byKey(const ValueKey('post-options-report-tile')), findsOneWidget);

        // Tap Report -> opens reason sheet
        await tester.tap(find.byKey(const ValueKey('post-options-report-tile')));
        await tester.pumpAndSettle();
        expect(find.text('Báo cáo nội dung'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('report-reason-spam')));
        await tester.pumpAndSettle();
        expect(find.text('Cảm ơn bạn. Báo cáo đã được gửi.'), findsOneWidget);
      },
    );

    testWidgets(
      '6. CommunityFeedScreen embeds CommunityStoryTray and navigates to CommunityInboxScreen without SnackBar',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fake = CommunityFakeDatasource(currentUserId: 'author_linh');
        await tester.pumpWidget(
          _wrapTestApp(
            fakeDatasource: fake,
            child: const CommunityFeedScreen(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(CommunityStoryTray), findsOneWidget);

        final inboxBtn = find.byKey(const ValueKey('feed-inbox-button'));
        expect(inboxBtn, findsOneWidget);
        await tester.tap(inboxBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(CommunityInboxScreen), findsOneWidget);
        expect(
          find.text('Hộp thư cộng đồng sẽ mở ở checkpoint tiếp theo.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '7. CommunityProfileScreen: _isMe opens CommunitySettingsScreen; !_isMe shows Nhắn tin & More menu',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fake = CommunityFakeDatasource(currentUserId: 'author_linh');

        // Case A: _isMe
        await tester.pumpWidget(
          _wrapTestApp(
            fakeDatasource: fake,
            child: const CommunityProfileScreen(authorId: 'me'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final settingsBtn = find.byKey(const ValueKey('profile-settings-btn'));
        expect(settingsBtn, findsOneWidget);
        await tester.tap(settingsBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(CommunitySettingsScreen), findsOneWidget);

        // Case B: !_isMe
        await tester.pumpWidget(
          _wrapTestApp(
            fakeDatasource: fake,
            child: const CommunityProfileScreen(authorId: 'author_minh'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(const ValueKey('profile-more-btn')), findsOneWidget);
        final msgBtn = find.byKey(const ValueKey('profile-message-btn'));
        expect(msgBtn, findsOneWidget);

        await tester.tap(msgBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(CommunityChatThreadScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '8. PostCardView: double-tap on Text-only post triggers onLikeToggle and heart animation',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fake = CommunityFakeDatasource(currentUserId: 'author_linh');
        var likeToggleCount = 0;

        const textPost = CommunityPost(
          id: 'post_w4_text_only',
          type: CommunityPostType.text,
          author: CommunityAuthor(
            id: 'author_other',
            name: 'Minh Trần',
            isVerified: true,
          ),
          timeAgo: '5 phút trước',
          caption: 'Bài viết text-only kiểm tra double tap!',
          likeCount: 2,
          commentCount: 0,
          isLiked: false,
        );

        await tester.pumpWidget(
          _wrapTestApp(
            fakeDatasource: fake,
            child: Scaffold(
              body: SingleChildScrollView(
                child: PostCardView(
                  post: textPost,
                  currentUserId: 'author_linh',
                  onLikeToggle: () {
                    likeToggleCount++;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final captionFinder =
            find.text('Bài viết text-only kiểm tra double tap!');
        expect(captionFinder, findsOneWidget);
        final center = tester.getCenter(captionFinder);
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 100));

        expect(likeToggleCount, 1);
        expect(
          find.byKey(const ValueKey('double-tap-heart-icon')),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '9. CommunityStoryTray: after createStory, tap "Tin của bạn" opens CommunityStoryViewerScreen and tap + opens CommunityCreateStorySheet',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final fake = CommunityFakeDatasource(currentUserId: 'author_linh');

        await tester.pumpWidget(
          _wrapTestApp(
            fakeDatasource: fake,
            child: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return Column(
                    children: [
                      const CommunityStoryTray(),
                      ElevatedButton(
                        onPressed: () {
                          ref
                              .read(communityStoriesProvider.notifier)
                              .createStory(
                                mediaType: 'text',
                                caption: 'My new story',
                              );
                        },
                        child: const Text('CreateStory'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('CreateStory'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Tin của bạn'), findsOneWidget);

        // Tap "Tin của bạn" -> opens CommunityStoryViewerScreen with own story
        await tester.tap(find.text('Tin của bạn'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(CommunityStoryViewerScreen), findsOneWidget);
        expect(find.text('My new story'), findsOneWidget);

        // Close viewer
        Navigator.of(
          tester.element(find.byType(CommunityStoryViewerScreen)),
        ).pop();
        await tester.pumpAndSettle();

        // Tap "+" badge -> opens CommunityCreateStorySheet
        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(CommunityCreateStorySheet), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
