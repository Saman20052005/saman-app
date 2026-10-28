import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/models/nutrition_model.dart';
import 'package:health_ai_app/screens/nutrition/widgets/nutrition_logged_meal_card.dart';

void main() {
  Widget buildTestWidget(NutritionLogEntry entry) {
    return MaterialApp(
      home: Scaffold(
        body: NutritionLoggedMealCard(entry: entry),
      ),
    );
  }

  group('NutritionLoggedMealCard tests', () {
    testWidgets('renders network image when entry.imageUrl is present', (tester) async {
      final entry = NutritionLogEntry(
        logId: 'test_1',
        foodName: 'Grilled Chicken Salad',
        mealType: 'dinner',
        totalCalories: 125,
        protein: 16.5,
        carbs: 3.5,
        fat: 4.2,
        imageUrl: 'https://example.com/salad.jpg',
        foods: [
          {'name': 'Grilled Chicken Salad', 'calories': 125}
        ],
      );

      await tester.pumpWidget(buildTestWidget(entry));
      await tester.pump();

      expect(find.text('DINNER'), findsOneWidget);
      expect(find.text('Grilled Chicken Salad'), findsOneWidget);
      expect(find.textContaining('16g pro'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('renders fallback restaurant icon when entry has no image', (tester) async {
      final entry = NutritionLogEntry(
        logId: 'test_2',
        foodName: 'White Rice',
        mealType: 'lunch',
        totalCalories: 200,
        protein: 4.0,
        carbs: 45.0,
        fat: 0.5,
        imageUrl: null,
        foods: [
          {'name': 'White Rice', 'calories': 200}
        ],
      );

      await tester.pumpWidget(buildTestWidget(entry));
      await tester.pump();

      expect(find.text('LUNCH'), findsOneWidget);
      expect(find.text('White Rice'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
    });

    testWidgets('falls back to food element image if entry.imageUrl is null', (tester) async {
      final entry = NutritionLogEntry(
        logId: 'test_3',
        foodName: 'Beef Steak',
        mealType: 'dinner',
        totalCalories: 500,
        protein: 40.0,
        carbs: 0.0,
        fat: 25.0,
        imageUrl: null,
        foods: [
          {
            'name': 'Beef Steak',
            'calories': 500,
            'image_url': 'https://example.com/steak.jpg',
          }
        ],
      );

      await tester.pumpWidget(buildTestWidget(entry));
      await tester.pump();

      expect(find.text('Beef Steak'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}

