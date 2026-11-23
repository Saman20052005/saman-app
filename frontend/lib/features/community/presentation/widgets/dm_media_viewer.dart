import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../screens/home/tokens/saman_home_tokens.dart';

/// Full-screen image and video viewers for Messenger-Lite DM attachments.
/// Uses an obsidian dark media backdrop for clear visual fidelity.
class DmMediaViewer {
  DmMediaViewer._();

  static const Color _viewerBg = Color(0xFF0A0B0C);
  static const Color _viewerOverlay = Color(0x990A0B0C);
  static const Color _viewerText = Color(0xFFF3F5F4);
  static const Color _viewerMuted = Color(0xFFABB4BD);

  static Future<void> showImage(BuildContext context, String imageUrl) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: _viewerBg,
        pageBuilder: (_, __, ___) => _DmFullScreenImagePage(imageUrl: imageUrl),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  static Future<void> showVideo(BuildContext context, String videoUrl) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: _viewerBg,
        pageBuilder: (_, __, ___) => _DmFullScreenVideoPage(videoUrl: videoUrl),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}

class _DmFullScreenImagePage extends StatefulWidget {
  final String imageUrl;

  const _DmFullScreenImagePage({required this.imageUrl});

  @override
  State<_DmFullScreenImagePage> createState() => _DmFullScreenImagePageState();
}

class _DmFullScreenImagePageState extends State<_DmFullScreenImagePage> {
  final TransformationController _transformationController =
      TransformationController();

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      _transformationController.value = Matrix4.identity()..scale(2.2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = SamanHomeTokens.of(context).greenAccent;

    return Scaffold(
      backgroundColor: DmMediaViewer._viewerBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onDoubleTap: _handleDoubleTap,
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.8,
              maxScale: 4.0,
              child: Center(
                child: Image.network(
                  widget.imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    final expected = loadingProgress.expectedTotalBytes;
                    final value = expected != null && expected > 0
                        ? loadingProgress.cumulativeBytesLoaded / expected
                        : null;
                    return Center(
                      child: CircularProgressIndicator(
                        value: value,
                        color: accent,
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => const _MediaErrorPlaceholder(
                    icon: Icons.broken_image_outlined,
                    label: 'Không thể tải hình ảnh',
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _ViewerCircleButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DmFullScreenVideoPage extends StatefulWidget {
  final String videoUrl;

  const _DmFullScreenVideoPage({required this.videoUrl});

  @override
  State<_DmFullScreenVideoPage> createState() => _DmFullScreenVideoPageState();
}

class _DmFullScreenVideoPageState extends State<_DmFullScreenVideoPage> {
  VideoPlayerController? _controller;
  bool _isInitializing = true;
  bool _hasError = false;
  bool _showControls = true;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    final uri = Uri.tryParse(widget.videoUrl.trim());
    if (uri == null || !uri.hasScheme) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _hasError = true;
      });
      return;
    }

    final previous = _controller;
    if (previous != null) {
      previous.removeListener(_onVideoTick);
      await previous.dispose();
    }

    if (!mounted) return;
    setState(() {
      _isInitializing = true;
      _hasError = false;
    });

    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    controller.addListener(_onVideoTick);

    try {
      await controller.initialize();
      await controller.setVolume(_isMuted ? 0.0 : 1.0);
      await controller.play();
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _hasError = true;
      });
    }
  }

  void _onVideoTick() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.hasError && !_hasError) {
      setState(() {
        _hasError = true;
        _isInitializing = false;
      });
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    final controller = _controller;
    controller?.removeListener(_onVideoTick);
    controller?.dispose();
    _controller = null;
    super.dispose();
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      final pos = controller.value.position;
      final dur = controller.value.duration;
      if (dur > Duration.zero && pos >= dur) {
        controller.seekTo(Duration.zero);
      }
      controller.play();
    }
  }

  void _toggleMute() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final nextMuted = !_isMuted;
    controller.setVolume(nextMuted ? 0.0 : 1.0);
    setState(() {
      _isMuted = nextMuted;
    });
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 35999);
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final accent = SamanHomeTokens.of(context).greenAccent;
    final controller = _controller;
    final isInitialized = controller != null && controller.value.isInitialized;
    final isPlaying = isInitialized && controller.value.isPlaying;
    final isBuffering = isInitialized && controller.value.isBuffering;
    final duration = isInitialized ? controller.value.duration : Duration.zero;
    final position = isInitialized ? controller.value.position : Duration.zero;
    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final currentMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Scaffold(
      backgroundColor: DmMediaViewer._viewerBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _showControls = !_showControls;
              });
            },
            child: Center(
              child: _isInitializing
                  ? CircularProgressIndicator(color: accent)
                  : _hasError || !isInitialized
                      ? _MediaErrorPlaceholder(
                          icon: Icons.videocam_off_outlined,
                          label: 'Không thể phát video',
                          onRetry: _initController,
                          accentColor: accent,
                        )
                      : AspectRatio(
                          aspectRatio: controller.value.aspectRatio > 0
                              ? controller.value.aspectRatio
                              : 16 / 9,
                          child: VideoPlayer(controller),
                        ),
            ),
          ),
          if (isBuffering && !_isInitializing && !_hasError)
            Center(
              child: CircularProgressIndicator(color: accent),
            ),
          if (isInitialized && _showControls && !isBuffering)
            Center(
              child: GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: DmMediaViewer._viewerOverlay,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 36,
                    color: DmMediaViewer._viewerText,
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _ViewerCircleButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          if (isInitialized && _showControls)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  color: DmMediaViewer._viewerOverlay,
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _togglePlayPause,
                        tooltip: isPlaying ? 'Tạm dừng' : 'Phát',
                        icon: Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: DmMediaViewer._viewerText,
                          size: 24,
                        ),
                      ),
                      Text(
                        _formatDuration(position),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: DmMediaViewer._viewerText,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                            activeTrackColor: accent,
                            inactiveTrackColor:
                                DmMediaViewer._viewerMuted.withOpacity(0.35),
                            thumbColor: accent,
                          ),
                          child: Slider(
                            min: 0.0,
                            max: maxMs,
                            value: currentMs,
                            onChanged: (value) {
                              controller.seekTo(
                                Duration(milliseconds: value.round()),
                              );
                            },
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(duration),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: DmMediaViewer._viewerMuted,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      IconButton(
                        onPressed: _toggleMute,
                        tooltip: _isMuted ? 'Bật âm thanh' : 'Tắt âm thanh',
                        icon: Icon(
                          _isMuted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          color: DmMediaViewer._viewerText,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ViewerCircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ViewerCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DmMediaViewer._viewerOverlay,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(
          icon,
          color: DmMediaViewer._viewerText,
          size: 22,
        ),
      ),
    );
  }
}

class _MediaErrorPlaceholder extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onRetry;
  final Color? accentColor;

  const _MediaErrorPlaceholder({
    required this.icon,
    required this.label,
    this.onRetry,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 48,
            color: DmMediaViewer._viewerMuted,
          ),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: DmMediaViewer._viewerText,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: accentColor ?? DmMediaViewer._viewerText,
                side: BorderSide(
                  color: accentColor ?? DmMediaViewer._viewerMuted,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Thử lại'),
            ),
          ],
        ],
      ),
    );
  }
}
