import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/exercise.dart';
import 'exercise_providers.dart';

// Provider for popular exercises
final popularExercisesProvider = FutureProvider<List<Exercise>>((ref) async {
  final repo = ref.watch(exerciseRepositoryProvider);
  return repo.getPopularExercises(limit: 6);
});

// Provider for weekly goal
final weeklyGoalNotifierProvider =
    StateNotifierProvider<WeeklyGoalNotifier, List<bool>>((ref) {
  return WeeklyGoalNotifier();
});

class WeeklyGoalNotifier extends StateNotifier<List<bool>> {
  WeeklyGoalNotifier() : super(List.generate(7, (i) => i < 2));

  void markTodayAsActive() {
    final today = DateTime.now().weekday - 1; // 0 = Monday, 6 = Sunday
    final newState = [...state];
    if (!newState[today]) {
      newState[today] = true;
      state = newState;
      // Lưu vào local storage
    }
  }
}
