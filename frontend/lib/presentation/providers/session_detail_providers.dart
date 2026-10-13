import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/exercise.dart';
import 'workout_history_providers.dart';

part 'session_detail_providers.g.dart';

@riverpod
Future<WorkoutSession> sessionDetail(
    SessionDetailRef ref, String sessionId) async {
  ref.watch(workoutAuthScopeProvider);
  final repo = ref.watch(workoutSessionRepositoryProvider);
  return repo.getSessionById(sessionId);
}
