import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class MembershipTokens {
  // ─── Colors ──────────────────────────────────────────────────────────
  static const Color canvas = Color(0xFF0C0D0E);
  static const Color card = Color(0xFF16171B);
  static const Color cardHover = Color(0xFF1F2126);
  static const Color border = Color(0xFF26282F);
  static const Color borderStrong = Color(0xFF383A42);
  static const Color surfaceHigh = Color(0xFF212328);

  static const Color textPrimary = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF94979E);
  static const Color textSubtle = Color(0xFFCBD5E1);

  static const Color accent = Color(0xFF10B981);
  static const Color accentBg = Color(0x1A10B981); // 10% opacity
  static const Color accentBorder = Color(0x3310B981); // 20% opacity

  static const Color primaryCtaBg = Color(0xFFF9FAFB);
  static const Color primaryCtaPressed = Color(0xFFE5E7EB);
  static const Color primaryCtaText = Color(0xFF0C0D0E);

  // ─── Metrics ─────────────────────────────────────────────────────────
  static const double screenGutter = 16.0;
  static const double cardRadius = 16.0;
  static const double sheetRadius = 16.0;
  static const double buttonRadius = 12.0;
  static const double primaryCtaMinHeight = 52.0;
  static const double minTouchTarget = 48.0;

  // ─── Typography ──────────────────────────────────────────────────────
  static TextStyle headline({
    double fontSize = 18.0,
    FontWeight fontWeight = FontWeight.w600,
    Color color = textPrimary,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.spaceGrotesk(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle body({
    double fontSize = 14.0,
    FontWeight fontWeight = FontWeight.w400,
    Color color = textPrimary,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle mono({
    double fontSize = 12.0,
    FontWeight fontWeight = FontWeight.w500,
    Color color = textPrimary,
    double? height,
    double? letterSpacing,
    bool tabular = true,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );
  }
}
