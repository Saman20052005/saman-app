import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../presentation/tokens/saman_workout_tokens.dart';
import '../../domain/entities/exercise_cv_state.dart';
import '../../domain/services/cv_form_summary_calculator.dart';
import '../../domain/services/cv_hardware_radar_service.dart';
import '../../domain/services/cv_tts_coach.dart';
import '../../domain/services/lat_pulldown_baseline.dart';
import '../../domain/services/workout_cv_exercise_registry.dart';
import '../../domain/services/workout_cv_motion_features.dart';
import '../controllers/workout_cv_controller.dart';
import '../widgets/cv_calibration_overlay.dart';
import '../widgets/cv_exercise_guide_sheet.dart';
import '../widgets/cv_hardware_radar_sheet.dart';
import '../widgets/pose_skeleton_painter.dart';
import '../workout_cv_replay_trial.dart';
import 'workout_cv_result_screen.dart';

class WorkoutCvScreen extends ConsumerStatefulWidget {
  final String exerciseId;
  final String exerciseSlug;
  final String exerciseName;
  final String? videoPath;
  final CvTtsCoach? ttsCoach;
  final CvHardwareRadarService? hardwareRadarService;
  final bool? autoCheckHardwareRadar;

  const WorkoutCvScreen({
    super.key,
    required this.exerciseId,
    required this.exerciseSlug,
    required this.exerciseName,
    this.videoPath,
    this.ttsCoach,
    this.hardwareRadarService,
    this.autoCheckHardwareRadar,
  });

  @override
  ConsumerState<WorkoutCvScreen> createState() => _WorkoutCvScreenState();
}

class _WorkoutCvScreenState extends ConsumerState<WorkoutCvScreen>
    with WidgetsBindingObserver {
  late final CvTtsCoach _ttsCoach;
  late final bool _ownsTtsCoach;
  late final CvHardwareRadarService _hardwareRadarService;
  late bool _isCalibrated;
  bool _hasCheckedHardwareRadar = false;
  Color? _borderPulseColor;
  Timer? _borderPulseTimer;

  bool get _useReplayTrial =>
      shouldUseWorkoutCvReplayTrial(exerciseSlug: widget.exerciseSlug);

  bool get _hasUploadedVideo =>
      widget.videoPath != null && widget.videoPath!.isNotEmpty;

  bool get _supportsCamera =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isVietnamese =>
      Localizations.maybeLocaleOf(context)?.languageCode == 'vi';

  Future<void> _bootstrapSession() async {
    final shouldAutoCheck = widget.autoCheckHardwareRadar ??
        (!kIsWeb &&
            Platform.isAndroid &&
            !_hasUploadedVideo &&
            !_useReplayTrial);
    if (shouldAutoCheck && !_hasCheckedHardwareRadar) {
      _hasCheckedHardwareRadar = true;
      final shouldShow = await _hardwareRadarService.shouldShowRadarSheet();
      if (!mounted) return;
      if (shouldShow) {
        await showCvHardwareRadarSheet(
          context,
          service: _hardwareRadarService,
          isVietnamese: _isVietnamese,
        );
        if (!mounted) return;
      }
    }
    await _initializeSession();
  }

  Future<void> _initializeSession() async {
    if (!_supportsCamera) return;
    await ref.read(workoutCvControllerProvider.notifier).initialize(
          exerciseId: widget.exerciseId,
          exerciseSlug: widget.exerciseSlug,
          videoReplay: _useReplayTrial,
          videoPath: widget.videoPath,
        );
  }

  Future<void> _openExerciseGuideSheet() async {
    await showCvExerciseGuideSheet(
      context,
      exerciseId: widget.exerciseId,
      exerciseSlug: widget.exerciseSlug,
      exerciseName: widget.exerciseName,
      isVietnamese: _isVietnamese,
    );
  }

  Future<void> _openHardwareRadarSheet() async {
    await showCvHardwareRadarSheet(
      context,
      service: _hardwareRadarService,
      isVietnamese: _isVietnamese,
    );
  }

  void _triggerBorderPulse(Color color, Duration duration) {
    _borderPulseTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _borderPulseColor = color;
    });
    _borderPulseTimer = Timer(duration, () {
      _borderPulseTimer = null;
      if (!mounted) return;
      setState(() {
        _borderPulseColor = null;
      });
    });
  }

  Color _resolveStatusBorderColor(ExerciseCvState cvState) {
    switch (cvState.trackingStatus) {
      case TrackingStatus.lost:
      case TrackingStatus.multiplePeople:
      case TrackingStatus.error:
      case TrackingStatus.permissionDenied:
        return SamanWorkoutTokens.crimsonAccent;
      case TrackingStatus.needsSetup:
        return SamanWorkoutTokens.amberAccent;
      case TrackingStatus.detecting:
        return _borderPulseColor ?? SamanWorkoutTokens.emeraldAccent;
      case TrackingStatus.uninitialized:
        return Colors.transparent;
    }
  }

  @override
  void initState() {
    super.initState();
    _ownsTtsCoach = widget.ttsCoach == null;
    final nativeSource = ref.read(workoutCvNativeSourceProvider);
    _ttsCoach = widget.ttsCoach ??
        CvTtsCoach(
          onRequestAudioFocus: nativeSource.requestAudioFocus,
          onAbandonAudioFocus: nativeSource.abandonAudioFocus,
        );
    _hardwareRadarService =
        widget.hardwareRadarService ?? CvHardwareRadarService();
    _isCalibrated = _useReplayTrial || _hasUploadedVideo;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_bootstrapSession());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode =
        Localizations.maybeLocaleOf(context)?.languageCode ?? 'vi';
    unawaited(_ttsCoach.updateLocale(languageCode));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final notifier = ref.read(workoutCvControllerProvider.notifier);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_ttsCoach.stop());
      notifier.stop();
    } else if (state == AppLifecycleState.resumed) {
      _initializeSession();
    }
  }

  @override
  void dispose() {
    _borderPulseTimer?.cancel();
    _borderPulseTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_ttsCoach.stop());
    if (_ownsTtsCoach) {
      unawaited(_ttsCoach.dispose());
    }
    super.dispose();
  }

  String _formCorrectionCueForModule(
    CvExerciseModule? module, {
    required bool isVietnamese,
  }) {
    switch (module) {
      case CvExerciseModule.squat:
        return isVietnamese ? 'Xuống sâu hơn nữa' : 'Go deeper';
      case CvExerciseModule.pullUp:
      case CvExerciseModule.latPulldown:
        return isVietnamese
            ? 'Kéo sát người hơn'
            : 'Pull closer to your chest';
      case CvExerciseModule.pushUp:
        return isVietnamese
            ? 'Xuống sâu hơn và giữ lưng thẳng'
            : 'Go lower and keep your back straight';
      case CvExerciseModule.bicepCurl:
        return isVietnamese
            ? 'Giữ cùi chỏ sát sườn'
            : 'Keep your elbows pinned';
      case CvExerciseModule.overheadPress:
        return isVietnamese
            ? 'Đẩy thẳng tay qua đầu'
            : 'Press all the way overhead';
      case CvExerciseModule.hipHinge:
        return isVietnamese
            ? 'Đẩy hông ra sau và giữ thẳng lưng'
            : 'Hinge at the hips and keep your back flat';
      case CvExerciseModule.hipThrust:
        return isVietnamese
            ? 'Đẩy hông lên cao hết biên độ'
            : 'Drive your hips fully to the top';
      case CvExerciseModule.tricepExtension:
        return isVietnamese
            ? 'Duỗi thẳng hết cánh tay và cố định cùi chỏ'
            : 'Extend fully and keep your elbows still';
      case CvExerciseModule.lateralRaise:
        return isVietnamese
            ? 'Nâng tay ngang vai có kiểm soát'
            : 'Raise smoothly to shoulder height';
      case CvExerciseModule.legExtension:
      case CvExerciseModule.legCurl:
        return isVietnamese
            ? 'Hoàn thành hết biên độ gối'
            : 'Complete the full knee range of motion';
      case CvExerciseModule.plankHold:
        return isVietnamese
            ? 'Giữ hông thẳng hàng với vai'
            : 'Keep your hips aligned with your shoulders';
      case CvExerciseModule.row:
      case CvExerciseModule.facePull:
        return isVietnamese
            ? 'Kéo hết biên độ và siết bả vai'
            : 'Pull through full range and squeeze your shoulder blades';
      case null:
        return isVietnamese
            ? 'Điều chỉnh biên độ và giữ chuẩn tư thế'
            : 'Adjust range of motion and keep good form';
    }
  }

  void _handleCvStateChange(ExerciseCvState? previous, ExerciseCvState next) {
    final isVi = _isVietnamese;
    final isVideoReplay = next.sourceMode == 'video_replay';
    final isCalibrated = isVideoReplay || _isCalibrated;

    if (previous != null &&
        previous.sourceMode == 'video_replay' &&
        next.sourceMode == 'camera' &&
        _isCalibrated) {
      setState(() {
        _isCalibrated = false;
      });
    }

    final prevReps = previous?.completedReps ?? 0;
    if (next.completedReps == 0 && prevReps > 0) {
      _ttsCoach.resetSessionTracking();
    }

    if (next.trackingStatus == TrackingStatus.multiplePeople) {
      unawaited(
        _ttsCoach.speakUrgent(
          'multi_person',
          isVi
              ? 'Có người khác trong khung hình, tạm dừng đếm'
              : 'Another person is in frame, pausing count',
        ),
      );
    } else if (next.trackingStatus == TrackingStatus.lost &&
        next.isCameraActive) {
      unawaited(
        _ttsCoach.speakUrgent(
          'lost_body',
          isVi ? 'Bước lại vào khung hình' : 'Step back into the frame',
        ),
      );
    } else if (next.trackingStatus == TrackingStatus.needsSetup &&
        next.isCameraActive &&
        isCalibrated) {
      unawaited(
        _ttsCoach.speakFormCue(
          'framing',
          isVi
              ? 'Điều chỉnh khung hình để thấy rõ khớp'
              : 'Adjust framing to show key joints',
        ),
      );
    }

    if (!isCalibrated) return;

    final module = WorkoutCvExerciseRegistry.resolveModule(
      id: next.exerciseId.isNotEmpty ? next.exerciseId : widget.exerciseId,
      slug:
          next.exerciseSlug.isNotEmpty ? next.exerciseSlug : widget.exerciseSlug,
    );
    final isHoldExercise = module == CvExerciseModule.plankHold;

    if (module == CvExerciseModule.pushUp &&
        next.detectedViewAngle == CameraViewAngle.frontal &&
        isCalibrated) {
      _triggerBorderPulse(
        SamanWorkoutTokens.amberAccent,
        const Duration(milliseconds: 1800),
      );
      unawaited(
        _ttsCoach.speakFormCue(
          'pushup_frontal_warning',
          isVi
              ? 'Góc chính diện khó đo độ sâu, hãy đặt máy chếch nghiêng 45 độ'
              : 'Frontal angle limits depth tracking, please place camera at a 45 degree angle',
        ),
      );
    }

    if (next.completedReps > prevReps) {
      unawaited(
        _ttsCoach.speakRepCount(
          next.completedReps,
          isHoldSecond: isHoldExercise,
        ),
      );

      final prevSummary = previous?.formSummary;
      final nextSummary = next.formSummary;
      final prevFastReps = prevSummary?.fastReps ?? 0;
      final prevValidReps = prevSummary?.validReps ?? 0;

      if (nextSummary.fastReps > prevFastReps) {
        _triggerBorderPulse(
          SamanWorkoutTokens.amberAccent,
          const Duration(milliseconds: 1800),
        );
        unawaited(
          _ttsCoach.speakFormCue(
            'tempo_fast',
            isVi ? 'Chậm lại một chút' : 'Slow down a bit',
          ),
        );
      } else if (nextSummary.validReps == prevValidReps) {
        _triggerBorderPulse(
          SamanWorkoutTokens.amberAccent,
          const Duration(milliseconds: 1800),
        );
        unawaited(
          _ttsCoach.speakFormCue(
            'form_depth_${module?.name ?? 'generic'}',
            _formCorrectionCueForModule(module, isVietnamese: isVi),
          ),
        );
      } else {
        _triggerBorderPulse(
          SamanWorkoutTokens.emeraldAccent,
          const Duration(milliseconds: 900),
        );
      }
    } else if (next.abortCount > (previous?.abortCount ?? 0)) {
      _triggerBorderPulse(
        SamanWorkoutTokens.amberAccent,
        const Duration(milliseconds: 1800),
      );
      unawaited(
        _ttsCoach.speakFormCue(
          'form_abort_${module?.name ?? 'generic'}',
          _formCorrectionCueForModule(module, isVietnamese: isVi),
        ),
      );
    }
  }

  void _handleCalibrationCompleted() {
    if (!mounted || _isCalibrated) return;
    setState(() {
      _isCalibrated = true;
    });
    unawaited(
      _ttsCoach.speakCountdown(_isVietnamese ? 'Bắt đầu!' : 'Start!'),
    );
  }

  void _handleCalibrationSkipped() {
    if (!mounted || _isCalibrated) return;
    setState(() {
      _isCalibrated = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ExerciseCvState>(
      workoutCvControllerProvider,
      _handleCvStateChange,
    );

    final isVi = Localizations.maybeLocaleOf(context)?.languageCode == 'vi';
    final t = SamanWorkoutTokens.of(context);
    final cvState = ref.watch(workoutCvControllerProvider);
    final module = WorkoutCvExerciseRegistry.resolveModule(
      id: cvState.exerciseId.isNotEmpty
          ? cvState.exerciseId
          : widget.exerciseId,
      slug: cvState.exerciseSlug.isNotEmpty
          ? cvState.exerciseSlug
          : widget.exerciseSlug,
    );
    final cameraAngleHint = _cameraAngleHintForModule(
      module,
      isVietnamese: isVi,
    );
    final showCalibrationOverlay = cvState.sourceMode == 'camera' &&
        !_isCalibrated &&
        cvState.isCameraActive &&
        cvState.trackingStatus != TrackingStatus.permissionDenied &&
        cvState.trackingStatus != TrackingStatus.error;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Camera View Layer
            if (cvState.trackingStatus == TrackingStatus.permissionDenied)
              _buildPermissionDeniedView(isVi, t)
            else if (!kIsWeb && Platform.isAndroid && cvState.isCameraActive)
              const AndroidView(
                viewType: 'workout_camera_view',
                creationParamsCodec: StandardMessageCodec(),
              )
            else
              _buildNonAndroidPlaceholder(isVi),

            // 2. Pose Skeleton Overlay Layer
            if (cvState.landmarks.isNotEmpty &&
                cvState.trackingStatus != TrackingStatus.permissionDenied)
              Positioned.fill(
                child: CustomPaint(
                  painter: PoseSkeletonPainter(
                    landmarks: cvState.landmarks,
                    trackingStatus: cvState.trackingStatus,
                    isSyncValid: cvState.isSyncValid,
                  ),
                ),
              ),

            // 2.5. Live Camera Calibration Overlay Layer (skipped in video_replay)
            if (showCalibrationOverlay)
              Positioned.fill(
                child: CvCalibrationOverlay(
                  trackingStatus: cvState.trackingStatus,
                  posesDetected: cvState.posesDetected,
                  landmarks: cvState.landmarks,
                  exerciseModule: module,
                  cameraAngleHint: cameraAngleHint,
                  isVietnamese: isVi,
                  onGuidanceCue: (cueKey, message) {
                    if ((cueKey == 'multi_person' &&
                            cvState.trackingStatus ==
                                TrackingStatus.multiplePeople) ||
                        (cueKey == 'lost_body' &&
                            cvState.trackingStatus == TrackingStatus.lost)) {
                      return;
                    }
                    unawaited(_ttsCoach.speakCalibrationCue(cueKey, message));
                  },
                  onCountdownTick: (seconds) {
                    final speech = seconds == 3
                        ? (isVi ? 'Giữ yên, 3' : 'Hold steady, 3')
                        : '$seconds';
                    unawaited(_ttsCoach.speakCountdown(speech));
                  },
                  onCalibrated: _handleCalibrationCompleted,
                  onSkip: _handleCalibrationSkipped,
                ),
              ),

            // 2.75. Visual 4px Status Border Layer (Green / Amber / Red)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  key: const ValueKey('workout_cv_status_border'),
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _resolveStatusBorderColor(cvState),
                      width: 4.0,
                    ),
                  ),
                ),
              ),
            ),

            // 3. Header & Controls Layer
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: _buildHeader(cvState, isVi: isVi, t: t),
            ),

            // 4. Bottom Info & Telemetry Layer
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _buildBottomTelemetry(
                cvState,
                isVi: isVi,
                t: t,
                hideCameraHint: showCalibrationOverlay,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    ExerciseCvState cvState, {
    required bool isVi,
    required SamanWorkoutPalette t,
  }) {
    final overlayButtonBg = (t.isDark ? t.canvas : SamanWorkoutTokens.canvas)
        .withOpacity(0.65);
    final subtitleText = cvState.sourceMode == 'video_replay'
        ? (_hasUploadedVideo
            ? (isVi ? 'Phân tích video' : 'Video Analysis')
            : (isVi ? 'Replay thử nghiệm • phát chậm' : 'Trial Replay · Slow'))
        : (_supportsCamera
            ? (isVi ? 'Camera trực tiếp' : 'Live Camera')
            : (isVi ? 'Chỉ hỗ trợ Android' : 'Android only'));

    final compactButtonStyle = IconButton.styleFrom(
      backgroundColor: overlayButtonBg,
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(34, 34),
      padding: const EdgeInsets.all(6),
    );

    return Row(
      children: [
        IconButton(
          key: const ValueKey('workout_cv_close_button'),
          tooltip: isVi ? 'Đóng' : 'Close',
          icon: const Icon(Icons.close, color: Colors.white, size: 22),
          onPressed: () => Navigator.of(context).pop(),
          style: compactButtonStyle,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.exerciseName,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  subtitleText,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        if (_useReplayTrial || _hasUploadedVideo) ...[
          IconButton(
            key: const ValueKey('workout_cv_switch_replay_button'),
            tooltip: cvState.sourceMode == 'video_replay'
                ? (isVi ? 'Chạy lại từ đầu' : 'Restart replay')
                : (isVi ? 'Phát lại video' : 'Video Replay'),
            icon: const Icon(Icons.video_library_outlined, size: 20),
            style: compactButtonStyle.copyWith(
              foregroundColor:
                  WidgetStateProperty.all(SamanWorkoutTokens.textPrimary),
            ),
            onPressed: () {
              final notifier = ref.read(workoutCvControllerProvider.notifier);
              if (cvState.sourceMode == 'video_replay') {
                notifier.restartVideoReplay();
              } else {
                notifier.startVideoReplay(videoPath: widget.videoPath);
              }
            },
          ),
          const SizedBox(width: 4),
        ],
        IconButton(
          key: const ValueKey('workout_cv_guide_button'),
          tooltip: isVi
              ? 'Hướng dẫn đặt máy & điểm mù AI'
              : 'Camera guide & AI blind spots',
          icon: const Icon(
            Icons.help_outline_rounded,
            color: Colors.white,
            size: 19,
          ),
          onPressed: _openExerciseGuideSheet,
          style: compactButtonStyle,
        ),
        const SizedBox(width: 4),
        IconButton(
          key: const ValueKey('workout_cv_tts_toggle_button'),
          tooltip: _ttsCoach.isMuted
              ? (isVi ? 'Bật giọng hướng dẫn' : 'Unmute voice coach')
              : (isVi ? 'Tắt giọng hướng dẫn' : 'Mute voice coach'),
          icon: Icon(
            _ttsCoach.isMuted
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
            color: _ttsCoach.isMuted ? Colors.white54 : Colors.white,
            size: 19,
          ),
          onPressed: () {
            setState(() {
              _ttsCoach.setMuted(!_ttsCoach.isMuted);
            });
          },
          style: compactButtonStyle,
        ),
        const SizedBox(width: 4),
        Flexible(
          flex: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 102),
            child: _buildStatusChip(cvState, isVi: isVi),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          key: const ValueKey('workout_cv_finish_button'),
          tooltip: isVi ? 'Hoàn thành' : 'Finish',
          icon: Icon(
            Icons.stop_circle_outlined,
            color: t.isDark ? t.emeraldAccent : SamanWorkoutTokens.emeraldAccent,
            size: 24,
          ),
          onPressed: () {
            final cvState = ref.read(workoutCvControllerProvider);
            final summary = cvState.formSummary;
            final repHistory = List<LatPulldownRepEvent>.from(
              cvState.replayRepEvents,
            );
            final repRecords = List<RepRecord>.from(cvState.repRecords);
            unawaited(_ttsCoach.stop());
            ref.read(workoutCvControllerProvider.notifier).stop();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<CvFormSummary>(
                    builder: (_) => WorkoutCvResultScreen(
                      repHistory: repHistory,
                      repRecords: repRecords,
                      exerciseName: widget.exerciseName,
                      exerciseId: widget.exerciseId,
                      exerciseSlug: widget.exerciseSlug,
                      formSummary: summary,
                    ),
                  ),
                );
              }
            });
          },
          style: compactButtonStyle,
        ),
      ],
    );
  }

  Widget _buildStatusChip(ExerciseCvState cvState, {required bool isVi}) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (cvState.trackingStatus) {
      case TrackingStatus.detecting:
        bg = const Color(0x3310B981);
        fg = const Color(0xFF10B981);
        label = cvState.replayAnalysisStatus == ReplayAnalysisStatus.analyzing
            ? cvState.localizedReplayAnalysisLabel(isVietnamese: isVi)
            : (isVi ? 'Đang theo dõi' : 'Tracking');
        icon = Icons.accessibility_new;
        break;
      case TrackingStatus.needsSetup:
        bg = const Color(0x33F59E0B);
        fg = const Color(0xFFF59E0B);
        label = isVi ? 'CĂN KHUNG' : 'FRAMING';
        icon = Icons.crop_free;
        break;
      case TrackingStatus.multiplePeople:
        bg = const Color(0x33EF4444);
        fg = const Color(0xFFEF4444);
        label = isVi ? 'NHIỀU NGƯỜI' : 'MULTI-PERSON';
        icon = Icons.people_outline;
        break;
      case TrackingStatus.lost:
        bg = const Color(0x33EF4444);
        fg = const Color(0xFFF87171);
        label = isVi ? 'MẤT DẤU' : 'LOST';
        icon = Icons.person_off_outlined;
        break;
      case TrackingStatus.permissionDenied:
        bg = const Color(0x33EF4444);
        fg = const Color(0xFFEF4444);
        label = isVi ? 'THIẾU QUYỀN' : 'NO PERMISSION';
        icon = Icons.lock_outline;
        break;
      case TrackingStatus.error:
        bg = const Color(0x33EF4444);
        fg = const Color(0xFFEF4444);
        label = isVi ? 'LỖI' : 'ERROR';
        icon = Icons.error_outline;
        break;
      case TrackingStatus.uninitialized:
        bg = Colors.white12;
        fg = Colors.white70;
        label = isVi ? 'KHỞI ĐỘNG' : 'STARTING';
        icon = Icons.hourglass_empty;
        break;
    }

    if (cvState.sourceMode == 'video_replay') {
      label = cvState.localizedReplayAnalysisLabel(isVietnamese: isVi);
      switch (cvState.replayAnalysisStatus) {
        case ReplayAnalysisStatus.waiting:
          icon = Icons.hourglass_empty;
          break;
        case ReplayAnalysisStatus.analyzing:
          icon = Icons.accessibility_new;
          break;
        case ReplayAnalysisStatus.insufficientData:
          fg = SamanWorkoutTokens.amberAccent;
          bg = SamanWorkoutTokens.surfaceElevated;
          icon = Icons.info_outline;
          break;
        case ReplayAnalysisStatus.finished:
          fg = SamanWorkoutTokens.textSecondary;
          bg = SamanWorkoutTokens.surfaceElevated;
          icon = Icons.stop_circle_outlined;
          break;
        case ReplayAnalysisStatus.error:
          icon = Icons.error_outline;
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Manrope',
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _localizedGuideMessage(ExerciseCvState cvState, bool isVi) {
    if (cvState.sourceMode == 'video_replay') {
      return cvState.errorMessage ??
          cvState.localizedReplayAnalysisLabel(isVietnamese: isVi);
    }
    final raw = cvState.guideMessage.trim();
    if (raw.isEmpty) {
      return isVi ? 'Đang khởi tạo camera...' : 'Initializing Camera...';
    }
    if (!isVi) return raw;
    switch (raw) {
      case 'Initializing Camera...':
        return 'Đang khởi tạo camera...';
      case 'Checking camera permission...':
        return 'Đang kiểm tra quyền camera...';
      case 'Camera permission denied. Please grant permission in Settings.':
        return 'Quyền camera bị từ chối. Vui lòng cấp quyền trong Cài đặt.';
      case 'Unable to start camera session.':
        return 'Không thể khởi động phiên camera.';
      case 'Starting camera stream...':
        return 'Đang mở luồng camera...';
      case 'Starting video replay...':
        return 'Đang khởi động phát lại video...';
      case 'Unable to start requested source.':
        return 'Không thể khởi động nguồn dữ liệu.';
      case 'Switching to live camera...':
        return 'Đang chuyển sang camera trực tiếp...';
      case 'Error receiving camera stream.':
        return 'Lỗi khi nhận luồng camera.';
      case 'Slow video replay: waiting for the next pose...':
        return 'Phát chậm: đang chờ khung hình tiếp theo...';
      case 'Video replay finished. Tap Restart to replay.':
        return 'Đã phát xong video. Nhấn Chạy lại để xem tiếp.';
      case 'Camera/Model encountered an error.':
        return 'Camera hoặc mô hình AI gặp lỗi.';
      case 'Multiple people detected. Only one person should be in frame.':
        return 'Phát hiện nhiều người. Chỉ giữ một người trong khung hình.';
      case 'No person detected. Step into the camera view.':
        return 'Chưa phát hiện người tập. Vui lòng bước vào khung hình.';
      case 'No landmarks detected. Step into camera view.':
        return 'Chưa nhận diện được các khớp. Vui lòng bước vào khung hình.';
      case 'Align lower body (hips, knees, ankles) inside frame.':
        return 'Căn phần thân dưới (hông, gối, cổ chân) vào khung hình.';
      case 'Align full body (shoulders, hips, ankles) inside frame.':
        return 'Căn toàn thân (vai, hông, cổ chân) vào khung hình.';
      case 'Align upper body (shoulders, arms, hips) inside frame.':
        return 'Căn phần thân trên (vai, tay, hông) vào khung hình.';
      case 'Pose detected. Tracking active.':
        return 'Đã nhận diện tư thế. Đang theo dõi.';
      case 'Frontal angle limits depth tracking. Place camera at a 45° angle.':
        return 'Góc chính diện khó đo độ sâu, hãy đặt máy chếch nghiêng 45 độ.';
      case 'Replay stopped. Restart to try again.':
        return 'Đã dừng phát lại. Nhấn Chạy lại để thử lại.';
      default:
        return raw;
    }
  }

  Widget _buildBottomTelemetry(
    ExerciseCvState cvState, {
    required bool isVi,
    required SamanWorkoutPalette t,
    bool hideCameraHint = false,
  }) {
    final module = WorkoutCvExerciseRegistry.resolveModule(
      id: cvState.exerciseId,
      slug: cvState.exerciseSlug,
    );
    final cameraAngleHint = _cameraAngleHintForModule(
      module,
      isVietnamese: isVi,
    );
    final telemetryCardBg = (t.isDark ? t.cardSurface : SamanWorkoutTokens.cardSurface)
        .withOpacity(0.88);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: telemetryCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (module != null)
            _ReplayRepSummary(
              countLabel: cvState.localizedRepCountLabel(isVietnamese: isVi),
              statusLabel:
                  '${cvState.localizedReplayAnalysisLabel(isVietnamese: isVi)} · ${cvState.localizedPhaseLabel(isVietnamese: isVi)}',
              isVietnamese: isVi,
              onRestart: cvState.sourceMode == 'video_replay'
                  ? () => ref
                      .read(workoutCvControllerProvider.notifier)
                      .restartVideoReplay()
                  : null,
            ),
          // Guide banner
          Row(
            children: [
              Icon(
                cvState.trackingStatus == TrackingStatus.detecting
                    ? Icons.accessibility_new
                    : (cvState.trackingStatus == TrackingStatus.multiplePeople
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline),
                size: 18,
                color: cvState.trackingStatus == TrackingStatus.detecting
                    ? SamanWorkoutTokens.emeraldAccent
                    : SamanWorkoutTokens.amberAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _localizedGuideMessage(cvState, isVi),
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (!hideCameraHint && cameraAngleHint != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.videocam_outlined,
                  size: 14,
                  color: SamanWorkoutTokens.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    cameraAngleHint,
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      color: SamanWorkoutTokens.textSecondary,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 8),

          // Telemetry Row + Hardware Radar trigger
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'FPS: ${cvState.fps.toStringAsFixed(1)} · Latency: ${cvState.latencyMs}ms',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'p50: ${cvState.p50LatencyMs}ms / p95: ${cvState.p95LatencyMs}ms',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (cvState.detectedViewAngle != CameraViewAngle.unknown) ...[
                const SizedBox(width: 6),
                Container(
                  key: const ValueKey('workout_cv_detected_angle_badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cvState.detectedViewAngle == CameraViewAngle.frontal &&
                            module == CvExerciseModule.pushUp
                        ? SamanWorkoutTokens.amberAccent.withOpacity(0.16)
                        : Colors.white10,
                    borderRadius:
                        BorderRadius.circular(SamanWorkoutTokens.radiusPill),
                    border: Border.all(
                      color: cvState.detectedViewAngle == CameraViewAngle.frontal &&
                              module == CvExerciseModule.pushUp
                          ? SamanWorkoutTokens.amberAccent.withOpacity(0.55)
                          : Colors.white24,
                    ),
                  ),
                  child: Text(
                    RepRecord(
                      repIndex: 0,
                      timestampSec: 0,
                      durationSec: 0,
                      isValid: true,
                      viewAngle: cvState.detectedViewAngle,
                    ).localizedViewAngleLabel(isVietnamese: isVi),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: cvState.detectedViewAngle == CameraViewAngle.frontal &&
                              module == CvExerciseModule.pushUp
                          ? SamanWorkoutTokens.amberAccent
                          : Colors.white70,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey('workout_cv_hardware_radar_button'),
                  onTap: _openHardwareRadarSheet,
                  borderRadius:
                      BorderRadius.circular(SamanWorkoutTokens.radiusPill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: SamanWorkoutTokens.tealAccent.withOpacity(0.14),
                      borderRadius:
                          BorderRadius.circular(SamanWorkoutTokens.radiusPill),
                      border: Border.all(
                        color: SamanWorkoutTokens.tealAccent.withOpacity(0.45),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.radar_rounded,
                          size: 14,
                          color: SamanWorkoutTokens.tealAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isVi ? 'Radar' : 'Radar',
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            color: SamanWorkoutTokens.tealAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _cameraAngleHintForModule(
    CvExerciseModule? module, {
    required bool isVietnamese,
  }) {
    switch (module?.name) {
      case 'pullUp':
        return isVietnamese
            ? 'Góc quay tối ưu: Chính diện hoặc chéo 30–45°, lấy trọn từ thanh xà đến hông.'
            : 'Best angle: Front or 30–45° diagonal, framing from the bar to your hips.';
      case 'latPulldown':
        return isVietnamese
            ? 'Góc quay tối ưu: Chính diện hoặc chéo 30–45°, thấy rõ thanh kéo, vai và khuỷu tay.'
            : 'Best angle: Front or 30–45° diagonal, clearly showing the bar, shoulders, and elbows.';
      case 'squat':
        return isVietnamese
            ? 'Góc quay tối ưu: Nghiêng bên 90° hoặc chéo 45°, lấy trọn từ đầu đến bàn chân.'
            : 'Best angle: 90° side view or 45° diagonal, framing head to toe.';
      case 'pushUp':
        return isVietnamese
            ? 'Góc quay tối ưu: Ngang 90° hoặc chéo 45° ngang tầm sàn, thấy trọn từ tay đến cổ chân.'
            : 'Best angle: 90° side or 45° floor-level view, framing hands to ankles.';
      case 'overheadPress':
        return isVietnamese
            ? 'Góc quay tối ưu: Chéo 30–45° hoặc chính diện, thấy từ hông lên hết tay khi duỗi qua đầu.'
            : 'Best angle: 30–45° diagonal or front view, framing hips to full overhead lockout.';
      case 'bicepCurl':
        return isVietnamese
            ? 'Góc quay tối ưu: Chéo 30–45° hoặc ngang bên, giữ khuỷu tay cố định sát sườn.'
            : 'Best angle: 30–45° diagonal or side view, keeping elbows pinned by your sides.';
      case 'hipHinge':
        return isVietnamese
            ? 'Góc quay tối ưu: Nghiêng bên 90° hoặc chéo 45°, thấy rõ vai, hông và gối suốt biên độ gập.'
            : 'Best angle: 90° side or 45° diagonal, showing shoulders, hips, and knees through the hinge.';
      case 'hipThrust':
        return isVietnamese
            ? 'Góc quay tối ưu: Ngang bên 90° ngang tầm ghế/sàn, thấy rõ vai, hông và gối khi đẩy hông.'
            : 'Best angle: 90° side view at bench/floor height, showing shoulders, hips, and knees.';
      case 'tricepExtension':
        return isVietnamese
            ? 'Góc quay tối ưu: Chéo 30–45° hoặc ngang bên, thấy rõ vai, khuỷu tay và cổ tay khi duỗi.'
            : 'Best angle: 30–45° diagonal or side view, showing shoulder, elbow, and wrist extension.';
      case 'lateralRaise':
        return isVietnamese
            ? 'Góc quay tối ưu: Chính diện hoặc chéo 30°, thấy rõ hông, vai và khuỷu tay hai bên.'
            : 'Best angle: Front or 30° diagonal, showing hips, shoulders, and both elbows clearly.';
      case 'legExtension':
        return isVietnamese
            ? 'Góc quay tối ưu: Ngang bên 90° cạnh máy, thấy rõ hông, gối và cổ chân suốt chu kỳ đạp/đá.'
            : 'Best angle: 90° side view next to the machine, showing hips, knees, and ankles.';
      case 'legCurl':
        return isVietnamese
            ? 'Góc quay tối ưu: Ngang bên 90° hoặc chéo 45°, lấy trọn hông, gối và cổ chân khi gập/chùng.'
            : 'Best angle: 90° side or 45° diagonal, framing hips, knees, and ankles throughout.';
      case 'plankHold':
        return isVietnamese
            ? 'Góc quay tối ưu: Ngang bên 90° ngang tầm sàn, thấy trọn từ vai, hông đến cổ chân.'
            : 'Best angle: 90° floor-level side view, framing shoulders, hips, and ankles.';
      case 'row':
        return isVietnamese
            ? 'Góc quay tối ưu: Ngang bên 90° hoặc chéo 45°, thấy rõ lưng, vai và khuỷu tay.'
            : 'Best angle: 90° side or 45° diagonal, clearly showing your back, shoulders, and elbows.';
      case 'facePull':
        return isVietnamese
            ? 'Góc quay tối ưu: Chéo 30–45° hoặc chính diện, thấy rõ vai, khuỷu tay và cổ tay ngang mặt.'
            : 'Best angle: 30–45° diagonal or front view, showing shoulders, elbows, and wrists at face level.';
      default:
        return null;
    }
  }

  Widget _buildPermissionDeniedView(bool isVi, SamanWorkoutPalette t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off_outlined,
              size: 64,
              color: t.isDark ? t.amberAccent : SamanWorkoutTokens.amberAccent,
            ),
            const SizedBox(height: 16),
            Text(
              isVi ? 'Cần quyền truy cập Camera' : 'Camera Permission Required',
              style: const TextStyle(
                fontFamily: 'Manrope',
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isVi
                  ? 'Cần quyền camera để theo dõi tư thế trực tiếp. Vui lòng cấp quyền để tiếp tục.'
                  : 'Camera access is needed for live pose tracking. Please grant permission to continue.',
              style: const TextStyle(
                fontFamily: 'Manrope',
                color: Colors.white70,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _initializeSession,
              style: ElevatedButton.styleFrom(
                backgroundColor: SamanWorkoutTokens.emeraldAccent,
                foregroundColor: Colors.black,
              ),
              child: Text(
                isVi ? 'Cấp quyền' : 'Grant Permission',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNonAndroidPlaceholder(bool isVi) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          isVi
              ? 'Camera CV chỉ hỗ trợ Android.\n'
                  'Web/iOS chưa có replay landmarks được đóng gói để demo.'
              : 'Camera CV is supported on Android only.\n'
                  'Web/iOS does not bundle demo replay landmarks yet.',
          style: const TextStyle(
            fontFamily: 'Manrope',
            color: Colors.white54,
            fontSize: 13,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ReplayRepSummary extends StatelessWidget {
  final String countLabel;
  final String statusLabel;
  final bool isVietnamese;
  final VoidCallback? onRestart;

  const _ReplayRepSummary({
    required this.countLabel,
    required this.statusLabel,
    required this.isVietnamese,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$countLabel. $statusLabel',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    countLabel,
                    key: const ValueKey('workout_cv_replay_rep_count'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontFamily: 'Manrope',
                          color: SamanWorkoutTokens.textPrimary,
                        ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    statusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'Manrope',
                          color: SamanWorkoutTokens.textSecondary,
                        ),
                  ),
                ),
              ],
            ),
          ),
          if (onRestart != null)
            Flexible(
              fit: FlexFit.loose,
              child: TextButton.icon(
                onPressed: onRestart,
                icon: const Icon(Icons.replay),
                label: Text(
                  isVietnamese ? 'Chạy lại' : 'Replay',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Manrope'),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: SamanWorkoutTokens.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
