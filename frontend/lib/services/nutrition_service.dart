import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../features/nutrition/domain/repositories/nutrition_repository.dart';
import '../features/nutrition/data/repositories/nutrition_repository_impl.dart';
import '../features/nutrition/domain/entities/food.dart';
import '../models/ai_analysis_result.dart';
import '../screens/nutrition/widgets/meal_review_dialog.dart';

class NutritionService {
  final INutritionRepository _repository;

  NutritionService({INutritionRepository? repository})
      : _repository = repository ?? NutritionRepositoryImpl();

  // ================================================================
  // 1. SEARCH FOODS
  // ================================================================
  Future<List<Food>> searchFoods(String query, {int limit = 20}) async {
    return await _repository.searchFoods(query, limit: limit);
  }

  // ================================================================
  // 2. ADD MEAL TO PLAN
  // ================================================================
  Future<bool> addMealToPlan({
    required String date,
    required String foodId,
    required String mealType,
    required int weightGrams,
  }) async {
    try {
      final body = {
        "date": date,
        "food_id": foodId,
        "meal_type": mealType,
        "weight_grams": weightGrams,
      };
      return await _repository.addMeal(body);
    } catch (e) {
      debugPrint("❌ Add Meal Error: $e");
      return false;
    }
  }

  // ================================================================
  // 3. UPDATE WATER INTAKE
  // ================================================================
  Future<bool> updateWaterIntake(String date, int amountMl) async {
    try {
      return await _repository.updateWater(date, amountMl);
    } catch (e) {
      debugPrint("❌ Water Log Error: $e");
      return false;
    }
  }

  // ================================================================
  // 4. CREATE CUSTOM FOOD
  // ================================================================
  Future<Food?> createCustomFood({
    required String name,
    required int calories,
    required double protein,
    required double carbs,
    required double fat,
  }) async {
    try {
      final body = {
        "name": name,
        "calories": calories,
        "protein": protein,
        "carbs": carbs,
        "fat": fat,
        "group": "User_Created",
      };
      return await _repository.createCustomFood(body);
    } catch (e) {
      debugPrint("❌ Create Food Error: $e");
      return null;
    }
  }

  // ================================================================
  // 5. UPLOAD LOG STORY
  // ================================================================
  Future<bool> uploadLogStory({
    required XFile? imageFile,
    required String mealType,
    required String note,
    required String loggedAt,
  }) async {
    try {
      return await _repository.uploadLogStory(
        imageFile: imageFile,
        mealType: mealType,
        note: note,
        loggedAt: loggedAt,
      );
    } catch (e) {
      debugPrint("❌ Upload Story Error: $e");
      return false;
    }
  }

  // ================================================================
  // 6. GET LOG STORIES
  // ================================================================
  Future<List<Map<String, dynamic>>> getLogStories(String date) async {
    try {
      return await _repository.getLogStories(date);
    } catch (e) {
      debugPrint("❌ Get Stories Error: $e");
      return [];
    }
  }

  // ================================================================
  // 7. DELETE LOG STORY
  // ================================================================
  Future<bool> deleteLogStory(String logId) async {
    try {
      return await _repository.deleteLogStory(logId);
    } catch (e) {
      debugPrint("❌ Delete Error: $e");
      return false;
    }
  }

  // ================================================================
  // 8. AI – ANALYZE FOOD IMAGE
  // ================================================================
  Future<AIAnalysisResult?> analyzeFoodImage(XFile imageFile) async {
    try {
      return await _repository.analyzeFoodImage(imageFile);
    } catch (e) {
      debugPrint("❌ Analyze Image Error: $e");
      return null;
    }
  }

  // ================================================================
  // 10. NEW: CONFIRM STORY LOG (for the new flow)
  // ================================================================
  Future<void> confirmStoryLog(MealLogData data) async {
    try {
      await _repository.confirmStoryLog(data);
    } catch (e) {
      debugPrint('❌ confirmStoryLog: $e');
      rethrow;
    }
  }

  // ================================================================
  // 11. NEW: GET WEEKLY REPORT
  // ================================================================
  Future<Map<String, dynamic>> getWeeklyReport(String startDate) async {
    try {
      return await _repository.getWeeklyReport(startDate);
    } catch (e) {
      debugPrint("❌ Get Weekly Report Error: $e");
      rethrow;
    }
  }
}
