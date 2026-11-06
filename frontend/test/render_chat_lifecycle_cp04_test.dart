import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_snapshot.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_message_list.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

class _RenderChatNotifier extends StateNotifier<ChatState> implements ChatController {
  _RenderChatNotifier(super.initialState);

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

class _StaticProfileNotifier extends StateNotifier<ProfileState> implements ProfileNotifier {
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

Future<void> _captureRepaintPng(
    WidgetTester tester, GlobalKey repaintKey, String outputPath) async {
  await tester.runAsync(() async {
    final boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
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

ThemeData _buildTestTheme() {
  return ThemeData.dark().copyWith(
    scaffoldBackgroundColor: SamanChatTokens.canvas,
    extensions: const [
      AppThemeExtension(
        aiAccent: SamanChatTokens.greenAccent,
        primaryPressed: Color(0xFF0B7249),
        warning: Color(0xFFD97706),
        inkMuted: Color(0xFF888888),
        inkSubtle: Color(0xFF555555),
        hairline: Color(0xFF2A2A2A),
        surfaceElevated: Color(0xFF222222),
        heroNumeric: TextStyle(fontSize: 44),
        labelCaps: TextStyle(fontSize: 11),
        statValue: TextStyle(fontSize: 17),
      ),
    ],
  );
}

Widget _buildApp({
  required ChatController chatNotifier,
  required GlobalKey repaintKey,
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
      theme: _buildTestTheme(),
      home: RepaintBoundary(
        key: repaintKey,
        child: const ChatScreen(),
      ),
    ),
  );
}

void main() {
  setUpAll(_loadTestFonts);

  const evidenceDir = 'D:/SamanDev/runtime_evidence/saman-coach-series3/CP-04/20261105T114000';

  group('CP-04 · Render Suite for Saman Coach Lifecycle & Recovery', () {
    testWidgets('1. Render Turn 01 - User bubble & generating indicator', (tester) async {
      tester.view.physicalSize = const Size(412 * 2, 850 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final notifier = _RenderChatNotifier(
        ChatState(
          messages: [
            ChatMessage(
              role: 'user',
              content: 'Gợi ý cho mình bài tập ngực hiệu quả tại phòng gym',
            ),
          ],
          isLoading: true,
          activeConversationId: 'conv_chest_01',
        ),
      );

      await tester.pumpWidget(_buildApp(chatNotifier: notifier, repaintKey: repaintKey));
      await tester.pump(const Duration(milliseconds: 300));

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/turn_01_user_bubble_and_generating.png',
      );
    });

    testWidgets('2. Render Turn 02 - Assistant response & typing next draft', (tester) async {
      tester.view.physicalSize = const Size(412 * 2, 850 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final notifier = _RenderChatNotifier(
        ChatState(
          messages: [
            ChatMessage(
              role: 'user',
              content: 'Gợi ý cho mình bài tập ngực hiệu quả tại phòng gym',
            ),
            ChatMessage(
              role: 'assistant',
              content: 'Dưới đây là lịch tập ngực cơ bản nhưng rất hiệu quả cho bạn:\n\n'
                  '1. Incline Barbell Bench Press: 4 hiệp x 8-10 reps\n'
                  '2. Flat Dumbbell Press: 3 hiệp x 10-12 reps\n'
                  '3. Cable Crossover (Flyes): 3 hiệp x 12-15 reps\n'
                  '4. Dips (Xà kép chú trọng ngực dưới): 3 hiệp đến gần thất bại.\n\n'
                  'Bạn muốn mình hướng dẫn kỹ hơn về form của bài nào?',
            ),
          ],
          isLoading: false,
          activeConversationId: 'conv_chest_01',
        ),
      );

      await tester.pumpWidget(_buildApp(chatNotifier: notifier, repaintKey: repaintKey));
      await tester.pumpAndSettle();

      // Enter a next draft into composer while viewing response
      await tester.enterText(find.byType(TextField), 'Còn chế độ ăn trước và sau buổi tập ngực thì sao?');
      await tester.pump();
      await tester.pumpAndSettle();

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/turn_02_drafting_next_question.png',
      );
    });

    testWidgets('3. Render Turn 03 - Scrolled up reading position & Mới nhất button', (tester) async {
      tester.view.physicalSize = const Size(412 * 2, 850 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final manyMessages = List.generate(
        10,
        (i) => i.isEven
            ? ChatMessage(role: 'user', content: 'Câu hỏi tư vấn số $i: Phân bổ khối lượng tạ?')
            : ChatMessage(
                role: 'assistant',
                content: 'Trả lời chi tiết số $i:\nNên duy trì mức RPE 7-9 cho các hiệp chính để kích thích phì đại cơ bắp tối đa mà không gây quá tải thần kinh.',
              ),
      );

      final notifier = _RenderChatNotifier(
        ChatState(
          messages: manyMessages,
          isLoading: false,
          activeConversationId: 'conv_history_02',
        ),
      );

      await tester.pumpWidget(_buildApp(chatNotifier: notifier, repaintKey: repaintKey));
      await tester.pumpAndSettle();

      // Scroll up by 400px to read earlier message
      final scrollableFinder = find
          .descendant(
            of: find.byType(SamanMessageList),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(scrollableFinder, const Offset(0, 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/turn_03_scroll_to_bottom_button.png',
      );
    });

    testWidgets('4. Render Turn 04 - Error response with Retry and Edit question', (tester) async {
      tester.view.physicalSize = const Size(412 * 2, 850 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final notifier = _RenderChatNotifier(
        ChatState(
          messages: [
            ChatMessage(
              role: 'user',
              content: 'Tối ưu macro cho giai đoạn cut 4 tuần',
            ),
          ],
          errorMessage: "I couldn't complete that response.",
          failedUserMessage: 'Tối ưu macro cho giai đoạn cut 4 tuần',
          isLoading: false,
          activeConversationId: 'conv_macro_03',
        ),
      );

      await tester.pumpWidget(_buildApp(chatNotifier: notifier, repaintKey: repaintKey));
      await tester.pumpAndSettle();

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/turn_04_error_retry_and_edit.png',
      );
    });

    testWidgets('5. Render Turn 05 - Edit question confirmation dialog protecting draft', (tester) async {
      tester.view.physicalSize = const Size(412 * 2, 850 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final notifier = _RenderChatNotifier(
        ChatState(
          messages: [
            ChatMessage(
              role: 'user',
              content: 'Tối ưu macro cho giai đoạn cut 4 tuần',
            ),
          ],
          errorMessage: "I couldn't complete that response.",
          failedUserMessage: 'Tối ưu macro cho giai đoạn cut 4 tuần',
          isLoading: false,
          activeConversationId: 'conv_macro_03',
        ),
      );

      await tester.pumpWidget(_buildApp(chatNotifier: notifier, repaintKey: repaintKey));
      await tester.pumpAndSettle();

      // Enter an active draft in composer
      await tester.enterText(find.byType(TextField), 'Bản nháp kế hoạch dinh dưỡng mới đang gõ dở...');
      await tester.pump();
      await tester.pumpAndSettle();

      // Tap "Edit question"
      await tester.tap(find.text('Edit question'));
      await tester.pump();
      await tester.pumpAndSettle();

      await _captureRepaintPng(
        tester,
        repaintKey,
        '$evidenceDir/turn_05_edit_question_dialog.png',
      );
    });
  });
}
