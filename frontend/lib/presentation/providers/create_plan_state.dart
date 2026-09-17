import 'package:freezed_annotation/freezed_annotation.dart';
import '../../data/models/exercise.dart';

part 'create_plan_state.freezed.dart';

@freezed
class CreatePlanState with _$CreatePlanState {
  const factory CreatePlanState({
    required String name,
    required List<Exercise> exercises,
    @Default(false) bool isSaving,
    String? error,
  }) = _CreatePlanState;
}
