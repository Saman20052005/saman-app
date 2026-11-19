import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_composer.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_context_card.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_empty_state.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_rapid_chips.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_generating_indicator.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_message_list.dart';

void main() {
  group('1. SamanChatComposer AI Mode Selection', () {
    testWidgets(
        'renders activeMode pro3 as "Pro 3" on pill, opens menu with unlocked Swift 3, Core 3, Pro 3, and selects Swift 3',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      AIMode? selectedMode;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 480.0,
                child: SamanChatComposer(
                  controller: controller,
                  onSend: () {},
                  activeMode: AIMode.pro3,
                  onModeSelected: (mode) => selectedMode = mode,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Render với activeMode: AIMode.pro3 -> hiển thị text Pro 3 trên pill selector
      expect(find.text('Pro 3'), findsOneWidget);

      // Bấm mở menu chọn mode
      await tester.tap(find.text('Pro 3'));
      await tester.pumpAndSettle();

      // Tìm thấy cả Swift 3, Core 3, Pro 3
      expect(find.text('Swift 3'), findsOneWidget);
      expect(find.text('Core 3'), findsOneWidget);
      expect(find.text('Pro 3'), findsWidgets); // Pill và mục trong menu

      // Không bị khóa: Icons.lock_outline_rounded không còn xuất hiện ở mục mode
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);

      // Bấm Swift 3 -> callback onModeSelected nhận AIMode.swift3
      await tester.tap(find.text('Swift 3'));
      await tester.pumpAndSettle();

      expect(selectedMode, equals(AIMode.swift3));
    });
  });

  group('2. SamanChatContextData.fromDailyBrief & SamanChatEmptyState', () {
    testWidgets(
        'renders calories target and brief text correctly in empty state',
        (tester) async {
      final contextData = SamanChatContextData.fromDailyBrief(
        brief: 'Bạn mới uống 500ml nước hôm nay.',
        metrics: {
          'calories': 1200,
          'calories_target': 2000,
          'water_ml': 500,
          'water_target_ml': 2000,
          'protein': 80,
          'protein_target': 140,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SamanChatEmptyState(
              contextData: contextData,
              onPromptSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Render thấy 1200 / 2000 kcal và Bạn mới uống 500ml nước hôm nay.
      expect(find.textContaining('1200 / 2000 kcal'), findsOneWidget);
      expect(find.text('Bạn mới uống 500ml nước hôm nay.'), findsOneWidget);
    });
  });

  group('3. SamanChatRapidChips.fromDynamicChips', () {
    test('empty input returns defaultChips', () {
      final result = SamanChatRapidChips.fromDynamicChips([]);
      expect(result, equals(SamanRapidChipItem.defaultChips));
    });

    testWidgets(
        'input with "Bù nước" renders chip "Bù nước" and tapping returns prompt',
        (tester) async {
      const expectedPrompt = 'Nhắc nhở bù 500ml nước sau khi vận động';
      final chips = SamanChatRapidChips.fromDynamicChips([
        {
          'label': 'Bù nước',
          'prompt': expectedPrompt,
          'icon': 'water_drop',
        },
      ]);

      String? tappedPrompt;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SamanChatRapidChips(
              chips: chips,
              onChipSelected: (prompt) => tappedPrompt = prompt,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bù nước'), findsOneWidget);

      await tester.tap(find.text('Bù nước'));
      await tester.pumpAndSettle();

      expect(tappedPrompt, equals(expectedPrompt));
    });
  });

  group('4. SamanMessageList Generating Indicator visibility', () {
    testWidgets(
        'when isLoading: true and isStreaming: true with 1 assistant message, does NOT display SamanGeneratingIndicator',
        (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SamanMessageList(
              messages: [
                ChatMessage(
                  role: 'assistant',
                  content: 'Saman đang soạn kế hoạch...',
                  isTyping: true,
                ),
              ],
              scrollController: scrollController,
              isLoading: true,
              isStreaming: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SamanGeneratingIndicator), findsNothing);
    });

    testWidgets(
        'when isLoading: true and isStreaming: false, displays SamanGeneratingIndicator',
        (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SamanMessageList(
              messages: [
                ChatMessage(
                  role: 'user',
                  content: 'Tôi nên ăn gì trước buổi tập chiều nay?',
                ),
              ],
              scrollController: scrollController,
              isLoading: true,
              isStreaming: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SamanGeneratingIndicator), findsOneWidget);
    });
  });
}
