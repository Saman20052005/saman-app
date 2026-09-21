import 'package:flutter/material.dart';

/// Design tokens specifically crafted for the Saman Home screen
/// based on the approved "Athletic Precision" Obsidian design handoff.
///
/// Follows strict visual discipline:
/// - Pitch/obsidian dark foundation (#0C0D0E)
/// - Matte charcoal card surfaces (#16171B)
/// - Hairline graphite borders (#26282F, #23252A)
/// - Semantic colors reserved strictly for data (Green, Amber, Violet)
class SamanHomeTokens {
  SamanHomeTokens._();

  // ─── Surfaces & Backgrounds ──────────────────────────────────────────
  static const Color canvas = Color(0xFF0C0D0E);
  static const Color cardSurface = Color(0xFF16171B);
  static const Color cardSurfaceElevated = Color(0xFF1B1D22);
  static const Color companionSurface = Color(0xFF131417);
  static const Color actionButtonSurface = Color(0xFF26282F);
  static const Color iconContainerBg = Color(0xFF212328);

  // ─── Hairlines & Borders ─────────────────────────────────────────────
  static const Color border = Color(0xFF26282F);
  static const Color borderSubtle = Color(0xFF23252A);
  static const Color borderHigh = Color(0xFF353842);
  static const Color divider = Color(0xFF1F2126);

  // ─── Typography & Content Colors ─────────────────────────────────────
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFFF3F4F6);
  static const Color textSecondary = Color(0xFF94979E);
  static const Color textMuted = Color(0xFF71717A);
  static const Color textTertiary = Color(0xFF52525B);

  // ─── Semantic Instrumentation Accents ────────────────────────────────
  /// Saman Green: completed sessions, streak, protein intake, positive badges
  static const Color greenAccent = Color(0xFF10B981);
  static const Color greenBadgeBg = Color(0x1A10B981); // 10% opacity
  static const Color greenBadgeBorder = Color(0x3310B981); // 20% opacity

  /// Warm Amber: Carbohydrates
  static const Color carbsAmber = Color(0xFFF59E0B);

  /// Muted Violet: Dietary Fats
  static const Color fatViolet = Color(0xFFA855F7);

  /// Caloric & neutral progress fills
  static const Color calorieFill = Color(0xFFE5E7EB);
  static const Color waterFill = Color(0xFFD1D5DB);
  static const Color progressTrack = Color(0xFF202227);

  // ─── Chart Specific ──────────────────────────────────────────────────
  static const Color chartGrid = Color(0xFF22242B);
  static const Color chartTargetDashed = Color(0xFF71717A);
  static const Color chartActualLine = Color(0xFF10B981);

  // ─── Radii ───────────────────────────────────────────────────────────
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusPill = 9999.0;

  // ─── Spacing ─────────────────────────────────────────────────────────
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 20.0;
  static const double spacingXxl = 24.0;
  static const double spacingSection = 16.0;

  // ─── Typography Styles ───────────────────────────────────────────────
  static const TextStyle screenTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: textWhite,
    height: 1.2,
  );

  static const TextStyle headerSubtitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: textSecondary,
    height: 1.3,
  );

  static const TextStyle sectionHeader = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.1,
    color: textSecondary,
  );

  static const TextStyle linkText = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: textWhite,
    height: 1.2,
  );

  static const TextStyle cardSubtitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  static const TextStyle statValue = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: textWhite,
  );

  static const TextStyle statLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.6,
    color: textMuted,
  );

  static const TextStyle badgeText = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: textWhite,
  );
}
