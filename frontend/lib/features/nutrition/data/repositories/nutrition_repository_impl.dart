// lib/features/nutrition/data/repositories/nutrition_repository_impl.dart
import 'package:image_picker/image_picker.dart';
import '../../../../models/ai_analysis_result.dart';
import '../../../../screens/nutrition/widgets/meal_review_dialog.dart';
import '../../domain/repositories/nutrition_repository.dart';
import '../../../../models/nutrition_model.dart';
import '../../../../models/nutrition_model.dart';
import '../../domain/entities/food.dart';
import '../datasources/nutrition_remote_data_source.dart';
import '../models/nutrition_plan_dto.dart';
import '../models/food_dto.dart';

class NutritionRepositoryImpl implements INutritionRepository {
  final INutritionRemoteDataSource _remoteDataSource;

  NutritionRepositoryImpl({INutritionRemoteDataSource? remoteDataSource})
      : _remoteDataSource = remoteDataSource ?? NutritionRemoteDataSourceImpl();

  @override
  Future<List<Food>> searchFoods(String query, {int limit = 20}) async {
    final rawList = await _remoteDataSource.searchFoods(query, limit);
    return rawList
        .map((e) => FoodDto.fromJson(e as Map<String, dynamic>).toEntity())
        .toList();
  }

  @override
  Future<NutritionPlan> getDailyPlan(String dateStr) async {
    final rawData = await _remoteDataSource.getDailyPlan(dateStr);

    Map<String, dynamic> combinedJson;
    if (rawData.containsKey('plan')) {
      combinedJson = Map<String, dynamic>.from(rawData['plan'] as Map);
      rawData.forEach((key, value) {
        if (key != 'plan') {
          combinedJson[key] = value;
        }
      });
    } else {
      combinedJson = rawData;
    }

    return NutritionPlanDto.fromJson(combinedJson).toEntity();
  }

  @override
  Future<NutritionPlan> generatePlan({
    required String goal,
    int targetCalories = 0,
    int? mealCount,
    String? style,
    bool remainingOnly = false,
  }) async {
    final rawData = await _remoteDataSource.generatePlan(
      goal: goal,
      targetCalories: targetCalories,
      mealCount: mealCount,
      style: style,
      remainingOnly: remainingOnly,
    );

    final planData = rawData['plan'] ?? rawData;
    return NutritionPlanDto.fromJson(Map<String, dynamic>.from(planData))
        .toEntity();
  }

  @override
  Future<bool> addMeal(Map<String, dynamic> body) async {
    return await _remoteDataSource.addMeal(body);
  }

  @override
  Future<bool> updateWater(String date, int amountMl) async {
    return await _remoteDataSource.updateWater(date, amountMl);
  }

  @override
  Future<bool> swapLoggedMeal({
    required String logId,
    required int foodIndex,
    required String replacementFoodId,
  }) async {
    return await _remoteDataSource.swapLoggedMeal(
      logId: logId,
      foodIndex: foodIndex,
      replacementFoodId: replacementFoodId,
    );
  }

  @override
  Future<bool> resetDay(String dateStr) async {
    return await _remoteDataSource.resetDay(dateStr);
  }

  @override
  Future<bool> uploadLogStory({
    required XFile? imageFile,
    required String mealType,
    required String note,
    required String loggedAt,
  }) async {
    return await _remoteDataSource.uploadLogStory(
      imageFile: imageFile,
      mealType: mealType,
      note: note,
      loggedAt: loggedAt,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getLogStories(String date) async {
    return await _remoteDataSource.getLogStories(date);
  }

  @override
  Future<bool> deleteLogStory(String logId) async {
    return await _remoteDataSource.deleteLogStory(logId);
  }

  @override
  Future<AIAnalysisResult?> analyzeFoodImage(XFile imageFile) async {
    final data = await _remoteDataSource.analyzeFoodImage(imageFile);
    return AIAnalysisResult.fromJson(data);
  }

  @override
  Future<void> confirmStoryLog(MealLogData data) async {
    await _remoteDataSource.confirmStoryLog(data);
  }

  @override
  Future<Food?> createCustomFood(Map<String, dynamic> body) async {
    final data = await _remoteDataSource.createCustomFood(body);
    final foodData = data['food'] as Map<String, dynamic>? ?? data;
    if (!foodData.containsKey('id') && !foodData.containsKey('_id')) {
      foodData['id'] = data['id'] ?? data['_id'];
    }
    return FoodDto.fromJson(foodData).toEntity();
  }

  @override
  Future<Map<String, dynamic>> getWeeklyReport(String startDate) async {
    return await _remoteDataSource.getWeeklyReport(startDate);
  }

  @override
  Future<NutritionPlan> swapMeal(
      String dateStr, Meal oldMeal, String goal) async {
    final rawData = await _remoteDataSource.swapMeal(
      dateStr: dateStr,
      oldMealName: oldMeal.name,
      mealType: oldMeal.mealType,
      goal: goal,
    );
    final planData = rawData['plan'] ?? rawData;
    return NutritionPlanDto.fromJson(Map<String, dynamic>.from(planData))
        .toEntity();
  }

  @override
  Future<bool> swapLoggedMealSimple(String dateStr, String logId) async {
    return await _remoteDataSource.swapLoggedMealSimple(dateStr, logId);
  }
}
