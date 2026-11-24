import 'package:flutter/foundation.dart';
import 'bicep_curl_baseline.dart';
import 'face_pull_baseline.dart';
import 'lat_pulldown_baseline.dart';
import 'overhead_press_baseline.dart';
import 'plank_hold_baseline.dart';
import 'pull_up_baseline.dart';
import 'push_up_baseline.dart';
import 'row_baseline.dart';
import 'squat_baseline.dart';
import 'workout_cv_exercise_registry.dart';

/// Per-exercise form evaluation criteria for CV summary and result reporting.
@immutable
class ExerciseFormCriteria {
  final double maxValidAngleDeg;
  final bool maxAngleInclusive;
  final bool isMinAngleCriteria;
  final int minValidDurationMs;
  final int maxValidDurationMs;
  final int fastDurationMsThreshold;
  final String angleMetricLabel;
  final String criteriaDisplayText;
  final String? angleMetricLabelEn;
  final String? criteriaDisplayTextEn;

  const ExerciseFormCriteria({
    required this.maxValidAngleDeg,
    this.maxAngleInclusive = false,
    this.isMinAngleCriteria = false,
    required this.minValidDurationMs,
    required this.maxValidDurationMs,
    required this.fastDurationMsThreshold,
    required this.angleMetricLabel,
    required this.criteriaDisplayText,
    this.angleMetricLabelEn,
    this.criteriaDisplayTextEn,
  });

  String localizedAngleMetricLabel({required bool isVietnamese}) =>
      isVietnamese ? angleMetricLabel : (angleMetricLabelEn ?? angleMetricLabel);

  String localizedCriteriaDisplayText({required bool isVietnamese}) =>
      isVietnamese
          ? criteriaDisplayText
          : (criteriaDisplayTextEn ?? criteriaDisplayText);

  /// Returns the canonical form criteria for [module].
  ///
  /// Defaults to Lat Pulldown criteria when [module] is null.
  factory ExerciseFormCriteria.forModule(CvExerciseModule? module) {
    switch (module) {
      case CvExerciseModule.pullUp:
        return const ExerciseFormCriteria(
          maxValidAngleDeg: 65.0,
          maxAngleInclusive: true,
          minValidDurationMs: 1500,
          maxValidDurationMs: 4000,
          fastDurationMsThreshold: 1500,
          angleMetricLabel: 'Góc khuỷu tay',
          criteriaDisplayText: 'Góc ≤ 65°',
          angleMetricLabelEn: 'Elbow angle',
          criteriaDisplayTextEn: 'Angle ≤ 65°',
        );
      case CvExerciseModule.squat:
        return const ExerciseFormCriteria(
          maxValidAngleDeg: 95.0,
          maxAngleInclusive: true,
          minValidDurationMs: 1500,
          maxValidDurationMs: 4500,
          fastDurationMsThreshold: 1500,
          angleMetricLabel: 'Góc gối',
          criteriaDisplayText: 'Góc gối ≤ 95°',
          angleMetricLabelEn: 'Knee angle',
          criteriaDisplayTextEn: 'Knee ≤ 95°',
        );
      case CvExerciseModule.pushUp:
        return const ExerciseFormCriteria(
          maxValidAngleDeg: 95.0,
          maxAngleInclusive: true,
          minValidDurationMs: 1200,
          maxValidDurationMs: 4000,
          fastDurationMsThreshold: 1200,
          angleMetricLabel: 'Góc khuỷu tay',
          criteriaDisplayText: 'Góc ≤ 95°',
          angleMetricLabelEn: 'Elbow angle',
          criteriaDisplayTextEn: 'Angle ≤ 95°',
        );
      case CvExerciseModule.overheadPress:
        return const ExerciseFormCriteria(
          maxValidAngleDeg: 155.0,
          maxAngleInclusive: true,
          isMinAngleCriteria: true,
          minValidDurationMs: 1500,
          maxValidDurationMs: 4000,
          fastDurationMsThreshold: 1500,
          angleMetricLabel: 'Đỉnh duỗi',
          criteriaDisplayText: 'Đỉnh duỗi ≥ 155°',
          angleMetricLabelEn: 'Peak lockout',
          criteriaDisplayTextEn: 'Lockout ≥ 155°',
        );
      case CvExerciseModule.bicepCurl:
        return const ExerciseFormCriteria(
          maxValidAngleDeg: 60.0,
          maxAngleInclusive: true,
          minValidDurationMs: 1500,
          maxValidDurationMs: 4000,
          fastDurationMsThreshold: 1500,
          angleMetricLabel: 'Góc khuỷu tay',
          criteriaDisplayText: 'Góc ≤ 60°',
          angleMetricLabelEn: 'Elbow angle',
          criteriaDisplayTextEn: 'Angle ≤ 60°',
        );
      case CvExerciseModule.hipHinge:
        return const ExerciseFormCriteria(
          maxValidAngleDeg: 105.0,
          maxAngleInclusive: true,
          isMinAngleCriteria: false,
          minValidDurationMs: 1200,
          maxValidDurationMs: 4500,
          fastDurationMsThreshold: 1200,
          angleMetricLabel: 'Gập hông',
          criteriaDisplayText: 'Gập hông ≤ 105°',
          angleMetricLabelEn: 'Hip hinge',
          criteriaDisplayTextEn: 'Hip hinge ≤ 105°',
        );
      case CvExerciseModule.hipThrust:
        return const ExerciseFormCriteria(
          maxValidAngleDeg: 160.0,
          maxAngleInclusive: true,
          isMinAngleCriteria: true,
          minValidDurationMs: 1200,
          maxValidDurationMs: 4000,
          fastDurationMsThreshold: 1200,
          angleMetricLabel: 'Khóa hông',
          criteriaDisplayText: 'Khóa hông ≥ 160°',
          angleMetricLabelEn: 'Hip lockout',
          criteriaDisplayTextEn: 'Hip lockout ≥ 160°',
        );
      case CvExerciseModule.tricepExtension:
        return const ExerciseFormCriteria(
          maxValidAngleDeg: 155.0,
          maxAngleInclusive: true,
          isMinAngleCriteria: true,
          minValidDurationMs: 1200,
          maxValidDurationMs: 4000,
          fastDurationMsThreshold: 1200,
          angleMetricLabel: 'Đỉnh duỗi',
          criteriaDisplayText: 'Đỉnh duỗi ≥ 155°',
          angleMetricLabelEn: 'Peak extension',
          criteriaDisplayTextEn: 'Extension ≥ 155°',
        );
      case CvExerciseModule.lateralRaise:
        return const ExerciseFormCriteria(
          maxValidAngleDeg: 75.0,
          maxAngleInclusive: true,
          isMinAngleCriteria: true,
          minValidDurationMs: 1200,
          maxValidDurationMs: 4000,
          fastDurationMsThreshold: 1200,
          angleMetricLabel: 'Dang vai',
          criteriaDisplayText: 'Dang vai ≥ 75°',
          angleMetricLabelEn: 'Shoulder raise',
          criteriaDisplayTextEn: 'Shoulder ≥ 75°',
        );
      case CvExerciseModule.legExtension:
        return const ExerciseFormCriteria(
          maxValidAngleDeg: 150.0,
          maxAngleInclusive: true,
          isMinAngleCriteria: true,
          minValidDurationMs: 1200,
          maxValidDurationMs: 4000,
          fastDurationMsThreshold: 1200,
          angleMetricLabel: 'Đỉnh duỗi gối',
          criteriaDisplayText: 'Đỉnh duỗi ≥ 150°',
          angleMetricLabelEn: 'Knee lockout',
          criteriaDisplayTextEn: 'Lockout ≥ 150°',
        );
      case CvExerciseModule.legCurl:
        return const ExerciseFormCriteria(
          maxValidAngleDeg: 105.0,
          maxAngleInclusive: true,
          isMinAngleCriteria: false,
          minValidDurationMs: 1200,
          maxValidDurationMs: 4500,
          fastDurationMsThreshold: 1200,
          angleMetricLabel: 'Góc gối',
          criteriaDisplayText: 'Góc gối ≤ 105°',
          angleMetricLabelEn: 'Knee angle',
          criteriaDisplayTextEn: 'Knee ≤ 105°',
        );
      case CvExerciseModule.plankHold:
        return const ExerciseFormCriteria(
          maxValidAngleDeg: 165.0,
          maxAngleInclusive: true,
          isMinAngleCriteria: true,
          minValidDurationMs: 900,
          maxValidDurationMs: 60000,
          fastDurationMsThreshold: 500,
          angleMetricLabel: 'Thẳng trục thân',
          criteriaDisplayText: 'Trục thân ≥ 165°',
          angleMetricLabelEn: 'Body alignment',
          criteriaDisplayTextEn: 'Alignment ≥ 165°',
        );
      case CvExerciseModule.row:
        return const ExerciseFormCriteria(
          maxValidAngleDeg: 80.0,
          maxAngleInclusive: true,
          minValidDurationMs: 1200,
          maxValidDurationMs: 4500,
          fastDurationMsThreshold: 1200,
          angleMetricLabel: 'Góc khuỷu tay',
          criteriaDisplayText: 'Góc ≤ 80°',
          angleMetricLabelEn: 'Elbow angle',
          criteriaDisplayTextEn: 'Angle ≤ 80°',
        );
      case CvExerciseModule.facePull:
        return const ExerciseFormCriteria(
          maxValidAngleDeg: 85.0,
          maxAngleInclusive: true,
          minValidDurationMs: 1200,
          maxValidDurationMs: 4000,
          fastDurationMsThreshold: 1200,
          angleMetricLabel: 'Góc khuỷu tay',
          criteriaDisplayText: 'Góc ≤ 85°',
          angleMetricLabelEn: 'Elbow angle',
          criteriaDisplayTextEn: 'Angle ≤ 85°',
        );
      case CvExerciseModule.latPulldown:
      case null:
        return const ExerciseFormCriteria(
          maxValidAngleDeg: 45.0,
          maxAngleInclusive: false,
          minValidDurationMs: 2000,
          maxValidDurationMs: 3000,
          fastDurationMsThreshold: 2000,
          angleMetricLabel: 'Góc khuỷu tay',
          criteriaDisplayText: 'Góc < 45°',
          angleMetricLabelEn: 'Elbow angle',
          criteriaDisplayTextEn: 'Angle < 45°',
        );
    }
  }

  /// Formatted tempo window string, e.g. `2–3s` or `1.5–4.5s`.
  String get tempoDisplayText =>
      '${_formatDurationSec(minValidDurationMs)}–${_formatDurationSec(maxValidDurationMs)}s';

  static String _formatDurationSec(int ms) {
    if (ms % 1000 == 0) {
      return '${ms ~/ 1000}';
    }
    if (ms % 100 == 0) {
      return (ms / 1000.0).toStringAsFixed(1);
    }
    return (ms / 1000.0).toStringAsFixed(2);
  }
}

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

  /// Returns true if [rep] satisfies the standard form criteria for [module].
  ///
  /// When [maxValidElbowAngleDeg] is explicitly provided, uses `< maxValidElbowAngleDeg`
  /// for backward compatibility with existing callers/tests.
  static bool isRepStandardMet(
    LatPulldownRepEvent rep, {
    CvExerciseModule? module,
    double? maxValidElbowAngleDeg,
    int? minValidDurationMs,
    int? maxValidDurationMs,
  }) {
    if (module == CvExerciseModule.pullUp &&
        rep is PullUpRepEvent &&
        rep.isChinCleared == false) {
      return false;
    }
    if (module == CvExerciseModule.squat &&
        rep is SquatRepEvent &&
        rep.isBackStraight == false) {
      return false;
    }
    if (module == CvExerciseModule.pushUp &&
        rep is PushUpRepEvent &&
        rep.isPlankAligned == false) {
      return false;
    }
    if (module == CvExerciseModule.overheadPress &&
        rep is OverheadPressRepEvent &&
        rep.isBackVertical == false) {
      return false;
    }
    if (module == CvExerciseModule.bicepCurl &&
        rep is BicepCurlRepEvent &&
        (rep.isElbowPinned == false || rep.isTorsoStable == false)) {
      return false;
    }
    if (module == CvExerciseModule.plankHold &&
        rep is PlankHoldRepEvent &&
        rep.isAligned == false) {
      return false;
    }
    if (module == CvExerciseModule.row &&
        rep is RowRepEvent &&
        rep.isBackStable == false) {
      return false;
    }
    if (module == CvExerciseModule.facePull &&
        rep is FacePullRepEvent &&
        rep.isElbowHigh == false) {
      return false;
    }

    final criteria = ExerciseFormCriteria.forModule(module);
    final angleThreshold = maxValidElbowAngleDeg ?? criteria.maxValidAngleDeg;
    final angleInclusive =
        maxValidElbowAngleDeg != null ? false : criteria.maxAngleInclusive;
    final minDuration = minValidDurationMs ?? criteria.minValidDurationMs;
    final maxDuration = maxValidDurationMs ?? criteria.maxValidDurationMs;

    final bool angleMet;
    if (maxValidElbowAngleDeg == null && criteria.isMinAngleCriteria) {
      angleMet = angleInclusive
          ? rep.minElbowAngleDeg >= angleThreshold
          : rep.minElbowAngleDeg > angleThreshold;
    } else {
      angleMet = angleInclusive
          ? rep.minElbowAngleDeg <= angleThreshold
          : rep.minElbowAngleDeg < angleThreshold;
    }

    return angleMet &&
        rep.durationMs >= minDuration &&
        rep.durationMs <= maxDuration;
  }

  /// Computes a [CvFormSummary] from [reps] and [abortCount].
  ///
  /// LatPulldownRepEvent and PullUpRepEvent (which inherits LatPulldownRepEvent)
  /// are both supported.
  static CvFormSummary compute({
    required List<LatPulldownRepEvent> reps,
    int abortCount = 0,
    CvExerciseModule? module,
    double? maxValidElbowAngleDeg,
    int? minValidDurationMs,
    int? maxValidDurationMs,
    int? fastDurationMsThreshold,
  }) {
    final criteria = ExerciseFormCriteria.forModule(module);
    final effectiveFastThreshold =
        fastDurationMsThreshold ?? criteria.fastDurationMsThreshold;

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
        module: module,
        maxValidElbowAngleDeg: maxValidElbowAngleDeg,
        minValidDurationMs: minValidDurationMs,
        maxValidDurationMs: maxValidDurationMs,
      )) {
        validReps++;
      }
      if (rep.durationMs < effectiveFastThreshold) {
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
