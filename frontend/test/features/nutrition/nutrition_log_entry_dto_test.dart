import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/features/nutrition/data/models/nutrition_log_entry_dto.dart';
import 'package:health_ai_app/models/nutrition_model.dart';

void main() {
  group('NutritionLogEntryDto & NutritionLogEntry tests', () {
    test('parses foods from foodsList (backend readback contract)', () {
      final json = {
        'log_id': 'log_123',
        'food_name': 'Grilled Chicken Salad',
        'meal_type': 'dinner',
        'calories': 125,
        'protein': 16.5,
        'carbs': 3.5,
        'fat': 4.2,
        'image_url': 'https://example.com/photos/salad.jpg',
        'foodsList': [
          {
            'name': 'Grilled Chicken Salad',
            'food_label': 'grilled_chicken_salad',
            'weight_grams': 100,
            'calories': 125,
            'protein': 16.5,
            'carbs': 3.5,
            'fat': 4.2,
          }
        ],
      };

      final dto = NutritionLogEntryDto.fromJson(json);
      expect(dto.logId, 'log_123');
      expect(dto.foodName, 'Grilled Chicken Salad');
      expect(dto.mealType, 'dinner');
      expect(dto.totalCalories, 125);
      expect(dto.protein, 16.5);
      expect(dto.carbs, 3.5);
      expect(dto.fat, 4.2);
      expect(dto.imageUrl, 'https://example.com/photos/salad.jpg');
      expect(dto.foods.length, 1);
      expect(dto.foods[0]['name'], 'Grilled Chicken Salad');

      final entity = dto.toEntity();
      expect(entity.imageUrl, 'https://example.com/photos/salad.jpg');
      expect(entity.foods.length, 1);
      expect(entity.foods[0]['name'], 'Grilled Chicken Salad');
    });

    test('parses foods from legacy foods key', () {
      final json = {
        'log_id': 'log_legacy',
        'food_name': 'Apple Pie',
        'meal_type': 'snack',
        'calories': 300,
        'protein': 2.0,
        'carbs': 45.0,
        'fat': 12.0,
        'foods': [
          {'name': 'Apple Pie', 'calories': 300}
        ],
      };

      final dto = NutritionLogEntryDto.fromJson(json);
      expect(dto.imageUrl, isNull);
      expect(dto.foods.length, 1);
      expect(dto.foods[0]['name'], 'Apple Pie');

      final entity = dto.toEntity();
      expect(entity.imageUrl, isNull);
      expect(entity.foods.length, 1);
    });

    test('NutritionLogEntry.fromJson supports both foods and foodsList with image_url', () {
      final jsonBackend = {
        'log_id': 'entry_b',
        'food_name': 'Pho Bo',
        'meal_type': 'breakfast',
        'total_calories': 450,
        'protein': 25.0,
        'carbs': 60.0,
        'fat': 10.0,
        'image_url': 'https://res.cloudinary.com/test/image/upload/pho.jpg',
        'foodsList': [
          {'name': 'Pho Bo', 'calories': 450}
        ],
      };

      final entry = NutritionLogEntry.fromJson(jsonBackend);
      expect(entry.logId, 'entry_b');
      expect(entry.imageUrl, 'https://res.cloudinary.com/test/image/upload/pho.jpg');
      expect(entry.foods.length, 1);
      expect(entry.foods[0]['name'], 'Pho Bo');
    });

    test('handles empty or missing foods gracefully without throwing', () {
      final json = {
        'log_id': 'empty_foods',
        'food_name': 'Coffee',
        'meal_type': 'morning',
        'calories': 10,
      };

      final dto = NutritionLogEntryDto.fromJson(json);
      expect(dto.foods, isEmpty);
      expect(dto.imageUrl, isNull);

      final entity = dto.toEntity();
      expect(entity.foods, isEmpty);
      expect(entity.imageUrl, isNull);
    });
  });
}

