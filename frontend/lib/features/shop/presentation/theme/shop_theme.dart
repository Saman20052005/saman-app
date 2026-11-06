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
}
