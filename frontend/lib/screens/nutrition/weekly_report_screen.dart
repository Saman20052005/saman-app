import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../../models/nutrition_model.dart';
import '../../../services/nutrition_service.dart';

// ── COLOR & DESIGN PALETTE (Adaptive Light / Dark) ──────────────────────────
class _WeeklyReportPalette {
  const _WeeklyReportPalette({
    required this.isDark,
    required this.bgColor,
    required this.cardColor,
    required this.cardBorder,
    required this.innerPill,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDim,
    required this.brandEmerald,
    required this.proteinAccent,
    required this.carbsAccent,
    required this.fatAccent,
    required this.trackBg,
    required this.gridLine,
    required this.baseLine,
    required this.unloggedDash,
    required this.selectedHighlight,
  });

  final bool isDark;
  final Color bgColor;
  final Color cardColor;
  final Color cardBorder;
  final Color innerPill;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDim;
  final Color brandEmerald;
  final Color proteinAccent;
  final Color carbsAccent;
  final Color fatAccent;
  final Color trackBg;
  final Color gridLine;
  final Color baseLine;
  final Color unloggedDash;
  final Color selectedHighlight;

  static const _WeeklyReportPalette dark = _WeeklyReportPalette(
    isDark: true,
    bgColor: Color(0xFF0F0F0F),
    cardColor: Color(0xFF191B1D),
    cardBorder: Color(0xFF272A30),
    innerPill: Color(0xFF0F0F0F),
    textPrimary: Color(0xFFF4F4F5),
    textSecondary: Color(0xFF9CA3AF),
    textMuted: Color(0xFF71717A),
    textDim: Color(0xFF52525B),
    brandEmerald: Color(0xFF10B981),
    proteinAccent: Color(0xFF60A5FA),
    carbsAccent: Color(0xFFFBBF24),
    fatAccent: Color(0xFFC084FC),
    trackBg: Color(0xFF26292E),
    gridLine: Color(0xFF222429),
    baseLine: Color(0xFF2E3138),
    unloggedDash: Color(0xFF3F3F46),
    selectedHighlight: Color(0x1A10B981),
  );

  static const _WeeklyReportPalette light = _WeeklyReportPalette(
    isDark: false,
    bgColor: Color(0xFFF8FAFC),
    cardColor: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE2E8F0),
    innerPill: Color(0xFFF1F5F9),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF64748B),
    textDim: Color(0xFF94A3B8),
    brandEmerald: Color(0xFF059669),
    proteinAccent: Color(0xFF2563EB),
    carbsAccent: Color(0xFFD97706),
    fatAccent: Color(0xFF9333EA),
    trackBg: Color(0xFFE2E8F0),
    gridLine: Color(0xFFE2E8F0),
    baseLine: Color(0xFFCBD5E1),
    unloggedDash: Color(0xFFCBD5E1),
    selectedHighlight: Color(0x1A059669),
  );

  static _WeeklyReportPalette of(BuildContext context) {
    return SamanPalette.of(context).isDark ? dark : light;
  }
}

class WeeklyReportScreen extends StatefulWidget {
  final NutritionService? service;
  final DateTime? initialDate;

  const WeeklyReportScreen({
    super.key,
    this.service,
    this.initialDate,
  });

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  late final NutritionService _service;
  late DateTime _selectedMonday;
  WeeklyReport? _report;
  bool _loading = true;
  String? _error;
  int _selectedDayIndex = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? NutritionService();
    final anchor = widget.initialDate ?? _getVietnamNow();
    _selectedMonday = _findMonday(anchor);
    _loadReport();
  }

  static DateTime _getVietnamNow() {
    return DateTime.now().toUtc().add(const Duration(hours: 7));
  }

  static DateTime _findMonday(DateTime date) {
    return DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - 1));
  }

  Future<void> _loadReport() async {
    final startDate = _formatYyyyMmDd(_selectedMonday);

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _service.getWeeklyReport(startDate);
      if (!mounted) return;
      final report = WeeklyReport.fromJson(response);
      setState(() {
        _report = report;
        _loading = false;
        _error = null;

        // Auto-select initialDate/today if present in this week, otherwise first logged day or day 0
        final anchor = widget.initialDate ?? _getVietnamNow();
        final anchorStr = _formatYyyyMmDd(anchor);
        final anchorIdx = report.daily.indexWhere((d) => d.date == anchorStr);
        if (anchorIdx != -1) {
          _selectedDayIndex = anchorIdx;
        } else {
          final firstLogged = report.daily.indexWhere((d) => d.hasData);
          _selectedDayIndex = firstLogged != -1 ? firstLogged : 0;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onPreviousWeek() {
    setState(() {
      _selectedMonday = _selectedMonday.subtract(const Duration(days: 7));
    });
    _loadReport();
  }

  void _onNextWeek() {
    setState(() {
      _selectedMonday = _selectedMonday.add(const Duration(days: 7));
    });
    _loadReport();
  }

  void _onSelectDay(int index) {
    if (index >= 0 && index < (_report?.daily.length ?? 0)) {
      setState(() {
        _selectedDayIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _WeeklyReportPalette.of(context);
    final weekNumber = _getIsoWeekNumber(_selectedMonday);

    return Scaffold(
      backgroundColor: p.bgColor,
      body: SafeArea(
        child: _loading && _report == null
            ? Center(
                child: CircularProgressIndicator(color: p.brandEmerald),
              )
            : _error != null && _report == null
                ? _buildErrorView(p)
                : RefreshIndicator(
                    color: p.brandEmerald,
                    backgroundColor: p.cardColor,
                    onRefresh: _loadReport,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Header(
                                weekNumber: weekNumber,
                                onBack: () => Navigator.maybePop(context),
                              ),
                              const SizedBox(height: 16),
                              _WeekSelector(
                                start: _selectedMonday,
                                end: _selectedMonday.add(const Duration(days: 6)),
                                daysLogged: _report?.daysLogged ?? 0,
                                onPrevious: _onPreviousWeek,
                                onNext: _onNextWeek,
                              ),
                              const SizedBox(height: 16),
                              if (_report != null) ...[
                                _DailyCalorieChart(
                                  report: _report!,
                                  selectedDayIndex: _selectedDayIndex,
                                  onSelectDay: _onSelectDay,
                                ),
                                const SizedBox(height: 16),
                                _WeeklyMacros(
                                  totals: _report!.weeklyTotals,
                                  targets: _report!.macroTargets,
                                ),
                                const SizedBox(height: 16),
                                _SummaryMetrics(
                                  avgCalories: _report!.avgCalories,
                                  targetCalories:
                                      _report!.macroTargets.calories.toDouble(),
                                  daysLogged: _report!.daysLogged,
                                ),
                                const SizedBox(height: 20),
                                _DailyBreakdown(
                                  daily: _report!.daily,
                                  selectedDayIndex: _selectedDayIndex,
                                  onSelectDay: _onSelectDay,
                                ),
                                const SizedBox(height: 32),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _buildErrorView(_WeeklyReportPalette p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: p.textSecondary,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'Không thể tải báo cáo tuần.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Vui lòng kiểm tra kết nối mạng và thử lại.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: p.cardColor,
                foregroundColor: p.brandEmerald,
                side: BorderSide(color: p.cardBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              child: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── MODULE 1: HEADER ─────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int weekNumber;
  final VoidCallback onBack;

  const _Header({
    required this.weekNumber,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final p = _WeeklyReportPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                child: Icon(
                  Icons.arrow_back_ios_new,
                  color: p.textPrimary,
                  size: 18,
                ),
              ),
            ),
            Text(
              'Tuần $weekNumber',
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Báo cáo tuần',
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Nhìn lại dinh dưỡng của bạn',
          style: TextStyle(
            color: p.textSecondary,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

// ── MODULE 1B: WEEK SELECTOR ─────────────────────────────────────────────────

class _WeekSelector extends StatelessWidget {
  final DateTime start, end;
  final int daysLogged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _WeekSelector({
    required this.start,
    required this.end,
    required this.daysLogged,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final p = _WeeklyReportPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: p.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.cardBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Tooltip(
                  message: 'Tuần trước',
                  child: InkWell(
                    onTap: onPrevious,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.chevron_left,
                        color: p.textSecondary,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _formatWeekRange(start, end),
                          maxLines: 1,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _formatYearText(start, end),
                          maxLines: 1,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Tuần sau',
                  child: InkWell(
                    onTap: onNext,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.chevron_right,
                        color: p.textSecondary,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: p.innerPill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: p.cardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: p.brandEmerald,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '$daysLogged/7 ngày đã ghi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── MODULE 2: DAILY CALORIE CHART ────────────────────────────────────────────

class _DailyCalorieChart extends StatelessWidget {
  final WeeklyReport report;
  final int selectedDayIndex;
  final ValueChanged<int> onSelectDay;

  const _DailyCalorieChart({
    required this.report,
    required this.selectedDayIndex,
    required this.onSelectDay,
  });

  @override
  Widget build(BuildContext context) {
    final p = _WeeklyReportPalette.of(context);
    const daysAbbr = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final target = report.macroTargets.calories.toDouble();
    final maxCal = report.daily.fold<double>(
      0,
      (prev, e) => math.max(prev, e.calories),
    );

    final double maxY;
    if (target > 0 && maxCal > 0) {
      maxY = math.max(target, maxCal) * 1.2;
    } else if (target > 0) {
      maxY = target * 1.2;
    } else if (maxCal > 0) {
      maxY = maxCal * 1.2;
    } else {
      maxY = 2500;
    }

    final selectedDay = (selectedDayIndex >= 0 && selectedDayIndex < report.daily.length)
        ? report.daily[selectedDayIndex]
        : (report.daily.isNotEmpty ? report.daily.first : null);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Năng lượng theo ngày',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Lượng đã ghi so với mục tiêu',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  target > 0
                      ? 'Mục tiêu · ${_formatNumber(target)} kcal'
                      : 'Chưa có mục tiêu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Chart Canvas Simulation
          SizedBox(
            height: 150,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const yAxisWidth = 32.0;
                final chartWidth = constraints.maxWidth - yAxisWidth;
                final targetRatio = target > 0 ? (target / maxY).clamp(0.0, 1.0) : 0.0;
                final targetYPos = (1.0 - targetRatio) * 150;

                return Stack(
                  children: [
                    // Grid lines & labels
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildGridLine(p, '${maxY.round()}', isBaseline: false),
                        _buildGridLine(p, '${(maxY * 0.66).round()}', isBaseline: false),
                        _buildGridLine(p, '${(maxY * 0.33).round()}', isBaseline: false),
                        _buildGridLine(p, '0', isBaseline: true),
                      ],
                    ),

                    // Target dashed line (if target > 0)
                    if (target > 0)
                      Positioned(
                        top: targetYPos,
                        left: 0,
                        right: 0,
                        child: Row(
                          children: [
                            SizedBox(
                              width: yAxisWidth,
                              child: Text(
                                '${target.round()}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: p.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: CustomPaint(
                                painter: _DashedHorizontalLinePainter(
                                  color: p.textDim,
                                  dashWidth: 4,
                                  dashSpace: 4,
                                ),
                                child: const SizedBox(height: 1),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Columns overlay
                    Positioned(
                      left: yAxisWidth + 8,
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(report.daily.length, (idx) {
                          final day = report.daily[idx];
                          final isSelected = idx == selectedDayIndex;
                          final hasData = day.hasData;
                          final calRatio = maxY > 0 ? (day.calories / maxY).clamp(0.0, 1.0) : 0.0;
                          final barHeight = (calRatio * 148).clamp(0.0, 148.0);

                          return Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onSelectDay(idx),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (hasData && day.calories > 0)
                                    Container(
                                      width: math.min(20.0, chartWidth / 10),
                                      height: math.max(6.0, barHeight),
                                      decoration: BoxDecoration(
                                        color: p.brandEmerald,
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(3),
                                        ),
                                        boxShadow: isSelected
                                            ? [
                                                BoxShadow(
                                                  color: p.brandEmerald.withOpacity(0.38),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, -2),
                                                ),
                                              ]
                                            : null,
                                      ),
                                    )
                                  else if (hasData && day.calories == 0)
                                    Container(
                                      width: 6,
                                      height: 3,
                                      margin: const EdgeInsets.only(bottom: 1),
                                      decoration: BoxDecoration(
                                        color: p.brandEmerald,
                                        borderRadius: BorderRadius.circular(1.5),
                                      ),
                                    )
                                  else
                                    Container(
                                      width: 8,
                                      height: 2,
                                      margin: const EdgeInsets.only(bottom: 1),
                                      decoration: BoxDecoration(
                                        color: p.unloggedDash,
                                        borderRadius: BorderRadius.circular(1),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // X-Axis Day Labels
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(report.daily.length, (idx) {
                final isSelected = idx == selectedDayIndex;
                final label = idx < daysAbbr.length ? daysAbbr[idx] : 'T${idx + 2}';
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelectDay(idx),
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isSelected ? p.brandEmerald : p.textSecondary,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // Selected Day Footer
          const SizedBox(height: 12),
          Divider(height: 1, color: p.cardBorder),
          const SizedBox(height: 12),
          if (selectedDay != null) _buildSelectedDayDetails(p, selectedDay),
        ],
      ),
    );
  }

  Widget _buildGridLine(_WeeklyReportPalette p, String label, {required bool isBaseline}) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: p.textMuted,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            color: isBaseline ? p.baseLine : p.gridLine,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedDayDetails(_WeeklyReportPalette p, DailyNutrition day) {
    final parsedDate = DateTime.tryParse(day.date);
    final dayLabel = parsedDate != null ? _formatSelectedDay(parsedDate) : day.date;
    final hasData = day.hasData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: hasData ? p.brandEmerald : p.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dayLabel,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              hasData ? '${_formatNumber(day.calories)} kcal' : '—',
              style: TextStyle(
                color: hasData ? p.brandEmerald : p.textMuted,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: hasData
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildMacroTag(p, 'Đạm', '${day.protein.round()} g', p.proteinAccent),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('·', style: TextStyle(color: p.textSecondary)),
                      ),
                      _buildMacroTag(p, 'Carb', '${day.carbs.round()} g', p.carbsAccent),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('·', style: TextStyle(color: p.textSecondary)),
                      ),
                      _buildMacroTag(p, 'Béo', '${day.fat.round()} g', p.fatAccent),
                    ],
                  ),
                )
              : Text(
                  'Chưa có dữ liệu nhật ký cho ngày này',
                  style: TextStyle(
                    color: p.textMuted,
                    fontSize: 12,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMacroTag(_WeeklyReportPalette p, String name, String value, Color dotColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$name $value',
          style: TextStyle(
            color: p.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

// ── CUSTOM PAINTER: DASHED LINE ──────────────────────────────────────────────

class _DashedHorizontalLinePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double dashSpace;

  const _DashedHorizontalLinePainter({
    required this.color,
    this.dashWidth = 4,
    this.dashSpace = 3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(math.min(startX + dashWidth, size.width), 0),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedHorizontalLinePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.dashWidth != dashWidth ||
        oldDelegate.dashSpace != dashSpace;
  }
}

// ── MODULE 3: WEEKLY MACROS ──────────────────────────────────────────────────

class _WeeklyMacros extends StatelessWidget {
  final MacroTargets totals;
  final MacroTargets targets;

  const _WeeklyMacros({
    required this.totals,
    required this.targets,
  });

  @override
  Widget build(BuildContext context) {
    final p = _WeeklyReportPalette.of(context);
    final targetProteinWeekly = targets.protein * 7;
    final targetCarbsWeekly = targets.carbs * 7;
    final targetFatWeekly = targets.fat * 7;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Macro trong tuần',
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 20),
          _buildMacroRow(
            p: p,
            label: 'Đạm',
            consumed: totals.protein,
            target: targetProteinWeekly,
            color: p.proteinAccent,
          ),
          const SizedBox(height: 18),
          _buildMacroRow(
            p: p,
            label: 'Carb',
            consumed: totals.carbs,
            target: targetCarbsWeekly,
            color: p.carbsAccent,
          ),
          const SizedBox(height: 18),
          _buildMacroRow(
            p: p,
            label: 'Béo',
            consumed: totals.fat,
            target: targetFatWeekly,
            color: p.fatAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildMacroRow({
    required _WeeklyReportPalette p,
    required String label,
    required double consumed,
    required double target,
    required Color color,
  }) {
    final progress = target > 0 ? (consumed / target).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_formatNumber(consumed)} g',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  target > 0
                      ? 'Mục tiêu ${_formatNumber(target)} g'
                      : 'Chưa có mục tiêu',
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 4,
          decoration: BoxDecoration(
            color: p.trackBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: constraints.maxWidth * progress,
                  height: 4,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── MODULE 4: SUMMARY METRICS ────────────────────────────────────────────────

class _SummaryMetrics extends StatelessWidget {
  final double avgCalories;
  final double targetCalories;
  final int daysLogged;

  const _SummaryMetrics({
    required this.avgCalories,
    required this.targetCalories,
    required this.daysLogged,
  });

  @override
  Widget build(BuildContext context) {
    final p = _WeeklyReportPalette.of(context);
    final hasTarget = targetCalories > 0;
    final diff = avgCalories - targetCalories;

    final String diffFormatted;
    if (!hasTarget) {
      diffFormatted = '—';
    } else {
      final sign = diff > 0 ? '+' : '';
      diffFormatted = '$sign${_formatNumber(diff)}';
    }

    final String noticeText;
    if (daysLogged == 0) {
      noticeText = 'Chưa có nhật ký nào trong tuần này. Hãy ghi bữa ăn để xem báo cáo dinh dưỡng.';
    } else if (daysLogged < 7) {
      noticeText = 'Bạn mới ghi $daysLogged/7 ngày. Báo cáo chưa phản ánh đầy đủ lượng ăn thực tế.';
    } else {
      noticeText = 'Dữ liệu tuần đã được ghi nhận đầy đủ 7/7 ngày.';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trung bình / ngày',
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _formatNumber(avgCalories),
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'kcal',
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'So với mục tiêu',
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            diffFormatted,
                            style: TextStyle(
                              color: p.textSecondary, // Calm neutral color as mandated by PRD
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.5,
                            ),
                          ),
                          if (hasTarget) ...[
                            const SizedBox(width: 4),
                            Text(
                              'kcal',
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: p.cardBorder),
          const SizedBox(height: 12),
          Text(
            'Trung bình tính trên 7 ngày của tuần.',
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.innerPill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.cardBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: p.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    noticeText,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── MODULE 5: DAILY BREAKDOWN ────────────────────────────────────────────────

class _DailyBreakdown extends StatelessWidget {
  final List<DailyNutrition> daily;
  final int selectedDayIndex;
  final ValueChanged<int> onSelectDay;

  const _DailyBreakdown({
    required this.daily,
    required this.selectedDayIndex,
    required this.onSelectDay,
  });

  @override
  Widget build(BuildContext context) {
    final p = _WeeklyReportPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Chi tiết từng ngày',
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: p.cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.cardBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: List.generate(daily.length, (idx) {
              final day = daily[idx];
              final isSelected = idx == selectedDayIndex;
              final parsedDate = DateTime.tryParse(day.date);
              final dayNumber = parsedDate != null
                  ? parsedDate.day.toString().padLeft(2, '0')
                  : (day.date.length >= 10 ? day.date.substring(8, 10) : '${idx + 1}');

              final isLast = idx == daily.length - 1;

              return Column(
                children: [
                  InkWell(
                    onTap: () => onSelectDay(idx),
                    child: Container(
                      color: isSelected ? p.selectedHighlight : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            child: Text(
                              dayNumber,
                              style: TextStyle(
                                color: isSelected ? p.brandEmerald : p.textMuted,
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: day.hasData
                                ? SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        Text(
                                          'Đạm ${day.protein.round()}g',
                                          style: TextStyle(
                                            color: isSelected ? p.textPrimary : p.textSecondary,
                                            fontSize: 12,
                                            fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 5),
                                          child: Text('·', style: TextStyle(color: p.textDim)),
                                        ),
                                        Text(
                                          'Carb ${day.carbs.round()}g',
                                          style: TextStyle(
                                            color: p.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 5),
                                          child: Text('·', style: TextStyle(color: p.textDim)),
                                        ),
                                        Text(
                                          'Béo ${day.fat.round()}g',
                                          style: TextStyle(
                                            color: p.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Text(
                                    'Chưa có dữ liệu',
                                    style: TextStyle(
                                      color: p.textMuted,
                                      fontSize: 13,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 8),
                          if (day.hasData)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${day.calories.round()}',
                                  style: TextStyle(
                                    color: isSelected ? p.brandEmerald : p.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  ' kcal',
                                  style: TextStyle(
                                    color: isSelected ? p.brandEmerald : p.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              '—',
                              style: TextStyle(
                                color: p.textDim,
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (!isLast) Divider(height: 1, color: p.cardBorder),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ── UTILITY HELPERS ──────────────────────────────────────────────────────────

int _getIsoWeekNumber(DateTime date) {
  final thursday = date.add(Duration(days: 3 - ((date.weekday + 6) % 7)));
  final firstThursday = DateTime(thursday.year, 1, 4);
  final firstThursdayMonday =
      firstThursday.subtract(Duration(days: (firstThursday.weekday + 6) % 7));
  return ((thursday.difference(firstThursdayMonday).inDays) / 7).floor() + 1;
}

String _formatWeekRange(DateTime start, DateTime end) {
  return '${start.day} thg ${start.month} – ${end.day} thg ${end.month}';
}

String _formatYearText(DateTime start, DateTime end) {
  if (start.year == end.year) {
    return 'Năm ${start.year}';
  }
  return 'Năm ${start.year} – ${end.year}';
}

String _formatYyyyMmDd(DateTime dt) {
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

String _formatNumber(num value) {
  final intVal = value.round();
  final isNegative = intVal < 0;
  final absStr = intVal.abs().toString();
  final buffer = StringBuffer();
  final len = absStr.length;
  for (int i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(absStr[i]);
  }
  return isNegative ? '−$buffer' : buffer.toString();
}

String _formatSelectedDay(DateTime dt) {
  const weekdayNames = [
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ Nhật',
  ];
  final name = weekdayNames[dt.weekday - 1];
  final day = dt.day.toString().padLeft(2, '0');
  final month = dt.month.toString().padLeft(2, '0');
  return '$name, $day/$month';
}
