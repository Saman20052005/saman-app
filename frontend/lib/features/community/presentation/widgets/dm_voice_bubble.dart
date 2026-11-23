import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../tokens/saman_ig_tokens.dart';

/// Voice note audio bubble for Messenger-Lite DM threads.
/// Uses [AudioPlayer] (`just_audio`) with lazy URL loading, minimalist
/// seekable waveform bars, and tabular `m:ss` duration display.
class DmVoiceBubble extends StatefulWidget {
  final String mediaUrl;
  final double? durationSeconds;
  final bool isMine;
  final SamanIgTokens tokens;

  const DmVoiceBubble({
    super.key,
    required this.mediaUrl,
    this.durationSeconds,
    required this.isMine,
    required this.tokens,
  });

  @override
  State<DmVoiceBubble> createState() => _DmVoiceBubbleState();
}

class _DmVoiceBubbleState extends State<DmVoiceBubble> {
  static const int _barCount = 26;

  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  bool _isLoaded = false;
  bool _isLoading = false;
  bool _isPlaying = false;
  String? _errorMessage;

  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  late List<double> _barHeights;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _barHeights = _generateWaveformBars(widget.mediaUrl);
    if (widget.durationSeconds != null && widget.durationSeconds! > 0) {
      _totalDuration = Duration(
        milliseconds: (widget.durationSeconds! * 1000).round(),
      );
    }
    _bindPlayerStreams();
  }

  @override
  void didUpdateWidget(covariant DmVoiceBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      _isLoaded = false;
      _isLoading = false;
      _isPlaying = false;
      _errorMessage = null;
      _position = Duration.zero;
      _barHeights = _generateWaveformBars(widget.mediaUrl);
      if (widget.durationSeconds != null && widget.durationSeconds! > 0) {
        _totalDuration = Duration(
          milliseconds: (widget.durationSeconds! * 1000).round(),
        );
      } else {
        _totalDuration = Duration.zero;
      }
      _player.stop();
    }
  }

  void _bindPlayerStreams() {
    _playerStateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      final completed = state.processingState == ProcessingState.completed;
      if (completed) {
        _player.seek(Duration.zero);
        _player.pause();
      }
      final buffering = state.processingState == ProcessingState.loading ||
          state.processingState == ProcessingState.buffering;
      setState(() {
        _isPlaying = state.playing && !completed;
        if (!buffering && _isLoaded) {
          _isLoading = false;
        }
        if (completed) {
          _position = Duration.zero;
        }
      });
    });

    _positionSub = _player.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() {
        _position = pos;
      });
    });

    _durationSub = _player.durationStream.listen((dur) {
      if (!mounted || dur == null || dur <= Duration.zero) return;
      setState(() {
        _totalDuration = dur;
      });
    });
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  List<double> _generateWaveformBars(String seedSource) {
    final rng = math.Random(seedSource.hashCode);
    return List<double>.generate(_barCount, (index) {
      final envelope = math.sin((index / (_barCount - 1)) * math.pi);
      final randomFactor = 0.35 + rng.nextDouble() * 0.65;
      return (0.25 + envelope * 0.75 * randomFactor).clamp(0.22, 1.0);
    });
  }

  Future<void> _togglePlayPause() async {
    final url = widget.mediaUrl.trim();
    if (url.isEmpty) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Âm thanh không khả dụng';
      });
      return;
    }

    if (_isPlaying) {
      await _player.pause();
      return;
    }

    if (!_isLoaded) {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      try {
        final loadedDuration = await _player.setUrl(url);
        if (!mounted) return;
        setState(() {
          _isLoaded = true;
          _isLoading = false;
          if (loadedDuration != null && loadedDuration > Duration.zero) {
            _totalDuration = loadedDuration;
          }
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _isLoaded = false;
          _errorMessage = 'Không thể tải âm thanh';
        });
        return;
      }
    }

    try {
      await _player.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _errorMessage = 'Không thể phát âm thanh';
      });
    }
  }

  Future<void> _seekToFraction(double fraction) async {
    if (!_isLoaded || _totalDuration <= Duration.zero) return;
    final clamped = fraction.clamp(0.0, 1.0);
    final targetMs = (_totalDuration.inMilliseconds * clamped).round();
    await _player.seek(Duration(milliseconds: targetMs));
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 35999);
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final ig = widget.tokens;
    final textTheme = Theme.of(context).textTheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    final fgColor = widget.isMine ? ig.onPrimaryAction : ig.textPrimary;
    final mutedColor = widget.isMine
        ? ig.onPrimaryAction.withOpacity(0.78)
        : ig.textSecondary;
    final activeBarColor =
        widget.isMine ? ig.onPrimaryAction : ig.primaryAction;
    final inactiveBarColor = widget.isMine
        ? ig.onPrimaryAction.withOpacity(0.32)
        : ig.textMuted.withOpacity(0.45);
    final playButtonBg =
        widget.isMine ? ig.onPrimaryAction : ig.primaryAction;
    final playButtonIcon =
        widget.isMine ? ig.dmBubbleSent : ig.onPrimaryAction;

    final double progress = _totalDuration.inMilliseconds > 0
        ? (_position.inMilliseconds / _totalDuration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    final Duration displayDuration =
        (_isPlaying || _position > Duration.zero) ? _position : _totalDuration;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 210, maxWidth: 260),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isLoading ? null : _togglePlayPause,
                    customBorder: const CircleBorder(),
                    child: Center(
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: playButtonBg,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: _isLoading
                              ? SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: playButtonIcon,
                                  ),
                                )
                              : Icon(
                                  _isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 20,
                                  color: playButtonIcon,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        if (constraints.maxWidth <= 0) return;
                        _seekToFraction(
                          details.localPosition.dx / constraints.maxWidth,
                        );
                      },
                      onHorizontalDragUpdate: (details) {
                        if (constraints.maxWidth <= 0) return;
                        _seekToFraction(
                          details.localPosition.dx / constraints.maxWidth,
                        );
                      },
                      child: SizedBox(
                        height: 32,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(_barCount, (index) {
                            final barThreshold = (index + 1) / _barCount;
                            final isFilled =
                                progress > 0 && progress >= barThreshold - 0.03;
                            final height = 6.0 + (_barHeights[index] * 18.0);
                            return AnimatedContainer(
                              duration: disableAnimations
                                  ? Duration.zero
                                  : const Duration(milliseconds: 120),
                              width: 2.5,
                              height: height,
                              decoration: BoxDecoration(
                                color: isFilled
                                    ? activeBarColor
                                    : inactiveBarColor,
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                            );
                          }),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _formatDuration(displayDuration),
                style: textTheme.labelSmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fgColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: _togglePlayPause,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 13,
                    color: mutedColor,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '$_errorMessage · Thử lại',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: mutedColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
