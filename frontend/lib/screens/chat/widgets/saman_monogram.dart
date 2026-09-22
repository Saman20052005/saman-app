import 'package:flutter/material.dart';
import '../tokens/saman_chat_tokens.dart';

/// Clean geometric 'S' monogram container for Saman Coach.
///
/// Features:
/// - Charcoal rounded container (#16171B / #212328)
/// - Subtle hairline graphite border (#23252A)
/// - Crisp, centered bold off-white 'S'
/// - Supports arbitrary sizing (standard: 20 for header, 44 for hero)
class SamanMonogram extends StatelessWidget {
  final double size;
  final double? fontSize;
  final double? borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? textColor;

  const SamanMonogram({
    super.key,
    this.size = SamanChatTokens.heroMonogramSize,
    this.fontSize,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.textColor,
  });

  /// Factory constructor for small header monogram (20x20)
  const SamanMonogram.header({super.key})
      : size = SamanChatTokens.headerMonogramSize,
        fontSize = 11.0,
        borderRadius = 4.0,
        backgroundColor = SamanChatTokens.iconContainerBg,
        borderColor = SamanChatTokens.borderSubtle,
        textColor = SamanChatTokens.textWhite;

  /// Factory constructor for assistant chat response monogram (20x20)
  const SamanMonogram.chat({super.key})
      : size = 20.0,
        fontSize = 11.0,
        borderRadius = 6.0,
        backgroundColor = SamanChatTokens.surface,
        borderColor = SamanChatTokens.borderSubtle,
        textColor = SamanChatTokens.textWhite;

  /// Factory constructor for hero empty state monogram (44x44)
  const SamanMonogram.hero({super.key})
      : size = SamanChatTokens.heroMonogramSize,
        fontSize = 20.0,
        borderRadius = 12.0,
        backgroundColor = SamanChatTokens.surface,
        borderColor = SamanChatTokens.borderSubtle,
        textColor = SamanChatTokens.textWhite;

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? (size * 0.25);
    final effectiveFontSize = fontSize ?? (size * 0.46);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor ?? SamanChatTokens.surface,
        borderRadius: BorderRadius.circular(effectiveRadius),
        border: Border.all(
          color: borderColor ?? SamanChatTokens.borderSubtle,
          width: 1.0,
        ),
        boxShadow: size >= 40
            ? const [
                BoxShadow(
                  color: Color(0x2A000000),
                  offset: Offset(0, 2),
                  blurRadius: 6,
                ),
              ]
            : null,
      ),
      child: Text(
        'S',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: textColor ?? SamanChatTokens.textWhite,
          fontSize: effectiveFontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          height: 1.0,
        ),
      ),
    );
  }
}
