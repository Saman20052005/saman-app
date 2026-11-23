import 'package:flutter/material.dart';

/// Design tokens for the Onboarding UI (Dark Calm Athleticism).
class OnboardingTokens {
  OnboardingTokens._();

  // Colors
  static const Color canvas = Color(0xFF0C0D0E);
  static const Color surface = Color(0xFF16171B);
  static const Color surfaceSelected = Color(0xFF1D1F25);
  static const Color borderDefault = Color(0xFF26282F);
  static const Color borderSelected = Color(0xFFE5E7EB);
  static const Color borderSubtle = Color(0xFF212328);
  static const Color divider = Color(0xFF23252A);

  static const Color textPrimary = Color(0xFFF3F4F6);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF737373);
  static const Color textDisabled = Color(0xFF525252);

  static const Color ctaBackground = Color(0xFF26282F);
  static const Color ctaBorder = Color(0xFF374151);
  static const Color ctaDisabledBg = Color(0xFF16171B);
  static const Color ctaDisabledBorder = Color(0xFF26282F);

  static const Color progressActive = Color(0xFFF3F4F6);
  static const Color progressCompleted = Color(0xFF94A3B8);
  static const Color progressUpcoming = Color(0xFF26282F);

  // Radii
  static const double radiusCard = 16.0;
  static const double radiusButton = 12.0;
  static const double radiusTag = 8.0;
  static const double radiusProgress = 4.0;

  // Spacing & Sizes
  static const double paddingHorizontal = 20.0;
  static const double ctaHeight = 54.0;

  /// Adaptive Light / Dark palette resolved from the active [ThemeData.brightness].
  static OnboardingPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? OnboardingPalette.dark
        : OnboardingPalette.light;
  }
}

/// Adaptive token snapshot for Onboarding screens (1-to-1 Light / Dark parity).
@immutable
class OnboardingPalette {
  const OnboardingPalette({
    required this.isDark,
    required this.canvas,
    required this.surface,
    required this.surfaceSelected,
    required this.borderDefault,
    required this.borderSelected,
    required this.borderSubtle,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.ctaBackground,
    required this.ctaBorder,
    required this.ctaText,
    required this.ctaDisabledBg,
    required this.ctaDisabledBorder,
    required this.progressActive,
    required this.progressCompleted,
    required this.progressUpcoming,
  });

  final bool isDark;
  final Color canvas;
  final Color surface;
  final Color surfaceSelected;
  final Color borderDefault;
  final Color borderSelected;
  final Color borderSubtle;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDisabled;
  final Color ctaBackground;
  final Color ctaBorder;
  final Color ctaText;
  final Color ctaDisabledBg;
  final Color ctaDisabledBorder;
  final Color progressActive;
  final Color progressCompleted;
  final Color progressUpcoming;

  static const OnboardingPalette dark = OnboardingPalette(
    isDark: true,
    canvas: OnboardingTokens.canvas,
    surface: OnboardingTokens.surface,
    surfaceSelected: OnboardingTokens.surfaceSelected,
    borderDefault: OnboardingTokens.borderDefault,
    borderSelected: OnboardingTokens.borderSelected,
    borderSubtle: OnboardingTokens.borderSubtle,
    divider: OnboardingTokens.divider,
    textPrimary: OnboardingTokens.textPrimary,
    textSecondary: OnboardingTokens.textSecondary,
    textMuted: OnboardingTokens.textMuted,
    textDisabled: OnboardingTokens.textDisabled,
    ctaBackground: OnboardingTokens.ctaBackground,
    ctaBorder: OnboardingTokens.ctaBorder,
    ctaText: OnboardingTokens.textPrimary,
    ctaDisabledBg: OnboardingTokens.ctaDisabledBg,
    ctaDisabledBorder: OnboardingTokens.ctaDisabledBorder,
    progressActive: OnboardingTokens.progressActive,
    progressCompleted: OnboardingTokens.progressCompleted,
    progressUpcoming: OnboardingTokens.progressUpcoming,
  );

  static const OnboardingPalette light = OnboardingPalette(
    isDark: false,
    canvas: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceSelected: Color(0xFFF1F5F9),
    borderDefault: Color(0xFFE2E8F0),
    borderSelected: Color(0xFF0F172A),
    borderSubtle: Color(0xFFE2E8F0),
    divider: Color(0xFFE2E8F0),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF64748B),
    textDisabled: Color(0xFF94A3B8),
    ctaBackground: Color(0xFF0F172A),
    ctaBorder: Color(0xFF0F172A),
    ctaText: Color(0xFFFFFFFF),
    ctaDisabledBg: Color(0xFFF1F5F9),
    ctaDisabledBorder: Color(0xFFE2E8F0),
    progressActive: Color(0xFF0F172A),
    progressCompleted: Color(0xFF059669),
    progressUpcoming: Color(0xFFE2E8F0),
  );
}
