import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../providers/exercise_providers.dart';
import '../widgets/exercise_card.dart';
import '../../core/constants/app_dimens.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_colors.dart';
import 'exercise_detail_screen.dart';

class ExerciseListScreen extends ConsumerStatefulWidget {
  final String muscleGroupSlug;
  final String muscleGroupName;

  const ExerciseListScreen({
    super.key,
    required this.muscleGroupSlug,
    required this.muscleGroupName,
  });

  @override
  ConsumerState<ExerciseListScreen> createState() => _ExerciseListScreenState();
}

class _ExerciseListScreenState extends ConsumerState<ExerciseListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Lắng nghe thay đổi search để invalidate provider
    _searchController.addListener(() {
      ref
          .read(exerciseFiltersProvider.notifier)
          .setSearch(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(exercisesByMuscleProvider(
      muscleGroupSlug: widget.muscleGroupSlug,
      difficulty: ref.read(exerciseFiltersProvider).difficulty,
      search: ref.read(exerciseFiltersProvider).search,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(exerciseFiltersProvider);
    final exercisesAsync = ref.watch(exercisesByMuscleProvider(
      muscleGroupSlug: widget.muscleGroupSlug,
      difficulty: filters.difficulty,
      search: filters.search,
    ));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.muscleGroupName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.spacingMd),
            child: Column(
              children: [
                // Search
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: AppStrings.searchExercises,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                ),
                const SizedBox(height: 12),
                // Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('all', 'Tất cả'),
                      _buildFilterChip('beginner', 'Beginner'),
                      _buildFilterChip('intermediate', 'Intermediate'),
                      _buildFilterChip('advanced', 'Advanced'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: exercisesAsync.when(
          data: (exercises) {
            if (exercises.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.fitness_center,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      AppStrings.noExercisesFound,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.tryDifferentFilter,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              );
            }
            return AnimationLimiter(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(AppDimens.spacingMd),
                itemCount: exercises.length,
                itemBuilder: (context, index) {
                  final exercise = exercises[index];
                  return AnimationConfiguration.staggeredList(
                    position: index,
                    duration: const Duration(milliseconds: 375),
                    child: SlideAnimation(
                      verticalOffset: 50.0,
                      child: FadeInAnimation(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ExerciseCard(
                            exercise: exercise,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ExerciseDetailScreen(exercise: exercise),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Lỗi: $err'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _refresh,
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = ref.watch(exerciseFiltersProvider).difficulty == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Text(label),
        onSelected: (_) {
          ref.read(exerciseFiltersProvider.notifier).setDifficulty(value);
        },
        backgroundColor: Colors.grey[100],
        selectedColor: value == 'all'
            ? AppColors.primary
            : value == 'beginner'
                ? AppColors.success
                : value == 'intermediate'
                    ? AppColors.warning
                    : AppColors.error,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.black,
          fontWeight: isSelected ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}
