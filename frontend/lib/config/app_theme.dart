// [File: lib/config/app_theme.dart]
// Monochrome Performance Design System — Light + Dark adaptive

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  // ─── Light theme ────────────────────────────────────────────────
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _lBg,
      cardColor: _lSurface,
      dividerColor: _lOutline,
      colorScheme: const ColorScheme.light(
        primary: _lPrimary,
        onPrimary: Color(0xFFFFFFFF),
        secondary: _lSecond,
        onSecondary: Color(0xFFFFFFFF),
        surface: _lSurface,
        onSurface: _lPrimary,
        outline: _lOutline,
        surfaceContainerHighest: Color(0xFFF0F0F0),
        error: danger,
      ),
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
        backgroundColor: _lPrimary,
        foregroundColor: Color(0xFFFFFFFF),
        elevation: 0,
        shape: StadiumBorder(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lPrimary,
          foregroundColor: Colors.white,
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
        primary: _dPrimary,
        onPrimary: Color(0xFF0F0F0F),
        secondary: _dSecond,
        onSecondary: Color(0xFF0F0F0F),
        surface: _dSurface,
        onSurface: _dPrimary,
        outline: _dOutline,
        surfaceContainerHighest: Color(0xFF252525),
        error: danger,
      ),
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
        backgroundColor: _dPrimary,
        foregroundColor: Color(0xFF0F0F0F),
        elevation: 0,
        shape: StadiumBorder(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _dPrimary,
          foregroundColor: const Color(0xFF0F0F0F),
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
