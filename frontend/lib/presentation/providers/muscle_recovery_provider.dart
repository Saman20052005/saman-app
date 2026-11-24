import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/exercise.dart';
import '../../utils/auth_helper.dart';
import 'workout_history_providers.dart';

final muscleRecoveryProvider =
    FutureProvider.autoDispose<List<MuscleRecoveryItem>>((ref) async {
  ref.watch(workoutAuthScopeProvider);
  final isLoggingOut = ref.watch(authLoggingOutProvider);
  if (isLoggingOut) return const [];
  final token = await AuthHelper.getToken();
  if (token == null || token.isEmpty) return const [];
  final repo = ref.watch(workoutSessionRepositoryProvider);
  return repo.getMuscleRecovery();
});
