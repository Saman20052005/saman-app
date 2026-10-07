import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../data/models/exercise.dart';
import '../providers/exercise_providers.dart';
import '../tokens/saman_workout_tokens.dart';
import 'exercise_detail_screen.dart';
import '../../screens/main_screen.dart';
import '../../screens/home/widgets/saman_bottom_navigation_bar.dart';
import '../../providers/profile_provider.dart';

class ExerciseLibraryScreen extends ConsumerStatefulWidget {
  final String initialCategory;
  final ValueChanged<int>? onTabSelected;
  final bool selectExercise;

  const ExerciseLibraryScreen({
    super.key,
    this.initialCategory = 'Upper Body',
    this.onTabSelected,
    this.selectExercise = false,
  });

  @override
  ConsumerState<ExerciseLibraryScreen> createState() =>
      _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends ConsumerState<ExerciseLibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  late String _selectedCategory;
  String _selectedSubFilter = 'All';

  static const List<String> _categories = [
    'All',
    'Upper Body',
    'Lower Body',
    'Core',
  ];

  static const Map<String, List<String>> _categorySubFilters = {
    'All': ['All', 'Chest', 'Back', 'Shoulders', 'Arms'],
    'Upper Body': ['All', 'Chest', 'Back', 'Shoulders', 'Arms'],
    'Lower Body': ['All', 'Quads', 'Glutes', 'Hamstrings', 'Calves'],
    'Core': ['All', 'Abs', 'Obliques'],
  };

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    final validFilters =
        _categorySubFilters[_selectedCategory] ?? const ['All'];
    if (!validFilters.contains(_selectedSubFilter)) {
      _selectedSubFilter = 'All';
    }
  }

  @override
  void didUpdateWidget(ExerciseLibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCategory != widget.initialCategory) {
      _selectCategory(widget.initialCategory);
    }
  }

  void _selectCategory(String category) {
    setState(() {
      _selectedCategory = category;
      final validFilters =
          _categorySubFilters[category] ?? const ['All'];
      if (!validFilters.contains(_selectedSubFilter)) {
        _selectedSubFilter = 'All';
      }
    });
  }

  bool _isUpperBody(Exercise e) {
    final group = e.muscleGroup.toLowerCase();
    const upperGroups = {
      'chest',
      'back',
      'shoulders',
      'arms',
      'biceps',
      'triceps',
      'forearms',
      'traps',
      'lats',
      'upper body',
    };
    return upperGroups.contains(group) || group.contains('upper');
  }

  bool _isLowerBody(Exercise e) {
    final group = e.muscleGroup.toLowerCase();
    const lowerGroups = {
      'legs',
      'quads',
      'quadriceps',
      'hamstrings',
      'glutes',
      'calves',
      'lower body',
    };
    return lowerGroups.contains(group) ||
        group.contains('lower') ||
        group.contains('leg');
  }

  bool _isCore(Exercise e) {
    final group = e.muscleGroup.toLowerCase();
    const coreGroups = {'core', 'abs', 'abdominals', 'obliques'};
    return coreGroups.contains(group);
  }

  bool _matchesCategory(Exercise e, String category) {
    switch (category) {
      case 'All':
        return true;
      case 'Upper Body':
        return _isUpperBody(e);
      case 'Lower Body':
        return _isLowerBody(e);
      case 'Core':
        return _isCore(e);
      default:
        return e.muscleGroup.toLowerCase() == category.toLowerCase();
    }
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
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: SamanWorkoutTokens.spacingLg),
          child: Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: SamanWorkoutTokens.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: SamanWorkoutTokens.border),
                ),
                child: const Icon(
                  Icons.chevron_left,
                  size: 20,
                  color: SamanWorkoutTokens.textSecondary,
                ),
              ),
            ),
          ),
        ),
        title: const Text(
          'Exercise Library',
          style: TextStyle(
            color: SamanWorkoutTokens.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: SamanWorkoutTokens.spacingLg),
            child: Center(
              child: InkWell(
                key: const ValueKey('exercise_library_bookmark_button'),
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Bookmark feature is in development (no exercises are bookmarked yet).',
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: SamanWorkoutTokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: SamanWorkoutTokens.border),
                  ),
                  child: const Icon(
                    Icons.bookmarks_outlined,
                    size: 18,
                    color: SamanWorkoutTokens.textSecondary,
                  ),
                ),
              ),
            ),
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
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        inputDecorationTheme: const InputDecorationTheme(
                          filled: false,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        cursorColor: SamanWorkoutTokens.emeraldAccent,
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
                          filled: false,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
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
                    onTap: () => _selectCategory(category),
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
                ...(_categorySubFilters[_selectedCategory] ?? const ['All'])
                    .map((filter) {
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
                final filtered = exercises.where((e) {
                  final matchCat = _matchesCategory(e, _selectedCategory);
                  final matchSub = _selectedSubFilter == 'All' ||
                      e.muscleGroup
                          .toLowerCase()
                          .contains(_selectedSubFilter.toLowerCase()) ||
                      e.targetMuscles.any((m) => m
                          .toLowerCase()
                          .contains(_selectedSubFilter.toLowerCase()));
                  final matchQuery = query.isEmpty ||
                      e.name.toLowerCase().contains(query) ||
                      e.nameVi.toLowerCase().contains(query) ||
                      e.muscleGroup.toLowerCase().contains(query) ||
                      e.targetMuscles.any((m) => m
                          .toLowerCase()
                          .contains(query));

                  return matchCat && matchSub && matchQuery;
                }).toList();

                if (filtered.isEmpty) {
                  final String emptyTitle;
                  final String emptySubtitle;
                  if (query.isNotEmpty) {
                    emptyTitle = 'No exercises found';
                    emptySubtitle = 'No exercises matching "$query"';
                  } else if (_selectedCategory == 'Lower Body') {
                    emptyTitle = 'No lower body exercises yet';
                    emptySubtitle =
                        'Lower body exercise library is coming soon.';
                  } else if (_selectedCategory == 'Core') {
                    emptyTitle = 'No core exercises yet';
                    emptySubtitle = 'Core exercise library is coming soon.';
                  } else if (_selectedSubFilter != 'All') {
                    emptyTitle = 'No $_selectedSubFilter exercises';
                    emptySubtitle = 'No exercises found for this muscle group.';
                  } else {
                    emptyTitle = 'No exercises found';
                    emptySubtitle = 'No exercises found matching criteria';
                  }

                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: SamanWorkoutTokens.spacingXl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.fitness_center_outlined,
                              size: 40, color: SamanWorkoutTokens.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            emptyTitle,
                            style: const TextStyle(
                              color: SamanWorkoutTokens.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            emptySubtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: SamanWorkoutTokens.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  key: ValueKey('exercise_list_${_selectedCategory}_$_selectedSubFilter'),
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
                      key: ValueKey('exercise_row_${exercise.id}'),
                      exercise: exercise,
                      onTap: () {
                        if (widget.selectExercise) {
                          Navigator.of(context).pop(exercise);
                          return;
                        }
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
      bottomNavigationBar: SamanBottomNavigationBar(
        currentIndex: 1,
        onTap: (index) {
          widget.onTabSelected?.call(index);
          if (index == 1) {
            // Already in Workout, return to WorkoutHomeScreen
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          } else {
            if (index == 3) {
              try {
                final profileState = ref.read(profileProvider);
                if (!profileState.isProfileValid) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          "⚠️ Vui lòng cập nhật Hồ sơ sức khỏe để tính Calories!"),
                      backgroundColor: Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  ref.read(mainNavIndexProvider.notifier).state = 4;
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                  return;
                }
              } catch (_) {}
            }

            ref.read(mainNavIndexProvider.notifier).state = index;
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          }
        },
      ),
    );
  }
}

class _ExerciseMovementRow extends StatelessWidget {
  final Exercise exercise;
  final VoidCallback onTap;

  const _ExerciseMovementRow({
    super.key,
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
              child: exercise.thumbnailUrl.isNotEmpty
                  ? CachedNetworkImage(
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
                        child: const Icon(Icons.fitness_center_outlined,
                            color: SamanWorkoutTokens.textMuted, size: 24),
                      ),
                    )
                  : Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: SamanWorkoutTokens.surfaceElevated,
                        borderRadius:
                            BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                        border:
                            Border.all(color: SamanWorkoutTokens.borderSubtle),
                      ),
                      child: const Icon(
                        Icons.fitness_center_outlined,
                        color: SamanWorkoutTokens.textMuted,
                        size: 24,
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
