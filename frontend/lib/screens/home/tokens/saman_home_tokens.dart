import 'package:flutter/material.dart';

/// Design tokens specifically crafted for the Saman Home screen
/// based on the approved "Dark Fitness Editorial" design handoff.
///
/// Follows strict visual discipline:
/// - Deep graphite foundation (#0D1013)
/// - Pure card surface (#15191E)
/// - Secondary surface / buttons (#1B2127)
/// - Ambient mood glow (#20362D)
/// - Mint accent (#54DFAC) for primary Start Workout CTA
/// - Graphite dark contrast text (#092018)
/// - Hairline white borders rgba(255, 255, 255, 0.08)
/// - High legibility typography (#F3F5F4 / #ABB4BD)
class SamanHomeTokens {
  SamanHomeTokens._();

  // ─── Surfaces & Backgrounds ──────────────────────────────────────────
  static const Color canvas = Color(0xFF0D1013);
  static const Color cardSurface = Color(0xFF15191E);
  static const Color cardSurfaceElevated = Color(0xFF1B2127);
  static const Color secondarySurface = Color(0xFF1B2127);
  static const Color companionSurface = Color(0xFF15191E);
  static const Color actionButtonSurface = Color(0xFF1B2127);
  static const Color iconContainerBg = Color(0xFF15191E);
  static const Color ambientMoodGlow = Color(0xFF20362D);

  // ─── Hairlines & Borders ─────────────────────────────────────────────
  static const Color border = Color(0x14FFFFFF); // rgba(255, 255, 255, 0.08)
  static const Color borderSubtle = Color(0x14FFFFFF);
  static const Color borderHigh = Color(0x1AFFFFFF); // rgba(255, 255, 255, 0.10)
  static const Color divider = Color(0x14FFFFFF);

  // ─── Typography & Content Colors ─────────────────────────────────────
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFFF3F5F4);
  static const Color textSecondary = Color(0xFFABB4BD);
  static const Color textMuted = Color(0xFF717B8C);
  static const Color textTertiary = Color(0xFF6B7280);

  // ─── Primary Action Accent ───────────────────────────────────────────
  /// Crisp Off-White Primary CTA: Matches editorial hero button (#F9FAFB)
  static const Color primaryCtaBg = Color(0xFFF9FAFB);
  /// Obsidian Black text & icon on Off-White button (#0C0D0E)
  static const Color primaryCtaText = Color(0xFF0C0D0E);

  /// Backwards compatibility aliases
  static const Color mintAccent = Color(0xFFF9FAFB);
  static const Color mintCtaText = Color(0xFF0C0D0E);

  // ─── Semantic Instrumentation Accents ────────────────────────────────
  /// Saman Green: completed sessions, streak, protein intake, positive badges
  static const Color greenAccent = Color(0xFF5BBFA0);
  static const Color greenBadgeBg = Color(0x1A5BBFA0); // 10% opacity
  static const Color greenBadgeBorder = Color(0x335BBFA0); // 20% opacity

  /// Warm Amber: Carbohydrates, Streak, Points
  static const Color carbsAmber = Color(0xFFF59E0B);

  /// Fat Accent: Rose / Pink
  static const Color fatRose = Color(0xFFFB7185);
  static const Color fatViolet = Color(0xFFFB7185); // Backwards compatibility

  /// Water Accent: Cyan
  static const Color waterCyan = Color(0xFF06B6D4);
  static const Color waterFill = Color(0xFF06B6D4);

  /// Caloric & neutral progress fills
  static const Color calorieFill = Color(0xFF5BBFA0);
  static const Color progressTrack = Color(0xFF1B2127);

  // ─── Chart Specific ──────────────────────────────────────────────────
  static const Color chartGrid = Color(0x14FFFFFF);
  static const Color chartTargetDashed = Color(0xFF333C4D);
  static const Color chartActualLine = Color(0xFF5BBFA0);

  // ─── Radii ───────────────────────────────────────────────────────────
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 16.0;
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
    color: textPrimary,
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
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1,
    color: textSecondary,
  );

  static const TextStyle linkText = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: textPrimary,
    height: 1.2,
  );

  static const TextStyle cardSubtitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  static const TextStyle statValue = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: textPrimary,
  );

  static const TextStyle statLabel = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: textSecondary,
  );

  static const TextStyle badgeText = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: textPrimary,
  );
}
