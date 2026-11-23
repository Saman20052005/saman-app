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

  /// Adaptive Light / Dark palette resolved from the active [ThemeData.brightness].
  static SamanHomePalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? SamanHomePalette.dark
        : SamanHomePalette.light;
  }
}

/// Adaptive token snapshot for Saman Home screens (1-to-1 Light / Dark parity).
@immutable
class SamanHomePalette {
  const SamanHomePalette({
    required this.isDark,
    required this.canvas,
    required this.cardSurface,
    required this.cardSurfaceElevated,
    required this.secondarySurface,
    required this.companionSurface,
    required this.actionButtonSurface,
    required this.iconContainerBg,
    required this.ambientMoodGlow,
    required this.border,
    required this.borderSubtle,
    required this.borderHigh,
    required this.divider,
    required this.textWhite,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textTertiary,
    required this.primaryCtaBg,
    required this.primaryCtaText,
    required this.mintAccent,
    required this.mintCtaText,
    required this.greenAccent,
    required this.greenBadgeBg,
    required this.greenBadgeBorder,
    required this.carbsAmber,
    required this.fatRose,
    required this.fatViolet,
    required this.waterCyan,
    required this.waterFill,
    required this.calorieFill,
    required this.progressTrack,
    required this.chartGrid,
    required this.chartTargetDashed,
    required this.chartActualLine,
  });

  final bool isDark;
  final Color canvas;
  final Color cardSurface;
  final Color cardSurfaceElevated;
  final Color secondarySurface;
  final Color companionSurface;
  final Color actionButtonSurface;
  final Color iconContainerBg;
  final Color ambientMoodGlow;
  final Color border;
  final Color borderSubtle;
  final Color borderHigh;
  final Color divider;
  final Color textWhite;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textTertiary;
  final Color primaryCtaBg;
  final Color primaryCtaText;
  final Color mintAccent;
  final Color mintCtaText;
  final Color greenAccent;
  final Color greenBadgeBg;
  final Color greenBadgeBorder;
  final Color carbsAmber;
  final Color fatRose;
  final Color fatViolet;
  final Color waterCyan;
  final Color waterFill;
  final Color calorieFill;
  final Color progressTrack;
  final Color chartGrid;
  final Color chartTargetDashed;
  final Color chartActualLine;

  static const SamanHomePalette dark = SamanHomePalette(
    isDark: true,
    canvas: SamanHomeTokens.canvas,
    cardSurface: SamanHomeTokens.cardSurface,
    cardSurfaceElevated: SamanHomeTokens.cardSurfaceElevated,
    secondarySurface: SamanHomeTokens.secondarySurface,
    companionSurface: SamanHomeTokens.companionSurface,
    actionButtonSurface: SamanHomeTokens.actionButtonSurface,
    iconContainerBg: SamanHomeTokens.iconContainerBg,
    ambientMoodGlow: SamanHomeTokens.ambientMoodGlow,
    border: SamanHomeTokens.border,
    borderSubtle: SamanHomeTokens.borderSubtle,
    borderHigh: SamanHomeTokens.borderHigh,
    divider: SamanHomeTokens.divider,
    textWhite: SamanHomeTokens.textWhite,
    textPrimary: SamanHomeTokens.textPrimary,
    textSecondary: SamanHomeTokens.textSecondary,
    textMuted: SamanHomeTokens.textMuted,
    textTertiary: SamanHomeTokens.textTertiary,
    primaryCtaBg: SamanHomeTokens.primaryCtaBg,
    primaryCtaText: SamanHomeTokens.primaryCtaText,
    mintAccent: SamanHomeTokens.mintAccent,
    mintCtaText: SamanHomeTokens.mintCtaText,
    greenAccent: SamanHomeTokens.greenAccent,
    greenBadgeBg: SamanHomeTokens.greenBadgeBg,
    greenBadgeBorder: SamanHomeTokens.greenBadgeBorder,
    carbsAmber: SamanHomeTokens.carbsAmber,
    fatRose: SamanHomeTokens.fatRose,
    fatViolet: SamanHomeTokens.fatViolet,
    waterCyan: SamanHomeTokens.waterCyan,
    waterFill: SamanHomeTokens.waterFill,
    calorieFill: SamanHomeTokens.calorieFill,
    progressTrack: SamanHomeTokens.progressTrack,
    chartGrid: SamanHomeTokens.chartGrid,
    chartTargetDashed: SamanHomeTokens.chartTargetDashed,
    chartActualLine: SamanHomeTokens.chartActualLine,
  );

  static const SamanHomePalette light = SamanHomePalette(
    isDark: false,
    canvas: Color(0xFFF8FAFC),
    cardSurface: Color(0xFFFFFFFF),
    cardSurfaceElevated: Color(0xFFF1F5F9),
    secondarySurface: Color(0xFFF1F5F9),
    companionSurface: Color(0xFFFFFFFF),
    actionButtonSurface: Color(0xFFF1F5F9),
    iconContainerBg: Color(0xFFF1F5F9),
    ambientMoodGlow: Color(0xFFDCFCE7),
    border: Color(0xFFE2E8F0),
    borderSubtle: Color(0xFFE2E8F0),
    borderHigh: Color(0xFFCBD5E1),
    divider: Color(0xFFE2E8F0),
    textWhite: Color(0xFF0F172A),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF64748B),
    textTertiary: Color(0xFF64748B),
    primaryCtaBg: Color(0xFF0F172A),
    primaryCtaText: Color(0xFFFFFFFF),
    mintAccent: Color(0xFF0F172A),
    mintCtaText: Color(0xFFFFFFFF),
    greenAccent: Color(0xFF059669),
    greenBadgeBg: Color(0x1A059669),
    greenBadgeBorder: Color(0x33059669),
    carbsAmber: Color(0xFFD97706),
    fatRose: Color(0xFFE11D48),
    fatViolet: Color(0xFFE11D48),
    waterCyan: Color(0xFF0891B2),
    waterFill: Color(0xFF0891B2),
    calorieFill: Color(0xFF059669),
    progressTrack: Color(0xFFE2E8F0),
    chartGrid: Color(0xFFE2E8F0),
    chartTargetDashed: Color(0xFF94A3B8),
    chartActualLine: Color(0xFF059669),
  );

  TextStyle get screenTitle => TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: textPrimary,
        height: 1.2,
      );

  TextStyle get headerSubtitle => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: textSecondary,
        height: 1.3,
      );

  TextStyle get sectionHeader => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: textSecondary,
      );

  TextStyle get linkText => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textSecondary,
      );

  TextStyle get cardTitle => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: textPrimary,
        height: 1.2,
      );

  TextStyle get cardSubtitle => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: textSecondary,
      );

  TextStyle get statValue => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: textPrimary,
      );

  TextStyle get statLabel => TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: textSecondary,
      );

  TextStyle get badgeText => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: textPrimary,
      );
}
