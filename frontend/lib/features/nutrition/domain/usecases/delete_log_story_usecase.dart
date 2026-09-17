// lib/features/nutrition/domain/usecases/delete_log_story_usecase.dart
import '../repositories/nutrition_repository.dart';

class DeleteLogStoryUseCase {
  final INutritionRepository _repository;

  DeleteLogStoryUseCase(this._repository);

  Future<bool> execute(String logId) async {
    return await _repository.deleteLogStory(logId);
  }
}
