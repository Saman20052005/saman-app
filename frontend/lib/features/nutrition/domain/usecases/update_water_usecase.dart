// lib/features/nutrition/domain/usecases/update_water_usecase.dart
import '../repositories/nutrition_repository.dart';

class UpdateWaterUseCase {
  final INutritionRepository _repository;

  UpdateWaterUseCase(this._repository);

  Future<bool> execute({required String date, required int amountMl}) async {
    return await _repository.updateWater(date, amountMl);
  }
}
