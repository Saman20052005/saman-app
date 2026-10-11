import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../models/nutrition_model.dart';
import '../../../providers/nutrition_provider.dart';
import '../../../providers/profile_provider.dart';
import '../food_log_screen.dart';
import 'meal_story_screen.dart';
import 'weekly_report_screen.dart';
import 'widgets/date_selector.dart';
import 'widgets/log_meal_sheet.dart';
import 'widgets/nutrition_logged_meal_card.dart';
import 'widgets/nutrition_summary.dart';
import 'widgets/nutrition_water_card.dart';
import 'widgets/plan_generator_sheet.dart';
import 'widgets/planned_meal_card.dart';

/// Redesigned Nutrition Screen for Saman App (Milestone CP2)
/// Implements authentic Calm Athleticism design spec:
/// 1. Header (Title + Subtitle + Report button)
/// 2. Compact Date Navigator Pill
/// 3. Today's Intake (Calories comparison headline + 6px progress bar + 3-macro telemetry)
/// 4. Fast Actions (Log meal primary CTA + Scan food secondary CTA)
/// 5. Logged Meals list with Meal Story route
/// 6. Water intake card with 8-segment ratio meter & +250ml double-tap lock
/// 7. Planned meal card with Review & log action
class NutritionScreen extends ConsumerStatefulWidget {
  const NutritionScreen({super.key});

  @override
  ConsumerState<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends ConsumerState<NutritionScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _isWaterUpdating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDataIfProfileReady();
    });
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

  // ─── CTA Flows ────────────────────────────────────────────────────────────

  void _openLogMeal() async {
    final profile = ref.read(profileProvider);
    final result = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (context) => FoodLogScreen(
          userGoal: profile.profile.goal.name,
          selectedDate: _selectedDate,
        ),
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã cập nhật thực đơn!')),
      );
      _loadData(forceRefresh: true);
    }
  }

  void _openScanFood() async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => LogMealSheet(selectedDate: _selectedDate),
    );
    if (result == true && mounted) {
      _loadData(forceRefresh: true);
    }
  }

  void _openMealStory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MealStoryScreen(date: _selectedDate),
      ),
    );
  }

  void _openReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const WeeklyReportScreen(),
      ),
    );
  }

  Future<void> _handleAddWater(int currentWater) async {
    if (_isWaterUpdating) return;
    setState(() => _isWaterUpdating = true);

    // Pin selected date to prevent race condition when date is changed
    final pinnedDate = _selectedDate;
    final dateStr = DateFormat('yyyy-MM-dd').format(pinnedDate);

    try {
      await ref
          .read(nutritionProvider.notifier)
          .updateWater(currentWater + 250, date: dateStr);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể cập nhật nước: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isWaterUpdating = false);
      }
    }
  }

  void _reviewAndLogMeal(Meal meal) {
    final pinnedDate = _selectedDate;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16171B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        bool isSaving = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Gợi ý bữa ăn',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF9FAFB),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Color(0xFF9CA3AF)),
                          onPressed: isSaving ? null : () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      meal.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF3F4F6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${meal.calories} kcal · ${meal.protein.toInt()}g protein · ${meal.carbs.toInt()}g carbs · ${meal.fat.toInt()}g fat',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorMessage!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF9FAFB),
                          foregroundColor: const Color(0xFF0C0D0E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                setModalState(() {
                                  isSaving = true;
                                  errorMessage = null;
                                });

                                try {
                                  final ok = await ref
                                      .read(nutritionProvider.notifier)
                                      .addMeal(
                                        date: pinnedDate,
                                        mealType: meal.mealType,
                                        foodId: meal.foodId,
                                        name: meal.name,
                                        calories: meal.calories.toDouble(),
                                        protein: meal.protein,
                                        carbs: meal.carbs,
                                        fat: meal.fat,
                                        weightGrams: meal.weightGrams > 0
                                            ? meal.weightGrams
                                            : 100,
                                      );

                                  if (ok) {
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            '✅ Đã ghi nhận bữa ăn vào nhật ký!',
                                          ),
                                        ),
                                      );
                                    }
                                  } else {
                                    setModalState(() {
                                      isSaving = false;
                                      errorMessage = 'Không thể ghi nhận bữa ăn. Vui lòng thử lại.';
                                    });
                                  }
                                } catch (e) {
                                  setModalState(() {
                                    isSaving = false;
                                    errorMessage = 'Lỗi: $e';
                                  });
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF0C0D0E),
                                ),
                              )
                            : const Text(
                                'Xác nhận & Ghi nhật ký',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final planState = ref.watch(nutritionProvider);
    final profileState = ref.watch(profileProvider);

    // Profile listener to trigger daily plan loading
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

    // Profile incomplete state
    if (!profileState.isProfileValid) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C0D0E),
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
                    decoration: const BoxDecoration(
                      color: Color(0xFF16171B),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.person_outline_rounded,
                        size: 36,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Thiếu thông tin Profile',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF9FAFB),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Vui lòng cập nhật thông tin cá nhân để tính toán mục tiêu dinh dưỡng.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF9FAFB),
                        foregroundColor: const Color(0xFF0C0D0E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Vui lòng cập nhật Profile'),
                          ),
                        );
                      },
                      child: const Text(
                        'Cập nhật ngay',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
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

    return Scaffold(
      backgroundColor: const Color(0xFF0C0D0E),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF10B981),
          backgroundColor: const Color(0xFF16171B),
          onRefresh: () async {
            _loadData(forceRefresh: true);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Header (Title + Subtitle + Report button)
                _buildHeader(),
                const SizedBox(height: 12),

                // 2. Compact Date Navigator Pill
                DateSelector(
                  selectedDate: _selectedDate,
                  onDateSelected: (date) {
                    if (_isWaterUpdating) return;
                    setState(() => _selectedDate = date);
                    _loadDataIfProfileReady();
                  },
                ),
                const SizedBox(height: 14),

                // 3-7. Content depending on planState
                planState.when(
                  data: (plan) => _buildDataView(plan, profileState),
                  loading: () => _buildLoadingView(),
                  error: (err, _) => _buildErrorView(err),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Header Section ───────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Nutrition',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF9FAFB),
                  letterSpacing: -0.6,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Fuel, log & track your day',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF9CA3AF),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),

        // Report action button
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openReport,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF16171B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF26282F)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.bar_chart_rounded,
                    size: 16,
                    color: Color(0xFF10B981),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Report',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9CA3AF),
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

  // ─── Populated Content ────────────────────────────────────────────────────

  Widget _buildDataView(NutritionPlan? plan, ProfileState profile) {
    final bool hasValidWaterTarget = profile.isProfileValid && profile.waterTargetMl > 0;
    final int waterTarget = hasValidWaterTarget ? profile.waterTargetMl : 0;

    final effectivePlan = plan ??
        NutritionPlan(
          date: DateFormat('yyyy-MM-dd').format(_selectedDate),
          meals: [],
          entries: [],
          currentWater: 0,
          targetWater: waterTarget,
        );

    final entries = effectivePlan.entries;
    final meals = effectivePlan.meals;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 3. Today's Intake Card (Intake headline + progress + macros)
        NutritionSummary(plan: effectivePlan, profile: profile),
        const SizedBox(height: 12),

        // 4. Fast Actions (Log meal + Scan food)
        _buildFastActions(),
        const SizedBox(height: 18),

        // 5. Logged Meals Section
        _buildLoggedMealsSection(entries, effectivePlan.totalCaloriesConsumed),
        const SizedBox(height: 16),

        // 6. Water Intake Card
        NutritionWaterCard(
          currentWater: effectivePlan.currentWater,
          targetWater: waterTarget,
          hasTarget: hasValidWaterTarget,
          isUpdating: _isWaterUpdating,
          onAddWater: () => _handleAddWater(effectivePlan.currentWater),
        ),
        const SizedBox(height: 16),

        // 7. Planned Meal Card
        _buildPlannedMealSection(
          meals,
          profile,
          profile.targetCalories - effectivePlan.totalCaloriesConsumed,
          effectivePlan.totalCaloriesConsumed,
        ),
      ],
    );
  }

  // ─── Fast Actions (Log meal & Scan food) ──────────────────────────────────

  Widget _buildFastActions() {
    return Row(
      children: [
        // Primary CTA: Log meal
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openLogMeal,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.add,
                        size: 20,
                        color: Color(0xFF0C0D0E),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Log meal',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0C0D0E),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Secondary CTA: Scan food (AI photo meal logging)
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openScanFood,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF16171B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF26282F)),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.camera_alt_outlined,
                        size: 19,
                        color: Color(0xFF10B981),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Scan food',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF3F4F6),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Logged Meals Section ─────────────────────────────────────────────────

  Widget _buildLoggedMealsSection(List<NutritionLogEntry> entries, int totalCaloriesConsumed) {
    final bool hasAggregateMismatch = totalCaloriesConsumed > 0 && entries.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(
              child: Text(
                'LOGGED MEALS',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openMealStory,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'Meal Story',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF10B981),
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: Color(0xFF10B981),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (entries.isEmpty)
          if (hasAggregateMismatch)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF16171B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.sync_problem_rounded,
                    size: 28,
                    color: Color(0xFFF59E0B),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Data needs refreshing',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF3F4F6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Logged entries do not match total consumed intake',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _loadData(forceRefresh: true),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF212328),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF26282F)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh,
                              size: 14,
                              color: Color(0xFF10B981),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Refresh',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF16171B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF26282F)),
              ),
              child: Column(
                children: const [
                  Icon(
                    Icons.restaurant_outlined,
                    size: 28,
                    color: Color(0xFF6B7280),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Chưa có bữa ăn nào được ghi hôm nay',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              return NutritionLoggedMealCard(entry: entries[index]);
            },
          ),
      ],
    );
  }

  // ─── Planned Meal Section ─────────────────────────────────────────────────

  Widget _buildPlannedMealSection(List<Meal> meals, ProfileState profile, int remainCal, int consumedCal) {
    if (meals.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF16171B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF26282F)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'MEAL PLAN',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9CA3AF),
                    letterSpacing: 1.2,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF212328),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF26282F)),
                  ),
                  child: const Text(
                    'CHƯA CÓ KẾ HOẠCH',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9CA3AF),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tạo kế hoạch ăn uống với AI',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => PlanGeneratorSheet(
                        remainingCalories: remainCal > 0 ? remainCal : 0,
                        consumedCalories: consumedCal,
                        userGoal: profile.profile.goal.name,
                        selectedDate: _selectedDate,
                      ),
                    );
                  },
                  child: const Text(
                    'Tạo kế hoạch',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Pick first planned meal
    final nextMeal = meals.first;
    return PlannedMealCard(
      meal: nextMeal,
      onReview: () => _reviewAndLogMeal(nextMeal),
    );
  }

  // ─── Loading Skeleton ─────────────────────────────────────────────────────

  Widget _buildLoadingView() {
    return Column(
      children: [
        _buildSkeletonBox(height: 170),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildSkeletonBox(height: 48)),
            const SizedBox(width: 10),
            Expanded(child: _buildSkeletonBox(height: 48)),
          ],
        ),
        const SizedBox(height: 18),
        _buildSkeletonBox(height: 80),
        const SizedBox(height: 16),
        _buildSkeletonBox(height: 100),
        const SizedBox(height: 16),
        _buildSkeletonBox(height: 90),
      ],
    );
  }

  Widget _buildSkeletonBox({required double height}) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F)),
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF26282F),
          ),
        ),
      ),
    );
  }

  // ─── Error View ───────────────────────────────────────────────────────────

  Widget _buildErrorView(Object error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF26282F)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 36,
            color: Color(0xFF9CA3AF),
          ),
          const SizedBox(height: 12),
          const Text(
            'Không thể tải dữ liệu dinh dưỡng',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF3F4F6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            error.toString(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF212328),
              foregroundColor: const Color(0xFFF3F4F6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFF26282F)),
              ),
            ),
            onPressed: () => _loadData(forceRefresh: true),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }
}
