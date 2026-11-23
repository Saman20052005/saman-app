import 'package:flutter/material.dart';
import '../../data/models/exercise.dart';
import '../tokens/saman_workout_tokens.dart';

class ExerciseSetLogCard extends StatelessWidget {
  final ExerciseSetLog log;
  final int index; // set number (0-based)

  const ExerciseSetLogCard({super.key, required this.log, required this.index});

  @override
  Widget build(BuildContext context) {
    final t = SamanWorkoutTokens.of(context);
    final summary = log.cvFormSummary;
    final hasSummary = summary != null && summary.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  'Set ${index + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Text(
                  log.effectiveUnit == SetUnit.seconds
                      ? '${log.secondsCompleted} s'
                      : '${log.repsCompleted} reps',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              if (log.effectiveUnit == SetUnit.reps) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    '${_formatWeight(log.weightKg)} kg',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              if (log.cvDetected)
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4),
                  child: Icon(
                    Icons.visibility,
                    size: 16,
                    color: t.emeraldAccent,
                  ),
                ),
              if (log.isCompleted)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.check_circle,
                    size: 16,
                    color: t.emeraldAccent,
                  ),
                ),
            ],
          ),
          if (hasSummary) ...[
            const SizedBox(height: 8),
            _CvFormSummaryStrip(summary: summary),
          ],
        ],
      ),
    );
  }

  static String _formatWeight(double weight) =>
      weight == weight.roundToDouble()
          ? weight.toInt().toString()
          : weight.toString();
}

class _CvFormSummaryStrip extends StatelessWidget {
  final Map<String, dynamic> summary;

  const _CvFormSummaryStrip({required this.summary});

  @override
  Widget build(BuildContext context) {
    final t = SamanWorkoutTokens.of(context);
    final validReps = _readInt(summary['valid_reps'] ?? summary['validReps']);
    final fastReps = _readInt(summary['fast_reps'] ?? summary['fastReps']);
    final avgTempo =
        _readDouble(summary['avg_tempo_sec'] ?? summary['avgTempoSec']);
    final avgElbow = _readDouble(
      summary['avg_elbow_angle_deg'] ?? summary['avgElbowAngleDeg'],
    );
    final abortCount =
        _readInt(summary['abort_count'] ?? summary['abortCount']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusSm),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.emeraldAccent,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'CV FORM ANALYSIS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: t.emeraldAccent,
                  ),
                ),
              ),
              if (abortCount != null && abortCount > 0)
                Text(
                  'Aborts: $abortCount',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: t.amberAccent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (validReps != null)
                _MetricText(
                  text: 'Valid reps: $validReps',
                  color: t.emeraldAccent,
                ),
              if (fastReps != null)
                _MetricText(
                  text: 'Fast reps: $fastReps',
                  color: fastReps > 0 ? t.amberAccent : t.textSecondary,
                ),
              if (avgTempo != null)
                _MetricText(
                  text: 'Avg tempo: ${_formatDecimal(avgTempo)}s',
                  color: t.textPrimary,
                ),
              if (avgElbow != null)
                _MetricText(
                  text: 'Elbow angle: ${_formatDecimal(avgElbow)}°',
                  color: t.textPrimary,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _readDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String _formatDecimal(double value) =>
      value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toStringAsFixed(1);
}

class _MetricText extends StatelessWidget {
  final String text;
  final Color color;

  const _MetricText({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}
