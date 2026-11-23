import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../../widgets/saman_feedback_snackbar.dart';
import '../../../domain/models/community_dm.dart';
import '../../../domain/models/community_story.dart';
import '../../providers/community_dm_provider.dart';
import '../../providers/community_social_providers.dart';
import '../../tokens/saman_ig_tokens.dart';

enum _SamanCheckInKind { workout, meal }

class _ParsedStoryContent {
  const _ParsedStoryContent({
    required this.captionText,
    this.checkInKind,
    this.checkInSummary,
  });

  final String captionText;
  final _SamanCheckInKind? checkInKind;
  final String? checkInSummary;

  bool get hasCheckIn =>
      checkInKind != null &&
      checkInSummary != null &&
      checkInSummary!.isNotEmpty;
}

_ParsedStoryContent _parseStoryContent(String rawCaption) {
  const workoutPrefix = '[SAMAN_WORKOUT]';
  const mealPrefix = '[SAMAN_MEAL]';

  final lines = rawCaption.split('\n');
  _SamanCheckInKind? kind;
  String? summary;
  final remaining = <String>[];

  for (final rawLine in lines) {
    final trimmed = rawLine.trim();
    if (kind == null && trimmed.startsWith(workoutPrefix)) {
      kind = _SamanCheckInKind.workout;
      summary = trimmed.substring(workoutPrefix.length).trim();
    } else if (kind == null && trimmed.startsWith(mealPrefix)) {
      kind = _SamanCheckInKind.meal;
      summary = trimmed.substring(mealPrefix.length).trim();
    } else {
      remaining.add(rawLine);
    }
  }

  return _ParsedStoryContent(
    captionText: remaining.join('\n').trim(),
    checkInKind: kind,
    checkInSummary: summary,
  );
}

class CommunityStoryViewerScreen extends ConsumerStatefulWidget {
  const CommunityStoryViewerScreen({
    super.key,
    required this.groups,
    this.initialGroupIndex = 0,
  });

  final List<CommunityStoryAuthorGroup> groups;
  final int initialGroupIndex;

  @override
  ConsumerState<CommunityStoryViewerScreen> createState() =>
      _CommunityStoryViewerScreenState();
}

class _CommunityStoryViewerScreenState
    extends ConsumerState<CommunityStoryViewerScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _defaultStoryDuration = Duration(seconds: 5);
  static const Duration _maxVideoDuration = Duration(seconds: 30);
  static const List<String> _quickReactions = <String>[
    '❤️',
    '🔥',
    '👏',
    '💪',
    '😍',
    '😂',
  ];

  late List<CommunityStoryAuthorGroup> _groups;
  late int _groupIndex;
  int _storyIndex = 0;

  late final AnimationController _progressController;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  final Set<String> _markedViewedIds = <String>{};

  VideoPlayerController? _videoController;
  int _mediaLoadGeneration = 0;
  bool _isPaused = false;
  bool _isHolding = false;
  bool _isVideoReady = false;
  bool _hasVideoError = false;
  bool _isSendingReply = false;
  bool _isDeleting = false;
  String? _activeReactionOverlay;
  Timer? _reactionOverlayTimer;

  @override
  void initState() {
    super.initState();
    _groups = widget.groups.where((g) => g.stories.isNotEmpty).toList();
    _groupIndex = _groups.isEmpty
        ? 0
        : widget.initialGroupIndex.clamp(0, _groups.length - 1);

    if (_groups.isNotEmpty) {
      final initialStories = _groups[_groupIndex].stories;
      final firstUnviewed = initialStories.indexWhere((s) => !s.isViewed);
      _storyIndex = firstUnviewed >= 0 ? firstUnviewed : 0;
    }

    _progressController = AnimationController(
      vsync: this,
      duration: _defaultStoryDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted && !_isPaused) {
          _nextStory();
        }
      });

    _replyFocusNode.addListener(_handleReplyFocusChange);

    if (_groups.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadCurrentStory();
      });
    }
  }

  @override
  void dispose() {
    _mediaLoadGeneration++;
    _reactionOverlayTimer?.cancel();
    _replyFocusNode.removeListener(_handleReplyFocusChange);
    _replyFocusNode.dispose();
    _replyController.dispose();
    _progressController.dispose();
    _disposeVideoController();
    super.dispose();
  }

  void _handleReplyFocusChange() {
    if (_replyFocusNode.hasFocus) {
      _pausePlayback();
    } else if (!_isDeleting && !_isHolding) {
      _resumePlayback();
    }
  }

  void _disposeVideoController() {
    final controller = _videoController;
    _videoController = null;
    if (controller != null) {
      controller.removeListener(_onVideoTick);
      controller.dispose();
    }
  }

  CommunityStoryAuthorGroup? get _currentGroup =>
      _groups.isNotEmpty && _groupIndex >= 0 && _groupIndex < _groups.length
          ? _groups[_groupIndex]
          : null;

  CommunityStory? get _currentStory {
    final group = _currentGroup;
    if (group == null ||
        _storyIndex < 0 ||
        _storyIndex >= group.stories.length) {
      return null;
    }
    return group.stories[_storyIndex];
  }

  Future<void> _loadCurrentStory() async {
    final group = _currentGroup;
    final story = _currentStory;
    if (group == null || story == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final gen = ++_mediaLoadGeneration;
    _progressController.stop();
    _progressController.reset();
    _disposeVideoController();

    setState(() {
      _isVideoReady = false;
      _hasVideoError = false;
      _isHolding = false;
      _isPaused = _replyFocusNode.hasFocus;
    });

    if (!group.isSelf && !_markedViewedIds.contains(story.id)) {
      _markedViewedIds.add(story.id);
      unawaited(
        ref
            .read(communityStoriesProvider.notifier)
            .markStoryViewed(story.id)
            .catchError((_) {}),
      );
    }

    if (story.mediaType == 'video') {
      final url = story.mediaUrl?.trim() ?? '';
      final uri = Uri.tryParse(url);
      if (url.isEmpty || uri == null || !uri.hasScheme) {
        if (!mounted || gen != _mediaLoadGeneration) return;
        setState(() => _hasVideoError = true);
        _progressController.duration = _defaultStoryDuration;
        if (!_isPaused) _progressController.forward(from: 0);
        return;
      }

      final controller = VideoPlayerController.networkUrl(uri);
      _videoController = controller;
      try {
        await controller.initialize();
        if (!mounted || gen != _mediaLoadGeneration) {
          await controller.dispose();
          return;
        }
        final rawDuration = controller.value.duration;
        final effectiveDuration = rawDuration > Duration.zero
            ? (rawDuration > _maxVideoDuration
                ? _maxVideoDuration
                : rawDuration)
            : _defaultStoryDuration;

        _progressController.duration = effectiveDuration;
        controller.addListener(_onVideoTick);
        setState(() => _isVideoReady = true);
        if (!_isPaused) {
          await controller.play();
          _progressController.forward(from: 0);
        }
      } catch (_) {
        if (!mounted || gen != _mediaLoadGeneration) return;
        _disposeVideoController();
        setState(() => _hasVideoError = true);
        _progressController.duration = _defaultStoryDuration;
        if (!_isPaused) _progressController.forward(from: 0);
      }
      return;
    }

    _progressController.duration = _defaultStoryDuration;
    if (!_isPaused) {
      _progressController.forward(from: 0);
    }
  }

  void _onVideoTick() {
    final controller = _videoController;
    if (controller == null || !mounted || _isPaused) return;
    final value = controller.value;
    if (!value.isInitialized) return;
    if (value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying &&
        _progressController.status != AnimationStatus.completed) {
      _nextStory();
    }
  }

  void _pausePlayback() {
    if (_isPaused) return;
    setState(() => _isPaused = true);
    _progressController.stop();
    _videoController?.pause();
  }

  void _resumePlayback() {
    if (!_isPaused) return;
    setState(() => _isPaused = false);
    if (_progressController.status != AnimationStatus.completed) {
      _progressController.forward();
    }
    if (_isVideoReady) {
      _videoController?.play();
    }
  }

  void _startHoldPause() {
    if (_replyFocusNode.hasFocus) return;
    setState(() => _isHolding = true);
    _pausePlayback();
  }

  void _endHoldPause() {
    if (!_isHolding) return;
    setState(() => _isHolding = false);
    if (!_replyFocusNode.hasFocus && !_isDeleting) {
      _resumePlayback();
    }
  }

  void _nextStory() {
    final group = _currentGroup;
    if (group == null) {
      Navigator.of(context).pop();
      return;
    }
    if (_storyIndex + 1 < group.stories.length) {
      setState(() => _storyIndex++);
      _loadCurrentStory();
      return;
    }
    if (_groupIndex + 1 < _groups.length) {
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
      _loadCurrentStory();
      return;
    }
    Navigator.of(context).pop();
  }

  void _previousStory() {
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _loadCurrentStory();
      return;
    }
    if (_groupIndex > 0) {
      final prevGroup = _groups[_groupIndex - 1];
      setState(() {
        _groupIndex--;
        _storyIndex =
            prevGroup.stories.isNotEmpty ? prevGroup.stories.length - 1 : 0;
      });
      _loadCurrentStory();
      return;
    }
    _loadCurrentStory();
  }

  Future<void> _confirmAndDelete(CommunityStory story) async {
    if (_isDeleting) return;
    _pausePlayback();
    setState(() => _isDeleting = true);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final ig = SamanIgTokens.of(dialogContext);
        return AlertDialog(
          backgroundColor: ig.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: ig.border, width: 1),
          ),
          title: Text(
            'Xóa tin này?',
            style: ig.displayTitle(
              color: ig.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'Tin 24h sẽ bị xóa vĩnh viễn và không thể khôi phục.',
            style: ig.body(
              color: ig.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: ig.textSecondary,
                minimumSize: const Size(0, SamanIgTokens.minTouchTarget),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Hủy',
                style: ig.buttonLabel(
                  color: ig.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: ig.danger,
                minimumSize: const Size(0, SamanIgTokens.minTouchTarget),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Xóa',
                style: ig.buttonLabel(
                  color: ig.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _isDeleting = false);
      _resumePlayback();
      return;
    }

    try {
      final deleted = await ref
          .read(communityStoriesProvider.notifier)
          .deleteStory(story.id);
      if (!mounted) return;
      if (!deleted) {
        setState(() => _isDeleting = false);
        _resumePlayback();
        SamanFeedbackSnackBar.show(
          context,
          message: 'Không thể xóa tin này',
          type: FeedbackType.error,
        );
        return;
      }

      final currentGroup = _groups[_groupIndex];
      final remainingStories =
          currentGroup.stories.where((s) => s.id != story.id).toList();
      if (remainingStories.isEmpty) {
        _groups.removeAt(_groupIndex);
        if (_groups.isEmpty) {
          Navigator.of(context).pop();
          return;
        }
        _groupIndex = _groupIndex.clamp(0, _groups.length - 1);
        _storyIndex = 0;
      } else {
        _groups[_groupIndex] = currentGroup.copyWith(stories: remainingStories);
        _storyIndex = _storyIndex.clamp(0, remainingStories.length - 1);
      }

      setState(() => _isDeleting = false);
      SamanFeedbackSnackBar.show(
        context,
        message: 'Đã xóa tin',
        type: FeedbackType.success,
      );
      _loadCurrentStory();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      _resumePlayback();
      SamanFeedbackSnackBar.show(
        context,
        message: 'Xóa tin thất bại. Vui lòng thử lại.',
        type: FeedbackType.error,
      );
    }
  }

  Future<void> _sendReplyPayload({
    required CommunityStoryAuthorGroup group,
    required CommunityStory story,
    required String content,
    bool clearInput = false,
    String? reactionEmoji,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty || _isSendingReply) return;

    setState(() {
      _isSendingReply = true;
      if (reactionEmoji != null) {
        _activeReactionOverlay = reactionEmoji;
      }
    });

    if (reactionEmoji != null) {
      _reactionOverlayTimer?.cancel();
      _reactionOverlayTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) {
          setState(() => _activeReactionOverlay = null);
        }
      });
    }

    try {
      final conv = await ref
          .read(communityInboxProvider.notifier)
          .createOrGetConversation(group.author.id);
      final sent = await ref
          .read(communityChatThreadProvider(conv.id).notifier)
          .sendMessage(
            type: DmMessageType.storyReply,
            content: trimmed,
            mediaUrl: story.mediaUrl,
          );

      if (!mounted) return;
      setState(() => _isSendingReply = false);
      if (sent == null) {
        SamanFeedbackSnackBar.show(
          context,
          message: 'Không thể gửi trả lời tin',
          type: FeedbackType.error,
        );
        return;
      }
      if (clearInput) {
        _replyController.clear();
        _replyFocusNode.unfocus();
      }
      SamanFeedbackSnackBar.show(
        context,
        message: reactionEmoji != null
            ? 'Đã gửi cảm xúc $reactionEmoji đến ${group.author.name}'
            : 'Đã gửi trả lời tin đến ${group.author.name}',
        type: FeedbackType.success,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSendingReply = false);
      SamanFeedbackSnackBar.show(
        context,
        message: 'Gửi tin nhắn thất bại. Vui lòng thử lại.',
        type: FeedbackType.error,
      );
    }
  }

  Future<void> _sendReply(
    CommunityStoryAuthorGroup group,
    CommunityStory story,
  ) {
    return _sendReplyPayload(
      group: group,
      story: story,
      content: _replyController.text,
      clearInput: true,
    );
  }

  Future<void> _sendQuickReaction(
    CommunityStoryAuthorGroup group,
    CommunityStory story,
    String emoji,
  ) {
    return _sendReplyPayload(
      group: group,
      story: story,
      content: emoji,
      reactionEmoji: emoji,
    );
  }

  Color _parseHexColor(String? hex, Color fallback) {
    final cleaned = (hex ?? '').replaceFirst('#', '').trim();
    if (cleaned.length == 6) {
      final value = int.tryParse('FF$cleaned', radix: 16);
      if (value != null) return Color(value);
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final group = _currentGroup;
    final story = _currentStory;
    if (group == null || story == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF000000),
        body: SizedBox.shrink(),
      );
    }

    final parsed = _parseStoryContent(story.caption);
    final chromeOpacity = _isHolding ? 0.0 : 1.0;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  if (_replyFocusNode.hasFocus) {
                    _replyFocusNode.unfocus();
                    return;
                  }
                  final width = MediaQuery.sizeOf(context).width;
                  if (details.localPosition.dx < width * 0.33) {
                    _previousStory();
                  } else {
                    _nextStory();
                  }
                },
                onLongPressStart: (_) => _startHoldPause(),
                onLongPressEnd: (_) => _endHoldPause(),
                onLongPressCancel: _endHoldPause,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _StoryMediaContent(
                        ig: ig,
                        story: story,
                        parsed: parsed,
                        videoController: _videoController,
                        isVideoReady: _isVideoReady,
                        hasVideoError: _hasVideoError,
                        backgroundColor: _parseHexColor(
                          story.backgroundColor,
                          const Color(0xFF1C1C1E),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: AnimatedOpacity(
                          opacity: chromeOpacity,
                          duration: const Duration(milliseconds: 160),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withOpacity(0.68),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _SegmentedProgressBar(
                                  count: group.stories.length,
                                  activeIndex: _storyIndex,
                                  animation: _progressController,
                                ),
                                const SizedBox(height: 12),
                                _StoryHeaderRow(
                                  ig: ig,
                                  group: group,
                                  story: story,
                                  onClose: () => Navigator.of(context).pop(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (story.mediaType != 'text' &&
                          (parsed.hasCheckIn || parsed.captionText.isNotEmpty))
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: AnimatedOpacity(
                            opacity: chromeOpacity,
                            duration: const Duration(milliseconds: 160),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (parsed.hasCheckIn) ...[
                                  _SamanCheckInStickerBadge(
                                    kind: parsed.checkInKind!,
                                    summary: parsed.checkInSummary!,
                                  ),
                                  if (parsed.captionText.isNotEmpty)
                                    const SizedBox(height: 10),
                                ],
                                if (parsed.captionText.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.58),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      parsed.captionText,
                                      textAlign: TextAlign.center,
                                      style: ig.body(
                                        color: Colors.white,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w500,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (_activeReactionOverlay != null)
                        IgnorePointer(
                          child: Center(
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey(_activeReactionOverlay),
                              tween: Tween(begin: 0.65, end: 1.15),
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeOutBack,
                              builder: (context, scale, child) {
                                return Transform.scale(
                                  scale: scale,
                                  child: child,
                                );
                              },
                              child: Text(
                                _activeReactionOverlay!,
                                style: const TextStyle(fontSize: 56),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedOpacity(
              opacity: chromeOpacity,
              duration: const Duration(milliseconds: 160),
              child: _StoryFooterBar(
                ig: ig,
                group: group,
                story: story,
                quickReactions: _quickReactions,
                replyController: _replyController,
                replyFocusNode: _replyFocusNode,
                isSendingReply: _isSendingReply,
                isDeleting: _isDeleting,
                onDelete: () => _confirmAndDelete(story),
                onSendReply: () => _sendReply(group, story),
                onQuickReaction: (emoji) =>
                    _sendQuickReaction(group, story, emoji),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SamanCheckInStickerBadge extends StatelessWidget {
  const _SamanCheckInStickerBadge({
    required this.kind,
    required this.summary,
  });

  final _SamanCheckInKind kind;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final isWorkout = kind == _SamanCheckInKind.workout;
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.62),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.22),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SamanIgTokens.storyGradient,
            ),
            alignment: Alignment.center,
            child: Icon(
              isWorkout
                  ? Icons.fitness_center_rounded
                  : Icons.restaurant_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isWorkout ? 'SAMAN WORKOUT' : 'SAMAN MEAL',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: SamanIgTokens.fontFamily,
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: SamanIgTokens.fontFamily,
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentedProgressBar extends StatelessWidget {
  const _SegmentedProgressBar({
    required this.count,
    required this.activeIndex,
    required this.animation,
  });

  final int count;
  final int activeIndex;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Row(
          children: List.generate(count, (index) {
            final double fill;
            if (index < activeIndex) {
              fill = 1.0;
            } else if (index == activeIndex) {
              fill = animation.value.clamp(0.0, 1.0);
            } else {
              fill = 0.0;
            }
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == count - 1 ? 0 : 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: fill,
                    minHeight: 2.5,
                    backgroundColor: Colors.white.withOpacity(0.30),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _StoryHeaderRow extends StatelessWidget {
  const _StoryHeaderRow({
    required this.ig,
    required this.group,
    required this.story,
    required this.onClose,
  });

  final SamanIgTokens ig;
  final CommunityStoryAuthorGroup group;
  final CommunityStory story;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = group.author.avatarUrl;
    return Row(
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: const Color(0xFF262626),
          backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
              ? NetworkImage(avatarUrl)
              : null,
          child: avatarUrl == null || avatarUrl.isEmpty
              ? Text(
                  group.author.name.isNotEmpty
                      ? group.author.name[0].toUpperCase()
                      : 'S',
                  style: ig.username(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      group.isSelf ? 'Tin của bạn' : group.author.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ig.username(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (group.author.isVerified) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.verified_rounded,
                      size: 14,
                      color: ig.primaryAction,
                    ),
                  ],
                  const SizedBox(width: 6),
                  Text(
                    story.timeAgo,
                    style: ig.caption(
                      color: Colors.white.withOpacity(0.72),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          constraints: const BoxConstraints(
            minWidth: SamanIgTokens.minTouchTarget,
            minHeight: SamanIgTokens.minTouchTarget,
          ),
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
          tooltip: 'Đóng',
        ),
      ],
    );
  }
}

class _StoryMediaContent extends StatelessWidget {
  const _StoryMediaContent({
    required this.ig,
    required this.story,
    required this.parsed,
    required this.videoController,
    required this.isVideoReady,
    required this.hasVideoError,
    required this.backgroundColor,
  });

  final SamanIgTokens ig;
  final CommunityStory story;
  final _ParsedStoryContent parsed;
  final VideoPlayerController? videoController;
  final bool isVideoReady;
  final bool hasVideoError;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    if (story.mediaType == 'text') {
      return Container(
        color: backgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 64),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (parsed.hasCheckIn) ...[
              _SamanCheckInStickerBadge(
                kind: parsed.checkInKind!,
                summary: parsed.checkInSummary!,
              ),
              if (parsed.captionText.isNotEmpty) const SizedBox(height: 18),
            ],
            if (parsed.captionText.isNotEmpty)
              Text(
                parsed.captionText,
                textAlign: TextAlign.center,
                style: ig.displayTitle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ).copyWith(height: 1.4),
              ),
          ],
        ),
      );
    }

    if (story.mediaType == 'video') {
      if (hasVideoError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_outlined,
                color: Colors.white54,
                size: 44,
              ),
              const SizedBox(height: 10),
              Text(
                'Không thể phát video này',
                style: ig.body(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      }
      if (!isVideoReady || videoController == null) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
      return Center(
        child: AspectRatio(
          aspectRatio: videoController!.value.aspectRatio > 0
              ? videoController!.value.aspectRatio
              : 9 / 16,
          child: VideoPlayer(videoController!),
        ),
      );
    }

    final url = story.mediaUrl ?? '';
    if (url.isEmpty) {
      return const Center(
        child:
            Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      },
      errorBuilder: (context, _, __) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 44,
            ),
            const SizedBox(height: 10),
            Text(
              'Không thể tải ảnh',
              style: ig.body(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryFooterBar extends StatelessWidget {
  const _StoryFooterBar({
    required this.ig,
    required this.group,
    required this.story,
    required this.quickReactions,
    required this.replyController,
    required this.replyFocusNode,
    required this.isSendingReply,
    required this.isDeleting,
    required this.onDelete,
    required this.onSendReply,
    required this.onQuickReaction,
  });

  final SamanIgTokens ig;
  final CommunityStoryAuthorGroup group;
  final CommunityStory story;
  final List<String> quickReactions;
  final TextEditingController replyController;
  final FocusNode replyFocusNode;
  final bool isSendingReply;
  final bool isDeleting;
  final VoidCallback onDelete;
  final VoidCallback onSendReply;
  final ValueChanged<String> onQuickReaction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      color: const Color(0xFF000000),
      child: group.isSelf
          ? Row(
              children: [
                const Icon(
                  Icons.visibility_outlined,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  '${story.viewCount} lượt xem',
                  style: ig.caption(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: isDeleting ? null : onDelete,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, SamanIgTokens.minTouchTarget),
                  ),
                  icon: isDeleting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ig.danger,
                          ),
                        )
                      : Icon(
                          Icons.delete_outline_rounded,
                          color: ig.danger,
                          size: 19,
                        ),
                  label: Text(
                    'Xóa',
                    style: ig.buttonLabel(
                      color: ig.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: quickReactions.map((emoji) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: isSendingReply
                            ? null
                            : () => onQuickReaction(emoji),
                        child: SizedBox(
                          width: 44,
                          height: 36,
                          child: Center(
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: replyController,
                        focusNode: replyFocusNode,
                        enabled: !isSendingReply,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSendReply(),
                        style: ig.body(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Gửi tin nhắn',
                          hintStyle: ig.body(
                            color: Colors.white.withOpacity(0.65),
                            fontSize: 14,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 11,
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.32),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.32),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: ig.primaryAction,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: isSendingReply ? null : onSendReply,
                      constraints: const BoxConstraints(
                        minWidth: SamanIgTokens.minTouchTarget,
                        minHeight: SamanIgTokens.minTouchTarget,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: ig.primaryAction,
                        foregroundColor: ig.onPrimaryAction,
                        minimumSize: const Size(
                          SamanIgTokens.minTouchTarget,
                          SamanIgTokens.minTouchTarget,
                        ),
                      ),
                      icon: isSendingReply
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: ig.onPrimaryAction,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 19),
                      tooltip: 'Gửi',
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
