import 'package:flutter/material.dart';
import '../../../widgets/app_logo.dart';
import '../tokens/saman_chat_tokens.dart';

/// App logo presentation for Saman Coach / AI Chat.
///
/// Reuses the official [AppLogo] widget (dark variant: white SVG brand icon),
/// maintaining proper aspect ratio (BoxFit.contain), zero external box wrappers,
/// and accessible semantics.
class SamanMonogram extends StatelessWidget {
  final double size;
  final double? fontSize;
  final double? borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? textColor;
  final bool isLightMode;

  const SamanMonogram({
    super.key,
    this.size = SamanChatTokens.heroMonogramSize,
    this.fontSize,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.textColor,
    this.isLightMode = false,
  });

  /// Factory constructor for small header logo (22x22)
  const SamanMonogram.header({super.key})
      : size = SamanChatTokens.headerMonogramSize,
        fontSize = null,
        borderRadius = null,
        backgroundColor = null,
        borderColor = null,
        textColor = null,
        isLightMode = false;

  /// Factory constructor for assistant chat response logo (22x22)
  const SamanMonogram.chat({super.key})
      : size = SamanChatTokens.messageMonogramSize,
        fontSize = null,
        borderRadius = null,
        backgroundColor = null,
        borderColor = null,
        textColor = null,
        isLightMode = false;

  /// Factory constructor for hero empty state logo (42x42)
  const SamanMonogram.hero({super.key})
      : size = SamanChatTokens.heroMonogramSize,
        fontSize = null,
        borderRadius = null,
        backgroundColor = null,
        borderColor = null,
        textColor = null,
        isLightMode = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: AppLogo(
        size: size,
        isLightMode: isLightMode,
      ),
    );
  }
}
