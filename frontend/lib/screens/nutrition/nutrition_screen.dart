// [File: lib/screens/nutrition/nutrition_screen.dart]
// UI REDESIGN: Monochrome Performance — Light + Dark adaptive
// Logic giữ nguyên 100%: providers, API calls, state management

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../food_log_screen.dart';

import '../../../models/nutrition_model.dart';
import '../../../providers/nutrition_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../services/nutrition_repository.dart';
import '../../../config/app_theme.dart'; // ← Design token extension

import 'widgets/nutrition_summary.dart';
import 'widgets/meal_card.dart';
import 'widgets/date_selector.dart';
import 'widgets/plan_generator_sheet.dart';

import 'widgets/log_meal_sheet.dart';
import 'widgets/story_timeline.dart';
import '../../../widgets/nutrition_primitives.dart';

import 'weekly_report_screen.dart';

class NutritionScreen extends ConsumerStatefulWidget {
  const NutritionScreen({super.key});

  @override
  ConsumerState<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends ConsumerState<NutritionScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _isWaterUpdating = false;

  // ─── Logic: giữ nguyên hoàn toàn ──────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDataIfProfileReady();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _loadDataIfProfileReady({bool forceRefresh = false}) {
    final profile = ref.read(profileProvider);
    if (!profile.isProfileValid || profile.targetCalories <= 0) {
      debugPrint('⏳ Profile not ready yet, skipping loadDailyPlan');
      return;
    }
    _loadData(forceRefresh: forceRefresh);
  }

  void _loadData({bool forceRefresh = false}) {
    final profile = ref.read(profileProvider);
    ref.read(nutritionProvider.notifier).loadDailyPlan(
          _selectedDate,
          forceRefresh: forceRefresh,
          fallbackCalories: profile.targetCalories,
          fallbackGoal: profile.profile.goal.name,
        );
  }

  void _confirmReset() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset ngày hôm nay?'),
        content: const Text(
          'Dữ liệu cũ vẫn được lưu vào báo cáo tuần.\n'
          'Daily view sẽ bắt đầu từ đầu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SamanTheme.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(context);
              final ok = await ref
                  .read(nutritionProvider.notifier)
                  .resetDay(_selectedDate);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok
                      ? '✅ Đã reset! Dữ liệu cũ vẫn lưu trong báo cáo tuần.'
                      : '❌ Reset thất bại'),
                ));
              }
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _openSearch() async {
    final profile = ref.read(profileProvider);
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FoodLogScreen(
        userGoal: profile.profile.goal.name,
        selectedDate: _selectedDate,
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã cập nhật thực đơn!')),
      );
      _loadData(forceRefresh: true);
    }
  }

  Future<void> _openStoryLog() async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => LogMealSheet(selectedDate: _selectedDate),
    );
    if (result == true && mounted) {
      _loadData(forceRefresh: true);
    }
  }

  void _openSwapSheet(NutritionLogEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SwapFoodSheet(
        logId: entry.logId,
        foodIndex: 0,
        currentFoodName: entry.foodName,
        onSwapped: () => _loadData(forceRefresh: true),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final planState = ref.watch(nutritionProvider);
    final profileState = ref.watch(profileProvider);
    final colors = Theme.of(context).colorScheme;

    // ✅ Logic ref.listen giữ nguyên
    ref.listen<ProfileState>(profileProvider, (previous, next) {
      final prevValid = previous != null &&
          previous.isProfileValid &&
          previous.targetCalories > 0;
      final nextValid = next.isProfileValid && next.targetCalories > 0;

      if (!nextValid) return;

      if (!prevValid && nextValid) {
        Future.microtask(() {
          if (!mounted) return;
          debugPrint('✅ Profile loaded → trigger loadDailyPlan');
          _loadData();
        });
        return;
      }

      final goalChanged = previous?.profile.goal != next.profile.goal;
      final calChanged = previous?.targetCalories != next.targetCalories;
      if (goalChanged || calChanged) {
        Future.microtask(() {
          if (!mounted) return;
          debugPrint('🔄 Profile changed → reload with clearCache');
          ref.read(nutritionProvider.notifier).clearCache();
          _loadData(forceRefresh: true);
        });
      }
    });

    // Invalid profile screen — monochrome
    if (!profileState.isProfileValid) {
      return Scaffold(
        backgroundColor: context.bgColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: context.trackColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 40,
                    color: colors.secondary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Thiếu thông tin Profile',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vui lòng cập nhật thông tin cá nhân để tiếp tục.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.secondary,
                      ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Vui lòng cập nhật Profile')),
                  ),
                  child: const Text('Cập nhật ngay'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: _buildAppBar(colors),
      floatingActionButton: _buildFAB(colors),
      body: Column(
        children: [
          DateSelector(
            selectedDate: _selectedDate,
            onDateSelected: (date) {
              setState(() => _selectedDate = date);
              _loadDataIfProfileReady();
            },
          ),
          Expanded(
            child: planState.when(
              data: (plan) => plan == null
                  ? _buildEmptyState(profileState)
                  : _buildContent(plan, profileState),
              loading: () => _buildLoading(),
              error: (e, st) => _buildErrorState(e),
            ),
          ),
        ],
      ),
    );
  }

  // ─── AppBar ─────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(ColorScheme colors) {
    return AppBar(
      title: const Text('Nutrition Plan'),
      centerTitle: true,
      actions: [
        _buildAppBarAction(Icons.restart_alt_outlined, 'Reset ngày hôm nay',
            colors, _confirmReset),
        _buildAppBarAction(
            Icons.search_outlined, 'Tìm món ăn', colors, _openSearch),
        _buildAppBarAction(
          Icons.bar_chart_rounded,
          'Báo cáo tuần',
          colors,
          () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const WeeklyReportScreen())),
        ),
        _buildAppBarAction(Icons.refresh_outlined, 'Tải lại', colors,
            () => _loadData(forceRefresh: true)),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildAppBarAction(
    IconData icon,
    String tooltip,
    ColorScheme colors,
    VoidCallback onTap,
  ) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }

  // ─── FAB ────────────────────────────────────────────────────────
  Widget _buildFAB(ColorScheme colors) {
    return FloatingActionButton.extended(
      onPressed: _openStoryLog,
      icon: const Icon(Icons.camera_alt_outlined),
      label: const Text('Log Story',
          style: TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  // ─── Loading (Skeleton) ──────────────────────────────────────────
  Widget _buildLoading() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSkeletonBox(
              height: 100, width: double.infinity), // Story section
          const SizedBox(height: AppSpacing.xl),
          _buildSkeletonBox(height: 180, width: double.infinity), // Summary
          const SizedBox(height: AppSpacing.xl),
          _buildSkeletonBox(height: 80, width: double.infinity), // Water
          const SizedBox(height: AppSpacing.xl),
          _buildSkeletonBox(height: 120, width: double.infinity), // Meal plan
        ],
      ),
    );
  }

  Widget _buildSkeletonBox({required double height, required double width}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: context.trackColor),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ProfileState profileState) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.trackColor,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.no_meals_outlined,
                  size: 64, color: colors.secondary),
            ),
            const SizedBox(height: 24),
            Text(
              'Chưa có kế hoạch nào',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Bắt đầu ngày mới bằng cách tạo một kế hoạch ăn uống thông minh được cá nhân hóa cho bạn.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: colors.secondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  final profile = profileState.profile;
                  if (!profile.isValid) return;

                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => PlanGeneratorSheet(
                      remainingCalories: profileState.targetCalories,
                      consumedCalories: 0,
                      userGoal: profile.goal.name,
                      selectedDate: _selectedDate,
                    ),
                  );
                },
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Tạo kế hoạch hôm nay',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 60, color: colors.error.withOpacity(0.8)),
            const SizedBox(height: 16),
            Text(
              'Không thể tải dữ liệu',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'Đã xảy ra lỗi khi kết nối với máy chủ. Vui lòng kiểm tra lại kết nối mạng.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.secondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => _loadData(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Main content ────────────────────────────────────────────────
  Widget _buildContent(dynamic plan, ProfileState profileState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Story log
          const NutritionSectionHeader(label: 'Nhật ký ăn uống (Story)'),
          const SizedBox(height: AppSpacing.md),
          StoryTimeline(date: _selectedDate),
          _buildEntriesSection(plan),
          Divider(height: 1, color: context.trackColor),
          const SizedBox(height: AppSpacing.xl),

          // Summary
          NutritionSummary(plan: plan, profile: profileState),
          const SizedBox(height: AppSpacing.lg),

          // Water tracker
          _buildWaterTracker(plan, profileState),
          const SizedBox(height: AppSpacing.xl),

          // Meal plan
          const NutritionSectionHeader(label: 'Kế hoạch gợi ý (Meal Plan)'),
          const SizedBox(height: AppSpacing.md),
          if (ref.watch(nutritionProvider.notifier).isMealPlanGenerating)
            _buildSkeletonBox(height: 200, width: double.infinity)
          else if (plan.meals.isEmpty)
            _buildEmptyMealPlan(plan, profileState)
          else
            ...plan.meals.map((meal) => MealCard(meal: meal)),

          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }

  // ─── Entries section ─────────────────────────────────────────────
  Widget _buildEntriesSection(NutritionPlan plan) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.check_circle_outline,
                size: 16, color: SamanTheme.success),
            const SizedBox(width: 8),
            Text(
              'ĐÃ ĂN HÔM NAY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.secondary,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            if (plan.entries.isNotEmpty)
              Text(
                '${plan.entries.length} món',
                style: TextStyle(fontSize: 11, color: colors.secondary),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (plan.entries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: context.trackColor.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.trackColor),
            ),
            child: Column(
              children: [
                Icon(Icons.restaurant_outlined,
                    size: 24, color: colors.secondary.withOpacity(0.5)),
                const SizedBox(height: 8),
                Text(
                  'Chưa có bữa ăn nào hôm nay',
                  style: TextStyle(fontSize: 12, color: colors.secondary),
                ),
              ],
            ),
          )
        else
          ...plan.entries.map((entry) => _buildEntryTile(entry)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildEntryTile(NutritionLogEntry entry) {
    final name = entry.foodName;
    final calories = entry.totalCalories;
    final mealType = entry.mealType;
    final logId = entry.logId;
    final colors = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [context.softShadow],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.trackColor,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.restaurant_outlined,
                size: 16, color: colors.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: colors.onSurface,
                  ),
                ),
                if (mealType.isNotEmpty)
                  Text(
                    mealType,
                    style: TextStyle(fontSize: 11, color: colors.secondary),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$calories kcal',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: colors.onSurface,
                ),
              ),
              if (logId.isNotEmpty) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _openSwapSheet(entry),
                  child: Icon(
                    Icons.swap_horiz_outlined,
                    size: 18,
                    color: colors.secondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ─── Empty meal plan ─────────────────────────────────────────────
  Widget _buildEmptyMealPlan(NutritionPlan plan, ProfileState profile) {
    final targetCal = profile.targetCalories;
    final consumed = plan.totalCaloriesConsumed;
    final remaining = (targetCal - consumed).clamp(0, targetCal);
    final remainPro =
        ((profile.targetProtein) - plan.totalProteinConsumed).clamp(0, 999);
    final remainCarbs =
        ((profile.targetCarbs) - plan.totalCarbsConsumed).clamp(0, 9999);
    final remainFat =
        ((profile.targetFat) - plan.totalFatConsumed).clamp(0, 999);
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NutritionMetricCard(
          label: 'Calories remaining',
          value: '$remaining',
          unit: 'kcal',
          icon: Icons.local_fire_department_outlined,
        ),
        const SizedBox(height: AppSpacing.lg),
        NutritionMacroProgress(
          label: 'Protein',
          consumed: '${plan.totalProteinConsumed.toInt()}g',
          target: '${profile.targetProtein.toInt()}g',
          progress: profile.targetProtein > 0
              ? (plan.totalProteinConsumed / profile.targetProtein)
                  .clamp(0.0, 1.0)
              : 0,
          remaining: '${remainPro}g remaining',
        ),
        const SizedBox(height: AppSpacing.lg),
        NutritionMacroProgress(
          label: 'Carbs',
          consumed: '${plan.totalCarbsConsumed.toInt()}g',
          target: '${profile.targetCarbs.toInt()}g',
          progress: profile.targetCarbs > 0
              ? (plan.totalCarbsConsumed / profile.targetCarbs).clamp(0.0, 1.0)
              : 0,
          remaining: '${remainCarbs}g remaining',
        ),
        const SizedBox(height: AppSpacing.lg),
        NutritionMacroProgress(
          label: 'Fat',
          consumed: '${plan.totalFatConsumed.toInt()}g',
          target: '${profile.targetFat.toInt()}g',
          progress: profile.targetFat > 0
              ? (plan.totalFatConsumed / profile.targetFat).clamp(0.0, 1.0)
              : 0,
          remaining: '${remainFat}g remaining',
        ),
        if (plan.rolloverCalories > 0) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: context.trackColor,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_forward, size: 13, color: colors.secondary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Rollover từ hôm qua: +${plan.rolloverCalories} kcal',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),

        // AI CTA card — dark charcoal (giữ dark gradient vì đây là accent element)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.insightCardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome,
                        size: 14, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'AI Meal Planner',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Tạo kế hoạch hôm nay',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                remaining > 0
                    ? 'AI gợi ý 4 bữa ăn phù hợp\nvới $remaining kcal còn lại của bạn.'
                    : 'Bạn đã đạt mục tiêu calories hôm nay! 🎉',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: remaining > 0
                      ? () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => PlanGeneratorSheet(
                              remainingCalories: remaining,
                              consumedCalories: plan.totalCaloriesConsumed,
                              userGoal: profile.profile.goal.name,
                              selectedDate: _selectedDate,
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.auto_awesome, size: 15),
                  label: Text(
                    remaining > 0 ? 'Tạo kế hoạch' : 'Đã hoàn thành',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    disabledBackgroundColor: colors.onPrimary.withOpacity(0.15),
                    disabledForegroundColor: colors.onPrimary.withOpacity(0.54),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Water tracker — monochrome ──────────────────────────────────
  Widget _buildWaterTracker(NutritionPlan plan, ProfileState profile) {
    final waterTarget =
        plan.targetWater > 0 ? plan.targetWater : profile.waterTargetMl;
    final ratio = waterTarget > 0 ? plan.currentWater / waterTarget : 0.0;
    final showWarning = ratio < 0.5 && DateTime.now().hour >= 15;
    final colors = Theme.of(context).colorScheme;
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [context.softShadow],
        border:
            showWarning ? Border.all(color: colors.outline, width: 1.5) : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.water_drop_outlined,
                color: colors.onSurface,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Water Intake',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: colors.onSurface,
                          ),
                        ),
                        if (showWarning) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.trackColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Uống thêm nước!',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: colors.secondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${plan.currentWater} / $waterTarget ml',
                      style: TextStyle(color: colors.secondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Controls
              _buildWaterBtn(
                Icons.remove,
                () async {
                  setState(() => _isWaterUpdating = true);
                  try {
                    final dateStr =
                        DateFormat('yyyy-MM-dd').format(_selectedDate);
                    final v =
                        plan.currentWater >= 250 ? plan.currentWater - 250 : 0;
                    await ref
                        .read(nutritionProvider.notifier)
                        .updateWater(v, date: dateStr);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                '❌ Không thể cập nhật lượng nước. Vui lòng thử lại.')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isWaterUpdating = false);
                  }
                },
                colors,
              ),
              const SizedBox(width: 8),
              _buildWaterBtn(
                Icons.add,
                () async {
                  setState(() => _isWaterUpdating = true);
                  try {
                    final dateStr =
                        DateFormat('yyyy-MM-dd').format(_selectedDate);
                    await ref.read(nutritionProvider.notifier).updateWater(
                          plan.currentWater + 250,
                          date: dateStr,
                        );
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                '❌ Không thể cập nhật lượng nước. Vui lòng thử lại.')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isWaterUpdating = false);
                  }
                },
                colors,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isWaterUpdating)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 2),
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
              ),
            )
          else
            const SizedBox(height: 4),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: context.trackColor,
              valueColor: AlwaysStoppedAnimation<Color>(colors.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaterBtn(IconData icon, VoidCallback onTap, ColorScheme colors) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: context.trackColor,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: colors.onSurface),
      ),
    );
  }
}

// ─── Swap Food Sheet — UI monochrome ─────────────────────────────
class _SwapFoodSheet extends ConsumerStatefulWidget {
  final String logId;
  final int foodIndex;
  final String currentFoodName;
  final VoidCallback onSwapped;

  const _SwapFoodSheet({
    required this.logId,
    required this.foodIndex,
    required this.currentFoodName,
    required this.onSwapped,
  });

  @override
  ConsumerState<_SwapFoodSheet> createState() => _SwapFoodSheetState();
}

class _SwapFoodSheetState extends ConsumerState<_SwapFoodSheet> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  final NutritionRepository _repository = NutritionRepository();

  // ─── Logic: giữ nguyên ─────────────────────────────────────────
  Future<void> _search(String q) async {
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final foods = await _repository.searchFoods(q, limit: 10);
      setState(() {
        _results = foods
            .map((f) => {
                  'id': f.id,
                  'name': f.name,
                  'calories': f.calories,
                  'protein': f.protein,
                  'carbs': f.carbs,
                  'fat': f.fat,
                })
            .toList();
      });
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _doSwap(Map<String, dynamic> food) async {
    try {
      await ref.read(nutritionProvider.notifier).swapLoggedMeal(
            DateTime.now(),
            widget.logId,
          );
      if (mounted) {
        Navigator.pop(context);
        widget.onSwapped();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Đã đổi sang ${food['name']}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Swap thất bại')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          children: [
            // Drag handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: colors.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Đổi: ${widget.currentFoodName}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: colors.onSurface,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              onChanged: _search,
              decoration: const InputDecoration(
                hintText: 'Tìm món thay thế...',
                prefixIcon: Icon(Icons.search_outlined),
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                itemCount: _results.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: colors.outline,
                ),
                itemBuilder: (_, i) {
                  final f = _results[i];
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    title: Text(
                      f['name'] ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      '${f['calories']} kcal · P${f['protein']}g C${f['carbs']}g F${f['fat']}g',
                      style: TextStyle(color: colors.secondary, fontSize: 12),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_outlined,
                      size: 18,
                      color: colors.secondary,
                    ),
                    onTap: () => _doSwap(f),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
