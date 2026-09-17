import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../data/models/exercise.dart';
import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/exercise_repository_impl.dart';
import '../../services/api_client.dart';

part 'exercise_providers.g.dart';
part 'exercise_providers.freezed.dart';

@riverpod
Future<List<Exercise>> exercisesByMuscle(
  ExercisesByMuscleRef ref, {
  required String muscleGroupSlug,
  String difficulty = 'all',
  String search = '',
}) async {
  final repo = ref.watch(exerciseRepositoryProvider);
  return repo.getExercisesByMuscleGroup(
    muscleGroupSlug: muscleGroupSlug,
    difficulty: difficulty == 'all' ? null : difficulty,
    search: search.isEmpty ? null : search,
  );
}

@riverpod
ExerciseRepository exerciseRepository(ExerciseRepositoryRef ref) {
  final dio = ref.watch(dioProvider);
  return ExerciseRepositoryImpl(dio: dio);
}

// Provider cho filter state (dùng StateNotifier)
@riverpod
class ExerciseFilters extends _$ExerciseFilters {
  @override
  ExerciseFilterState build() => const ExerciseFilterState();

  void setDifficulty(String difficulty) {
    state = state.copyWith(difficulty: difficulty);
  }

  void setSearch(String search) {
    state = state.copyWith(search: search);
  }

  void reset() {
    state = const ExerciseFilterState();
  }
}

@freezed
class ExerciseFilterState with _$ExerciseFilterState {
  const factory ExerciseFilterState({
    @Default('all') String difficulty,
    @Default('') String search,
  }) = _ExerciseFilterState;
}
