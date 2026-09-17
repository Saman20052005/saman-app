// lib/features/nutrition/domain/usecases/get_log_stories_usecase.dart
import '../repositories/nutrition_repository.dart';

class GetLogStoriesUseCase {
  final INutritionRepository _repository;

  GetLogStoriesUseCase(this._repository);

  Future<List<Map<String, dynamic>>> execute(String date) async {
    return await _repository.getLogStories(date);
  }
}
