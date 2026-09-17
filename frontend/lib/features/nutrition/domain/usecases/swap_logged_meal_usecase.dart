// lib/features/nutrition/domain/usecases/swap_logged_meal_usecase.dart
import '../repositories/nutrition_repository.dart';

class SwapLoggedMealUseCase {
  final INutritionRepository _repository;

  SwapLoggedMealUseCase(this._repository);

  Future<bool> execute({required String date, required String logId}) async {
    return await _repository.swapLoggedMealSimple(date, logId);
  }
}
