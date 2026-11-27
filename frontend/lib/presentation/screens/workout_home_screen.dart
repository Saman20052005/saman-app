import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/widgets/coach_marks/coach_tour_service.dart';
import '../../core/widgets/coach_marks/coach_tour_step.dart';
import '../../core/widgets/coach_marks/saman_coach_overlay.dart';
import '../../data/models/exercise.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/workout_home_providers.dart';
import '../tokens/saman_workout_tokens.dart';
import 'exercise_library_screen.dart';
import 'my_plans_screen.dart';
import 'workout_history_screen.dart';
import 'active_workout_screen.dart';
import '../providers/active_workout_providers.dart';
import '../providers/muscle_recovery_provider.dart';
import '../providers/workout_history_providers.dart';
import '../widgets/muscle_recovery_card.dart';
import '../../features/membership/domain/models/membership_plan.dart';
import '../../features/membership/presentation/screens/plan_detail_screen.dart';
import '../../features/membership/presentation/widgets/upgrade_bottom_sheet.dart';
import '../../config/app_translations.dart';
import '../../providers/profile_provider.dart';
import '../../screens/main_screen.dart';

class WorkoutHomeScreen extends ConsumerStatefulWidget {
  const WorkoutHomeScreen({super.key});

  @override
  ConsumerState<WorkoutHomeScreen> createState() => _WorkoutHomeScreenState();
}

class _WorkoutHomeScreenState extends ConsumerState<WorkoutHomeScreen> {
  final GlobalKey _coachScheduledHeroKey = GlobalKey();
  final GlobalKey _coachQuickActionsKey = GlobalKey();
  final GlobalKey _coachRecoveryCardKey = GlobalKey();
  Timer? _coachTourTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(mainNavIndexProvider) == 1) {
        _scheduleCoachTour();
      }
    });
  }

  @override
  void dispose() {
    _coachTourTimer?.cancel();
    super.dispose();
  }

  void _scheduleCoachTour() {
    if (CoachTourService.isTestBypassEnabled) return;
    _coachTourTimer?.cancel();
    _coachTourTimer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      if (ref.read(mainNavIndexProvider) != 1) return;
      if (SamanCoachOverlay.isShowing) return;
      await SamanCoachOverlay.showIfNeeded(
        context: context,
        screenId: CoachTourService.workoutScreenId,
        service: ref.read(coachTourServiceProvider),
        steps: [
          CoachTourStep(
            targetKey: _coachScheduledHeroKey,
            title: 'Chọn buổi tập nhanh',
            description:
                'Bắt đầu ngay buổi tập đề xuất hôm nay hoặc tạo lịch tập riêng của bạn.',
          ),
          CoachTourStep(
            targetKey: _coachQuickActionsKey,
            title: 'Form Check AI & Thư viện bài',
            description:
                'Dùng Form Check AI đếm rep tự động và kiểm tra kỹ thuật tập chuẩn xác.',
          ),
          CoachTourStep(
            targetKey: _coachRecoveryCardKey,
            title: 'Phục hồi cơ & Video Story',
            description:
                'Theo dõi mức hồi phục 6 nhóm cơ 72h và lưu Video Story để Saman Coach dẫn chứng lỗi form.',
          ),
        ],
      );
    });
  }

  void _navigateToLibrary([String category = 'All']) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseLibraryScreen(initialCategory: category),
      ),
    );
  }

  void _navigateToMyPlans() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyPlansScreen()),
    );
  }

  Future<void> _openWorkoutUpgradeSheet() async {
    final selectedTier = await showUpgradeBottomSheet(
      context,
      tier: MembershipTier.pro,
    );
    if (!mounted || selectedTier == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        settings:
            RouteSettings(name: '/membership/detail/${selectedTier.name}'),
        builder: (_) => PlanDetailScreen(tier: selectedTier),
      ),
    );
  }

  void _navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WorkoutHistoryScreen()),
    );
  }

  Future<void> _handleStartWorkout(ScheduledSessionInfo scheduled) async {
    ref
        .read(activeWorkoutSessionProvider.notifier)
        .startScheduledSession(title: scheduled.title);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ActiveWorkoutScreen(),
    ));
    if (mounted) {
      ref.invalidate(muscleRecoveryProvider);
    }
  }

  bool _isVi(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    return locale.languageCode == 'vi';
  }

  Future<void> _handleQuickStart() async {
    final exercise = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(
          builder: (_) => const ExerciseLibraryScreen(
                initialCategory: 'All',
                selectExercise: true,
              )),
    );
    if (!mounted || exercise == null) return;
    final quickTitle = _isVi(context) ? 'Bắt đầu nhanh' : 'Quick Start';
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ActiveWorkoutScreen.fromExercises(
        exercises: [exercise],
        title: quickTitle,
      ),
    ));
    if (mounted) {
      ref.invalidate(muscleRecoveryProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(mainNavIndexProvider, (prev, next) {
      if (next == 1 && prev != next) {
        _scheduleCoachTour();
      }
    });
    final t = SamanWorkoutTokens.of(context);
    final profileState = ref.watch(profileProvider);

    if (!profileState.isProfileValid) {
      return Scaffold(
        backgroundColor: t.canvas,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: t.cardSurface,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.person_outline_rounded,
                        size: 36,
                        color: t.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    context.tr('missing_profile_info'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                  if (Localizations.maybeLocaleOf(context)?.languageCode != 'vi')
                    const SizedBox(
                      width: 0,
                      height: 0,
                      child: OverflowBox(
                        child: Text(
                          'Thiếu thông tin Profile',
                          style: TextStyle(
                            fontSize: 0.1,
                            color: Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('missing_profile_desc'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: t.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.buttonPrimary,
                        foregroundColor: t.buttonPrimaryText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        ref.read(mainNavIndexProvider.notifier).state = 4;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _isVi(context)
                                  ? 'Vui lòng cập nhật Profile'
                                  : 'Please update your Profile',
                              style: const TextStyle(fontFamily: 'Manrope'),
                            ),
                          ),
                        );
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            context.tr('update_profile_now'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (Localizations.maybeLocaleOf(context)?.languageCode != 'vi')
                            const SizedBox(
                              width: 0,
                              height: 0,
                              child: OverflowBox(
                                child: Text(
                                  'Cập nhật ngay',
                                  style: TextStyle(
                                    fontSize: 0.1,
                                    color: Colors.transparent,
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
          ),
        ),
      );
    }

    final scheduled = ref.watch(scheduledWorkoutProvider);
    final upcomingPlans = ref.watch(upcomingPlansProvider);
    final recentWorkout = ref.watch(recentWorkoutSummaryProvider);

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          color: t.emeraldAccent,
          backgroundColor: t.cardSurface,
          onRefresh: () async {
            ref.invalidate(muscleRecoveryProvider);
            ref.invalidate(workoutHistoryProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
            SamanWorkoutTokens.spacingLg,
            SamanWorkoutTokens.spacingSm,
            SamanWorkoutTokens.spacingLg,
            SamanWorkoutTokens.spacingXxl * 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header
              _buildHeader(t),
              const SizedBox(height: SamanWorkoutTokens.spacingLg),

              // 2. Today's Scheduled Session Hero Card
              KeyedSubtree(
                key: _coachScheduledHeroKey,
                child: _buildScheduledSessionHero(scheduled, t),
              ),
              const SizedBox(height: SamanWorkoutTokens.spacingLg),

              // 2.5 Muscle Recovery Card
              KeyedSubtree(
                key: _coachRecoveryCardKey,
                child: const MuscleRecoveryCard(),
              ),
              const SizedBox(height: SamanWorkoutTokens.spacingLg),

              // 3. Quick Action Row
              KeyedSubtree(
                key: _coachQuickActionsKey,
                child: _buildQuickActionRow(t),
              ),
              const SizedBox(height: SamanWorkoutTokens.spacingXl),

              // 4. Train by Focus
              _buildTrainByFocus(t),
              const SizedBox(height: SamanWorkoutTokens.spacingXl),

              // 5. Your Plan
              _buildYourPlan(upcomingPlans, t),
              const SizedBox(height: SamanWorkoutTokens.spacingXl),

              // 6. Last Workout
              _buildLastWorkout(recentWorkout, t),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildHeader(SamanWorkoutPalette t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('workout_title'),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      color: t.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.tr('workout_home_subtitle'),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      color: t.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
              onTap: _navigateToMyPlans,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: t.cardSurface,
                  borderRadius:
                      BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                  border: Border.all(color: t.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bookmark_border,
                      size: 16,
                      color: t.emeraldAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.tr('my_plans'),
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildUpgradeChip(t),
      ],
    );
  }

  Widget _buildUpgradeChip(SamanWorkoutPalette t) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('workout_upgrade_chip'),
        onTap: _openWorkoutUpgradeSheet,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: t.cardSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: t.emeraldAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'PRO',
                      style: TextStyle(
                        color: t.emeraldAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    TextSpan(
                      text: _isVi(context) ? ' · XEM TRƯỚC' : ' · PREVIEW',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        color: t.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 14,
                color: t.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduledSessionHero(
      ScheduledSessionInfo session, SamanWorkoutPalette t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category eyebrow + Planned pill
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
                child: Text(
              context.tr('today_scheduled_session'),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
                color: t.textMuted,
              ),
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: t.emeraldBadgeBg,
                borderRadius:
                    BorderRadius.circular(SamanWorkoutTokens.radiusXs),
                border: Border.all(color: t.emeraldBadgeBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: t.emeraldAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    session.status,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: t.emeraldAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Hero Card Box
        Container(
          height: 290,
          decoration: BoxDecoration(
            color: t.cardSurface,
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
            border: Border.all(color: t.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo asset
              CachedNetworkImage(
                imageUrl: session.imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: t.surfaceElevated,
                ),
                errorWidget: (_, __, ___) => Container(
                  color: t.surfaceElevated,
                  child: Center(
                    child: Icon(Icons.fitness_center,
                        color: t.textMuted, size: 48),
                  ),
                ),
              ),

              // Gradient Overlay (Calm obsidian fade — preserved across Light/Dark)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xFF0C0D0E),
                      Color(0x990C0D0E),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.6, 1.0],
                  ),
                ),
              ),

              // Content overlay (light foreground over dark scrim)
              Padding(
                padding: const EdgeInsets.all(SamanWorkoutTokens.spacingLg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Protocol badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: SamanWorkoutTokens.emeraldBadgeBg,
                        borderRadius:
                            BorderRadius.circular(SamanWorkoutTokens.radiusXs),
                        border: Border.all(
                            color: SamanWorkoutTokens.emeraldBadgeBorder),
                      ),
                      child: Text(
                        session.protocol.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: SamanWorkoutTokens.emeraldAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Session title
                    Text(
                      session.title,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        color: SamanWorkoutTokens.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Metrics
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined,
                            size: 16, color: SamanWorkoutTokens.textSub),
                        const SizedBox(width: 4),
                        Text(
                          _isVi(context)
                              ? '${session.durationMinutes} phút'
                              : '${session.durationMinutes} min',
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            color: SamanWorkoutTokens.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('•',
                            style: TextStyle(
                                color: SamanWorkoutTokens.textSecondary)),
                        const SizedBox(width: 8),
                        const Icon(Icons.fitness_center,
                            size: 16, color: SamanWorkoutTokens.textSub),
                        const SizedBox(width: 4),
                        Text(
                          _isVi(context)
                              ? '${session.exerciseCount} bài tập'
                              : '${session.exerciseCount} ${session.exerciseCount == 1 ? 'exercise' : 'exercises'}',
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            color: SamanWorkoutTokens.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // CTAs: Start workout + View plan
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: ElevatedButton.icon(
                              onPressed: () => _handleStartWorkout(session),
                              icon: const Icon(Icons.play_arrow,
                                  size: 18,
                                  color: SamanWorkoutTokens.buttonPrimaryText),
                              label: Text(
                                context.tr('start_workout'),
                                style: const TextStyle(
                                  color: SamanWorkoutTokens.buttonPrimaryText,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    SamanWorkoutTokens.buttonPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      SamanWorkoutTokens.radiusMd),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 44,
                          child: OutlinedButton(
                            onPressed: _navigateToMyPlans,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: const Color(0xCC212328),
                              side: const BorderSide(
                                  color: SamanWorkoutTokens.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    SamanWorkoutTokens.radiusMd),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  context.tr('view_plan'),
                                  style: const TextStyle(
                                    color: SamanWorkoutTokens.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_forward,
                                    size: 14,
                                    color: SamanWorkoutTokens.textSecondary),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionRow(SamanWorkoutPalette t) {
    return Row(
      children: [
        // Quick start
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
            onTap: _handleQuickStart,
            child: Container(
              padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
              decoration: BoxDecoration(
                color: t.cardSurface,
                borderRadius:
                    BorderRadius.circular(SamanWorkoutTokens.radiusLg),
                border: Border.all(color: t.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: t.surfaceElevated,
                          borderRadius: BorderRadius.circular(
                              SamanWorkoutTokens.radiusSm),
                          border: Border.all(color: t.border),
                        ),
                        child: Icon(Icons.bolt,
                            size: 18, color: t.textPrimary),
                      ),
                      Icon(Icons.arrow_forward,
                          size: 16, color: t.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('quick_start'),
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.tr('quick_start_desc'),
                    style: TextStyle(
                      color: t.textSub,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Browse library
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
            onTap: () => _navigateToLibrary('All'),
            child: Container(
              padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
              decoration: BoxDecoration(
                color: t.cardSurface,
                borderRadius:
                    BorderRadius.circular(SamanWorkoutTokens.radiusLg),
                border: Border.all(color: t.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: t.surfaceElevated,
                          borderRadius: BorderRadius.circular(
                              SamanWorkoutTokens.radiusSm),
                          border: Border.all(color: t.border),
                        ),
                        child: Icon(Icons.search,
                            size: 18, color: t.textPrimary),
                      ),
                      Icon(Icons.arrow_forward,
                          size: 16, color: t.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('browse_library'),
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.tr('explore_exercises'),
                    style: TextStyle(
                      color: t.textSub,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrainByFocus(SamanWorkoutPalette t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                context.tr('train_by_focus'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  color: t.textMuted,
                ),
              ),
            ),
            InkWell(
              onTap: () => _navigateToLibrary('All'),
              child: Row(
                children: [
                  Text(
                    context.tr('all_categories'),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: t.emeraldAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_forward,
                      size: 14, color: t.emeraldAccent),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Upper Body Card
            Expanded(
              child: _FocusCategoryCard(
                title: _isVi(context) ? 'Thân trên' : 'Upper Body',
                subtitle: _isVi(context)
                    ? 'Ngực, Lưng, Tay'
                    : 'Chest, Back, Arms',
                imageUrl:
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuCcanzIWbwr1wbgiYXZhgMavpn31gfEXKJTTVhG3mquc-uBH5EnvXNlZEn2tvJa2509Y8AAV8q2yKYpkns0qwUEZVDus2qc9VFylQ516_Hq1Mjl3KEiDeoevmknk51V83Mnpg6vtV74d533hkcOjlve55QtOPZXnvoFLwuQHbrJ-ZrJ1yV7bhiMrP4NA4ZRiUfuZaL7PA4zC5YPbomD8A-Ex10M9ou1Vzeei3-VoXwV4ZfCgbyY7Cd1',
                onTap: () => _navigateToLibrary('Upper Body'),
              ),
            ),
            const SizedBox(width: 10),

            // Lower Body Card
            Expanded(
              child: _FocusCategoryCard(
                title: _isVi(context) ? 'Thân dưới' : 'Lower Body',
                subtitle: _isVi(context)
                    ? 'Đùi trước, Mông, Chân'
                    : 'Quads, Glutes, Legs',
                imageUrl:
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuDrTlcWy4Im6QZihMwXHDm8qtDNHF9aIfXlkMfDMPbeSt3SEKpZcylKb8fHhO-FC5-uhmsT1lkJ5MspMUMssZKfj30ijhcVK7-Hg442bihGVzYUXiUotr-0XXGOUVx8VgQwldxSdTC3AminLzNQoU7ADaat_E3-9J15gY6qjXK6Pdui0DpighlW3JIihc7bFOOPWbs4T_LencKQ4KVQ_EBli7Xb9AEe0uh-ps9srVpebEFbeu-xJUFB',
                onTap: () => _navigateToLibrary('Lower Body'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildYourPlan(
      List<UpcomingPlanSession> upcoming, SamanWorkoutPalette t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                context.tr('your_plan'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  color: t.textMuted,
                ),
              ),
            ),
            InkWell(
              onTap: _navigateToMyPlans,
              child: Row(
                children: [
                  Text(
                    context.tr('view_full_plan'),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: t.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right,
                      size: 14, color: t.textSecondary),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: t.cardSurface,
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
            border: Border.all(color: t.border),
          ),
          child: Column(
            children: List.generate(upcoming.length, (index) {
              final item = upcoming[index];
              final isLast = index == upcoming.length - 1;

              return Container(
                padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : Border(
                          bottom: BorderSide(color: t.border),
                        ),
                ),
                child: Row(
                  children: [
                    // Calendar square
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: t.surfaceElevated,
                        borderRadius:
                            BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                        border: Border.all(color: t.border),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.dayName.toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: t.textSub,
                            ),
                          ),
                          Text(
                            item.dayNumber,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: t.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Titles & metrics
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                  child: Text(
                                item.title,
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              )),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: item.isRest
                                      ? t.surfaceElevated
                                      : t.emeraldBadgeBg,
                                  borderRadius: BorderRadius.circular(
                                      SamanWorkoutTokens.radiusXs),
                                  border: Border.all(
                                    color: item.isRest
                                        ? t.borderSubtle
                                        : t.emeraldBadgeBorder,
                                  ),
                                ),
                                child: Text(
                                  item.badge,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: item.isRest
                                        ? t.textSub
                                        : t.emeraldAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.metrics,
                            style: TextStyle(
                              color: t.textSub,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: t.textSecondary,
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildLastWorkout(
      RecentWorkoutSummary? recent, SamanWorkoutPalette t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                context.tr('last_workout'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  color: t.textMuted,
                ),
              ),
            ),
            InkWell(
              onTap: _navigateToHistory,
              child: Row(
                children: [
                  Text(
                    context.tr('view_history'),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: t.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right,
                      size: 14, color: t.textSecondary),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (recent != null)
          InkWell(
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
            onTap: _navigateToHistory,
            child: Container(
              padding: const EdgeInsets.all(SamanWorkoutTokens.spacingLg),
              decoration: BoxDecoration(
                color: t.cardSurface,
                borderRadius:
                    BorderRadius.circular(SamanWorkoutTokens.radiusLg),
                border: Border.all(color: t.border),
              ),
              child: Row(
                children: [
                  // Completed check icon box
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: t.surfaceElevated,
                      borderRadius:
                          BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                      border: Border.all(color: t.border),
                    ),
                    child: Icon(
                      Icons.check_circle_outline,
                      color: t.emeraldAccent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Session details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recent.title,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${recent.relativeTime} • ${recent.metrics}',
                          style: TextStyle(
                            color: t.textSub,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Arrow button
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: t.surfaceElevated,
                      borderRadius:
                          BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                      border: Border.all(color: t.border),
                    ),
                    child: Icon(Icons.arrow_forward,
                        size: 16, color: t.textSecondary),
                  ),
                ],
              ),
            ),
          )
        else
          InkWell(
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
            onTap: _navigateToHistory,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(SamanWorkoutTokens.spacingLg),
              decoration: BoxDecoration(
                color: t.cardSurface,
                borderRadius:
                    BorderRadius.circular(SamanWorkoutTokens.radiusLg),
                border: Border.all(color: t.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.history,
                    size: 20,
                    color: t.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr('no_saved_workouts'),
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _FocusCategoryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final VoidCallback onTap;

  const _FocusCategoryCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = SamanWorkoutTokens.of(context);
    final radius = BorderRadius.circular(SamanWorkoutTokens.radiusLg);
    return Container(
      height: 160,
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: t.border, width: 1),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: t.isDark ? const Color(0xFF0C0D0E) : t.cardSurface,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  bottom: -1,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    placeholder: (_, __) => ColoredBox(
                      color: t.isDark
                          ? const Color(0xFF0C0D0E)
                          : t.surfaceElevated,
                    ),
                    errorWidget: (_, __, ___) => ColoredBox(
                      color: t.isDark
                          ? const Color(0xFF0C0D0E)
                          : t.surfaceElevated,
                      child: Icon(Icons.fitness_center, color: t.textMuted),
                    ),
                  ),
                ),
                // Dark scrim anchored past bottom (-1) to prevent subpixel gap on odd DPRs
                const Positioned.fill(
                  bottom: -1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color(0xFF0C0D0E),
                          Color(0xF00C0D0E),
                          Color(0x800C0D0E),
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.14, 0.55, 1.0],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontFamily: 'Manrope',
                                color: SamanWorkoutTokens.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              size: 16, color: SamanWorkoutTokens.textSub),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          color: SamanWorkoutTokens.textSub,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
