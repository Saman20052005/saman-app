import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/exercise.dart';
import 'create_plan_state.dart';
import 'exercise_providers.dart';
import 'my_plans_providers.dart';

part 'create_plan_providers.g.dart';

@riverpod
class CreatePlanNotifier extends _$CreatePlanNotifier {
  @override
  CreatePlanState build() {
    return const CreatePlanState(name: 'Plan mới', exercises: []);
  }

  void setName(String name) {
    state = state.copyWith(name: name);
  }

  void addExercise(Exercise exercise) {
    if (state.exercises.any((e) => e.id == exercise.id)) return;
    state = state.copyWith(
      exercises: [...state.exercises, exercise],
    );
  }

  void removeExercise(String id) {
    state = state.copyWith(
      exercises: state.exercises.where((e) => e.id != id).toList(),
    );
  }

  void reorderExercises(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final newList = [...state.exercises];
    final item = newList.removeAt(oldIndex);
    newList.insert(newIndex, item);
    state = state.copyWith(exercises: newList);
  }

  void clear() {
    state = const CreatePlanState(name: 'Plan mới', exercises: []);
  }

  Future<bool> savePlan({String? planId}) async {
    if (state.isSaving) return false;
    if (state.exercises.isEmpty || state.name.trim().isEmpty) {
      state = state.copyWith(error: 'Enter a name and add at least one exercise.');
      return false;
    }
    state = state.copyWith(isSaving: true, error: null);
    await ref.read(workoutDemoRepositoryProvider).savePlan(
      id: planId,
      name: state.name.trim(),
      exerciseIds: state.exercises.map((exercise) => exercise.id).toList(),
    );
    state = state.copyWith(isSaving: false);
    ref.invalidate(myPlansNotifierProvider);
    return true;
  }
  void clearError() {
    state = state.copyWith(error: null);
  }
}
