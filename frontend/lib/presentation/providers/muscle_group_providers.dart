import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/muscle_group_repository.dart';
import '../../data/models/muscle_group.dart';

// Provider for MuscleGroupRepository
final muscleGroupRepositoryProvider = Provider<MuscleGroupRepository>((ref) {
  return MuscleGroupRepository();
});

// Provider for featured muscle groups
final featuredMuscleGroupsProvider =
    FutureProvider<List<MuscleGroup>>((ref) async {
  final repository = ref.watch(muscleGroupRepositoryProvider);
  return repository.getFeaturedMuscleGroups(limit: 4);
});

// Provider for all muscle groups
final muscleGroupsProvider =
    FutureProvider.autoDispose<List<MuscleGroup>>((ref) async {
  final repository = ref.watch(muscleGroupRepositoryProvider);
  return repository.getAllMuscleGroups();
});

// Provider for muscle group by slug
final muscleGroupBySlugProvider =
    FutureProvider.family<MuscleGroup, String>((ref, slug) async {
  final repository = ref.watch(muscleGroupRepositoryProvider);
  return repository.getMuscleGroupBySlug(slug);
});
