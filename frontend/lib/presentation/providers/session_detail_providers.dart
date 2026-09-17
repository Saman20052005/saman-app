import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/models/exercise.dart';
import 'exercise_providers.dart';

part 'session_detail_providers.g.dart';

@riverpod
Future<WorkoutSession> sessionDetail(
    SessionDetailRef ref, String sessionId) async {
  final repo = ref.watch(exerciseRepositoryProvider);
  return repo.getSessionById(sessionId);
}
