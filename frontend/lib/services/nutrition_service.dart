import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../features/nutrition/domain/repositories/nutrition_repository.dart';
import '../features/nutrition/data/repositories/nutrition_repository_impl.dart';
import '../features/nutrition/domain/entities/food.dart';
import '../models/ai_analysis_result.dart';
import '../screens/nutrition/widgets/meal_review_dialog.dart';
import '../presentation/providers/workout_history_providers.dart';
import '../providers/profile_provider.dart';
import '../utils/auth_helper.dart';

export '../features/nutrition/domain/repositories/nutrition_repository.dart'
    show NutritionRequestContext, NutritionSessionChanged;

/// Food requests reuse the existing logout scope; no credentials are persisted here.
final nutritionSessionProvider = Provider<NutritionSession>((ref) {
  final session = NutritionSession(ref);
  ref.listen(workoutAuthScopeProvider, (_, __) => session.invalidate());
  ref.listen(authLoggingOutProvider, (_, next) {
    if (next) session.invalidate();
  });
  ref.onDispose(() => session._disposed = true);
  return session;
});

class NutritionSession {
  final Ref _ref;
  int _generation = 0;
  bool _disposed = false;
  String? _lastToken;

  NutritionSession(this._ref);

  void invalidate() => _generation++;

  Future<NutritionRequestContext> capture() async {
    final generation = _generation;
    if (_disposed || _ref.read(authLoggingOutProvider)) {
      throw const NutritionSessionChanged();
    }
    final token = await _readToken();
    if (_disposed || generation != _generation ||
        _ref.read(authLoggingOutProvider)) {
      throw const NutritionSessionChanged();
    }
    if (token == null || token.isEmpty) {
      throw const NutritionSessionChanged();
    }
    if (_lastToken != null && _lastToken != token) invalidate();
    _lastToken = token;
    final capturedGeneration = _generation;
    return NutritionRequestContext(
      authorization: 'Bearer $token',
      generation: capturedGeneration,
      validate: () async {
        if (_disposed || capturedGeneration != _generation ||
            _ref.read(authLoggingOutProvider)) {
          throw const NutritionSessionChanged();
        }
        final currentToken = await _readToken();
        if (_disposed || capturedGeneration != _generation ||
            _ref.read(authLoggingOutProvider) || currentToken != token) {
          throw const NutritionSessionChanged();
        }
      },
    );
  }

  Future<String?> _readToken() async {
    try {
      return await AuthHelper.getToken();
    } catch (_) {
      // Unreadable credentials invalidate this request, never a success estimate.
      throw const NutritionSessionChanged();
    }
  }

  Future<void> recoverAuthorization() =>
      _ref.read(profileProvider.notifier).loadProfile();
}

String foodAnalysisErrorMessage(Object error) {
  if (error is NutritionSessionChanged ||
      (error is DioException && error.error is NutritionSessionChanged)) {
    return const NutritionSessionChanged().toString();
  }
  if (error is DioException) {
    switch (error.response?.statusCode) {
      case 401:
        return 'Session expired. Please sign in again.';
      case 403:
        return 'Advanced analysis is not enabled for this account. Try Standard.';
      case 422:
        return 'Please check the photo and analysis mode, then try again.';
    }
    return 'Food analysis is unavailable. Check your connection and try again.';
  }
  return "I couldn't estimate this meal confidently from the photo.";
}

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
  Future<bool> updateWaterIntake(
    String date,
    int? amountMl, {
    int? deltaMl,
    int? version,
    String? idempotencyKey,
  }) async {
    try {
      return await _repository.updateWater(
        date,
        amountMl,
        deltaMl: deltaMl,
        version: version,
        idempotencyKey: idempotencyKey,
      );
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
  Future<AIAnalysisResult?> analyzeFoodImage(XFile imageFile,
      {String? mode, NutritionRequestContext? session}) async {
    return _repository.analyzeFoodImage(imageFile, mode: mode, session: session);
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
