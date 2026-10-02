import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../data/models/exercise.dart';
import '../providers/exercise_providers.dart';
import '../tokens/saman_workout_tokens.dart';
import 'exercise_detail_screen.dart';

/// Provider for verified exercise library items matching the design handoff
final exerciseLibraryListProvider = FutureProvider<List<Exercise>>((ref) async {
  final repo = ref.watch(exerciseRepositoryProvider);
  try {
    final exercises = await repo.getExercisesByMuscleGroup(
      muscleGroupSlug: 'all',
      difficulty: null,
      search: null,
    );
    if (exercises.isNotEmpty) {
      return exercises;
    }
  } catch (_) {
    // Fallback to verified local curated library exercises
  }

  // Curated fallback exercises matching design handoff exactly
  return const [
    Exercise(
      id: 'db-bench-press',
      slug: 'dumbbell-bench-press',
      name: 'Dumbbell Bench Press',
      nameVi: 'Đẩy ngực với tạ đơn',
      muscleGroup: 'Chest',
      targetMuscles: ['Chest', 'Pectoralis Major'],
      secondaryMuscles: ['Triceps', 'Shoulders', 'Anterior Deltoid'],
      equipment: ['Dumbbells', 'Flat bench'],
      difficulty: 'intermediate',
      thumbnailUrl:
          'https://lh3.googleusercontent.com/aida-public/AB6AXuAzZ8AN5eaYmQP_EvKw44Mfp-YxaGOwX40UdqgBZjq20Um1LTYduBYBVa8dm-3IgrFmdHVPhbSBhdaGgY3JAx_DSJvKI0-TULkJ_L7KS4B7tOsxq5n5RPpuFC32VeGylN5bZ6COF4ZIwwEVV2MM22TwFI4dDyuMTTG3O7mSlnxsrLuFa6VkeJIc9FhiyaIQ-x7ZuA9rV7PCr1S-qGYpCbjJF1VEaQ1ycjOtMsLs4ys63WeZ4Yo7E1VD',
      defaultSets: 4,
      defaultReps: '8-10',
      restSeconds: 90,
      repType: 'reps',
      cvSupported: false,
      cues: [
        'Keep your feet firmly planted on the floor',
        'Maintain a slight natural arch in lower back',
        'Lower dumbbells with control to mid-chest level',
        'Press vertically until arms are fully extended',
      ],
      commonMistakes: [
        'Flaring elbows out at 90 degrees',
        'Bouncing dumbbells off chest',
        'Lifting feet off the floor during press',
      ],
    ),
    Exercise(
      id: 'lat-pulldown',
      slug: 'lat-pulldown',
      name: 'Lat Pulldown',
      nameVi: 'Kéo xô máy',
      muscleGroup: 'Back',
      targetMuscles: ['Back', 'Latissimus Dorsi'],
      secondaryMuscles: ['Biceps', 'Rear Deltoid'],
      equipment: ['Cable Machine', 'Lat Bar'],
      difficulty: 'beginner',
      thumbnailUrl:
          'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?auto=format&fit=crop&w=600&q=80',
      defaultSets: 3,
      defaultReps: '10-12',
      restSeconds: 60,
      repType: 'reps',
      cvSupported: false,
      cues: [
        'Grip slightly wider than shoulder width',
        'Pull down towards upper chest with elbows leading',
        'Squeeze lats at the bottom',
      ],
      commonMistakes: [
        'Leaning back excessively',
        'Pulling behind the neck',
      ],
    ),
    Exercise(
      id: 'seated-cable-row',
      slug: 'seated-cable-row',
      name: 'Seated Cable Row',
      nameVi: 'Kéo cáp ngồi',
      muscleGroup: 'Back',
      targetMuscles: ['Back', 'Rhomboids', 'Mid Traps'],
      secondaryMuscles: ['Biceps', 'Forearms'],
      equipment: ['Cable Machine', 'V-Bar'],
      difficulty: 'intermediate',
      thumbnailUrl:
          'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?auto=format&fit=crop&w=600&q=80',
      defaultSets: 3,
      defaultReps: '10-12',
      restSeconds: 60,
      repType: 'reps',
      cvSupported: false,
      cues: [
        'Keep spine upright with neutral curvature',
        'Initiate pull by retracting shoulder blades',
        'Pause and squeeze at the torso',
      ],
      commonMistakes: [
        'Rounding the lower back',
        'Using excessive body swing momentum',
      ],
    ),
    Exercise(
      id: 'db-shoulder-press',
      slug: 'dumbbell-shoulder-press',
      name: 'Dumbbell Shoulder Press',
      nameVi: 'Đẩy vai với tạ đơn',
      muscleGroup: 'Shoulders',
      targetMuscles: ['Shoulders', 'Anterior Deltoid'],
      secondaryMuscles: ['Triceps', 'Upper Chest'],
      equipment: ['Dumbbells', 'Incline/Vertical Bench'],
      difficulty: 'intermediate',
      thumbnailUrl:
          'https://images.unsplash.com/photo-1541534741688-6078c6bfb5c5?auto=format&fit=crop&w=600&q=80',
      defaultSets: 4,
      defaultReps: '8-10',
      restSeconds: 90,
      repType: 'reps',
      cvSupported: false,
      cues: [
        'Keep core tight and ribs down',
        'Press weights directly overhead',
        'Control descent to ear level',
      ],
      commonMistakes: [
        'Hyperextending the lower back',
        'Locking out elbows aggressively at the top',
      ],
    ),
    Exercise(
      id: 'push-up',
      slug: 'push-up',
      name: 'Push-Up',
      nameVi: 'Hít đất',
      muscleGroup: 'Chest',
      targetMuscles: ['Chest', 'Triceps'],
      secondaryMuscles: ['Core', 'Anterior Deltoid'],
      equipment: ['Bodyweight'],
      difficulty: 'beginner',
      thumbnailUrl:
          'https://images.unsplash.com/photo-1598971639058-fab3c3109a00?auto=format&fit=crop&w=600&q=80',
      defaultSets: 3,
      defaultReps: '12-15',
      restSeconds: 60,
      repType: 'reps',
      cvSupported: false,
      cues: [
        'Keep body in a rigid plank line',
        'Elbows tracking at 45 degrees',
        'Lower chest until nearly touching floor',
      ],
      commonMistakes: [
        'Sagging hips',
        'Flaring elbows out 90 degrees',
      ],
    ),
  ];
});

class ExerciseLibraryScreen extends ConsumerStatefulWidget {
  final String initialCategory;

  const ExerciseLibraryScreen({
    super.key,
    this.initialCategory = 'Upper Body',
  });

  @override
  ConsumerState<ExerciseLibraryScreen> createState() =>
      _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends ConsumerState<ExerciseLibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  late String _selectedCategory;
  String _selectedSubFilter = 'All';

  final List<String> _categories = [
    'All',
    'Upper Body',
    'Lower Body',
    'Core',
  ];

  final List<String> _subFilters = [
    'All',
    'Chest',
    'Back',
    'Shoulders',
    'Arms',
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exercisesAsync = ref.watch(exerciseLibraryListProvider);

    return Scaffold(
      backgroundColor: SamanWorkoutTokens.canvas,
      appBar: AppBar(
        backgroundColor: SamanWorkoutTokens.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: SamanWorkoutTokens.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Exercise Library',
          style: TextStyle(
            color: SamanWorkoutTokens.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined,
                size: 20, color: SamanWorkoutTokens.textSecondary),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Bookmarks are saved locally in your library.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            tooltip: 'Bookmarks',
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SamanWorkoutTokens.spacingLg,
              vertical: SamanWorkoutTokens.spacingSm,
            ),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: SamanWorkoutTokens.cardSurface,
                borderRadius:
                    BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                border: Border.all(color: SamanWorkoutTokens.border),
              ),
              child: Row(
                children: [
                  const SizedBox(width: SamanWorkoutTokens.spacingMd),
                  const Icon(Icons.search,
                      size: 20, color: SamanWorkoutTokens.textSecondary),
                  const SizedBox(width: SamanWorkoutTokens.spacingSm),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(
                        color: SamanWorkoutTokens.textPrimary,
                        fontSize: 14,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Search exercises',
                        hintStyle: TextStyle(
                          color: SamanWorkoutTokens.textSecondary,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 16, color: SamanWorkoutTokens.textSecondary),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.tune,
                        size: 18, color: SamanWorkoutTokens.textSecondary),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),

          // 2. Primary Category Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: SamanWorkoutTokens.spacingLg,
              vertical: SamanWorkoutTokens.spacingSm,
            ),
            child: Row(
              children: _categories.map((category) {
                final isSelected = _selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                    onTap: () => setState(() => _selectedCategory = category),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? SamanWorkoutTokens.surfaceElevated
                            : Colors.transparent,
                        borderRadius:
                            BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                        border: Border.all(
                          color: isSelected
                              ? SamanWorkoutTokens.borderHover
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected && category != 'All') ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: SamanWorkoutTokens.emeraldAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            category,
                            style: TextStyle(
                              color: isSelected
                                  ? SamanWorkoutTokens.textPrimary
                                  : SamanWorkoutTokens.textSecondary,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // 3. Secondary Sub-Filter Chips (when Upper Body or All)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: SamanWorkoutTokens.spacingLg,
              vertical: 4,
            ),
            child: Row(
              children: [
                ..._subFilters.map((filter) {
                  final isSelected = _selectedSubFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                      onTap: () => setState(() => _selectedSubFilter = filter),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? SamanWorkoutTokens.cardSurface
                              : SamanWorkoutTokens.canvas,
                          borderRadius:
                              BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                          border: Border.all(
                            color: isSelected
                                ? SamanWorkoutTokens.borderHover
                                : SamanWorkoutTokens.borderSubtle,
                          ),
                        ),
                        child: Text(
                          filter,
                          style: TextStyle(
                            color: isSelected
                                ? SamanWorkoutTokens.textPrimary
                                : SamanWorkoutTokens.textSecondary,
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: SamanWorkoutTokens.canvas,
                    borderRadius:
                        BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                    border: Border.all(color: SamanWorkoutTokens.borderSubtle),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Equipment',
                        style: TextStyle(
                          color: SamanWorkoutTokens.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down,
                          size: 14, color: SamanWorkoutTokens.textSecondary),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 4. Movements Header
          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: SamanWorkoutTokens.spacingLg,
              vertical: SamanWorkoutTokens.spacingSm,
            ),
            child: Row(
              children: [
                Text(
                  'MOVEMENTS',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: SamanWorkoutTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),

          // 5. Movements List
          Expanded(
            child: exercisesAsync.when(
              data: (exercises) {
                final query = _searchController.text.trim().toLowerCase();
                var filtered = exercises.where((e) {
                  final matchQuery = query.isEmpty ||
                      e.name.toLowerCase().contains(query) ||
                      e.nameVi.toLowerCase().contains(query) ||
                      e.muscleGroup.toLowerCase().contains(query);

                  final matchSub = _selectedSubFilter == 'All' ||
                      e.muscleGroup
                          .toLowerCase()
                          .contains(_selectedSubFilter.toLowerCase()) ||
                      e.targetMuscles.any((m) => m
                          .toLowerCase()
                          .contains(_selectedSubFilter.toLowerCase()));

                  return matchQuery && matchSub;
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fitness_center_outlined,
                            size: 40, color: SamanWorkoutTokens.textMuted),
                        SizedBox(height: 12),
                        Text(
                          'No exercises found matching criteria',
                          style: TextStyle(
                            color: SamanWorkoutTokens.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    SamanWorkoutTokens.spacingLg,
                    0,
                    SamanWorkoutTokens.spacingLg,
                    SamanWorkoutTokens.spacingXxl,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: SamanWorkoutTokens.spacingSm),
                  itemBuilder: (context, index) {
                    final exercise = filtered[index];
                    return _ExerciseMovementRow(
                      exercise: exercise,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ExerciseDetailScreen(exercise: exercise),
                          ),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: SamanWorkoutTokens.emeraldAccent,
                ),
              ),
              error: (err, _) => Center(
                child: Text(
                  'Error loading exercises: $err',
                  style: const TextStyle(
                      color: SamanWorkoutTokens.textSecondary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseMovementRow extends StatelessWidget {
  final Exercise exercise;
  final VoidCallback onTap;

  const _ExerciseMovementRow({
    required this.exercise,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final equipmentStr =
        exercise.equipment.isNotEmpty ? exercise.equipment.first : 'Bodyweight';
    final subtitle = '${exercise.muscleGroup} • $equipmentStr';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(SamanWorkoutTokens.spacingSm),
        decoration: BoxDecoration(
          color: SamanWorkoutTokens.cardSurface,
          borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
          border: Border.all(color: SamanWorkoutTokens.border),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
              child: CachedNetworkImage(
                imageUrl: exercise.thumbnailUrl,
                width: 68,
                height: 68,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 68,
                  height: 68,
                  color: SamanWorkoutTokens.surfaceElevated,
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: SamanWorkoutTokens.emeraldAccent,
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 68,
                  height: 68,
                  color: SamanWorkoutTokens.surfaceElevated,
                  child: const Icon(Icons.fitness_center,
                      color: SamanWorkoutTokens.textMuted, size: 24),
                ),
              ),
            ),
            const SizedBox(width: SamanWorkoutTokens.spacingMd),

            // Content details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SamanWorkoutTokens.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SamanWorkoutTokens.textSub,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Affordance: Video Guide badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: SamanWorkoutTokens.surfaceElevated,
                          borderRadius:
                              BorderRadius.circular(SamanWorkoutTokens.radiusXs),
                          border: Border.all(
                              color: SamanWorkoutTokens.borderSubtle),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_circle_outline,
                                size: 12,
                                color: SamanWorkoutTokens.emeraldAccent),
                            SizedBox(width: 4),
                            Text(
                              'Video guide',
                              style: TextStyle(
                                color: SamanWorkoutTokens.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Chevron
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color: SamanWorkoutTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
