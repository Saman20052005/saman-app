import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/create_plan_providers.dart';
import '../providers/exercise_providers.dart';
import '../../core/constants/app_dimens.dart';
import '../../core/constants/app_strings.dart';
import '../widgets/exercise_card.dart';
import 'exercise_detail_screen.dart';
import 'active_workout_screen.dart';
import '../../data/models/workout_plan.dart';
import '../../data/models/exercise.dart';
import 'muscle_group_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.planToEdit?.name ?? 'Plan mới');
    if (widget.planToEdit != null) {
      // Load danh sách bài tập đã có trong plan
      _loadExercisesFromPlan();
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
      // Gán vào provider (create_plan_providers)
      ref
          .read(createPlanNotifierProvider.notifier)
          .setName(widget.planToEdit!.name);
      for (var ex in exercises) {
        ref.read(createPlanNotifierProvider.notifier).addExercise(ex);
      }
    } catch (e) {
      // Xử lý lỗi
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onNameChanged() {
    final currentName = ref.read(createPlanNotifierProvider).name;
    if (_nameController.text != currentName) {
      setState(() => _hasChanges = true);
    } else {
      setState(() => _hasChanges = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(createPlanNotifierProvider);
    final notifier = ref.read(createPlanNotifierProvider.notifier);

    return WillPopScope(
      onWillPop: () async {
        if (_hasChanges || state.exercises.isNotEmpty) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Thoát?'),
              content: const Text(
                  'Bạn có thay đổi chưa lưu. Bạn có chắc muốn thoát?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Ở lại'),
                ),
                TextButton(
                  onPressed: () {
                    notifier.clear();
                    Navigator.pop(context, true);
                  },
                  child: const Text('Thoát'),
                ),
              ],
            ),
          );
          return confirm ?? false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.planToEdit != null ? 'Chỉnh sửa Plan' : 'Tạo Plan mới',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _PlanNameField(
                    controller: _nameController,
                    onChanged: (name) {
                      notifier.setName(name);
                      setState(() => _hasChanges = true);
                    },
                  ),
                  const Divider(),
                  _ExercisesHeader(
                    count: state.exercises.length,
                    onAddPressed: () => _navigateToLibrary(context),
                  ),
                  Expanded(
                    child: state.exercises.isEmpty
                        ? _EmptyState(
                            onAddPressed: () => _navigateToLibrary(context))
                        : _ExercisesList(
                            exercises: state.exercises,
                            onReorder: (oldIndex, newIndex) =>
                                notifier.reorderExercises(oldIndex, newIndex),
                            onRemove: (id) => notifier.removeExercise(id),
                          ),
                  ),
                  _SaveButton(
                    isSaving: state.isSaving,
                    error: state.error,
                    hasExercises: state.exercises.isNotEmpty,
                    onPressed: () async {
                      // TODO: inject usecase
                      // await notifier.savePlan(saveWorkoutPlanUseCase);
                      // Tạm thời:
                      notifier.savePlan(null as dynamic);
                      if (state.error == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Đã lưu plan thành công!')),
                        );
                        // Chuyển sang ActiveWorkoutScreen
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ActiveWorkoutScreen.fromExercises(
                                exercises: state.exercises),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _navigateToLibrary(context),
          icon: const Icon(Icons.add),
          label: const Text('Thêm bài tập'),
        ),
      ),
    );
  }

  void _navigateToLibrary(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MuscleGroupScreen()),
    );
  }
}

// --- Widget con ---
class _PlanNameField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _PlanNameField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppDimens.paddingL),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: 'Tên Plan',
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusL)),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _ExercisesHeader extends StatelessWidget {
  final int count;
  final VoidCallback onAddPressed;

  const _ExercisesHeader({required this.count, required this.onAddPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.paddingL, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Bài tập trong Plan ($count)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          TextButton.icon(
            onPressed: onAddPressed,
            icon: const Icon(Icons.add),
            label: const Text('Thêm'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddPressed;

  const _EmptyState({required this.onAddPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.fitness_center, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Chưa có bài tập nào',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('Hãy thêm bài tập từ Library',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAddPressed,
            icon: const Icon(Icons.search),
            label: const Text('Mở Library'),
          ),
        ],
      ),
    );
  }
}

class _ExercisesList extends StatelessWidget {
  final List<Exercise> exercises;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(String id) onRemove;

  const _ExercisesList({
    required this.exercises,
    required this.onReorder,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(AppDimens.paddingL),
      itemCount: exercises.length,
      onReorder: onReorder,
      itemBuilder: (context, index) {
        final exercise = exercises[index];
        return ExerciseCard(
          key: ValueKey(exercise.id),
          exercise: exercise,
          onTap: () {}, // không cần mở detail
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => onRemove(exercise.id),
          ),
        );
      },
    );
  }
}

class _SaveButton extends StatelessWidget {
  final bool isSaving;
  final String? error;
  final bool hasExercises;
  final VoidCallback onPressed;

  const _SaveButton({
    required this.isSaving,
    required this.error,
    required this.hasExercises,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.paddingL),
        child: Column(
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: hasExercises && !isSaving ? onPressed : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimens.radiusL),
                  ),
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Lưu Plan',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
