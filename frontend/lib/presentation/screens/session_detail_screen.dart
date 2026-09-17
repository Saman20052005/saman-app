import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
              // Lấy tên bài tập từ log đầu tiên (có thể fetch từ repository nếu cần)
              final exerciseName = logs.first.exerciseSlug;
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exerciseName,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      // Header
                      Row(
                        children: const [
                          SizedBox(width: 40, child: Text('Set')),
                          Expanded(child: Text('Reps')),
                          Expanded(child: Text('Weight (kg)')),
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
              Text('Lỗi: $err'),
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
        0, (sum, log) => sum + (log.repsCompleted * log.weightKg).round());
  }
}
