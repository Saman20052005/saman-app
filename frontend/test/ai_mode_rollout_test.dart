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
          'Core 3 is the only selectable mode at $size, scale $textScale',
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
        expect(find.text('Sắp ra mắt'), findsNWidgets(2));
        expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));

        for (final (name, message) in [
          (
            'Swift 3',
            'Chế độ Swift 3 đang được hiệu chuẩn, vui lòng trải nghiệm Core 3.',
          ),
          ('Pro 3', 'Chế độ Pro 3 sẽ ra mắt trong bản cập nhật tới.'),
        ]) {
          expect(chip(name).selected, isFalse);
          expect(chip(name).onSelected, isNull);
          await tester.tap(find
              .ancestor(
                of: find.text(name),
                matching: find.byType(InkWell),
              )
              .last);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text(message), findsOneWidget);
          expect(container.read(chatControllerProvider), same(initialState));
          expect(container.read(chatControllerProvider).selectedAIMode,
              AIMode.core3);
          expect(chip('Core 3').selected, isTrue);
          expect(chip(name).onSelected, isNull);
          expect(tester.takeException(), isNull);
        }
        await tester.tap(find
            .ancestor(
              of: find.text('Core 3'),
              matching: find.byType(InkWell),
            )
            .last);
        await tester.pump();
        expect(container.read(chatControllerProvider), same(initialState));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
