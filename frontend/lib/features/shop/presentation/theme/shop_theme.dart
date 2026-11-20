import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens and typography for the Saman Shop Curated Boutique.
///
/// Adheres strictly to the verified dark aesthetic:
/// - Canvas: #0C0D0E
/// - Card Surface: #16171B
/// - Border: #23252B / rgba(255,255,255,0.06)
/// - Primary Text: #F3F4F6
/// - Secondary Text: #94979E
/// - Accent: #10B981 (Emerald)
/// - Primary CTA: #F3F4F6 with #0C0D0E text
class ShopTheme {
  ShopTheme._();

  // ─── COLOR TOKENS ──────────────────────────────────────────────────────────
  static const Color canvas = Color(0xFF0C0D0E);
  static const Color surfaceCard = Color(0xFF16171B);
  static const Color surfaceElevated = Color(0xFF1C1D22);
  static const Color surfaceModal = Color(0xFF212329);
  static const Color borderSubtle = Color(0xFF23252B);
  static const Color borderDivider = Color(0x10FFFFFF); // rgba(255,255,255,0.06)

  static const Color textPrimary = Color(0xFFF3F4F6);
  static const Color textSecondary = Color(0xFF94979E);
  static const Color textMuted = Color(0xFF6B7280);

  static const Color emerald = Color(0xFF10B981);
  static const Color ctaSurface = Color(0xFFF3F4F6);
  static const Color ctaText = Color(0xFF0C0D0E);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color errorRed = Color(0xFFEF4444);

  // ─── SPACING & RADII ───────────────────────────────────────────────────────
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 14.0;
  static const double radiusXl = 16.0;
  static const double radiusPill = 999.0;

  static const double paddingPage = 20.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 20.0;

  // ─── TYPOGRAPHY (MANROPE WITH SANS-SERIF FALLBACK) ──────────────────────────
  static TextStyle fontManrope({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = textPrimary,
    double? height,
    double? letterSpacing,
  }) {
    if (!GoogleFonts.config.allowRuntimeFetching) {
      return TextStyle(
        fontFamily: 'Manrope',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
    }
    try {
      return GoogleFonts.manrope(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
    } catch (_) {
      // Fallback in environments where GoogleFonts runtime lookup is restricted
      return TextStyle(
        fontFamily: 'Manrope',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
    }
  }

  static TextStyle get headerTitle => fontManrope(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: textPrimary,
      );

  static TextStyle get heroTitle => fontManrope(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: textPrimary,
      );

  static TextStyle get heroSubtitle => fontManrope(
        fontSize: 11.5,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: textSecondary,
      );

  static TextStyle get heroAction => fontManrope(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textPrimary,
      );

  static TextStyle get tabActive => fontManrope(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );

  static TextStyle get tabInactive => fontManrope(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: textSecondary,
      );

  static TextStyle get sectionHeaderCaps => fontManrope(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: textSecondary,
      );

  static TextStyle get sectionCount => fontManrope(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: textMuted,
      );

  static TextStyle get productTitle => fontManrope(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        height: 1.25,
        color: textPrimary,
      );

  static TextStyle get productPrice => fontManrope(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: textPrimary,
      );

  static TextStyle get demoBadge => fontManrope(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: textMuted,
      );

  static TextStyle get collectionBadge => fontManrope(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
        color: textSecondary,
      );

  static TextStyle get collectionTitle => fontManrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );

  static TextStyle get collectionSubtitle => fontManrope(
        fontSize: 11.5,
        fontWeight: FontWeight.w400,
        color: textSecondary,
      );

  static TextStyle get ctaButtonText => fontManrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: ctaText,
      );

  /// Adaptive Light / Dark palette resolved from the active [ThemeData.brightness].
  static ShopPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? ShopPalette.dark
        : ShopPalette.light;
  }
}

/// Adaptive token snapshot for Saman Shop screens (1-to-1 Light / Dark parity).
@immutable
class ShopPalette {
  const ShopPalette({
    required this.isDark,
    required this.canvas,
    required this.surfaceCard,
    required this.surfaceElevated,
    required this.surfaceModal,
    required this.borderSubtle,
    required this.borderDivider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.emerald,
    required this.ctaSurface,
    required this.ctaText,
    required this.warningAmber,
    required this.errorRed,
  });

  final bool isDark;
  final Color canvas;
  final Color surfaceCard;
  final Color surfaceElevated;
  final Color surfaceModal;
  final Color borderSubtle;
  final Color borderDivider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color emerald;
  final Color ctaSurface;
  final Color ctaText;
  final Color warningAmber;
  final Color errorRed;

  static const ShopPalette dark = ShopPalette(
    isDark: true,
    canvas: ShopTheme.canvas,
    surfaceCard: ShopTheme.surfaceCard,
    surfaceElevated: ShopTheme.surfaceElevated,
    surfaceModal: ShopTheme.surfaceModal,
    borderSubtle: ShopTheme.borderSubtle,
    borderDivider: ShopTheme.borderDivider,
    textPrimary: ShopTheme.textPrimary,
    textSecondary: ShopTheme.textSecondary,
    textMuted: ShopTheme.textMuted,
    emerald: ShopTheme.emerald,
    ctaSurface: ShopTheme.ctaSurface,
    ctaText: ShopTheme.ctaText,
    warningAmber: ShopTheme.warningAmber,
    errorRed: ShopTheme.errorRed,
  );

  static const ShopPalette light = ShopPalette(
    isDark: false,
    canvas: Color(0xFFF8FAFC),
    surfaceCard: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF1F5F9),
    surfaceModal: Color(0xFFFFFFFF),
    borderSubtle: Color(0xFFE2E8F0),
    borderDivider: Color(0xFFE2E8F0),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF64748B),
    emerald: Color(0xFF059669),
    ctaSurface: Color(0xFF0F172A),
    ctaText: Color(0xFFFFFFFF),
    warningAmber: Color(0xFFD97706),
    errorRed: Color(0xFFDC2626),
  );

  TextStyle get headerTitle => ShopTheme.fontManrope(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: textPrimary,
      );

  TextStyle get heroTitle => ShopTheme.fontManrope(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: textPrimary,
      );

  TextStyle get heroSubtitle => ShopTheme.fontManrope(
        fontSize: 11.5,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: textSecondary,
      );

  TextStyle get heroAction => ShopTheme.fontManrope(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textPrimary,
      );

  TextStyle get tabActive => ShopTheme.fontManrope(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );

  TextStyle get tabInactive => ShopTheme.fontManrope(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: textSecondary,
      );

  TextStyle get sectionHeaderCaps => ShopTheme.fontManrope(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: textSecondary,
      );

  TextStyle get sectionCount => ShopTheme.fontManrope(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: textMuted,
      );

  TextStyle get productTitle => ShopTheme.fontManrope(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        height: 1.25,
        color: textPrimary,
      );

  TextStyle get productPrice => ShopTheme.fontManrope(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: textPrimary,
      );

  TextStyle get demoBadge => ShopTheme.fontManrope(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: textMuted,
      );

  TextStyle get collectionBadge => ShopTheme.fontManrope(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
        color: textSecondary,
      );

  TextStyle get collectionTitle => ShopTheme.fontManrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );

  TextStyle get collectionSubtitle => ShopTheme.fontManrope(
        fontSize: 11.5,
        fontWeight: FontWeight.w400,
        color: textSecondary,
      );

  TextStyle get ctaButtonText => ShopTheme.fontManrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: ctaText,
      );
}
