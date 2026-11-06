import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/models/ai_analysis_result.dart';
import 'package:health_ai_app/screens/nutrition/widgets/meal_review_dialog.dart';

void main() {
  final result = AIAnalysisResult.fromJson({
    'food_name': 'Chicken Rice Bowl',
    'food_label': 'chicken_rice_bowl',
    'confidence': 0.94,
    'grams': 350,
    'nutrition': {
      'calories': 525,
      'protein': 42,
      'carbs': 56,
      'fat': 14,
      'fiber': 7,
    },
    'fiber': 7,
    'ingredients': [
      {
        'name': 'Chicken',
        'portion_grams': 120,
        'calories': 198,
        'protein': 37,
        'carbs': 0,
        'fat': 4,
        'confidence': 0.9,
      },
    ],
    'health_insights': ['Good protein source'],
  });

  testWidgets('review displays fiber and estimated ingredient details',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MealReviewDialog(result: result)),
    ));

    expect(find.text('Chất xơ  7.0g'), findsOneWidget);
    expect(find.text('Thành phần ước tính'), findsOneWidget);
    expect(find.text('Chicken'), findsOneWidget);
    expect(find.text('120g · 198 kcal'), findsOneWidget);
  });

  testWidgets('confirm invokes save callback only after user taps',
      (tester) async {
    MealLogData? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MealReviewDialog(
          result: result,
          onConfirm: (data) async => saved = data,
        ),
      ),
    ));

    expect(saved, isNull);
    final confirmButton = find.text('Lưu bữa này');
    await tester.ensureVisible(confirmButton);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.foodName, 'Chicken Rice Bowl');
    expect(saved!.grams, 350);
    expect(saved!.calories, 525);
  });
}
