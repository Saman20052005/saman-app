// lib/features/nutrition/data/datasources/nutrition_remote_data_source.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import '../../../../services/api_client.dart';
import '../../../../config/api_config.dart';
import '../../../../screens/nutrition/widgets/meal_review_dialog.dart';

abstract class INutritionRemoteDataSource {
  Future<Map<String, dynamic>> getDailyPlan(String dateStr);
  Future<Map<String, dynamic>> generatePlan({
    required String goal,
    int targetCalories,
    int? mealCount,
    String? style,
    bool remainingOnly,
  });
  Future<bool> addMeal(Map<String, dynamic> body);
  Future<bool> updateWater(String date, int amountMl);
  Future<bool> swapLoggedMeal({
    required String logId,
    required int foodIndex,
    required String replacementFoodId,
  });
  Future<Map<String, dynamic>> swapMeal({
    required String dateStr,
    required String oldMealName,
    required String mealType,
    required String goal,
  });
  Future<bool> swapLoggedMealSimple(String dateStr, String logId);
  Future<bool> resetDay(String dateStr);
  Future<bool> uploadLogStory({
    required XFile? imageFile,
    required String mealType,
    required String note,
    required String loggedAt,
  });
  Future<List<Map<String, dynamic>>> getLogStories(String date);
  Future<bool> deleteLogStory(String logId);
  Future<Map<String, dynamic>> analyzeFoodImage(XFile imageFile);
  Future<void> confirmStoryLog(MealLogData data);
  Future<Map<String, dynamic>> createCustomFood(Map<String, dynamic> body);
  Future<Map<String, dynamic>> getWeeklyReport(String startDate);
  Future<List<dynamic>> searchFoods(String query, int limit);
}

class NutritionRemoteDataSourceImpl implements INutritionRemoteDataSource {
  final Dio _dio = ApiClient.dio;

  @override
  Future<List<dynamic>> searchFoods(String query, int limit) async {
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
      return (data is Map && data['foods'] is List)
          ? data['foods'] as List<dynamic>
          : (data is List ? data as List<dynamic> : []);
    }
    return [];
  }

  @override
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

  @override
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
    throw Exception('Failed to generate plan');
  }

  @override
  Future<bool> addMeal(Map<String, dynamic> body) async {
    final response = await _dio.post(ApiConfig.addMealEndpoint, data: body);
    return response.statusCode == 200 || response.statusCode == 201;
  }

  @override
  Future<bool> updateWater(String date, int amountMl) async {
    final response = await _dio.post(
      ApiConfig.updateWaterEndpoint,
      data: {"date": date, "amount_ml": amountMl},
    );
    return response.statusCode == 200 || response.statusCode == 201;
  }

  @override
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

  @override
  Future<bool> resetDay(String dateStr) async {
    final response = await _dio.post(
      '${ApiConfig.baseUrl}/api/nutrition/reset-day',
      data: {"date": dateStr},
    );
    return response.statusCode == 200;
  }

  @override
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
      formData.files.add(MapEntry(
        'file',
        MultipartFile.fromBytes(bytes,
            filename: imageFile.name, contentType: MediaType('image', 'jpeg')),
      ));
    }

    final response = await _dio.post(
      ApiConfig.logStoryEndpoint,
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    return response.statusCode == 200 || response.statusCode == 201;
  }

  @override
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

  @override
  Future<bool> deleteLogStory(String logId) async {
    final response = await _dio.delete('${ApiConfig.logStoryEndpoint}/$logId');
    return response.statusCode == 200 || response.statusCode == 204;
  }

  @override
  Future<Map<String, dynamic>> analyzeFoodImage(XFile imageFile) async {
    final formData = FormData();
    final bytes = await imageFile.readAsBytes();
    formData.files.add(MapEntry(
      'image',
      MultipartFile.fromBytes(bytes,
          filename: imageFile.name, contentType: MediaType('image', 'jpeg')),
    ));

    final response = await _dio.post(
      ApiConfig.analyzeFoodImageEndpoint,
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );

    if (response.statusCode == 200 && response.data != null) {
      return response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
    }
    throw Exception('Failed to analyze image');
  }

  @override
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

  @override
  Future<Map<String, dynamic>> createCustomFood(
      Map<String, dynamic> body) async {
    final response =
        await _dio.post('${ApiConfig.baseUrl}/api/nutrition/foods', data: body);
    if (response.statusCode == 200 && response.data != null) {
      return response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
    }
    throw Exception('Failed to create custom food');
  }

  @override
  Future<Map<String, dynamic>> getWeeklyReport(String startDate) async {
    final response = await _dio.get(
      '/api/nutrition/report/weekly',
      queryParameters: {'start_date': startDate},
    );
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> swapMeal({
    required String dateStr,
    required String oldMealName,
    required String mealType,
    required String goal,
  }) async {
    final response = await _dio.post(
      '${ApiConfig.baseUrl}/api/nutrition/swap-meal',
      data: {
        'date': dateStr,
        'old_meal_name': oldMealName,
        'meal_type': mealType,
        'goal': goal,
      },
    );
    if (response.statusCode == 200 && response.data != null) {
      return response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
    }
    throw Exception('Failed to swap meal');
  }

  @override
  Future<bool> swapLoggedMealSimple(String dateStr, String logId) async {
    final response = await _dio.post(
      '${ApiConfig.baseUrl}/api/nutrition/logs/$logId/swap-simple',
      data: {'date': dateStr},
    );
    return response.statusCode == 200;
  }
}
