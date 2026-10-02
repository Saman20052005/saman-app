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
    }
  }
}

// ─── Design-Driven Models & Providers for Workout Home ──────────────

class ScheduledSessionInfo {
  final String protocol;
  final String title;
  final int durationMinutes;
  final int exerciseCount;
  final String imageUrl;
  final String status;

  const ScheduledSessionInfo({
    required this.protocol,
    required this.title,
    required this.durationMinutes,
    required this.exerciseCount,
    required this.imageUrl,
    this.status = 'Planned',
  });
}

class UpcomingPlanSession {
  final String dayName;
  final String dayNumber;
  final String title;
  final String metrics;
  final String badge;
  final bool isRest;

  const UpcomingPlanSession({
    required this.dayName,
    required this.dayNumber,
    required this.title,
    required this.metrics,
    required this.badge,
    this.isRest = false,
  });
}

class RecentWorkoutSummary {
  final String title;
  final String relativeTime;
  final String metrics;

  const RecentWorkoutSummary({
    required this.title,
    required this.relativeTime,
    required this.metrics,
  });
}

/// Illustrative scheduled workout session provided via Riverpod
final scheduledWorkoutProvider = Provider<ScheduledSessionInfo>((ref) {
  return const ScheduledSessionInfo(
    protocol: 'Upper Body Protocol',
    title: 'Upper Body Strength',
    durationMinutes: 50,
    exerciseCount: 5,
    imageUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuBgWvtzvWGeJfEEROJJeouakHsiO-tUOGhvcow8DiMS33mS03q7PVqlt6q-foe7bz7-Rp2AybLJM2ODNEeAajirmXdGgREKng-sy-3XrS0N78Cjd9dGR9qTQ2zusfsBEFLHiZFL3r0aMxrwNtyLdxbTf1QXbc7j_l-d4wDbA_MJ7J1q72jnieVdQg-blP8l-w6kDsaTCqxGhKCkFnfyyD1TXKUcxg3gyCmM-nouFckNoo2jDR-KOW6H',
    status: 'Planned',
  );
});

/// Illustrative upcoming plan horizon provided via Riverpod
final upcomingPlansProvider = Provider<List<UpcomingPlanSession>>((ref) {
  return const [
    UpcomingPlanSession(
      dayName: 'Wed',
      dayNumber: '25',
      title: 'Lower Body Strength',
      metrics: '45 min · 5 exercises',
      badge: 'Planned',
      isRest: false,
    ),
    UpcomingPlanSession(
      dayName: 'Thu',
      dayNumber: '26',
      title: 'Active Recovery',
      metrics: '25 min flow · Mobility',
      badge: 'Rest & Flow',
      isRest: true,
    ),
  ];
});

/// Illustrative recent workout summary provided via Riverpod
final recentWorkoutSummaryProvider = Provider<RecentWorkoutSummary?>((ref) {
  return const RecentWorkoutSummary(
    title: 'Leg Day & Posterior Chain',
    relativeTime: 'Yesterday',
    metrics: '48 min • 5 exercises',
  );
});

