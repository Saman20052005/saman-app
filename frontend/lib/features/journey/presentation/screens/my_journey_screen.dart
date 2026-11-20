import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/routes.dart';
import '../../../../screens/food_log_screen.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../../../presentation/screens/workout_home_screen.dart';
import '../../domain/models/journey_models.dart';
import '../providers/journey_providers.dart';
import '../../../../widgets/saman_feedback_snackbar.dart';

class MyJourneyScreen extends ConsumerWidget {
  const MyJourneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SamanHomeTokens.of(context);
    final scaffoldBg =
        tokens.isDark ? const Color(0xFF0C0D0E) : tokens.canvas;
    final cardBg =
        tokens.isDark ? const Color(0xFF16171B) : tokens.cardSurface;
    final borderColor =
        tokens.isDark ? const Color(0xFF26282F) : tokens.border;
    final textPrimary =
        tokens.isDark ? const Color(0xFFF3F4F6) : tokens.textPrimary;
    final textSecondary =
        tokens.isDark ? const Color(0xFF94979E) : tokens.textSecondary;
    final emerald =
        tokens.isDark ? const Color(0xFF10B981) : tokens.greenAccent;
    final ctaBg =
        tokens.isDark ? const Color(0xFFF9FAFB) : const Color(0xFF059669);
    final ctaFg =
        tokens.isDark ? const Color(0xFF0C0D0E) : Colors.white;

    final journeyState = ref.watch(journeyControllerProvider);
    final walletState = ref.watch(walletControllerProvider);
    final journey = journeyState.journey;

    if (journeyState.isLoading) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        body: Center(
          child: CircularProgressIndicator(color: emerald),
        ),
      );
    }

    if (journey == null || !journey.isActive) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: textSecondary),
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
                          color: cardBg,
                          shape: BoxShape.circle,
                          border: Border.all(color: borderColor),
                        ),
                        child: Icon(Icons.flag_outlined, size: 48, color: textSecondary),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Chưa có hành trình đang diễn ra',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Hãy thiết lập một cam kết 7, 14, 21 hoặc 30 ngày để xây dựng thói quen và nhận điểm thưởng mỗi ngày.',
                        style: TextStyle(fontSize: 13, color: textSecondary, height: 1.4),
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
                            backgroundColor: ctaBg,
                            foregroundColor: ctaFg,
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
      backgroundColor: scaffoldBg,
      body: SafeArea(
        child: RefreshIndicator(
          color: emerald,
          backgroundColor: cardBg,
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
                            icon: Icon(Icons.arrow_back, color: textSecondary),
                            onPressed: () {
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                              } else {
                                Navigator.of(context).pushReplacementNamed(AppRoutes.main);
                              }
                            },
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hành trình của tôi',
                                  style: TextStyle(
                                    fontFamily: 'Manrope',
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: textPrimary,
                                    letterSpacing: -0.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Tiến độ cá nhân & kỷ luật mỗi ngày',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: textSecondary,
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
                      icon: Icon(Icons.tune_rounded, color: textSecondary),
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
                _buildHeroCard(tokens, journey, currentDayIndex),
                const SizedBox(height: 20),

                // 3. TODAY'S TASKS & DAILY REWARD
                _buildTodaySection(context, ref, journey, today, completedTasks, totalTasks),
                const SizedBox(height: 20),

                // 4. JOURNEY CALENDAR (7-COLUMN GRID)
                _buildCalendarCard(tokens, journey),
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

  Widget _buildHeroCard(SamanHomePalette tokens, SamanJourney journey, int currentDayIndex) {
    final cardBg =
        tokens.isDark ? const Color(0xFF16171B) : tokens.cardSurface;
    final borderColor =
        tokens.isDark ? const Color(0xFF26282F) : tokens.border;
    final textPrimary =
        tokens.isDark ? const Color(0xFFF3F4F6) : tokens.textPrimary;
    final textSecondary =
        tokens.isDark ? const Color(0xFF94979E) : tokens.textSecondary;
    final emerald =
        tokens.isDark ? const Color(0xFF10B981) : tokens.greenAccent;
    final streakBg =
        tokens.isDark ? const Color(0xB3212328) : tokens.secondarySurface;
    final amber =
        tokens.isDark ? const Color(0xFFFFB95F) : tokens.carbsAmber;
    final trackBg =
        tokens.isDark ? const Color(0xFF212328) : tokens.progressTrack;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
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
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: emerald,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Mỗi ngày một tốt hơn',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      journey.focus.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: textSecondary,
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
                  color: streakBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      color: amber,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${journey.currentStreak}',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'chuỗi',
                      style: TextStyle(
                        fontSize: 11,
                        color: textSecondary,
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
              backgroundColor: trackBg,
              valueColor: AlwaysStoppedAnimation<Color>(emerald),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Đã hoàn thành ${journey.completedDaysCount} / ${journey.totalDays} ngày',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Hôm nay · Ngày $currentDayIndex',
                style: TextStyle(
                  fontSize: 12,
                  color: textSecondary,
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
    final tokens = SamanHomeTokens.of(context);
    final cardBg =
        tokens.isDark ? const Color(0xFF16171B) : tokens.cardSurface;
    final borderColor =
        tokens.isDark ? const Color(0xFF26282F) : tokens.border;
    final textPrimary =
        tokens.isDark ? const Color(0xFFF3F4F6) : tokens.textPrimary;
    final textSecondary =
        tokens.isDark ? const Color(0xFF94979E) : tokens.textSecondary;
    final emerald =
        tokens.isDark ? const Color(0xFF10B981) : tokens.greenAccent;
    final amber =
        tokens.isDark ? const Color(0xFFFFB95F) : tokens.carbsAmber;
    final claimedBg =
        tokens.isDark ? const Color(0xFF212328) : tokens.secondarySurface;
    final ctaBg =
        tokens.isDark ? const Color(0xFFF9FAFB) : const Color(0xFF059669);
    final ctaFg =
        tokens.isDark ? const Color(0xFF0C0D0E) : Colors.white;

    final tasks = today?.tasks ?? [];
    final journeyState = ref.watch(journeyControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Hôm nay',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            Text(
              '$completedTasks / $totalTasks nhiệm vụ',
              style: TextStyle(
                fontSize: 12,
                color: textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Tasks Card (Clean divided rows, no manual checkboxes)
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: tasks.length,
              separatorBuilder: (_, __) => Divider(color: borderColor, height: 1),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.stars_rounded, color: emerald, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Hoàn thành các nhiệm vụ hôm nay để nhận 20 điểm.',
                            style: TextStyle(fontSize: 12, color: textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '20 điểm',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: amber,
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
                          SamanFeedbackSnackBar.show(
                            context,
                            message: '🎉 Bạn đã nhận thành công 20 điểm thưởng!',
                            type: FeedbackType.success,
                          );
                        }
                      },
                icon: journeyState.isClaiming
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: ctaFg),
                      )
                    : Icon(Icons.stars_rounded, color: ctaFg, size: 18),
                label: Text(
                  'Nhận 20 điểm',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ctaFg,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ctaBg,
                  foregroundColor: ctaFg,
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
                color: claimedBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: emerald, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Đã nhận 20 điểm hôm nay',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: textPrimary,
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
    final tokens = SamanHomeTokens.of(context);
    final textPrimary =
        tokens.isDark ? const Color(0xFFF3F4F6) : tokens.textPrimary;
    final textSecondary =
        tokens.isDark ? const Color(0xFF94979E) : tokens.textSecondary;
    final emerald =
        tokens.isDark ? const Color(0xFF10B981) : tokens.greenAccent;
    final emeraldBg =
        tokens.isDark ? const Color(0x2610B981) : tokens.greenBadgeBg;
    final emeraldBorder =
        tokens.isDark ? const Color(0x4D10B981) : tokens.greenBadgeBorder;
    final pendingCircleBg =
        tokens.isDark ? const Color(0xFF212328) : tokens.secondarySurface;
    final borderColor =
        tokens.isDark ? const Color(0xFF26282F) : tokens.border;

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
                      color: emeraldBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: emeraldBorder, width: 1),
                    ),
                    child: Icon(Icons.check, color: emerald, size: 18),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          task.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: textSecondary,
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
            Text(
              'Đã xong',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: emerald,
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
                      color: pendingCircleBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: borderColor, width: 1),
                    ),
                    child: Icon(
                      task.type == JourneyTaskType.nutrition
                          ? Icons.restaurant_rounded
                          : Icons.fitness_center_rounded,
                      color: textSecondary,
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
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          task.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: textSecondary,
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
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right, color: textSecondary, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarCard(SamanHomePalette tokens, SamanJourney journey) {
    final days = journey.days;
    final total = journey.totalDays;
    final todayStr = journey.todayRecord?.date;
    final cardBg =
        tokens.isDark ? const Color(0xFF16171B) : tokens.cardSurface;
    final borderColor =
        tokens.isDark ? const Color(0xFF26282F) : tokens.border;
    final textPrimary =
        tokens.isDark ? const Color(0xFFF3F4F6) : tokens.textPrimary;
    final textSecondary =
        tokens.isDark ? const Color(0xFF94979E) : tokens.textSecondary;
    final emerald =
        tokens.isDark ? const Color(0xFF10B981) : tokens.greenAccent;
    final upcomingDotColor =
        tokens.isDark ? const Color(0xFF26282F) : tokens.borderHigh;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
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
                    Text(
                      'Lịch hành trình',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(total / 7).ceil()} tuần xây dựng thói quen',
                      style: TextStyle(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Tuần 1',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: emerald,
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
                tokens: tokens,
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
          Divider(color: borderColor, height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: emerald),
                  const SizedBox(width: 4),
                  Text('Hoàn thành', style: TextStyle(fontSize: 11, color: textSecondary)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.radio_button_checked, size: 10, color: emerald),
                  const SizedBox(width: 4),
                  Text('Hôm nay', style: TextStyle(fontSize: 11, color: textSecondary)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.spa_rounded, size: 12, color: textSecondary),
                  const SizedBox(width: 4),
                  Text('Ngày nghỉ', style: TextStyle(fontSize: 11, color: textSecondary)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: upcomingDotColor),
                  const SizedBox(width: 4),
                  Text('Sắp tới', style: TextStyle(fontSize: 11, color: textSecondary)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell({
    required SamanHomePalette tokens,
    required int dayIndex,
    required bool isToday,
    required bool isDone,
    required bool isRest,
    required bool isMissed,
  }) {
    final textPrimary =
        tokens.isDark ? const Color(0xFFF3F4F6) : tokens.textPrimary;
    final textSecondary =
        tokens.isDark ? const Color(0xFF94979E) : tokens.textSecondary;
    final emerald =
        tokens.isDark ? const Color(0xFF10B981) : tokens.greenAccent;
    final borderColor =
        tokens.isDark ? const Color(0xFF26282F) : tokens.border;
    final surfaceElevated =
        tokens.isDark ? const Color(0xFF212328) : tokens.secondarySurface;

    if (isToday) {
      return Container(
        decoration: BoxDecoration(
          color: surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: emerald, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayIndex',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Icon(Icons.circle, size: 5, color: emerald),
          ],
        ),
      );
    }

    if (isDone) {
      return Container(
        decoration: BoxDecoration(
          color: tokens.isDark ? const Color(0x2610B981) : tokens.greenBadgeBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: tokens.isDark ? const Color(0x4D10B981) : tokens.greenBadgeBorder,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayIndex',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: emerald,
              ),
            ),
            const SizedBox(height: 2),
            Icon(Icons.check, size: 10, color: emerald),
          ],
        ),
      );
    }

    if (isRest) {
      return Container(
        decoration: BoxDecoration(
          color: tokens.isDark
              ? const Color(0x1A212328)
              : tokens.secondarySurface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayIndex',
              style: TextStyle(fontSize: 12, color: textSecondary),
            ),
            const SizedBox(height: 2),
            Icon(Icons.spa_rounded, size: 10, color: textSecondary),
          ],
        ),
      );
    }

    if (isMissed) {
      return Container(
        decoration: BoxDecoration(
          color: surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayIndex',
              style: TextStyle(fontSize: 12, color: textSecondary),
            ),
            const SizedBox(height: 2),
            Container(width: 8, height: 1.5, color: textSecondary),
          ],
        ),
      );
    }

    // Upcoming
    return Container(
      decoration: BoxDecoration(
        color: tokens.isDark
            ? const Color(0x4D212328)
            : tokens.secondarySurface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        '$dayIndex',
        style: TextStyle(fontSize: 12, color: textSecondary),
      ),
    );
  }

  Widget _buildWalletEntryRow(BuildContext context, WidgetRef ref, WalletState walletState) {
    final tokens = SamanHomeTokens.of(context);
    final cardBg =
        tokens.isDark ? const Color(0xFF16171B) : tokens.cardSurface;
    final borderColor =
        tokens.isDark ? const Color(0xFF26282F) : tokens.border;
    final circleBg =
        tokens.isDark ? const Color(0xFF212328) : tokens.secondarySurface;
    final emerald =
        tokens.isDark ? const Color(0xFF10B981) : tokens.greenAccent;
    final textPrimary =
        tokens.isDark ? const Color(0xFFF3F4F6) : tokens.textPrimary;
    final textSecondary =
        tokens.isDark ? const Color(0xFF94979E) : tokens.textSecondary;

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
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1),
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
                      color: circleBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: borderColor, width: 1),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      color: emerald,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Ví điểm & Lượt AI',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: textPrimary,
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
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: textSecondary, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
