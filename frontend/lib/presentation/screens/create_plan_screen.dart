import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/create_plan_providers.dart';
import '../providers/create_plan_state.dart';
import '../providers/exercise_providers.dart';
import '../tokens/saman_workout_tokens.dart';
import '../widgets/exercise_card.dart';
import '../../data/models/workout_plan.dart';
import '../../data/models/exercise.dart';
import 'exercise_library_screen.dart';

class CreatePlanScreen extends ConsumerStatefulWidget {
  final WorkoutPlan? planToEdit;

  const CreatePlanScreen({super.key, this.planToEdit});

  @override
  ConsumerState<CreatePlanScreen> createState() => _CreatePlanScreenState();
}

class _CreatePlanScreenState extends ConsumerState<CreatePlanScreen> {
  late TextEditingController _nameController;
  bool _hasChanges = false;
  bool _isLoading = false;
  bool _isSavingLocally = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.planToEdit?.name ?? '',
    );

    if (widget.planToEdit != null) {
      _loadExercisesFromPlan();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(createPlanNotifierProvider.notifier).clear();
        ref.read(createPlanNotifierProvider.notifier).setName('');
      });
    }

    _nameController.addListener(_onNameChanged);
  }

  Future<void> _loadExercisesFromPlan() async {
    setState(() => _isLoading = true);
    final repo = ref.read(exerciseRepositoryProvider);
    try {
      final exercises = await Future.wait(
        widget.planToEdit!.exerciseIds.map((id) => repo.getExerciseById(id)),
      );
      if (!mounted) return;
      ref.read(createPlanNotifierProvider.notifier).clear();
      ref
          .read(createPlanNotifierProvider.notifier)
          .setName(widget.planToEdit!.name);
      for (var ex in exercises) {
        ref.read(createPlanNotifierProvider.notifier).addExercise(ex);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load plan: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onNameChanged() {
    final currentNotifierName = ref.read(createPlanNotifierProvider).name;
    if (_nameController.text != currentNotifierName) {
      ref
          .read(createPlanNotifierProvider.notifier)
          .setName(_nameController.text);
    }
    final initialName = widget.planToEdit?.name ?? '';
    final changed = _nameController.text != initialName;
    if (changed != _hasChanges) {
      setState(() => _hasChanges = changed);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<bool> _showDiscardDialog(BuildContext context) async {
    final t = SamanWorkoutTokens.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
          side: BorderSide(color: t.border),
        ),
        title: Text(
          'Discard changes?',
          style: TextStyle(
            fontFamily: 'Space Grotesk',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        content: Text(
          'You have unsaved changes. Are you sure you want to exit?',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: t.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Keep editing',
              style: TextStyle(
                fontFamily: 'Inter',
                color: t.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Discard',
              style: TextStyle(
                fontFamily: 'Inter',
                color: t.isDark ? Colors.redAccent : t.crimsonAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return confirm ?? false;
  }

  Future<void> _handleClose(
    BuildContext context,
    CreatePlanState state,
    CreatePlanNotifier notifier,
  ) async {
    if (_hasChanges || state.exercises.isNotEmpty) {
      final shouldPop = await _showDiscardDialog(context);
      if (shouldPop && context.mounted) {
        notifier.clear();
        Navigator.of(context).pop();
      }
    } else {
      notifier.clear();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = SamanWorkoutTokens.of(context);
    final state = ref.watch(createPlanNotifierProvider);
    final notifier = ref.read(createPlanNotifierProvider.notifier);

    return PopScope(
      canPop: !_hasChanges && state.exercises.isEmpty,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _showDiscardDialog(context);
        if (shouldPop && context.mounted) {
          notifier.clear();
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: t.canvas,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Top Navigation Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 22,
                              color: t.textSecondary,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            onPressed: () =>
                                _handleClose(context, state, notifier),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              widget.planToEdit != null
                                  ? 'Edit plan'
                                  : 'Create plan',
                              style: TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: t.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: t.surfaceElevated.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(
                          SamanWorkoutTokens.radiusPill,
                        ),
                        border: Border.all(
                          color: t.border.withOpacity(0.4),
                        ),
                      ),
                      child: Text(
                        'Demo mode',
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 11,
                          color: t.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Main Scrollable Form Area
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: t.textPrimary,
                          strokeWidth: 2.5,
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Panoramic Gym Introduction Card
                            Container(
                              width: double.infinity,
                              height: 112,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  SamanWorkoutTokens.radiusLg,
                                ),
                                border: Border.all(
                                  color: t.border.withOpacity(0.5),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Image.asset(
                                      'assets/images/create_plan_hero.jpg',
                                      fit: BoxFit.cover,
                                      alignment: Alignment.center,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: t.cardSurface,
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          stops: const [0.0, 0.6, 1.0],
                                          colors: [
                                            const Color(0xFF0C0D0E)
                                                .withOpacity(0.9),
                                            Colors.transparent,
                                            Colors.black.withOpacity(0.3),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: ColoredBox(
                                      color: Colors.black.withOpacity(0.15),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Plan Name Section
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 8),
                              child: Text(
                                'PLAN NAME',
                                style: TextStyle(
                                  fontFamily: 'JetBrains Mono',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                  color: t.textSecondary,
                                ),
                              ),
                            ),
                            TextField(
                              controller: _nameController,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                color: t.textPrimary,
                              ),
                              cursorColor: t.emeraldAccent,
                              decoration: InputDecoration(
                                hintText: 'e.g. Upper Body Strength',
                                hintStyle: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  color: t.textSecondary,
                                ),
                                filled: true,
                                fillColor: t.cardSurface,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    SamanWorkoutTokens.radiusMd,
                                  ),
                                  borderSide: BorderSide(
                                    color: t.border,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    SamanWorkoutTokens.radiusMd,
                                  ),
                                  borderSide: BorderSide(
                                    color: t.emeraldAccent.withOpacity(0.6),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Exercises Header Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Text(
                                        'Exercises',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: t.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: t.surfaceElevated,
                                          borderRadius: BorderRadius.circular(
                                            SamanWorkoutTokens.radiusXs,
                                          ),
                                        ),
                                        child: Text(
                                          '${state.exercises.length}',
                                          style: TextStyle(
                                            fontFamily: 'JetBrains Mono',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: t.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _navigateToLibrary(context),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    '+ Add',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: t.emeraldAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Empty Card or Populated Exercises List
                            state.exercises.isEmpty
                                ? _buildEmptyExercisesCard(context, t)
                                : _buildPopulatedExercisesList(
                                    state.exercises,
                                    notifier,
                                    t,
                                  ),
                          ],
                        ),
                      ),
              ),

              // Sticky Bottom Save Plan CTA
              _buildStickyBottom(context, state, notifier, t),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyExercisesCard(
      BuildContext context, SamanWorkoutPalette t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusXl),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: t.surfaceElevated,
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.fitness_center_rounded,
              size: 24,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Add your first exercise',
            style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: t.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Choose exercises from your library.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: t.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: () => _navigateToLibrary(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.surfaceElevated,
                foregroundColor: t.textPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    SamanWorkoutTokens.radiusMd,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: t.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Browse library',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: t.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const Positioned.fill(
                    child: Center(
                      child: Text(
                        'Mở Library',
                        style: TextStyle(
                          color: Colors.transparent,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopulatedExercisesList(
    List<Exercise> exercises,
    CreatePlanNotifier notifier,
    SamanWorkoutPalette t,
  ) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: exercises.length,
      onReorder: (oldIndex, newIndex) =>
          notifier.reorderExercises(oldIndex, newIndex),
      itemBuilder: (context, index) {
        final exercise = exercises[index];
        return Container(
          key: ValueKey(exercise.id),
          margin: const EdgeInsets.only(bottom: 8),
          child: ExerciseCard(
            exercise: exercise,
            onTap: () {},
            trailing: IconButton(
              icon: Icon(
                Icons.delete_outline_rounded,
                color: t.isDark ? Colors.redAccent : t.crimsonAccent,
                size: 20,
              ),
              onPressed: () => notifier.removeExercise(exercise.id),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStickyBottom(
    BuildContext context,
    CreatePlanState state,
    CreatePlanNotifier notifier,
    SamanWorkoutPalette t,
  ) {
    final isValid =
        state.exercises.isNotEmpty && _nameController.text.trim().isNotEmpty;
    final canSave = isValid && !state.isSaving && !_isSavingLocally;
    final disabledBg = t.isDark ? const Color(0xFF1F2126) : t.surfaceElevated;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: const [0.0, 0.7, 1.0],
          colors: [
            t.canvas,
            t.canvas.withOpacity(0.95),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                state.error!,
                style: TextStyle(
                    color: t.isDark ? Colors.redAccent : t.crimsonAccent,
                    fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: canSave
                  ? () async {
                      if (_isSavingLocally || state.isSaving) return;
                      setState(() => _isSavingLocally = true);
                      final navigator = Navigator.of(context);
                      final saved = await notifier.savePlan(
                        planId: widget.planToEdit?.id,
                      );
                      if (!mounted) return;
                      setState(() => _isSavingLocally = false);
                      if (!saved) return;
                      notifier.clear();
                      navigator.pop();
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isValid ? t.buttonPrimary : disabledBg,
                disabledBackgroundColor: disabledBg,
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    SamanWorkoutTokens.radiusLg,
                  ),
                ),
                padding: EdgeInsets.zero,
              ),
              child: state.isSaving || _isSavingLocally
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.buttonPrimaryText,
                      ),
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          'Save plan',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isValid
                                ? t.buttonPrimaryText
                                : t.textSecondary,
                          ),
                        ),
                        const Positioned.fill(
                          child: Center(
                            child: Text(
                              'Lưu Plan',
                              style: TextStyle(
                                color: Colors.transparent,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToLibrary(BuildContext context) async {
    final exercise = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(
        builder: (_) => const ExerciseLibraryScreen(
          initialCategory: 'All',
          selectExercise: true,
        ),
      ),
    );
    if (!mounted || exercise == null) return;
    ref.read(createPlanNotifierProvider.notifier).addExercise(exercise);
    setState(() => _hasChanges = true);
  }
}
