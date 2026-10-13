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
          final Map<String, List<ExerciseSetLog>> groupedLogs = {};
          for (var log in session.exerciseLogs) {
            groupedLogs.putIfAbsent(log.exerciseId, () => []).add(log);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppDimens.paddingL),
            itemCount: groupedLogs.length,
            itemBuilder: (context, index) {
              final exerciseId = groupedLogs.keys.elementAt(index);
              final logs = groupedLogs[exerciseId]!;
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTextStyle(
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
                          Expanded(child: Text(
                            logs.every((log) => log.effectiveUnit == SetUnit.seconds)
                                ? 'Seconds' : logs.every((log) => log.effectiveUnit == SetUnit.reps)
                                    ? 'Reps' : 'Reps / Seconds',
                          )),
                          if (logs.any((log) => log.effectiveUnit == SetUnit.reps))
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Total volume: ${_calculateVolume(logs)} kg',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
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

  int _calculateVolume(List<ExerciseSetLog> logs) {
    return logs.fold(
        0, (sum, log) => sum + log.volumeKg.round());
  }
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
        return Text(name.isEmpty ? 'Bài tập không có tên' : name);
      },
    );
  }
}
