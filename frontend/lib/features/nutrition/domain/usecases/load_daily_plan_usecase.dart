// lib/features/nutrition/domain/usecases/load_daily_plan_usecase.dart
import '../../../../models/nutrition_model.dart';
import '../repositories/nutrition_repository.dart';

class LoadDailyPlanUseCase {
  final INutritionRepository _repository;

  LoadDailyPlanUseCase(this._repository);

  Future<NutritionPlan> execute(DateTime date) async {
    final dateStr =
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    final plan = await _repository.getDailyPlan(dateStr);

    if (plan.meals.isEmpty && plan.entries.isEmpty) {
      // Auto-generate if empty
      // In a real app, 'goal' might come from a UserProfile repository
      return await _repository.generatePlan(
        goal: 'maintain', // Default or from profile
        targetCalories: 0,
        remainingOnly: true,
      );
    }

    return plan;
  }
}
