import 'package:flutter/material.dart';
import '../../home/tokens/saman_home_tokens.dart';

export '../../home/tokens/saman_home_tokens.dart';

/// Design tokens specifically tailored for the Saman Chat module,
/// extending the approved "Athletic Precision" Obsidian foundation.
///
/// Visual rules:
/// - Dark obsidian canvas (#0C0D0E / #121316)
/// - Matte charcoal card & bubble surfaces (#16171B / #1E2024)
/// - Hairline graphite borders (#26282F / #23252A)
/// - Default send action is strictly neutral / monochrome
/// - Semantic green (#10B981) reserved strictly for contextual actions
class SamanChatTokens {
  SamanChatTokens._();

  // ─── Surfaces & Containers ───────────────────────────────────────────
  static const Color canvas = SamanHomeTokens.canvas;
  static const Color surface = SamanHomeTokens.cardSurface; // #16171B
  static const Color surfaceElevated = SamanHomeTokens.cardSurfaceElevated; // #1B1D22
  static const Color iconContainerBg = SamanHomeTokens.iconContainerBg; // #212328
  static const Color chipBackground = Color(0xFF16171B);

  // ─── Borders & Hairlines ─────────────────────────────────────────────
  static const Color border = SamanHomeTokens.border; // #26282F
  static const Color borderSubtle = SamanHomeTokens.borderSubtle; // #23252A

  // ─── Chat Bubble Palettes ────────────────────────────────────────────
  static const Color userBubble = Color(0xFF1E2024);
  static const Color userBubbleBorder = Color(0xFF23252A);
  static const Color assistantBubble = Color(0xFF16171B);
  static const Color assistantBubbleBorder = Color(0xFF23252A);

  // ─── Composer Specific ───────────────────────────────────────────────
  static const Color composerBg = Color(0xFF16171B);
  static const Color composerBorder = Color(0xFF23252A);

  /// Default send button is strictly neutral / monochrome
  static const Color composerSendBg = Color(0xFFE3E2E6);
  static const Color composerSendIcon = Color(0xFF121316);
  static const Color composerSendDisabledBg = Color(0xFF292A2D);
  static const Color composerSendDisabledIcon = Color(0xFF71717A);
  static const Color composerStopBg = Color(0xFF292A2D);
  static const Color composerStopIcon = Color(0xFFE3E2E6);

  // ─── Semantic Accents ────────────────────────────────────────────────
  static const Color greenAccent = SamanHomeTokens.greenAccent; // #10B981
  static const Color amberAccent = SamanHomeTokens.carbsAmber; // #F59E0B
  static const Color violetAccent = SamanHomeTokens.fatViolet; // #A855F7

  // ─── Typography Colors ───────────────────────────────────────────────
  static const Color textWhite = SamanHomeTokens.textWhite;
  static const Color textPrimary = SamanHomeTokens.textPrimary;
  static const Color textSecondary = SamanHomeTokens.textSecondary;
  static const Color textMuted = SamanHomeTokens.textMuted;

  // ─── Monogram Dimensions ─────────────────────────────────────────────
  static const double headerMonogramSize = 20.0;
  static const double heroMonogramSize = 44.0;
  static const double messageMonogramSize = 22.0;

  // ─── Typography Styles ───────────────────────────────────────────────
  static const TextStyle headerTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: textPrimary,
  );

  static const TextStyle heroTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    color: textWhite,
    height: 1.25,
  );

  static const TextStyle heroSubtitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
    color: textSecondary,
    height: 1.4,
  );

  static const TextStyle contextCardOverline = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );

  static const TextStyle contextCardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: textWhite,
  );

  static const TextStyle contextCardSubtitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  static const TextStyle actionRowLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
    color: textWhite,
  );

  static const TextStyle chipLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    color: textWhite,
  );

  static const TextStyle composerInput = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  static const TextStyle composerHint = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textMuted,
  );

  static const TextStyle userMessage = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textWhite,
    height: 1.45,
  );

  static const TextStyle assistantName = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    color: textSecondary,
  );

  static const TextStyle assistantBody = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textWhite,
    height: 1.55,
  );

  static const TextStyle assistantHelper = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textMuted,
    height: 1.4,
  );
}
