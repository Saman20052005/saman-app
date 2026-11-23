import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/main_screen.dart';
import 'package:health_ai_app/features/profile/domain/entities/profile_entity.dart';
import 'package:health_ai_app/features/profile/data/repositories/profile_repository_impl.dart';

class _RenderPathProvider extends PathProviderPlatform {
  _RenderPathProvider(this.temporaryDirectory, this.supportDirectory);

  final Directory temporaryDirectory;
  final Directory supportDirectory;

  @override
  Future<String?> getTemporaryPath() async => temporaryDirectory.path;

  @override
  Future<String?> getApplicationSupportPath() async => supportDirectory.path;
}

class _MockProfileRepository implements ProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockProfileNotifier extends ProfileNotifier {
  _MockProfileNotifier() : super(_MockProfileRepository()) {
    state = ProfileState(
      profile: const ProfileEntity(
        age: 28,
        gender: Gender.male,
        height: 178,
        weight: 75,
        activityLevel: ActivityLevel.medium,
        goal: Goal.gain_muscle,
      ),
    );
  }

  @override
  Future<void> loadProfile() async {}
}

class _MockNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  _MockNutritionNotifier()
      : super(
          AsyncValue.data(
            NutritionPlan(
              date: '2026-11-06',
              meals: [],
              currentWater: 0,
              targetWater: 2400,
              totalCaloriesConsumed: 0,
              totalProteinConsumed: 0,
              totalCarbsConsumed: 0,
              totalFatConsumed: 0,
            ),
          ),
        );

  @override
  MacroTargets? get macroTargets => const MacroTargets(
        calories: 3129,
        protein: 136,
        carbs: 451,
        fat: 87,
      );

  @override
  Future<void> loadDailyPlan(
    DateTime date, {
    bool forceRefresh = false,
    int fallbackCalories = 2000,
    String fallbackGoal = 'maintain',
  }) async {}

  @override
  Future<void> updateWater(int amountMl, {required String date}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _capturePng(WidgetTester tester, GlobalKey key, String outputPath) async {
  await tester.runAsync(() async {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final buffer = byteData.buffer.asUint8List();
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(buffer);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalPathProvider = PathProviderPlatform.instance;

  setUpAll(() async {
    final evidenceDirectory = Directory.systemTemp;
    final cacheRoot = await evidenceDirectory.createTemp('home-stitch-cache-');
    final temporaryDirectory =
        await Directory('${cacheRoot.path}/temporary').create();
    final supportDirectory =
        await Directory('${cacheRoot.path}/support').create();
    PathProviderPlatform.instance =
        _RenderPathProvider(temporaryDirectory, supportDirectory);
  });

  tearDownAll(() {
    PathProviderPlatform.instance = originalPathProvider;
  });

  testWidgets('Renders and captures Home screen top and scrolled viewports', (tester) async {
    const mobileWidth = 390.0;
    const mobileHeight = 844.0;
    tester.view.physicalSize = const Size(mobileWidth * 2.0, mobileHeight * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'user_fullname': 'Saman',
      'user_email': 'saman@example.com',
    });
    final sharedPrefs = await SharedPreferences.getInstance();

    final repaintKey = GlobalKey();
    const evidenceDir = 'runtime_evidence/stitch_handoff';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPrefs),
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          profileProvider.overrideWith((ref) => _MockProfileNotifier()),
          nutritionProvider.overrideWith((ref) => _MockNutritionNotifier()),
          macroTargetsProvider.overrideWithValue(
            const MacroTargets(
              calories: 3129,
              protein: 136,
              carbs: 451,
              fat: 87,
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: repaintKey,
            child: const MainScreen(loadProfileOnInit: false),
          ),
        ),
      ),
    );

    await tester.pump();
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // 1. Capture Top Viewport (Header, Ask Saman, Workout Hero with Mint Button, Daily Targets preview, Bottom Nav)
    await _capturePng(tester, repaintKey, '$evidenceDir/saman_home_top_viewport.png');

    // 2. Scroll down 520px to show Daily Targets, Quick Actions, Consistency & Saman Picks
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -520));
    await tester.pump(const Duration(milliseconds: 300));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Capture Scrolled Viewport (Daily Targets, Quick Actions, Weekly Consistency, Saman Picks, Bottom Nav)
    await _capturePng(tester, repaintKey, '$evidenceDir/saman_home_scrolled_viewport.png');

    // Drain background cache timers cleanly
    await tester.pump(const Duration(seconds: 12));
  });
}
