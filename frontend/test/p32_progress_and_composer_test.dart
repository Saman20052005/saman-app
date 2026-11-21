import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/presentation/providers/workout_history_providers.dart';
import 'package:health_ai_app/presentation/screens/workout_history_screen.dart';
import 'package:health_ai_app/screens/chat/tokens/saman_chat_tokens.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_attachment_sheet.dart';
import 'package:health_ai_app/screens/chat/widgets/saman_chat_composer.dart';
import 'package:health_ai_app/screens/profile/widgets/progress_snapshot_card.dart';

Widget _wrapWithApp({
  required ThemeData theme,
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: theme,
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final themeVariants = <String, ThemeData Function()>{
    'Light': SamanTheme.light,
    'Dark': SamanTheme.dark,
  };

  group('P3.2 · ProgressSnapshotCard (Light & Dark)', () {
    for (final entry in themeVariants.entries) {
      testWidgets(
        '${entry.key}: renders Xem tiến trình without Coming soon and invokes onViewProgressTap',
        (tester) async {
          var tapped = false;

          await tester.pumpWidget(
            _wrapWithApp(
              theme: entry.value(),
              child: Scaffold(
                body: Builder(
                  builder: (context) {
                    final tokens = SamanHomeTokens.of(context);
                    expect(
                      tokens.isDark,
                      entry.key == 'Dark',
                    );
                    return Center(
                      child: ProgressSnapshotCard(
                        workoutsCount: 12,
                        streakDays: 5,
                        adherencePercent: 85,
                        onViewProgressTap: () => tapped = true,
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Xem tiến trình'), findsOneWidget);
          expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
          expect(find.textContaining('Coming soon'), findsNothing);
          expect(find.textContaining('Sắp ra mắt'), findsNothing);
          expect(find.text('12'), findsOneWidget);
          expect(find.text('5d'), findsOneWidget);
          expect(find.text('85%'), findsOneWidget);

          await tester.tap(find.text('Xem tiến trình'));
          await tester.pumpAndSettle();
          expect(tapped, isTrue);
        },
      );

      testWidgets(
        '${entry.key}: default tap navigates to WorkoutHistoryScreen when onViewProgressTap is null',
        (tester) async {
          await tester.pumpWidget(
            _wrapWithApp(
              theme: entry.value(),
              overrides: [
                workoutHistoryProvider.overrideWith((ref) async => const []),
              ],
              child: const Scaffold(
                body: Center(
                  child: ProgressSnapshotCard(
                    workoutsCount: 8,
                    streakDays: 3,
                    adherencePercent: 75,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Xem tiến trình'), findsOneWidget);
          expect(find.textContaining('Coming soon'), findsNothing);

          await tester.tap(find.text('Xem tiến trình'));
          await tester.pumpAndSettle();

          expect(find.byType(WorkoutHistoryScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('P3.2 · SamanChatComposer Tools & Thinking Level (Light & Dark)', () {
    for (final entry in themeVariants.entries) {
      testWidgets(
        '${entry.key}: [+] tools popover shows 3 items and tapping Đính kèm buổi tập gần nhất fills prompt & focuses',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          final controller = TextEditingController();
          final focusNode = FocusNode();
          addTearDown(controller.dispose);
          addTearDown(focusNode.dispose);

          await tester.pumpWidget(
            _wrapWithApp(
              theme: entry.value(),
              child: Scaffold(
                body: Builder(
                  builder: (context) {
                    final tokens = SamanChatTokens.of(context);
                    expect(tokens.isDark, entry.key == 'Dark');
                    return Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560.0),
                          child: SamanChatComposer(
                            controller: controller,
                            focusNode: focusNode,
                            onSend: () {},
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byTooltip('Thêm công cụ'));
          await tester.pumpAndSettle();

          expect(find.text('Phân tích ảnh món ăn'), findsOneWidget);
          expect(find.text('Phân tích lịch sử'), findsOneWidget);
          expect(find.text('Đính kèm buổi tập gần nhất'), findsOneWidget);
          expect(
            find.text('Gửi ngữ cảnh buổi tập vào hội thoại'),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.fitness_center_outlined), findsOneWidget);

          await tester.tap(find.text('Đính kèm buổi tập gần nhất'));
          await tester.pumpAndSettle();

          expect(
            controller.text,
            'Hãy phân tích buổi tập gần nhất của tôi và gợi ý cách phục hồi / điều chỉnh tiếp theo.',
          );
          expect(focusNode.hasFocus, isTrue);
          expect(find.text('Đính kèm buổi tập gần nhất'), findsNothing);
        },
      );

      testWidgets(
        '${entry.key}: [+] tools invokes custom onAttachLatestWorkout when provided',
        (tester) async {
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          var attachedWorkoutTapped = false;

          await tester.pumpWidget(
            _wrapWithApp(
              theme: entry.value(),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SamanChatComposer(
                      controller: controller,
                      onSend: () {},
                      onAttachLatestWorkout: () => attachedWorkoutTapped = true,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byTooltip('Thêm công cụ'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Đính kèm buổi tập gần nhất'));
          await tester.pumpAndSettle();

          expect(attachedWorkoutTapped, isTrue);
          expect(controller.text, isEmpty);
        },
      );

      testWidgets(
        '${entry.key}: Thinking Level submenu unlocks Low->swift3, Medium->core3, High->pro3 without Coming soon',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          final controller = TextEditingController();
          addTearDown(controller.dispose);
          final selectedModes = <AIMode>[];
          var activeMode = AIMode.core3;

          await tester.pumpWidget(
            _wrapWithApp(
              theme: entry.value(),
              child: StatefulBuilder(
                builder: (context, setState) {
                  return Scaffold(
                    body: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560.0),
                          child: SamanChatComposer(
                            controller: controller,
                            onSend: () {},
                            activeMode: activeMode,
                            onModeSelected: (mode) {
                              selectedModes.add(mode);
                              setState(() => activeMode = mode);
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Open Mode menu -> Thinking Level submenu
          await tester.tap(find.text('Core 3'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Mức độ suy luận'));
          await tester.pumpAndSettle();

          expect(find.text('Low'), findsOneWidget);
          expect(find.text('Medium'), findsOneWidget);
          expect(find.text('High'), findsOneWidget);
          expect(find.text('Sắp ra mắt'), findsNothing);
          expect(find.text('Coming soon'), findsNothing);
          expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);

          // Select High -> AIMode.pro3
          await tester.tap(find.text('High'));
          await tester.pumpAndSettle();
          expect(selectedModes.last, AIMode.pro3);
          expect(find.text('Pro 3'), findsOneWidget);

          // Re-open Mode menu -> Thinking Level -> select Low -> AIMode.swift3
          await tester.tap(find.text('Pro 3'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Mức độ suy luận'));
          await tester.pumpAndSettle();

          expect(find.text('Sắp ra mắt'), findsNothing);
          expect(find.text('Coming soon'), findsNothing);

          await tester.tap(find.text('Low'));
          await tester.pumpAndSettle();
          expect(selectedModes.last, AIMode.swift3);
          expect(find.text('Swift 3'), findsOneWidget);

          // Re-open Mode menu -> Thinking Level -> select Medium -> AIMode.core3
          await tester.tap(find.text('Swift 3'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Mức độ suy luận'));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Medium'));
          await tester.pumpAndSettle();
          expect(selectedModes, [AIMode.pro3, AIMode.swift3, AIMode.core3]);
        },
      );

      testWidgets(
        '${entry.key}: SamanAttachmentSheet supports optional onAttachLatestWorkout',
        (tester) async {
          var workoutAttached = false;

          await tester.pumpWidget(
            _wrapWithApp(
              theme: entry.value(),
              child: Scaffold(
                body: SamanAttachmentSheet(
                  onAttachLatestWorkout: () => workoutAttached = true,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Take food photo'), findsOneWidget);
          expect(find.text('Upload image'), findsOneWidget);
          expect(find.text('Đính kèm buổi tập gần nhất'), findsOneWidget);
          expect(
            find.text('Gửi ngữ cảnh buổi tập vào hội thoại'),
            findsOneWidget,
          );

          await tester.tap(find.text('Đính kèm buổi tập gần nhất'));
          await tester.pumpAndSettle();
          expect(workoutAttached, isTrue);
        },
      );
    }
  });
}
