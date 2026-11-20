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
  static const Color textMuted = Color(0xFF9CA3AF);
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

  /// Adaptive Light / Dark palette resolved from the active [ThemeData.brightness].
  static SamanWorkoutPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? SamanWorkoutPalette.dark
        : SamanWorkoutPalette.light;
  }
}

/// Adaptive token snapshot for Saman Workout screens (1-to-1 Light / Dark parity).
@immutable
class SamanWorkoutPalette {
  const SamanWorkoutPalette({
    required this.isDark,
    required this.canvas,
    required this.cardSurface,
    required this.surfaceElevated,
    required this.buttonPrimary,
    required this.buttonPrimaryText,
    required this.border,
    required this.borderSubtle,
    required this.borderHover,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textSub,
    required this.emeraldAccent,
    required this.emeraldBadgeBg,
    required this.emeraldBadgeBorder,
    required this.amberAccent,
    required this.tealAccent,
    required this.tealLightAccent,
    required this.crimsonAccent,
  });

  final bool isDark;
  final Color canvas;
  final Color cardSurface;
  final Color surfaceElevated;
  final Color buttonPrimary;
  final Color buttonPrimaryText;
  final Color border;
  final Color borderSubtle;
  final Color borderHover;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textSub;
  final Color emeraldAccent;
  final Color emeraldBadgeBg;
  final Color emeraldBadgeBorder;
  final Color amberAccent;
  final Color tealAccent;
  final Color tealLightAccent;
  final Color crimsonAccent;

  static const SamanWorkoutPalette dark = SamanWorkoutPalette(
    isDark: true,
    canvas: SamanWorkoutTokens.canvas,
    cardSurface: SamanWorkoutTokens.cardSurface,
    surfaceElevated: SamanWorkoutTokens.surfaceElevated,
    buttonPrimary: SamanWorkoutTokens.buttonPrimary,
    buttonPrimaryText: SamanWorkoutTokens.buttonPrimaryText,
    border: SamanWorkoutTokens.border,
    borderSubtle: SamanWorkoutTokens.borderSubtle,
    borderHover: SamanWorkoutTokens.borderHover,
    divider: SamanWorkoutTokens.divider,
    textPrimary: SamanWorkoutTokens.textPrimary,
    textSecondary: SamanWorkoutTokens.textSecondary,
    textMuted: SamanWorkoutTokens.textMuted,
    textSub: SamanWorkoutTokens.textSub,
    emeraldAccent: SamanWorkoutTokens.emeraldAccent,
    emeraldBadgeBg: SamanWorkoutTokens.emeraldBadgeBg,
    emeraldBadgeBorder: SamanWorkoutTokens.emeraldBadgeBorder,
    amberAccent: SamanWorkoutTokens.amberAccent,
    tealAccent: SamanWorkoutTokens.tealAccent,
    tealLightAccent: SamanWorkoutTokens.tealLightAccent,
    crimsonAccent: SamanWorkoutTokens.crimsonAccent,
  );

  static const SamanWorkoutPalette light = SamanWorkoutPalette(
    isDark: false,
    canvas: Color(0xFFF8FAFC),
    cardSurface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF1F5F9),
    buttonPrimary: Color(0xFF0F172A),
    buttonPrimaryText: Color(0xFFFFFFFF),
    border: Color(0xFFE2E8F0),
    borderSubtle: Color(0xFFE2E8F0),
    borderHover: Color(0xFFCBD5E1),
    divider: Color(0xFFE2E8F0),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF64748B),
    textSub: Color(0xFF334155),
    emeraldAccent: Color(0xFF059669),
    emeraldBadgeBg: Color(0x1A059669),
    emeraldBadgeBorder: Color(0x33059669),
    amberAccent: Color(0xFFD97706),
    tealAccent: Color(0xFF0D9488),
    tealLightAccent: Color(0xFF0F766E),
    crimsonAccent: Color(0xFFDC2626),
  );
}
