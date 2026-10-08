import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../tokens/saman_workout_tokens.dart';

/// Shared renderer for a resolved thumbnail or poster source.
/// Source selection belongs to the existing exercise data, not this widget.
class ExerciseThumbnail extends StatelessWidget {
  const ExerciseThumbnail({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.showUnavailableLabel = false,
  });

  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool showUnavailableLabel;

  @override
  Widget build(BuildContext context) {
    final imageSource = source.trim();
    final uri = Uri.tryParse(imageSource);
    final fallback = _ExerciseImageFallback(
      showLabel: showUnavailableLabel,
    );
    final Widget content;
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      content = CachedNetworkImage(
        imageUrl: imageSource,
        key: ValueKey(imageSource),
        fit: fit,
        placeholder: (_, __) => const _ExerciseImageFallback(isLoading: true),
        errorWidget: (_, __, ___) => fallback,
      );
    } else if (imageSource.startsWith('assets/')) {
      content = Image.asset(
        imageSource,
        key: ValueKey(imageSource),
        fit: fit,
        frameBuilder: (_, child, frame, synchronous) =>
            synchronous || frame != null
                ? child
                : const _ExerciseImageFallback(isLoading: true),
        errorBuilder: (_, __, ___) => fallback,
      );
    } else {
      content = fallback;
    }
    return SizedBox(width: width, height: height, child: content);
  }
}

class _ExerciseImageFallback extends StatelessWidget {
  const _ExerciseImageFallback(
      {this.isLoading = false, this.showLabel = false});

  final bool isLoading;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: SamanWorkoutTokens.surfaceElevated,
      child: Center(
        child: isLoading
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: SamanWorkoutTokens.emeraldAccent,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.fitness_center_outlined,
                    color: SamanWorkoutTokens.textMuted,
                  ),
                  if (showLabel) ...[
                    const SizedBox(height: SamanWorkoutTokens.spacingSm),
                    Text(
                      'Exercise image unavailable',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SamanWorkoutTokens.textSecondary,
                          ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
