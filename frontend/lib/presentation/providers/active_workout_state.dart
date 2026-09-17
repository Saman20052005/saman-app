import 'package:freezed_annotation/freezed_annotation.dart';
import '../../data/models/exercise.dart';

part 'active_workout_state.freezed.dart';

// --- State cho toàn bộ session ---
@freezed
class ActiveWorkoutState with _$ActiveWorkoutState {
  const factory ActiveWorkoutState({
    required List<Exercise> exercises,
    required int currentExerciseIndex,
    required int currentSetIndex,
    required List<ExerciseSetLog> completedLogs,
    @Default(false) bool isFinished,
  }) = _ActiveWorkoutState;

  const ActiveWorkoutState._(); // <- thêm dòng này

  Exercise? get currentExercise =>
      exercises.isNotEmpty ? exercises[currentExerciseIndex] : null;
  int get currentSetNumber => currentSetIndex + 1;
}

// --- State cho set đang thực hiện (riêng để dễ quản lý timer) ---
@freezed
class CurrentSetState with _$CurrentSetState {
  const factory CurrentSetState({
    required int reps,
    required double weight,
    @Default(false) bool isResting,
    @Default(0) int restSecondsLeft,
  }) = _CurrentSetState;
}
