import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/workout_plan.dart';
import 'exercise_providers.dart';

part 'my_plans_providers.g.dart';

@riverpod
class MyPlansNotifier extends _$MyPlansNotifier {
  @override
  FutureOr<List<WorkoutPlan>> build() async {
    final repo = ref.watch(exerciseRepositoryProvider);
    return repo.getMyPlans();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(exerciseRepositoryProvider).getMyPlans());
  }

  Future<void> deletePlan(String id) async {
    final repo = ref.read(exerciseRepositoryProvider);
    await repo.deletePlan(id);
    await refresh();
  }
}
