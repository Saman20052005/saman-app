import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../../widgets/saman_feedback_snackbar.dart';
import '../../../domain/models/community_dm.dart';
import '../../../domain/models/community_story.dart';
import '../../providers/community_dm_provider.dart';
import '../../providers/community_social_providers.dart';

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
  bool _isVideoReady = false;
  bool _hasVideoError = false;
  bool _isSendingReply = false;
  bool _isDeleting = false;

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
    } else if (!_isDeleting) {
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
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF15191E),
        title: const Text(
          'Xóa tin này?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Tin 24h sẽ bị xóa vĩnh viễn và không thể khôi phục.',
          style: TextStyle(color: Color(0xFFABB4BD)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Hủy',
              style: TextStyle(color: Color(0xFFABB4BD)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Xóa',
              style: TextStyle(
                color: Color(0xFFFB7185),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
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

  Future<void> _sendReply(
    CommunityStoryAuthorGroup group,
    CommunityStory story,
  ) async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _isSendingReply) return;

    setState(() => _isSendingReply = true);
    try {
      final conv = await ref
          .read(communityInboxProvider.notifier)
          .createOrGetConversation(group.author.id);
      final sent = await ref
          .read(communityChatThreadProvider(conv.id).notifier)
          .sendMessage(
            type: DmMessageType.storyReply,
            content: text,
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
      _replyController.clear();
      _replyFocusNode.unfocus();
      SamanFeedbackSnackBar.show(
        context,
        message: 'Đã gửi trả lời tin đến ${group.author.name}',
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

  Color _parseHexColor(String? hex) {
    final cleaned = (hex ?? '').replaceFirst('#', '').trim();
    if (cleaned.length == 6) {
      final value = int.tryParse('FF$cleaned', radix: 16);
      if (value != null) return Color(value);
    }
    return const Color(0xFF087F66);
  }

  @override
  Widget build(BuildContext context) {
    final group = _currentGroup;
    final story = _currentStory;
    if (group == null || story == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
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
                  if (details.localPosition.dx < width * 0.35) {
                    _previousStory();
                  } else {
                    _nextStory();
                  }
                },
                onLongPressStart: (_) => _pausePlayback(),
                onLongPressEnd: (_) {
                  if (!_replyFocusNode.hasFocus) {
                    _resumePlayback();
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _StoryMediaContent(
                      story: story,
                      videoController: _videoController,
                      isVideoReady: _isVideoReady,
                      hasVideoError: _hasVideoError,
                      backgroundColor: _parseHexColor(story.backgroundColor),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.65),
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
                              group: group,
                              story: story,
                              onClose: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (story.mediaType != 'text' &&
                        story.caption.trim().isNotEmpty)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            story.caption.trim(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _StoryFooterBar(
              group: group,
              story: story,
              replyController: _replyController,
              replyFocusNode: _replyFocusNode,
              isSendingReply: _isSendingReply,
              isDeleting: _isDeleting,
              onDelete: () => _confirmAndDelete(story),
              onSendReply: () => _sendReply(group, story),
            ),
          ],
        ),
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
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: fill,
                    minHeight: 3,
                    backgroundColor: Colors.white.withOpacity(0.28),
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
    required this.group,
    required this.story,
    required this.onClose,
  });

  final CommunityStoryAuthorGroup group;
  final CommunityStory story;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = group.author.avatarUrl;
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFF1B2127),
          backgroundImage:
              avatarUrl != null && avatarUrl.isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
          child: avatarUrl == null || avatarUrl.isEmpty
              ? Text(
                  group.author.name.isNotEmpty
                      ? group.author.name[0].toUpperCase()
                      : 'S',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (group.author.isVerified) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.verified_rounded,
                      size: 14,
                      color: Color(0xFF5BBFA0),
                    ),
                  ],
                ],
              ),
              Text(
                story.timeAgo,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          tooltip: 'Đóng',
        ),
      ],
    );
  }
}

class _StoryMediaContent extends StatelessWidget {
  const _StoryMediaContent({
    required this.story,
    required this.videoController,
    required this.isVideoReady,
    required this.hasVideoError,
    required this.backgroundColor,
  });

  final CommunityStory story;
  final VideoPlayerController? videoController;
  final bool isVideoReady;
  final bool hasVideoError;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    if (story.mediaType == 'text') {
      return Container(
        color: backgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
        alignment: Alignment.center,
        child: Text(
          story.caption,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
      );
    }

    if (story.mediaType == 'video') {
      if (hasVideoError) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 44),
              SizedBox(height: 10),
              Text(
                'Không thể phát video này',
                style: TextStyle(color: Colors.white70, fontSize: 14),
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
        child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
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
      errorBuilder: (context, _, __) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.white54, size: 44),
            SizedBox(height: 10),
            Text(
              'Không thể tải ảnh',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryFooterBar extends StatelessWidget {
  const _StoryFooterBar({
    required this.group,
    required this.story,
    required this.replyController,
    required this.replyFocusNode,
    required this.isSendingReply,
    required this.isDeleting,
    required this.onDelete,
    required this.onSendReply,
  });

  final CommunityStoryAuthorGroup group;
  final CommunityStory story;
  final TextEditingController replyController;
  final FocusNode replyFocusNode;
  final bool isSendingReply;
  final bool isDeleting;
  final VoidCallback onDelete;
  final VoidCallback onSendReply;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      color: Colors.black,
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: isDeleting ? null : onDelete,
                  icon: isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFFB7185),
                          ),
                        )
                      : const Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFFFB7185),
                          size: 19,
                        ),
                  label: const Text(
                    'Xóa',
                    style: TextStyle(
                      color: Color(0xFFFB7185),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: replyController,
                    focusNode: replyFocusNode,
                    enabled: !isSendingReply,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSendReply(),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Trả lời tin này...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.22),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.22),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(
                          color: Color(0xFF5BBFA0),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: isSendingReply ? null : onSendReply,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF5BBFA0),
                    foregroundColor: Colors.black,
                  ),
                  icon: isSendingReply
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 19),
                  tooltip: 'Gửi',
                ),
              ],
            ),
    );
  }
}
