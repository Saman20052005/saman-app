import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/exercise_providers.dart';
import '../providers/my_plans_providers.dart';
import '../../data/models/workout_plan.dart';
import '../../core/constants/app_dimens.dart';
import 'active_workout_screen.dart';
import 'create_plan_screen.dart';

class MyPlansScreen extends ConsumerWidget {
  const MyPlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(myPlansNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Plans',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: plansAsync.when(
        data: (plans) => plans.isEmpty
            ? _buildEmptyState(context, ref)
            : ListView.builder(
                padding: const EdgeInsets.all(AppDimens.paddingL),
                itemCount: plans.length,
                itemBuilder: (context, index) {
                  final plan = plans[index];
                  return _PlanCard(
                    plan: plan,
                    onStart: () => _startPlan(context, ref, plan),
                    onEdit: () => _editPlan(context, ref, plan),
                    onDelete: () => _showDeleteDialog(context, ref, plan.id),
                    ref: ref,
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Không tải được danh sách plan'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    ref.read(myPlansNotifierProvider.notifier).refresh(),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createNewPlan(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Tạo Plan mới'),
      ),
    );
  }

  Future<void> _startPlan(
      BuildContext context, WidgetRef ref, WorkoutPlan plan) async {
    final repo = ref.read(exerciseRepositoryProvider);
    try {
      // Lấy danh sách exercises từ plan
      final exercises = await Future.wait(
        plan.exerciseIds.map((id) => repo.getExerciseById(id)),
      );
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ActiveWorkoutScreen.fromExercises(exercises: exercises),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải bài tập: $e')),
        );
      }
    }
  }

  void _editPlan(BuildContext context, WidgetRef ref, WorkoutPlan plan) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePlanScreen(planToEdit: plan),
      ),
    ).then((_) {
      // Khi quay lại, refresh danh sách
      if (context.mounted) {
        ref.read(myPlansNotifierProvider.notifier).refresh();
      }
    });
  }

  void _createNewPlan(BuildContext context, WidgetRef ref) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CreatePlanScreen(),
      ),
    ).then((_) {
      if (context.mounted) {
        ref.read(myPlansNotifierProvider.notifier).refresh();
      }
    });
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, String planId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa Plan?'),
        content: const Text('Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(myPlansNotifierProvider.notifier).deletePlan(planId);
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.playlist_add, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('Chưa có Plan nào',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Tạo plan đầu tiên để bắt đầu',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _createNewPlan(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Tạo Plan ngay'),
          ),
        ],
      ),
    );
  }
}

// Widget riêng cho card plan
class _PlanCard extends StatelessWidget {
  final WorkoutPlan plan;
  final VoidCallback onStart;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final WidgetRef ref;

  const _PlanCard({
    required this.plan,
    required this.onStart,
    required this.onEdit,
    required this.onDelete,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      plan.name,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${plan.totalExercises} bài tập'),
              if (plan.lastUsedAt != null)
                Text(
                  'Lần cuối: ${_formatDate(plan.lastUsedAt!)}',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: onStart,
                  child: const Text('Bắt đầu'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
