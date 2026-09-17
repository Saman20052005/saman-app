import 'package:flutter/material.dart';

class AppShadows {
  static const BoxShadow small = BoxShadow(
    color: Colors.black12,
    blurRadius: 4,
    offset: Offset(0, 2),
  );
  static const BoxShadow medium = BoxShadow(
    color: Colors.black26,
    blurRadius: 8,
    offset: Offset(0, 4),
  );
  static const BoxShadow large = BoxShadow(
    color: Colors.black38,
    blurRadius: 12,
    offset: Offset(0, 6),
  );

  static List<BoxShadow> subtle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
        blurRadius: isDark ? 18 : 16,
        offset: const Offset(0, 8),
      ),
    ];
  }
}
