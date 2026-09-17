import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/exercise.dart';
import 'create_plan_state.dart';

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

  Future<void> savePlan(dynamic useCase) async {
    if (state.exercises.isEmpty) {
      state = state.copyWith(error: 'Chưa có bài tập nào trong Plan');
      return;
    }
    state = state.copyWith(isSaving: true, error: null);
    try {
      // TODO: Implement save plan logic
      final planData = {
        'name': state.name,
        'exerciseIds': state.exercises.map((e) => e.id).toList(),
      };

      // Simulate API call
      await Future.delayed(const Duration(seconds: 2));

      state = state.copyWith(
        isSaving: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        error: e.toString(),
      );
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}
