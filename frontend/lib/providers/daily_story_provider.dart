// lib/providers/daily_story_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../models/meal_log.dart';
import '../models/ai_analysis_result.dart';
import '../services/api_client.dart';
import '../config/api_config.dart';
import '../services/nutrition_service.dart';
import '../features/nutrition/domain/repositories/nutrition_repository.dart'
    show ConfirmLogException, ConfirmLogFailureStage;
import '../features/nutrition/data/datasources/nutrition_remote_data_source.dart';
import '../screens/nutrition/widgets/meal_review_dialog.dart' show MealLogData;
import '../presentation/providers/workout_history_providers.dart';
import '../utils/auth_helper.dart';
import 'nutrition_provider.dart';
export '../features/nutrition/domain/repositories/nutrition_repository.dart'
    show ConfirmLogException, ConfirmLogFailureStage;

final nutritionServiceProvider = Provider<NutritionService>((ref) {
  return NutritionService();
});

class _SaveProgress {
  final MealLogData data;
  _SaveProgress(this.data);
  String? storyId;
  bool mealSaved = false;
  ConfirmLogException? uncertain;
}

class _SaveTracker {
  bool busy = false;
  final operations = Map<Object, _SaveProgress>.identity();
}

// Survives autoDispose/recreation, scoped to this container and auth generation.
// No token, image or operation state is persisted on disk.
final _saveTrackerProvider = Provider.family<_SaveTracker, (int, String)>(
    (ref, key) => _SaveTracker());

class DailyStoryController
    extends AutoDisposeFamilyAsyncNotifier<List<MealLog>, String> {
  bool _alive = false;
  int _buildEpoch = 0;

  @override
  Future<List<MealLog>> build(String arg) async {
    final epoch = ++_buildEpoch;
    _alive = true;
    ref.onDispose(() => _alive = false);
    ref.watch(workoutAuthScopeProvider);
    final loggingOut = ref.watch(authLoggingOutProvider);
    final service = ref.watch(nutritionServiceProvider);
    final session = ref.watch(nutritionSessionProvider);
    if (loggingOut) return [];
    try {
      final owner = await session.capture();
      final rawStories = await service.getLogStories(arg);
      await owner.validate();
      if (!_alive || epoch != _buildEpoch) return [];
      return _parseStories(rawStories);
    } on NutritionSessionChanged {
      return [];
    }
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

  Future<AIAnalysisResult?> analyzeImage(XFile imageFile,
      {String? mode, NutritionRequestContext? session}) async {
    final epoch = _buildEpoch;
    final guard = ref.read(nutritionSessionProvider);
    final service = ref.read(nutritionServiceProvider);
    final owner = session ?? await guard.capture();
    await _validate(owner, epoch);
    try {
      final result = await service.analyzeFoodImage(imageFile,
          mode: mode, session: owner);
      await _validate(owner, epoch);
      if (result == null) throw StateError('Food analysis unavailable');
      return result;
    } on DioException catch (e) {
      await _validate(owner, epoch);
      if (e.response?.statusCode == 401) await guard.recoverAuthorization();
      rethrow;
    }
  }

  Future<void> _validate(NutritionRequestContext owner, int epoch) async {
    if (!_alive || epoch != _buildEpoch) throw const NutritionSessionChanged();
    await owner.validate();
    if (!_alive || epoch != _buildEpoch) throw const NutritionSessionChanged();
  }

  Future<void> confirmLog(MealLogData data,
      {XFile? imageFile, NutritionRequestContext? session}) async {
    final epoch = _buildEpoch;
    final guard = ref.read(nutritionSessionProvider);
    final owner = session ?? await guard.capture();
    await _validate(owner, epoch);
    final tracker = ref.read(_saveTrackerProvider((owner.generation, arg)));
    if (tracker.busy) {
      throw const ConfirmLogException(ConfirmLogFailureStage.busy,
          'This meal is already being saved. Please wait.');
    }
    final progress = tracker.operations.putIfAbsent(imageFile ?? data, () => _SaveProgress(data));
    if (progress.storyId != null &&
        (data.foodName != progress.data.foodName ||
         data.foodLabel != progress.data.foodLabel ||
         data.mealType != progress.data.mealType || data.grams != progress.data.grams ||
         data.calories != progress.data.calories || data.protein != progress.data.protein ||
         data.carbs != progress.data.carbs || data.fat != progress.data.fat)) {
      throw const ConfirmLogException(ConfirmLogFailureStage.changedInput,
          'This photo already has a confirmed save operation. Check your diary before logging different meal details.');
    }
    data = progress.data;
    if (progress.uncertain != null) throw progress.uncertain!;
    if (progress.mealSaved) return;
    tracker.busy = true;
    final dio = ref.read(dioProvider);
    NutritionRemoteDataSourceImpl.installSessionGuard(dio);
    final options = Options(extra: {'nutritionSession': owner});
    bool dispatched = false;
    try {
      if (progress.storyId == null) {
        final formData = FormData.fromMap({
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
        });
        if (imageFile != null) {
          final bytes = await imageFile.readAsBytes();
          await _validate(owner, epoch);
          formData.files.add(MapEntry('file', MultipartFile.fromBytes(bytes,
              filename: imageFile.name, contentType: MediaType('image', 'jpeg'))));
        }
        await _validate(owner, epoch);
        dispatched = true;
        final response = await dio.post(ApiConfig.logStoryEndpoint,
            data: formData, options: options);
        // Record confirmed progress even if the originating provider was disposed.
        // This tracker belongs only to its captured auth generation.
        await owner.validate();
        final storyId = response.data is Map ? response.data['log_id']?.toString() : null;
        if (storyId == null || storyId.isEmpty) {
          throw StateError('Story save was not confirmed');
        }
        progress.storyId = storyId;
        dispatched = false;
        await _validate(owner, epoch);
      }
      await _validate(owner, epoch);
      dispatched = true;
      final mealResponse = await dio.post('${ApiConfig.baseUrl}/api/nutrition/logs', options: options,
          data: {
        'date': arg,
        'meal_type': data.mealType,
        'total_calories': data.calories.round(),
        'notes': '',
        'story_id': progress.storyId,
        'foods': [{
          'name': data.foodName,
          'food_label': data.foodLabel,
          'weight_grams': data.grams.round(),
          'calories': data.calories.round(),
          'protein': data.protein,
          'carbs': data.carbs,
          'fat': data.fat,
          'food_id': '',
        }],
      });
      if (mealResponse.statusCode != 200 && mealResponse.statusCode != 201) {
        throw StateError('Meal save was not confirmed');
      }
      await owner.validate();
      progress.mealSaved = true;
      dispatched = false;
      await _validate(owner, epoch);
      ref.invalidate(nutritionProvider);
      ref.invalidateSelf();
    } on NutritionSessionChanged {
      rethrow;
    } catch (error) {
      final sessionChanged = error is DioException &&
          error.error is NutritionSessionChanged;
      if (sessionChanged) throw const NutritionSessionChanged();
      // Only explicit client rejection / failure before dispatch permits retry.
      // Timeouts, transport loss and server errors can follow a committed write.
      final definite = !dispatched || (error is DioException &&
          (error.type == DioExceptionType.connectionTimeout ||
          (error.response != null && error.response!.statusCode! >= 400 &&
           error.response!.statusCode! < 500 && error.response!.statusCode != 408)));
      final storySaved = progress.storyId != null;
      final failure = ConfirmLogException(
        storySaved ? ConfirmLogFailureStage.meal : ConfirmLogFailureStage.story,
        definite
            ? (storySaved
                ? 'Photo saved, but the meal was not logged. Retry to save the meal.'
                : 'The photo was not saved. Please try again.')
            : (storySaved
                ? 'Photo saved. Meal save is unconfirmed. Check your diary before trying again.'
                : 'Photo save is unconfirmed. Check your diary before trying again.'),
        storySaved: storySaved,
        outcomeUnknown: !definite,
      );
      await owner.validate();
      if (!definite) progress.uncertain = failure;
      await _validate(owner, epoch);
      if (error is DioException && error.response?.statusCode == 401) {
        await guard.recoverAuthorization();
      }
      throw failure;
    } finally {
      tracker.busy = false;
    }
  }

  Future<void> saveStoryWithoutAI({
    required XFile imageFile,
    required String mealType,
    required String note,
  }) async {
    // Backend defaults unknown nutrition to zero. Never dispatch this branch.
    throw const ConfirmLogException(ConfirmLogFailureStage.photoOnly,
        'Photo-only saving is currently unavailable. Keep the photo and try analysis again, or cancel.');
  }

  Future<void> deleteStory(String logId) async {
    final epoch = _buildEpoch;
    final owner = await ref.read(nutritionSessionProvider).capture();
    final dio = ref.read(dioProvider);
    NutritionRemoteDataSourceImpl.installSessionGuard(dio);
    await _validate(owner, epoch);
    await dio.delete('${ApiConfig.baseUrl}/api/nutrition/log-story/$logId',
        options: Options(extra: {'nutritionSession': owner}));
    await _validate(owner, epoch);
    ref.invalidateSelf();
  }
}

final dailyStoryControllerProvider = AsyncNotifierProvider.family
    .autoDispose<DailyStoryController, List<MealLog>, String>(
  DailyStoryController.new,
);
