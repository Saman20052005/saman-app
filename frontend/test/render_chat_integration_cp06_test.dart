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
import 'package:health_ai_app/screens/chat/widgets/saman_message_list.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

class _RenderIntegrationNotifier extends StateNotifier<ChatState>
    implements ChatController {
  _RenderIntegrationNotifier(super.initialState);

  @override
  Ref get ref => throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> sendMessage(String text) async {}

  @override
  Future<void> retry() async {}

  @override
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  @override
  void clearChat() {
    state = state.copyWith(messages: []);
  }

  @override
  void newConversation() {
    state = state.copyWith(messages: [], clearActiveConversation: true);
  }

  @override
  Future<void> loadConversations({bool loadLatest = false}) async {}

  @override
  Future<void> loadConversation(String conversationId) async {
    state = state.copyWith(activeConversationId: conversationId);
  }
}

class _StaticProfileNotifier extends StateNotifier<ProfileState>
    implements ProfileNotifier {
  _StaticProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _loadTestFonts() async {
  final packageConfigFile = File('.dart_tool/package_config.json').absolute;
  final config =
      jsonDecode(await packageConfigFile.readAsString()) as Map<String, dynamic>;
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
    ]) {
      try {
        fontLoader.addFont(readFont(name));
      } catch (_) {}
    }
    try {
      await fontLoader.load();
    } catch (_) {}
  }
}

Widget _buildRenderApp({
  required _RenderIntegrationNotifier chatNotifier,
  required GlobalKey repaintKey,
  bool disableAnimations = false,
  Size? size,
}) {
  const profileEntity = ProfileEntity(height: 175, weight: 70, age: 28);
  const profileSnapshot = ProfileSnapshot(
    profile: profileEntity,
    fullName: 'Saman Athlete',
    email: 'saman@member.app',
  );

  return ProviderScope(
    overrides: [
      chatControllerProvider.overrideWith((ref) => chatNotifier),
      profileProvider.overrideWith(
        (ref) => _StaticProfileNotifier(
          ProfileState(
            profile: profileEntity,
            snapshot: profileSnapshot,
            status: ProfileStatus.ready,
          ),
        ),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: SamanChatTokens.canvas,
      ),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            disableAnimations: disableAnimations,
            size: size ?? mq.size,
          ),
          child: child!,
        );
      },
      home: RepaintBoundary(
        key: repaintKey,
        child: const ChatScreen(isTabActive: false),
      ),
    ),
  );
}

Future<void> _captureRepaintPng(
  WidgetTester tester,
  GlobalKey key,
  String outputPath,
) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final buffer = byteData.buffer.asUint8List();
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(buffer);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const evidenceDir =
      r'D:\SamanDev\runtime_evidence\saman-coach-series3\CP-06\20261105T130000';

  setUpAll(() async {
    await _loadTestFonts();
    Directory(evidenceDir).createSync(recursive: true);
  });

  group('CP-06 · Visual Render Suite for Integration Acceptance', () {
    testWidgets('1. Render desktop expanded sidebar with navigation & tools', (tester) async {
      tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final notifier = _RenderIntegrationNotifier(
        ChatState(
          messages: [],
          isLoading: false,
          activeConversationId: 'c1',
          recentConversations: [
            ChatConversationSummary(
              id: 'c1',
              title: 'Buổi tập ngực & tay sau',
              updatedAt: DateTime.now().toIso8601String(),
            ),
            ChatConversationSummary(
              id: 'c2',
              title: 'Thực đơn thâm hụt calo',
              updatedAt: DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
            ),
          ],
        ),
      );

      await tester.pumpWidget(_buildRenderApp(
        chatNotifier: notifier,
        repaintKey: repaintKey,
        size: const Size(1024, 768),
      ));
      await tester.pumpAndSettle();

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/integration_01_desktop_sidebar_and_navigation.png',
      );
    });

    testWidgets('2. Render mobile drawer & responsive breakpoint layout', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final notifier = _RenderIntegrationNotifier(
        ChatState(
          messages: [],
          isLoading: false,
          activeConversationId: 'c1',
          recentConversations: [
            ChatConversationSummary(
              id: 'c1',
              title: 'Buổi tập ngực & tay sau',
              updatedAt: DateTime.now().toIso8601String(),
            ),
            ChatConversationSummary(
              id: 'c2',
              title: 'Thực đơn thâm hụt calo',
              updatedAt: DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
            ),
          ],
        ),
      );

      await tester.pumpWidget(_buildRenderApp(
        chatNotifier: notifier,
        repaintKey: repaintKey,
        size: const Size(390, 844),
      ));
      await tester.pumpAndSettle();

      // Open drawer
      await tester.tap(find.byTooltip('Coach Menu'));
      await tester.pumpAndSettle();

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/integration_02_mobile_drawer_and_breakpoint_resize.png',
      );
    });

    testWidgets('3. Render multiline composer & Tools popover menu', (tester) async {
      tester.view.physicalSize = const Size(400 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final notifier = _RenderIntegrationNotifier(
        ChatState(
          messages: [],
          isLoading: false,
          activeConversationId: null,
        ),
      );

      await tester.pumpWidget(_buildRenderApp(
        chatNotifier: notifier,
        repaintKey: repaintKey,
        size: const Size(400, 800),
      ));
      await tester.pumpAndSettle();

      // Enter multiline draft
      await tester.enterText(
        find.byType(TextField),
        'Tôi đã hoàn thành 4 hiệp Barbell Bench Press hôm nay.\n'
        'Mức tạ: 80kg x 8 reps mỗi hiệp (RPE 8.5).\n'
        'Hãy đánh giá khối lượng tập và gợi ý bài tập tiếp theo.',
      );
      await tester.pumpAndSettle();

      // Open tools popover
      await tester.tap(find.byTooltip('Thêm công cụ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/integration_03_composer_multiline_and_tools_popover.png',
      );
    });

    testWidgets('4. Render AI mode selector with high-contrast locked badges', (tester) async {
      tester.view.physicalSize = const Size(400 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final notifier = _RenderIntegrationNotifier(
        ChatState(
          messages: [],
          isLoading: false,
          activeConversationId: null,
        ),
      );

      await tester.pumpWidget(_buildRenderApp(
        chatNotifier: notifier,
        repaintKey: repaintKey,
        size: const Size(400, 800),
      ));
      await tester.pumpAndSettle();

      // Open mode menu
      await tester.tap(find.text('Core 3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/integration_04_ai_mode_selector_and_locked_badges.png',
      );
    });

    testWidgets('5. Render turn lifecycle, reading position & Mới nhất pill button', (tester) async {
      tester.view.physicalSize = const Size(400 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final longHistory = <ChatMessage>[
        ChatMessage(role: 'user', content: 'Kế hoạch tập ngực và tay sau hôm nay của tôi thế nào?'),
        ChatMessage(
          role: 'assistant',
          content: 'Chào bạn! Hôm nay chúng ta sẽ tập trung vào cơ ngực và tay sau với 4 bài chính:\n'
              '1. Barbell Bench Press: 4 hiệp x 8-10 reps (RPE 8)\n'
              '2. Incline Dumbbell Press: 3 hiệp x 10-12 reps\n'
              '3. Dips (Xà kép): 3 hiệp x 10-12 reps\n'
              '4. Triceps Pushdown: 3 hiệp x 12-15 reps.\n'
              'Hãy nhớ khởi động kỹ khớp vai và khuỷu tay trước khi bắt đầu nhé!',
        ),
        ChatMessage(role: 'user', content: 'Mức tạ cho Bench Press nên chọn bao nhiêu?'),
        ChatMessage(
          role: 'assistant',
          content: 'Dựa trên lịch sử buổi tập gần nhất, mức tạ gợi ý cho bạn hôm nay là 75kg - 80kg.\n'
              'Hãy bắt đầu hiệp 1 ở 75kg để cảm nhận form chuyển động, sau đó tăng dần lên 80kg nếu RPE < 8.',
        ),
        ChatMessage(role: 'user', content: 'Sau buổi tập nên nạp bao nhiêu protein?'),
        ChatMessage(
          role: 'assistant',
          content: 'Bạn nên nạp khoảng 30-35g protein trong vòng 1-2 giờ sau tập (ví dụ: 1 muỗng Whey Isolate hoặc 150g ức gà áp chảo kèm cơm trắng).',
        ),
      ];

      final notifier = _RenderIntegrationNotifier(
        ChatState(
          messages: longHistory,
          isLoading: false,
          activeConversationId: 'c1',
        ),
      );

      await tester.pumpWidget(_buildRenderApp(
        chatNotifier: notifier,
        repaintKey: repaintKey,
        size: const Size(400, 800),
      ));
      await tester.pumpAndSettle();

      // Enter a draft in composer
      await tester.enterText(find.byType(TextField), 'Buổi tối tôi có thể uống thêm sữa hạt không?');
      await tester.pump();

      // Drag scroll view up by 400px to trigger "Mới nhất" floating button
      final scrollableFinder = find.descendant(
        of: find.byType(SamanMessageList),
        matching: find.byType(Scrollable),
      ).first;
      await tester.drag(scrollableFinder, const Offset(0, 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/integration_05_turn_lifecycle_and_reading_position.png',
      );
    });

    testWidgets('6. Render error recovery & edit question confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final notifier = _RenderIntegrationNotifier(
        ChatState(
          messages: [
            ChatMessage(role: 'user', content: 'Kế hoạch dinh dưỡng sau tập của tôi?'),
          ],
          isLoading: false,
          errorMessage: "I couldn't complete that response.",
          failedUserMessage: 'Kế hoạch dinh dưỡng sau tập của tôi?',
          activeConversationId: 'c1',
        ),
      );

      await tester.pumpWidget(_buildRenderApp(
        chatNotifier: notifier,
        repaintKey: repaintKey,
        size: const Size(1024, 768),
      ));
      await tester.pumpAndSettle();

      // Type a different draft in composer
      await tester.enterText(find.byType(TextField), 'Đang soạn câu hỏi mới khác...');
      await tester.pump();

      // Tap 'Edit question' -> shows confirmation dialog
      await tester.tap(find.text('Edit question'));
      await tester.pumpAndSettle();

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/integration_06_error_recovery_retry_and_edit_question.png',
      );
    });
  });
}
