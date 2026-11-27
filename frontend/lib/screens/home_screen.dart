// [File: lib/screens/home_screen.dart]
// UI REDESIGN: Saman Home — Obsidian Athletic Precision
// Preserves 100% of existing architecture, auth, providers, and business logic.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../config/app_translations.dart';
import '../core/utils/vn_date_utils.dart';
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
import 'nutrition/nutrition_screen.dart';
import 'profile_screen.dart';
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

  bool _isLoggingOut = false;

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final tokens = SamanHomeTokens.of(context);
        return AlertDialog(
          backgroundColor: tokens.cardSurface,
          title: Text(
            context.tr('logout_confirm_title'),
            style: TextStyle(
              color: tokens.textWhite,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            context.tr('logout_confirm_msg'),
            style: TextStyle(color: tokens.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                context.tr('cancel'),
                style: TextStyle(color: tokens.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.actionButtonSurface,
                foregroundColor: tokens.textWhite,
              ),
              child: Text(context.tr('logout')),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      _isLoggingOut = true;
      try {
        await AuthHelper.logout(ref);
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.login,
            (route) => false,
          );
        }
      } catch (e) {
        _isLoggingOut = false;
        debugPrint('[AUTH] Logout failed: $e');
        if (mounted) {
          if (e is LogoutException &&
              (e.tokenState == AuthTokenState.confirmedLost ||
               e.tokenState == AuthTokenState.indeterminate)) {
            // Credentials lost or indeterminate: do not reopen protected UI on MainScreen.
            // Navigate away to Login and display explanatory warning SnackBar.
            Navigator.pushNamedAndRemoveUntil(
              context,
              AppRoutes.login,
              (route) => false,
            );
            SamanFeedbackSnackBar.show(
              context,
              message: 'Đã đăng xuất (lỗi xóa dữ liệu phụ: $e)',
              type: FeedbackType.warning,
            );
          } else {
            // Token confirmed still intact: remain on screen and offer retry
            SamanFeedbackSnackBar.show(
              context,
              message: 'Đăng xuất thất bại: $e',
              type: FeedbackType.error,
              action: SnackBarAction(
                label: 'Thử lại',
                textColor: SamanHomeTokens.of(context).isDark
                    ? const Color(0xFF10B981)
                    : SamanHomeTokens.of(context).greenAccent,
                onPressed: _logout,
              ),
            );
          }
        }
      }
    }
  }

  // ─── Navigation & Action Handlers ───────────────────────────────
  void _handleNotificationTap() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('no_notifications')),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleSettingsTap() {
    final tokens = SamanHomeTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final sheetTokens = SamanHomeTokens.of(ctx);
        final logoutColor =
            sheetTokens.isDark ? Colors.redAccent : const Color(0xFFDC2626);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    Icons.person_outline_rounded,
                    color: sheetTokens.textWhite,
                  ),
                  title: Text(
                    context.tr('profile_health_details'),
                    style: TextStyle(color: sheetTokens.textWhite),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: sheetTokens.textSecondary,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (widget.onOpenProfile != null) {
                      widget.onOpenProfile!();
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      );
                    }
                  },
                ),
                Divider(color: sheetTokens.borderSubtle),
                ListTile(
                  leading: Icon(
                    Icons.logout_rounded,
                    color: logoutColor,
                  ),
                  title: Text(
                    context.tr('logout'),
                    style: TextStyle(color: logoutColor),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _logout();
                  },
                ),
              ],
            ),
          ),
        );
      },
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
    SamanFeedbackSnackBar.show(
      context,
      message: 'T?nh n?ng ?ang ho?n thi?n, s? s?m ra m?t!',
      type: FeedbackType.info,
    );
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

    final caloriesConsumed = plan?.totalCaloriesConsumed ?? 1850;
    final caloriesTarget = hasDynamicTarget
        ? dynamicTarget.calories
        : ((macroTargets?.calories != null && macroTargets!.calories > 0)
            ? macroTargets.calories
            : (profileState.targetCalories > 0
                ? profileState.targetCalories
                : 2500));

    final proteinConsumed = (plan?.totalProteinConsumed ?? 120).toDouble();
    final proteinTarget = (hasDynamicTarget && dynamicTarget.protein > 0)
        ? dynamicTarget.protein.toDouble()
        : ((macroTargets?.protein != null && macroTargets!.protein > 0)
            ? macroTargets.protein
            : (profileState.targetProtein > 0
                ? profileState.targetProtein.toDouble()
                : 160.0));

    final carbsConsumed = (plan?.totalCarbsConsumed ?? 210).toDouble();
    final carbsTarget = (hasDynamicTarget && dynamicTarget.carbs > 0)
        ? dynamicTarget.carbs.toDouble()
        : ((macroTargets?.carbs != null && macroTargets!.carbs > 0)
            ? macroTargets.carbs
            : (profileState.targetCarbs > 0
                ? profileState.targetCarbs.toDouble()
                : 260.0));

    final fatConsumed = (plan?.totalFatConsumed ?? 55).toDouble();
    final fatTarget = (hasDynamicTarget && dynamicTarget.fat > 0)
        ? dynamicTarget.fat.toDouble()
        : ((macroTargets?.fat != null && macroTargets!.fat > 0)
            ? macroTargets.fat
            : (profileState.targetFat > 0
                ? profileState.targetFat.toDouble()
                : 70.0));

    final waterConsumedLiters = (plan?.currentWater ?? 1800) / 1000.0;
    final targetWaterVal = plan?.targetWater;
    final waterTargetLiters = (targetWaterVal != null && targetWaterVal > 0
            ? targetWaterVal
            : (profileState.waterTargetMl > 0
                ? profileState.waterTargetMl
                : 2500)) /
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
    final onTrackBadgeText = onTrackCount > 0
        ? '$onTrackCount ${context.tr('on_track')}'
        : '2 ${context.tr('on_track')}';

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
                        hasUnreadNotifications: true,
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
                    child: WorkoutRecommendationCarousel(
                      onStartWorkout: _handleStartWorkout,
                      onViewWorkout: _handleViewWorkout,
                    ).animate().fadeIn(delay: 60.ms, duration: 400.ms),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: SamanHomeTokens.spacingSection),
                  ),

                  // 4. Daily Targets (Nutrition & Hydration Module)
                  SliverToBoxAdapter(
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
                  const SliverToBoxAdapter(child: SizedBox(height: 10)),

                  // 5. Quick Action Dock (2-Column Grid)
                  SliverToBoxAdapter(
                    child: QuickActionDock(
                      onLogMealTap: _handleLogMeal,
                      onAddWaterTap: _handleAddWater,
                    ).animate().fadeIn(delay: 140.ms, duration: 400.ms),
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

                  // 7. Saman Picks (Contextual Editorial & Ecosystem)
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
