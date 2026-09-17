import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/workout_home_providers.dart';
import '../providers/muscle_group_providers.dart';
import '../widgets/exercise_card.dart';
import '../widgets/muscle_group_card.dart';
import '../../core/constants/app_dimens.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Workout',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
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
        padding: const EdgeInsets.all(AppDimens.paddingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Search Bar (tích hợp navigate tới Library)
            GestureDetector(
              onTap: () => _navigateToLibrary(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.grey),
                    const SizedBox(width: 12),
                    Text(
                      'Search workouts or exercises...',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const Spacer(),
                    const Icon(Icons.mic, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 2. Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filters.map((filter) {
                  final isSelected = _selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(filter),
                      selected: isSelected,
                      onSelected: (_) =>
                          setState(() => _selectedFilter = filter),
                      backgroundColor: Colors.grey[100],
                      selectedColor: Colors.black,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                        fontWeight: isSelected ? FontWeight.w600 : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 32),

            // 3. Featured Workout
            _buildFeaturedWorkout(context),
            const SizedBox(height: 32),

            // 4. Weekly Goal
            _buildWeeklyGoal(weeklyGoal, ref),
            const SizedBox(height: 32),

            // 5. Popular Exercises
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Popular exercises',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                TextButton(
                  onPressed: () => _navigateToLibrary(context),
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            popularAsync.when(
              data: (exercises) => ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: exercises.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => ExerciseCard(
                  exercise: exercises[i],
                  onTap: () => _navigateToExerciseDetail(context, exercises[i]),
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Column(
                  children: [
                    const Text('Unable to load popular exercises'),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => ref.invalidate(popularExercisesProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // 6. Browse by muscle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Browse by muscle',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                TextButton(
                  onPressed: () => _navigateToLibrary(context),
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            muscleGroupsAsync.when(
              data: (groups) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.6,
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
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Text('Unable to load muscle groups'),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToCreatePlan(context),
        icon: const Icon(Icons.add),
        label: const Text('Create Plan'),
        elevation: 2,
      ),
    );
  }

  Widget _buildFeaturedWorkout(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF2D2D2D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WORKOUT',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Full Body Power',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '45 Min · Intermediate · Boost your overall strength',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const Spacer(),
          SizedBox(
            height: 44,
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
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WEEKLY GOAL',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$activeDays/$target Days Active',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white24,
              color: Colors.green,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
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
                      color: active ? Colors.green : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: active ? Colors.green : Colors.white38,
                        width: 2,
                      ),
                    ),
                    child: active
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    day,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
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
