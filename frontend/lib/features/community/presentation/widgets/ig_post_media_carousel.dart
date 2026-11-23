import 'dart:io';

import 'package:flutter/material.dart';

import '../tokens/saman_ig_tokens.dart';

/// Wraps post media or text content to provide Instagram-style double-tap heart
/// animation (`#FF3040` / `ig.likeHeart`) and single-tap detail navigation.
class IgPostDoubleTapOverlay extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  const IgPostDoubleTapOverlay({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
  });

  @override
  State<IgPostDoubleTapOverlay> createState() => _IgPostDoubleTapOverlayState();
}

class _IgPostDoubleTapOverlayState extends State<IgPostDoubleTapOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  bool _showHeart = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.4, end: 1.28)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.28, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 30,
      ),
    ]).animate(_controller);
    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0),
        weight: 30,
      ),
    ]).animate(_controller);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showHeart = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    widget.onDoubleTap?.call();
    setState(() => _showHeart = true);
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTap: _handleDoubleTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          if (_showHeart)
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return Opacity(
                    opacity: _opacity.value,
                    child: Transform.scale(
                      scale: _scale.value,
                      child: Icon(
                        Icons.favorite_rounded,
                        key: const ValueKey('double-tap-heart-icon'),
                        size: 88,
                        color: ig.likeHeart,
                        shadows: [
                          Shadow(
                            color: ig.scrim,
                            blurRadius: 18,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Edge-to-edge 100% width Instagram media viewer (1:1 aspect ratio) supporting
/// single photo or multi-photo `PageView` carousel with `1/N` counter badge and
/// bottom dot indicators.
class IgPostMediaCarousel extends StatefulWidget {
  final List<String> photoUrls;

  const IgPostMediaCarousel({
    super.key,
    required this.photoUrls,
  });

  @override
  State<IgPostMediaCarousel> createState() => _IgPostMediaCarouselState();
}

class _IgPostMediaCarouselState extends State<IgPostMediaCarousel> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    final isMulti = widget.photoUrls.length > 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isMulti)
                PageView.builder(
                  itemCount: widget.photoUrls.length,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                  },
                  itemBuilder: (context, index) => _IgPostImage(
                    path: widget.photoUrls[index],
                    ig: ig,
                  ),
                )
              else if (widget.photoUrls.isNotEmpty)
                _IgPostImage(
                  path: widget.photoUrls.first,
                  ig: ig,
                )
              else
                ColoredBox(
                  color: ig.surfaceElevated,
                  child: Center(
                    child: Icon(
                      Icons.image_outlined,
                      size: 48,
                      color: ig.textSecondary,
                    ),
                  ),
                ),
              if (isMulti)
                PositionedDirectional(
                  top: 12,
                  end: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: ig.scrim,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${_currentIndex + 1}/${widget.photoUrls.length}',
                      style: const TextStyle(
                        fontFamily: SamanIgTokens.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (isMulti)
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.photoUrls.length, (index) {
                final isActive = index == _currentIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  width: isActive ? 6 : 5,
                  height: isActive ? 6 : 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? ig.primaryAction : ig.border,
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _IgPostImage extends StatelessWidget {
  final String path;
  final SamanIgTokens ig;

  const _IgPostImage({
    required this.path,
    required this.ig,
  });

  @override
  Widget build(BuildContext context) {
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('/static/')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _PlaceholderFrame(
          icon: Icons.broken_image_outlined,
          ig: ig,
        ),
      );
    }
    if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _PlaceholderFrame(
          icon: Icons.image_outlined,
          ig: ig,
        ),
      );
    }
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return _PlaceholderFrame(
      icon: Icons.image_outlined,
      ig: ig,
    );
  }
}

class _PlaceholderFrame extends StatelessWidget {
  final IconData icon;
  final SamanIgTokens ig;

  const _PlaceholderFrame({
    required this.icon,
    required this.ig,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ig.surfaceElevated,
      child: Center(
        child: Icon(icon, size: 48, color: ig.textSecondary),
      ),
    );
  }
}
