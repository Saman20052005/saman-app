import 'package:flutter/foundation.dart';
import 'lat_pulldown_baseline.dart';

/// Immutable summary of CV form analysis for workout reps.
@immutable
class CvFormSummary {
  final int validReps;
  final int totalReps;
  final int fastReps;
  final double avgElbowAngleDeg;
  final double avgTempoSec;
  final int abortCount;

  const CvFormSummary({
    this.validReps = 0,
    this.totalReps = 0,
    this.fastReps = 0,
    this.avgElbowAngleDeg = 0.0,
    this.avgTempoSec = 0.0,
    this.abortCount = 0,
  });

  /// Serializes to the backend CP0.3 schema.
  Map<String, dynamic> toJson() {
    return {
      'valid_reps': validReps,
      'fast_reps': fastReps,
      'avg_elbow_angle_deg': avgElbowAngleDeg,
      'avg_tempo_sec': avgTempoSec,
      'abort_count': abortCount,
    };
  }

  factory CvFormSummary.fromJson(Map<String, dynamic> json) {
    return CvFormSummary(
      validReps: (json['valid_reps'] as num?)?.toInt() ?? 0,
      totalReps: (json['total_reps'] as num?)?.toInt() ??
          (json['valid_reps'] as num?)?.toInt() ??
          0,
      fastReps: (json['fast_reps'] as num?)?.toInt() ?? 0,
      avgElbowAngleDeg: (json['avg_elbow_angle_deg'] as num?)?.toDouble() ?? 0.0,
      avgTempoSec: (json['avg_tempo_sec'] as num?)?.toDouble() ?? 0.0,
      abortCount: (json['abort_count'] as num?)?.toInt() ?? 0,
    );
  }

  CvFormSummary copyWith({
    int? validReps,
    int? totalReps,
    int? fastReps,
    double? avgElbowAngleDeg,
    double? avgTempoSec,
    int? abortCount,
  }) {
    return CvFormSummary(
      validReps: validReps ?? this.validReps,
      totalReps: totalReps ?? this.totalReps,
      fastReps: fastReps ?? this.fastReps,
      avgElbowAngleDeg: avgElbowAngleDeg ?? this.avgElbowAngleDeg,
      avgTempoSec: avgTempoSec ?? this.avgTempoSec,
      abortCount: abortCount ?? this.abortCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CvFormSummary &&
          runtimeType == other.runtimeType &&
          validReps == other.validReps &&
          totalReps == other.totalReps &&
          fastReps == other.fastReps &&
          avgElbowAngleDeg == other.avgElbowAngleDeg &&
          avgTempoSec == other.avgTempoSec &&
          abortCount == other.abortCount;

  @override
  int get hashCode =>
      validReps.hashCode ^
      totalReps.hashCode ^
      fastReps.hashCode ^
      avgElbowAngleDeg.hashCode ^
      avgTempoSec.hashCode ^
      abortCount.hashCode;

  @override
  String toString() {
    return 'CvFormSummary(validReps: $validReps, totalReps: $totalReps, fastReps: $fastReps, avgElbowAngleDeg: $avgElbowAngleDeg, avgTempoSec: $avgTempoSec, abortCount: $abortCount)';
  }
}

/// Service to compute [CvFormSummary] from rep events and session telemetry.
class CvFormSummaryCalculator {
  const CvFormSummaryCalculator._();

  static const double defaultMaxValidElbowAngleDeg = 45.0;
  static const int defaultMinValidDurationMs = 2000;
  static const int defaultMaxValidDurationMs = 3000;
  static const int defaultFastDurationMsThreshold = 2000;

  /// Returns true if [rep] satisfies the standard form criteria:
  /// - [minElbowAngleDeg] < 45.0 (or [maxValidElbowAngleDeg])
  /// - [durationMs] between 2000ms and 3000ms inclusive
  static bool isRepStandardMet(
    LatPulldownRepEvent rep, {
    double maxValidElbowAngleDeg = defaultMaxValidElbowAngleDeg,
    int minValidDurationMs = defaultMinValidDurationMs,
    int maxValidDurationMs = defaultMaxValidDurationMs,
  }) {
    return rep.minElbowAngleDeg < maxValidElbowAngleDeg &&
        rep.durationMs >= minValidDurationMs &&
        rep.durationMs <= maxValidDurationMs;
  }

  /// Computes a [CvFormSummary] from [reps] and [abortCount].
  ///
  /// LatPulldownRepEvent and PullUpRepEvent (which inherits LatPulldownRepEvent)
  /// are both supported.
  static CvFormSummary compute({
    required List<LatPulldownRepEvent> reps,
    int abortCount = 0,
    double maxValidElbowAngleDeg = defaultMaxValidElbowAngleDeg,
    int minValidDurationMs = defaultMinValidDurationMs,
    int maxValidDurationMs = defaultMaxValidDurationMs,
    int fastDurationMsThreshold = defaultFastDurationMsThreshold,
  }) {
    final totalReps = reps.length;
    if (totalReps == 0) {
      return CvFormSummary(
        validReps: 0,
        totalReps: 0,
        fastReps: 0,
        avgElbowAngleDeg: 0.0,
        avgTempoSec: 0.0,
        abortCount: abortCount,
      );
    }

    int validReps = 0;
    int fastReps = 0;
    double sumElbowAngle = 0.0;
    int sumDurationMs = 0;

    for (final rep in reps) {
      if (isRepStandardMet(
        rep,
        maxValidElbowAngleDeg: maxValidElbowAngleDeg,
        minValidDurationMs: minValidDurationMs,
        maxValidDurationMs: maxValidDurationMs,
      )) {
        validReps++;
      }
      if (rep.durationMs < fastDurationMsThreshold) {
        fastReps++;
      }
      sumElbowAngle += rep.minElbowAngleDeg;
      sumDurationMs += rep.durationMs;
    }

    final rawAvgElbow = sumElbowAngle / totalReps;
    final avgElbowAngleDeg = double.parse(rawAvgElbow.toStringAsFixed(1));

    final rawAvgTempo = sumDurationMs / (totalReps * 1000.0);
    final avgTempoSec = double.parse(rawAvgTempo.toStringAsFixed(2));

    return CvFormSummary(
      validReps: validReps,
      totalReps: totalReps,
      fastReps: fastReps,
      avgElbowAngleDeg: avgElbowAngleDeg,
      avgTempoSec: avgTempoSec,
      abortCount: abortCount,
    );
  }
}
