import 'package:flutter/material.dart';

/// Design tokens specifically crafted for Saman Workout screens
/// based on the verified "Calm Athleticism" Obsidian design specification.
class SamanWorkoutTokens {
  SamanWorkoutTokens._();

  // ─── Surfaces & Backgrounds ──────────────────────────────────────────
  static const Color canvas = Color(0xFF0C0D0E);
  static const Color cardSurface = Color(0xFF16171B);
  static const Color surfaceElevated = Color(0xFF212328);
  static const Color buttonPrimary = Color(0xFFF9FAFB);
  static const Color buttonPrimaryText = Color(0xFF0C0D0E);

  // ─── Borders & Dividers ──────────────────────────────────────────────
  static const Color border = Color(0xFF26282F);
  static const Color borderSubtle = Color(0xFF23252A);
  static const Color borderHover = Color(0xFF383A42);
  static const Color divider = Color(0xFF26282F);

  // ─── Typography & Content Colors ─────────────────────────────────────
  static const Color textPrimary = Color(0xFFF9FAFB);
  static const Color textSecondary = Color(0xFF94979E);
  static const Color textMuted = Color(0xFF71717A);
  static const Color textSub = Color(0xFFCBD5E1);

  // ─── Semantic Accents ────────────────────────────────────────────────
  static const Color emeraldAccent = Color(0xFF10B981);
  static const Color emeraldBadgeBg = Color(0x1A10B981); // 10% opacity
  static const Color emeraldBadgeBorder = Color(0x3310B981); // 20% opacity
  static const Color amberAccent = Color(0xFFF59E0B);
  static const Color tealAccent = Color(0xFF14B8A6);
  static const Color tealLightAccent = Color(0xFF2DD4BF);
  static const Color crimsonAccent = Color(0xFFEF4444);

  // ─── Radii ───────────────────────────────────────────────────────────
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusPill = 999.0;

  // ─── Spacing ─────────────────────────────────────────────────────────
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 20.0;
  static const double spacingXxl = 24.0;
}
