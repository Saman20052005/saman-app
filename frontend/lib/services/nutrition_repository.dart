// [File: lib/services/nutrition_repository.dart]
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import '../models/food_model.dart';
import '../models/ai_analysis_result.dart';
import '../models/nutrition_model.dart';
import '../screens/nutrition/widgets/meal_review_dialog.dart';
import 'api_client.dart';

class NutritionRepository {
  final Dio _dio = ApiClient.dio;

  // ================================================================
  // 1. FOOD SEARCH & FETCH
  // ================================================================
  Future<List<FoodModel>> searchFoods(String query, {int limit = 20}) async {
    try {
      final response = await _dio.get(
        '${ApiConfig.baseUrl}/api/nutrition/foods/search',
        queryParameters: {'q': query, 'limit': limit},
      );

      if (response.statusCode == 200 &&
          response.data != null &&
          response.data != "null") {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        final List<dynamic> foodList = (data is Map && data['foods'] is List)
            ? data['foods'] as List<dynamic>
            : (data is List ? data as List<dynamic> : []);

        return foodList
            .map((e) => FoodModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint("❌ Search Error: $e");
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getDailyPlan(String dateStr) async {
    final response =
        await _dio.get('${ApiConfig.nutritionGetEndpoint}/$dateStr');
    if (response.statusCode == 200 &&
        response.data != null &&
        response.data != "null") {
      return response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
    );
  }

  // ================================================================
  // 2. PLAN GENERATION
  // ====================C============================================
  Future<Map<String, dynamic>> generatePlan({
    required String goal,
    int targetCalories = 0,
    int? mealCount,
    String? style,
    bool remainingOnly = false,
  }) async {
    final response = await _dio.post(
      ApiConfig.generatePlanEndpoint,
      data: {
        'target_calories': targetCalories,
        'goal': goal,
        if (mealCount != null) 'meal_count': mealCount,
        if (style != null) 'style': style,
        'remaining_only': remainingOnly,
        'dietary_preferences': [],
        'allergies': [],
      },
    );

    if (response.statusCode == 200 && response.data != null) {
      return response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
    }
    throw Exception('Failed to generate plan: ${response.statusCode}');
  }

  // ================================================================
  // 3. MEAL & WATER LOGGING
  // ================================================================
  Future<bool> addMeal(Map<String, dynamic> body) async {
    final response = await _dio.post(
      ApiConfig.addMealEndpoint,
      data: body,
    );
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> updateWater(String date, int amountMl) async {
    final response = await _dio.post(
      ApiConfig.updateWaterEndpoint,
      data: {
        "date": date,
        "amount_ml": amountMl,
      },
    );
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> swapLoggedMeal({
    required String logId,
    required int foodIndex,
    required String replacementFoodId,
  }) async {
    final response = await _dio.put(
      '${ApiConfig.baseUrl}/api/nutrition/logs/$logId/swap',
      data: {
        'log_id': logId,
        'food_index': foodIndex,
        'replacement_food_id': replacementFoodId,
      },
    );
    return response.statusCode == 200;
  }

  Future<bool> resetDay(String dateStr) async {
    final response = await _dio.post(
      '${ApiConfig.baseUrl}/api/nutrition/reset-day',
      data: {"date": dateStr},
    );
    return response.statusCode == 200;
  }

  // ================================================================
  // 4. STORY & AI LOGGING
  // ================================================================
  Future<bool> uploadLogStory({
    required XFile? imageFile,
    required String mealType,
    required String note,
    required String loggedAt,
  }) async {
    final formData = FormData.fromMap({
      'meal_type': mealType,
      'logged_at': loggedAt,
      if (note.isNotEmpty) 'note': note,
    });

    if (imageFile != null) {
      final bytes = await imageFile.readAsBytes();
      formData.files.add(
        MapEntry(
          'file',
          MultipartFile.fromBytes(
            bytes,
            filename: imageFile.name,
            contentType: MediaType('image', 'jpeg'),
          ),
        ),
      );
    }

    final response = await _dio.post(
      ApiConfig.logStoryEndpoint,
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<List<Map<String, dynamic>>> getLogStories(String date) async {
    final response = await _dio.get('${ApiConfig.logStoryEndpoint}/$date');
    if (response.statusCode == 200 && response.data != null) {
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      if (data is Map && data['stories'] != null) {
        return List<Map<String, dynamic>>.from(data['stories'] as List);
      }
      if (data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
    }
    return [];
  }

  Future<bool> deleteLogStory(String logId) async {
    final response = await _dio.delete('${ApiConfig.logStoryEndpoint}/$logId');
    return response.statusCode == 200 || response.statusCode == 204;
  }

  Future<AIAnalysisResult?> analyzeFoodImage(XFile imageFile) async {
    final formData = FormData();
    if (kIsWeb) {
      final bytes = await imageFile.readAsBytes();
      formData.files.add(MapEntry(
        'file',
        MultipartFile.fromBytes(bytes,
            filename: imageFile.name, contentType: MediaType('image', 'jpeg')),
      ));
    } else {
      formData.files.add(MapEntry(
        'file',
        await MultipartFile.fromFile(imageFile.path,
            filename: imageFile.name, contentType: MediaType('image', 'jpeg')),
      ));
    }

    final response = await _dio.post(
      ApiConfig.analyzeFoodImageEndpoint,
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      return AIAnalysisResult.fromJson(data);
    }
    return null;
  }

  Future<void> confirmStoryLog(MealLogData data) async {
    await _dio.post(
      ApiConfig.logStoryEndpoint,
      data: FormData.fromMap({
        'meal_type': data.mealType,
        'food_name': data.foodName,
        'food_label': data.foodLabel,
        'calories': data.calories.toString(),
        'protein': data.protein.toString(),
        'carbs': data.carbs.toString(),
        'fat': data.fat.toString(),
        'grams': data.grams.toString(),
        'logged_at': data.loggedAt,
        'note': '',
      }),
    );
  }

  // ================================================================
  // 5. CUSTOM FOOD & REPORTS
  // ================================================================
  Future<FoodModel?> createCustomFood(Map<String, dynamic> body) async {
    final response = await _dio.post(
      '${ApiConfig.baseUrl}/api/nutrition/foods',
      data: body,
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data as Map<String, dynamic>;
      final foodData = data['food'] as Map<String, dynamic>? ?? data;
      if (!foodData.containsKey('id') && !foodData.containsKey('_id')) {
        foodData['id'] = data['id'] ?? data['_id'];
      }
      return FoodModel.fromJson(foodData);
    }
    return null;
  }

  Future<Map<String, dynamic>> getWeeklyReport(String startDate) async {
    final response = await _dio.get(
      '/api/nutrition/report/weekly',
      queryParameters: {'start_date': startDate},
    );
    return response.data as Map<String, dynamic>;
  }
}
