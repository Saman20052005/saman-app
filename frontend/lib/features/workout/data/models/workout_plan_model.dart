import '../../domain/entities/workout_plan.dart';

class WorkoutPlanModel extends WorkoutPlan {
  WorkoutPlanModel({
    super.id,
    required super.title,
    required super.category,
    required super.level,
    required super.duration,
    required super.kcal,
    super.imageUrl,
    required super.exercises,
  });

  factory WorkoutPlanModel.fromJson(Map<String, dynamic> json) {
    return WorkoutPlanModel(
      id: json['_id'] ?? json['id'],
      title: json['title'] ?? json['name'] ?? 'Untitled Workout',
      category: json['category'] ??
          (json['target_muscles'] is List &&
                  (json['target_muscles'] as List).isNotEmpty
              ? (json['target_muscles'] as List).first
              : 'General'),
      level: json['level'] ?? json['difficulty'] ?? 'Beginner',
      // Xử lý duration có thể là string "45 min" hoặc số phút
      duration: _parseDuration(json['duration'] ??
          json['duration_minutes'] ??
          json['estimated_duration']),
      kcal: json['kcal'] ?? json['calories_burned'] ?? 0,
      imageUrl: json['image'] ?? json['image_url'],
      exercises: (json['exercises'] as List? ?? [])
          .map((e) => WorkoutExerciseModel.fromJson(e))
          .toList(),
    );
  }

  static int _parseDuration(dynamic val) {
    if (val is int) return val;
    if (val is String) {
      return int.tryParse(val.replaceAll(RegExp(r'[^0-9]'), '')) ?? 30;
    }
    return 30;
  }

  Map<String, dynamic> toJson() {
    return {
      "name": title,
      "description": "Custom workout plan",
      "difficulty": level.toLowerCase(),
      "duration_minutes": duration,
      "target_muscles": [category],
      "exercises":
          exercises.map((e) => (e as WorkoutExerciseModel).toJson()).toList(),
    };
  }
}

class WorkoutExerciseModel extends WorkoutExercise {
  WorkoutExerciseModel(
      {required super.name, required super.reps, required super.setCount});

  factory WorkoutExerciseModel.fromJson(Map<String, dynamic> json) {
    return WorkoutExerciseModel(
      name: json['name'] ?? 'Unknown Exercise',
      reps: json['reps']?.toString() ?? '12',
      setCount: json['sets'] ?? json['set_count'] ?? 3,
    );
  }

  Map<String, dynamic> toJson() {
    // Backend expects reps as int, we try to parse it
    int repsInt = int.tryParse(reps.replaceAll(RegExp(r'[^0-9]'), '')) ?? 12;
    return {
      "name": name,
      "reps": repsInt,
      "sets": setCount,
      "rest_time": 60, // Default rest time
    };
  }
}
