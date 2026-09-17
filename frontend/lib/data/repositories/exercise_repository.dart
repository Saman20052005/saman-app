import '../models/exercise.dart';
import '../models/muscle_group.dart';
import '../models/workout_plan.dart';

abstract class ExerciseRepository {
  Future<List<MuscleGroup>> getMuscleGroups();

  Future<List<Exercise>> getExercisesByMuscleGroup({
    required String muscleGroupSlug,
    String? difficulty,
    String? search,
  });

  Future<List<Exercise>> getPopularExercises({int limit = 6});

  Future<void> saveWorkoutSession(WorkoutSession session);

  Future<List<WorkoutSession>> getWorkoutHistory();

  Future<List<WorkoutPlan>> getMyPlans();

  Future<void> deletePlan(String planId);

  Future<WorkoutPlan> getPlanById(String id);

  Future<Exercise> getExerciseById(String id);

  Future<WorkoutSession> getSessionById(String sessionId);
}
