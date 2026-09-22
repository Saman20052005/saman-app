// [File: lib/screens/report_screen.dart]
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../features/report/presentation/providers/report_provider.dart';
import '../features/report/domain/entities/weekly_report_entity.dart';
import '../providers/profile_provider.dart';
import '../models/report_model.dart';
import '../config/app_theme.dart';
import '../widgets/nutrition_primitives.dart';
import '../widgets/trend_chart_card.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  DateTime _selectedDate = DateTime.now();
  int _selectedIndex = 0; // Để quản lý Filter Tab

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<AppThemeExtension>()!;
    final profileState = ref.watch(profileProvider);
    final targetCalories = profileState.targetCalories;
    final targetProtein = profileState.targetProtein;
    final targetBurned =
        profileState.targetBurned > 0 ? profileState.targetBurned : 300;

    final reportAsync = ref.watch(weeklyReportProvider(_selectedDate));

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.bgColor,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report', style: theme.textTheme.headlineSmall),
            Text(
              "Week of ${DateFormat('MMM dd').format(_selectedDate.subtract(const Duration(days: 6)))} - ${DateFormat('MMM dd').format(_selectedDate)}",
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.inkMuted,
              ),
            )
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: AppSpacing.lg),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: tokens.hairline),
            ),
            child: IconButton(
              icon: const Icon(Icons.calendar_today_outlined, size: 20),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2023),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _selectedDate = picked);
              },
            ),
          )
        ],
      ),
      body: reportAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: colors.primary),
        ),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'We could not load this report.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.inkMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(weeklyReportProvider(_selectedDate)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (report) {
          final consumedData = report.days
              .map((e) => DailyReportItem(
                    date: e.date.toIso8601String(),
                    calories: e.caloriesIn.toInt(),
                    protein: e.protein,
                    water: 0,
                  ))
              .toList();

          final burnedData = report.days
              .map((e) => DailyReportItem(
                    date: e.date.toIso8601String(),
                    calories: e.caloriesBurned.toInt(),
                    protein: 0,
                    water: 0,
                  ))
              .toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. FILTER TABS (Tăng tính tương tác)
                _buildFilterTabs(),
                const SizedBox(height: AppSpacing.lg),

                // 2. SUMMARY CARD (Design mới gọn hơn)
                _buildModernSummaryCard(report, targetCalories),
                const SizedBox(height: AppSpacing.xl),

                const NutritionSectionHeader(label: 'Weekly trends'),
                const SizedBox(height: AppSpacing.md),

                // 3. CHARTS AREA
                // Logic hiển thị theo Tab
                if (_selectedIndex == 0 || _selectedIndex == 1) ...[
                  TrendChartCard(
                    title: "Calories Consumed",
                    data: consumedData,
                    targetValue: targetCalories.toDouble(),
                    baseColor: tokens.warning,
                    unit: "kcal",
                  ),
                ],

                if (_selectedIndex == 0 || _selectedIndex == 2) ...[
                  TrendChartCard(
                    title: "Calories Burned",
                    data: burnedData,
                    targetValue: targetBurned.toDouble(),
                    baseColor: colors.error,
                    unit: "kcal",
                  ),
                ],

                if (_selectedIndex == 0 || _selectedIndex == 1) ...[
                  TrendChartCard(
                    title: "Protein Intake",
                    data: consumedData,
                    targetValue: targetProtein.toDouble(),
                    baseColor: colors.primary,
                    unit: "g",
                  ),
                ],

                const SizedBox(height: AppSpacing.xxxl),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterTabs() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<AppThemeExtension>()!;
    final tabs = ["Overview", "Nutrition", "Activity"];
    return Row(
      children: tabs.asMap().entries.map((e) {
        final isActive = _selectedIndex == e.key;
        return GestureDetector(
          onTap: () => setState(() => _selectedIndex = e.key),
          child: Container(
            margin: const EdgeInsets.only(right: AppSpacing.md),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isActive ? colors.primary : colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: isActive ? null : Border.all(color: tokens.hairline),
            ),
            child: Text(
              e.value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isActive ? colors.onPrimary : colors.onSurface,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildModernSummaryCard(WeeklyReportEntity report, int dailyTarget) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<AppThemeExtension>()!;
    // Tính toán đơn giản
    final avg = report.avgCaloriesIn.toInt();
    final isGood = avg <= dailyTarget + 100 && avg >= dailyTarget - 200;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Weekly Average', style: tokens.labelCaps),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: isGood
                      ? colors.primary.withOpacity(0.12)
                      : tokens.warning.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  isGood ? 'On Track' : 'Needs Attention',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isGood ? colors.primary : tokens.warning,
                  ),
                ),
              )
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("$avg", style: tokens.heroNumeric),
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'kcal/day',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.inkMuted,
                  ),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }
}
