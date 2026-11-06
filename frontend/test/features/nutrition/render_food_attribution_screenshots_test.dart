import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/nutrition/data/food_image_attribution.dart';
import 'package:health_ai_app/features/nutrition/data/food_image_manifest.dart';
import 'package:health_ai_app/features/nutrition/domain/entities/food.dart';
import 'package:health_ai_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/models/food_model.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/food_log_screen.dart';
import 'package:health_ai_app/services/nutrition_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const destination = String.fromEnvironment('EVIDENCE_DIR',
    defaultValue: r'D:\SamanDev\runtime_evidence\nutrition_food_images\runtime_screenshots');
const captureKey = ValueKey('food-log-screen-capture');

Future<void> capture(WidgetTester tester, String filename) async {
  if (destination.isEmpty) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory(destination).createSync(recursive: true);
    File('$destination/$filename.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    img.dispose();
  });
}

class _MockProfileRepository implements ProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestProfileNotifier extends ProfileNotifier {
  TestProfileNotifier() : super(_MockProfileRepository()) {
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
      targetCarbs: 250,
      targetFat: 70,
    );
  }
}

class _FakeNutritionService extends NutritionService {
  @override
  Future<List<Food>> searchFoods(String query, {int limit = 20}) async {
    return const [
      Food(
        id: '1',
        name: 'Cơm trắng (1 chén)',
        calories: 130,
        protein: 2.7,
        carbs: 28.2,
        fat: 0.3,
        tags: [],
      ),
      Food(
        id: '80',
        name: 'Phở bò',
        calories: 350,
        protein: 18.0,
        carbs: 55.0,
        fat: 6.0,
        tags: [],
      ),
      Food(
        id: '90',
        name: 'Cơm gà xối mỡ',
        calories: 550,
        protein: 28.0,
        carbs: 65.0,
        fat: 20.0,
        tags: [],
      ),
    ];
  }
}

Widget testApp(Widget child) {
  return ProviderScope(
    overrides: [
      profileProvider.overrideWith((ref) => TestProfileNotifier()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
      ),
      builder: (context, rootChild) => RepaintBoundary(
        key: captureKey,
        child: rootChild!,
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    const sdk = r'D:\SamanDev\sdks\flutter';
    final robotoFile =
        File('$sdk/bin/cache/artifacts/material_fonts/roboto-regular.ttf');
    if (robotoFile.existsSync()) {
      final bytes = robotoFile.readAsBytesSync();
      await (FontLoader('Roboto')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
    final iconFile = File(
        '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (iconFile.existsSync()) {
      final bytes = iconFile.readAsBytesSync();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }

    SharedPreferences.setMockInitialValues({});
    await FoodAttributionService.loadAll();
  });

  testWidgets(
      'Verify Runtime Workflow: Search -> Selection -> Portion Review -> Attribution (AI, Commons, Pending)',
      (tester) async {
    tester.view.physicalSize = const Size(390, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final screen = FoodLogScreen(
      userGoal: 'weight_loss',
      apiService: _FakeNutritionService(),
    );
    await tester.pumpWidget(testApp(screen));
    await tester.pumpAndSettle();

    // 1. Search Query
    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, 'cơm');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // Verify search items
    expect(find.text('Cơm trắng (1 chén)'), findsOneWidget);
    expect(find.text('Phở bò'), findsOneWidget);
    expect(find.text('Cơm gà xối mỡ'), findsOneWidget);

    for (final food in ['Cơm trắng (1 chén)', 'Phở bò']) {
      final asset = foodImageAssetFor(food);
      if (asset != null) {
        await tester.runAsync(() => precacheImage(
            AssetImage(asset), tester.element(find.byType(FoodLogScreen))));
      }
    }
    await tester.pump();

    // CAPTURE 1: Search results with AI, Commons and Pending thumbnails
    await capture(tester, '01_search_results_thumbnails');

    // ─────────────────────────────────────────────────────────────
    // 2. AI FOOD FLOW: Cơm trắng (1 chén)
    // ─────────────────────────────────────────────────────────────
    await tester.tap(find.text('Cơm trắng (1 chén)'));
    await tester.pumpAndSettle();

    final state = tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
    expect(state.currentStep, FoodLogStep.portionReview);

    // CAPTURE 2: Portion Review AI Food
    await capture(tester, '02_portion_review_ai_food');

    // Open Attribution Sheet
    final attrBtn = find.byKey(const Key('food_attribution_button'));
    expect(attrBtn, findsOneWidget);
    await tester.tap(attrBtn);
    await tester.pumpAndSettle();

    // Verify AI attribution text
    expect(find.text('Ảnh minh họa tạo bằng AI'), findsWidgets);
    expect(find.text('Saman App AI Generator'), findsOneWidget);

    // CAPTURE 3: Attribution Modal Sheet AI Food
    await capture(tester, '03_attribution_modal_ai_food');

    // Close Modal Sheet
    Navigator.of(tester.element(find.text('Đóng'))).pop();
    await tester.pumpAndSettle();

    // Go back to search
    await tester.tap(find.byTooltip('Quay lại tìm kiếm'));
    await tester.pumpAndSettle();

    // ─────────────────────────────────────────────────────────────
    // 3. COMMONS FOOD FLOW: Phở bò
    // ─────────────────────────────────────────────────────────────
    await tester.tap(find.text('Phở bò'));
    await tester.pumpAndSettle();

    expect(state.currentStep, FoodLogStep.portionReview);

    // CAPTURE 4: Portion Review Commons Food
    await capture(tester, '04_portion_review_commons_food');

    // Open Attribution Sheet
    await tester.tap(find.byKey(const Key('food_attribution_button')));
    await tester.pumpAndSettle();

    expect(find.text('Ảnh thật (Wikimedia Commons)'), findsOneWidget);
    expect(find.text('Andy Li'), findsOneWidget);
    expect(find.text('CC0'), findsOneWidget);

    // CAPTURE 5: Attribution Modal Sheet Commons Food
    await capture(tester, '05_attribution_modal_commons_food');

    // Close Modal Sheet
    Navigator.of(tester.element(find.text('Đóng'))).pop();
    await tester.pumpAndSettle();

    // Go back to search
    await tester.tap(find.byTooltip('Quay lại tìm kiếm'));
    await tester.pumpAndSettle();

    // ─────────────────────────────────────────────────────────────
    // 4. PENDING FOOD FLOW: Cơm gà xối mỡ
    // ─────────────────────────────────────────────────────────────
    await tester.tap(find.text('Cơm gà xối mỡ'));
    await tester.pumpAndSettle();

    expect(state.currentStep, FoodLogStep.portionReview);
    expect(find.byKey(const Key('food_thumb_missing')), findsOneWidget);

    // CAPTURE 6: Portion Review Pending Food
    await capture(tester, '06_portion_review_pending_food');

    // Open Attribution Sheet
    await tester.tap(find.byKey(const Key('food_attribution_button')));
    await tester.pumpAndSettle();

    expect(find.text('Trạng thái: Chưa có ảnh (Pending)'), findsOneWidget);

    // CAPTURE 7: Attribution Modal Sheet Pending Food
    await capture(tester, '07_attribution_modal_pending_food');

    // Close Modal Sheet
    Navigator.of(tester.element(find.text('Đóng'))).pop();
    await tester.pumpAndSettle();
  });
}
