import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Tokens defining the refined "Saman Aurora" ambient background system.
///
/// Designed to provide subtle, focused atmospheric depth for the Saman Coach / AI Chat,
/// featuring a single soft royal blue & indigo elliptical light pool concentrated
/// in the lower-middle region over a deep neutral obsidian base (#0D0F14).
class SamanAuroraTokens {
  SamanAuroraTokens._();

  // ─── Color Palette ───────────────────────────────────────────────────
  /// Base deep neutral obsidian background (#0D0F14)
  static const Color baseBackground = Color(0xFF0D0F14);

  /// Primary soft royal blue glow (#1D3A8A)
  static const Color primaryGlow = Color(0xFF1D3A8A);

  /// Secondary subtle indigo glow (#373078)
  static const Color secondaryGlow = Color(0xFF373078);

  // Backward compatibility aliases
  static const Color blueGlow = primaryGlow;
  static const Color tealGlow = secondaryGlow;
  static const Color emeraldGlow = primaryGlow;

  // ─── Alpha Thresholds (Welcome State) ───────────────────────────────
  /// Tuned for refined visibility with srcOver blending over #0D0F14
  static const double primaryMaxAlpha = 0.42;
  static const double secondaryMaxAlpha = 0.16;

  // Backward compatibility alpha aliases
  static const double blueMaxAlpha = primaryMaxAlpha;
  static const double tealMaxAlpha = secondaryMaxAlpha;
  static const double emeraldMaxAlpha = 0.0;

  // ─── Active Conversation Intensity ──────────────────────────────────
  /// When conversation exists, glow alpha scales down to 50% for high readability.
  static const double conversationIntensityRatio = 0.50;

  /// Duration to glide between welcome and conversation intensities.
  static const Duration intensityDuration = Duration(milliseconds: 500);

  // ─── Animation Cycles ───────────────────────────────────────────────
  static const Duration cycleDrift = Duration(seconds: 30);
  static const Duration cycleBlue = cycleDrift;
  static const Duration cycleTeal = cycleDrift;
  static const Duration cycleEmerald = cycleDrift;
}

/// Atmospheric drifting background for Saman Coach / AI Chat.
///
/// Renders a single soft royal blue–indigo elliptical glow pool centered in the
/// lower-middle region (y ~ 60–65%) that gently drifts (3–5% amplitude) across
/// a 30-second cycle over a near-black obsidian canvas (#0D0F14).
///
/// Architecture highlights:
/// - Paints via a [CustomPainter] hooked directly to a merged [Listenable] so
///   animation ticks never trigger widget tree rebuilds.
/// - Automatically pauses when app moves to background or tab is inactive.
/// - Gracefully supports accessibility reduced motion (`disableAnimations`).
/// - Smoothly shifts glow intensity down to 50% once a conversation begins.
/// - Glow fades out completely to 0 alpha before the bottom edge, seamlessly
///   transitioning into the base background behind the composer.
class SamanChatBackground extends StatefulWidget {
  /// Whether an active conversation exists (messages, food analysis, or active nudge).
  final bool hasConversation;

  /// Whether this view is currently visible to the user (e.g. active tab in IndexedStack).
  final bool isActive;

  const SamanChatBackground({
    super.key,
    this.hasConversation = false,
    this.isActive = true,
  });

  @override
  State<SamanChatBackground> createState() => _SamanChatBackgroundState();
}

class _SamanChatBackgroundState extends State<SamanChatBackground>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _driftController;
  late final AnimationController _intensityController;
  late final Listenable _repaintListenable;

  bool _isAppResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _driftController = AnimationController(
      vsync: this,
      duration: SamanAuroraTokens.cycleDrift,
    );

    final initialIntensity = widget.hasConversation
        ? SamanAuroraTokens.conversationIntensityRatio
        : 1.0;
    _intensityController = AnimationController(
      vsync: this,
      duration: SamanAuroraTokens.intensityDuration,
      value: initialIntensity,
    );

    _repaintListenable = Listenable.merge([
      _driftController,
      _intensityController,
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimationState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isResumed = state == AppLifecycleState.resumed;
    if (_isAppResumed != isResumed) {
      _isAppResumed = isResumed;
      _syncAnimationState();
    }
  }

  @override
  void didUpdateWidget(covariant SamanChatBackground oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isActive != widget.isActive) {
      _syncAnimationState();
    }

    if (oldWidget.hasConversation != widget.hasConversation) {
      final target = widget.hasConversation
          ? SamanAuroraTokens.conversationIntensityRatio
          : 1.0;
      _intensityController.animateTo(
        target,
        duration: SamanAuroraTokens.intensityDuration,
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _syncAnimationState() {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_isAppResumed && widget.isActive && !disableAnimations) {
      _startOrResumeDrift();
    } else {
      _pauseDrift();
    }
  }

  void _startOrResumeDrift() {
    if (!_driftController.isAnimating) _driftController.repeat();
  }

  void _pauseDrift() {
    if (_driftController.isAnimating) _driftController.stop(canceled: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _driftController.dispose();
    _intensityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _AuroraBackgroundPainter(
            driftController: _driftController,
            intensityController: _intensityController,
            disableAnimations: disableAnimations,
            repaint: _repaintListenable,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Custom painter rendering the focused lower-center royal blue–indigo ellipse glow.
class _AuroraBackgroundPainter extends CustomPainter {
  final AnimationController driftController;
  final AnimationController intensityController;
  final bool disableAnimations;

  _AuroraBackgroundPainter({
    required this.driftController,
    required this.intensityController,
    required this.disableAnimations,
    required super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. Draw base solid canvas #0D0F14 (neutral obsidian)
    final basePaint = Paint()..color = SamanAuroraTokens.baseBackground;
    canvas.drawRect(Offset.zero & size, basePaint);

    final intensity = intensityController.value;
    if (intensity <= 0) return;

    // Evaluation progress in [0, 1] (fixed harmonious frame if reduced motion)
    final double t = disableAnimations ? 0.35 : driftController.value;

    final angle1 = t * 2 * math.pi;
    final angle2 = (t * 2 * math.pi) + (math.pi / 4.0);

    // ─── Layer 1: Secondary Indigo Glow (#373078) ───────────────────────
    // Center at x ~ 50%, y ~ 60%, width ~ 80%, height ~ 44%, amplitude ~ 3%
    final dx2 = math.cos(angle2) * (size.width * 0.03);
    final dy2 = math.sin(angle2) * (size.height * 0.02);
    final center2 = Offset(
      size.width * 0.50 + dx2,
      size.height * 0.60 + dy2,
    );
    final scale2 = 1.0 + 0.025 * (1.0 + math.cos(angle2)) / 2.0;
    final rx2 = size.width * 0.40 * scale2;
    final ry2 = size.height * 0.22 * scale2;

    _drawSoftEllipseGlow(
      canvas: canvas,
      center: center2,
      rx: rx2,
      ry: ry2,
      color: SamanAuroraTokens.secondaryGlow,
      maxAlpha: SamanAuroraTokens.secondaryMaxAlpha * intensity,
    );

    // ─── Layer 2: Primary Soft Royal Blue Glow (#1D3A8A) ─────────────────
    // Center at x ~ 50%, y ~ 62.5%, width ~ 90%, height ~ 50%, amplitude ~ 3.5%
    final dx1 = math.sin(angle1) * (size.width * 0.035);
    final dy1 = math.cos(angle1) * (size.height * 0.025);
    final center1 = Offset(
      size.width * 0.50 + dx1,
      size.height * 0.625 + dy1,
    );
    final scale1 = 1.0 + 0.03 * (1.0 + math.sin(angle1)) / 2.0;
    final rx1 = size.width * 0.45 * scale1;
    final ry1 = size.height * 0.25 * scale1;

    _drawSoftEllipseGlow(
      canvas: canvas,
      center: center1,
      rx: rx1,
      ry: ry1,
      color: SamanAuroraTokens.primaryGlow,
      maxAlpha: SamanAuroraTokens.primaryMaxAlpha * intensity,
    );
  }

  /// Draws an ultra-soft elliptical glow using BlendMode.srcOver with smootherstep falloff.
  ///
  /// The shader evaluates radial distance in local transformed space, creating
  /// an exact ellipse with semi-axes [rx] and [ry]. Multi-stop falloff guarantees
  /// that opacity reaches 0.0 before the outer boundary with a zero derivative,
  /// preventing rings or harsh edges.
  void _drawSoftEllipseGlow({
    required Canvas canvas,
    required Offset center,
    required double rx,
    required double ry,
    required Color color,
    required double maxAlpha,
  }) {
    if (rx <= 0 || ry <= 0 || maxAlpha <= 0) return;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1.0, ry / rx);

    final paint = Paint()
      ..isAntiAlias = true
      ..blendMode = BlendMode.srcOver
      ..shader = ui.Gradient.radial(
        Offset.zero,
        rx,
        [
          color.withOpacity(maxAlpha),
          color.withOpacity(maxAlpha * 0.95),
          color.withOpacity(maxAlpha * 0.78),
          color.withOpacity(maxAlpha * 0.50),
          color.withOpacity(maxAlpha * 0.22),
          color.withOpacity(maxAlpha * 0.06),
          color.withOpacity(0.0),
        ],
        const [0.0, 0.18, 0.38, 0.58, 0.76, 0.90, 1.0],
      );

    // Draw rect covering slightly past rx to ensure fully transparent outer clamping
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: rx * 2.1, height: rx * 2.1),
      paint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AuroraBackgroundPainter oldDelegate) {
    return oldDelegate.disableAnimations != disableAnimations;
  }
}
