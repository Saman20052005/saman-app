import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:health_ai_app/models/ai_analysis_result.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';
import 'package:health_ai_app/screens/chat_screen.dart';
import 'package:health_ai_app/providers/daily_story_provider.dart';
import 'package:health_ai_app/screens/nutrition/widgets/log_meal_sheet.dart';
import 'package:health_ai_app/screens/nutrition/widgets/meal_review_dialog.dart';
import 'daily_story_controller_test.dart';

Future<void> openReview(WidgetTester tester, FoodHarness h) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(UncontrolledProviderScope(
      container: h.container,
      child: MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => MealReviewDialog.show(
                          context, AIAnalysisResult.fromJson(foodPayload),
                          onConfirm: (data) => h.controller.confirmLog(data)),
                      child: const Text('Review')))))));
  await tester.tap(find.text('Review'));
  await tester.pumpAndSettle();
}

Future<void> tapSave(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Lưu bữa này');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cancel review creates no Story or meal writes', (tester) async {
    final h = FoodHarness();
    await tester.runAsync(h.start);
    addTearDown(h.close);
    await openReview(tester, h);
    expect(h.writes('/log-story'), 0);
    final cancel = find.widgetWithText(OutlinedButton, 'Huỷ');
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(h.writes('/log-story'), 0);
    expect(h.writes('/logs'), 0);
  });

  testWidgets('partial failure stays in real review; retry saves only meal',
      (tester) async {
    var fail = true;
    late FoodHarness h;
    h = FoodHarness(onRequest: (o) async {
      if (o.method == 'POST' && o.path.endsWith('/logs') && fail)
        return foodReply({}, 422);
      return h.defaults(o);
    });
    await tester.runAsync(h.start);
    addTearDown(h.close);
    await openReview(tester, h);
    await tapSave(tester);
    expect(find.byType(MealReviewDialog), findsOneWidget);
    expect(find.textContaining('Photo saved, but the meal was not logged'),
        findsOneWidget);
    expect(find.text('Meal logged successfully!'), findsNothing);
    expect(h.writes('/log-story'), 1);
    expect(h.writes('/logs'), 1);
    fail = false;
    final retry = find.widgetWithText(FilledButton, 'Retry meal save');
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.byType(MealReviewDialog), findsNothing);
    expect(h.writes('/log-story'), 1);
    expect(h.writes('/logs'), 2);
  });

  testWidgets(
      'blocked photo-only failure keeps picked photo and note; writes nothing',
      (tester) async {
    late FoodHarness h;
    h = FoodHarness(onRequest: (o) async {
      if (o.path.endsWith('/analyze')) {
        return foodReply({}, 500);
      }
      return h.defaults(o);
    });
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(h.start);
    addTearDown(h.close);
    final directory = Platform.environment['SAMAN_CP06C_EVIDENCE'] ??
        Directory.systemTemp.path;
    final photo = File('$directory/widget_meal.png');
    await tester.runAsync(() => photo.writeAsBytes(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aY1sAAAAASUVORK5CYII=')));
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => photo.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
            home: Scaffold(
                body: LogMealSheet(selectedDate: DateTime(2026, 10, 23))))));
    await tester.tap(find.text('Thư viện'));
    await tester.pumpAndSettle();
    final note = find.byType(TextField);
    await tester.enterText(note, 'Keep my meal note');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final save = find.text('Lưu Nhật Ký Ảnh');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    for (var i = 0; i < 100 && find.text('Đóng').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('Lưu chỉ ảnh hiện chưa khả dụng'), findsWidgets);
    expect(h.writes('/log-story'), 0);
    expect(h.writes('/logs'), 0);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(find.text('Keep my meal note'), findsOneWidget);
    expect(find.text('Đổi ảnh'), findsOneWidget);
    expect(
        h.requests
            .where((o) => o.method == 'POST' && !o.path.endsWith('/analyze')),
        isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('real Chat flow never marks a partially saved meal as logged',
      (tester) async {
    late FoodHarness h;
    h = FoodHarness(onRequest: (o) async {
      if (o.method == 'POST' && o.path.endsWith('/logs'))
        return foodReply({}, 422);
      return h.defaults(o);
    });
    await tester.runAsync(h.start);
    addTearDown(h.close);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() => h.container
        .read(chatControllerProvider.notifier)
        .analyzeFoodPhoto(h.photo()));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container, child: const MaterialApp(home: ChatScreen())));
    await tester.pumpAndSettle();
    final log = find.text('Log meal');
    await tester.ensureVisible(log);
    await tester.pumpAndSettle();
    await tester.tap(log);
    await tester.pumpAndSettle();
    await tapSave(tester);
    expect(find.textContaining('Photo saved, but the meal was not logged'),
        findsOneWidget);
    expect(find.text('Meal logged successfully!'), findsNothing);
    expect(
        h.container
            .read(chatControllerProvider)
            .foodAnalysisState!
            .isMealLogged,
        false);
    expect(h.writes('/log-story'), 1);
    expect(h.writes('/logs'), 1);
    final cancel = find.widgetWithText(OutlinedButton, 'Huỷ');
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('Log meal'), findsOneWidget);
  });
}
