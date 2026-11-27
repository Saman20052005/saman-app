import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/models/ai_analysis_result.dart';
import 'package:health_ai_app/screens/nutrition/widgets/meal_review_dialog.dart';

AIAnalysisResult _buildSampleResult({bool singleIngredient = false}) {
  final ingredients = <Map<String, dynamic>>[
    {
      'name': 'Ức gà',
      'portion_grams': 100.0,
      'calories': 165.0,
      'protein': 31.0,
      'carbs': 0.0,
      'fat': 3.6,
      'confidence': 0.92,
    },
    if (!singleIngredient)
      {
        'name': 'Cơm trắng',
        'portion_grams': 200.0,
        'calories': 260.0,
        'protein': 5.4,
        'carbs': 56.0,
        'fat': 0.6,
        'confidence': 0.95,
      },
  ];

  final totalGrams = singleIngredient ? 100.0 : 300.0;
  final totalCalories = singleIngredient ? 165.0 : 425.0;
  final totalProtein = singleIngredient ? 31.0 : 36.4;
  final totalCarbs = singleIngredient ? 0.0 : 56.0;
  final totalFat = singleIngredient ? 3.6 : 4.2;

  return AIAnalysisResult.fromJson({
    'food_name': 'Cơm ức gà',
    'food_label': 'chicken_rice',
    'confidence': 0.93,
    'grams': totalGrams,
    'nutrition': {
      'calories': totalCalories,
      'protein': totalProtein,
      'carbs': totalCarbs,
      'fat': totalFat,
    },
    'per_100g': {
      'calories': totalCalories / (totalGrams / 100.0),
      'protein': totalProtein / (totalGrams / 100.0),
      'carbs': totalCarbs / (totalGrams / 100.0),
      'fat': totalFat / (totalGrams / 100.0),
    },
    'nutrition_source': 'gemini',
    'ingredients': ingredients,
  });
}

void main() {
  testWidgets('remove ingredient updates totals and undo restores original',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MealReviewDialog(result: _buildSampleResult()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('300g • 425 kcal'), findsOneWidget);
    expect(find.text('36.4g'), findsOneWidget);
    expect(find.byKey(const ValueKey('ingredient_undo_btn')), findsNothing);

    final removeSecond = find.byKey(const ValueKey('ingredient_remove_1'));
    await tester.ensureVisible(removeSecond);
    await tester.tap(removeSecond);
    await tester.pumpAndSettle();

    expect(find.text('Cơm trắng'), findsNothing);
    expect(find.text('100g • 165 kcal'), findsOneWidget);
    expect(find.text('31.0g'), findsOneWidget);
    expect(find.byKey(const ValueKey('ingredient_undo_btn')), findsOneWidget);

    final undoBtn = find.byKey(const ValueKey('ingredient_undo_btn'));
    await tester.ensureVisible(undoBtn);
    await tester.tap(undoBtn);
    await tester.pumpAndSettle();

    expect(find.text('Cơm trắng'), findsOneWidget);
    expect(find.text('300g • 425 kcal'), findsOneWidget);
    expect(find.text('36.4g'), findsOneWidget);
    expect(find.byKey(const ValueKey('ingredient_undo_btn')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cannot remove the last remaining ingredient', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MealReviewDialog(
            result: _buildSampleResult(singleIngredient: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final removeBtnFinder = find.byKey(const ValueKey('ingredient_remove_0'));
    await tester.ensureVisible(removeBtnFinder);
    final IconButton removeBtn = tester.widget<IconButton>(removeBtnFinder);
    expect(removeBtn.onPressed, isNull);

    await tester.tap(removeBtnFinder);
    await tester.pumpAndSettle();

    expect(find.text('Ức gà'), findsOneWidget);
    expect(find.byKey(const ValueKey('ingredient_undo_btn')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'increment, decrement, and direct gram input update totals proportionally',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MealReviewDialog(result: _buildSampleResult()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // +25g on Ức gà (100g -> 125g)
    final incBtn = find.byKey(const ValueKey('ingredient_inc_0'));
    await tester.ensureVisible(incBtn);
    await tester.tap(incBtn);
    await tester.pumpAndSettle();

    // 125g + 200g = 325g; 206.25 + 260 = 466.25 (~466 kcal); 38.75 + 5.4 = 44.15 (44.1g)
    expect(find.text('325g • 466 kcal'), findsOneWidget);
    expect(find.text('44.1g'), findsOneWidget);
    expect(find.text('125g · 206 kcal'), findsOneWidget);

    // -25g on Ức gà (125g -> 100g) returns to exact baseline
    final decBtn = find.byKey(const ValueKey('ingredient_dec_0'));
    await tester.ensureVisible(decBtn);
    await tester.tap(decBtn);
    await tester.pumpAndSettle();

    expect(find.text('300g • 425 kcal'), findsOneWidget);
    expect(find.text('36.4g'), findsOneWidget);

    // Direct input: tap gram chip -> enter 150 -> confirm
    final gramChip = find.byKey(const ValueKey('ingredient_grams_0'));
    await tester.ensureVisible(gramChip);
    await tester.tap(gramChip);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('ingredient_grams_input')),
      '150',
    );
    await tester.tap(find.byKey(const ValueKey('ingredient_grams_confirm_btn')));
    await tester.pumpAndSettle();

    // 150g + 200g = 350g; 247.5 + 260 = 507.5 (~508 kcal); 46.5 + 5.4 = 51.9g
    expect(find.text('350g • 508 kcal'), findsOneWidget);
    expect(find.text('51.9g'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save passes edited macros, grams, and ingredients to onConfirm',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    MealLogData? savedData;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MealReviewDialog(
            result: _buildSampleResult(),
            onConfirm: (data) async {
              savedData = data;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Remove Cơm trắng
    final removeSecond = find.byKey(const ValueKey('ingredient_remove_1'));
    await tester.ensureVisible(removeSecond);
    await tester.tap(removeSecond);
    await tester.pumpAndSettle();

    // +25g on Ức gà (100g -> 125g)
    final incBtn = find.byKey(const ValueKey('ingredient_inc_0'));
    await tester.ensureVisible(incBtn);
    await tester.tap(incBtn);
    await tester.pumpAndSettle();

    // Save
    final saveBtn = find.widgetWithText(FilledButton, 'Lưu bữa này');
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    expect(savedData, isNotNull);
    expect(savedData!.grams, closeTo(125.0, 0.01));
    expect(savedData!.calories, closeTo(206.25, 0.01));
    expect(savedData!.protein, closeTo(38.75, 0.01));
    expect(savedData!.carbs, closeTo(0.0, 0.01));
    expect(savedData!.fat, closeTo(4.5, 0.01));
    expect(savedData!.ingredients.length, 1);
    expect(savedData!.ingredients.first.name, 'Ức gà');
    expect(savedData!.ingredients.first.portionGrams, closeTo(125.0, 0.01));
  });
}
