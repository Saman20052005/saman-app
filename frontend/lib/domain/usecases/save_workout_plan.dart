import '../../data/models/workout_plan.dart';

class SaveWorkoutPlan {
  final Future<void> Function(WorkoutPlan plan) save;

  const SaveWorkoutPlan({required this.save});

  Future<void> call(WorkoutPlan plan) async {
    try {
      await save(plan);
    } catch (e) {
      throw Exception('Failed to save workout plan: $e');
    }
  }
}
