import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../screens/home/tokens/saman_home_tokens.dart';
import 'coach_tour_service.dart';
import 'coach_tour_step.dart';

/// Game-style spotlight Coach Marks overlay tailored to Saman's dark obsidian UI.
///
/// Guarantees:
/// - Never stacks two overlays simultaneously ([isShowing] re-entrancy guard).
/// - Never blocks the screen if targets are unmounted, empty, or off-screen.
/// - Safely removes its [OverlayEntry] on skip, completion, or disposal.
class SamanCoachOverlay {
  SamanCoachOverlay._();

  static OverlayEntry? _activeEntry;

  /// Whether a coach tour overlay is currently displayed.
  static bool get isShowing => _activeEntry != null;

  /// Dismisses the currently active coach tour overlay, if any.
  static void dismissActive() {
    final entry = _activeEntry;
    _activeEntry = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }

  /// Displays the coach tour for [screenId] if it has not been seen yet
  /// (or if [forceShow] is `true`).
  ///
  /// Returns `true` if the overlay was inserted, or `false` if skipped
  /// (already seen, already showing, unmounted context, or no valid targets).
  static Future<bool> showIfNeeded({
    required BuildContext context,
    required String screenId,
    required List<CoachTourStep> steps,
    CoachTourService? service,
    bool forceShow = false,
  }) async {
    if (steps.isEmpty || isShowing) {
      return false;
    }

    final svc = service ?? CoachTourService();
    if (!forceShow) {
      final should = await svc.shouldShow(screenId);
      if (!should) {
        return false;
      }
    }

    if (!context.mounted || isShowing) {
      return false;
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return false;
    }

    final viewportSize = _resolveViewportSize(context, overlay);
    if (viewportSize.isEmpty) {
      return false;
    }
    final viewport = Offset.zero & viewportSize;

    final validSteps = <CoachTourStep>[
      for (final step in steps)
        if (_resolveTargetRect(step, viewport) != null) step,
    ];

    if (validSteps.isEmpty) {
      return false;
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => _SamanCoachOverlayView(
        entry: entry,
        screenId: screenId,
        steps: validSteps,
        service: svc,
      ),
    );

    _activeEntry = entry;
    overlay.insert(entry);
    return true;
  }

  static Size _resolveViewportSize(
    BuildContext context,
    OverlayState overlay,
  ) {
    final overlayBox = overlay.context.findRenderObject();
    if (overlayBox is RenderBox && overlayBox.hasSize && !overlayBox.size.isEmpty) {
      return overlayBox.size;
    }
    return MediaQuery.maybeSizeOf(context) ?? Size.zero;
  }

  /// Resolves the padded global [Rect] of [step.targetKey] if it is mounted,
  /// laid out with non-empty size, and intersects [viewport].
  static Rect? _resolveTargetRect(CoachTourStep step, Rect viewport) {
    final targetContext = step.targetKey.currentContext;
    if (targetContext == null || !targetContext.mounted) {
      return null;
    }

    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize ||
        renderObject.size.isEmpty) {
      return null;
    }

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final rawRect = topLeft & renderObject.size;
    if (!rawRect.isFinite || rawRect.isEmpty || !rawRect.overlaps(viewport)) {
      return null;
    }

    final padded = step.highlightPadding.inflateRect(rawRect);
    // Clamp spotlight inside the viewport with a tiny margin so cutouts remain clean.
    final clampedLeft = padded.left.clamp(0.0, viewport.width);
    final clampedTop = padded.top.clamp(0.0, viewport.height);
    final clampedRight = padded.right.clamp(clampedLeft, viewport.width);
    final clampedBottom = padded.bottom.clamp(clampedTop, viewport.height);
    final result = Rect.fromLTRB(
      clampedLeft,
      clampedTop,
      clampedRight,
      clampedBottom,
    );
    if (result.isEmpty) {
      return null;
    }
    return result;
  }
}

class _SamanCoachOverlayView extends StatefulWidget {
  const _SamanCoachOverlayView({
    required this.entry,
    required this.screenId,
    required this.steps,
    required this.service,
  });

  final OverlayEntry entry;
  final String screenId;
  final List<CoachTourStep> steps;
  final CoachTourService service;

  @override
  State<_SamanCoachOverlayView> createState() => _SamanCoachOverlayViewState();
}

class _SamanCoachOverlayViewState extends State<_SamanCoachOverlayView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  int _currentIndex = 0;
  bool _isClosing = false;
  bool _pendingAutoSkip = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations && _controller.duration != Duration.zero) {
      _controller.duration = Duration.zero;
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    if (identical(SamanCoachOverlay._activeEntry, widget.entry)) {
      SamanCoachOverlay._activeEntry = null;
    }
    super.dispose();
  }

  void _closeOverlay() {
    if (_isClosing) return;
    _isClosing = true;
    if (identical(SamanCoachOverlay._activeEntry, widget.entry)) {
      SamanCoachOverlay._activeEntry = null;
    }
    if (widget.entry.mounted) {
      widget.entry.remove();
    }
  }

  Future<void> _handleSkip() async {
    _closeOverlay();
    await widget.service.markSeen(widget.screenId);
  }

  Future<void> _handleNext(Rect viewport) async {
    final nextIndex = _findNextValidIndex(_currentIndex + 1, viewport);
    if (nextIndex == null) {
      _closeOverlay();
      await widget.service.markSeen(widget.screenId);
      return;
    }
    if (!mounted) return;
    setState(() {
      _currentIndex = nextIndex;
    });
  }

  int? _findNextValidIndex(int startIndex, Rect viewport) {
    for (int i = startIndex; i < widget.steps.length; i++) {
      if (SamanCoachOverlay._resolveTargetRect(widget.steps[i], viewport) !=
          null) {
        return i;
      }
    }
    return null;
  }

  void _scheduleAutoSkip(Rect viewport) {
    if (_pendingAutoSkip || _isClosing) return;
    _pendingAutoSkip = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingAutoSkip = false;
      if (!mounted || _isClosing) return;
      final nextIndex = _findNextValidIndex(_currentIndex + 1, viewport);
      if (nextIndex != null) {
        setState(() {
          _currentIndex = nextIndex;
        });
      } else {
        // No remaining valid targets: close cleanly without trapping the user.
        _closeOverlay();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final viewportSize = mediaQuery.size;
    final viewport = Offset.zero & viewportSize;
    final safePadding = mediaQuery.padding;

    final currentStep = widget.steps[_currentIndex];
    final spotlightRect =
        SamanCoachOverlay._resolveTargetRect(currentStep, viewport);

    if (spotlightRect == null) {
      _scheduleAutoSkip(viewport);
      return const SizedBox.shrink();
    }

    final isLastStep = _currentIndex >= widget.steps.length - 1;
    const double horizontalMargin = 16.0;
    const double verticalGap = 12.0;

    final double safeTop = safePadding.top + 12.0;
    final double safeBottom =
        math.max(safeTop + 120.0, viewportSize.height - safePadding.bottom - 12.0);
    final double availableWidth =
        math.max(200.0, viewportSize.width - horizontalMargin * 2);
    final double cardWidth = math.min(320.0, availableWidth);

    final double spaceBelow = safeBottom - spotlightRect.bottom - verticalGap;
    final double spaceAbove = spotlightRect.top - safeTop - verticalGap;
    const double preferredCardHeight = 184.0;
    final bool placeBelow =
        spaceBelow >= preferredCardHeight || spaceBelow >= spaceAbove;

    final double maxCardHeight = math.max(
      120.0,
      placeBelow
          ? math.max(spaceBelow, safeBottom - safeTop)
          : math.max(spaceAbove, safeBottom - safeTop),
    );

    final double cardLeft = (spotlightRect.center.dx - cardWidth / 2).clamp(
      horizontalMargin,
      math.max(horizontalMargin, viewportSize.width - cardWidth - horizontalMargin),
    );

    final double? cardTop = placeBelow
        ? (spotlightRect.bottom + verticalGap).clamp(
            safeTop,
            math.max(safeTop, safeBottom - 140.0),
          )
        : null;

    final double? cardBottom = placeBelow
        ? null
        : (viewportSize.height - spotlightRect.top + verticalGap).clamp(
            safePadding.bottom + 12.0,
            math.max(safePadding.bottom + 12.0, viewportSize.height - safeTop - 140.0),
          );

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // Dimmed backdrop with even-odd spotlight cutout; blocks taps outside card.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: CustomPaint(
                  painter: _SpotlightPainter(
                    spotlightRect: spotlightRect,
                    borderRadius: currentStep.borderRadius,
                  ),
                ),
              ),
            ),
            Positioned(
              left: cardLeft,
              top: cardTop,
              bottom: cardBottom,
              width: cardWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 320.0,
                  maxHeight: maxCardHeight,
                ),
                child: _CoachTooltipCard(
                  stepIndex: _currentIndex,
                  totalSteps: widget.steps.length,
                  title: currentStep.title,
                  description: currentStep.description,
                  isLastStep: isLastStep,
                  onSkip: _handleSkip,
                  onNext: () => _handleNext(viewport),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({
    required this.spotlightRect,
    required this.borderRadius,
  });

  final Rect spotlightRect;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      spotlightRect,
      Radius.circular(borderRadius),
    );

    final backdropPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rrect);

    final backdropPaint = Paint()
      ..color = Colors.black.withOpacity(0.72)
      ..style = PaintingStyle.fill;
    canvas.drawPath(backdropPath, backdropPaint);

    // Subtle outer glow around the spotlight cutout.
    final glowPaint = Paint()
      ..color = SamanHomeTokens.greenAccent.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawRRect(rrect, glowPaint);

    final borderPaint = Paint()
      ..color = SamanHomeTokens.greenAccent.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.spotlightRect != spotlightRect ||
        oldDelegate.borderRadius != borderRadius;
  }
}

class _CoachTooltipCard extends StatelessWidget {
  const _CoachTooltipCard({
    required this.stepIndex,
    required this.totalSteps,
    required this.title,
    required this.description,
    required this.isLastStep,
    required this.onSkip,
    required this.onNext,
  });

  final int stepIndex;
  final int totalSteps;
  final String title;
  final String description;
  final bool isLastStep;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SamanHomeTokens.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SamanHomeTokens.borderHigh),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: SamanHomeTokens.greenBadgeBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: SamanHomeTokens.greenBadgeBorder),
              ),
              child: Text(
                '${stepIndex + 1}/$totalSteps',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: SamanHomeTokens.greenAccent,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: SamanHomeTokens.textPrimary,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
                color: SamanHomeTokens.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('coach_tour_skip_button'),
                  onPressed: onSkip,
                  style: TextButton.styleFrom(
                    foregroundColor: SamanHomeTokens.textSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: const Size(48, 36),
                  ),
                  child: const Text(
                    'Bỏ qua',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('coach_tour_next_button'),
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: SamanHomeTokens.greenAccent,
                    foregroundColor: const Color(0xFF061B14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    minimumSize: const Size(64, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    isLastStep ? 'Xong' : 'Tiếp theo',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
