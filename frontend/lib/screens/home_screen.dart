// [File: lib/screens/home_screen.dart]
// UI REDESIGN: Saman Home — Obsidian Athletic Precision
// Preserves 100% of existing architecture, auth, providers, and business logic.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../config/app_translations.dart';
import '../core/utils/vn_date_utils.dart';
import '../core/widgets/coach_marks/coach_tour_service.dart';
import '../core/widgets/coach_marks/coach_tour_step.dart';
import '../core/widgets/coach_marks/saman_coach_overlay.dart';
import '../config/routes.dart';
import '../config/theme_provider.dart';
import '../controllers/chat_controller.dart';
import '../models/saman_nudge.dart';
import '../utils/auth_helper.dart';
import '../providers/profile_provider.dart';
import '../providers/nutrition_provider.dart';
import '../presentation/providers/workout_home_providers.dart';
import '../data/models/exercise.dart';

// Home Modular Design System
import 'home/tokens/saman_home_tokens.dart';
import 'home/widgets/widgets.dart';

// Journey Feature
import 'package:shared_preferences/shared_preferences.dart';
import '../features/journey/presentation/providers/journey_providers.dart';
import '../features/journey/presentation/widgets/saman_journey_card.dart';
import '../widgets/saman_feedback_snackbar.dart';
import '../features/journey/presentation/screens/create_journey_screen.dart';

// Destination Screens
import 'chat_screen.dart';
import 'food_log_screen.dart';
import 'main_screen.dart';
import 'nutrition/nutrition_screen.dart';
import 'settings/app_settings_screen.dart';
import '../features/community/presentation/providers/community_providers.dart';
import '../features/community/presentation/screens/notifications/community_notifications_screen.dart';
import '../presentation/screens/active_workout_screen.dart';
import '../presentation/screens/workout_home_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.onOpenProfile});

  final VoidCallback? onOpenProfile;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Map<String, String>? _profile;
  bool _isLoading = false;
  String? _pendingWaterRetryKey;
  String? _pendingWaterRetryDate;
  final GlobalKey _coachTargetsKey = GlobalKey();
  final GlobalKey _coachQuickActionsKey = GlobalKey();
  final GlobalKey _coachWorkoutOrCompanionKey = GlobalKey();
  Timer? _coachTourTimer;

  @override
  void initState() {
    super.initState();
    _loadProfile();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vn = DateTime.now().toUtc().add(const Duration(hours: 7));
      final vnToday = DateTime(vn.year, vn.month, vn.day);
      ref.read(nutritionProvider.notifier).loadDailyPlan(vnToday);
      ref.read(chatControllerProvider.notifier).loadDailyBrief();
      _checkPostOnboardingJourneyInvitation();
      if (ref.read(mainNavIndexProvider) == 0) {
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
      if (ref.read(mainNavIndexProvider) != 0) return;
      if (SamanCoachOverlay.isShowing) return;
      await SamanCoachOverlay.showIfNeeded(
        context: context,
        screenId: CoachTourService.homeScreenId,
        service: ref.read(coachTourServiceProvider),
        steps: [
          CoachTourStep(
            targetKey: _coachTargetsKey,
            title: 'Mục tiêu hôm nay',
            description:
                'Theo dõi lượng Calo, Macro và nước uống thực tế của bạn trong ngày.',
          ),
          CoachTourStep(
            targetKey: _coachQuickActionsKey,
            title: 'Ghi nhanh 1 chạm',
            description:
                'Chạm Log meal để ghi bữa ăn hoặc Add water để cộng nhanh +250ml nước.',
          ),
          CoachTourStep(
            targetKey: _coachWorkoutOrCompanionKey,
            title: 'Bắt đầu tập & Hỏi Saman',
            description:
                'Bắt đầu buổi tập đề xuất hoặc trò chuyện cùng Saman AI Coach bất cứ lúc nào.',
          ),
        ],
      );
    });
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    final name = await AuthHelper.getUserName();
    final email = await AuthHelper.getUserEmail();
    setState(() {
      _profile = {
        'name': (name != null && name.isNotEmpty)
            ? name
            : (email?.split('@').first ?? 'Saman'),
        'email': email ?? '',
      };
      _isLoading = false;
    });
  }

  Future<void> _checkPostOnboardingJourneyInvitation() async {
    if (!mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = ref.read(profileProvider).userId;
      if (userId == null || userId.isEmpty) return;

      final isNew = prefs.getBool('just_finished_onboarding_$userId') ?? false;
      final dismissed = prefs.getBool('has_dismissed_journey_prompt_$userId') ?? false;
      if (isNew && !dismissed) {
        await prefs.setBool('just_finished_onboarding_$userId', false);
        await prefs.setBool('has_dismissed_journey_prompt_$userId', true);
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => CreateJourneyScreen(
            onDismiss: () => Navigator.of(context).pop(),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _onRefresh() async {
    await _loadProfile();
    final vn = DateTime.now().toUtc().add(const Duration(hours: 7));
    final vnToday = DateTime(vn.year, vn.month, vn.day);
    await ref
        .read(nutritionProvider.notifier)
        .loadDailyPlan(vnToday, forceRefresh: true);
    try {
      await ref.read(chatControllerProvider.notifier).loadDailyBrief();
    } catch (_) {}
    ref.invalidate(popularExercisesProvider);
  }

  String tr(String key) {
    final locale = ref.read(languageProvider);
    return AppTranslations.text(key, locale);
  }

  // ─── Navigation & Action Handlers ───────────────────────────────
  void _handleNotificationTap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: AppRoutes.communityNotifications),
        builder: (_) => const CommunityNotificationsScreen(),
      ),
    );
  }

  void _handleSettingsTap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: AppRoutes.appSettings),
        builder: (_) => const AppSettingsScreen(),
      ),
    );
  }

  void _navigateToChat({SamanNudge? nudge}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(initialNudge: nudge)),
    );
  }

  void _navigateToNutrition() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NutritionScreen()),
    );
  }

  void _handleLogMeal() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FoodLogScreen(selectedDate: vnTodayDate()),
      ),
    );
  }

  Future<void> _handleAddWater({String? retryKey, String? retryDate}) async {
    final todayStr = vnTodayIsoDate();
    final dateToUse = retryDate ?? todayStr;
    final keyToUse = retryKey;

    try {
      await ref
          .read(nutritionProvider.notifier)
          .addWater(250, date: dateToUse, idempotencyKey: keyToUse);
      _pendingWaterRetryKey = null;
      _pendingWaterRetryDate = null;
      if (mounted) {
        SamanFeedbackSnackBar.show(
          context,
          message: '💧 +250ml water logged',
          type: FeedbackType.success,
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      _pendingWaterRetryKey =
          keyToUse ?? ref.read(nutritionProvider.notifier).lastFailedWaterKey;
      _pendingWaterRetryDate = dateToUse;
      if (mounted) {
        SamanFeedbackSnackBar.show(
          context,
          message: 'Failed to update water. Please try again.',
          type: FeedbackType.error,
          action: SnackBarAction(
            label: 'Retry',
            textColor: SamanHomeTokens.of(context).isDark
                ? const Color(0xFF10B981)
                : SamanHomeTokens.of(context).greenAccent,
            onPressed: () => _handleAddWater(
              retryKey: _pendingWaterRetryKey,
              retryDate: _pendingWaterRetryDate,
            ),
          ),
        );
      }
    }
  }

  void _handleStartWorkout(RecommendedWorkout workout) {
    final popularExercises =
        ref.read(popularExercisesProvider).valueOrNull ?? const <Exercise>[];

    if (popularExercises.isEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Workout exercises are loading. Please try again shortly.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveWorkoutScreen.fromExercises(
          exercises: popularExercises.take(5).toList(),
          title: workout.title,
        ),
      ),
    );
  }

  void _handleViewWorkout(RecommendedWorkout workout) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WorkoutHomeScreen()),
    );
  }

  void _navigateToProgress() {
    ref.read(mainNavIndexProvider.notifier).state = 1;
  }

  void _navigateToWorkoutHome() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WorkoutHomeScreen()),
    );
  }

  // ─── Build Method ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    ref.watch(languageProvider);
    ref.watch(themeProvider);
    ref.listen<int>(mainNavIndexProvider, (prev, next) {
      if (next == 0 && prev != next) {
        _scheduleCoachTour();
      }
    });

    // Watch providers for real live data
    final profileState = ref.watch(profileProvider);
    final nutritionState = ref.watch(nutritionProvider);
    final plan = nutritionState.valueOrNull;
    final macroTargets = ref.watch(macroTargetsProvider);
    final weeklyGoal = ref.watch(weeklyGoalNotifierProvider);
    final chatState = ref.watch(chatControllerProvider);
    final journeyState = ref.watch(journeyControllerProvider);

    // 1. User Name & Header Subtitle
    final rawName = _profile?['name'] ?? 'Saman';
    final userName = rawName.trim().isNotEmpty ? rawName.trim() : 'Saman';

    final now = DateTime.now();
    final dateSubtitle =
        '${DateFormat('EEEE, MMM d').format(now)} • Recovery & Power';

    // 2. Nutrition & Water Metrics
    final dynamicTarget = plan?.dynamicTarget;
    final hasDynamicTarget = dynamicTarget != null && dynamicTarget.calories > 0;
    final hasDailyPlan = plan != null;

    final caloriesConsumed = plan?.totalCaloriesConsumed ?? 0;
    final caloriesTarget = hasDynamicTarget
        ? dynamicTarget.calories
        : ((macroTargets?.calories != null && macroTargets!.calories > 0)
            ? macroTargets.calories
            : (profileState.targetCalories > 0
                ? profileState.targetCalories
                : 0));

    final proteinConsumed = (plan?.totalProteinConsumed ?? 0).toDouble();
    final proteinTarget = (hasDynamicTarget && dynamicTarget.protein > 0)
        ? dynamicTarget.protein.toDouble()
        : ((macroTargets?.protein != null && macroTargets!.protein > 0)
            ? macroTargets.protein
            : (profileState.targetProtein > 0
                ? profileState.targetProtein.toDouble()
                : 0.0));

    final carbsConsumed = (plan?.totalCarbsConsumed ?? 0).toDouble();
    final carbsTarget = (hasDynamicTarget && dynamicTarget.carbs > 0)
        ? dynamicTarget.carbs.toDouble()
        : ((macroTargets?.carbs != null && macroTargets!.carbs > 0)
            ? macroTargets.carbs
            : (profileState.targetCarbs > 0
                ? profileState.targetCarbs.toDouble()
                : 0.0));

    final fatConsumed = (plan?.totalFatConsumed ?? 0).toDouble();
    final fatTarget = (hasDynamicTarget && dynamicTarget.fat > 0)
        ? dynamicTarget.fat.toDouble()
        : ((macroTargets?.fat != null && macroTargets!.fat > 0)
            ? macroTargets.fat
            : (profileState.targetFat > 0
                ? profileState.targetFat.toDouble()
                : 0.0));

    final waterConsumedLiters = (plan?.currentWater ?? 0) / 1000.0;
    final targetWaterVal = plan?.targetWater;
    final waterTargetLiters = (targetWaterVal != null && targetWaterVal > 0
            ? targetWaterVal
            : (profileState.waterTargetMl > 0
                ? profileState.waterTargetMl
                : 0)) /
        1000.0;

    int onTrackCount = 0;
    if (proteinTarget > 0 && (proteinConsumed / proteinTarget) >= 0.7) {
      onTrackCount++;
    }
    if (carbsTarget > 0 && (carbsConsumed / carbsTarget) >= 0.7) {
      onTrackCount++;
    }
    if (fatTarget > 0 && (fatConsumed / fatTarget) >= 0.7) {
      onTrackCount++;
    }
    final onTrackBadgeText = '$onTrackCount ${context.tr('on_track')}';

    // 3. Weekly Consistency Metrics
    final completedSessions = weeklyGoal.where((d) => d).length;
    const targetSessions = 4;
    final completionPercentage =
        ((completedSessions / targetSessions) * 100).round().clamp(0, 100);
    final activeDayIndex = (now.weekday - 1).clamp(0, 6);

    String? pendingTaskTitle;
    final todayRecord = journeyState.journey?.todayRecord;
    if (todayRecord != null && !todayRecord.isRestDay) {
      for (final t in todayRecord.tasks) {
        if (!t.isCompleted) {
          pendingTaskTitle = t.title;
          break;
        }
      }
    }

    final dailyBriefMetrics = chatState.dailyBriefMetrics;
    final bool hasStaleDailyBriefMetrics = plan != null &&
        dailyBriefMetrics != null &&
        ((dailyBriefMetrics['calories'] as num?)?.round() !=
                plan.totalCaloriesConsumed ||
            (dailyBriefMetrics['water_ml'] as num?)?.round() !=
                plan.currentWater);

    final SamanNudge? activeNudge =
        (chatState.dailyNudge == null || hasStaleDailyBriefMetrics)
            ? (SamanNudgeHelper.buildGroundedHomeNudge(
                  consumedCalories: plan?.totalCaloriesConsumed ?? 0,
                  targetCalories: caloriesTarget,
                  consumedProtein: (plan?.totalProteinConsumed ?? 0).toDouble(),
                  targetProtein: proteinTarget,
                  waterMl: plan?.currentWater ?? 0,
                  waterTargetMl: (waterTargetLiters * 1000).round(),
                  pendingJourneyTaskTitle: pendingTaskTitle,
                  hasRealNutritionData: plan != null,
                ) ??
                (plan != null
                    ? SamanNudge(
                        id: 'live_nutrition_summary_nudge',
                        message:
                            'Hôm nay: ${plan.totalCaloriesConsumed}/$caloriesTarget kcal · ${plan.currentWater} ml nước.',
                        supportingLine:
                            '• ${plan.totalCaloriesConsumed} / $caloriesTarget kcal · ${plan.currentWater} / ${(waterTargetLiters * 1000).round()} ml nước',
                        primaryLabel: 'Hỏi Saman',
                        secondaryLabel: 'Để sau',
                        promptToSend:
                            'Dựa trên tiến độ hôm nay (${plan.totalCaloriesConsumed}/$caloriesTarget kcal, ${plan.currentWater} ml nước), tôi nên làm gì tiếp theo?',
                      )
                    : null))
            : chatState.dailyNudge;

    final tokens = SamanHomeTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: tokens.greenAccent,
              ),
            )
          : RefreshIndicator(
              color: tokens.greenAccent,
              backgroundColor: tokens.cardSurface,
              onRefresh: _onRefresh,
              child: Stack(
                children: [
                  // Ambient mood glow: subtle moss green behind greeting & Ask Saman, fading out by hero bottom
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 440,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0.0, -0.6),
                            radius: 1.0,
                            colors: tokens.isDark
                                ? const [
                                    Color(0x3320362D),
                                    Color(0x1420362D),
                                    Colors.transparent,
                                  ]
                                : [
                                    tokens.greenAccent.withOpacity(0.06),
                                    tokens.greenAccent.withOpacity(0.02),
                                    Colors.transparent,
                                  ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                  // 1. Header (Greeting, Subtitle, Actions)
                  SliverToBoxAdapter(
                    child: SafeArea(
                      bottom: false,
                      child: HomeHeader(
                        userName: userName,
                        dateSubtitle: dateSubtitle,
                        hasUnreadNotifications: ref.watch(
                          communityNotificationsProvider.select(
                            (s) => s.unreadCount > 0,
                          ),
                        ),
                        onNotificationTap: _handleNotificationTap,
                        onSettingsTap: _handleSettingsTap,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // 2. Saman Companion AI Line
                  SliverToBoxAdapter(
                    child: SamanCompanionBar(
                      message: activeNudge?.message,
                      onAskSamanTap: () => _navigateToChat(nudge: activeNudge),
                    ).animate().fadeIn(duration: 350.ms),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: SamanHomeTokens.spacingSection),
                  ),

                  // 3. Workout Recommendation Carousel (Hero Track)
                  SliverToBoxAdapter(
                    child: KeyedSubtree(
                      key: _coachWorkoutOrCompanionKey,
                      child: WorkoutRecommendationCarousel(
                        onStartWorkout: _handleStartWorkout,
                        onViewWorkout: _handleViewWorkout,
                      ).animate().fadeIn(delay: 60.ms, duration: 400.ms),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: SamanHomeTokens.spacingSection),
                  ),

                  // 4. Daily Targets (Nutrition & Hydration Module)
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        KeyedSubtree(
                          key: _coachTargetsKey,
                          child: DailyTargetsCard(
                            caloriesConsumed: caloriesConsumed,
                            caloriesTarget: caloriesTarget,
                            proteinConsumed: proteinConsumed,
                            proteinTarget: proteinTarget,
                            carbsConsumed: carbsConsumed,
                            carbsTarget: carbsTarget,
                            fatConsumed: fatConsumed,
                            fatTarget: fatTarget,
                            waterConsumedLiters: waterConsumedLiters,
                            waterTargetLiters: waterTargetLiters,
                            onTrackBadgeText: onTrackBadgeText,
                            onNutritionDetailsTap: _navigateToNutrition,
                          ).animate().fadeIn(delay: 100.ms, duration: 400.ms),
                        ),
                        if (!hasDailyPlan)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              SamanHomeTokens.spacingLg,
                              8,
                              SamanHomeTokens.spacingLg,
                              0,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.cardSurface,
                                borderRadius: BorderRadius.circular(
                                  SamanHomeTokens.radiusMd,
                                ),
                                border: Border.all(color: tokens.border),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.track_changes_rounded,
                                    size: 18,
                                    color: tokens.greenAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Chưa thiết lập mục tiêu hôm nay',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: tokens.textSecondary,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      ref
                                          .read(mainNavIndexProvider.notifier)
                                          .state = 3;
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: tokens.greenAccent,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text(
                                      'Thiết lập mục tiêu',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
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
                  const SliverToBoxAdapter(child: SizedBox(height: 10)),

                  // 5. Quick Action Dock (2-Column Grid)
                  SliverToBoxAdapter(
                    child: KeyedSubtree(
                      key: _coachQuickActionsKey,
                      child: QuickActionDock(
                        onLogMealTap: _handleLogMeal,
                        onAddWaterTap: _handleAddWater,
                      ).animate().fadeIn(delay: 140.ms, duration: 400.ms),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: SamanHomeTokens.spacingSection),
                  ),

                  // 5B. Saman Journey & Gamification Module
                  SliverToBoxAdapter(
                    child: SamanJourneyCard(
                      onCreateJourneyTap: () => Navigator.pushNamed(context, AppRoutes.createJourney),
                      onViewJourneyTap: () => Navigator.pushNamed(context, AppRoutes.myJourney),
                    ).animate().fadeIn(delay: 160.ms, duration: 400.ms),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: SamanHomeTokens.spacingSection),
                  ),

                  // 6. Weekly Consistency (Performance Module)
                  SliverToBoxAdapter(
                    child: WeeklyConsistencyCard(
                      completedSessions: completedSessions,
                      targetSessions: targetSessions,
                      completionPercentage: completionPercentage,
                      streakDays: completedSessions > 0 ? completedSessions : 3,
                      activeDayIndex: activeDayIndex,
                      onViewProgressTap: _navigateToProgress,
                    ).animate().fadeIn(delay: 180.ms, duration: 400.ms),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: SamanHomeTokens.spacingSection),
                  ),

                  // 7. Saman Community (Native In-App Community Feed Entry)
                  SliverToBoxAdapter(
                    child: SamanCommunityCard(
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.communityFeed),
                    ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: SamanHomeTokens.spacingSection),
                  ),

                  // 8. Saman Picks (Contextual Editorial & Ecosystem)
                  if (kEnableFrozenModulesV1)
                    SliverToBoxAdapter(
                      child: SamanPicksCarousel(
                        onExploreTap: _navigateToWorkoutHome,
                      ).animate().fadeIn(delay: 220.ms, duration: 400.ms),
                    ),

                  // Safe bottom padding
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ],
          ),
        ),
    );
  }
}
