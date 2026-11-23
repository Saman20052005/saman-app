// [File: lib/config/app_theme.dart]
// Monochrome Performance Design System — Light + Dark adaptive

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // Calm Athleticism Light (WCAG AA)
  static const canvas = Color(0xFFEEF2F6);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceElevated = Color(0xFFF1F5F9);
  static const ink = Color(0xFF0F172A);
  static const inkMuted = Color(0xFF475569);
  static const inkSubtle = Color(0xFF64748B);
  static const hairline = Color(0xFFD5DCE6);
  static const primary = Color(0xFF059669);
  static const primaryPressed = Color(0xFF047857);
  static const onPrimary = Color(0xFFFFFFFF);
  static const aiAccent = Color(0xFFEA580C);
  static const error = Color(0xFFDC2626);
  static const warning = Color(0xFFD97706);
  static const amberAccent = Color(0xFFD97706);
  static const cyanAccent = Color(0xFF0891B2);
  static const roseAccent = Color(0xFFE11D48);
}

class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
}

class AppRadius {
  AppRadius._();

  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 9999.0;
}

class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  const AppThemeExtension({
    required this.aiAccent,
    required this.primaryPressed,
    required this.warning,
    required this.inkMuted,
    required this.inkSubtle,
    required this.hairline,
    required this.surfaceElevated,
    required this.heroNumeric,
    required this.labelCaps,
    required this.statValue,
  });

  final Color aiAccent;
  final Color primaryPressed;
  final Color warning;
  final Color inkMuted;
  final Color inkSubtle;
  final Color hairline;
  final Color surfaceElevated;
  final TextStyle heroNumeric;
  final TextStyle labelCaps;
  final TextStyle statValue;

  @override
  AppThemeExtension copyWith({
    Color? aiAccent,
    Color? primaryPressed,
    Color? warning,
    Color? inkMuted,
    Color? inkSubtle,
    Color? hairline,
    Color? surfaceElevated,
    TextStyle? heroNumeric,
    TextStyle? labelCaps,
    TextStyle? statValue,
  }) {
    return AppThemeExtension(
      aiAccent: aiAccent ?? this.aiAccent,
      primaryPressed: primaryPressed ?? this.primaryPressed,
      warning: warning ?? this.warning,
      inkMuted: inkMuted ?? this.inkMuted,
      inkSubtle: inkSubtle ?? this.inkSubtle,
      hairline: hairline ?? this.hairline,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      heroNumeric: heroNumeric ?? this.heroNumeric,
      labelCaps: labelCaps ?? this.labelCaps,
      statValue: statValue ?? this.statValue,
    );
  }

  @override
  AppThemeExtension lerp(
    covariant ThemeExtension<AppThemeExtension>? other,
    double t,
  ) {
    if (other is! AppThemeExtension) return this;
    return AppThemeExtension(
      aiAccent: Color.lerp(aiAccent, other.aiAccent, t)!,
      primaryPressed: Color.lerp(primaryPressed, other.primaryPressed, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      inkSubtle: Color.lerp(inkSubtle, other.inkSubtle, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      heroNumeric: TextStyle.lerp(heroNumeric, other.heroNumeric, t)!,
      labelCaps: TextStyle.lerp(labelCaps, other.labelCaps, t)!,
      statValue: TextStyle.lerp(statValue, other.statValue, t)!,
    );
  }
}

/// Shared Semantic Design Tokens attached to both [SamanTheme.light] and
/// [SamanTheme.dark] for 1-to-1 Light/Dark parity.
@immutable
class SamanPalette extends ThemeExtension<SamanPalette> {
  const SamanPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceElevated,
    required this.border,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.primaryCtaBg,
    required this.primaryCtaText,
    required this.amber,
    required this.rose,
    required this.cyan,
    required this.violet,
    required this.danger,
    required this.isDark,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceElevated;
  final Color border;
  final Color borderSubtle;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color onAccent;
  final Color primaryCtaBg;
  final Color primaryCtaText;
  final Color amber;
  final Color rose;
  final Color cyan;
  final Color violet;
  final Color danger;
  final bool isDark;

  /// Calm Athleticism Light (WCAG AA)
  static const SamanPalette light = SamanPalette(
    canvas: Color(0xFFEEF2F6),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF1F5F9),
    border: Color(0xFFD5DCE6),
    borderSubtle: Color(0xFFEDF2F7),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF64748B),
    accent: Color(0xFF059669),
    onAccent: Color(0xFFFFFFFF),
    primaryCtaBg: Color(0xFF0F172A),
    primaryCtaText: Color(0xFFFFFFFF),
    amber: Color(0xFFD97706),
    rose: Color(0xFFE11D48),
    cyan: Color(0xFF0891B2),
    violet: Color(0xFF7C3AED),
    danger: Color(0xFFDC2626),
    isDark: false,
  );

  /// Calm Athleticism Dark (Obsidian — 100% parity with existing Dark Mode)
  static const SamanPalette dark = SamanPalette(
    canvas: Color(0xFF0C0D0E),
    surface: Color(0xFF16171B),
    surfaceElevated: Color(0xFF1E2026),
    border: Color(0xFF26282F),
    borderSubtle: Color(0xFF23252A),
    textPrimary: Color(0xFFF9FAFB),
    textSecondary: Color(0xFF9CA3AF),
    textMuted: Color(0xFF6B7280),
    accent: Color(0xFF10B981),
    onAccent: Color(0xFF052E16),
    primaryCtaBg: Color(0xFFF9FAFB),
    primaryCtaText: Color(0xFF0C0D0E),
    amber: Color(0xFFF59E0B),
    rose: Color(0xFFFB7185),
    cyan: Color(0xFF06B6D4),
    violet: Color(0xFFA855F7),
    danger: Color(0xFFE53935),
    isDark: true,
  );

  static SamanPalette of(BuildContext context) {
    final ext = Theme.of(context).extension<SamanPalette>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  @override
  SamanPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceElevated,
    Color? border,
    Color? borderSubtle,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? onAccent,
    Color? primaryCtaBg,
    Color? primaryCtaText,
    Color? amber,
    Color? rose,
    Color? cyan,
    Color? violet,
    Color? danger,
    bool? isDark,
  }) {
    return SamanPalette(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      primaryCtaBg: primaryCtaBg ?? this.primaryCtaBg,
      primaryCtaText: primaryCtaText ?? this.primaryCtaText,
      amber: amber ?? this.amber,
      rose: rose ?? this.rose,
      cyan: cyan ?? this.cyan,
      violet: violet ?? this.violet,
      danger: danger ?? this.danger,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  SamanPalette lerp(
    covariant ThemeExtension<SamanPalette>? other,
    double t,
  ) {
    if (other is! SamanPalette) return this;
    return SamanPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      primaryCtaBg: Color.lerp(primaryCtaBg, other.primaryCtaBg, t)!,
      primaryCtaText: Color.lerp(primaryCtaText, other.primaryCtaText, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
      rose: Color.lerp(rose, other.rose, t)!,
      cyan: Color.lerp(cyan, other.cyan, t)!,
      violet: Color.lerp(violet, other.violet, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

class SamanTheme {
  SamanTheme._();

  // ─── Light palette (Calm Athleticism Light + WCAG AA) ───────────
  static const _lBg = Color(0xFFEEF2F6);
  static const _lSurface = Color(0xFFFFFFFF);
  static const _lSurfaceElevated = Color(0xFFF1F5F9);
  static const _lPrimary = Color(0xFF0F172A);
  static const _lSecond = Color(0xFF475569);
  static const _lSubtle = Color(0xFF64748B);
  static const _lOutline = Color(0xFFD5DCE6);
  static const _lAccent = Color(0xFF059669);
  static const _lOnAccent = Color(0xFFFFFFFF);
  static const _lDanger = Color(0xFFDC2626);

  // ─── Dark palette (Calm Athleticism + WCAG AA) ──────────────────
  static const _dBg = Color(0xFF0C0D0E);
  static const _dSurface = Color(0xFF16171B);
  static const _dSurfaceElevated = Color(0xFF1E2026);
  static const _dPrimary = Color(0xFFF9FAFB);
  static const _dSecond = Color(0xFF9CA3AF);
  static const _dSubtle = Color(0xFF6B7280);
  static const _dOutline = Color(0xFF26282F);
  static const _dAccent = Color(0xFF10B981);
  static const _dOnAccent = Color(0xFF052E16);
  static const _dAiAccent = Color(0xFFFF8A3D);
  static const _dPrimaryPressed = Color(0xFF0B7249);
  static const _dWarning = Color(0xFFD97706);

  // ─── Semantic (shared) ──────────────────────────────────────────
  static const success = Color(0xFF4CAF50);
  static const danger = Color(0xFFE53935);
  static const warning = Color(0xFFFFA726);

  static TextTheme _textTheme(Color color, {Color? secondaryColor}) {
    final subColor = secondaryColor ?? color;
    return GoogleFonts.manropeTextTheme(TextTheme(
      displayLarge: GoogleFonts.manrope(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      headlineMedium: GoogleFonts.manrope(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      titleLarge: GoogleFonts.manrope(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      titleMedium: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      titleSmall: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      bodyLarge: GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: color,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: color,
      ),
      bodySmall: GoogleFonts.manrope(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: subColor,
      ),
      labelLarge: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      labelSmall: GoogleFonts.manrope(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: subColor,
      ),
    ));
  }

  // ─── Light theme ────────────────────────────────────────────────
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _lBg,
      cardColor: _lSurface,
      dividerColor: _lOutline,
      colorScheme: const ColorScheme.light(
        primary: _lAccent,
        onPrimary: _lOnAccent,
        secondary: _lSecond,
        onSecondary: _lOnAccent,
        surface: _lSurface,
        onSurface: _lPrimary,
        outline: _lOutline,
        surfaceContainerHighest: _lSurfaceElevated,
        error: _lDanger,
        onError: _lOnAccent,
      ),
      textTheme: _textTheme(_lPrimary, secondaryColor: _lSecond),
      extensions: const [
        AppThemeExtension(
          aiAccent: AppColors.aiAccent,
          primaryPressed: AppColors.primaryPressed,
          warning: AppColors.amberAccent,
          inkMuted: _lSecond,
          inkSubtle: _lSubtle,
          hairline: _lOutline,
          surfaceElevated: _lSurfaceElevated,
          heroNumeric: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 44,
            fontWeight: FontWeight.w800,
            letterSpacing: -2,
            color: _lPrimary,
          ),
          labelCaps: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: _lSecond,
          ),
          statValue: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: _lPrimary,
          ),
        ),
        SamanPalette.light,
      ],
      appBarTheme: const AppBarTheme(
        backgroundColor: _lBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _lPrimary,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          color: _lPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: _lPrimary, size: 22),
        actionsIconTheme: IconThemeData(color: _lPrimary, size: 22),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _lAccent,
        foregroundColor: _lOnAccent,
        elevation: 0,
        shape: StadiumBorder(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lAccent,
          foregroundColor: _lOnAccent,
          disabledBackgroundColor: _lSurfaceElevated,
          disabledForegroundColor: _lSubtle,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _lAccent,
          foregroundColor: _lOnAccent,
          disabledBackgroundColor: _lSurfaceElevated,
          disabledForegroundColor: _lSubtle,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _lPrimary,
          side: const BorderSide(color: _lOutline),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _lPrimary),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: _lSurface,
        hintStyle: TextStyle(color: _lSubtle),
        labelStyle: TextStyle(color: _lSecond),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _lOutline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _lOutline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _lAccent, width: 1.5),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _lAccent,
        linearTrackColor: _lOutline,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: _lSurface,
        side: BorderSide(color: _lOutline),
        labelStyle: TextStyle(color: _lPrimary, fontWeight: FontWeight.w500),
      ),
      dialogTheme: const DialogTheme(
        backgroundColor: _lSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          color: _lPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Manrope',
          color: _lSecond,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: _lSurface,
        contentTextStyle: TextStyle(
          fontFamily: 'Manrope',
          color: _lPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: _lOutline, width: 1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _lSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }

  // ─── Dark theme ─────────────────────────────────────────────────
  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _dBg,
      cardColor: _dSurface,
      dividerColor: _dOutline,
      colorScheme: const ColorScheme.dark(
        primary: _dAccent,
        onPrimary: _dOnAccent,
        secondary: _dSecond,
        onSecondary: _dBg,
        surface: _dSurface,
        onSurface: _dPrimary,
        outline: _dOutline,
        surfaceContainerHighest: _dSurfaceElevated,
        error: danger,
      ),
      textTheme: _textTheme(_dPrimary, secondaryColor: _dSecond),
      extensions: const [
        AppThemeExtension(
          aiAccent: _dAiAccent,
          primaryPressed: _dPrimaryPressed,
          warning: _dWarning,
          inkMuted: _dSecond,
          inkSubtle: _dSubtle,
          hairline: _dOutline,
          surfaceElevated: _dSurfaceElevated,
          heroNumeric: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 44,
            fontWeight: FontWeight.w800,
            letterSpacing: -2,
            color: _dPrimary,
          ),
          labelCaps: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: _dSecond,
          ),
          statValue: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: _dPrimary,
          ),
        ),
        SamanPalette.dark,
      ],
      appBarTheme: const AppBarTheme(
        backgroundColor: _dBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _dPrimary,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          color: _dPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: _dPrimary, size: 22),
        actionsIconTheme: IconThemeData(color: _dPrimary, size: 22),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _dAccent,
        foregroundColor: _dOnAccent,
        elevation: 0,
        shape: StadiumBorder(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _dAccent,
          foregroundColor: _dOnAccent,
          disabledBackgroundColor: _dSurfaceElevated,
          disabledForegroundColor: _dSubtle,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _dAccent,
          foregroundColor: _dOnAccent,
          disabledBackgroundColor: _dSurfaceElevated,
          disabledForegroundColor: _dSubtle,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _dPrimary,
          side: const BorderSide(color: _dOutline),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _dPrimary),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: _dSurface,
        hintStyle: TextStyle(color: _dSubtle),
        labelStyle: TextStyle(color: _dSecond),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _dOutline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _dOutline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _dAccent, width: 1.5),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _dAccent,
        linearTrackColor: _dOutline,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: _dSurface,
        side: BorderSide(color: _dOutline),
        labelStyle: TextStyle(color: _dPrimary, fontWeight: FontWeight.w500),
      ),
      dialogTheme: const DialogTheme(
        backgroundColor: _dSurfaceElevated,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          color: _dPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Manrope',
          color: _dSecond,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF26282D),
        contentTextStyle: TextStyle(
          fontFamily: 'Manrope',
          color: Color(0xFFF3F4F6),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: Color(0xFF383A40), width: 1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _dSurfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }
}

// ─── Context extensions: dùng trong build() ────────────────────────
extension SamanColors on BuildContext {
  /// Full semantic palette (Calm Athleticism Light / Dark)
  SamanPalette get samanColors => SamanPalette.of(this);

  /// Card background — #FFFFFF (light) / #16171B (dark)
  Color get surfaceColor => Theme.of(this).cardColor;

  /// Page background — #F8FAFC (light) / #0C0D0E (dark)
  Color get bgColor => Theme.of(this).scaffoldBackgroundColor;

  /// Insight / secondary elevated card — #F1F5F9 (light) / #1E2026 (dark)
  Color get insightCardColor => Theme.of(this).brightness == Brightness.dark
      ? const Color(0xFF1E2026)
      : const Color(0xFFF1F5F9);

  /// Progress track — #E2E8F0 (light) / #26282F (dark)
  Color get trackColor => Theme.of(this).brightness == Brightness.dark
      ? const Color(0xFF26282F)
      : const Color(0xFFE2E8F0);

  /// Adaptive card shadow
  BoxShadow get cardShadow => Theme.of(this).brightness == Brightness.dark
      ? BoxShadow(
          color: Colors.black.withOpacity(0.35),
          blurRadius: 16,
          offset: const Offset(0, 4),
        )
      : BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 16,
          offset: const Offset(0, 4),
        );

  /// Lighter shadow for small elements
  BoxShadow get softShadow => Theme.of(this).brightness == Brightness.dark
      ? BoxShadow(
          color: Colors.black.withOpacity(0.25),
          blurRadius: 8,
          offset: const Offset(0, 2),
        )
      : BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        );
}
