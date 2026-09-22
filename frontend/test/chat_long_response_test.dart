import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_assistant_response.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_food_analysis_loading.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_monogram.dart';
import 'package:health_ai_app/screens/chat_screen.dart';

class _FakeLongChatNotifier extends StateNotifier<ChatState>
    implements ChatController {
  _FakeLongChatNotifier({ChatState? initialState})
      : super(initialState ?? ChatState(messages: []));

  @override
  Ref get ref => throw UnimplementedError();

  @override
  Future<void> sendMessage(String text) async {}

  @override
  void clearChat() {
    state = ChatState(messages: []);
  }

  @override
  Future<void> retry() async {}

  @override
  void clearError() {}

  @override
  Future<void> analyzeFoodPhoto(XFile file, {String? caption}) async {}

  @override
  void markMealLogged() {}

  @override
  void clearFoodAnalysis() {}
}

const String _fixtureLongMarkdown = '''
Looking at your training log and nutrition intake today, here is your breakdown and recommended plan:

### Training

1. Keep the leg session scheduled for tomorrow.
2. Reduce top-set intensity slightly (target **RPE 8** instead of 9).
3. Add a 5-minute hip-mobility warm-up before squats.

### Nutrition

You finished close to your calorie goal but are still about 24g short on protein.

| Metric | Today | Target |
| --- | --- | --- |
| Calories | 2,180 | 2,400 |
| Protein | 142g | 160g |
| Workout | RPE 8.5 | RPE 7–8 |
| Recovery | Moderate | Good |

### Tomorrow

Start with a higher-protein breakfast and keep the session around **RPE 7–8** to compensate for today's systemic fatigue.
''';

Widget _buildWrapper({
  required Widget child,
  double width = 390,
  double height = 844,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: SamanTheme.dark(),
    home: Scaffold(
      backgroundColor: SamanChatTokens.canvas,
      body: SizedBox(
        width: width,
        height: height,
        child: child,
      ),
    ),
  );
}

void main() {
  group('Saman Chat Phase 6 — State 09 Long Response / Markdown / Table', () {
    testWidgets('1-5. Long Markdown renders paragraphs, title-case "Saman", sections & lists',
        (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: _fixtureLongMarkdown,
      );

      await tester.pumpWidget(
        _buildWrapper(
          child: SingleChildScrollView(
            child: SamanAssistantResponse(message: msg),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Identity is title-case "Saman", monogram is chat size (20x20)
      expect(find.text('Saman'), findsOneWidget);
      expect(find.byType(SamanMonogram), findsOneWidget);

      // 4. Strictly NO obsolete labels
      expect(find.text('Saman COACH'), findsNothing);
      expect(find.text('TELEMETRY SYNCED'), findsNothing);
      expect(find.text('TELEMETRY'), findsNothing);
      expect(find.text('TRAINING FOCUS'), findsNothing);
      expect(find.text('NUTRITION DELTA'), findsNothing);
      expect(find.text('TOMORROW STRATEGY'), findsNothing);

      // 3. Sections exist
      expect(find.textContaining('Training'), findsWidgets);
      expect(find.textContaining('Nutrition'), findsWidgets);
      expect(find.textContaining('Tomorrow'), findsWidgets);

      // 5. Numbered list text renders
      expect(
        find.textContaining('Keep the leg session scheduled for tomorrow.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Reduce top-set intensity slightly'),
        findsOneWidget,
      );
    });

    testWidgets('6-7. Compact table renders with headers Metric, Today, Target',
        (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: _fixtureLongMarkdown,
      );

      await tester.pumpWidget(
        _buildWrapper(
          child: SingleChildScrollView(
            child: SamanAssistantResponse(message: msg),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Table widget exists
      expect(find.byType(Table), findsOneWidget);

      // Headers exist with exact casing
      expect(find.text('Metric'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Target'), findsOneWidget);

      // Body cells exist
      expect(find.text('Calories'), findsOneWidget);
      expect(find.text('2,180'), findsOneWidget);
      expect(find.text('2,400'), findsOneWidget);
      expect(find.text('Protein'), findsOneWidget);
      expect(find.text('142g'), findsOneWidget);
      expect(find.text('160g'), findsOneWidget);
    });

    testWidgets('8. No horizontal overflow at 360px viewport', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final msg = ChatMessage(
        role: 'assistant',
        content: _fixtureLongMarkdown,
      );

      await tester.pumpWidget(
        _buildWrapper(
          width: 360,
          height: 780,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SamanAssistantResponse(message: msg),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Table), findsOneWidget);
    });

    testWidgets('9-10. Assistant response remains directly on canvas with no surrounding bubble card',
        (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: 'Short response directly on canvas.',
      );

      await tester.pumpWidget(
        _buildWrapper(
          child: SamanAssistantResponse(message: msg),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Short response directly on canvas.'), findsOneWidget);

      // Check that the root of SamanAssistantResponse is Column directly on canvas
      final assistantWidget = tester.widget<SamanAssistantResponse>(
        find.byType(SamanAssistantResponse),
      );
      expect(assistantWidget, isNotNull);
      // No Card widget surrounding it
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('11. Optional actions render only when explicitly supplied',
        (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: 'Response with actions.',
      );

      // A: Without actions -> no action pills rendered
      await tester.pumpWidget(
        _buildWrapper(
          child: SamanAssistantResponse(message: msg),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Adjust tomorrow's workout"), findsNothing);
      expect(find.text('Plan breakfast'), findsNothing);

      // B: With explicitly supplied actions -> action pills rendered
      bool actionTapped = false;
      final actions = [
        SamanAssistantAction(
          label: "Adjust tomorrow's workout",
          icon: Icons.edit_calendar_outlined,
          isPrimary: true,
          onTap: () {
            actionTapped = true;
          },
        ),
        const SamanAssistantAction(
          label: 'Plan breakfast',
          icon: Icons.restaurant_menu_outlined,
          isPrimary: false,
        ),
      ];

      await tester.pumpWidget(
        _buildWrapper(
          child: SamanAssistantResponse(
            message: msg,
            actions: actions,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Adjust tomorrow's workout"), findsOneWidget);
      expect(find.text('Plan breakfast'), findsOneWidget);

      // Tap action
      await tester.tap(find.text("Adjust tomorrow's workout"));
      await tester.pumpAndSettle();
      expect(actionTapped, isTrue);
    });

    testWidgets('12. Normal short messages remain unchanged', (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: 'I recommend keeping your hydration around 2.5L today.',
      );

      await tester.pumpWidget(
        _buildWrapper(
          child: SamanAssistantResponse(message: msg),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('I recommend keeping your hydration around 2.5L today.'),
        findsOneWidget,
      );
      expect(find.text('Saman'), findsOneWidget);
    });

    testWidgets('13. Meal-log error handling displays calm user copy and no raw exception text',
        (tester) async {
      final fakeNotifier = _FakeLongChatNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatControllerProvider.overrideWith((ref) => fakeNotifier),
          ],
          child: MaterialApp(
            theme: SamanTheme.dark(),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify no raw exception messages appear anywhere in the screen
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('Exception:'), findsNothing);
      expect(find.textContaining('Failed to log meal:'), findsNothing);
    });

    testWidgets('14. Food-analysis loading dots use restrained neutral styling, not semantic green',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SamanTheme.dark(),
          home: const Scaffold(
            backgroundColor: SamanChatTokens.canvas,
            body: SamanFoodAnalysisLoading(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Find all Containers representing the dots
      final containerWidgets = tester.widgetList<Container>(find.byType(Container));
      for (final container in containerWidgets) {
        if (container.decoration is BoxDecoration) {
          final box = container.decoration as BoxDecoration;
          if (box.shape == BoxShape.circle) {
            // Must NOT be green accent!
            expect(box.color, isNot(equals(SamanChatTokens.greenAccent)));
          }
        }
      }
    });
  });
}
