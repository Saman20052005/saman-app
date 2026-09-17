// lib/providers/daily_story_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';

import '../features/nutrition/domain/entities/meal.dart' as entity;
import '../models/meal_log.dart';
import '../models/ai_analysis_result.dart';
import '../services/api_client.dart';
import '../config/api_config.dart';
import '../services/nutrition_service.dart';
import 'nutrition_provider.dart';
// Note: MealReviewDialog import will be updated once moved

// Provider for the NutritionService singleton
final _nutritionServiceProvider = Provider<NutritionService>((ref) {
  return NutritionService();
});

// Data class for confirmLog (moved from meal_review_dialog.dart if needed,
// but it's defined in the dialog file usually. Let's keep it here for now or
// expect it from the dialog)

class DailyStoryController
    extends AutoDisposeFamilyAsyncNotifier<List<MealLog>, String> {
  @override
  Future<List<MealLog>> build(String arg) async {
    final service = ref.watch(_nutritionServiceProvider);
    final rawStories = await service.getLogStories(arg);
    return _parseStories(rawStories);
  }

  List<MealLog> _parseStories(List<Map<String, dynamic>> raw) {
    return raw.map((s) {
      return MealLog(
        id: (s['id'] ?? s['log_id'] ?? s['_id'] ?? '').toString(),
        foodName: (s['food_name'] ?? s['note'] ?? 'Món ăn').toString(),
        mealType: MealType.fromString((s['meal_type'] ?? 'snack').toString()),
        loggedAt: s['logged_at'] != null
            ? DateTime.tryParse(s['logged_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        imageUrl: s['image_url']?.toString(),
        note: s['note']?.toString(),
      );
    }).toList();
  }

  Future<AIAnalysisResult?> analyzeImage(XFile imageFile) async {
    try {
      final service = ref.read(_nutritionServiceProvider);
      final result = await service.analyzeFoodImage(imageFile);
      if (result == null) {
        throw Exception('AI không nhận diện được món ăn');
      }
      return result;
    } catch (e) {
      debugPrint('❌ analyzeImage error: $e');
      // Re-throw to let UI handle the error
      rethrow;
    }
  }

  Future<void> confirmLog(dynamic data, {XFile? imageFile}) async {
    // data is MealLogData from the dialog
    try {
      final formFields = {
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
      };

      final formData = FormData.fromMap(formFields);

      if (imageFile != null) {
        if (kIsWeb) {
          final bytes = await imageFile.readAsBytes();
          formData.files.add(MapEntry(
            'file',
            MultipartFile.fromBytes(
              bytes,
              filename: imageFile.name,
              contentType: MediaType('image', 'jpeg'),
            ),
          ));
        } else {
          formData.files.add(MapEntry(
            'file',
            await MultipartFile.fromFile(
              imageFile.path,
              filename: imageFile.name,
              contentType: MediaType('image', 'jpeg'),
            ),
          ));
        }
      }

      final storyResp = await ApiClient.dio.post(
        ApiConfig.logStoryEndpoint,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      final storyId = storyResp.data['log_id']?.toString();

      try {
        await ApiClient.dio.post(
          '${ApiConfig.baseUrl}/api/nutrition/logs',
          data: {
            'date': arg,
            'meal_type': data.mealType,
            'total_calories': data.calories.round(),
            'notes': '',
            'story_id': storyId,
            'foods': [
              {
                'name': data.foodName,
                'food_label': data.foodLabel,
                'weight_grams': data.grams.round(),
                'calories': data.calories.round(),
                'protein': data.protein,
                'carbs': data.carbs,
                'fat': data.fat,
                'food_id': '',
              }
            ],
          },
        );
      } catch (e) {
        debugPrint('Post to /api/nutrition/logs failed in confirmLog: $e');
      }

      ref.invalidateSelf();
      ref.invalidate(nutritionProvider);
    } catch (e, st) {
      debugPrint('confirmLog failed: $e');
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> saveStoryWithoutAI({
    required XFile imageFile,
    required String mealType,
    required String note,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final formData = FormData.fromMap({
        'meal_type': mealType,
        'note': note,
        'logged_at': DateTime.now().toIso8601String(),
        'food_name': note.isNotEmpty ? note : 'Unknown',
        'calories': '0',
        'protein': '0',
        'carbs': '0',
        'fat': '0',
        'grams': '100',
      });
      formData.files.add(MapEntry(
        'file',
        MultipartFile.fromBytes(
          bytes,
          filename: imageFile.name,
          contentType: MediaType('image', 'jpeg'),
        ),
      ));

      final storyResp =
          await ApiClient.dio.post(ApiConfig.logStoryEndpoint, data: formData);
      final storyId = storyResp.data['log_id']?.toString();

      try {
        await ApiClient.dio.post(
          '${ApiConfig.baseUrl}/api/nutrition/logs',
          data: {
            'date': arg,
            'meal_type': mealType,
            'total_calories': 0,
            'notes': note.isNotEmpty ? note : '',
            'story_id': storyId,
            'foods': [
              {
                'name': note.isNotEmpty ? note : 'Unknown',
                'food_label': note.isNotEmpty ? note.toLowerCase() : 'unknown',
                'weight_grams': 100,
                'calories': 0,
                'protein': 0.0,
                'carbs': 0.0,
                'fat': 0.0,
                'food_id': '',
              }
            ],
          },
        );
      } catch (e) {
        debugPrint(
            'Post to /api/nutrition/logs failed in saveStoryWithoutAI: $e');
      }

      ref.invalidateSelf();
      ref.invalidate(nutritionProvider);
    } catch (e, st) {
      debugPrint('saveStoryWithoutAI failed: $e');
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteStory(String logId) async {
    final previousState = state.valueOrNull;
    if (previousState != null) {
      state = AsyncValue.data(
        previousState.where((log) => log.id != logId).toList(),
      );
    }

    try {
      await ApiClient.dio.delete(
        '${ApiConfig.baseUrl}/api/nutrition/log-story/$logId',
      );
      ref.invalidateSelf();
    } catch (e) {
      debugPrint('❌ deleteStory failed: $e');
      if (previousState != null) {
        state = AsyncValue.data(previousState);
      }
    }
  }
}

final dailyStoryControllerProvider = AsyncNotifierProvider.family
    .autoDispose<DailyStoryController, List<MealLog>, String>(
  DailyStoryController.new,
);
