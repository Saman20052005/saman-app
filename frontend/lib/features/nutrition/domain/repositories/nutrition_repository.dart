// lib/features/nutrition/domain/repositories/nutrition_repository.dart
import 'package:image_picker/image_picker.dart';
import '../../../../models/ai_analysis_result.dart';
import '../../../../screens/nutrition/widgets/meal_review_dialog.dart';
import '../../../../models/nutrition_model.dart';
import '../entities/food.dart';

abstract class INutritionRepository {
  Future<List<Food>> searchFoods(String query, {int limit = 20});
  Future<NutritionPlan> getDailyPlan(String dateStr,
      {NutritionRequestContext? session});
  Future<NutritionPlan> generatePlan({
    required String dateStr,
    required String goal,
    int targetCalories = 0,
    int? mealCount,
    String? style,
    bool remainingOnly = false,
    NutritionRequestContext? session,
  });
  Future<NutritionPlan> swapMeal(String dateStr, Meal oldMeal, String goal);
  Future<bool> swapLoggedMealSimple(String dateStr, String logId);
  Future<bool> addMeal(Map<String, dynamic> body);
  Future<bool> updateWater(
    String date,
    int? amountMl, {
    int? deltaMl,
    int? version,
    String? idempotencyKey,
    NutritionRequestContext? session,
  });
  Future<bool> swapLoggedMeal({
    required String logId,
    required int foodIndex,
    required String replacementFoodId,
  });
  Future<bool> resetDay(String dateStr, {NutritionRequestContext? session});
  Future<bool> uploadLogStory({
    required XFile? imageFile,
    required String mealType,
    required String note,
    required String loggedAt,
  });
  Future<List<Map<String, dynamic>>> getLogStories(String date);
  Future<bool> deleteLogStory(String logId);
  Future<AIAnalysisResult?> analyzeFoodImage(
    XFile imageFile, {
    String? mode,
    NutritionRequestContext? session,
    String? idempotencyKey,
    String? clientRequestId,
  });
  Future<AIAnalysisResult?> lookupAnalysisOperation({
    required String idempotencyKey,
    String benefitId = 'ai.nutrition_gemini',
    NutritionRequestContext? session,
  });
  Future<void> confirmStoryLog(MealLogData data);
  Future<Food?> createCustomFood(Map<String, dynamic> body);
  Future<Map<String, dynamic>> getWeeklyReport(String startDate);
  Future<Food?> getFoodById(String foodId);
}

/// Raised when an operation lookup finds an in-progress or failed_unknown operation
/// so the caller does NOT redispatch inference.
class AnalysisOperationStateException implements Exception {
  final String status;
  final String message;

  const AnalysisOperationStateException(this.status, this.message);

  @override
  String toString() => message;
}

/// An in-memory request lease. Never used as an authorization decision or cache key.
class NutritionRequestContext {
  final String authorization;
  final int generation;
  final Future<void> Function() validate;

  const NutritionRequestContext({
    required this.authorization,
    required this.generation,
    required this.validate,
  });
}

class NutritionSessionChanged implements Exception {
  const NutritionSessionChanged();

  @override
  String toString() => 'Session changed. Please select the photo again.';
}

enum ConfirmLogFailureStage { story, meal, busy, changedInput, photoOnly }

class ConfirmLogException implements Exception {
  final ConfirmLogFailureStage stage;
  final bool storySaved;
  final bool outcomeUnknown;
  final String message;

  const ConfirmLogException(this.stage, this.message,
      {this.storySaved = false, this.outcomeUnknown = false});

  bool get canRetry => !outcomeUnknown &&
      (stage == ConfirmLogFailureStage.story || stage == ConfirmLogFailureStage.meal);

  @override
  String toString() => message;
}
