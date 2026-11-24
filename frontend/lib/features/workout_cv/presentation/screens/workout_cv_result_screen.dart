import 'dart:async';
import 'dart:ui' show FontFeature, ImageFilter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../config/app_translations.dart';
import '../../../community/domain/models/community_post.dart';
import '../../../community/domain/models/post_attachment_snapshot.dart';
import '../../../community/presentation/providers/community_composer_provider.dart';
import '../../../community/presentation/screens/compose/post_compose_publish_screen.dart';
import '../../../community/presentation/widgets/community_create_story_sheet.dart';
import '../../data/datasources/workout_cv_replay_source.dart';
import '../../domain/entities/exercise_cv_state.dart';
import '../../domain/services/cv_form_summary_calculator.dart';
import '../../domain/services/lat_pulldown_baseline.dart';
import '../../domain/services/workout_cv_exercise_registry.dart';
import '../controllers/workout_cv_controller.dart';
import '../widgets/pose_skeleton_painter.dart';

/// Calm Athleticism adaptive tokens for CV Report Screen (Light + Dark).
class _CalmAthleticismReportTokens {
  const _CalmAthleticismReportTokens({
    required this.canvas,
    required this.cardSurface,
    required this.cardHover,
    required this.border,
    required this.iconContainer,
    required this.videoBackdrop,
    required this.textPrimary,
    required this.textHeadline,
    required this.textSecondary,
    required this.textSubtle,
    required this.statusValid,
    required this.statusWarning,
    required this.ctaBackground,
    required this.ctaForeground,
  });

  final Color canvas;
  final Color cardSurface;
  final Color cardHover;
  final Color border;
  final Color iconContainer;
  final Color videoBackdrop;
  final Color textPrimary;
  final Color textHeadline;
  final Color textSecondary;
  final Color textSubtle;
  final Color statusValid;
  final Color statusWarning;
  final Color ctaBackground;
  final Color ctaForeground;

  static const _CalmAthleticismReportTokens dark = _CalmAthleticismReportTokens(
    canvas: Color(0xFF0C0D0E),
    cardSurface: Color(0xFF16171B),
    cardHover: Color(0xFF1F2126),
    border: Color(0xFF26282F),
    iconContainer: Color(0xFF212328),
    videoBackdrop: Color(0xFF000000),
    textPrimary: Color(0xFFF9FAFB),
    textHeadline: Color(0xFFF3F4F6),
    textSecondary: Color(0xFF94979E),
    textSubtle: Color(0xFFCBD5E1),
    statusValid: Color(0xFF10B981),
    statusWarning: Color(0xFFF59E0B),
    ctaBackground: Color(0xFFF9FAFB),
    ctaForeground: Color(0xFF0C0D0E),
  );

  static const _CalmAthleticismReportTokens light = _CalmAthleticismReportTokens(
    canvas: Color(0xFFF8FAFC),
    cardSurface: Color(0xFFFFFFFF),
    cardHover: Color(0xFFF1F5F9),
    border: Color(0xFFE2E8F0),
    iconContainer: Color(0xFFF1F5F9),
    videoBackdrop: Color(0xFF000000),
    textPrimary: Color(0xFF0F172A),
    textHeadline: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textSubtle: Color(0xFF334155),
    statusValid: Color(0xFF059669),
    statusWarning: Color(0xFFD97706),
    ctaBackground: Color(0xFF059669),
    ctaForeground: Color(0xFFFFFFFF),
  );

  static _CalmAthleticismReportTokens of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  static TextStyle headline({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w600,
    required Color color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: 'Manrope',
      fontFamilyFallback: const ['sans-serif'],
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
    required Color color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: 'Manrope',
      fontFamilyFallback: const ['sans-serif'],
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
    required Color color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Courier New'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}

bool _isVietnameseLocale(BuildContext context) =>
    Localizations.maybeLocaleOf(context)?.languageCode == 'vi';

class WorkoutCvResultScreen extends ConsumerStatefulWidget {
  final List<LatPulldownRepEvent> repHistory;
  final String? exerciseName;
  final String exerciseId;
  final String exerciseSlug;
  final String? replayVideoPath;
  final WorkoutCvReplaySource? replaySource;
  final VoidCallback? onDone;
  final CvFormSummary? formSummary;

  const WorkoutCvResultScreen({
    super.key,
    required this.repHistory,
    this.exerciseName,
    this.exerciseId = '',
    this.exerciseSlug = '',
    this.replayVideoPath,
    this.replaySource,
    this.onDone,
    this.formSummary,
  });

  static bool isRepStandardMet(
    LatPulldownRepEvent rep, {
    CvExerciseModule? module,
  }) {
    return CvFormSummaryCalculator.isRepStandardMet(rep, module: module);
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

  CvExerciseModule? _resolveModule(ExerciseCvState cvState) {
    final effectiveId =
        widget.exerciseId.isNotEmpty ? widget.exerciseId : cvState.exerciseId;
    final effectiveSlug = widget.exerciseSlug.isNotEmpty
        ? widget.exerciseSlug
        : cvState.exerciseSlug;
    return WorkoutCvExerciseRegistry.resolveModule(
      id: effectiveId,
      slug: effectiveSlug,
    );
  }

  String _effectiveReplaySlug(ExerciseCvState cvState) {
    if (widget.exerciseSlug.isNotEmpty) return widget.exerciseSlug;
    if (cvState.exerciseSlug.isNotEmpty) return cvState.exerciseSlug;
    return 'lat-pulldown';
  }

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

    final cvState = _currentCvState();
    final effectiveSlug = _effectiveReplaySlug(cvState);

    final directReplaySource = widget.replaySource;
    if (directReplaySource != null) {
      if (!directReplaySource.isPlaying) {
        await directReplaySource.startSession(effectiveSlug);
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
        await nativeSource.startSession(effectiveSlug);
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
    final module = _resolveModule(cvState);
    final effectiveReps = widget.repHistory.isNotEmpty
        ? widget.repHistory
        : cvState.replayRepEvents;
    final summaryToReturn = widget.formSummary ??
        CvFormSummaryCalculator.compute(
          reps: effectiveReps,
          module: module,
        );
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).pop<CvFormSummary>(summaryToReturn);
    }
  }

  Future<void> _showShareSheet({
    required int totalReps,
    required int standardReps,
    required CvExerciseModule? module,
  }) async {
    final t = _CalmAthleticismReportTokens.of(context);
    final isVi = _isVietnameseLocale(context);
    final rawName = widget.exerciseName?.trim() ?? '';
    final exerciseLabel =
        rawName.isNotEmpty ? rawName : (module?.name ?? 'Workout CV');
    final standardPct =
        totalReps > 0 ? ((standardReps / totalReps) * 100).round() : 0;
    final summaryLabel = isVi
        ? '$standardReps/$totalReps ($standardPct% Chuẩn)'
        : '$standardReps/$totalReps ($standardPct% Form)';
    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(DateTime.now());

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sheetContext.tr('workout_share_sheet_title'),
                  style: _CalmAthleticismReportTokens.headline(
                    fontSize: 16,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sheetContext.tr('workout_share_sheet_subtitle'),
                  style: _CalmAthleticismReportTokens.body(
                    fontSize: 12,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  key: const ValueKey('workout_cv_share_post_option'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: CircleAvatar(
                    backgroundColor: t.iconContainer,
                    child: Icon(Icons.post_add_outlined, color: t.statusValid),
                  ),
                  title: Text(
                    sheetContext.tr('workout_share_post_title'),
                    style: _CalmAthleticismReportTokens.body(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '$exerciseLabel • $summaryLabel',
                    style: _CalmAthleticismReportTokens.body(
                      fontSize: 12,
                      color: t.textSecondary,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    final exId = widget.exerciseId.trim().isNotEmpty
                        ? widget.exerciseId.trim()
                        : (module?.name ?? 'cv');
                    final snapshot = PostAttachmentSnapshot(
                      type: AttachmentType.workout,
                      id: 'cv_${exId}_${DateTime.now().millisecondsSinceEpoch}',
                      title: '$exerciseLabel — $summaryLabel',
                      dateFormatted: dateStr,
                      category: 'Saman Workout CV',
                      includeDuration: true,
                      includeExercisesOrFoods: true,
                      includeLoadOrMacros: false,
                      exerciseCount: 1,
                      exercises: [
                        ExerciseThumbnailPreview(
                          title: '$exerciseLabel ($summaryLabel)',
                        ),
                      ],
                      sharedSnapshot: <String, dynamic>{
                        'exercise_count': 1,
                        'exercises': <Map<String, dynamic>>[
                          <String, dynamic>{
                            'name': '$exerciseLabel ($summaryLabel)',
                          },
                        ],
                      },
                    ).sanitize();

                    final composerNotifier =
                        ref.read(communityComposerProvider.notifier);
                    if (!ref
                        .read(communityComposerProvider)
                        .hasPendingSubmission) {
                      composerNotifier.reset();
                    }
                    composerNotifier.setAttachment(snapshot);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PostComposePublishScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  key: const ValueKey('workout_cv_share_story_option'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: CircleAvatar(
                    backgroundColor: t.iconContainer,
                    child: Icon(
                      Icons.auto_awesome_outlined,
                      color: t.statusValid,
                    ),
                  ),
                  title: Text(
                    sheetContext.tr('workout_share_story_title'),
                    style: _CalmAthleticismReportTokens.body(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '$exerciseLabel • $summaryLabel',
                    style: _CalmAthleticismReportTokens.body(
                      fontSize: 12,
                      color: t.textSecondary,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    final prefill = context
                        .tr('workout_cv_share_story_prefill')
                        .replaceAll('{exercise}', exerciseLabel)
                        .replaceAll('{standard}', '$standardReps')
                        .replaceAll('{total}', '$totalReps')
                        .replaceAll('{pct}', '$standardPct');
                    CommunityCreateStorySheet.show(
                      context,
                      initialCaption: prefill,
                      initialPrivacy: 'followers_only',
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _CalmAthleticismReportTokens.of(context);
    final cvState = _hasScope
        ? ref.watch(workoutCvControllerProvider)
        : const ExerciseCvState();
    final module = _resolveModule(cvState);
    final criteria = ExerciseFormCriteria.forModule(module);

    final effectiveReps = widget.repHistory.isNotEmpty
        ? widget.repHistory
        : cvState.replayRepEvents;
    final totalReps = effectiveReps.length;
    final standardCount = effectiveReps
        .where(
          (rep) => WorkoutCvResultScreen.isRepStandardMet(
            rep,
            module: module,
          ),
        )
        .length;
    final isPlaying = _isPlayingNow(cvState);

    return Scaffold(
      backgroundColor: t.canvas,
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
                  _CriteriaBanner(
                    key: const ValueKey('workout_cv_result_criteria_banner'),
                    criteria: criteria,
                  ),
                  const SizedBox(height: 16),
                  _RepBreakdownSection(
                    repHistory: effectiveReps,
                    module: module,
                    criteria: criteria,
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
        onShare: () => _showShareSheet(
          totalReps: totalReps,
          standardReps: standardCount,
          module: module,
        ),
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
    final t = _CalmAthleticismReportTokens.of(context);
    final isVi = _isVietnameseLocale(context);
    final trimmedName = exerciseName?.trim() ?? '';
    final hasExerciseName = trimmedName.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Material(
              color: t.cardSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: t.border,
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('workout_cv_result_back_button'),
                onTap: onBack,
                child: Center(
                  child: Icon(
                    Icons.arrow_back,
                    size: 20,
                    color: t.textSecondary,
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
                    text: isVi ? 'Báo cáo CV' : 'CV Report',
                    style: _CalmAthleticismReportTokens.headline(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                      height: 1.2,
                      letterSpacing: -0.3,
                    ),
                    children: [
                      if (hasExerciseName)
                        TextSpan(
                          text: ' · $trimmedName',
                          style: _CalmAthleticismReportTokens.headline(
                            fontSize: 18,
                            fontWeight: FontWeight.w400,
                            color: t.textSecondary,
                            height: 1.2,
                            letterSpacing: -0.3,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isVi ? 'PHÂN TÍCH THỊ GIÁC MÁY' : 'COMPUTER VISION ANALYSIS',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _CalmAthleticismReportTokens.mono(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: t.textSecondary,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _NeutralStatusBadge(
              dotColor: t.statusValid,
              label: isVi ? 'AI XÁC THỰC' : 'AI VERIFIED',
            ),
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
    const dark = _CalmAthleticismReportTokens.dark;
    final isVi = _isVietnameseLocale(context);
    final hasError = cvState.trackingStatus == TrackingStatus.error;
    final canRenderNativeView =
        supportsNativeVideoView && cvState.isCameraActive && !hasError;
    final clipLabel = cvState.clipName.trim().isNotEmpty
        ? cvState.clipName.trim()
        : (exerciseName?.trim().isNotEmpty == true
            ? exerciseName!.trim()
            : (isVi ? 'Phát lại buổi tập' : 'Session Replay'));

    final activePtsMs = cvState.videoPtsMs > 0
        ? cvState.videoPtsMs
        : (seekTimestampMs ??
            (repHistory.isNotEmpty ? repHistory.first.startTimestampMs : 0));

    return SizedBox(
      height: _cardHeight,
      child: Container(
        decoration: BoxDecoration(
          color: dark.videoBackdrop,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _CalmAthleticismReportTokens.of(context).border,
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
                                  dark.canvas.withOpacity(0.80),
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
                                  color: dark.iconContainer.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: dark.border,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  selectedRepNumber != null
                                      ? 'REP $selectedRepNumber · ${_formatMsToSeconds(activePtsMs)}'
                                      : (isPlaying
                                          ? (isVi
                                              ? 'PHÁT LẠI · ${_formatMsToSeconds(activePtsMs)}'
                                              : 'REPLAY · ${_formatMsToSeconds(activePtsMs)}')
                                          : (isVi
                                              ? 'PHÁT LẠI BUỔI TẬP'
                                              : 'SESSION REPLAY')),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _CalmAthleticismReportTokens.mono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: dark.textSubtle,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Material(
                              color: dark.iconContainer.withOpacity(0.85),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(
                                  color: dark.border,
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
                                            ? dark.statusValid
                                            : dark.textSecondary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        showSkeletonOverlay
                                            ? (isVi
                                                ? 'KHUNG XƯƠNG BẬT'
                                                : 'SKELETON ON')
                                            : (isVi
                                                ? 'KHUNG XƯƠNG TẮT'
                                                : 'SKELETON OFF'),
                                        style:
                                            _CalmAthleticismReportTokens.mono(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: dark.textSubtle,
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
                                  color: dark.iconContainer.withOpacity(0.80),
                                  shape: CircleBorder(
                                    side: BorderSide(
                                      color: dark.border,
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
                                        color: dark.textHeadline,
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
                                      ? (isVi
                                          ? 'Video phiên tập chưa sẵn sàng để phát lại'
                                          : 'Session video is not ready for replay')
                                      : (selectedRepNumber != null
                                          ? (isVi
                                              ? 'Đang định vị mốc Rep $selectedRepNumber (${_formatMsToSeconds(activePtsMs)})'
                                              : 'Seeking to Rep $selectedRepNumber (${_formatMsToSeconds(activePtsMs)})')
                                          : clipLabel),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _CalmAthleticismReportTokens.mono(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                    color: dark.textSecondary,
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
                                    color: dark.textSubtle,
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

  String _message(bool isVi) {
    if (hasError) {
      return isVi
          ? 'Không thể tải video phiên tập trên thiết bị này'
          : 'Unable to load session video on this device';
    }
    if (!hasReplay) {
      return isVi
          ? 'Phiên này không có video ghi lại để phát lại'
          : 'No recorded video is available for replay in this session';
    }
    if (isLoading) {
      return isVi ? 'Đang tải video phiên tập…' : 'Loading session video…';
    }
    if (selectedRepNumber != null && seekTimestampMs != null) {
      return isVi
          ? 'Đã chọn Rep $selectedRepNumber • Nhấn Phát để xem lại'
          : 'Selected Rep $selectedRepNumber • Tap Play to replay';
    }
    if (repCount > 0) {
      return isVi
          ? 'Nhấn Phát hoặc chạm vào từng Rep để xem lại'
          : 'Tap Play or select a Rep to review';
    }
    return isVi
        ? 'Chưa có bản ghi video trong phiên này'
        : 'No video recording captured in this session';
  }

  @override
  Widget build(BuildContext context) {
    const dark = _CalmAthleticismReportTokens.dark;
    final isVi = _isVietnameseLocale(context);
    return ColoredBox(
      color: dark.cardSurface,
      child: CustomPaint(
        painter: _TelemetryFrameGuidePainter(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              _message(isVi),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: _CalmAthleticismReportTokens.body(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: dark.textSecondary,
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
      ..color = _CalmAthleticismReportTokens.dark.border.withOpacity(0.65)
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
    final t = _CalmAthleticismReportTokens.of(context);
    final isVi = _isVietnameseLocale(context);
    final needsImprovementReps = (totalReps - standardReps).clamp(0, totalReps);
    final standardPct =
        totalReps > 0 ? ((standardReps * 100) / totalReps).round() : 0;
    final improvementPct = totalReps > 0 ? (100 - standardPct) : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: t.border,
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
                  color: t.iconContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: t.border,
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.fitness_center,
                    size: 18,
                    color: t.statusValid,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isVi ? 'TỔNG SỐ REP HỢP LỆ' : 'TOTAL VALID REPS',
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: _CalmAthleticismReportTokens.mono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: t.textSecondary,
                    height: 1.25,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _NeutralStatusBadge(
                dotColor: t.statusValid,
                label: isVi
                    ? 'ĐẠT CHUẨN: $standardReps/$totalReps REP'
                    : 'STANDARD: $standardReps/$totalReps REPS',
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
                  color: t.textHeadline,
                  height: 1.0,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isVi ? 'Rep' : (totalReps == 1 ? 'Rep' : 'Reps'),
                style: _CalmAthleticismReportTokens.body(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: t.textSecondary,
                  height: 1.0,
                ),
              ),
              const Spacer(),
              _NeutralStatusBadge(
                dotColor: t.statusValid,
                label: '$standardPct%',
                isBoldLabel: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            thickness: 1,
            color: t.border,
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 4,
              width: double.infinity,
              child: ColoredBox(
                color: t.iconContainer,
                child: totalReps > 0
                    ? Row(
                        children: [
                          if (standardReps > 0)
                            Expanded(
                              flex: standardReps,
                              child: ColoredBox(
                                color: t.statusValid,
                              ),
                            ),
                          if (needsImprovementReps > 0)
                            Expanded(
                              flex: needsImprovementReps,
                              child: ColoredBox(
                                color: t.statusWarning,
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
                dotColor: t.statusValid,
                label: isVi
                    ? '$standardReps Rep đạt chuẩn ($standardPct%)'
                    : '$standardReps Standard ($standardPct%)',
              ),
              _ProgressLegendItem(
                dotColor: t.statusWarning,
                label: isVi
                    ? '$needsImprovementReps Cần cải thiện ($improvementPct%)'
                    : '$needsImprovementReps Needs work ($improvementPct%)',
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
    final t = _CalmAthleticismReportTokens.of(context);
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
            color: t.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _CriteriaBanner extends StatelessWidget {
  final ExerciseFormCriteria criteria;

  const _CriteriaBanner({
    super.key,
    required this.criteria,
  });

  @override
  Widget build(BuildContext context) {
    final t = _CalmAthleticismReportTokens.of(context);
    final isVi = _isVietnameseLocale(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: t.border,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: t.iconContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: t.border,
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.info_outline,
                size: 14,
                color: t.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isVi ? 'MỨC CHUẨN ĐỘNG TÁC' : 'FORM CRITERIA',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _CalmAthleticismReportTokens.mono(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: t.textSecondary,
                letterSpacing: 0.7,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                criteria.localizedCriteriaDisplayText(isVietnamese: isVi),
                style: _CalmAthleticismReportTokens.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: t.textHeadline,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '·',
                  style: _CalmAthleticismReportTokens.mono(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.textSecondary,
                  ),
                ),
              ),
              Text(
                criteria.tempoDisplayText,
                style: _CalmAthleticismReportTokens.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: t.textHeadline,
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
  final CvExerciseModule? module;
  final ExerciseFormCriteria criteria;
  final int? selectedRepNumber;
  final void Function(LatPulldownRepEvent rep, int displayIndex) onRepTap;

  const _RepBreakdownSection({
    required this.repHistory,
    required this.module,
    required this.criteria,
    required this.selectedRepNumber,
    required this.onRepTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = _CalmAthleticismReportTokens.of(context);
    final isVi = _isVietnameseLocale(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  isVi ? 'CHI TIẾT TỪNG REP' : 'REP BREAKDOWN',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _CalmAthleticismReportTokens.mono(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.textSecondary,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  isVi
                      ? '${repHistory.length} reps đã phân tích'
                      : '${repHistory.length} ${repHistory.length == 1 ? 'rep' : 'reps'} analyzed',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: _CalmAthleticismReportTokens.mono(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: t.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: t.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: t.border,
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
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: t.border,
                        ),
                      _RepResultRow(
                        key: ValueKey(
                          'cv_result_rep_${repHistory[index].repNumber}_$index',
                        ),
                        rep: repHistory[index],
                        module: module,
                        criteria: criteria,
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
  final CvExerciseModule? module;
  final ExerciseFormCriteria criteria;
  final int displayIndex;
  final bool isSelected;
  final VoidCallback onTap;

  const _RepResultRow({
    super.key,
    required this.rep,
    required this.module,
    required this.criteria,
    required this.displayIndex,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = _CalmAthleticismReportTokens.of(context);
    final isVi = _isVietnameseLocale(context);
    final durationSec = rep.durationMs / 1000.0;
    final isStandardMet =
        WorkoutCvResultScreen.isRepStandardMet(rep, module: module);
    final statusColor = isStandardMet ? t.statusValid : t.statusWarning;

    final durationText = durationSec.toStringAsFixed(1);
    final angleText = rep.minElbowAngleDeg.toStringAsFixed(1);

    return Material(
      color: isSelected ? t.cardHover : Colors.transparent,
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
                  color: t.iconContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: t.border,
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
                        color: t.textHeadline,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        text: '${durationText}s ',
                        style: _CalmAthleticismReportTokens.mono(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: t.textSubtle,
                        ),
                        children: [
                          TextSpan(
                            text: '• ',
                            style: _CalmAthleticismReportTokens.mono(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: t.textSecondary,
                            ),
                          ),
                          TextSpan(
                            text:
                                '${criteria.localizedAngleMetricLabel(isVietnamese: isVi)}: $angleText°',
                            style: _CalmAthleticismReportTokens.mono(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: t.textSubtle,
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
                label: isStandardMet
                    ? (isVi ? 'ĐẠT CHUẨN' : 'STANDARD')
                    : (isVi ? 'CẦN CẢI THIỆN' : 'NEEDS WORK'),
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
    final t = _CalmAthleticismReportTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: t.iconContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: t.border,
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
              color: t.textSubtle,
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
    final t = _CalmAthleticismReportTokens.of(context);
    final isVi = _isVietnameseLocale(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: t.iconContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: t.border,
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.info_outline,
                color: t.statusWarning,
                size: 26,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isVi
                ? 'Chưa ghi nhận Rep hợp lệ nào trong phiên này.'
                : 'No completed reps were recorded in this session.',
            textAlign: TextAlign.center,
            style: _CalmAthleticismReportTokens.body(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyBottomCta extends StatelessWidget {
  final VoidCallback onDone;
  final VoidCallback onShare;

  const _StickyBottomCta({
    required this.onDone,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final t = _CalmAthleticismReportTokens.of(context);
    final isVi = _isVietnameseLocale(context);
    return Container(
      decoration: BoxDecoration(
        color: t.canvas,
        border: Border(
          top: BorderSide(
            color: t.border,
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
              child: Row(
                children: [
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      key: const ValueKey('workout_cv_result_share_button'),
                      onPressed: onShare,
                      icon: Icon(
                        Icons.share_outlined,
                        size: 18,
                        color: t.textPrimary,
                      ),
                      label: Text(
                        context.tr('workout_share_short_cta'),
                        style: _CalmAthleticismReportTokens.body(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: t.cardSurface,
                        side: BorderSide(color: t.border),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        key: const ValueKey('workout_cv_result_done_button'),
                        onPressed: onDone,
                        icon: Icon(
                          Icons.check_circle_outline_rounded,
                          size: 20,
                          color: t.ctaForeground,
                        ),
                        label: Text(
                          isVi ? 'Hoàn thành' : 'Done',
                          style: _CalmAthleticismReportTokens.body(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: t.ctaForeground,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.ctaBackground,
                          foregroundColor: t.ctaForeground,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
