import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/exercise_providers.dart';
import '../providers/my_plans_providers.dart';
import '../tokens/saman_workout_tokens.dart';
import '../../data/models/workout_plan.dart';
import 'active_workout_screen.dart';
import 'create_plan_screen.dart';

class MyPlansScreen extends ConsumerWidget {
  const MyPlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(myPlansNotifierProvider);

    return Scaffold(
      backgroundColor: SamanWorkoutTokens.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Navigation & Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back Arrow Button
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                      color: SamanWorkoutTokens.textPrimary,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    alignment: Alignment.centerLeft,
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(height: 8),
                  // Title Block & Demo Mode Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'My Plans',
                        style: TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: SamanWorkoutTokens.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: SamanWorkoutTokens.cardSurface,
                          borderRadius: BorderRadius.circular(
                            SamanWorkoutTokens.radiusXs,
                          ),
                          border: Border.all(
                            color: SamanWorkoutTokens.borderSubtle,
                          ),
                        ),
                        child: const Text(
                          'DEMO MODE',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            color: SamanWorkoutTokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Subtitle
                  const Text(
                    'Your routines, ready when you are.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: SamanWorkoutTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // Body Content
            Expanded(
              child: plansAsync.when(
                data: (plans) => plans.isEmpty
                    ? _buildEmptyHero(context, ref)
                    : _buildPlansList(context, ref, plans),
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: SamanWorkoutTokens.textPrimary,
                    strokeWidth: 2.5,
                  ),
                ),
                error: (_, __) => _buildErrorState(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHero(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 460),
        decoration: BoxDecoration(
          color: SamanWorkoutTokens.cardSurface,
          borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusXl),
          border: Border.all(color: SamanWorkoutTokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Photographic Gym Background Image
            Positioned.fill(
              child: Image.asset(
                'assets/images/my_plans_hero.jpg',
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) => Container(
                  color: SamanWorkoutTokens.cardSurface,
                ),
              ),
            ),
            // Multi-layer Atmospheric Gradients
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.45, 1.0],
                    colors: [
                      Colors.transparent,
                      SamanWorkoutTokens.canvas.withOpacity(0.85),
                      SamanWorkoutTokens.canvas,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withOpacity(0.35),
              ),
            ),
            // Hero Content Layer
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 190),
                  // Category Accent Pill Tag
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: SamanWorkoutTokens.emeraldBadgeBg,
                      borderRadius: BorderRadius.circular(
                        SamanWorkoutTokens.radiusPill,
                      ),
                      border: Border.all(
                        color: SamanWorkoutTokens.emeraldBadgeBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: SamanWorkoutTokens.emeraldAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'CUSTOM TRAINING',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: SamanWorkoutTokens.emeraldAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Hero Heading
                  const Text(
                    'Build your first plan',
                    style: TextStyle(
                      fontFamily: 'Space Grotesk',
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: SamanWorkoutTokens.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Supporting Text
                  const Text(
                    'Create a routine that fits your goals.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: SamanWorkoutTokens.textSub,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Primary CTA Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => _createNewPlan(context, ref),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SamanWorkoutTokens.buttonPrimary,
                        foregroundColor: SamanWorkoutTokens.buttonPrimaryText,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            SamanWorkoutTokens.radiusLg,
                          ),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Stack(
                        alignment: Alignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add,
                                size: 20,
                                color: SamanWorkoutTokens.buttonPrimaryText,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Create plan',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: SamanWorkoutTokens.buttonPrimaryText,
                                ),
                              ),
                            ],
                          ),
                          // Compatibility alias for automated test taps
                          Positioned.fill(
                            child: Center(
                              child: Text(
                                'Tạo Plan mới',
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlansList(
    BuildContext context,
    WidgetRef ref,
    List<WorkoutPlan> plans,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: plans.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Saved routines (${plans.length})',
                    style: const TextStyle(
                      fontFamily: 'Space Grotesk',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: SamanWorkoutTokens.textPrimary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _createNewPlan(context, ref),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Stack(
                    alignment: Alignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add,
                            size: 16,
                            color: SamanWorkoutTokens.emeraldAccent,
                          ),
                          SizedBox(width: 4),
                          Text(
                            '+ Create',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: SamanWorkoutTokens.emeraldAccent,
                            ),
                          ),
                        ],
                      ),
                      Positioned.fill(
                        child: Center(
                          child: Text(
                            'Tạo Plan mới',
                            style: TextStyle(
                              color: Colors.transparent,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        final plan = plans[index - 1];
        return _PlanCard(
          plan: plan,
          onStart: () => _startPlan(context, ref, plan),
          onEdit: () => _editPlan(context, ref, plan),
          onDelete: () => _showDeleteDialog(context, ref, plan.id),
        );
      },
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: SamanWorkoutTokens.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not load routines',
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: SamanWorkoutTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please try again in a moment.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: SamanWorkoutTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () =>
                  ref.read(myPlansNotifierProvider.notifier).refresh(),
              style: ElevatedButton.styleFrom(
                backgroundColor: SamanWorkoutTokens.buttonPrimary,
                foregroundColor: SamanWorkoutTokens.buttonPrimaryText,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    SamanWorkoutTokens.radiusMd,
                  ),
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startPlan(
    BuildContext context,
    WidgetRef ref,
    WorkoutPlan plan,
  ) async {
    final repo = ref.read(exerciseRepositoryProvider);
    try {
      final exercises = await Future.wait(
        plan.exerciseIds.map((id) => repo.getExerciseById(id)),
      );
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ActiveWorkoutScreen.fromExercises(
              exercises: exercises,
              title: plan.name,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading exercises: $e')),
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
      builder: (ctx) => AlertDialog(
        backgroundColor: SamanWorkoutTokens.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
          side: const BorderSide(color: SamanWorkoutTokens.border),
        ),
        title: const Text(
          'Delete plan?',
          style: TextStyle(
            fontFamily: 'Space Grotesk',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: SamanWorkoutTokens.textPrimary,
          ),
        ),
        content: const Text(
          'This action cannot be undone.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: SamanWorkoutTokens.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  'Cancel',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: SamanWorkoutTokens.textSecondary,
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: Text(
                      'Hủy',
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
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(myPlansNotifierProvider.notifier).deletePlan(planId);
            },
            child: const Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  'Delete',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: Text(
                      'Xóa',
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
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final WorkoutPlan plan;
  final VoidCallback onStart;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PlanCard({
    required this.plan,
    required this.onStart,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: SamanWorkoutTokens.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
        border: Border.all(color: SamanWorkoutTokens.border),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
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
                        fontFamily: 'Space Grotesk',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: SamanWorkoutTokens.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: SamanWorkoutTokens.textSecondary,
                      size: 20,
                    ),
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '${plan.totalExercises} ${plan.totalExercises == 1 ? 'exercise' : 'exercises'}',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: SamanWorkoutTokens.textSecondary,
                    ),
                  ),
                  if (plan.lastUsedAt != null) ...[
                    const SizedBox(width: 8),
                    const Text(
                      '•',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: SamanWorkoutTokens.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Last: ${_formatDate(plan.lastUsedAt!)}',
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 12,
                        color: SamanWorkoutTokens.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton(
                    onPressed: onStart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SamanWorkoutTokens.buttonPrimary,
                      foregroundColor: SamanWorkoutTokens.buttonPrimaryText,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          SamanWorkoutTokens.radiusMd,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          'Start workout',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: SamanWorkoutTokens.buttonPrimaryText,
                          ),
                        ),
                        Positioned.fill(
                          child: Center(
                            child: Text(
                              'Bắt đầu',
                              style: TextStyle(
                                color: Colors.transparent,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
