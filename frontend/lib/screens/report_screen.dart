// [File: lib/screens/report_screen.dart]
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/report/presentation/providers/report_provider.dart';
import '../features/report/domain/entities/weekly_report_entity.dart';
import '../features/report/presentation/widgets/report_header.dart';
import '../features/report/presentation/widgets/report_week_navigator.dart';
import '../features/report/presentation/widgets/report_tab_bar.dart';
import '../features/report/presentation/widgets/report_weekly_summary_card.dart';
import '../features/report/presentation/widgets/calories_consumed_chart_card.dart';
import '../features/report/presentation/widgets/protein_intake_chart_card.dart';
import '../features/report/presentation/widgets/calories_burned_chart_card.dart';
import '../features/report/presentation/widgets/report_takeaway_card.dart';
import '../features/report/presentation/widgets/daily_breakdown_sheet.dart';
import '../features/report/presentation/widgets/report_nutrition_tab.dart';
import '../features/report/presentation/widgets/report_activity_tab.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  late DateTime _selectedDate;
  int _selectedTab = 0; // 0: Overview, 1: Nutrition, 2: Activity
  int _selectedDayIndex = 0; // 0: Mo .. 6: Su

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _selectedDayIndex = now.weekday - 1; // 0 = Mon, 6 = Sun
  }

  DateTime get _weekMonday {
    final monday = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  void _onPreviousWeek() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 7));
      _selectedDayIndex = 0;
    });
  }

  void _onNextWeek() {
    final nextWeek = _selectedDate.add(const Duration(days: 7));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!nextWeek.isAfter(today.add(const Duration(days: 6)))) {
      setState(() {
        _selectedDate = nextWeek;
        final monday = _weekMonday;
        final sunday = monday.add(const Duration(days: 6));
        if (!today.isBefore(monday) && !today.isAfter(sunday)) {
          _selectedDayIndex = today.weekday - 1;
        } else {
          _selectedDayIndex = 0;
        }
      });
    }
  }

  Future<void> _onPickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF10B981),
              onPrimary: Color(0xFF0C0D0E),
              surface: Color(0xFF16171A),
              onSurface: Color(0xFFF3F4F6),
            ),
            dialogBackgroundColor: const Color(0xFF16171A),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final monday = _weekMonday;
        final sunday = monday.add(const Duration(days: 6));
        if (!today.isBefore(monday) && !today.isAfter(sunday)) {
          _selectedDayIndex = today.weekday - 1;
        } else {
          _selectedDayIndex = picked.weekday - 1;
        }
      });
    }
  }

  bool get _canGoNext {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = _weekMonday;
    final nextMonday = monday.add(const Duration(days: 7));
    return !nextMonday.isAfter(today);
  }

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(weeklyReportProvider(_selectedDate));

    return Scaffold(
      backgroundColor: const Color(0xFF0C0D0E),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Compact Header
                ReportHeader(
                  onBack: () => Navigator.of(context).pop(),
                ),

                // 2. Week Navigation
                ReportWeekNavigator(
                  weekMonday: _weekMonday,
                  onPrevious: _onPreviousWeek,
                  onNext: _canGoNext ? _onNextWeek : null,
                  onPickDate: _onPickDate,
                ),

                // 3. Segmented 3-Tab Switcher
                ReportTabBar(
                  selectedIndex: _selectedTab,
                  onTabSelected: (idx) {
                    setState(() => _selectedTab = idx);
                  },
                ),
                const SizedBox(height: 8),

                // Main Tab Content
                Expanded(
                  child: reportAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF10B981),
                        strokeWidth: 2.5,
                      ),
                    ),
                    error: (err, stack) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.cloud_off_rounded,
                              size: 36,
                              color: Color(0xFF71717A),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Could not load weekly report data.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFFA1A1AA),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF26282F),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () {
                                ref.invalidate(weeklyReportProvider(_selectedDate));
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    data: (report) {
                      return RefreshIndicator(
                        color: const Color(0xFF10B981),
                        backgroundColor: const Color(0xFF16171A),
                        onRefresh: () async {
                          ref.invalidate(weeklyReportProvider(_selectedDate));
                        },
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Content matching active tab
                              if (_selectedTab == 0) ...[
                                _buildOverviewTab(report),
                              ] else if (_selectedTab == 1) ...[
                                ReportNutritionTab(
                                  report: report,
                                  selectedIndex: _selectedDayIndex,
                                  onSelectIndex: (idx) {
                                    setState(() => _selectedDayIndex = idx);
                                  },
                                ),
                              ] else ...[
                                ReportActivityTab(
                                  report: report,
                                  selectedIndex: _selectedDayIndex,
                                  onSelectIndex: (idx) {
                                    setState(() => _selectedDayIndex = idx);
                                  },
                                ),
                              ],
                              const SizedBox(height: 36),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab(WeeklyReportEntity report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 4. Weekly Summary ("Your week, at a glance")
        ReportWeeklySummaryCard(
          daysLogged: report.daysLogged,
          avgProtein: report.avgProtein,
          targetProtein: report.targetProtein,
          activeDays: report.activeDays,
          targetActiveDays: 4,
          avgRpe: report.workoutSessions.isNotEmpty ? 8.2 : null,
        ),
        const SizedBox(height: 16),

        // 5. Calories Consumed Card (White/Gray Bar Chart)
        CaloriesConsumedChartCard(
          days: report.days,
          avgCalories: report.avgCaloriesIn,
          targetCalories: report.targetCalories,
          selectedIndex: _selectedDayIndex,
          onSelectIndex: (idx) {
            setState(() => _selectedDayIndex = idx);
          },
        ),
        const SizedBox(height: 16),

        // 6. Protein Intake Card (Emerald Line Chart)
        ProteinIntakeChartCard(
          days: report.days,
          avgProtein: report.avgProtein,
          targetProtein: report.targetProtein,
          selectedIndex: _selectedDayIndex,
          onSelectIndex: (idx) {
            setState(() => _selectedDayIndex = idx);
          },
        ),
        const SizedBox(height: 16),

        // 7. Calories Burned Card (Compact Amber Bar Chart)
        CaloriesBurnedChartCard(
          days: report.days,
          avgCaloriesBurned: report.avgCaloriesBurned,
          targetBurned: report.targetBurned,
          selectedIndex: _selectedDayIndex,
          onSelectIndex: (idx) {
            setState(() => _selectedDayIndex = idx);
          },
        ),
        const SizedBox(height: 16),

        // 8. Weekly Takeaway Card
        if (report.takeaway != null && report.takeaway!.isNotEmpty) ...[
          ReportTakeawayCard(takeaway: report.takeaway!),
          const SizedBox(height: 12),
        ],

        // 9. View Daily Breakdown Action
        Center(
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD1D5DB),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              DailyBreakdownSheet.show(
                context,
                days: report.days,
                targetCalories: report.targetCalories,
                targetProtein: report.targetProtein,
              );
            },
            child: const Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'View daily breakdown',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 6),
                Icon(Icons.arrow_forward_rounded, size: 14),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
