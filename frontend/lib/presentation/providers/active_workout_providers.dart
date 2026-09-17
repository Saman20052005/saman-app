import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/exercise.dart';
import '../providers/active_workout_state.dart';

part 'active_workout_providers.g.dart';

// Provider for last weight per exercise
final lastWeightProviderProvider =
    Provider.family<double, String>((ref, exerciseId) {
  return 20.0; // Default 20kg
});

@riverpod
class ActiveWorkoutNotifier extends _$ActiveWorkoutNotifier {
  CurrentSetState _setState = const CurrentSetState(reps: 0, weight: 0);

  @override
  ActiveWorkoutState build() {
    return const ActiveWorkoutState(
      exercises: [],
      currentExerciseIndex: 0,
      currentSetIndex: 0,
      completedLogs: [],
    );
  }

  void startSession(List<Exercise> exercises) {
    if (exercises.isEmpty) return;
    state = ActiveWorkoutState(
      exercises: exercises,
      currentExerciseIndex: 0,
      currentSetIndex: 0,
      completedLogs: [],
    );
    _initCurrentSet();
  }

  void _initCurrentSet() {
    final exercise = state.currentExercise!;
    final defaultReps =
        int.tryParse(exercise.defaultReps.split('-').first) ?? 8;
    // Lấy weight từ lịch sử (sẽ implement sau)
    final lastWeight = _getLastWeightForExercise(exercise.id);
    _setState = CurrentSetState(
      reps: defaultReps,
      weight: lastWeight,
      isResting: false,
      restSecondsLeft: exercise.restSeconds,
    );
  }

  double _getLastWeightForExercise(String exerciseId) {
    // Get last weight from history provider
    return ref.read(lastWeightProviderProvider(exerciseId));
  }

  void updateReps(int reps) {
    _setState = _setState.copyWith(reps: reps.clamp(0, 999));
  }

  void updateWeight(double weight) {
    _setState = _setState.copyWith(weight: weight.clamp(0.0, 500.0));
  }

  void startRest() {
    _setState = _setState.copyWith(
      isResting: true,
      restSecondsLeft: state.currentExercise!.restSeconds,
    );
  }

  void tickRest() {
    if (_setState.restSecondsLeft > 0) {
      _setState =
          _setState.copyWith(restSecondsLeft: _setState.restSecondsLeft - 1);
      if (_setState.restSecondsLeft == 0) {
        _setState = _setState.copyWith(isResting: false);
      }
    }
  }

  void skipRest() {
    _setState = _setState.copyWith(isResting: false, restSecondsLeft: 0);
  }

  void completeCurrentSet() {
    final exercise = state.currentExercise!;
    final log = ExerciseSetLog(
      exerciseId: exercise.id,
      exerciseSlug: exercise.slug,
      setNumber: state.currentSetNumber,
      repsCompleted: _setState.reps,
      weightKg: _setState.weight,
      isCompleted: true,
      restTakenSeconds: exercise.restSeconds - _setState.restSecondsLeft,
    );

    final updatedLogs = [...state.completedLogs, log];
    final nextSetIndex = state.currentSetIndex + 1;

    if (nextSetIndex < exercise.defaultSets) {
      // Chuyển sang set tiếp theo của cùng bài
      state = state.copyWith(
        currentSetIndex: nextSetIndex,
        completedLogs: updatedLogs,
      );
      _initCurrentSet();
    } else {
      // Chuyển sang bài tiếp theo
      final nextExerciseIndex = state.currentExerciseIndex + 1;
      if (nextExerciseIndex < state.exercises.length) {
        state = state.copyWith(
          currentExerciseIndex: nextExerciseIndex,
          currentSetIndex: 0,
          completedLogs: updatedLogs,
        );
        _initCurrentSet();
      } else {
        // Hoàn thành toàn bộ
        state = state.copyWith(isFinished: true, completedLogs: updatedLogs);
      }
    }
  }

  // Getter để UI lấy thông tin set hiện tại
  CurrentSetState get currentSetState => _setState;
}
