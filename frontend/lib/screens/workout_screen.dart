import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/workout/domain/entities/workout_plan.dart';
import '../features/workout/presentation/controllers/workout_controller.dart';
import '../features/workout/data/repositories/workout_repository_impl.dart';

import 'active_workout_screen.dart';
import 'create_plan_screen.dart';

class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({super.key});

  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen> {
  final Color _bgCol = const Color(0xFFF4F6F8);
  final Color _darkCol = const Color(0xFF121212);
  final Color _accentCol = const Color(0xFF00E676);

  int _selectedCategoryIndex = 0;
  final List<String> _categories = [
    'All',
    'Chest',
    'Back',
    'Legs',
    'Shoulder',
    'Arms',
    'Abs',
    'Cardio'
  ];

  @override
  Widget build(BuildContext context) {
    // Lắng nghe dữ liệu từ Controller (Clean Architecture)
    final plansState = ref.watch(workoutControllerProvider);
    final streakFuture = ref.watch(weeklyStreakProvider);

    return Scaffold(
      backgroundColor: _bgCol,
      body: RefreshIndicator(
        // Kéo xuống để refresh data
        onRefresh: () => ref.refresh(workoutControllerProvider.future),
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Streak Section (Xử lý AsyncValue)
                    streakFuture.when(
                      data: (streak) => _buildStreakSection(streak),
                      error: (_, __) =>
                          _buildStreakSection(List.filled(7, false)),
                      loading: () => const SizedBox(
                          height: 140,
                          child: Center(child: CircularProgressIndicator())),
                    ),
                    const SizedBox(height: 25),

                    _buildCategorySelector(),
                    const SizedBox(height: 25),

                    // Workout List (Xử lý AsyncValue)
                    plansState.when(
                      data: (plans) {
                        if (plans.isEmpty) return _buildEmptyState();
                        return _buildWorkoutList(plans);
                      },
                      error: (err, _) => _buildErrorState(err.toString()),
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: 50),
                          child: CircularProgressIndicator(
                              color: Color(0xFF121212)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToCreatePlan,
        backgroundColor: _darkCol,
        foregroundColor: _accentCol,
        elevation: 10,
        icon: const Icon(Icons.add_rounded),
        label: const Text("NEW PLAN",
            style: TextStyle(fontWeight: FontWeight.bold)),
      ).animate().scale(delay: 500.ms),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      backgroundColor: _bgCol,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: Text(
          'Workout Plans',
          style: TextStyle(
              color: _darkCol, fontWeight: FontWeight.w900, fontSize: 24),
        ),
      ),
    );
  }

  Widget _buildStreakSection(List<bool> weeklyProgress) {
    // 1. Xác định ngày hôm nay (0: Mon, ... 6: Sun)
    final int todayIndex = DateTime.now().weekday - 1;
    final List<String> dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    // Tính tổng số ngày đã tập trong tuần
    final int completedDays = weeklyProgress.where((e) => e).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        // Gradient nền đen sang xám đậm (Modern Look)
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C3E50), Color(0xFF000000)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFF00E676).withOpacity(0.15), // Glow nhẹ màu xanh
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Title + Progress Counter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "WEEKLY GOAL",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$completedDays/7 Days Active",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              // Icon lửa trang trí
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_fire_department_rounded,
                    color: Color(0xFF00E676), size: 24),
              )
            ],
          ),

          const SizedBox(height: 24),

          // 7 Days Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              final isCompleted =
                  index < weeklyProgress.length ? weeklyProgress[index] : false;
              final isToday = index == todayIndex;

              return Column(
                children: [
                  // Circle Indicator
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Màu nền: Xanh nếu xong, Xám nhạt nếu chưa
                      color: isCompleted
                          ? const Color(0xFF00E676)
                          : (isToday
                              ? Colors.white.withOpacity(0.1)
                              : Colors.transparent),
                      // Viền:
                      // - Nếu hôm nay mà chưa xong: Viền trắng đậm
                      // - Nếu ngày thường chưa xong: Viền xám mờ
                      // - Nếu đã xong: Không viền
                      border: isCompleted
                          ? null
                          : Border.all(
                              color: isToday ? Colors.white : Colors.white24,
                              width: isToday ? 2 : 1,
                            ),
                      boxShadow: isCompleted
                          ? [
                              BoxShadow(
                                  color:
                                      const Color(0xFF00E676).withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2))
                            ]
                          : null,
                    ),
                    child: Center(
                      child: isCompleted
                          ? const Icon(Icons.check_rounded,
                              color: Colors.black, size: 22) // Dấu tích đậm
                          : (isToday
                              ? const Text("Today",
                                  style: TextStyle(
                                      fontSize: 8,
                                      color: Colors.white,
                                      fontWeight: FontWeight
                                          .bold)) // Chữ nhỏ thay dấu tích
                              : null),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Weekday Label (M, T, W...)
                  Text(
                    dayLabels[index],
                    style: TextStyle(
                      color: isToday
                          ? const Color(0xFF00E676)
                          : Colors.white54, // Highlight chữ hôm nay màu xanh
                      fontWeight: isToday ? FontWeight.w900 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 600.ms)
        .slideY(begin: 0.2, curve: Curves.easeOutBack);
  }

  Widget _buildCategorySelector() {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (ctx, i) {
          final isSel = i == _selectedCategoryIndex;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategoryIndex = i),
            child: AnimatedContainer(
              duration: 200.ms,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSel ? _darkCol : Colors.white,
                borderRadius: BorderRadius.circular(30),
                border:
                    Border.all(color: isSel ? _darkCol : Colors.grey.shade300),
                boxShadow: isSel
                    ? [
                        BoxShadow(
                            color: _darkCol.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4))
                      ]
                    : null,
              ),
              child: Text(_categories[i],
                  style: TextStyle(
                      color: isSel ? Colors.white : _darkCol,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(Icons.fitness_center_outlined,
              size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text("No workout plans found.",
              style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("Create your first plan to get started!",
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _navigateToCreatePlan(),
            icon: const Icon(Icons.add),
            label: const Text("CREATE PLAN"),
            style: ElevatedButton.styleFrom(
                backgroundColor: _darkCol, foregroundColor: _accentCol),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.red.shade100),
        ),
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text("Something went wrong",
                style: TextStyle(
                    color: Colors.red.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () =>
                  ref.read(workoutControllerProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("TRY AGAIN"),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade400,
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToCreatePlan() async {
    final res = await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const CreatePlanScreen()));
    if (res == true) {
      ref.read(workoutControllerProvider.notifier).refresh();
    }
  }

  Widget _buildWorkoutList(List<WorkoutPlan> plans) {
    final filtered = _selectedCategoryIndex == 0
        ? plans
        : plans
            .where((p) => p.category == _categories[_selectedCategoryIndex])
            .toList();

    return Column(children: filtered.map((p) => _buildCard(p)).toList());
  }

  Widget _buildCard(WorkoutPlan item) {
    final String heroTag =
        "hero_${item.id ?? DateTime.now().toIso8601String()}";
    final String imageUrl = item.imageUrl ??
        'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?q=80&w=1000';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 5))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            // Chuyển sang ActiveWorkoutScreen với dữ liệu Entity
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ActiveWorkoutScreen(
                        workoutPlan: item, heroTag: heroTag)));
            // Refresh streak sau khi tập xong
            ref.invalidate(weeklyStreakProvider);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Section
              Hero(
                tag: heroTag,
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  child: Stack(
                    children: [
                      Image.network(
                        imageUrl,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(height: 160, color: Colors.grey.shade900),
                      ),
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                Colors.black.withOpacity(0.6),
                                Colors.transparent
                              ])),
                        ),
                      ),
                      Positioned(
                        bottom: 12,
                        left: 16,
                        child: Text(item.title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5)),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              color: Colors.black54,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.timer,
                                      color: Colors.white, size: 14),
                                  const SizedBox(width: 4),
                                  Text("${item.duration} min",
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Content Section
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _buildTag(item.level, Colors.blue.shade500),
                    const SizedBox(width: 8),
                    _buildTag("${item.exercises.length} Exercises",
                        Colors.orange.shade500),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.redAccent, size: 20),
                      onPressed: () => _showDeleteDialog(item),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 16, color: Colors.grey.shade400)
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    ).animate().fadeIn().moveY(begin: 20);
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  void _showDeleteDialog(WorkoutPlan item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Plan"),
        content: Text("Are you sure you want to delete '${item.title}'?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(workoutRepositoryProvider)
                    .deleteWorkoutPlan(item.id!);
                ref.read(workoutControllerProvider.notifier).refresh();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Plan deleted")));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text("Error: $e"), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
