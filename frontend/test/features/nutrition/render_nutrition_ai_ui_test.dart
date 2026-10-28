import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_ai_app/models/ai_analysis_result.dart';
import 'package:health_ai_app/screens/nutrition/widgets/meal_review_dialog.dart';
import 'package:health_ai_app/screens/nutrition/widgets/log_meal_sheet.dart';
import 'daily_story_controller_test.dart';

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

    // 1. Primary destination in runtime_evidence
    const evidenceDir =
        'd:/SamanDev/runtime_evidence/NUTRITION_ACTIVE_20261027/ui_evidence';
    final primaryDir = Directory(evidenceDir);
    if (!primaryDir.existsSync()) {
      primaryDir.createSync(recursive: true);
    }
    File('$evidenceDir/$fileName').writeAsBytesSync(bytes);

    // 2. Secondary fallback / env destination
    final secondaryDir = Platform.environment['SAMAN_RENDER_EVIDENCE'] ??
        Directory.systemTemp.path;
    final secDir = Directory(secondaryDir);
    if (!secDir.existsSync()) {
      secDir.createSync(recursive: true);
    }
    File('$secondaryDir/$fileName').writeAsBytesSync(bytes);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mobileSize = Size(390, 844);

  testWidgets('Capture 01: Mode Selection & LogMealSheet', (tester) async {
    final h = FoodHarness();
    await tester.runAsync(h.start);
    addTearDown(h.close);

    await tester.binding.setSurfaceSize(mobileSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final rootKey = GlobalKey();

    await tester.pumpWidget(
      RepaintBoundary(
        key: rootKey,
        child: UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(),
            home: Scaffold(
              backgroundColor: const Color(0xFF0F0F0F),
              body: LogMealSheet(selectedDate: DateTime(2026, 10, 27)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tiêu chuẩn'), findsOneWidget);
    expect(find.text('✨ AI nâng cao'), findsOneWidget);
    expect(find.text('Lưu Nhật Ký Ảnh'), findsOneWidget);

    await _captureRepaintBoundary(
      tester,
      rootKey,
      '01_mode_selection_and_log_sheet.png',
    );
  });

  testWidgets('Capture 02: Review Dialog Standard Mode (Dữ liệu tham chiếu)',
      (tester) async {
    final h = FoodHarness();
    await tester.runAsync(h.start);
    addTearDown(h.close);

    await tester.binding.setSurfaceSize(mobileSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final standardResult = AIAnalysisResult(
      foodName: 'Phở Bò',
      foodLabel: 'pho_bo',
      confidence: 0.92,
      lowConfidence: false,
      grams: 100.0,
      calories: 135.0,
      protein: 9.5,
      carbs: 17.0,
      fat: 3.2,
      per100g: const {
        'calories': 135.0,
        'protein': 9.5,
        'carbs': 17.0,
        'fat': 3.2,
      },
      nutritionSource: 'fallback',
      top3: const [
        FoodPrediction(label: 'pho_bo', foodName: 'Phở Bò', confidence: 0.92),
        FoodPrediction(
            label: 'bun_bo_hue', foodName: 'Bún Bò Huế', confidence: 0.05),
        FoodPrediction(label: 'hu_tieu', foodName: 'Hủ Tiếu', confidence: 0.03),
      ],
    );

    final rootKey = GlobalKey();

    await tester.pumpWidget(
      RepaintBoundary(
        key: rootKey,
        child: UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(),
            home: Scaffold(
              backgroundColor: const Color(0xFF0F0F0F),
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => MealReviewDialog.show(
                      context,
                      standardResult,
                      onConfirm: (data) => h.controller.confirmLog(data),
                    ),
                    child: const Text('Open Review'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Review'));
    await tester.pumpAndSettle();

    expect(find.text('Kiểm tra món ăn'), findsOneWidget);
    expect(find.text('⚖️ Dữ liệu tham chiếu'), findsOneWidget);
    expect(find.text('Phở Bò'), findsWidgets);
    expect(find.text('135'), findsOneWidget);
    expect(find.text('9.5g'), findsOneWidget);
    expect(find.text('17.0g'), findsOneWidget);
    expect(find.text('3.2g'), findsOneWidget);
    expect(find.text('Lưu bữa này'), findsOneWidget);
    expect(find.text('Huỷ'), findsOneWidget);

    await _captureRepaintBoundary(
      tester,
      rootKey,
      '02_review_dialog_standard_mode.png',
    );
  });

  testWidgets('Capture 03: Review Dialog Advanced Mode (✨ AI ước tính)',
      (tester) async {
    final h = FoodHarness();
    await tester.runAsync(h.start);
    addTearDown(h.close);

    await tester.binding.setSurfaceSize(mobileSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final advancedResult = AIAnalysisResult(
      foodName: 'Cơm Tấm Sườn Bì Chả',
      foodLabel: 'com_tam',
      confidence: 0.88,
      lowConfidence: false,
      grams: 350.0,
      calories: 680.0,
      protein: 34.0,
      carbs: 82.0,
      fat: 22.0,
      per100g: const {
        'calories': 194.3,
        'protein': 9.7,
        'carbs': 23.4,
        'fat': 6.3,
      },
      nutritionSource: 'gemini_estimate',
      top3: const [
        FoodPrediction(
            label: 'com_tam', foodName: 'Cơm Tấm Sườn Bì Chả', confidence: 0.88),
        FoodPrediction(
            label: 'com_ga', foodName: 'Cơm Gà Xối Mỡ', confidence: 0.08),
      ],
    );

    final rootKey = GlobalKey();

    await tester.pumpWidget(
      RepaintBoundary(
        key: rootKey,
        child: UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(),
            home: Scaffold(
              backgroundColor: const Color(0xFF0F0F0F),
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => MealReviewDialog.show(
                      context,
                      advancedResult,
                      onConfirm: (data) => h.controller.confirmLog(data),
                    ),
                    child: const Text('Open Review'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Review'));
    await tester.pumpAndSettle();

    expect(find.text('✨ AI ước tính'), findsOneWidget);
    expect(find.text('Cơm Tấm Sườn Bì Chả'), findsWidgets);

    // Toggle the explanation popover
    await tester.tap(find.text('Giải thích'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Chỉ số calo và macro do AI ước lượng'),
      findsOneWidget,
    );

    await _captureRepaintBoundary(
      tester,
      rootKey,
      '03_review_dialog_gemini_mode.png',
    );
  });

  testWidgets('Capture 04: Low Confidence Warning & Error/Retry State',
      (tester) async {
    late FoodHarness h;
    h = FoodHarness(onRequest: (o) async {
      if (o.method == 'POST' && o.path.endsWith('/logs')) {
        return foodReply({}, 422);
      }
      return h.defaults(o);
    });
    await tester.runAsync(h.start);
    addTearDown(h.close);

    await tester.binding.setSurfaceSize(mobileSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final lowConfResult = AIAnalysisResult(
      foodName: 'Bún Riêu Cua',
      foodLabel: 'bun_rieu',
      confidence: 0.35,
      lowConfidence: true,
      grams: 200.0,
      calories: 320.0,
      protein: 14.0,
      carbs: 45.0,
      fat: 8.0,
      per100g: const {
        'calories': 160.0,
        'protein': 7.0,
        'carbs': 22.5,
        'fat': 4.0,
      },
      nutritionSource: 'gemini_estimate',
      top3: const [
        FoodPrediction(
            label: 'bun_rieu', foodName: 'Bún Riêu Cua', confidence: 0.35),
        FoodPrediction(label: 'canh_bun', foodName: 'Canh Bún', confidence: 0.30),
      ],
    );

    final rootKey = GlobalKey();

    await tester.pumpWidget(
      RepaintBoundary(
        key: rootKey,
        child: UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(),
            home: Scaffold(
              backgroundColor: const Color(0xFF0F0F0F),
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => MealReviewDialog.show(
                      context,
                      lowConfResult,
                      onConfirm: (data) => h.controller.confirmLog(data),
                    ),
                    child: const Text('Open Review'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Review'));
    await tester.pumpAndSettle();

    // Verify low confidence banner
    expect(
      find.text('⚠️ Mức độ nhận diện thấp — vui lòng kiểm tra lại món ăn và số gram.'),
      findsOneWidget,
    );

    // Tap save -> will trigger 422 error and show retry state
    final saveButton = find.widgetWithText(FilledButton, 'Lưu bữa này');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Photo saved, but the meal was not logged'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Thử lưu lại'), findsOneWidget);

    await _captureRepaintBoundary(
      tester,
      rootKey,
      '04_review_dialog_low_conf_and_error.png',
    );
  });
}

