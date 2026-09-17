// lib/features/nutrition/domain/usecases/swap_meal_usecase.dart
import '../../../../models/nutrition_model.dart';
import '../../../../models/nutrition_model.dart';
import '../repositories/nutrition_repository.dart';

class SwapMealUseCase {
  final INutritionRepository _repository;

  SwapMealUseCase(this._repository);

  Future<NutritionPlan> execute({
    required DateTime date,
    required Meal oldMeal,
    required String goal,
  }) async {
    final dateStr =
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    return await _repository.swapMeal(dateStr, oldMeal, goal);
  }
}
