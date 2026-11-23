import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Authoritative avatar widget for the Saman application.
///
/// Implements fallback order:
///   1. Valid network image (cached with CachedNetworkImage)
///   2. Fallback initials derived from athlete name (or 'SA' if empty)
///
/// Designed to preserve obsidian tokens and maintain exact visual
/// parity across loading, error, and initials states.
class SamanAvatar extends StatelessWidget {
  const SamanAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.size = 52.0,
    this.borderWidth = 1.0,
    this.borderColor,
    this.backgroundColor,
    this.textColor,
    this.fontSize,
  });

  final String name;
  final String? avatarUrl;
  final double size;
  final double borderWidth;
  final Color? borderColor;
  final Color? backgroundColor;
  final Color? textColor;
  final double? fontSize;

  static String getInitials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'SA';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedBorderColor = borderColor ??
        (isDark ? const Color(0xFF26282F) : const Color(0xFFE2E8F0));
    final resolvedBackgroundColor = backgroundColor ??
        (isDark ? const Color(0xFF212328) : const Color(0xFFF1F5F9));
    final resolvedTextColor =
        textColor ?? (isDark ? Colors.white : const Color(0xFF0F172A));

    final initials = getInitials(name);
    final calculatedFontSize = fontSize ?? (size * 0.35).clamp(10.0, 32.0);

    final initialsWidget = Center(
      child: Text(
        initials,
        style: TextStyle(
          fontSize: calculatedFontSize,
          fontWeight: FontWeight.w700,
          color: resolvedTextColor,
          letterSpacing: 0.5,
        ),
      ),
    );

    final hasValidUrl = avatarUrl != null && avatarUrl!.trim().isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: resolvedBackgroundColor,
        border: Border.all(
          color: resolvedBorderColor,
          width: borderWidth,
        ),
      ),
      child: ClipOval(
        child: hasValidUrl
            ? CachedNetworkImage(
                imageUrl: avatarUrl!.trim(),
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (context, url) => initialsWidget,
                errorWidget: (context, url, error) => initialsWidget,
              )
            : initialsWidget,
      ),
    );
  }
}

