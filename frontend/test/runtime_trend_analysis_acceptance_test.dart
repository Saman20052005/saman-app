import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat/widgets/history_analytics_sheet.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_action_row.dart';
import 'package:health_ai_app/screens/chat_screen.dart';
import 'package:health_ai_app/screens/profile_screen.dart';
import 'package:health_ai_app/services/analytics_service.dart';

Future<void> _loadTestFonts() async {
  final packageConfigFile = File('.dart_tool/package_config.json').absolute;
  final config = jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
  final packages = config['packages'] as List<dynamic>;
  final flutterPackage = packages
      .cast<Map<String, dynamic>>()
      .singleWhere((package) => package['name'] == 'flutter');
  final flutterRoot = Directory.fromUri(
    packageConfigFile.uri.resolve(flutterPackage['rootUri'] as String),
  );
  final sdkRoot = flutterRoot.parent.parent;
  final fontDirectory = Directory.fromUri(
    sdkRoot.uri.resolve('bin/cache/artifacts/material_fonts/'),
  );

  Future<ByteData> readFont(String name) async {
    final file = File.fromUri(fontDirectory.uri.resolve(name));
    return ByteData.sublistView(await file.readAsBytes());
  }

  for (final family in ['Roboto', 'Inter']) {
    final fontLoader = FontLoader(family);
    for (final name in [
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
      'Roboto-Italic.ttf',
    ]) {
      fontLoader.addFont(readFont(name));
    }
    await fontLoader.load();
  }

  final iconFont = FontLoader('MaterialIcons')
    ..addFont(readFont('MaterialIcons-Regular.otf'));
  await iconFont.load();
}

Future<void> _captureScreenPng(WidgetTester tester, String outputPath) async {
  await tester.runAsync(() async {
    final boundary =
        tester.allRenderObjects.whereType<RenderRepaintBoundary>().firstOrNull;
    if (boundary != null) {
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final buffer = byteData.buffer.asUint8List();
        final file = File(outputPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(buffer);

        // Also duplicate to brain artifact dir for immediate report embedding
        const artifactDir =
            'C:/Users/GL/.gemini/antigravity/brain/8c3bc196-eb01-4a85-9800-fccc4ce6d672/trend_analysis_stitch';
        final fileName = outputPath.split(RegExp(r'[/\\]')).last;
        final artifactFile = File('$artifactDir/$fileName');
        await artifactFile.parent.create(recursive: true);
        await artifactFile.writeAsBytes(buffer);
      }
    }
  });
}

class _AcceptanceProfileNotifier extends StateNotifier<ProfileState>
    implements ProfileNotifier {
  _AcceptanceProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AcceptanceChatNotifier extends StateNotifier<ChatState>
    implements ChatController {
  _AcceptanceChatNotifier({ChatState? initialState})
      : super(
          initialState ??
              ChatState(
                messages: [
                  ChatMessage(
                    role: 'assistant',
                    content:
                        'Chào bạn! Tôi là Saman Coach. Hôm nay bạn muốn xem xu hướng hay phân tích nhật ký nào?',
                  ),
                ],
                recentConversations: [
                  ChatConversationSummary(
                    id: 'active-thread',
                    title: 'Kế hoạch dinh dưỡng',
                    updatedAt: DateTime.now().toIso8601String(),
                  ),
                ],
                activeConversationId: 'active-thread',
              ),
        );

  AnalyticsQuote? lastExecutedQuote;

  @override
  Future<void> loadConversations({bool loadLatest = false}) async {}

  @override
  Future<String> executeHistoryAnalytics(AnalyticsQuote quote) async {
    lastExecutedQuote = quote;
    return 'Đã hoàn thành phân tích xu hướng cho ${quote.rangeDays} ngày qua.';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockPreflightAnalyticsService extends AnalyticsService {
  _MockPreflightAnalyticsService(this.quoteBuilder);

  final Future<AnalyticsQuote> Function(int rangeDays) quoteBuilder;

  @override
  Future<AnalyticsQuote> getPreflightQuote(int rangeDays) {
    return quoteBuilder(rangeDays);
  }
}

void main() {
  setUpAll(_loadTestFonts);

  const evidenceDir =
      'D:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/runtime_evidence/trend_analysis';

  group('Runtime Acceptance · Redesign Phân tích xu hướng', () {
    testWidgets(
        '1. Runtime Flow from AI Chat -> Sheet: Frame 1 (With Data) Screenshot',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final chatNotifier = _AcceptanceChatNotifier();
      final service = _MockPreflightAnalyticsService((rangeDays) async {
        final active = rangeDays == 7 ? 5 : (rangeDays == 14 ? 12 : 24);
        final meals = rangeDays == 7 ? 18 : (rangeDays == 14 ? 38 : 82);
        final workouts = rangeDays == 7 ? 6 : (rangeDays == 14 ? 14 : 28);
        return AnalyticsQuote(
          quoteId: 'runtime-quote-$rangeDays',
          rangeDays: rangeDays,
          rawNutritionCount: meals,
          activeDays: active,
          workoutSessions: workouts,
          includedWorkouts: workouts,
          workoutTruncated: false,
          estimatedTokens: 500 + (active * 25) + (workouts * 35),
          quotaCost: 1,
        );
      });

      const profileEntity = ProfileEntity(height: 175, weight: 70, age: 28);
      const profileSnapshot = ProfileSnapshot(
        profile: profileEntity,
        fullName: 'Test Athlete (Saman Member)',
        email: 'test_athlete@saman.app',
      );
      final profNotifier = _AcceptanceProfileNotifier(
        ProfileState(
          profile: profileEntity,
          snapshot: profileSnapshot,
          status: ProfileStatus.ready,
        ),
      );

      final repaintKey = GlobalKey();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatControllerProvider.overrideWith((ref) => chatNotifier),
            profileProvider.overrideWith((ref) => profNotifier),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
              scaffoldBackgroundColor: SamanChatTokens.canvas,
            ),
            routes: {
              '/profile': (_) => const ProfileScreen(),
            },
            home: RepaintBoundary(
              key: repaintKey,
              child: Builder(
                builder: (context) => Scaffold(
                  body: Stack(
                    children: [
                      const ChatScreen(isTabActive: false),
                      // Positioned trigger targeting approved SamanChatActionRow builder
                      Positioned(
                        bottom: 80,
                        left: 20,
                        right: 20,
                        child: SamanChatActionRow(
                          item: SamanChatActionItem.approvedActions.last,
                          onTap: (_) {},
                          analyticsSheetBuilder: (_) => HistoryAnalyticsSheet(
                            service: service,
                            isDemo: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open from actual AI Chat action chip
      await tester.tap(find.text('Phân tích xu hướng').last);
      await tester.pumpAndSettle();

      // Verify sheet is open
      expect(find.byType(HistoryAnalyticsSheet), findsOneWidget);
      expect(find.text('Phân tích xu hướng'), findsWidgets);
      expect(find.text('18'), findsOneWidget);
      expect(find.text('bữa ăn'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('buổi tập'), findsOneWidget);
      expect(find.textContaining('5/7 ngày'), findsOneWidget);
      expect(find.text('Token ước tính'), findsOneWidget);
      expect(find.text('~835 token'), findsOneWidget);
      expect(find.text('SAMAN SẼ PHÂN TÍCH'), findsOneWidget);

      // Capture runtime screenshot Frame 1
      await _captureScreenPng(
        tester,
        '$evidenceDir/trend_analysis_runtime_frame1_data.png',
      );
    });

    testWidgets(
        '2. Runtime Flow from AI Chat -> Sheet: Frame 2 (0 Meals, 0 Workouts) Screenshot',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final chatNotifier = _AcceptanceChatNotifier();
      // Returns 0 meals and 0 workouts
      final service = _MockPreflightAnalyticsService((rangeDays) async {
        return AnalyticsQuote(
          quoteId: 'runtime-empty-$rangeDays',
          rangeDays: rangeDays,
          rawNutritionCount: 0,
          activeDays: 0,
          workoutSessions: 0,
          includedWorkouts: 0,
          workoutTruncated: false,
          estimatedTokens: 150,
          quotaCost: 1,
        );
      });

      const profileEntity = ProfileEntity(height: 175, weight: 70, age: 28);
      const profileSnapshot = ProfileSnapshot(
        profile: profileEntity,
        fullName: 'Test Athlete (Empty Account)',
        email: 'empty_athlete@saman.app',
      );
      final profNotifier = _AcceptanceProfileNotifier(
        ProfileState(
          profile: profileEntity,
          snapshot: profileSnapshot,
          status: ProfileStatus.ready,
        ),
      );

      final repaintKey = GlobalKey();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatControllerProvider.overrideWith((ref) => chatNotifier),
            profileProvider.overrideWith((ref) => profNotifier),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
              scaffoldBackgroundColor: SamanChatTokens.canvas,
            ),
            routes: {
              '/profile': (_) => const ProfileScreen(),
            },
            home: RepaintBoundary(
              key: repaintKey,
              child: Builder(
                builder: (context) => Scaffold(
                  body: Stack(
                    children: [
                      const ChatScreen(isTabActive: false),
                      Positioned(
                        bottom: 80,
                        left: 20,
                        right: 20,
                        child: SamanChatActionRow(
                          item: SamanChatActionItem.approvedActions.last,
                          onTap: (_) {},
                          analyticsSheetBuilder: (_) => HistoryAnalyticsSheet(
                            service: service,
                            isDemo: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open from actual AI Chat action chip
      await tester.tap(find.text('Phân tích xu hướng').last);
      await tester.pumpAndSettle();

      // Verify sheet is open in Frame 2 empty state
      expect(find.byType(HistoryAnalyticsSheet), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
      expect(
          find.text(
              'Chưa có nhật ký trong khoảng này. Thử chọn 14 hoặc 30 ngày.'),
          findsOneWidget);

      // Verify token estimate IS VISIBLE before confirm in live preflight flow
      expect(find.text('Token ước tính'), findsOneWidget);
      expect(find.text('~150 token'), findsOneWidget);

      // Guidance block is hidden in empty state
      expect(find.text('SAMAN SẼ PHÂN TÍCH'), findsNothing);

      // Confirm button is ENABLED according to backend policy allowing empty analytics
      final confirmBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Xác nhận phân tích'));
      expect(confirmBtn.onPressed, isNotNull);

      // Capture runtime screenshot Frame 2
      await _captureScreenPng(
        tester,
        '$evidenceDir/trend_analysis_runtime_frame2_empty.png',
      );
    });

    testWidgets(
        '3. Rapid Range Switching 7 -> 14 -> 30 days during in-flight load',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final completer7 = Completer<AnalyticsQuote>();
      final completer14 = Completer<AnalyticsQuote>();
      final completer30 = Completer<AnalyticsQuote>();

      final service = _MockPreflightAnalyticsService((rangeDays) {
        if (rangeDays == 7) return completer7.future;
        if (rangeDays == 14) return completer14.future;
        if (rangeDays == 30) return completer30.future;
        throw UnimplementedError();
      });

      final chatNotifier = _AcceptanceChatNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatControllerProvider.overrideWith((ref) => chatNotifier),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => HistoryAnalyticsSheet(
                      service: service,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Immediately switch to 14 days
      await tester.tap(find.text('14 ngày'));
      await tester.pump();

      // Immediately switch to 30 days
      await tester.tap(find.text('30 ngày'));
      await tester.pump();

      // Confirm button must be disabled
      var confirmBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Xác nhận phân tích'));
      expect(confirmBtn.onPressed, isNull);

      // Resolve 7 days (late)
      completer7.complete(AnalyticsQuote(
        quoteId: 'quote-7-delayed',
        rangeDays: 7,
        rawNutritionCount: 10,
        activeDays: 4,
        workoutSessions: 3,
        includedWorkouts: 3,
        workoutTruncated: false,
        estimatedTokens: 500,
        quotaCost: 1,
      ));
      await tester.pump();

      // Must remain disabled and not overwrite with 7 days
      confirmBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Xác nhận phân tích'));
      expect(confirmBtn.onPressed, isNull);

      // Resolve 14 days (late)
      completer14.complete(AnalyticsQuote(
        quoteId: 'quote-14-delayed',
        rangeDays: 14,
        rawNutritionCount: 20,
        activeDays: 8,
        workoutSessions: 6,
        includedWorkouts: 6,
        workoutTruncated: false,
        estimatedTokens: 1000,
        quotaCost: 1,
      ));
      await tester.pump();

      // Must remain disabled and not overwrite with 14 days
      confirmBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Xác nhận phân tích'));
      expect(confirmBtn.onPressed, isNull);

      // Resolve 30 days (current target)
      completer30.complete(AnalyticsQuote(
        quoteId: 'quote-30-active',
        rangeDays: 30,
        rawNutritionCount: 45,
        activeDays: 22,
        workoutSessions: 16,
        includedWorkouts: 16,
        workoutTruncated: false,
        estimatedTokens: 3500,
        quotaCost: 1,
      ));
      await tester.pumpAndSettle();

      // Now confirm button is enabled for 30 days
      confirmBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Xác nhận phân tích'));
      expect(confirmBtn.onPressed, isNotNull);
      expect(find.text('Dữ liệu trong 30 ngày qua'), findsOneWidget);
      expect(find.text('~3500 token'), findsOneWidget);

      // Execute request
      await tester.ensureVisible(find.text('Xác nhận phân tích'));
      await tester.tap(find.text('Xác nhận phân tích'));
      await tester.pumpAndSettle();
      expect(chatNotifier.lastExecutedQuote, isNotNull);
      expect(chatNotifier.lastExecutedQuote!.rangeDays, 30);
      expect(chatNotifier.lastExecutedQuote!.quoteId, 'quote-30-active');
    });
  });
}
