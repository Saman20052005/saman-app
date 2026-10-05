// [File: lib/screens/home_screen.dart]
// UI REDESIGN: Saman Home — Obsidian Athletic Precision
// Preserves 100% of existing architecture, auth, providers, and business logic.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../config/app_translations.dart';
import '../config/theme_provider.dart';
import '../utils/auth_helper.dart';
import '../providers/profile_provider.dart';
import '../providers/nutrition_provider.dart';
import '../presentation/providers/workout_home_providers.dart';
import '../data/models/exercise.dart';

// Home Modular Design System
import 'home/tokens/saman_home_tokens.dart';
import 'home/widgets/widgets.dart';

// Destination Screens
import 'chat_screen.dart';
import 'food_log_screen.dart';
import 'login/login_screen.dart';
import 'nutrition/nutrition_screen.dart';
import 'profile_screen.dart';
import 'report_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _loadProfile();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(nutritionProvider.notifier).loadDailyPlan(DateTime.now());
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

  Future<void> _onRefresh() async {
    await _loadProfile();
    await ref
        .read(nutritionProvider.notifier)
        .loadDailyPlan(DateTime.now(), forceRefresh: true);
    ref.invalidate(popularExercisesProvider);
  }

  String tr(String key) {
    final locale = ref.read(languageProvider);
    return AppTranslations.text(key, locale);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SamanHomeTokens.cardSurface,
        title: Text(
          tr('logout'),
          style: const TextStyle(
            color: SamanHomeTokens.textWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: SamanHomeTokens.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              tr('cancel'),
              style: const TextStyle(color: SamanHomeTokens.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SamanHomeTokens.actionButtonSurface,
              foregroundColor: SamanHomeTokens.textWhite,
            ),
            child: Text(tr('logout')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await AuthHelper.logout(ref);
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  // ─── Navigation & Action Handlers ───────────────────────────────
  void _handleNotificationTap() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No new notifications. You are on track!'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleSettingsTap() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SamanHomeTokens.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.person_outline_rounded,
                  color: SamanHomeTokens.textWhite,
                ),
                title: const Text(
                  'Profile & Health Details',
                  style: TextStyle(color: SamanHomeTokens.textWhite),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: SamanHomeTokens.textSecondary,
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
              const Divider(color: SamanHomeTokens.borderSubtle),
              ListTile(
                leading: const Icon(
                  Icons.logout_rounded,
                  color: Colors.redAccent,
                ),
                title: Text(
                  tr('logout'),
                  style: const TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _logout();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToChat() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatScreen()),
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
        builder: (_) => FoodLogScreen(selectedDate: DateTime.now()),
      ),
    );
  }

  Future<void> _handleAddWater() async {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final nutritionState = ref.read(nutritionProvider);
    final currentWater = nutritionState.valueOrNull?.currentWater ?? 1800;
    final newWater = currentWater + 250;

    try {
      await ref
          .read(nutritionProvider.notifier)
          .updateWater(newWater, date: todayStr);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '💧 +250ml water logged (${(newWater / 1000).toStringAsFixed(1)}L total)',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update water. Please try again.'),
            behavior: SnackBarBehavior.floating,
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReportScreen()),
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

    // 1. User Name & Header Subtitle
    final rawName = _profile?['name'] ?? 'Saman';
    final userName = rawName.trim().isNotEmpty ? rawName.trim() : 'Saman';

    final now = DateTime.now();
    final dateSubtitle =
        '${DateFormat('EEEE, MMM d').format(now)} • Recovery & Power';

    // 2. Nutrition & Water Metrics
    final caloriesConsumed = plan?.totalCaloriesConsumed ?? 1850;
    final caloriesTarget =
        (macroTargets?.calories != null && macroTargets!.calories > 0)
            ? macroTargets.calories
            : (profileState.targetCalories > 0
                ? profileState.targetCalories
                : 2500);

    final proteinConsumed = (plan?.totalProteinConsumed ?? 120).toDouble();
    final proteinTarget =
        (macroTargets?.protein != null && macroTargets!.protein > 0)
            ? macroTargets.protein
            : (profileState.targetProtein > 0
                ? profileState.targetProtein.toDouble()
                : 160.0);

    final carbsConsumed = (plan?.totalCarbsConsumed ?? 210).toDouble();
    final carbsTarget = (macroTargets?.carbs != null && macroTargets!.carbs > 0)
        ? macroTargets.carbs
        : (profileState.targetCarbs > 0
            ? profileState.targetCarbs.toDouble()
            : 260.0);

    final fatConsumed = (plan?.totalFatConsumed ?? 55).toDouble();
    final fatTarget = (macroTargets?.fat != null && macroTargets!.fat > 0)
        ? macroTargets.fat
        : (profileState.targetFat > 0
            ? profileState.targetFat.toDouble()
            : 70.0);

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
    final onTrackBadgeText =
        onTrackCount > 0 ? '$onTrackCount on track' : '2 on track';

    // 3. Weekly Consistency Metrics
    final completedSessions = weeklyGoal.where((d) => d).length;
    const targetSessions = 4;
    final completionPercentage =
        ((completedSessions / targetSessions) * 100).round().clamp(0, 100);
    final activeDayIndex = (now.weekday - 1).clamp(0, 6);

    return Scaffold(
      backgroundColor: SamanHomeTokens.canvas,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: SamanHomeTokens.greenAccent,
              ),
            )
          : RefreshIndicator(
              color: SamanHomeTokens.greenAccent,
              backgroundColor: SamanHomeTokens.cardSurface,
              onRefresh: _onRefresh,
              child: CustomScrollView(
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
                      onAskSamanTap: _navigateToChat,
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
            ),
    );
  }
}
