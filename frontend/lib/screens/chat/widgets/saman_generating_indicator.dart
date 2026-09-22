import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../tokens/saman_chat_tokens.dart';
import 'saman_monogram.dart';

/// Approved transient generating indicator for Saman Chat (State 05).
///
/// Visual structure:
/// - Saman identity row: [S monogram] + "Saman"
/// - Subtle elevated container with 3 softly pulsing neutral dots
/// - Natural supporting copy: "Reviewing your recent training..."
///
/// Rules:
/// - UI-only component, never persisted or inserted into ChatMessage history
/// - No CircularProgressIndicator or green spinners
/// - No technical telemetry or "thinking" labels
class SamanGeneratingIndicator extends StatefulWidget {
  final String supportingText;

  const SamanGeneratingIndicator({
    super.key,
    this.supportingText = 'Reviewing your recent training...',
  });

  @override
  State<SamanGeneratingIndicator> createState() =>
      _SamanGeneratingIndicatorState();
}

class _SamanGeneratingIndicatorState extends State<SamanGeneratingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      label: 'Saman is generating a response: ${widget.supportingText}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Identity row: Small S monogram + "Saman"
          const Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SamanMonogram(
                size: 20,
                borderRadius: 4,
                fontSize: 11,
                backgroundColor: SamanChatTokens.iconContainerBg,
                borderColor: SamanChatTokens.borderSubtle,
              ),
              SizedBox(width: 8.0),
              Text(
                'Saman',
                style: SamanChatTokens.assistantName,
              ),
            ],
          ),

          const SizedBox(height: 8.0),

          // 2. Subtle capsule container with 3 pulsing dots
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
            decoration: BoxDecoration(
              color: SamanChatTokens.surface,
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(
                color: SamanChatTokens.borderSubtle,
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulsingDot(
                  controller: _controller,
                  delayFraction: 0.0,
                  disableAnimations: disableAnimations,
                ),
                const SizedBox(width: 5.0),
                _PulsingDot(
                  controller: _controller,
                  delayFraction: 0.2,
                  disableAnimations: disableAnimations,
                ),
                const SizedBox(width: 5.0),
                _PulsingDot(
                  controller: _controller,
                  delayFraction: 0.4,
                  disableAnimations: disableAnimations,
                ),
              ],
            ),
          ),

          const SizedBox(height: 8.0),

          // 3. Natural supporting coach note
          Text(
            widget.supportingText,
            style: SamanChatTokens.assistantHelper,
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatelessWidget {
  final AnimationController controller;
  final double delayFraction;
  final bool disableAnimations;

  const _PulsingDot({
    required this.controller,
    required this.delayFraction,
    required this.disableAnimations,
  });

  @override
  Widget build(BuildContext context) {
    if (disableAnimations) {
      return Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: SamanChatTokens.textSecondary,
          shape: BoxShape.circle,
        ),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final progress = (controller.value + delayFraction) % 1.0;
        final wave = 0.5 * (1.0 + math.sin((progress * 2.0 * math.pi) - (math.pi / 2.0)));
        final opacity = 0.25 + 0.75 * wave;
        return Opacity(
          opacity: opacity.clamp(0.25, 1.0),
          child: child,
        );
      },
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: SamanChatTokens.textSecondary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
