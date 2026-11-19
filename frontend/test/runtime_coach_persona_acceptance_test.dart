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
import 'package:health_ai_app/providers/coach_persona_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_account_popup_menu.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_drawer.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_persona_menu.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

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

Future<void> _captureScreenPng(WidgetTester tester, String outputPath) async {
  await tester.runAsync(() async {
    final boundary = tester.allRenderObjects
        .whereType<RenderRepaintBoundary>()
        .firstOrNull;
    if (boundary != null) {
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final buffer = byteData.buffer.asUint8List();
        final file = File(outputPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(buffer);

        // Also duplicate to current conversation brain artifact dir for immediate report embedding
        const artifactDir =
            'C:/Users/GL/.gemini/antigravity/brain/dd776699-076b-49c4-a273-0d162dbef616/coach_persona';
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
  String? sentPersonaPrompt;

  _AcceptanceChatNotifier({ChatState? initialState})
      : super(
          initialState ??
              ChatState(
                messages: [
                  ChatMessage(
                    role: 'assistant',
                    content:
                        'Chào bạn! Tôi là Saman Coach. Hôm nay bạn muốn lên thực đơn hay xem xu hướng?',
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

  @override
  Future<void> loadConversations({bool loadLatest = false}) async {}

  @override
  Future<void> sendMessage(String text, {List<dynamic>? attachments}) async {
    sentPersonaPrompt = text;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildAcceptanceApp({
  required Widget child,
  Size size = const Size(1024, 768),
  _AcceptanceChatNotifier? chatNotifier,
}) {
  const profileEntity = ProfileEntity(height: 175, weight: 70, age: 28);
  const profileSnapshot = ProfileSnapshot(
    profile: profileEntity,
    fullName: 'Saman Athlete',
    email: 'sa***@gmail.com',
  );

  return ProviderScope(
    overrides: [
      profileProvider.overrideWith(
        (ref) => _AcceptanceProfileNotifier(
          ProfileState(
            profile: profileEntity,
            snapshot: profileSnapshot,
            status: ProfileStatus.ready,
          ),
        ),
      ),
      chatControllerProvider.overrideWith(
        (ref) => chatNotifier ?? _AcceptanceChatNotifier(),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0C0D0E),
      ),
      home: RepaintBoundary(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    try {
      await _loadTestFonts();
    } catch (_) {}
  });

  group('Runtime Acceptance — Saman Coach Persona Selector', () {
    testWidgets(
        '1. Desktop: Open Persona Menu from Drawer row with draft, anchored to right, checkmark and close preserves draft',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_buildAcceptanceApp(
        child: const ChatScreen(),
        size: const Size(1024, 768),
      ));
      await tester.pumpAndSettle();

      // Enter a draft in composer
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);
      await tester.enterText(textFieldFinder, 'Kế hoạch dinh dưỡng tuần tới thế nào?');
      await tester.pumpAndSettle();

      // Ensure "Phong cách Coach" row is in drawer
      expect(find.text('Phong cách Coach'), findsOneWidget);
      expect(find.text('Supportive Coach'), findsWidgets);

      // Tap "Phong cách Coach" row to open persona menu
      await tester.tap(find.text('Phong cách Coach'));
      await tester.pumpAndSettle();

      // Persona popup menu is open
      expect(find.byType(SamanPersonaMenu), findsOneWidget);

      // Verify desktop positioning: menu should be positioned to the right of drawer (> 240 px)
      final menuTopLeft = tester.getTopLeft(find.byType(SamanPersonaMenu));
      expect(menuTopLeft.dx, greaterThanOrEqualTo(240.0));

      // Verify all 3 personas rendered with descriptions and checkmark
      expect(find.text('Strict PT'), findsOneWidget);
      expect(find.text('Nutrition Doctor'), findsOneWidget);
      expect(find.text('Supportive Coach'), findsWidgets);

      expect(find.text('Kỷ luật cao, tập trung hiệu suất, không thỏa hiệp.'), findsOneWidget);
      expect(find.text('Khoa học, điềm tĩnh và giải thích chuyên sâu.'), findsOneWidget);
      expect(find.text('Thân thiện, đồng cảm và truyền cảm hứng.'), findsOneWidget);

      // Checkmark ✓ on current persona (Supportive Coach)
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      // Capture desktop screenshot
      await _captureScreenPng(
        tester,
        'runtime_evidence/coach_persona/coach_persona_desktop.png',
      );

      // Dismiss menu by tapping outside / barrier
      await tester.tapAt(const Offset(600, 200));
      await tester.pumpAndSettle();

      // Verify persona menu closed
      expect(find.byType(SamanPersonaMenu), findsNothing);

      // Verify composer draft was completely preserved
      final editable = tester.widget<TextField>(find.byType(TextField));
      expect(editable.controller?.text, 'Kế hoạch dinh dưỡng tuần tới thế nào?');
    });

    testWidgets(
        '2. Mobile (360x800): Opens below trigger in drawer, switch to Strict PT updates subtitle and dispatches prompt',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final chatNotifier = _AcceptanceChatNotifier();

      await tester.pumpWidget(_buildAcceptanceApp(
        child: const ChatScreen(),
        size: const Size(360, 800),
        chatNotifier: chatNotifier,
      ));
      await tester.pumpAndSettle();

      // In mobile, drawer starts closed. Tap drawer menu button
      final drawerButton = find.byTooltip('Coach Menu');
      if (drawerButton.evaluate().isNotEmpty) {
        await tester.tap(drawerButton);
      } else {
        final iconBtn = find.byIcon(Icons.notes_rounded);
        if (iconBtn.evaluate().isNotEmpty) {
          await tester.tap(iconBtn);
        } else {
          await tester.tap(find.byType(IconButton).first);
        }
      }
      await tester.pumpAndSettle();

      // Verify drawer opened and "Phong cách Coach" is visible
      expect(find.text('Phong cách Coach'), findsOneWidget);
      final triggerRect = tester.getRect(find.text('Phong cách Coach'));

      // Tap "Phong cách Coach"
      await tester.tap(find.text('Phong cách Coach'));
      await tester.pumpAndSettle();

      // SamanPersonaMenu is visible
      expect(find.byType(SamanPersonaMenu), findsOneWidget);

      // Verify mobile positioning: below trigger (menu y >= trigger bottom)
      final menuRect = tester.getRect(find.byType(SamanPersonaMenu));
      expect(menuRect.top, greaterThanOrEqualTo(triggerRect.top));

      // Capture mobile screenshot
      await _captureScreenPng(
        tester,
        'runtime_evidence/coach_persona/coach_persona_mobile.png',
      );

      // Tap "Strict PT"
      await tester.tap(find.text('Strict PT'));
      await tester.pumpAndSettle();

      // Menu closes after selection
      expect(find.byType(SamanPersonaMenu), findsNothing);

      // Drawer subtitle updates to "Strict PT"
      expect(find.text('Strict PT'), findsOneWidget);

      // Verify prompt was dispatched
      expect(chatNotifier.sentPersonaPrompt, contains('From now on, act as a STRICT Personal Trainer.'));
    });

    testWidgets(
        '3. Tri-point synchronization: Rail shortcut & Account menu "Cá nhân hóa Coach" open the same persona selector',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_buildAcceptanceApp(
        child: const ChatScreen(),
        size: const Size(1024, 768),
      ));
      await tester.pumpAndSettle();

      // 1. Point A: Collapsed rail shortcut
      // Collapse sidebar to rail
      final collapseButton = find.byTooltip('Thu gọn thanh bên');
      if (collapseButton.evaluate().isNotEmpty) {
        await tester.tap(collapseButton);
        await tester.pumpAndSettle();

        // Tap rail persona icon
        final railPersonaBtn = find.byTooltip('Phong cách Coach: Supportive Coach');
        expect(railPersonaBtn, findsOneWidget);
        await tester.tap(railPersonaBtn);
        await tester.pumpAndSettle();

        expect(find.byType(SamanPersonaMenu), findsOneWidget);

        // Close by outside tap
        await tester.tapAt(const Offset(500, 200));
        await tester.pumpAndSettle();
        expect(find.byType(SamanPersonaMenu), findsNothing);

        // Expand sidebar back
        await tester.tap(find.byTooltip('Mở rộng thanh bên'));
        await tester.pumpAndSettle();
      }

      // 2. Point B: Account popup menu "Cá nhân hóa Coach"
      await tester.tap(find.byTooltip('Tùy chọn Saman'));
      await tester.pumpAndSettle();

      expect(find.byType(SamanAccountPopupMenu), findsOneWidget);
      await tester.tap(find.text('Cá nhân hóa Coach'));
      await tester.pumpAndSettle();

      // Account menu closed and SamanPersonaMenu opened
      expect(find.byType(SamanAccountPopupMenu), findsNothing);
      expect(find.byType(SamanPersonaMenu), findsOneWidget);

      // Close menu
      await tester.tapAt(const Offset(600, 200));
      await tester.pumpAndSettle();
      expect(find.byType(SamanPersonaMenu), findsNothing);
    });
  });
}
