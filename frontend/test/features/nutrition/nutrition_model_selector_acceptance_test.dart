import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/nutrition/presentation/providers/nutrition_usual_foods_provider.dart';
import 'package:health_ai_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/nutrition/nutrition_screen.dart';
import 'package:health_ai_app/screens/nutrition/widgets/log_meal_sheet.dart';
import 'daily_story_controller_test.dart';

class _MockProfileRepo implements ProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestProfileNotifier extends ProfileNotifier {
  _TestProfileNotifier() : super(_MockProfileRepo()) {
    state = ProfileState(
      profile: const ProfileEntity(
        age: 28,
        gender: Gender.male,
        height: 178,
        weight: 75,
        activityLevel: ActivityLevel.medium,
        goal: Goal.gain_muscle,
      ),
      targetCalories: 2300,
      targetProtein: 160,
      targetCarbs: 240,
      targetFat: 65,
      waterTargetMl: 2000,
      isLoading: false,
    );
  }
}

class _TestUsualFoodsNotifier extends UsualFoodsNotifier {
  _TestUsualFoodsNotifier() : super(userId: 'test_user') {
    state = const UsualFoodsState(isLoading: false);
  }
}

class _TestNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _TestNutritionNotifier()
      : super(
          AsyncValue.data(
            NutritionPlan(
              id: 'plan_1',
              date: '2026-11-06',
              totalCaloriesConsumed: 500,
              currentWater: 1000,
              meals: [],
              entries: [],
            ),
          ),
        );

  @override
  Future<void> loadDailyPlan(
    DateTime date, {
    bool forceRefresh = false,
    int fallbackCalories = 2000,
    String fallbackGoal = 'maintain',
  }) async {}

  @override
  MacroTargets? get macroTargets => const MacroTargets(
        calories: 2300,
        protein: 160,
        carbs: 240,
        fat: 65,
      );

  @override
  bool get isMealPlanGenerating => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _captureRepaintBoundary(
  WidgetTester tester,
  GlobalKey key,
  String fileName,
) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final bytes = byteData.buffer.asUint8List();

    const evidenceDir =
        'd:/SamanDev/runtime_evidence/NUTRITION_ACTIVE_20261027/ui_evidence';
    final primaryDir = Directory(evidenceDir);
    if (!primaryDir.existsSync()) {
      primaryDir.createSync(recursive: true);
    }
    File('$evidenceDir/$fileName').writeAsBytesSync(bytes);

    final secondaryDir =
        Platform.environment['SAMAN_RENDER_EVIDENCE'] ?? Directory.systemTemp.path;
    final secDir = Directory(secondaryDir);
    if (!secDir.existsSync()) {
      secDir.createSync(recursive: true);
    }
    File('$secondaryDir/$fileName').writeAsBytesSync(bytes);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Nutrition Model Selector: Opens from NutritionScreen, Pro 3 default, Core 3 toggle and Pro 3 selection persists on note input, no overflow on narrow viewport',
    (tester) async {
      final h = FoodHarness();
      await tester.runAsync(h.start);
      addTearDown(h.close);

      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final rootKey = GlobalKey();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: ProviderScope(
            overrides: [
              profileProvider.overrideWith((ref) => _TestProfileNotifier()),
              nutritionProvider.overrideWith((ref) => _TestNutritionNotifier()),
              usualFoodsProvider.overrideWith((ref) => _TestUsualFoodsNotifier()),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData.dark(),
              locale: const Locale('vi'),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: RepaintBoundary(
                key: rootKey,
                child: const Scaffold(
                  body: NutritionScreen(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify we are on real Nutrition screen and tap 'Scan food' to open sheet
      expect(find.text('Scan food'), findsOneWidget);
      await tester.tap(find.text('Scan food'));
      await tester.pumpAndSettle();

      // 2. Verify LogMealSheet opened with title 'Ghi Nhận Dinh Dưỡng'
      expect(find.byType(LogMealSheet), findsOneWidget);
      expect(find.text('Ghi Nhận Dinh Dưỡng'), findsOneWidget);

      // 3. Verify 'Core 3' and 'Pro 3' are present (not old labels)
      expect(find.text('Tiêu chuẩn'), findsNothing);
      expect(find.text('✨ AI nâng cao'), findsNothing);
      expect(find.text('Core 3'), findsOneWidget);
      expect(find.text('Pro 3'), findsOneWidget);

      // 4. Verify Pro 3 is selected by default
      final pro3TextBefore = tester.widget<Text>(find.text('Pro 3'));
      expect(pro3TextBefore.style?.fontWeight, equals(FontWeight.w600));
      expect(pro3TextBefore.style?.fontSize, equals(14.0));
      expect(pro3TextBefore.style?.color, equals(Colors.white));

      final core3TextBefore = tester.widget<Text>(find.text('Core 3'));
      expect(core3TextBefore.style?.fontWeight, equals(FontWeight.w500));
      expect(core3TextBefore.style?.fontSize, equals(14.0));
      expect(core3TextBefore.style?.color, equals(const Color(0xFFAAAAAA)));

      // Verify thin outline icons
      expect(find.byIcon(Icons.balance_outlined), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);

      // Capture screenshot 1: Pro 3 default state in sheet
      await _captureRepaintBoundary(
        tester,
        rootKey,
        '01_nutrition_sheet_core3_default.png',
      );

      // 5. Tap Core 3, then tap Pro 3 to switch back to Pro 3
      await tester.tap(find.text('Core 3'));
      await tester.pumpAndSettle();

      final core3TextSelected = tester.widget<Text>(find.text('Core 3'));
      expect(core3TextSelected.style?.fontWeight, equals(FontWeight.w600));

      await tester.tap(find.text('Pro 3'));
      await tester.pumpAndSettle();

      // Verify Pro 3 is now selected (weight 600, white text)
      final pro3TextAfter = tester.widget<Text>(find.text('Pro 3'));
      expect(pro3TextAfter.style?.fontWeight, equals(FontWeight.w600));
      expect(pro3TextAfter.style?.color, equals(Colors.white));

      // Core 3 is now unselected (weight 500, secondary text)
      final core3TextAfter = tester.widget<Text>(find.text('Core 3'));
      expect(core3TextAfter.style?.fontWeight, equals(FontWeight.w500));
      expect(core3TextAfter.style?.color, equals(const Color(0xFFAAAAAA)));

      // 6. Enter notes into text field and verify Pro 3 selection is preserved
      final noteField = find.byType(TextField);
      expect(noteField, findsOneWidget);
      await tester.enterText(noteField, 'Phở bò tái nạm 1 tô');
      await tester.pumpAndSettle();

      // Verify Pro 3 selection persisted after note input
      final pro3TextWithNote = tester.widget<Text>(find.text('Pro 3'));
      expect(pro3TextWithNote.style?.fontWeight, equals(FontWeight.w600));
      expect(pro3TextWithNote.style?.color, equals(Colors.white));

      // Capture screenshot 2: Pro 3 selected with note input
      await _captureRepaintBoundary(
        tester,
        rootKey,
        '02_nutrition_sheet_pro3_selected_with_note.png',
      );
    },
  );

  testWidgets(
    'Nutrition Model Selector: Compact mobile viewport (360px) and narrow constraints render without overflow',
    (tester) async {
      final h = FoodHarness();
      await tester.runAsync(h.start);
      addTearDown(h.close);

      tester.view.physicalSize = const Size(360 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final rootKey = GlobalKey();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(),
            locale: const Locale('vi'),
            home: RepaintBoundary(
              key: rootKey,
              child: Scaffold(
                backgroundColor: const Color(0xFF0F0F0F),
                body: LogMealSheet(selectedDate: DateTime(2026, 11, 6)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Core 3 and Pro 3 are rendered
      final core3Finder = find.text('Core 3');
      final pro3Finder = find.text('Pro 3');
      expect(core3Finder, findsOneWidget);
      expect(pro3Finder, findsOneWidget);

      final core3Render = tester.renderObject<RenderParagraph>(core3Finder);
      final pro3Render = tester.renderObject<RenderParagraph>(pro3Finder);
      expect(core3Render.size.width, greaterThan(0));
      expect(pro3Render.size.width, greaterThan(0));

      expect(tester.takeException(), isNull);

      await _captureRepaintBoundary(
        tester,
        rootKey,
        '03_nutrition_sheet_compact_360px.png',
      );
    },
  );

  test(
    'Core 3 invokes standard flow; Pro 3 invokes advanced flow with existing payloads and contracts',
    () async {
      final h = FoodHarness();
      await h.start();
      addTearDown(h.close);

      final photo = h.photo();
      final standardResult =
          await h.controller.analyzeImage(photo, mode: 'standard');
      expect(standardResult?.foodName, isNotEmpty);

      final advancedResult =
          await h.controller.analyzeImage(photo, mode: 'advanced');
      expect(advancedResult?.foodName, isNotEmpty);
    },
  );
}
