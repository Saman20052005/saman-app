import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../presentation/tokens/saman_workout_tokens.dart';
import '../../domain/entities/exercise_cv_state.dart';
import '../controllers/workout_cv_controller.dart';
import '../widgets/pose_skeleton_painter.dart';
import '../workout_cv_replay_trial.dart';

class WorkoutCvScreen extends ConsumerStatefulWidget {
  final String exerciseId;
  final String exerciseSlug;
  final String exerciseName;

  const WorkoutCvScreen({
    super.key,
    required this.exerciseId,
    required this.exerciseSlug,
    required this.exerciseName,
  });

  @override
  ConsumerState<WorkoutCvScreen> createState() => _WorkoutCvScreenState();
}

class _WorkoutCvScreenState extends ConsumerState<WorkoutCvScreen>
    with WidgetsBindingObserver {
  bool get _useReplayTrial =>
      shouldUseWorkoutCvReplayTrial(exerciseSlug: widget.exerciseSlug);

  Future<void> _initializeSession() =>
      ref.read(workoutCvControllerProvider.notifier).initialize(
            exerciseId: widget.exerciseId,
            exerciseSlug: widget.exerciseSlug,
            videoReplay: _useReplayTrial,
          );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSession();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final notifier = ref.read(workoutCvControllerProvider.notifier);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      notifier.stop();
    } else if (state == AppLifecycleState.resumed) {
      _initializeSession();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cvState = ref.watch(workoutCvControllerProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Camera View Layer
            if (cvState.trackingStatus == TrackingStatus.permissionDenied)
              _buildPermissionDeniedView()
            else if (!kIsWeb && Platform.isAndroid && cvState.isCameraActive)
              const AndroidView(
                viewType: 'workout_camera_view',
                creationParamsCodec: StandardMessageCodec(),
              )
            else
              _buildNonAndroidPlaceholder(),

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

            // 3. Header & Controls Layer
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: _buildHeader(cvState),
            ),

            // 4. Bottom Info & Telemetry Layer
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _buildBottomTelemetry(cvState),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ExerciseCvState cvState) {
    return Row(
      children: [
        IconButton(
          key: const ValueKey('workout_cv_close_button'),
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(
            backgroundColor: Colors.black45,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.exerciseName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                cvState.sourceMode == 'video_replay'
                    ? 'Replay thử nghiệm • phát chậm'
                    : 'MediaPipe Pose Lite · Back Camera',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (_useReplayTrial)
          IconButton(
            key: const ValueKey('workout_cv_switch_replay_button'),
            tooltip: cvState.sourceMode == 'video_replay' ? 'Chạy lại từ 0' : 'Video Replay',
            icon: const Icon(Icons.video_library_outlined),
            style: IconButton.styleFrom(foregroundColor: SamanWorkoutTokens.textPrimary),
            onPressed: () {
              final notifier = ref.read(workoutCvControllerProvider.notifier);
              if (cvState.sourceMode == 'video_replay') {
                notifier.restartVideoReplay();
              } else {
                notifier.startVideoReplay();
              }
            },
          ),
        _buildStatusChip(cvState),
      ],
    );
  }

  Widget _buildStatusChip(ExerciseCvState cvState) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (cvState.trackingStatus) {
      case TrackingStatus.detecting:
        bg = const Color(0x3310B981);
        fg = const Color(0xFF10B981);
        label = 'TRACKING';
        icon = Icons.check_circle_outline;
        break;
      case TrackingStatus.needsSetup:
        bg = const Color(0x33F59E0B);
        fg = const Color(0xFFF59E0B);
        label = 'FRAMING';
        icon = Icons.crop_free;
        break;
      case TrackingStatus.multiplePeople:
        bg = const Color(0x33EF4444);
        fg = const Color(0xFFEF4444);
        label = 'MULTI-PERSON';
        icon = Icons.people_outline;
        break;
      case TrackingStatus.lost:
        bg = const Color(0x33EF4444);
        fg = const Color(0xFFF87171);
        label = 'LOST';
        icon = Icons.person_off_outlined;
        break;
      case TrackingStatus.permissionDenied:
        bg = const Color(0x33EF4444);
        fg = const Color(0xFFEF4444);
        label = 'NO PERMISSION';
        icon = Icons.lock_outline;
        break;
      case TrackingStatus.error:
        bg = const Color(0x33EF4444);
        fg = const Color(0xFFEF4444);
        label = 'ERROR';
        icon = Icons.error_outline;
        break;
      case TrackingStatus.uninitialized:
        bg = Colors.white12;
        fg = Colors.white70;
        label = 'STARTING';
        icon = Icons.hourglass_empty;
        break;
    }

    if (cvState.sourceMode == 'video_replay') {
      label = cvState.replayAnalysisLabel;
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
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomTelemetry(ExerciseCvState cvState) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xDD121316),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cvState.sourceMode == 'video_replay')
            _ReplayRepSummary(
              countLabel: cvState.repCountLabel,
              statusLabel: cvState.replayAnalysisLabel,
              onRestart: _useReplayTrial
                  ? () => ref.read(workoutCvControllerProvider.notifier).restartVideoReplay()
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
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cvState.sourceMode == 'video_replay'
                      ? (cvState.errorMessage ?? cvState.replayAnalysisLabel)
                      : cvState.guideMessage,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 8),

          // Telemetry Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'FPS: ${cvState.fps.toStringAsFixed(1)} · Latency: ${cvState.latencyMs}ms',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                'p50: ${cvState.p50LatencyMs}ms / p95: ${cvState.p95LatencyMs}ms',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            cvState.sourceMode == 'video_replay'
                ? 'Chỉ thử nghiệm • Không tự lưu lịch sử hoặc hoàn thành set'
                : 'PoC Form Check · Auto-log & rep counting disabled · Manual workout preserved',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off_outlined,
                size: 64, color: Colors.amber),
            const SizedBox(height: 16),
            const Text(
              'Camera Permission Required',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Camera access is needed for live pose tracking. Please grant permission to continue.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _initializeSession,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.black,
              ),
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNonAndroidPlaceholder() {
    return const Center(
      child: Text(
        'Camera PlatformView is available on Android devices.',
        style: TextStyle(color: Colors.white54, fontSize: 13),
      ),
    );
  }
}

class _ReplayRepSummary extends StatelessWidget {
  final String countLabel;
  final String statusLabel;
  final VoidCallback? onRestart;

  const _ReplayRepSummary({required this.countLabel, required this.statusLabel, required this.onRestart});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$countLabel. $statusLabel',
      child: Row(
        children: [
          Expanded(
            child: Text(
              countLabel,
              key: const ValueKey('workout_cv_replay_rep_count'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: SamanWorkoutTokens.textPrimary,
              ),
            ),
          ),
          if (onRestart != null)
            TextButton.icon(
              onPressed: onRestart,
              icon: const Icon(Icons.replay),
              label: const Text('Chạy lại'),
              style: TextButton.styleFrom(foregroundColor: SamanWorkoutTokens.textPrimary),
            ),
        ],
      ),
    );
  }
}
