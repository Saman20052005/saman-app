// lib/features/nutrition/domain/repositories/nutrition_repository.dart
import 'package:image_picker/image_picker.dart';
import '../../../../models/ai_analysis_result.dart';
import '../../../../screens/nutrition/widgets/meal_review_dialog.dart';
import '../../../../models/nutrition_model.dart';
import '../../../../models/nutrition_model.dart';
import '../entities/food.dart';

abstract class INutritionRepository {
  Future<List<Food>> searchFoods(String query, {int limit = 20});
  Future<NutritionPlan> getDailyPlan(String dateStr);
  Future<NutritionPlan> generatePlan({
    required String goal,
    int targetCalories = 0,
    int? mealCount,
    String? style,
    bool remainingOnly = false,
  });
  Future<NutritionPlan> swapMeal(String dateStr, Meal oldMeal, String goal);
  Future<bool> swapLoggedMealSimple(String dateStr, String logId);
  Future<bool> addMeal(Map<String, dynamic> body);
  Future<bool> updateWater(String date, int amountMl);
  Future<bool> swapLoggedMeal({
    required String logId,
    required int foodIndex,
    required String replacementFoodId,
  });
  Future<bool> resetDay(String dateStr);
  Future<bool> uploadLogStory({
    required XFile? imageFile,
    required String mealType,
    required String note,
    required String loggedAt,
  });
  Future<List<Map<String, dynamic>>> getLogStories(String date);
  Future<bool> deleteLogStory(String logId);
  Future<AIAnalysisResult?> analyzeFoodImage(XFile imageFile);
  Future<void> confirmStoryLog(MealLogData data);
  Future<Food?> createCustomFood(Map<String, dynamic> body);
  Future<Map<String, dynamic>> getWeeklyReport(String startDate);
}
