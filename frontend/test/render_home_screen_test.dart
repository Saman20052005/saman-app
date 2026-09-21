import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/providers/nutrition_provider.dart';
import 'package:health_ai_app/providers/profile_provider.dart';
import 'package:health_ai_app/screens/home_screen.dart';

class FakeNutritionNotifier extends StateNotifier<AsyncValue<NutritionPlan?>>
    implements NutritionNotifier {
  FakeNutritionNotifier()
      : super(
          AsyncValue.data(
            NutritionPlan(
              date: '2026-09-21',
              meals: [],
              currentWater: 1800,
              targetWater: 2500,
              totalCaloriesConsumed: 1850,
              totalProteinConsumed: 120,
              totalCarbsConsumed: 210,
              totalFatConsumed: 55,
            ),
          ),
        );

  @override
  MacroTargets? get macroTargets => const MacroTargets(
        calories: 2500,
        protein: 160,
        carbs: 260,
        fat: 70,
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
    await file.writeAsBytes(buffer);
  });
}

void main() {
  testWidgets('Capture visual renders of HomeScreen at 390px mobile viewport', (tester) async {
    const mobileWidth = 390.0;
    const mobileHeight = 844.0;
    tester.view.physicalSize = const Size(mobileWidth * 2.0, mobileHeight * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'user_fullname': 'Alex Morgan',
      'user_email': 'alex@example.com',
    });
    final sharedPrefs = await SharedPreferences.getInstance();

    final repaintKey = GlobalKey();
    const artifactsDir = '/Users/saman/.gemini/antigravity-ide/brain/7192097f-8ea4-4fbd-a6ab-c262b10f4206';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPrefs),
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          nutritionProvider.overrideWith((ref) => FakeNutritionNotifier()),
          macroTargetsProvider.overrideWithValue(
            const MacroTargets(
              calories: 2500,
              protein: 160,
              carbs: 260,
              fat: 70,
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF0C0D0E),
          ),
          home: RepaintBoundary(
            key: repaintKey,
            child: const HomeScreen(),
          ),
        ),
      ),
    );

    await tester.pump();
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Capture 1: Top viewport
    await _capturePng(tester, repaintKey, '$artifactsDir/rendered_home_top.png');

    // Scroll down 420px to show Daily Targets, Quick Actions, Weekly Consistency
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await tester.pump(const Duration(milliseconds: 300));
    await _capturePng(tester, repaintKey, '$artifactsDir/rendered_home_middle.png');

    // Scroll down another 450px to show Weekly Consistency bottom & Saman Picks
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
    await tester.pump(const Duration(milliseconds: 300));
    await _capturePng(tester, repaintKey, '$artifactsDir/rendered_home_bottom.png');
  });
}
