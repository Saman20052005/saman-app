// lib/config/theme_provider.dart
//
// BUG FIX #1 (line 37): onPrimary: Colors.white        → const Color(0xFFFFFFFF)
// BUG FIX #2 (line 42): onSurface: Colors.black        → const Color(0xFF1A1A1A)
// BUG FIX #3 (line 44): shadow: Colors.black12         → const Color(0x1F000000)
// BUG FIX #4 (dark):    onPrimary: Colors.black        → const Color(0xFF0F0F0F)
// BUG FIX #5 (dark):    onSurface: Colors.white        → const Color(0xFFF0F0F0)
// BUG FIX #6 (dark):    shadow: Colors.black54         → const Color(0x8A000000)
//
// ALIGN: primary accent tím → monochrome (đồng bộ với toàn bộ redesign session)
//   light primary: Color(0xFF9B7BFF) → Color(0xFF1A1A1A)
//   dark  primary: Color(0xFFB794F4) → Color(0xFFF0F0F0)
//
// LOGIC: giữ nguyên 100%
//   - ThemeNotifier, toggleTheme(), _loadTheme()
//   - SharedPreferences key 'is_dark_mode' (bool) — không đổi
//   - themeProvider — không đổi

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Notifier (không thay đổi gì) ─────────────────────────────────────────────
class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.light) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('is_dark_mode') ?? false; // key giữ nguyên
    state = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (state == ThemeMode.light) {
      state = ThemeMode.dark;
      await prefs.setBool('is_dark_mode', true);
    } else {
      state = ThemeMode.light;
      await prefs.setBool('is_dark_mode', false);
    }
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});

// ── Semantic color constants ──────────────────────────────────────────────────
// Dùng const thay vì Colors.X để tránh bug hardcode + dễ trace
// Light
const _lightSurface = Color(0xFFF8F8F8); // giữ nguyên từ source gốc
const _lightBg = Color(0xFFFFFFFF); // giữ nguyên
const _lightPrimary = Color(0xFF1A1A1A); // BUG FIX: thay #9B7BFF → monochrome
const _lightOnPrimary = Color(0xFFFFFFFF); // BUG FIX #1: thay Colors.white
const _lightOnSurface = Color(0xFF1A1A1A); // BUG FIX #2: thay Colors.black
const _lightSecondary = Color(0xFF757575); // giữ nguyên
const _lightTertiary = Color(0xFFE0E0E0); // giữ nguyên
const _lightOutline = Color(0xFFE0E0E0); // giữ nguyên
const _lightShadow = Color(0x1F000000); // BUG FIX #3: thay Colors.black12

// Dark
const _darkBg = Color(0xFF0F0F0F); // giữ nguyên
const _darkSurface = Color(0xFF1E1E1E); // giữ nguyên
const _darkPrimary = Color(0xFFF0F0F0); // BUG FIX: thay #B794F4 → monochrome
const _darkOnPrimary = Color(0xFF0F0F0F); // BUG FIX #4: thay Colors.black
const _darkOnSurface = Color(0xFFF0F0F0); // BUG FIX #5: thay Colors.white
const _darkSecondary = Color(0xFFB0B0B0); // giữ nguyên
const _darkTertiary = Color(0xFF2C2C2C); // giữ nguyên
const _darkOutline = Color(0xFF2C2C2C); // giữ nguyên
const _darkShadow = Color(0x8A000000); // BUG FIX #6: thay Colors.black54

// ── Light theme ───────────────────────────────────────────────────────────────
final lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  scaffoldBackgroundColor: _lightBg,
  cardColor: _lightSurface,
  primaryColor: _lightPrimary,
  colorScheme: const ColorScheme.light(
    primary: _lightPrimary,
    onPrimary: _lightOnPrimary, // BUG FIX #1
    surface: _lightSurface,
    onSurface: _lightOnSurface, // BUG FIX #2
    secondary: _lightSecondary,
    tertiary: _lightTertiary,
    outline: _lightOutline,
    shadow: _lightShadow, // BUG FIX #3
    error: Color(0xFFB00020),
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: _lightOnSurface),
    titleMedium: TextStyle(color: _lightOnSurface, fontWeight: FontWeight.bold),
    labelSmall: TextStyle(color: _lightSecondary),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: _lightPrimary,
      foregroundColor: _lightOnPrimary,
    ),
  ),
);

// ── Dark theme ────────────────────────────────────────────────────────────────
final darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: _darkBg,
  cardColor: _darkSurface,
  primaryColor: _darkPrimary,
  colorScheme: const ColorScheme.dark(
    primary: _darkPrimary,
    onPrimary: _darkOnPrimary, // BUG FIX #4
    surface: _darkSurface,
    onSurface: _darkOnSurface, // BUG FIX #5
    secondary: _darkSecondary,
    tertiary: _darkTertiary,
    outline: _darkOutline,
    shadow: _darkShadow, // BUG FIX #6
    error: Color(0xFFCF6679),
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: _darkOnSurface),
    titleMedium: TextStyle(color: _darkOnSurface, fontWeight: FontWeight.bold),
    labelSmall: TextStyle(color: _darkSecondary),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: _darkPrimary,
      foregroundColor: _darkOnPrimary,
    ),
  ),
);
