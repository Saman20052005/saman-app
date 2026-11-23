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
    return GoogleFonts.manrope(
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

  /// Adaptive Light / Dark palette resolved from the active [ThemeData.brightness].
  static MembershipPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? MembershipPalette.dark
        : MembershipPalette.light;
  }
}

/// Adaptive token snapshot for Membership screens (1-to-1 Light / Dark parity).
@immutable
class MembershipPalette {
  const MembershipPalette({
    required this.isDark,
    required this.canvas,
    required this.card,
    required this.cardHover,
    required this.border,
    required this.borderStrong,
    required this.surfaceHigh,
    required this.textPrimary,
    required this.textMuted,
    required this.textSubtle,
    required this.accent,
    required this.accentBg,
    required this.accentBorder,
    required this.primaryCtaBg,
    required this.primaryCtaPressed,
    required this.primaryCtaText,
  });

  final bool isDark;
  final Color canvas;
  final Color card;
  final Color cardHover;
  final Color border;
  final Color borderStrong;
  final Color surfaceHigh;
  final Color textPrimary;
  final Color textMuted;
  final Color textSubtle;
  final Color accent;
  final Color accentBg;
  final Color accentBorder;
  final Color primaryCtaBg;
  final Color primaryCtaPressed;
  final Color primaryCtaText;

  static const MembershipPalette dark = MembershipPalette(
    isDark: true,
    canvas: MembershipTokens.canvas,
    card: MembershipTokens.card,
    cardHover: MembershipTokens.cardHover,
    border: MembershipTokens.border,
    borderStrong: MembershipTokens.borderStrong,
    surfaceHigh: MembershipTokens.surfaceHigh,
    textPrimary: MembershipTokens.textPrimary,
    textMuted: MembershipTokens.textMuted,
    textSubtle: MembershipTokens.textSubtle,
    accent: MembershipTokens.accent,
    accentBg: MembershipTokens.accentBg,
    accentBorder: MembershipTokens.accentBorder,
    primaryCtaBg: MembershipTokens.primaryCtaBg,
    primaryCtaPressed: MembershipTokens.primaryCtaPressed,
    primaryCtaText: MembershipTokens.primaryCtaText,
  );

  static const MembershipPalette light = MembershipPalette(
    isDark: false,
    canvas: Color(0xFFF8FAFC),
    card: Color(0xFFFFFFFF),
    cardHover: Color(0xFFF1F5F9),
    border: Color(0xFFE2E8F0),
    borderStrong: Color(0xFFCBD5E1),
    surfaceHigh: Color(0xFFF1F5F9),
    textPrimary: Color(0xFF0F172A),
    textMuted: Color(0xFF475569),
    textSubtle: Color(0xFF64748B),
    accent: Color(0xFF059669),
    accentBg: Color(0x1A059669),
    accentBorder: Color(0x33059669),
    primaryCtaBg: Color(0xFF0F172A),
    primaryCtaPressed: Color(0xFF1E293B),
    primaryCtaText: Color(0xFFFFFFFF),
  );

  TextStyle headline({
    double fontSize = 18.0,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      MembershipTokens.headline(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? textPrimary,
        height: height,
        letterSpacing: letterSpacing,
      );

  TextStyle body({
    double fontSize = 14.0,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      MembershipTokens.body(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? textPrimary,
        height: height,
        letterSpacing: letterSpacing,
      );

  TextStyle mono({
    double fontSize = 12.0,
    FontWeight fontWeight = FontWeight.w500,
    Color? color,
    double? height,
    double? letterSpacing,
    bool tabular = true,
  }) =>
      MembershipTokens.mono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? textPrimary,
        height: height,
        letterSpacing: letterSpacing,
        tabular: tabular,
      );
}
