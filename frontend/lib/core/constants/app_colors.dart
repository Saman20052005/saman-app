import 'package:flutter/material.dart';

class AppColors {
  static const Color success = Color(0xFF43A047);
  static const Color warning = Color(0xFFFFA000);
  static const Color error = Color(0xFFE53935);
  static const Color primary = Color(0xFF1E88E5);
}

extension AppColorsExtension on BuildContext {
  ColorScheme get scheme => Theme.of(this).colorScheme;

  Color get background => scheme.surface;
  Color get surface => scheme.surface;
  Color get onSurface => scheme.onSurface;
  Color get primary => scheme.primary;
  Color get onPrimary => scheme.onPrimary;
  Color get outline => scheme.outline;
  Color get error => scheme.error;
}
