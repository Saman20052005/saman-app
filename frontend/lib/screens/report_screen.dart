// [File: lib/screens/report_screen.dart]
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../features/report/presentation/providers/report_provider.dart';
import '../features/report/domain/entities/weekly_report_entity.dart';
import '../providers/profile_provider.dart';
import '../models/report_model.dart';
// IMPORT WIDGET MỚI
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
    final profileState = ref.watch(profileProvider);
    final targetCalories = profileState.targetCalories;
    final targetProtein = profileState.targetProtein;
    final targetBurned =
        profileState.targetBurned > 0 ? profileState.targetBurned : 300;

    final reportAsync = ref.watch(weeklyReportProvider(_selectedDate));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), // Nền xám nhạt hiện đại
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Report",
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(
              "Week of ${DateFormat('MMM dd').format(_selectedDate.subtract(const Duration(days: 6)))} - ${DateFormat('MMM dd').format(_selectedDate)}",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            )
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200)),
            child: IconButton(
              icon: const Icon(Icons.calendar_today_outlined,
                  size: 20, color: Colors.black87),
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text("Error: $err")),
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. FILTER TABS (Tăng tính tương tác)
                _buildFilterTabs(),
                const SizedBox(height: 20),

                // 2. SUMMARY CARD (Design mới gọn hơn)
                _buildModernSummaryCard(report, targetCalories),
                const SizedBox(height: 24),

                // 3. CHARTS AREA
                // Logic hiển thị theo Tab
                if (_selectedIndex == 0 || _selectedIndex == 1) ...[
                  TrendChartCard(
                    title: "Calories Consumed",
                    data: consumedData,
                    targetValue: targetCalories.toDouble(),
                    baseColor: Colors.orange,
                    unit: "kcal",
                  ),
                ],

                if (_selectedIndex == 0 || _selectedIndex == 2) ...[
                  TrendChartCard(
                    title: "Calories Burned",
                    data: burnedData,
                    targetValue: targetBurned.toDouble(),
                    baseColor: Colors.redAccent,
                    unit: "kcal",
                  ),
                ],

                if (_selectedIndex == 0 || _selectedIndex == 1) ...[
                  TrendChartCard(
                    title: "Protein Intake",
                    data: consumedData,
                    targetValue: targetProtein.toDouble(),
                    baseColor: Colors.teal,
                    unit: "g",
                  ),
                ],

                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterTabs() {
    final tabs = ["Overview", "Nutrition", "Activity"];
    return Row(
      children: tabs.asMap().entries.map((e) {
        final isActive = _selectedIndex == e.key;
        return GestureDetector(
          onTap: () => setState(() => _selectedIndex = e.key),
          child: Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isActive ? Colors.black87 : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: isActive ? null : Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              e.value,
              style: TextStyle(
                  color: isActive ? Colors.white : Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildModernSummaryCard(WeeklyReportEntity report, int dailyTarget) {
    // Tính toán đơn giản
    final avg = report.avgCaloriesIn.toInt();
    final isGood = avg <= dailyTarget + 100 && avg >= dailyTarget - 200;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF4A90E2), const Color(0xFF007AFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF007AFF).withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Weekly Average",
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(isGood ? "On Track 👍" : "Needs Attention ⚠️",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              )
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("$avg",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      height: 1.0)),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text("kcal/day",
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
              )
            ],
          ),
        ],
      ),
    );
  }
}
