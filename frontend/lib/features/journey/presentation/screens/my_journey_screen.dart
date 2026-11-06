import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/routes.dart';
import '../../../../screens/food_log_screen.dart';
import '../../../../presentation/screens/workout_home_screen.dart';
import '../../domain/models/journey_models.dart';
import '../providers/journey_providers.dart';

class MyJourneyScreen extends ConsumerWidget {
  const MyJourneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journeyState = ref.watch(journeyControllerProvider);
    final walletState = ref.watch(walletControllerProvider);
    final journey = journeyState.journey;

    if (journeyState.isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0C0D0E),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF10B981)),
        ),
      );
    }

    if (journey == null || !journey.isActive) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C0D0E),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF94979E)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16171B),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF26282F)),
                        ),
                        child: const Icon(Icons.flag_outlined, size: 48, color: Color(0xFF94979E)),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Chưa có hành trình đang diễn ra',
                        style: TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF3F4F6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Hãy thiết lập một cam kết 7, 14, 21 hoặc 30 ngày để xây dựng thói quen và nhận điểm thưởng mỗi ngày.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF94979E), height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: 220,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            await Navigator.of(context).pushNamed(AppRoutes.createJourney);
                            ref.read(journeyControllerProvider.notifier).loadActiveJourney();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF9FAFB),
                            foregroundColor: const Color(0xFF0C0D0E),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text('Tạo hành trình ngay', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      );
    }

    final today = journey.todayRecord;
    final totalTasks = today?.tasks.length ?? 0;
    final completedTasks = today?.tasks.where((t) => t.isCompleted).length ?? 0;
    final currentDayIndex = today?.dayIndex ?? 1;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0D0E),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF10B981),
          backgroundColor: const Color(0xFF16171B),
          onRefresh: () async {
            await ref.read(journeyControllerProvider.notifier).loadActiveJourney();
            await ref.read(walletControllerProvider.notifier).loadWalletData();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. HEADER
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Color(0xFF94979E)),
                            onPressed: () {
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                              } else {
                                Navigator.of(context).pushReplacementNamed(AppRoutes.main);
                              }
                            },
                          ),
                          const SizedBox(width: 4),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hành trình của tôi',
                                  style: TextStyle(
                                    fontFamily: 'Space Grotesk',
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFF3F4F6),
                                    letterSpacing: -0.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Tiến độ cá nhân & kỷ luật mỗi ngày',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94979E),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.tune_rounded, color: Color(0xFF94979E)),
                      tooltip: 'Thiết lập hành trình',
                      onPressed: () async {
                        await Navigator.of(context).pushNamed(AppRoutes.createJourney);
                        ref.read(journeyControllerProvider.notifier).loadActiveJourney();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 2. HERO ACTIVE JOURNEY CARD
                _buildHeroCard(journey, currentDayIndex),
                const SizedBox(height: 20),

                // 3. TODAY'S TASKS & DAILY REWARD
                _buildTodaySection(context, ref, journey, today, completedTasks, totalTasks),
                const SizedBox(height: 20),

                // 4. JOURNEY CALENDAR (7-COLUMN GRID)
                _buildCalendarCard(journey),
                const SizedBox(height: 20),

                // 5. POINT WALLET ENTRY ROW
                _buildWalletEntryRow(context, ref, walletState),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(SamanJourney journey, int currentDayIndex) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hành trình ${journey.totalDays} ngày'.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF10B981),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Mỗi ngày một tốt hơn',
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF3F4F6),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      journey.focus.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94979E),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xB3212328),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF26282F), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      color: Color(0xFFFFB95F),
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${journey.currentStreak}',
                      style: const TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF3F4F6),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'chuỗi',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94979E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: journey.progress,
              minHeight: 8,
              backgroundColor: const Color(0xFF212328),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Đã hoàn thành ${journey.completedDaysCount} / ${journey.totalDays} ngày',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFF3F4F6),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Hôm nay · Ngày $currentDayIndex',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94979E),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodaySection(
    BuildContext context,
    WidgetRef ref,
    SamanJourney journey,
    JourneyDayRecord? today,
    int completedTasks,
    int totalTasks,
  ) {
    final tasks = today?.tasks ?? [];
    final journeyState = ref.watch(journeyControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Hôm nay',
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF3F4F6),
              ),
            ),
            Text(
              '$completedTasks / $totalTasks nhiệm vụ',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF94979E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Tasks Card (Clean divided rows, no manual checkboxes)
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF16171B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF26282F), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const Divider(color: Color(0xFF26282F), height: 1),
              itemBuilder: (context, index) {
                final task = tasks[index];
                return _buildTaskRow(context, ref, task);
              },
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Daily Reward Integration
        if (today != null) ...[
          if (!today.isCompleted) ...[
            // State A: Pending tasks
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.stars_rounded, color: Color(0xFF10B981), size: 16),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Hoàn thành các nhiệm vụ hôm nay để nhận 20 điểm.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF94979E)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '20 điểm',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFFB95F),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (today.isReadyToClaim) ...[
            // State B: Ready to claim
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: journeyState.isClaiming
                    ? null
                    : () async {
                        final ok = await ref
                            .read(journeyControllerProvider.notifier)
                            .claimDailyReward(date: today.date);
                        if (ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🎉 Bạn đã nhận thành công 20 điểm thưởng!'),
                              backgroundColor: Color(0xFF10B981),
                            ),
                          );
                        }
                      },
                icon: journeyState.isClaiming
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0C0D0E)),
                      )
                    : const Icon(Icons.stars_rounded, color: Color(0xFF0C0D0E), size: 18),
                label: const Text(
                  'Nhận 20 điểm',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0C0D0E),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF9FAFB),
                  foregroundColor: const Color(0xFF0C0D0E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ] else ...[
            // State C: Claimed
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF212328),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF26282F), width: 1),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Đã nhận 20 điểm hôm nay',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFF3F4F6),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildTaskRow(BuildContext context, WidgetRef ref, JourneyTask task) {
    if (task.isCompleted) {
      // Completed State (Read-only driven by real logging)
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0x2610B981),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0x4D10B981), width: 1),
                    ),
                    child: const Icon(Icons.check, color: Color(0xFF10B981), size: 18),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFF3F4F6),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          task.subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94979E),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Đã xong',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF10B981),
              ),
            ),
          ],
        ),
      );
    }

    // Pending State: Tappable row to launch appropriate action
    return InkWell(
      onTap: () async {
        if (task.type == JourneyTaskType.nutrition) {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FoodLogScreen()));
        } else if (task.type == JourneyTaskType.workout) {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WorkoutHomeScreen()));
        }
        ref.read(journeyControllerProvider.notifier).loadActiveJourney();
        ref.read(walletControllerProvider.notifier).loadWalletData();
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF212328),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF26282F), width: 1),
                    ),
                    child: Icon(
                      task.type == JourneyTaskType.nutrition
                          ? Icons.restaurant_rounded
                          : Icons.fitness_center_rounded,
                      color: const Color(0xFF94979E),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFF3F4F6),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          task.subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94979E),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              children: [
                Text(
                  task.type == JourneyTaskType.nutrition ? 'Ghi nhận' : 'Bắt đầu',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94979E),
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right, color: Color(0xFF94979E), size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarCard(SamanJourney journey) {
    final days = journey.days;
    final total = journey.totalDays;
    final todayStr = journey.todayRecord?.date;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Lịch hành trình',
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF3F4F6),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(total / 7).ceil()} tuần xây dựng thói quen',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94979E),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Tuần 1',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 7-Column Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: total,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 0.9,
            ),
            itemBuilder: (context, index) {
              final dayIndex = index + 1;
              final dayRec = index < days.length ? days[index] : null;
              final isToday = dayRec?.date == todayStr;
              final isDone = dayRec?.isCompleted ?? false;
              final isRest = dayRec?.isRestDay ?? false;
              final isPast = dayRec != null && todayStr != null && dayRec.date.compareTo(todayStr) < 0;
              final isMissed = isPast && !isDone && !isRest;

              return _buildDayCell(
                dayIndex: dayIndex,
                isToday: isToday,
                isDone: isDone,
                isRest: isRest,
                isMissed: isMissed,
              );
            },
          ),
          const SizedBox(height: 16),

          // Legend
          const Divider(color: Color(0xFF26282F), height: 1),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: Color(0xFF10B981)),
                  SizedBox(width: 4),
                  Text('Hoàn thành', style: TextStyle(fontSize: 11, color: Color(0xFF94979E))),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.radio_button_checked, size: 10, color: Color(0xFF10B981)),
                  SizedBox(width: 4),
                  Text('Hôm nay', style: TextStyle(fontSize: 11, color: Color(0xFF94979E))),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.spa_rounded, size: 12, color: Color(0xFF94979E)),
                  SizedBox(width: 4),
                  Text('Ngày nghỉ', style: TextStyle(fontSize: 11, color: Color(0xFF94979E))),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: Color(0xFF26282F)),
                  SizedBox(width: 4),
                  Text('Sắp tới', style: TextStyle(fontSize: 11, color: Color(0xFF94979E))),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell({
    required int dayIndex,
    required bool isToday,
    required bool isDone,
    required bool isRest,
    required bool isMissed,
  }) {
    if (isToday) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF212328),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF10B981), width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayIndex',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF3F4F6),
              ),
            ),
            const SizedBox(height: 2),
            const Icon(Icons.circle, size: 5, color: Color(0xFF10B981)),
          ],
        ),
      );
    }

    if (isDone) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0x2610B981),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x4D10B981), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayIndex',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF10B981),
              ),
            ),
            const SizedBox(height: 2),
            const Icon(Icons.check, size: 10, color: Color(0xFF10B981)),
          ],
        ),
      );
    }

    if (isRest) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0x1A212328),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF26282F), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayIndex',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94979E)),
            ),
            const SizedBox(height: 2),
            const Icon(Icons.spa_rounded, size: 10, color: Color(0xFF94979E)),
          ],
        ),
      );
    }

    if (isMissed) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF212328),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF26282F), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayIndex',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94979E)),
            ),
            const SizedBox(height: 2),
            Container(width: 8, height: 1.5, color: const Color(0xFF94979E)),
          ],
        ),
      );
    }

    // Upcoming
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x4D212328),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF26282F), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        '$dayIndex',
        style: const TextStyle(fontSize: 12, color: Color(0xFF94979E)),
      ),
    );
  }

  Widget _buildWalletEntryRow(BuildContext context, WidgetRef ref, WalletState walletState) {
    return InkWell(
      onTap: () async {
        await Navigator.of(context).pushNamed(AppRoutes.walletRewards);
        ref.read(walletControllerProvider.notifier).loadWalletData();
        ref.read(journeyControllerProvider.notifier).loadActiveJourney();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF16171B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF26282F), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF212328),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF26282F), width: 1),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Color(0xFF10B981),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Ví điểm & Lượt AI',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFF3F4F6),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '${walletState.balance} điểm · ${walletState.aiCredits} lượt AI',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF94979E),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: Color(0xFF94979E), size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
