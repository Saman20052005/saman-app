import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../presentation/tokens/saman_workout_tokens.dart';
import '../../domain/entities/exercise_cv_state.dart';
import '../../domain/entities/pose_landmark.dart';
import '../../domain/services/workout_cv_exercise_registry.dart';

/// Pure-Dart Face-ID style framing guidance evaluator for pre-workout setup.
///
/// Evaluates tracking state and normalized pose landmarks in strict priority:
/// 1. Multiple people in frame (`multi_person`)
/// 2. Subject missing / lost (`lost_body`)
/// 3. Low average visibility of key joints (`low_light`)
/// 4. Edge clipping or missing legs/full body for the exercise (`step_back`)
/// 5. Unclear shoulder-to-hip alignment (`rotate_body`)
/// 6. Ready for 3-2-1 hold steady countdown (`hold_steady`)
class CvCalibrationGuidance {
  const CvCalibrationGuidance._();

  static const List<int> _coreJointIndices = <int>[
    PoseLandmark.leftShoulder,
    PoseLandmark.rightShoulder,
    PoseLandmark.leftElbow,
    PoseLandmark.rightElbow,
    PoseLandmark.leftHip,
    PoseLandmark.rightHip,
    PoseLandmark.leftKnee,
    PoseLandmark.rightKnee,
  ];

  static const List<int> _edgeCheckJointIndices = <int>[
    PoseLandmark.leftShoulder,
    PoseLandmark.rightShoulder,
    PoseLandmark.leftElbow,
    PoseLandmark.rightElbow,
    PoseLandmark.leftWrist,
    PoseLandmark.rightWrist,
    PoseLandmark.leftHip,
    PoseLandmark.rightHip,
    PoseLandmark.leftKnee,
    PoseLandmark.rightKnee,
    PoseLandmark.leftAnkle,
    PoseLandmark.rightAnkle,
  ];

  static const Set<CvExerciseModule> _legVisibilityModules = <CvExerciseModule>{
    CvExerciseModule.squat,
    CvExerciseModule.hipHinge,
    CvExerciseModule.hipThrust,
    CvExerciseModule.legExtension,
    CvExerciseModule.legCurl,
  };

  static const Set<CvExerciseModule> _fullBodyModules = <CvExerciseModule>{
    CvExerciseModule.pushUp,
    CvExerciseModule.plankHold,
  };

  /// Returns `(cueKey, localizedHeadline)` for the current framing state.
  static (String cueKey, String headline) resolve({
    required TrackingStatus trackingStatus,
    required int posesDetected,
    required List<PoseLandmark> landmarks,
    CvExerciseModule? exerciseModule,
    bool isVietnamese = true,
  }) {
    // 1. Multiple people
    if (trackingStatus == TrackingStatus.multiplePeople || posesDetected > 1) {
      return (
        'multi_person',
        isVietnamese
            ? 'Có người khác trong khung hình, tạm dừng đếm'
            : 'Another person is in frame, pausing count',
      );
    }

    final isReady =
        trackingStatus == TrackingStatus.detecting && posesDetected == 1;

    // 2. Lost / no body landmarks
    if (trackingStatus == TrackingStatus.lost ||
        (landmarks.isEmpty && !isReady)) {
      return (
        'lost_body',
        isVietnamese ? 'Bước lại vào khung hình' : 'Step back into the frame',
      );
    }

    if (landmarks.isNotEmpty) {
      final byIndex = <int, PoseLandmark>{
        for (final lm in landmarks) lm.index: lm,
      };

      // 3. Low light / low visibility (< 0.50 average visibility on core joints)
      final coreJoints = <PoseLandmark>[
        for (final idx in _coreJointIndices)
          if (byIndex.containsKey(idx)) byIndex[idx]!,
      ];
      final visibilityPool = coreJoints.isNotEmpty ? coreJoints : landmarks;
      final avgVisibility = visibilityPool.fold<double>(
            0.0,
            (sum, lm) => sum + lm.visibility,
          ) /
          visibilityPool.length;
      if (avgVisibility < 0.50) {
        return (
          'low_light',
          isVietnamese
              ? 'Hơi tối hoặc mờ, hãy tăng ánh sáng'
              : 'Low lighting detected, please add more light',
        );
      }

      // 4. Clipped near top/bottom frame edges or missing legs / full body
      if (_hasEdgeClipping(byIndex, landmarks) ||
          _isMissingRequiredBodyCoverage(byIndex, exerciseModule)) {
        return (
          'step_back',
          isVietnamese
              ? 'Lùi ra xa hơn để thấy cả chân'
              : 'Step back further to show your legs',
        );
      }

      // 5. Unclear shoulder-hip axis
      if (!_hasClearShoulderHipAxis(byIndex)) {
        return (
          'rotate_body',
          isVietnamese
              ? 'Xoay nhẹ người để thấy rõ vai và hông'
              : 'Turn slightly to show shoulders and hips',
        );
      }
    }

    // 6. Ready for 3-2-1 countdown
    if (isReady) {
      return (
        'hold_steady',
        isVietnamese
            ? 'Giữ yên... Chuẩn bị bắt đầu'
            : 'Hold steady... Get ready',
      );
    }

    return (
      'rotate_body',
      isVietnamese
          ? 'Xoay nhẹ người để thấy rõ vai và hông'
          : 'Turn slightly to show shoulders and hips',
    );
  }

  static bool _hasEdgeClipping(
    Map<int, PoseLandmark> byIndex,
    List<PoseLandmark> landmarks,
  ) {
    final relevant = <PoseLandmark>[
      for (final idx in _edgeCheckJointIndices)
        if (byIndex.containsKey(idx)) byIndex[idx]!,
    ];
    final pool = relevant.isNotEmpty ? relevant : landmarks;
    for (final lm in pool) {
      if (lm.visibility >= 0.50 && (lm.y > 0.94 || lm.y < 0.05)) {
        return true;
      }
    }
    return false;
  }

  static bool _isMissingRequiredBodyCoverage(
    Map<int, PoseLandmark> byIndex,
    CvExerciseModule? module,
  ) {
    if (module == null) return false;

    bool visible(int index) {
      final lm = byIndex[index];
      return lm != null && lm.visibility >= 0.50;
    }

    if (_legVisibilityModules.contains(module)) {
      final leftLegOk =
          visible(PoseLandmark.leftKnee) && visible(PoseLandmark.leftAnkle);
      final rightLegOk =
          visible(PoseLandmark.rightKnee) && visible(PoseLandmark.rightAnkle);
      return !(leftLegOk || rightLegOk);
    }

    if (_fullBodyModules.contains(module)) {
      final leftFullOk = visible(PoseLandmark.leftShoulder) &&
          visible(PoseLandmark.leftHip) &&
          visible(PoseLandmark.leftAnkle);
      final rightFullOk = visible(PoseLandmark.rightShoulder) &&
          visible(PoseLandmark.rightHip) &&
          visible(PoseLandmark.rightAnkle);
      return !(leftFullOk || rightFullOk);
    }

    return false;
  }

  static bool _hasClearShoulderHipAxis(Map<int, PoseLandmark> byIndex) {
    final lShoulder = byIndex[PoseLandmark.leftShoulder];
    final rShoulder = byIndex[PoseLandmark.rightShoulder];
    final lHip = byIndex[PoseLandmark.leftHip];
    final rHip = byIndex[PoseLandmark.rightHip];

    final hasLeftShoulder = lShoulder != null && lShoulder.visibility >= 0.55;
    final hasRightShoulder = rShoulder != null && rShoulder.visibility >= 0.55;
    final hasLeftHip = lHip != null && lHip.visibility >= 0.55;
    final hasRightHip = rHip != null && rHip.visibility >= 0.55;

    if ((!hasLeftShoulder && !hasRightShoulder) ||
        (!hasLeftHip && !hasRightHip)) {
      return false;
    }

    final shoulder = hasLeftShoulder && hasRightShoulder
        ? Offset(
            (lShoulder.x + rShoulder.x) / 2,
            (lShoulder.y + rShoulder.y) / 2,
          )
        : Offset(
            (hasLeftShoulder ? lShoulder : rShoulder)!.x,
            (hasLeftShoulder ? lShoulder : rShoulder)!.y,
          );
    final hip = hasLeftHip && hasRightHip
        ? Offset((lHip.x + rHip.x) / 2, (lHip.y + rHip.y) / 2)
        : Offset(
            (hasLeftHip ? lHip : rHip)!.x,
            (hasLeftHip ? lHip : rHip)!.y,
          );

    final dx = shoulder.dx - hip.dx;
    final dy = shoulder.dy - hip.dy;
    final torsoSpan = math.sqrt(dx * dx + dy * dy);
    return torsoSpan >= 0.08;
  }
}

/// Framing & readiness overlay displayed in live camera mode prior to rep counting.
///
/// Renders corner framing brackets, a low-opacity posture silhouette guide,
/// Face-ID style step-by-step setup guidance, recommended camera angle hints,
/// a 3-2-1 stability countdown when exactly one subject is cleanly tracked,
/// and a skip button for manual override.
class CvCalibrationOverlay extends StatefulWidget {
  final TrackingStatus trackingStatus;
  final int posesDetected;
  final String? cameraAngleHint;
  final VoidCallback onCalibrated;
  final VoidCallback? onSkip;
  final ValueChanged<int>? onCountdownTick;
  final bool isVietnamese;
  final int initialCountdownSeconds;
  final List<PoseLandmark> landmarks;
  final CvExerciseModule? exerciseModule;
  final void Function(String cueKey, String message)? onGuidanceCue;

  const CvCalibrationOverlay({
    super.key,
    required this.trackingStatus,
    required this.posesDetected,
    this.cameraAngleHint,
    required this.onCalibrated,
    this.onSkip,
    this.onCountdownTick,
    this.isVietnamese = true,
    this.initialCountdownSeconds = 3,
    this.landmarks = const [],
    this.exerciseModule,
    this.onGuidanceCue,
  });

  @override
  State<CvCalibrationOverlay> createState() => _CvCalibrationOverlayState();
}

class _CvCalibrationOverlayState extends State<CvCalibrationOverlay> {
  Timer? _countdownTimer;
  late int _secondsRemaining;
  bool _hasCompleted = false;
  String? _lastGuidanceCueKey;

  bool get _isReadyForCountdown =>
      widget.trackingStatus == TrackingStatus.detecting &&
      widget.posesDetected == 1;

  (String cueKey, String headline) _resolveGuidance() {
    return CvCalibrationGuidance.resolve(
      trackingStatus: widget.trackingStatus,
      posesDetected: widget.posesDetected,
      landmarks: widget.landmarks,
      exerciseModule: widget.exerciseModule,
      isVietnamese: widget.isVietnamese,
    );
  }

  void _emitGuidanceIfChanged() {
    if (_hasCompleted) return;
    final (cueKey, headline) = _resolveGuidance();
    if (_isReadyForCountdown && cueKey == 'hold_steady') {
      _lastGuidanceCueKey = cueKey;
      return;
    }
    if (cueKey != _lastGuidanceCueKey) {
      _lastGuidanceCueKey = cueKey;
      widget.onGuidanceCue?.call(cueKey, headline);
    }
  }

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.initialCountdownSeconds;
    _emitGuidanceIfChanged();
    if (_isReadyForCountdown) {
      _startCountdown();
    }
  }

  @override
  void didUpdateWidget(covariant CvCalibrationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasCompleted) return;

    _emitGuidanceIfChanged();

    if (_isReadyForCountdown) {
      if (_countdownTimer == null) {
        _startCountdown();
      }
    } else {
      _resetCountdown();
    }
  }

  void _startCountdown() {
    if (_hasCompleted || _countdownTimer != null) return;
    _secondsRemaining = widget.initialCountdownSeconds;
    widget.onCountdownTick?.call(_secondsRemaining);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _hasCompleted) {
        timer.cancel();
        return;
      }
      if (!_isReadyForCountdown) {
        _resetCountdown();
        return;
      }

      if (_secondsRemaining <= 1) {
        timer.cancel();
        _countdownTimer = null;
        _hasCompleted = true;
        setState(() {
          _secondsRemaining = 0;
        });
        widget.onCalibrated();
      } else {
        final nextValue = _secondsRemaining - 1;
        setState(() {
          _secondsRemaining = nextValue;
        });
        widget.onCountdownTick?.call(nextValue);
      }
    });
  }

  void _resetCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_secondsRemaining != widget.initialCountdownSeconds && mounted) {
      setState(() {
        _secondsRemaining = widget.initialCountdownSeconds;
      });
    } else {
      _secondsRemaining = widget.initialCountdownSeconds;
    }
  }

  void _handleSkip() {
    if (_hasCompleted) return;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _hasCompleted = true;
    if (widget.onSkip != null) {
      widget.onSkip!();
    } else {
      widget.onCalibrated();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    super.dispose();
  }

  Color _accentColor(String cueKey) {
    if (_isReadyForCountdown && cueKey == 'hold_steady') {
      return SamanWorkoutTokens.emeraldAccent;
    }
    if (cueKey == 'multi_person' || cueKey == 'lost_body') {
      return SamanWorkoutTokens.crimsonAccent;
    }
    return SamanWorkoutTokens.amberAccent;
  }

  IconData _statusIcon(String cueKey) {
    switch (cueKey) {
      case 'hold_steady':
        return Icons.check_circle_outline_rounded;
      case 'multi_person':
        return Icons.people_outline_rounded;
      case 'lost_body':
        return Icons.person_off_outlined;
      case 'low_light':
        return Icons.wb_sunny_outlined;
      case 'step_back':
        return Icons.zoom_out_map_rounded;
      case 'rotate_body':
        return Icons.screen_rotation_alt_rounded;
      default:
        return Icons.center_focus_strong_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final (cueKey, headline) = _resolveGuidance();
    final accent = _accentColor(cueKey);
    final isReady = _isReadyForCountdown;
    final hint = widget.cameraAngleHint?.trim();

    return ColoredBox(
      color: const Color(0x5C0C0D0E),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 74, 20, 174),
        child: Column(
          children: [
            // Top guidance card separated above the camera framing brackets
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xCC121316),
                  borderRadius: BorderRadius.circular(
                    SamanWorkoutTokens.radiusMd,
                  ),
                  border: Border.all(
                    color: accent.withOpacity(0.45),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _statusIcon(cueKey),
                          size: 16,
                          color: accent,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            headline,
                            key: const ValueKey(
                              'workout_cv_calibration_headline',
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              color: accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hint != null && hint.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        hint,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          color: SamanWorkoutTokens.textSub,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Dedicated camera framing viewport: brackets + silhouette + countdown
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _CalibrationFramePainter(
                        bracketColor: accent,
                        silhouetteColor: isReady
                            ? SamanWorkoutTokens.emeraldAccent
                            : SamanWorkoutTokens.textPrimary,
                      ),
                    ),
                  ),
                  Center(
                    child: isReady && _secondsRemaining > 0
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Container(
                              width: 104,
                              height: 104,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xCC0C0D0E),
                                border: Border.all(
                                  color: SamanWorkoutTokens.emeraldAccent,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: SamanWorkoutTokens.emeraldAccent
                                        .withOpacity(0.28),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Text(
                                '$_secondsRemaining',
                                key: const ValueKey(
                                  'workout_cv_calibration_countdown',
                                ),
                                style: const TextStyle(
                                  fontFamily: 'Manrope',
                                  color: SamanWorkoutTokens.textPrimary,
                                  fontSize: 52,
                                  fontWeight: FontWeight.w800,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Skip calibration action separated below the framing brackets
            Align(
              alignment: Alignment.bottomCenter,
              child: OutlinedButton.icon(
                key: const ValueKey('workout_cv_calibration_skip_button'),
                onPressed: _handleSkip,
                icon: const Icon(Icons.skip_next_rounded, size: 18),
                label: Text(
                  widget.isVietnamese ? 'Bỏ qua' : 'Skip',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SamanWorkoutTokens.textPrimary,
                  backgroundColor: const Color(0xB8121316),
                  side: const BorderSide(color: Colors.white30),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      SamanWorkoutTokens.radiusPill,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalibrationFramePainter extends CustomPainter {
  final Color bracketColor;
  final Color silhouetteColor;

  const _CalibrationFramePainter({
    required this.bracketColor,
    required this.silhouetteColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final frameHeight = size.height * 0.94;
    final frameWidth = math.min(size.width * 0.88, frameHeight * 0.72);
    final left = (size.width - frameWidth) / 2;
    final top = (size.height - frameHeight) / 2;
    final rect = Rect.fromLTWH(left, top, frameWidth, frameHeight);

    _drawCornerBrackets(canvas, rect);
    _drawPostureSilhouette(canvas, rect);
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect) {
    final bracketLen =
        (math.min(rect.width, rect.height) * 0.14).clamp(16.0, 36.0);
    final paint = Paint()
      ..color = bracketColor.withOpacity(0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top + bracketLen)
        ..lineTo(rect.left, rect.top)
        ..lineTo(rect.left + bracketLen, rect.top),
      paint,
    );

    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - bracketLen, rect.top)
        ..lineTo(rect.right, rect.top)
        ..lineTo(rect.right, rect.top + bracketLen),
      paint,
    );

    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.bottom - bracketLen)
        ..lineTo(rect.left, rect.bottom)
        ..lineTo(rect.left + bracketLen, rect.bottom),
      paint,
    );

    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - bracketLen, rect.bottom)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.right, rect.bottom - bracketLen),
      paint,
    );
  }

  void _drawPostureSilhouette(Canvas canvas, Rect rect) {
    final cx = rect.center.dx;
    final h = rect.height;
    final w = rect.width;

    final fillPaint = Paint()
      ..color = silhouetteColor.withOpacity(0.20)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = silhouetteColor.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Head
    final headRadius = math.min(w * 0.11, h * 0.062);
    final headCenter = Offset(cx, rect.top + h * 0.18);
    canvas.drawCircle(headCenter, headRadius, fillPaint);
    canvas.drawCircle(headCenter, headRadius, strokePaint);

    // Torso, shoulders, arms & legs silhouette
    final shoulderY = rect.top + h * 0.28;
    final shoulderHalfW = w * 0.23;
    final elbowY = rect.top + h * 0.44;
    final wristY = rect.top + h * 0.56;
    final waistY = rect.top + h * 0.52;
    final hipHalfW = w * 0.14;
    final kneeY = rect.top + h * 0.72;
    final ankleY = rect.top + h * 0.89;
    final legGapHalfW = w * 0.04;
    final legOuterHalfW = w * 0.14;

    final bodyPath = Path()
      // Left shoulder
      ..moveTo(cx - shoulderHalfW * 0.42, rect.top + h * 0.25)
      ..quadraticBezierTo(
        cx - shoulderHalfW,
        shoulderY,
        cx - shoulderHalfW * 1.15,
        elbowY,
      )
      ..lineTo(cx - shoulderHalfW * 1.12, wristY)
      ..quadraticBezierTo(
        cx - shoulderHalfW * 0.88,
        wristY + h * 0.015,
        cx - shoulderHalfW * 0.80,
        elbowY,
      )
      ..lineTo(cx - hipHalfW, waistY)
      // Left leg
      ..lineTo(cx - legOuterHalfW, kneeY)
      ..lineTo(cx - legOuterHalfW * 0.92, ankleY)
      ..lineTo(cx - legGapHalfW, ankleY)
      ..lineTo(cx - legGapHalfW * 0.7, rect.top + h * 0.58)
      // Crotch center
      ..lineTo(cx + legGapHalfW * 0.7, rect.top + h * 0.58)
      // Right leg
      ..lineTo(cx + legGapHalfW, ankleY)
      ..lineTo(cx + legOuterHalfW * 0.92, ankleY)
      ..lineTo(cx + legOuterHalfW, kneeY)
      ..lineTo(cx + hipHalfW, waistY)
      // Right arm
      ..lineTo(cx + shoulderHalfW * 0.80, elbowY)
      ..quadraticBezierTo(
        cx + shoulderHalfW * 0.88,
        wristY + h * 0.015,
        cx + shoulderHalfW * 1.12,
        wristY,
      )
      ..lineTo(cx + shoulderHalfW * 1.15, elbowY)
      ..quadraticBezierTo(
        cx + shoulderHalfW,
        shoulderY,
        cx + shoulderHalfW * 0.42,
        rect.top + h * 0.25,
      )
      ..close();

    canvas.drawPath(bodyPath, fillPaint);
    canvas.drawPath(bodyPath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _CalibrationFramePainter oldDelegate) {
    return oldDelegate.bracketColor != bracketColor ||
        oldDelegate.silhouetteColor != silhouetteColor;
  }
}
