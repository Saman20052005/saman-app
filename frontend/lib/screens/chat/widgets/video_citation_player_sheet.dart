import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../models/video_citation.dart';
import '../tokens/saman_chat_tokens.dart';

Future<void> showVideoCitationPlayerSheet(
  BuildContext context,
  VideoCitation citation,
) {
  final t = SamanChatTokens.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: t.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
    ),
    builder: (sheetContext) => VideoCitationPlayerSheet(citation: citation),
  );
}

class VideoCitationPlayerSheet extends StatefulWidget {
  final VideoCitation citation;

  const VideoCitationPlayerSheet({
    super.key,
    required this.citation,
  });

  @override
  State<VideoCitationPlayerSheet> createState() =>
      _VideoCitationPlayerSheetState();
}

class _VideoCitationPlayerSheetState extends State<VideoCitationPlayerSheet> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isDisposed = false;

  Duration get _seekTarget => Duration(
        milliseconds: (widget.citation.seekSec * 1000).round(),
      );

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final trimmedUrl = widget.citation.videoUrl.trim();
    final uri = Uri.tryParse(trimmedUrl);
    final isValidHttp = uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;

    if (!isValidHttp) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      return;
    }

    final previous = _controller;
    _controller = null;
    if (previous != null) {
      previous.removeListener(_onControllerTick);
      await previous.dispose();
    }

    if (!mounted || _isDisposed) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    controller.addListener(_onControllerTick);

    try {
      await controller.initialize();
      if (!mounted || _isDisposed || !identical(_controller, controller)) {
        controller.removeListener(_onControllerTick);
        await controller.dispose();
        return;
      }

      if (widget.citation.seekSec > 0) {
        await controller.seekTo(_seekTarget);
        if (!mounted || _isDisposed || !identical(_controller, controller)) {
          return;
        }
      }

      await controller.play();
      if (!mounted || _isDisposed || !identical(_controller, controller)) {
        return;
      }

      setState(() {
        _isLoading = false;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted || _isDisposed || !identical(_controller, controller)) {
        return;
      }
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _onControllerTick() {
    if (!mounted || _isDisposed) return;
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.hasError && !_hasError) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      return;
    }
    setState(() {});
  }

  Future<void> _togglePlayPause() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      final duration = controller.value.duration;
      if (duration > Duration.zero && controller.value.position >= duration) {
        await controller.seekTo(Duration.zero);
        if (!mounted || _isDisposed) return;
      }
      await controller.play();
    }
  }

  Future<void> _seekToCitationMoment() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.seekTo(_seekTarget);
    if (!mounted || _isDisposed) return;
    if (!controller.value.isPlaying) {
      await controller.play();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onControllerTick);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = SamanChatTokens.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final maxVideoHeight = MediaQuery.sizeOf(context).height * 0.56;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 16.0 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),
            const SizedBox(height: 12.0),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.citation.label.isNotEmpty
                        ? widget.citation.label
                        : 'Video dẫn chứng',
                    style: TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.w600,
                      color: t.textWhite,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8.0),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  decoration: BoxDecoration(
                    color: t.surfaceElevated,
                    borderRadius: BorderRadius.circular(999.0),
                    border: Border.all(color: t.borderSubtle),
                  ),
                  child: Text(
                    widget.citation.formattedTimestamp,
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                      color: t.greenAccent,
                    ),
                  ),
                ),
                const SizedBox(width: 4.0),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: t.textSecondary),
                  tooltip: 'Đóng',
                ),
              ],
            ),
            const SizedBox(height: 12.0),
            _buildPlayerBody(t, maxVideoHeight),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerBody(SamanChatPalette t, double maxVideoHeight) {
    if (_isLoading) {
      return Container(
        height: 220.0,
        decoration: BoxDecoration(
          color: t.canvas,
          borderRadius: BorderRadius.circular(14.0),
          border: Border.all(color: t.borderSubtle),
        ),
        child: Center(
          child: SizedBox(
            width: 28.0,
            height: 28.0,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: t.greenAccent,
            ),
          ),
        ),
      );
    }

    final controller = _controller;
    if (_hasError || controller == null || !controller.value.isInitialized) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 28.0),
        decoration: BoxDecoration(
          color: t.canvas,
          borderRadius: BorderRadius.circular(14.0),
          border: Border.all(color: t.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off_outlined,
              size: 36.0,
              color: t.textSecondary,
            ),
            const SizedBox(height: 10.0),
            Text(
              'Không thể tải video dẫn chứng. Vui lòng kiểm tra kết nối và thử lại.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: t.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14.0),
            OutlinedButton.icon(
              onPressed: _initializePlayer,
              icon: const Icon(Icons.refresh_rounded, size: 18.0),
              label: const Text('Thử lại'),
              style: OutlinedButton.styleFrom(
                foregroundColor: t.textWhite,
                side: BorderSide(color: t.border),
              ),
            ),
          ],
        ),
      );
    }

    final aspectRatio = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 9 / 16;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14.0),
          child: Container(
            color: Colors.black,
            constraints: BoxConstraints(maxHeight: maxVideoHeight),
            child: Center(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10.0),
        VideoProgressIndicator(
          controller,
          allowScrubbing: true,
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          colors: VideoProgressColors(
            playedColor: t.greenAccent,
            bufferedColor: t.border,
            backgroundColor: t.surfaceElevated,
          ),
        ),
        const SizedBox(height: 8.0),
        Row(
          children: [
            IconButton(
              onPressed: _togglePlayPause,
              icon: Icon(
                controller.value.isPlaying
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_filled_rounded,
                size: 34.0,
                color: t.textWhite,
              ),
              tooltip: controller.value.isPlaying ? 'Tạm dừng' : 'Phát',
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _seekToCitationMoment,
                icon: Icon(
                  Icons.replay_rounded,
                  size: 18.0,
                  color: t.greenAccent,
                ),
                label: Text(
                  'Tua lại mốc lỗi (${widget.citation.formattedTimestamp})',
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.textWhite,
                  backgroundColor: t.surfaceElevated,
                  side: BorderSide(color: t.greenAccent.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 10.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
