// [File: lib/config/api_config.dart]
import 'package:flutter/foundation.dart';

class ApiConfig {
  // ✅ URL Backend chính thức
  static const String baseUrl =
      'https://nguyenvananan2005-saman-backend.hf.space';

  // ==================== NUTRITION ENDPOINTS ====================
  static const String nutritionGetEndpoint = '$baseUrl/api/nutrition';
  static const String nutritionCreateEndpoint =
      '$baseUrl/api/nutrition/foods/create';
  static const String nutritionUpdateEndpoint = '$baseUrl/api/nutrition/update';
  static const String generatePlanEndpoint =
      '$baseUrl/api/nutrition/generate-plan';

  /// Water log — POST /api/nutrition/water
  static const String updateWaterEndpoint = '$baseUrl/api/nutrition/water';

  /// Meal log — POST /api/nutrition/logs (backend NutritionLog schema)
  static const String addMealEndpoint = '$baseUrl/api/nutrition/logs';

  /// Story log — POST/GET/DELETE base; append /{date} or /{id} as needed
  static const String logStoryEndpoint = '$baseUrl/api/nutrition/log-story';

  /// Food AI analysis — backend/routers/food_analysis.py
  static const String analyzeFoodImageEndpoint = '$baseUrl/api/food/analyze';

  // ==================== AUTH ENDPOINTS ====================
  static const String registerEndpoint = '$baseUrl/api/auth/register';
  static const String loginEndpoint = '$baseUrl/api/auth/login';
  // ✅ [FIX] Sửa thành đúng route Backend: /api/user/profile
  static const String getProfileEndpoint = '$baseUrl/api/user/profile';

  // ==================== WORKOUT ENDPOINTS ====================
  static const String workoutPlansEndpoint = '$baseUrl/api/workouts/plans';
  static const String logWorkoutEndpoint = '$baseUrl/api/workouts/sessions';
  static const String workoutStreakEndpoint = '$baseUrl/api/workouts/streak';
  static const String createPlanEndpoint = '$baseUrl/api/workouts/plans';
  static const String deletePlanEndpoint =
      '$baseUrl/api/workouts/plans'; // Append /{id} when calling
  static const String saveSessionEndpoint = '$baseUrl/api/workouts/sessions';
  static const String historyEndpoint = '$baseUrl/api/workouts/history';
  static const String myPlansEndpoint = '$baseUrl/api/workouts/plans';
  static const String getSessionEndpoint = '$baseUrl/api/workouts/sessions';

  // ==================== EXERCISE ENDPOINTS ====================
  static const String muscleGroupsEndpoint =
      '$baseUrl/api/workouts/muscle-groups';
  static const String exercisesEndpoint = '$baseUrl/api/workouts/exercises';
  static const String popularExercisesEndpoint =
      '$baseUrl/api/workouts/exercises/popular';
  static const String featuredMuscleGroupsEndpoint =
      '$baseUrl/api/workouts/muscle-groups/featured';

  // ==================== USER / PROFILE ENDPOINTS ====================
  // ✅ [FIX] Sửa thành đúng route Backend: /api/user/update-profile
  static const String profileUpdateEndpoint =
      '$baseUrl/api/user/update-profile';

  // ==================== OTHER ENDPOINTS ====================
  static const String chatEndpoint = '$baseUrl/api/chat';
  static const String foodLogEndpoint = '$baseUrl/api/food/log';
  static const String healthEndpoint = '$baseUrl/api/health/ping';
  static const String analyzeImageEndpoint = '$baseUrl/api/analyze_image';
  static const String analyzeFileEndpoint = '$baseUrl/api/analyze_file';

  // ==================== CONFIG ====================
  static const Duration requestTimeout = Duration(seconds: 120);
  static const bool isDebug = kDebugMode;

  static void printDebug(String message) {
    if (kDebugMode) {
      debugPrint('🔍 [API] $message');
    }
  }
}
