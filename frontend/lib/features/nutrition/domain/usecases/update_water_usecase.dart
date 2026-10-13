// lib/features/nutrition/domain/usecases/update_water_usecase.dart
import '../repositories/nutrition_repository.dart';

class UpdateWaterUseCase {
  final INutritionRepository _repository;

  UpdateWaterUseCase(this._repository);

  Future<bool> execute({
    required String date,
    int? amountMl,
    int? deltaMl,
    int? version,
    String? idempotencyKey,
  }) async {
    return await _repository.updateWater(
      date,
      amountMl,
      deltaMl: deltaMl,
      version: version,
      idempotencyKey: idempotencyKey,
    );
  }
}
