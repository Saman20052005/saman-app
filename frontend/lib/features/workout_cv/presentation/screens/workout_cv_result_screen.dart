import 'dart:async';
import 'dart:ui' show FontFeature, ImageFilter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/workout_cv_replay_source.dart';
import '../../domain/entities/exercise_cv_state.dart';
import '../../domain/services/cv_form_summary_calculator.dart';
import '../../domain/services/lat_pulldown_baseline.dart';
import '../controllers/workout_cv_controller.dart';
import '../widgets/pose_skeleton_painter.dart';

/// Calm Athleticism (Dark Mode Obsidian) tokens for CV Report Screen.
class _CalmAthleticismReportTokens {
  _CalmAthleticismReportTokens._();

  static const Color canvas = Color(0xFF0C0D0E);
  static const Color cardSurface = Color(0xFF16171B);
  static const Color cardHover = Color(0xFF1F2126);
  static const Color border = Color(0xFF26282F);
  static const Color iconContainer = Color(0xFF212328);
  static const Color videoBackdrop = Color(0xFF000000);

  static const Color textPrimary = Color(0xFFF9FAFB);
  static const Color textHeadline = Color(0xFFF3F4F6);
  static const Color textSecondary = Color(0xFF94979E);
  static const Color textSubtle = Color(0xFFCBD5E1);

  static const Color statusValid = Color(0xFF10B981);
  static const Color statusWarning = Color(0xFFF59E0B);

  static TextStyle headline({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w600,
    Color color = textHeadline,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: 'Space Grotesk',
      fontFamilyFallback: const ['Manrope', 'Inter', 'sans-serif'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle body({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    Color color = textPrimary,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: const ['Manrope', 'sans-serif'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle mono({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w500,
    Color color = textSecondary,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: const ['monospace', 'Courier New'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}

class WorkoutCvResultScreen extends ConsumerStatefulWidget {
  final List<LatPulldownRepEvent> repHistory;
  final String? exerciseName;
  final String? replayVideoPath;
  final WorkoutCvReplaySource? replaySource;
  final VoidCallback? onDone;
  final CvFormSummary? formSummary;

  const WorkoutCvResultScreen({
    super.key,
    required this.repHistory,
    this.exerciseName,
    this.replayVideoPath,
    this.replaySource,
    this.onDone,
    this.formSummary,
  });

  static bool isRepStandardMet(LatPulldownRepEvent rep) {
    final durationSec = rep.durationMs / 1000.0;
    return rep.minElbowAngleDeg < 45.0 &&
        durationSec >= 2.0 &&
        durationSec <= 3.0;
  }

  @override
  ConsumerState<WorkoutCvResultScreen> createState() =>
      _WorkoutCvResultScreenState();
}

class _WorkoutCvResultScreenState extends ConsumerState<WorkoutCvResultScreen>
    with WidgetsBindingObserver {
  /// [ExerciseCvState] does not expose the input frame size. The replay clip is
  /// 360x480 portrait, so 3:4 is used for the video box and the skeleton overlay.
  static const double _fallbackVideoAspectRatio = 3 / 4;
  static const Duration _controlsAutoHideDelay = Duration(milliseconds: 2200);

  bool _isReplayPlaying = false;
  bool _isAutoStarting = false;
  bool _controlsVisible = true;
  bool _showSkeletonOverlay = true;
  int? _selectedRepNumber;
  int? _seekTimestampMs;
  late final bool _hasScope;
  WorkoutCvNotifier? _notifier;
  Timer? _controlsTimer;

  bool get _supportsNativeVideoView =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool _hasProviderScope(BuildContext context) {
    try {
      ProviderScope.containerOf(context, listen: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  ExerciseCvState _currentCvState() =>
      _hasScope ? ref.read(workoutCvControllerProvider) : const ExerciseCvState();

  /// A recording exists only for video-replay sessions (or an explicit path).
  /// Live-camera sessions are never recorded, so nothing is replayed for them.
  bool _canReplay(ExerciseCvState cvState) =>
      widget.replaySource != null ||
      (widget.replayVideoPath?.isNotEmpty ?? false) ||
      cvState.sourceMode == 'video_replay';

  bool _isPlayingNow(ExerciseCvState cvState) =>
      _isReplayPlaying &&
      !cvState.isEndOfStream &&
      cvState.trackingStatus != TrackingStatus.error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hasScope = _hasProviderScope(context);
    if (_hasScope) {
      _notifier = ref.read(workoutCvControllerProvider.notifier);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _autoStartReplay();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _isReplayPlaying) {
      _stopReplay();
      setState(() {
        _isReplayPlaying = false;
        _controlsVisible = true;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controlsTimer?.cancel();
    final directReplaySource = widget.replaySource;
    if (directReplaySource != null && directReplaySource.isPlaying) {
      directReplaySource.stopSession();
    }
    _notifier?.stop();
    super.dispose();
  }

  /// The previous screen stopped the native session before navigating here, so
  /// the replay is restarted once the route transition has finished. This mounts
  /// the platform view and streams frames without waiting for a Play tap.
  Future<void> _autoStartReplay() async {
    if (!_canReplay(_currentCvState())) return;
    setState(() => _isAutoStarting = true);

    final animation = ModalRoute.of(context)?.animation;
    if (animation != null && animation.status != AnimationStatus.completed) {
      final transitionDone = Completer<void>();
      void onStatus(AnimationStatus status) {
        if (status == AnimationStatus.completed && !transitionDone.isCompleted) {
          transitionDone.complete();
        }
      }

      animation.addStatusListener(onStatus);
      await transitionDone.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
      animation.removeStatusListener(onStatus);
    }

    if (!mounted) return;
    await _startOrSeekReplay();
    if (mounted) setState(() => _isAutoStarting = false);
  }

  void _revealControls() {
    _controlsTimer?.cancel();
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    if (_isReplayPlaying) {
      _controlsTimer = Timer(_controlsAutoHideDelay, () {
        if (mounted && _isReplayPlaying) {
          setState(() => _controlsVisible = false);
        }
      });
    }
  }

  Future<void> _toggleReplayPlayback() async {
    if (!_hasScope && widget.replaySource == null) {
      setState(() {
        _isReplayPlaying = !_isReplayPlaying;
      });
      return;
    }

    if (_isPlayingNow(_currentCvState())) {
      await _stopReplay();
      if (mounted) {
        setState(() {
          _isReplayPlaying = false;
          _controlsVisible = true;
        });
      }
      return;
    }

    await _startOrSeekReplay(timestampMs: _seekTimestampMs);
  }

  Future<void> _startOrSeekReplay({int? timestampMs}) async {
    if (!_canReplay(_currentCvState())) return;
    if (mounted) {
      setState(() {
        _isReplayPlaying = true;
        if (timestampMs != null) {
          _seekTimestampMs = timestampMs;
        }
      });
      _revealControls();
    }

    final directReplaySource = widget.replaySource;
    if (directReplaySource != null) {
      if (!directReplaySource.isPlaying) {
        await directReplaySource.startSession('lat-pulldown');
      }
      if (timestampMs != null) {
        directReplaySource.seekTo(timestampMs);
      }
      return;
    }

    final notifier = _notifier;
    if (notifier == null || !mounted) return;

    final nativeSource = ref.read(workoutCvNativeSourceProvider);
    if (nativeSource is WorkoutCvReplaySource) {
      if (!nativeSource.isPlaying) {
        await nativeSource.startSession('lat-pulldown');
      }
      if (timestampMs != null) {
        nativeSource.seekTo(timestampMs);
      }
      return;
    }

    if (widget.replayVideoPath != null && widget.replayVideoPath!.isNotEmpty) {
      await notifier.startVideoReplay(videoPath: widget.replayVideoPath);
    } else {
      await notifier.restartVideoReplay();
    }
  }

  Future<void> _onRepSelected(LatPulldownRepEvent rep, int displayIndex) async {
    setState(() {
      _selectedRepNumber = displayIndex;
      _seekTimestampMs = rep.startTimestampMs;
    });
    await _startOrSeekReplay(timestampMs: rep.startTimestampMs);
  }

  Future<void> _stopReplay() async {
    _controlsTimer?.cancel();
    final directReplaySource = widget.replaySource;
    if (directReplaySource != null && directReplaySource.isPlaying) {
      await directReplaySource.stopSession();
    }
    await _notifier?.stop();
  }

  void _handleExit() {
    _stopReplay();
    final cvState = _currentCvState();
    final effectiveReps = widget.repHistory.isNotEmpty
        ? widget.repHistory
        : cvState.replayRepEvents;
    final summaryToReturn =
        widget.formSummary ?? CvFormSummaryCalculator.compute(reps: effectiveReps);
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).pop<CvFormSummary>(summaryToReturn);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cvState = _hasScope
        ? ref.watch(workoutCvControllerProvider)
        : const ExerciseCvState();

    final effectiveReps = widget.repHistory.isNotEmpty
        ? widget.repHistory
        : cvState.replayRepEvents;
    final totalReps = effectiveReps.length;
    final standardCount =
        effectiveReps.where(WorkoutCvResultScreen.isRepStandardMet).length;
    final isPlaying = _isPlayingNow(cvState);

    return Scaffold(
      backgroundColor: _CalmAthleticismReportTokens.canvas,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopHeader(
                    exerciseName: widget.exerciseName,
                    onBack: () {
                      _stopReplay();
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(height: 16),
                  _SessionReplayVideoCard(
                    key: const ValueKey('workout_cv_result_video_card'),
                    cvState: cvState,
                    repHistory: effectiveReps,
                    exerciseName: widget.exerciseName,
                    isPlaying: isPlaying,
                    isLoading: _isAutoStarting,
                    hasReplay: _canReplay(cvState),
                    showControls: !isPlaying || _controlsVisible,
                    showSkeletonOverlay: _showSkeletonOverlay,
                    supportsNativeVideoView: _supportsNativeVideoView,
                    videoAspectRatio: _fallbackVideoAspectRatio,
                    selectedRepNumber: _selectedRepNumber,
                    seekTimestampMs: _seekTimestampMs,
                    onVideoTap: _revealControls,
                    onTogglePlayPause: _toggleReplayPlayback,
                    onToggleSkeleton: () {
                      setState(() {
                        _showSkeletonOverlay = !_showSkeletonOverlay;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  _HeroSummaryCard(
                    totalReps: totalReps,
                    standardReps: standardCount,
                  ),
                  const SizedBox(height: 16),
                  const _CriteriaBanner(
                    key: ValueKey('workout_cv_result_criteria_banner'),
                  ),
                  const SizedBox(height: 16),
                  _RepBreakdownSection(
                    repHistory: effectiveReps,
                    selectedRepNumber: _selectedRepNumber,
                    onRepTap: _onRepSelected,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _StickyBottomCta(
        onDone: _handleExit,
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  final String? exerciseName;
  final VoidCallback onBack;

  const _TopHeader({
    required this.exerciseName,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedName = exerciseName?.trim() ?? '';
    final hasExerciseName = trimmedName.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Material(
              color: _CalmAthleticismReportTokens.cardSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(
                  color: _CalmAthleticismReportTokens.border,
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('workout_cv_result_back_button'),
                onTap: onBack,
                child: const Center(
                  child: Icon(
                    Icons.arrow_back,
                    size: 20,
                    color: _CalmAthleticismReportTokens.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    text: 'Báo cáo CV',
                    style: _CalmAthleticismReportTokens.headline(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: _CalmAthleticismReportTokens.textPrimary,
                      height: 1.2,
                      letterSpacing: -0.3,
                    ),
                    children: [
                      if (hasExerciseName)
                        TextSpan(
                          text: ' · $trimmedName',
                          style: _CalmAthleticismReportTokens.headline(
                            fontSize: 19,
                            fontWeight: FontWeight.w400,
                            color: _CalmAthleticismReportTokens.textSecondary,
                            height: 1.2,
                            letterSpacing: -0.3,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'COMPUTER VISION ANALYSIS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _CalmAthleticismReportTokens.mono(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _CalmAthleticismReportTokens.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const _NeutralStatusBadge(
            dotColor: _CalmAthleticismReportTokens.statusValid,
            label: 'AI VERIFIED',
          ),
        ],
      ),
    );
  }
}

class _SessionReplayVideoCard extends StatelessWidget {
  static const double _cardHeight = 280;

  final ExerciseCvState cvState;
  final List<LatPulldownRepEvent> repHistory;
  final String? exerciseName;
  final bool isPlaying;
  final bool isLoading;
  final bool hasReplay;
  final bool showControls;
  final bool showSkeletonOverlay;
  final bool supportsNativeVideoView;
  final double videoAspectRatio;
  final int? selectedRepNumber;
  final int? seekTimestampMs;
  final VoidCallback onVideoTap;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onToggleSkeleton;

  const _SessionReplayVideoCard({
    super.key,
    required this.cvState,
    required this.repHistory,
    required this.exerciseName,
    required this.isPlaying,
    required this.isLoading,
    required this.hasReplay,
    required this.showControls,
    required this.showSkeletonOverlay,
    required this.supportsNativeVideoView,
    required this.videoAspectRatio,
    required this.selectedRepNumber,
    required this.seekTimestampMs,
    required this.onVideoTap,
    required this.onTogglePlayPause,
    required this.onToggleSkeleton,
  });

  String _formatMsToSeconds(int ms) {
    final sec = (ms / 1000.0).clamp(0.0, 9999.0);
    return '${sec.toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final hasError = cvState.trackingStatus == TrackingStatus.error;
    final canRenderNativeView =
        supportsNativeVideoView && cvState.isCameraActive && !hasError;
    final clipLabel = cvState.clipName.trim().isNotEmpty
        ? cvState.clipName.trim()
        : (exerciseName?.trim().isNotEmpty == true
            ? exerciseName!.trim()
            : 'Session Replay');

    final activePtsMs = cvState.videoPtsMs > 0
        ? cvState.videoPtsMs
        : (seekTimestampMs ??
            (repHistory.isNotEmpty ? repHistory.first.startTimestampMs : 0));

    return SizedBox(
      height: _cardHeight,
      child: Container(
        decoration: BoxDecoration(
          color: _CalmAthleticismReportTokens.videoBackdrop,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _CalmAthleticismReportTokens.border,
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video + skeleton share one box with the real frame ratio, so the
            // clip is pillarboxed (never stretched) and landmarks stay aligned.
            Center(
              child: AspectRatio(
                aspectRatio: videoAspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (canRenderNativeView)
                      const AndroidView(
                        viewType: 'workout_camera_view',
                        creationParamsCodec: StandardMessageCodec(),
                      )
                    else
                      _MinimalReplaySurfaceFallback(
                        hasError: hasError,
                        hasReplay: hasReplay,
                        isLoading: isLoading,
                        repCount: repHistory.length,
                        selectedRepNumber: selectedRepNumber,
                        seekTimestampMs: seekTimestampMs,
                      ),
                    if (showSkeletonOverlay &&
                        canRenderNativeView &&
                        cvState.landmarks.isNotEmpty &&
                        cvState.trackingStatus != TrackingStatus.permissionDenied)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: PoseSkeletonPainter(
                              landmarks: cvState.landmarks,
                              trackingStatus: cvState.trackingStatus,
                              isSyncValid: cvState.isSyncValid,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Transparent layer above the platform view so taps reach Flutter.
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('workout_cv_result_video_tap_area'),
                behavior: HitTestBehavior.opaque,
                onTap: onVideoTap,
              ),
            ),
            // Overlays fade out while playing so the athlete stays unobstructed.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !showControls,
                child: AnimatedOpacity(
                  opacity: showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 56,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  _CalmAthleticismReportTokens.canvas
                                      .withOpacity(0.80),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _CalmAthleticismReportTokens
                                      .iconContainer
                                      .withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _CalmAthleticismReportTokens.border,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  selectedRepNumber != null
                                      ? 'REP $selectedRepNumber · ${_formatMsToSeconds(activePtsMs)}'
                                      : (isPlaying
                                          ? 'REPLAY · ${_formatMsToSeconds(activePtsMs)}'
                                          : 'SESSION REPLAY'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _CalmAthleticismReportTokens.mono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        _CalmAthleticismReportTokens.textSubtle,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Material(
                              color: _CalmAthleticismReportTokens.iconContainer
                                  .withOpacity(0.85),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: const BorderSide(
                                  color: _CalmAthleticismReportTokens.border,
                                  width: 1,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                key: const ValueKey(
                                  'workout_cv_result_skeleton_toggle',
                                ),
                                onTap: onToggleSkeleton,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.accessibility_new_rounded,
                                        size: 13,
                                        color: showSkeletonOverlay
                                            ? _CalmAthleticismReportTokens
                                                .statusValid
                                            : _CalmAthleticismReportTokens
                                                .textSecondary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        showSkeletonOverlay
                                            ? 'SKELETON ON'
                                            : 'SKELETON OFF',
                                        style:
                                            _CalmAthleticismReportTokens.mono(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: _CalmAthleticismReportTokens
                                              .textSubtle,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasReplay)
                        Center(
                          child: ClipOval(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: Material(
                                  color: _CalmAthleticismReportTokens
                                      .iconContainer
                                      .withOpacity(0.80),
                                  shape: const CircleBorder(
                                    side: BorderSide(
                                      color: _CalmAthleticismReportTokens.border,
                                      width: 1,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    key: const ValueKey(
                                      'workout_cv_result_play_pause_button',
                                    ),
                                    onTap: onTogglePlayPause,
                                    child: Center(
                                      child: Icon(
                                        isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        size: 28,
                                        color: _CalmAthleticismReportTokens
                                            .textHeadline,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 10,
                        child: IgnorePointer(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  hasError
                                      ? 'Video phiên tập chưa sẵn sàng để phát lại'
                                      : (selectedRepNumber != null
                                          ? 'Đang định vị mốc Rep $selectedRepNumber (${_formatMsToSeconds(activePtsMs)})'
                                          : clipLabel),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _CalmAthleticismReportTokens.mono(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                    color: _CalmAthleticismReportTokens
                                        .textSecondary,
                                  ),
                                ),
                              ),
                              if (repHistory.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '${_formatMsToSeconds(repHistory.first.startTimestampMs)} – ${_formatMsToSeconds(repHistory.last.endTimestampMs)}',
                                  style: _CalmAthleticismReportTokens.mono(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        _CalmAthleticismReportTokens.textSubtle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
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

class _MinimalReplaySurfaceFallback extends StatelessWidget {
  final bool hasError;
  final bool hasReplay;
  final bool isLoading;
  final int repCount;
  final int? selectedRepNumber;
  final int? seekTimestampMs;

  const _MinimalReplaySurfaceFallback({
    required this.hasError,
    required this.hasReplay,
    required this.isLoading,
    required this.repCount,
    required this.selectedRepNumber,
    required this.seekTimestampMs,
  });

  String get _message {
    if (hasError) return 'Không thể tải video phiên tập trên thiết bị này';
    if (!hasReplay) return 'Phiên này không có video ghi lại để phát lại';
    if (isLoading) return 'Đang tải video phiên tập…';
    if (selectedRepNumber != null && seekTimestampMs != null) {
      return 'Đã chọn Rep $selectedRepNumber • Nhấn Play để phát lại';
    }
    if (repCount > 0) return 'Nhấn Play hoặc chạm vào từng Rep để xem lại';
    return 'Chưa có bản ghi video trong phiên này';
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _CalmAthleticismReportTokens.cardSurface,
      child: CustomPaint(
        painter: _TelemetryFrameGuidePainter(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              _message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: _CalmAthleticismReportTokens.body(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: _CalmAthleticismReportTokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TelemetryFrameGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _CalmAthleticismReportTokens.border.withOpacity(0.65)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const inset = 20.0;
    const corner = 14.0;
    final rect = Rect.fromLTWH(
      inset,
      inset + 18,
      (size.width - inset * 2).clamp(0.0, size.width),
      (size.height - inset * 2 - 28).clamp(0.0, size.height),
    );

    if (rect.width <= corner * 2 || rect.height <= corner * 2) return;

    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + const Offset(corner, 0),
      paint,
    );
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + const Offset(0, corner),
      paint,
    );

    canvas.drawLine(
      rect.topRight,
      rect.topRight + const Offset(-corner, 0),
      paint,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight + const Offset(0, corner),
      paint,
    );

    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + const Offset(corner, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + const Offset(0, -corner),
      paint,
    );

    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + const Offset(-corner, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + const Offset(0, -corner),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HeroSummaryCard extends StatelessWidget {
  final int totalReps;
  final int standardReps;

  const _HeroSummaryCard({
    required this.totalReps,
    required this.standardReps,
  });

  @override
  Widget build(BuildContext context) {
    final needsImprovementReps = (totalReps - standardReps).clamp(0, totalReps);
    final standardPct =
        totalReps > 0 ? ((standardReps * 100) / totalReps).round() : 0;
    final improvementPct = totalReps > 0 ? (100 - standardPct) : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _CalmAthleticismReportTokens.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _CalmAthleticismReportTokens.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _CalmAthleticismReportTokens.iconContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _CalmAthleticismReportTokens.border,
                    width: 1,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.fitness_center,
                    size: 18,
                    color: _CalmAthleticismReportTokens.statusValid,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'TỔNG SỐ REP HỢP LỆ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _CalmAthleticismReportTokens.mono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _CalmAthleticismReportTokens.textSecondary,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _NeutralStatusBadge(
                dotColor: _CalmAthleticismReportTokens.statusValid,
                label: 'ĐẠT CHUẨN: $standardReps/$totalReps REP',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$totalReps',
                key: const ValueKey('workout_cv_result_total_reps'),
                style: _CalmAthleticismReportTokens.headline(
                  fontSize: 58,
                  fontWeight: FontWeight.w600,
                  color: _CalmAthleticismReportTokens.textHeadline,
                  height: 1.0,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Rep',
                style: _CalmAthleticismReportTokens.body(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: _CalmAthleticismReportTokens.textSecondary,
                  height: 1.0,
                ),
              ),
              const Spacer(),
              _NeutralStatusBadge(
                dotColor: _CalmAthleticismReportTokens.statusValid,
                label: '$standardPct%',
                isBoldLabel: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(
            height: 1,
            thickness: 1,
            color: _CalmAthleticismReportTokens.border,
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 4,
              width: double.infinity,
              child: ColoredBox(
                color: _CalmAthleticismReportTokens.iconContainer,
                child: totalReps > 0
                    ? Row(
                        children: [
                          if (standardReps > 0)
                            Expanded(
                              flex: standardReps,
                              child: const ColoredBox(
                                color: _CalmAthleticismReportTokens.statusValid,
                              ),
                            ),
                          if (needsImprovementReps > 0)
                            Expanded(
                              flex: needsImprovementReps,
                              child: const ColoredBox(
                                color:
                                    _CalmAthleticismReportTokens.statusWarning,
                              ),
                            ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 6,
            spacing: 12,
            children: [
              _ProgressLegendItem(
                dotColor: _CalmAthleticismReportTokens.statusValid,
                label: '$standardReps Rep đạt chuẩn ($standardPct%)',
              ),
              _ProgressLegendItem(
                dotColor: _CalmAthleticismReportTokens.statusWarning,
                label: '$needsImprovementReps Cần cải thiện ($improvementPct%)',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressLegendItem extends StatelessWidget {
  final Color dotColor;
  final String label;

  const _ProgressLegendItem({
    required this.dotColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: _CalmAthleticismReportTokens.mono(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: _CalmAthleticismReportTokens.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _CriteriaBanner extends StatelessWidget {
  const _CriteriaBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _CalmAthleticismReportTokens.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _CalmAthleticismReportTokens.border,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _CalmAthleticismReportTokens.iconContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _CalmAthleticismReportTokens.border,
                width: 1,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.info_outline,
                size: 14,
                color: _CalmAthleticismReportTokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'MỨC CHUẨN ĐỘNG TÁC',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _CalmAthleticismReportTokens.mono(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _CalmAthleticismReportTokens.textSecondary,
                letterSpacing: 0.7,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Góc < 45°',
                style: _CalmAthleticismReportTokens.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _CalmAthleticismReportTokens.textHeadline,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '·',
                  style: _CalmAthleticismReportTokens.mono(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _CalmAthleticismReportTokens.textSecondary,
                  ),
                ),
              ),
              Text(
                '2–3s',
                style: _CalmAthleticismReportTokens.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _CalmAthleticismReportTokens.textHeadline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RepBreakdownSection extends StatelessWidget {
  final List<LatPulldownRepEvent> repHistory;
  final int? selectedRepNumber;
  final void Function(LatPulldownRepEvent rep, int displayIndex) onRepTap;

  const _RepBreakdownSection({
    required this.repHistory,
    required this.selectedRepNumber,
    required this.onRepTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CHI TIẾT TỪNG REP',
                style: _CalmAthleticismReportTokens.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _CalmAthleticismReportTokens.textSecondary,
                  letterSpacing: 0.7,
                ),
              ),
              Text(
                '${repHistory.length} reps đã phân tích',
                style: _CalmAthleticismReportTokens.mono(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: _CalmAthleticismReportTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: _CalmAthleticismReportTokens.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _CalmAthleticismReportTokens.border,
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: repHistory.isEmpty
              ? const _EmptyRepHistoryCard()
              : Column(
                  children: [
                    for (int index = 0; index < repHistory.length; index++) ...[
                      if (index > 0)
                        const Divider(
                          height: 1,
                          thickness: 1,
                          color: _CalmAthleticismReportTokens.border,
                        ),
                      _RepResultRow(
                        key: ValueKey(
                          'cv_result_rep_${repHistory[index].repNumber}_$index',
                        ),
                        rep: repHistory[index],
                        displayIndex: repHistory[index].repNumber > 0
                            ? repHistory[index].repNumber
                            : index + 1,
                        isSelected: selectedRepNumber ==
                            (repHistory[index].repNumber > 0
                                ? repHistory[index].repNumber
                                : index + 1),
                        onTap: () => onRepTap(
                          repHistory[index],
                          repHistory[index].repNumber > 0
                              ? repHistory[index].repNumber
                              : index + 1,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _RepResultRow extends StatelessWidget {
  final LatPulldownRepEvent rep;
  final int displayIndex;
  final bool isSelected;
  final VoidCallback onTap;

  const _RepResultRow({
    super.key,
    required this.rep,
    required this.displayIndex,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final durationSec = rep.durationMs / 1000.0;
    final isStandardMet = WorkoutCvResultScreen.isRepStandardMet(rep);
    final statusColor = isStandardMet
        ? _CalmAthleticismReportTokens.statusValid
        : _CalmAthleticismReportTokens.statusWarning;

    final durationText = durationSec.toStringAsFixed(1);
    final angleText = rep.minElbowAngleDeg.toStringAsFixed(1);

    return Material(
      color: isSelected
          ? _CalmAthleticismReportTokens.cardHover
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _CalmAthleticismReportTokens.iconContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _CalmAthleticismReportTokens.border,
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Icon(
                    isStandardMet
                        ? Icons.check_circle_outline_rounded
                        : Icons.warning_amber_rounded,
                    color: statusColor,
                    size: 27,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Rep $displayIndex',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _CalmAthleticismReportTokens.body(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _CalmAthleticismReportTokens.textHeadline,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        text: '${durationText}s ',
                        style: _CalmAthleticismReportTokens.mono(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: _CalmAthleticismReportTokens.textSubtle,
                        ),
                        children: [
                          TextSpan(
                            text: '• ',
                            style: _CalmAthleticismReportTokens.mono(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: _CalmAthleticismReportTokens.textSecondary,
                            ),
                          ),
                          TextSpan(
                            text: 'Góc khuỷu tay: $angleText°',
                            style: _CalmAthleticismReportTokens.mono(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: _CalmAthleticismReportTokens.textSubtle,
                            ),
                          ),
                        ],
                      ),
                      softWrap: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _NeutralStatusBadge(
                dotColor: statusColor,
                label: isStandardMet ? 'ĐẠT CHUẨN' : 'CẦN CẢI THIỆN',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeutralStatusBadge extends StatelessWidget {
  final Color dotColor;
  final String label;
  final bool isBoldLabel;

  const _NeutralStatusBadge({
    required this.dotColor,
    required this.label,
    this.isBoldLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _CalmAthleticismReportTokens.iconContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _CalmAthleticismReportTokens.border,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: _CalmAthleticismReportTokens.mono(
              fontSize: 11,
              fontWeight: isBoldLabel ? FontWeight.w700 : FontWeight.w500,
              color: _CalmAthleticismReportTokens.textSubtle,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRepHistoryCard extends StatelessWidget {
  const _EmptyRepHistoryCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _CalmAthleticismReportTokens.iconContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _CalmAthleticismReportTokens.border,
                width: 1,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.info_outline,
                color: _CalmAthleticismReportTokens.statusWarning,
                size: 26,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Chưa ghi nhận Rep hợp lệ nào trong phiên này.',
            textAlign: TextAlign.center,
            style: _CalmAthleticismReportTokens.body(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: _CalmAthleticismReportTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyBottomCta extends StatelessWidget {
  final VoidCallback onDone;

  const _StickyBottomCta({
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _CalmAthleticismReportTokens.canvas,
        border: Border(
          top: BorderSide(
            color: _CalmAthleticismReportTokens.border,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Center(
            heightFactor: 1.0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  key: const ValueKey('workout_cv_result_done_button'),
                  onPressed: onDone,
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 20,
                    color: _CalmAthleticismReportTokens.canvas,
                  ),
                  label: Text(
                    'Hoàn thành',
                    style: _CalmAthleticismReportTokens.body(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _CalmAthleticismReportTokens.canvas,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _CalmAthleticismReportTokens.textPrimary,
                    foregroundColor: _CalmAthleticismReportTokens.canvas,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
