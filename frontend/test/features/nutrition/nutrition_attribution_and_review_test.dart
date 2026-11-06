import 'package:flutter/material.dart';
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
        tags: const [],
      ),
      Food(
        id: '80',
        name: 'Phở bò',
        calories: 350,
        protein: 18.0,
        carbs: 55.0,
        fat: 6.0,
        tags: const [],
      ),
      Food(
        id: '90',
        name: 'Cơm gà xối mỡ',
        calories: 550,
        protein: 28.0,
        carbs: 65.0,
        fat: 20.0,
        tags: const [],
      ),
    ];
  }
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

Widget testApp(Widget child) {
  return ProviderScope(
    overrides: [
      profileProvider.overrideWith((ref) => TestProfileNotifier()),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FoodAttributionService.loadAll();
  });

  group('Nutrition Food Images & Attribution Integration', () {
    test('Service loads 198 attributions from JSON correctly', () async {
      final all = await FoodAttributionService.loadAll();
      expect(all.length, 198);

      final phoBo = await FoodAttributionService.getByName('Phở bò');
      expect(phoBo, isNotNull);
      expect(phoBo!.isCommons, isTrue);
      expect(phoBo.author, 'Andy Li');
      expect(phoBo.license, 'CC0');
      expect(phoBo.licenseUrl, contains('creativecommons.org'));
      expect(phoBo.isCroppedResized, isTrue);

      final comTrang = await FoodAttributionService.getByName('Cơm trắng (1 chén)');
      expect(comTrang, isNotNull);
      expect(comTrang!.isAi, isTrue);
      expect(comTrang.author, 'Saman App AI Generator');
    });

    testWidgets('1. AI Image Food: Search -> Hero -> Attribution Sheet',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final screen = FoodLogScreen(userGoal: 'weight_loss');
      await tester.pumpWidget(testApp(screen));
      await tester.pumpAndSettle();

      final state = tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));

      // 1. Món AI: Cơm trắng (1 chén)
      final aiFood = FoodModel(
        id: '1',
        name: 'Cơm trắng (1 chén)',
        calories: 130,
        protein: 2.7,
        carbs: 28.2,
        fat: 0.3,
        tags: const [],
      );

      state.selectFood(aiFood);
      await tester.pump();
      await tester.pumpAndSettle();

      // Đã chuyển sang PortionReview
      expect(state.currentStep, FoodLogStep.portionReview);
      expect(find.text('Cơm trắng (1 chén)'), findsWidgets);

      // Nút xem nguồn ảnh xuất hiện
      final attrBtn = find.byKey(const Key('food_attribution_button'));
      expect(attrBtn, findsOneWidget);

      // Nhấn mở BottomSheet
      await tester.tap(attrBtn);
      await tester.pump();
      await tester.pumpAndSettle();

      // Kiểm chứng thông tin hiển thị trên modal sheet
      expect(find.text('Ảnh minh họa tạo bằng AI'), findsWidgets);
      expect(find.text('Saman App AI Generator'), findsOneWidget);
      expect(find.text('Đóng'), findsOneWidget);

      // Đóng sheet
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
    });

    testWidgets('2. Commons Image Food: Search -> Hero -> Attribution Sheet',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final screen = FoodLogScreen(userGoal: 'weight_loss');
      await tester.pumpWidget(testApp(screen));
      await tester.pumpAndSettle();

      final state = tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));

      // 2. Món Commons: Phở bò
      final commonsFood = FoodModel(
        id: '80',
        name: 'Phở bò',
        calories: 350,
        protein: 18.0,
        carbs: 55.0,
        fat: 6.0,
        tags: const [],
      );

      state.selectFood(commonsFood);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(state.currentStep, FoodLogStep.portionReview);
      expect(find.text('Phở bò'), findsWidgets);

      final attrBtn = find.byKey(const Key('food_attribution_button'));
      expect(attrBtn, findsOneWidget);

      await tester.tap(attrBtn);
      await tester.pump();
      await tester.pumpAndSettle();

      // Kiểm chứng attribution Commons
      expect(find.text('Ảnh thật (Wikimedia Commons)'), findsOneWidget);
      expect(find.text('Andy Li'), findsOneWidget);
      expect(find.text('CC0'), findsOneWidget);
      expect(find.text('Đóng'), findsOneWidget);

      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
    });

    testWidgets('3. Pending Food: Search -> Hero -> Missing Thumb & Pending Sheet',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final screen = FoodLogScreen(userGoal: 'weight_loss');
      await tester.pumpWidget(testApp(screen));
      await tester.pumpAndSettle();

      final state = tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));

      // 3. Món Pending: Cơm gà xối mỡ
      final pendingFood = FoodModel(
        id: '90',
        name: 'Cơm gà xối mỡ',
        calories: 550,
        protein: 28.0,
        carbs: 65.0,
        fat: 20.0,
        tags: const [],
      );

      // Kiểm chứng manifest trả về null cho pending food
      expect(foodImageAssetFor('Cơm gà xối mỡ'), isNull);
      expect(isFoodImagePending('Cơm gà xối mỡ'), isTrue);

      state.selectFood(pendingFood);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(state.currentStep, FoodLogStep.portionReview);
      expect(find.text('Cơm gà xối mỡ'), findsWidgets);

      // Icon placeholder món chưa có ảnh
      expect(find.byKey(const Key('food_thumb_missing')), findsOneWidget);

      final attrBtn = find.byKey(const Key('food_attribution_button'));
      expect(attrBtn, findsOneWidget);

      await tester.tap(attrBtn);
      await tester.pump();
      await tester.pumpAndSettle();

      // Kiểm chứng thông báo trạng thái Pending
      expect(find.text('Trạng thái: Chưa có ảnh (Pending)'), findsOneWidget);
      expect(find.textContaining('đang ở trạng thái Pending'), findsOneWidget);

      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
    });

    testWidgets(
        '4. End-to-end Search -> Results with Thumbnails -> Selection -> Portion Review',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final screen = FoodLogScreen(
        userGoal: 'weight_loss',
        apiService: _FakeNutritionService(),
      );
      await tester.pumpWidget(testApp(screen));
      await tester.pumpAndSettle();

      // Enter search query
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'cơm');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Results displayed with thumbnails
      expect(find.text('Cơm trắng (1 chén)'), findsOneWidget);
      expect(find.text('Phở bò'), findsOneWidget);
      expect(find.text('Cơm gà xối mỡ'), findsOneWidget);

      expect(find.byKey(const ValueKey('food_thumb_Cơm trắng (1 chén)')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('food_thumb_Phở bò')), findsOneWidget);
      expect(find.byKey(const ValueKey('food_thumb_Cơm gà xối mỡ')),
          findsOneWidget);

      // Select Commons food 'Phở bò'
      await tester.tap(find.text('Phở bò'));
      await tester.pumpAndSettle();

      final state =
          tester.state<FoodLogScreenState>(find.byType(FoodLogScreen));
      expect(state.currentStep, FoodLogStep.portionReview);
      expect(find.text('Phở bò'), findsWidgets);

      // Verify Hero card attribution button
      final attrBtn = find.byKey(const Key('food_attribution_button'));
      expect(attrBtn, findsOneWidget);

      await tester.tap(attrBtn);
      await tester.pumpAndSettle();

      expect(find.text('Ảnh thật (Wikimedia Commons)'), findsOneWidget);
      expect(find.text('Andy Li'), findsOneWidget);

      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
    });
  });
}
