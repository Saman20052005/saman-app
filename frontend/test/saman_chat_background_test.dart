import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_background.dart';

void main() {
  group('SamanChatBackground & Aurora tokens', () {
    test('Tokens define approved Saman Aurora color palette', () {
      expect(SamanAuroraTokens.baseBackground, const Color(0xFF0D0F14));
      expect(SamanAuroraTokens.primaryGlow, const Color(0xFF1D3A8A));
      expect(SamanAuroraTokens.secondaryGlow, const Color(0xFF373078));
      expect(SamanAuroraTokens.primaryMaxAlpha, greaterThan(0.0));
      expect(SamanAuroraTokens.secondaryMaxAlpha, greaterThan(0.0));
      expect(SamanAuroraTokens.conversationIntensityRatio, 0.50);
      expect(SamanAuroraTokens.cycleDrift, const Duration(seconds: 30));
    });

    testWidgets('Renders within RepaintBoundary and IgnorePointer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 844,
              child: SamanChatBackground(
                hasConversation: false,
                isActive: false, // Inactive for static testing
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SamanChatBackground), findsOneWidget);
      expect(find.byType(RepaintBoundary), findsWidgets);
      expect(find.byType(IgnorePointer), findsWidgets);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('Handles reduced motion (disableAnimations) gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: SizedBox(
                width: 390,
                height: 844,
                child: SamanChatBackground(
                  hasConversation: false,
                  isActive: true,
                ),
              ),
            ),
          ),
        ),
      );

      // Should settle immediately since animations are disabled
      await tester.pumpAndSettle();
      expect(find.byType(SamanChatBackground), findsOneWidget);
    });

    testWidgets('Handles conversation state change smoothly', (tester) async {
      bool hasConv = false;
      late StateSetter setStateFunc;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setStateFunc = setState;
              return Scaffold(
                body: SizedBox(
                  width: 390,
                  height: 844,
                  child: SamanChatBackground(
                    hasConversation: hasConv,
                    isActive: false,
                  ),
                ),
              );
            },
          ),
        ),
      );

      expect(find.byType(SamanChatBackground), findsOneWidget);

      // Trigger conversation start
      setStateFunc(() {
        hasConv = true;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(SamanChatBackground), findsOneWidget);
    });

    testWidgets('Adapts to viewport resize without throwing errors', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SamanChatBackground(
              hasConversation: false,
              isActive: false,
            ),
          ),
        ),
      );

      expect(find.byType(SamanChatBackground), findsOneWidget);

      // Simulate keyboard opening (height reduction)
      tester.view.physicalSize = const Size(390 * 2, 450 * 2);
      await tester.pump();

      expect(find.byType(SamanChatBackground), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
