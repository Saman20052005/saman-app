// [File: lib/config/app_theme.dart]
// Monochrome Performance Design System — Light + Dark adaptive

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const canvas = Color(0xFFFAF8F5);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceElevated = Color(0xFFF3F1EC);
  static const ink = Color(0xFF1A1A18);
  static const inkMuted = Color(0xFF6B6862);
  static const inkSubtle = Color(0xFF9B978F);
  static const hairline = Color(0xFFE5E1D8);
  static const primary = Color(0xFF0E8F5E);
  static const primaryPressed = Color(0xFF0B7249);
  static const onPrimary = Color(0xFFFFFFFF);
  static const aiAccent = Color(0xFFFF8A3D);
  static const error = Color(0xFFC4341C);
  static const warning = Color(0xFFD97706);
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

class SamanTheme {
  SamanTheme._();

  // ─── Light palette ──────────────────────────────────────────────
  static const _lBg = Color(0xFFF5F5F5);
  static const _lSurface = Color(0xFFFFFFFF);
  static const _lPrimary = Color(0xFF1A1A1A);
  static const _lSecond = Color(0xFF888888);
  static const _lOutline = Color(0xFFE8E8E8);

  // ─── Dark palette ───────────────────────────────────────────────
  static const _dBg = Color(0xFF0F0F0F);
  static const _dSurface = Color(0xFF1C1C1C);
  static const _dPrimary = Color(0xFFF0F0F0);
  static const _dSecond = Color(0xFF888888);
  static const _dOutline = Color(0xFF2A2A2A);

  // ─── Semantic (shared) ──────────────────────────────────────────
  static const success = Color(0xFF4CAF50);
  static const danger = Color(0xFFE53935);
  static const warning = Color(0xFFFFA726);

  static TextTheme _textTheme(Color color) {
    return GoogleFonts.interTextTheme(TextTheme(
      displayLarge: GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: color,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: color,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: color,
      ),
    ));
  }

  // ─── Light theme ────────────────────────────────────────────────
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.canvas,
      cardColor: AppColors.surface,
      dividerColor: AppColors.hairline,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        secondary: AppColors.inkMuted,
        onSecondary: AppColors.onPrimary,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        outline: AppColors.hairline,
        surfaceContainerHighest: AppColors.surfaceElevated,
        error: AppColors.error,
      ),
      textTheme: _textTheme(AppColors.ink),
      extensions: const [
        AppThemeExtension(
          aiAccent: AppColors.aiAccent,
          primaryPressed: AppColors.primaryPressed,
          warning: AppColors.warning,
          inkMuted: AppColors.inkMuted,
          inkSubtle: AppColors.inkSubtle,
          hairline: AppColors.hairline,
          surfaceElevated: AppColors.surfaceElevated,
          heroNumeric: TextStyle(
            fontFamily: 'Inter',
            fontSize: 44,
            fontWeight: FontWeight.w800,
            letterSpacing: -2,
            color: AppColors.ink,
          ),
          labelCaps: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: AppColors.inkMuted,
          ),
          statValue: TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: AppColors.ink,
          ),
        ),
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
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        shape: StadiumBorder(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: Color(0xFFD0D0D0),
          disabledForegroundColor: Color(0xFF888888),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _lPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lSurface,
        hintStyle: const TextStyle(color: _lSecond),
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
          borderSide: BorderSide(color: _lPrimary, width: 1.5),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _lPrimary,
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: _lPrimary,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
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
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        secondary: _dSecond,
        onSecondary: Color(0xFF0F0F0F),
        surface: _dSurface,
        onSurface: _dPrimary,
        outline: _dOutline,
        surfaceContainerHighest: Color(0xFF252525),
        error: danger,
      ),
      textTheme: _textTheme(_dPrimary),
      extensions: const [
        AppThemeExtension(
          aiAccent: AppColors.aiAccent,
          primaryPressed: AppColors.primaryPressed,
          warning: AppColors.warning,
          inkMuted: _dSecond,
          inkSubtle: Color(0xFF666666),
          hairline: _dOutline,
          surfaceElevated: Color(0xFF252525),
          heroNumeric: TextStyle(
            fontFamily: 'Inter',
            fontSize: 44,
            fontWeight: FontWeight.w800,
            letterSpacing: -2,
            color: _dPrimary,
          ),
          labelCaps: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: _dSecond,
          ),
          statValue: TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: _dPrimary,
          ),
        ),
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
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        shape: StadiumBorder(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: const Color(0xFF2D2D2D),
          disabledForegroundColor: const Color(0xFF666666),
          elevation: 0,
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
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _dSurface,
        hintStyle: const TextStyle(color: _dSecond),
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: const BorderSide(color: _dOutline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: const BorderSide(color: _dOutline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: const BorderSide(color: _dPrimary, width: 1.5),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _dPrimary,
        linearTrackColor: _dOutline,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: _dSurface,
        side: BorderSide(color: _dOutline),
        labelStyle: TextStyle(color: _dPrimary, fontWeight: FontWeight.w500),
      ),
      dialogTheme: const DialogTheme(
        backgroundColor: _dSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: _dSurface,
        contentTextStyle: TextStyle(color: _dPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _dSurface,
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
  /// Card background — white (light) / #1C1C1C (dark)
  Color get surfaceColor => Theme.of(this).cardColor;

  /// Page background — #F5F5F5 (light) / #0F0F0F (dark)
  Color get bgColor => Theme.of(this).scaffoldBackgroundColor;

  /// Charcoal insight card — #2D2D2D (light) / #1A1A1A (dark)
  Color get insightCardColor => Theme.of(this).brightness == Brightness.dark
      ? const Color(0xFF1A1A1A)
      : const Color(0xFF2D2D2D);

  /// Progress track — muted gray adaptive
  Color get trackColor => Theme.of(this).brightness == Brightness.dark
      ? const Color(0xFF2A2A2A)
      : const Color(0xFFE8E8E8);

  /// Adaptive card shadow
  BoxShadow get cardShadow => Theme.of(this).brightness == Brightness.dark
      ? BoxShadow(
          color: Colors.black.withOpacity(0.35),
          blurRadius: 16,
          offset: const Offset(0, 4),
        )
      : BoxShadow(
          color: Colors.black.withOpacity(0.05),
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
          color: Colors.black.withOpacity(0.03),
          blurRadius: 8,
          offset: const Offset(0, 2),
        );
}
