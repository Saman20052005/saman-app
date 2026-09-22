import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/workout_home_providers.dart';
import '../providers/muscle_group_providers.dart';
import '../widgets/exercise_card.dart';
import '../widgets/muscle_group_card.dart';
import '../../config/app_theme.dart';
import '../../data/models/exercise.dart';
import 'create_plan_screen.dart';
import 'muscle_group_screen.dart';
import 'active_workout_screen.dart';
import 'exercise_detail_screen.dart';
import 'exercise_list_screen.dart';
import 'my_plans_screen.dart';

class WorkoutHomeScreen extends ConsumerStatefulWidget {
  const WorkoutHomeScreen({super.key});

  @override
  ConsumerState<WorkoutHomeScreen> createState() => _WorkoutHomeScreenState();
}

class _WorkoutHomeScreenState extends ConsumerState<WorkoutHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All';

  final List<String> _filters = ['All', 'Strength', 'Cardio', 'Core', 'Yoga'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final popularAsync = ref.watch(popularExercisesProvider);
    final weeklyGoal = ref.watch(weeklyGoalNotifierProvider);
    final muscleGroupsAsync = ref.watch(featuredMuscleGroupsProvider);
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Workout',
          style: textTheme.headlineMedium?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
        backgroundColor: context.bgColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyPlansScreen()),
            ),
            tooltip: 'My Plans',
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.xxxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Search Bar (tích hợp navigate tới Library)
            Material(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () => _navigateToLibrary(context),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: context.trackColor,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: colors.outline),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: colors.secondary),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'Search workouts or exercises...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colors.secondary,
                          ),
                        ),
                      ),
                      Icon(Icons.mic_outlined, color: colors.secondary),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // 2. Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filters.map((filter) {
                  final isSelected = _selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: FilterChip(
                      label: Text(filter),
                      selected: isSelected,
                      onSelected: (_) =>
                          setState(() => _selectedFilter = filter),
                      backgroundColor: context.surfaceColor,
                      selectedColor: colors.primary,
                      side: BorderSide(
                        color: isSelected ? colors.primary : colors.outline,
                      ),
                      labelStyle: TextStyle(
                        color: isSelected ? colors.onPrimary : colors.onSurface,
                        fontWeight: isSelected ? FontWeight.w600 : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // 3. Featured Workout
            _buildFeaturedWorkout(context),
            const SizedBox(height: AppSpacing.xxl),

            // 4. Weekly Goal
            _buildWeeklyGoal(weeklyGoal, ref),
            const SizedBox(height: AppSpacing.xxl),

            // 5. Popular Exercises
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Popular exercises',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextButton(
                  onPressed: () => _navigateToLibrary(context),
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            popularAsync.when(
              data: (exercises) => ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: exercises.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, i) => ExerciseCard(
                  exercise: exercises[i],
                  onTap: () => _navigateToExerciseDetail(context, exercises[i]),
                ),
              ),
              loading: () => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(
                  child: CircularProgressIndicator(color: colors.primary),
                ),
              ),
              error: (err, stack) => Center(
                child: Column(
                  children: [
                    Text(
                      'Unable to load popular exercises',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.secondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: () => ref.invalidate(popularExercisesProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // 6. Browse by muscle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Browse by muscle',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextButton(
                  onPressed: () => _navigateToLibrary(context),
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            muscleGroupsAsync.when(
              data: (groups) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  childAspectRatio: 0.95,
                ),
                itemCount: groups.length,
                itemBuilder: (context, index) {
                  final group = groups[index];
                  return MuscleGroupCard(
                    group: group,
                    onTap: () => _navigateToExerciseList(
                        context, group.slug, group.nameVi),
                    heroTag: group.slug,
                  );
                },
              ),
              loading: () => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(
                  child: CircularProgressIndicator(color: colors.primary),
                ),
              ),
              error: (_, __) => Text(
                'Unable to load muscle groups',
                style: textTheme.bodyMedium?.copyWith(color: colors.secondary),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToCreatePlan(context),
        icon: const Icon(Icons.add),
        label: const Text('Create Plan'),
        elevation: 0,
      ),
    );
  }

  Widget _buildFeaturedWorkout(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final extension = Theme.of(context).extension<AppThemeExtension>()!;

    return Container(
      height: 208,
      decoration: BoxDecoration(
        color: context.insightCardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WORKOUT',
            style: extension.labelCaps
                .copyWith(color: colors.onPrimary.withOpacity(0.7)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Full Body Power',
            style: textTheme.headlineMedium?.copyWith(
              color: colors.onPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '45 Min · Intermediate · Boost your overall strength',
            style: textTheme.bodyMedium?.copyWith(
              color: colors.onPrimary.withOpacity(0.72),
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: () async {
                final popularExercises =
                    ref.read(popularExercisesProvider).valueOrNull ??
                        const <Exercise>[];

                if (popularExercises.isEmpty) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Popular exercises are still loading.'),
                    ),
                  );
                  return;
                }

                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ActiveWorkoutScreen.fromExercises(
                      exercises: popularExercises.take(5).toList(),
                      title: 'Popular Workout',
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: const Text('Start',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyGoal(List<bool> weeklyGoal, WidgetRef ref) {
    final activeDays = weeklyGoal.where((e) => e).length;
    final target = 7;
    final progress = activeDays / target;
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final extension = Theme.of(context).extension<AppThemeExtension>()!;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: context.insightCardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WEEKLY GOAL',
            style: extension.labelCaps
                .copyWith(color: colors.onPrimary.withOpacity(0.7)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$activeDays/$target Days Active',
            style: textTheme.headlineMedium?.copyWith(
              color: colors.onPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: colors.onPrimary.withOpacity(0.2),
              color: colors.primary,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              final active = weeklyGoal[index];
              final day = ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index];
              return Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: active ? colors.primary : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: active
                            ? colors.primary
                            : colors.onPrimary.withOpacity(0.35),
                        width: 2,
                      ),
                    ),
                    child: active
                        ? Icon(Icons.check, color: colors.onPrimary, size: 20)
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    day,
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.onPrimary.withOpacity(0.72),
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  void _navigateToLibrary(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MuscleGroupScreen()),
    );
  }

  void _navigateToCreatePlan(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreatePlanScreen()),
    );
  }

  void _navigateToExerciseDetail(BuildContext context, Exercise exercise) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ExerciseDetailScreen(exercise: exercise)),
    );
  }

  void _navigateToExerciseList(BuildContext context, String slug, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseListScreen(
          muscleGroupSlug: slug,
          muscleGroupName: name,
        ),
      ),
    );
  }
}
