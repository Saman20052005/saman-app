class WorkoutPlan {
  final String? id;
  final String title;
  final String category;
  final String level;
  final int duration;
  final int kcal;
  final String? imageUrl;
  final List<WorkoutExercise> exercises;

  WorkoutPlan({
    this.id,
    required this.title,
    required this.category,
    required this.level,
    required this.duration,
    required this.kcal,
    this.imageUrl,
    required this.exercises,
  });
}

class WorkoutExercise {
  final String name;
  final String reps; // e.g., "4 sets x 12 reps"
  final int setCount;

  WorkoutExercise({
    required this.name,
    required this.reps,
    required this.setCount,
  });
}
