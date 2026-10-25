import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/workout_history_providers.dart';
import '../../data/models/exercise.dart';
import '../../core/constants/app_dimens.dart';
import '../../core/constants/app_colors.dart';
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
        searchQuery: _search.text);
    final filtered = ref.watch(filteredWorkoutHistoryProvider(filter));
    final historyAsync = ref.watch(workoutHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Workout History',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: historyAsync.when(
        data: (sessions) {
          if (sessions.isEmpty) {
            return _buildEmptyState(context);
          }
          final visible = filtered.valueOrNull ?? const <WorkoutSession>[];
          return ListView(
            padding: const EdgeInsets.all(AppDimens.paddingL),
            children: [
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: 'Search workouts',
                  hintText: 'Plan or exercise',
                  suffixIcon: IconButton(
                    tooltip: 'Clear filters',
                    onPressed: _clear,
                    icon: const Icon(Icons.clear),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Calendar and period overview'),
                children: [
                  Wrap(spacing: 8, children: [
                    for (final period in HistoryPeriod.values)
                      ChoiceChip(
                        label: Text(switch (period) {
                          HistoryPeriod.thisWeek => 'This week',
                          HistoryPeriod.thisMonth => 'Calendar month',
                          HistoryPeriod.allTime => 'All loaded',
                        }),
                        selected: _period == period && _date == null,
                        onSelected: (_) => setState(() {
                          _period = period;
                          _date = null;
                        }),
                      ),
                  ]),
                  LayoutBuilder(
                    builder: (context, constraints) => Scrollbar(
                        controller: _calendarScroll,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _calendarScroll,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: constraints.maxWidth < 300
                                ? 300
                                : constraints.maxWidth,
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
                        )),
                  ),
                  if (_date != null)
                    Text(
                        'Selected date: ${DateFormat('yyyy-MM-dd').format(_date!)} (UTC+7); overrides period'),
                  _HistoryOverview(
                      sessions: visible, loadedCount: sessions.length),
                  TextButton(
                      onPressed: _clear, child: const Text('Clear filters')),
                ],
              ),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No workouts match your filters'),
                ),
              for (final session in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _WorkoutSessionCard(session: session),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Unable to load workout history'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(workoutHistoryProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.fitness_center_outlined,
            size: 100,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No workout history yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start your first workout to see it here!',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(12),
      child: Text(
        'Filtered overview: ${overview.completedWorkouts} of $loadedCount loaded workouts\n'
        'Search and date/period filters applied (UTC+7). Loaded data only; older history may be absent.\n'
        '${overview.totalSets} completed sets / ${NumberFormat('0.###').format(overview.totalVolumeKg)} kg external load volume\n'
        '${overview.knownDurationSeconds} s known session duration / ${overview.unknownDurations} unknown durations',
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
    final formattedDate = DateFormat('MMM dd, yyyy').format(date);
    final formattedTime = DateFormat('HH:mm').format(date);

    final exerciseCount =
        session.exerciseLogs.map((log) => log.exerciseId).toSet().length;
    final totalVolume = session.totalVolumeKg;
    final duration = session.totalDurationMinutes;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SessionDetailScreen(sessionId: session.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with date and time
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                      child: Text(
                    session.planName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  )),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Completed',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Date and time
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    formattedDate,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    formattedTime,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Stats row
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _StatItem(
                    icon: Icons.fitness_center,
                    label: 'Exercises',
                    value: exerciseCount.toString(),
                  ),
                  _StatItem(
                    icon: Icons.timer,
                    label: 'Duration',
                    value: duration == null
                        ? '—'
                        : duration == 0
                            ? '<1 min'
                            : '${duration}m',
                  ),
                  _StatItem(
                    icon: Icons.monitor_weight,
                    label: 'Volume',
                    value: '${totalVolume}kg',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
