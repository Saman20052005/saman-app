import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/screens/chat/widgets/ai_mode_selector.dart';

void main() {
  for (final size in const [Size(390, 844), Size(1440, 960)]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
          'All 3 AI modes are selectable at $size, scale $textScale',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(primary: AppColors.primary),
            ),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(textScale),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: const AIModeSelector(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));

        ChoiceChip chip(String name) => tester.widget<ChoiceChip>(find.ancestor(
              of: find.text(name),
              matching: find.byType(ChoiceChip),
            ));
        final initialState = container.read(chatControllerProvider);
        expect(initialState.selectedAIMode, AIMode.core3);
        expect(initialState.copyWith(isLoading: true).selectedAIMode,
            AIMode.core3);
        expect(find.byType(ChoiceChip), findsNWidgets(3));
        expect(chip('Core 3').selected, isTrue);
        expect(chip('Core 3').onSelected, isNotNull);
        expect(chip('Core 3').selectedColor, AppColors.primary);
        expect(find.text('Đang dùng'), findsOneWidget);
        expect(find.text('Sắp ra mắt'), findsNothing);
        expect(find.byIcon(Icons.lock_outline), findsNothing);

        for (final (name, expectedMode) in [
          ('Swift 3', AIMode.swift3),
          ('Pro 3', AIMode.pro3),
          ('Core 3', AIMode.core3),
        ]) {
          expect(chip(name).onSelected, isNotNull);
          await tester.tap(
            find.ancestor(
              of: find.text(name),
              matching: find.byType(ChoiceChip),
            ),
          );
          await tester.pump();
          expect(container.read(chatControllerProvider).selectedAIMode,
              expectedMode);
          expect(chip(name).selected, isTrue);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
