import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../providers/exercise_providers.dart';
import '../providers/session_detail_providers.dart';
import '../../core/constants/app_dimens.dart';
import '../widgets/exercise_set_log_card.dart';
import '../../data/models/exercise.dart';

class SessionDetailScreen extends ConsumerWidget {
  final String sessionId;

  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionDetailProvider(sessionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết buổi tập',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: sessionAsync.when(
        data: (session) {
          // Nhóm các log theo exerciseId
          final metrics = SessionDetailMetrics.compute(session);
          final groupedLogs = {
            for (final group in metrics.exerciseGroups)
              group.exerciseId: group.sets
          };

          return ListView.builder(
            padding: const EdgeInsets.all(AppDimens.paddingL),
            itemCount: groupedLogs.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Session: ${session.planName}\n'
                    '${metrics.completedExercisesCount} exercises / ${metrics.completedSetsCount} completed sets\n'
                    '${metrics.totalReps} total reps / ${metrics.totalTimedSeconds} timed seconds\n'
                    '${_formatVolume(metrics.totalVolumeKg)} kg external load volume / '
                    '${metrics.durationSeconds == null ? "Unknown duration" : "${metrics.durationSeconds} s session duration"}',
                  ),
                );
              }
              final group = metrics.exerciseGroups[index - 1];
              final exerciseId = group.exerciseId;
              final logs = groupedLogs[exerciseId]!;
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTextStyle.merge(
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                        child: _SessionExerciseName(
                          key: ValueKey(exerciseId),
                          exerciseId: exerciseId,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Header
                      Row(
                        children: [
                          const SizedBox(width: 40, child: Text('Set')),
                          Expanded(
                              child: Text(
                            logs.every((log) =>
                                    log.effectiveUnit == SetUnit.seconds)
                                ? 'Seconds'
                                : logs.every((log) =>
                                        log.effectiveUnit == SetUnit.reps)
                                    ? 'Reps'
                                    : 'Reps / Seconds',
                          )),
                          if (logs
                              .any((log) => log.effectiveUnit == SetUnit.reps))
                            const Expanded(child: Text('Weight (kg)')),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ...logs.asMap().entries.map((entry) {
                        return ExerciseSetLogCard(
                          log: entry.value,
                          index: entry.key,
                        );
                      }).toList(),
                      const SizedBox(height: 8),
                      // Tổng volume cho bài tập
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Total volume: ${_formatVolume(group.totalVolumeKg)} kg',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (!group.hasExternalLoad)
                        const Text('External load only; timed sets and bodyweight add no kg volume.',
                            style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Không tải được buổi tập'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    ref.invalidate(sessionDetailProvider(sessionId)),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatVolume(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

class _SessionExerciseName extends ConsumerStatefulWidget {
  const _SessionExerciseName({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  ConsumerState<_SessionExerciseName> createState() =>
      _SessionExerciseNameState();
}

class _SessionExerciseNameState extends ConsumerState<_SessionExerciseName> {
  late Future<Exercise> _exercise;

  @override
  void initState() {
    super.initState();
    _exercise = _loadExercise();
  }

  @override
  void didUpdateWidget(covariant _SessionExerciseName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exerciseId != widget.exerciseId) {
      _exercise = _loadExercise();
    }
  }

  Future<Exercise> _loadExercise() {
    // The default demo workout uses a legacy ID for this library exercise.
    final libraryId =
        widget.exerciseId == 'ex_1' ? 'db-bench-press' : widget.exerciseId;
    return ref.read(exerciseRepositoryProvider).getExerciseById(libraryId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Exercise>(
      future: _exercise,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Text('Đang tải tên bài tập…');
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          final notFound = error is StateError ||
              (error is DioException && error.response?.statusCode == 404);
          if (notFound) {
            return const Text('Bài tập không còn trong thư viện');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Không tải được tên bài tập'),
              TextButton(
                onPressed: () {
                  final exercise = _loadExercise();
                  setState(() {
                    _exercise = exercise;
                  });
                },
                child: const Text('Thử lại'),
              ),
            ],
          );
        }
        final name = snapshot.data!.name.trim();
        final exercise = snapshot.data!;
        final muscles = exercise.targetMuscles.isNotEmpty
            ? exercise.targetMuscles.join(', ')
            : exercise.muscleGroup.trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name.isEmpty ? 'Bài tập không có tên' : name),
            Text(
                muscles.isEmpty
                    ? 'Muscle information unavailable'
                    : 'Muscles: $muscles',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
          ],
        );
      },
    );
  }
}
