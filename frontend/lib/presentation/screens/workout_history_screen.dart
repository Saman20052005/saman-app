import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/workout_history_providers.dart';
import '../providers/exercise_providers.dart';
import '../tokens/saman_workout_tokens.dart';
import '../../data/models/exercise.dart';
import 'session_detail_screen.dart';

class WorkoutHistoryScreen extends ConsumerStatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  ConsumerState<WorkoutHistoryScreen> createState() =>
      _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends ConsumerState<WorkoutHistoryScreen> {
  final _search = TextEditingController();
  final _calendarScroll = ScrollController();
  HistoryPeriod _period = HistoryPeriod.allTime;
  DateTime _month = toVietnamTime(DateTime.now());
  DateTime? _date;

  @override
  void dispose() {
    _search.dispose();
    _calendarScroll.dispose();
    super.dispose();
  }

  void _clear() {
    setState(() {
      _search.clear();
      _period = HistoryPeriod.allTime;
      _date = null;
      _month = toVietnamTime(DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workoutAuthScopeProvider, (_, __) => _clear());
    final filter = WorkoutHistoryFilterState(
      period: _period,
      calendarMonth: _month,
      selectedDate: _date,
      searchQuery: _search.text,
    );
    final filtered = ref.watch(filteredWorkoutHistoryProvider(filter));
    final historyAsync = ref.watch(workoutHistoryProvider);

    final canPop = Navigator.canPop(context);

    return Scaffold(
      backgroundColor: SamanWorkoutTokens.canvas,
      appBar: AppBar(
        backgroundColor: SamanWorkoutTokens.canvas,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: canPop
            ? Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: SamanWorkoutTokens.cardSurface,
                        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                        border: Border.all(color: SamanWorkoutTokens.border),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: SamanWorkoutTokens.textSecondary,
                      ),
                    ),
                  ),
                ),
              )
            : null,
        title: const Text(
          'Workout History',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Space Grotesk',
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: SamanWorkoutTokens.textPrimary,
            letterSpacing: -0.5,
          ),
        ),

      ),
      body: historyAsync.when(
        data: (sessions) {
          if (sessions.isEmpty) {
            return _buildEmptyState(context);
          }
          final visible = filtered.valueOrNull ?? const <WorkoutSession>[];

          // Compute summary strip values
          final overview = WorkoutHistoryOverviewData(visible);
          final totalMinutes = overview.knownDurationSeconds ~/ 60;
          final totalHours = totalMinutes ~/ 60;
          final remainingMinutes = totalMinutes % 60;
          final totalVolumeText = NumberFormat('#,###').format(overview.totalVolumeKg.round());

          // Group sessions by day in Vietnam Time
          final groupedSessions = <DateTime, List<WorkoutSession>>{};
          for (final session in visible) {
            final vtDate = toVietnamTime(session.startedAt);
            final dayKey = DateTime.utc(vtDate.year, vtDate.month, vtDate.day);
            groupedSessions.putIfAbsent(dayKey, () => []).add(session);
          }

          final monthLabel = DateFormat('MMMM yyyy').format(_month);
          final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

          return ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: SamanWorkoutTokens.spacingLg,
              vertical: SamanWorkoutTokens.spacingMd,
            ),
            children: [
              // Search Input Bar
              Container(
                decoration: BoxDecoration(
                  color: SamanWorkoutTokens.cardSurface,
                  borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                  border: Border.all(color: SamanWorkoutTokens.border),
                ),
                child: TextField(
                  controller: _search,
                  style: const TextStyle(
                    color: SamanWorkoutTokens.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 18,
                      color: SamanWorkoutTokens.textSecondary,
                    ),
                    hintText: 'Search workouts',
                    labelText: 'Search workouts',
                    labelStyle: const TextStyle(
                      color: SamanWorkoutTokens.textSecondary,
                      fontSize: 13,
                    ),
                    hintStyle: const TextStyle(
                      color: SamanWorkoutTokens.textSecondary,
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    suffixIcon: IconButton(
                      tooltip: 'Clear filters',
                      onPressed: _clear,
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: SamanWorkoutTokens.textSecondary,
                      ),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 10),

              // Expandable Calendar & Overview Accordion
              Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: SamanWorkoutTokens.cardSurface,
                    borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                    border: Border.all(color: SamanWorkoutTokens.border),
                  ),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    title: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: SamanWorkoutTokens.surfaceElevated,
                            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                            border: Border.all(color: SamanWorkoutTokens.border),
                          ),
                          child: const Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: SamanWorkoutTokens.emeraldAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Calendar and period overview',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: SamanWorkoutTokens.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(left: 34),
                      child: Text(
                        '$monthLabel · All $daysInMonth days',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: SamanWorkoutTokens.textSecondary,
                        ),
                      ),
                    ),
                    iconColor: SamanWorkoutTokens.textSecondary,
                    collapsedIconColor: SamanWorkoutTokens.textSecondary,
                    children: [
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final period in HistoryPeriod.values)
                            ChoiceChip(
                              label: Text(
                                switch (period) {
                                  HistoryPeriod.thisWeek => 'This week',
                                  HistoryPeriod.thisMonth => 'Calendar month',
                                  HistoryPeriod.allTime => 'All loaded',
                                },
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _period == period && _date == null
                                      ? SamanWorkoutTokens.emeraldAccent
                                      : SamanWorkoutTokens.textSecondary,
                                  fontWeight: _period == period && _date == null
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              selected: _period == period && _date == null,
                              backgroundColor: SamanWorkoutTokens.surfaceElevated,
                              selectedColor: SamanWorkoutTokens.emeraldBadgeBg,
                              side: BorderSide(
                                color: _period == period && _date == null
                                    ? SamanWorkoutTokens.emeraldAccent
                                    : SamanWorkoutTokens.border,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusPill),
                              ),
                              onSelected: (_) => setState(() {
                                _period = period;
                                _date = null;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) => SizedBox(
                          width: constraints.maxWidth,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: 300,
                              child: Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: SamanWorkoutTokens.emeraldAccent,
                                    onPrimary: SamanWorkoutTokens.buttonPrimaryText,
                                    surface: SamanWorkoutTokens.cardSurface,
                                    onSurface: SamanWorkoutTokens.textPrimary,
                                  ),
                                ),
                                child: CalendarDatePicker(
                                  initialDate: _date ?? _month,
                                  firstDate: DateTime(1970),
                                  lastDate: DateTime(2100, 12, 31),
                                  onDateChanged: (date) =>
                                      setState(() => _date = date),
                                  onDisplayedMonthChanged: (month) =>
                                      setState(() => _month = month),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_date != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Selected date: ${DateFormat('yyyy-MM-dd').format(_date!)} (UTC+7); overrides period',
                            style: const TextStyle(
                              color: SamanWorkoutTokens.emeraldAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      _HistoryOverview(
                        sessions: visible,
                        loadedCount: sessions.length,
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _clear,
                          style: TextButton.styleFrom(
                            foregroundColor: SamanWorkoutTokens.emeraldAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          child: const Text('Clear filters'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Period Summary Strip (3-column metric card)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                decoration: BoxDecoration(
                  color: SamanWorkoutTokens.cardSurface,
                  borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
                  border: Border.all(color: SamanWorkoutTokens.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'SESSIONS',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9,
                              letterSpacing: 0.8,
                              color: SamanWorkoutTokens.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${visible.length}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: SamanWorkoutTokens.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 28, color: SamanWorkoutTokens.border),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'TOTAL TIME',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9,
                              letterSpacing: 0.8,
                              color: SamanWorkoutTokens.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: const TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: SamanWorkoutTokens.textPrimary,
                              ),
                              children: [
                                if (totalMinutes == 0 && overview.knownDurationSeconds > 0) ...[
                                  const TextSpan(text: '<1'),
                                  const TextSpan(
                                    text: 'm',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: SamanWorkoutTokens.textSecondary),
                                  ),
                                ] else if (totalHours > 0) ...[
                                  TextSpan(text: '$totalHours'),
                                  const TextSpan(
                                    text: 'h ',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: SamanWorkoutTokens.textSecondary),
                                  ),
                                  TextSpan(text: '$remainingMinutes'),
                                  const TextSpan(
                                    text: 'm',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: SamanWorkoutTokens.textSecondary),
                                  ),
                                ] else ...[
                                  TextSpan(text: '$totalMinutes'),
                                  const TextSpan(
                                    text: 'm',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: SamanWorkoutTokens.textSecondary),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 28, color: SamanWorkoutTokens.border),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'TOTAL VOLUME',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9,
                              letterSpacing: 0.8,
                              color: SamanWorkoutTokens.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$totalVolumeText kg',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: SamanWorkoutTokens.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Filter empty state when no workouts match
              if (visible.isEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: SamanWorkoutTokens.cardSurface,
                    borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
                    border: Border.all(color: SamanWorkoutTokens.border),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: SamanWorkoutTokens.surfaceElevated,
                          shape: BoxShape.circle,
                          border: Border.all(color: SamanWorkoutTokens.border),
                        ),
                        child: const Icon(
                          Icons.search_off,
                          size: 22,
                          color: SamanWorkoutTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No workouts match your filters',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: SamanWorkoutTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Try adjusting your search query or calendar date range.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: SamanWorkoutTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton(
                        onPressed: _clear,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: SamanWorkoutTokens.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                          ),
                        ),
                        child: const Text(
                          'Reset filters',
                          style: TextStyle(color: SamanWorkoutTokens.emeraldAccent),
                        ),
                      ),
                    ],
                  ),
                ),

              // Timeline grouped by day
              for (final entry in groupedSessions.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8, left: 4, right: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: SamanWorkoutTokens.emeraldAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          DateFormat('EEEE, MMM d, yyyy').format(entry.key).toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: SamanWorkoutTokens.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${entry.value.length} session${entry.value.length > 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: SamanWorkoutTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final session in entry.value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _WorkoutSessionCard(session: session),
                  ),
              ],
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: SamanWorkoutTokens.emeraldAccent),
        ),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 40, color: SamanWorkoutTokens.crimsonAccent),
                const SizedBox(height: 12),
                const Text(
                  'Unable to load workout history',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: SamanWorkoutTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => ref.invalidate(workoutHistoryProvider),
                  style: TextButton.styleFrom(
                    foregroundColor: SamanWorkoutTokens.emeraldAccent,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: SamanWorkoutTokens.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: SamanWorkoutTokens.border),
              ),
              child: const Icon(
                Icons.fitness_center_outlined,
                size: 28,
                color: SamanWorkoutTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No workout history yet',
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: SamanWorkoutTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Start your first workout to see it here!\nCompleted training sessions, weights, and set logs will be automatically archived here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: SamanWorkoutTokens.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryOverview extends StatelessWidget {
  const _HistoryOverview({required this.sessions, required this.loadedCount});
  final List<WorkoutSession> sessions;
  final int loadedCount;

  @override
  Widget build(BuildContext context) {
    final overview = WorkoutHistoryOverviewData(sessions);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Filtered overview: ${overview.completedWorkouts} of $loadedCount loaded workouts\n'
        'Search and date/period filters applied (UTC+7). Loaded data only; older history may be absent.\n'
        '${overview.totalSets} completed sets / ${NumberFormat('0.###').format(overview.totalVolumeKg)} kg external load volume\n'
        '${overview.knownDurationSeconds} s known session duration / ${overview.unknownDurations} unknown durations',
        style: const TextStyle(
          fontSize: 11,
          color: SamanWorkoutTokens.textMuted,
          height: 1.4,
        ),
      ),
    );
  }
}

class _WorkoutSessionCard extends StatelessWidget {
  final WorkoutSession session;

  const _WorkoutSessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final date = toVietnamTime(session.startedAt);
    final formattedDateTime = DateFormat('MMM d, yyyy · HH:mm').format(date);

    final exerciseCount =
        session.exerciseLogs.map((log) => log.exerciseId).toSet().length;
    final totalVolume = session.totalVolumeKg;
    final duration = session.totalDurationMinutes;

    final durationText = duration == null
        ? '—'
        : duration == 0
            ? '<1 min'
            : '${duration}m';

    // Group logs by exerciseId to display previews
    final exerciseGroups = <String, List<ExerciseSetLog>>{};
    for (final log in session.exerciseLogs) {
      exerciseGroups.putIfAbsent(log.exerciseId, () => []).add(log);
    }

    final primaryExerciseId = session.exerciseLogs.isNotEmpty
        ? session.exerciseLogs.first.exerciseId
        : null;
    final resolvedPrimaryId = primaryExerciseId == 'ex_1'
        ? 'db-bench-press'
        : primaryExerciseId;

    Exercise? primaryExercise;
    if (resolvedPrimaryId != null) {
      for (final ex in curatedExerciseLibrary) {
        if (ex.id == resolvedPrimaryId || ex.slug == resolvedPrimaryId) {
          primaryExercise = ex;
          break;
        }
      }
    }

    String? coverImagePath;
    if (primaryExercise != null) {
      coverImagePath = primaryExercise.thumbnailUrl.replaceAll('-thumb.jpg', '-poster.jpg');
    }

    return Container(
      decoration: BoxDecoration(
        color: SamanWorkoutTokens.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
        border: Border.all(color: SamanWorkoutTokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SessionDetailScreen(sessionId: session.id),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover Photo with Gradient & Badges
            SizedBox(
              height: 160,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCoverImage(coverImagePath),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          SamanWorkoutTokens.cardSurface,
                          SamanWorkoutTokens.cardSurface.withOpacity(0.65),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  // Top Badges (Wrap to prevent overflow on narrow screens/high text scale)
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: SamanWorkoutTokens.canvas.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                            border: Border.all(color: SamanWorkoutTokens.border),
                          ),
                          child: Text(
                            formattedDateTime,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: SamanWorkoutTokens.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: SamanWorkoutTokens.emeraldBadgeBg,
                            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusSm),
                            border: Border.all(color: SamanWorkoutTokens.emeraldBadgeBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: SamanWorkoutTokens.emeraldAccent,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                'Completed',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: SamanWorkoutTokens.emeraldAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Bottom Title
                  Positioned(
                    bottom: 10,
                    left: 14,
                    right: 14,
                    child: Text(
                      session.planName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: SamanWorkoutTokens.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Card Body (Metrics & Exercise previews)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Metrics 3-Col Box
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: SamanWorkoutTokens.surfaceElevated.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                      border: Border.all(color: SamanWorkoutTokens.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.fitness_center, size: 16, color: SamanWorkoutTokens.textSecondary),
                              const SizedBox(height: 2),
                              Text(
                                '$exerciseCount',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Space Grotesk',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: SamanWorkoutTokens.textPrimary,
                                ),
                              ),
                              Text(
                                exerciseCount == 1 ? 'EXERCISE' : 'EXERCISES',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 8,
                                  color: SamanWorkoutTokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 26, color: SamanWorkoutTokens.border),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined, size: 16, color: SamanWorkoutTokens.textSecondary),
                              const SizedBox(height: 2),
                              Text(
                                durationText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Space Grotesk',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: SamanWorkoutTokens.textPrimary,
                                ),
                              ),
                              const Text(
                                'DURATION',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 8,
                                  color: SamanWorkoutTokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 26, color: SamanWorkoutTokens.border),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.scale, size: 16, color: SamanWorkoutTokens.textSecondary),
                              const SizedBox(height: 2),
                              Text(
                                '$totalVolume kg',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Space Grotesk',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: SamanWorkoutTokens.textPrimary,
                                ),
                              ),
                              const Text(
                                'VOLUME',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 8,
                                  color: SamanWorkoutTokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Exercises Performed / Preview Header
                  const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'EXERCISES PERFORMED',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: SamanWorkoutTokens.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View session',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: SamanWorkoutTokens.emeraldAccent,
                            ),
                          ),
                          SizedBox(width: 2),
                          Icon(
                            Icons.arrow_forward,
                            size: 12,
                            color: SamanWorkoutTokens.emeraldAccent,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Exercise Chips
                  if (exerciseGroups.isNotEmpty)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry in exerciseGroups.entries.take(3))
                              ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                                child: _buildExerciseChip(entry.key, entry.value, session.planName),
                              ),
                            if (exerciseGroups.length > 3)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: SamanWorkoutTokens.surfaceElevated.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
                                  border: Border.all(color: SamanWorkoutTokens.border),
                                ),
                                child: Text(
                                  '+${exerciseGroups.length - 3} more',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: SamanWorkoutTokens.textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseChip(String exerciseId, List<ExerciseSetLog> logs, [String? parentPlanName]) {
    final resolvedId = exerciseId == 'ex_1' ? 'db-bench-press' : exerciseId;
    Exercise? found;
    for (final ex in curatedExerciseLibrary) {
      if (ex.id == resolvedId || ex.slug == resolvedId) {
        found = ex;
        break;
      }
    }

    final displayName = found?.name ??
        exerciseId
            .replaceAll('-', ' ')
            .split(' ')
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '')
            .join(' ');
    final isDuplicate = parentPlanName != null && parentPlanName.trim().toLowerCase() == displayName.trim().toLowerCase();
    final chipLabel = isDuplicate ? '$displayName\u200B' : displayName;

    final completedSets = logs.where((l) => l.isCompleted).length;
    final totalSets = logs.length;
    final setDisplay = completedSets > 0 ? completedSets : totalSets;
    final volume = logs.fold<double>(0, (sum, l) => sum + l.volumeKg).round();

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: SamanWorkoutTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(color: SamanWorkoutTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: SamanWorkoutTokens.cardSurface,
              borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusSm),
            ),
            clipBehavior: Clip.antiAlias,
            child: found != null
                ? Image.asset(
                    found.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.fitness_center, size: 14, color: SamanWorkoutTokens.textSecondary),
                    ),
                  )
                : const Center(
                    child: Icon(Icons.fitness_center, size: 14, color: SamanWorkoutTokens.textSecondary),
                  ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  chipLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: SamanWorkoutTokens.textPrimary,
                  ),
                ),
                Text(
                  volume > 0 ? '$setDisplay sets · $volume kg' : '$setDisplay sets',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    color: SamanWorkoutTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildCoverImage(String? imagePath) {
    if (imagePath != null && imagePath.isNotEmpty) {
      if (imagePath.startsWith('http')) {
        return CachedNetworkImage(
          imageUrl: imagePath,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _fallbackCover(),
        );
      }
      return Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackCover(),
      );
    }
    return _fallbackCover();
  }

  Widget _fallbackCover() {
    return Image.asset(
      'assets/images/home_workout_upper.jpg',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: SamanWorkoutTokens.surfaceElevated,
        child: const Center(
          child: Icon(Icons.fitness_center, size: 40, color: SamanWorkoutTokens.border),
        ),
      ),
    );
  }
}
