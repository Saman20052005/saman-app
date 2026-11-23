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
  static const Color surfaceElevated =
      SamanHomeTokens.cardSurfaceElevated; // #1B1D22
  static const Color iconContainerBg =
      SamanHomeTokens.iconContainerBg; // #212328
  static const Color chipBackground = SamanHomeTokens.cardSurface;
  static const Color drawerBg = Color(0xFF111215);
  static const Color drawerScrim = Color(0x99000000);

  // ─── Suggestion Rows & Rapid Chips (Refined Translucent Tokens) ──────
  /// Lightweight translucent white background (alpha 0.025–0.035)
  static const Color actionRowBg = Color(0x08FFFFFF); // ~0.031 white alpha
  /// Hairline translucent white border (alpha ~0.06, max 1px)
  static const Color actionRowBorder = Color(0x0FFFFFFF); // ~0.059 white alpha
  /// Uniform outline icon color (#A8ADB7)
  static const Color actionRowIconColor = Color(0xFFA8ADB7);

  /// Subtle chevron color (#737985)
  static const Color actionRowChevronColor = Color(0xFF737985);

  /// Hover background feedback
  static const Color actionRowHoverBg = Color(0x0DFFFFFF);

  /// Focus background feedback
  static const Color actionRowFocusBg = Color(0x14FFFFFF);

  /// Pressed background feedback (alpha ~0.07)
  static const Color actionRowPressedBg = Color(0x12FFFFFF);

  /// Compact rapid pill background (alpha ~0.025)
  static const Color rapidChipBg = Color(0x06FFFFFF); // ~0.024 white alpha
  /// Compact rapid pill border (alpha ~0.06)
  static const Color rapidChipBorder = Color(0x0FFFFFFF);

  /// Rapid chip outline icon color
  static const Color rapidChipIconColor = Color(0xFFA8ADB7);

  /// Rapid chip text color (#C0C5CF)
  static const Color rapidChipTextColor = Color(0xFFC0C5CF);

  /// Translucent background & border for the data context card to harmonize
  static const Color contextCardBg = Color(0xCC16171B);
  static const Color contextCardBorder = Color(0x1AFFFFFF);

  // ─── Borders & Hairlines ─────────────────────────────────────────────
  static const Color border = SamanHomeTokens.border; // #26282F
  static const Color borderSubtle = SamanHomeTokens.borderSubtle; // #23252A

  // ─── Chat Bubble Palettes ────────────────────────────────────────────
  static const Color userBubble = Color(0xFF1E2024);
  static const Color userBubbleBorder = SamanHomeTokens.borderSubtle;
  static const Color assistantBubble = SamanHomeTokens.cardSurface;
  static const Color assistantBubbleBorder = SamanHomeTokens.borderSubtle;

  // ─── Composer Specific ───────────────────────────────────────────────
  static const Color composerBg = SamanHomeTokens.cardSurface;
  static const Color composerBorder = SamanHomeTokens.borderSubtle;

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

  // ─── Floating Account Menu Tokens (Gemini-Style Charcoal) ─────────
  static const Color menuSurface = Color(0xFF1E2024);
  static const Color menuBorder = Color(0xFF2D3039);
  static const Color menuDivider = Color(0xFF2B2E37);
  static const Color menuGroupHeader = Color(0xFF8E929C);
  static const Color menuItemHover = Color(0xFF282B33);
  static const Color menuItemText = Color(0xFFE4E4E7);
  static const Color menuItemIcon = Color(0xFFA8ADB7);
  static const Color menuChevron = Color(0xFF737985);
  static const Color sparkleWhite = Color(0xFFF3F4F6);

  // ─── Typography Colors ───────────────────────────────────────────────
  static const Color textWhite = SamanHomeTokens.textWhite;
  static const Color textPrimary = SamanHomeTokens.textPrimary;
  static const Color textSecondary = SamanHomeTokens.textSecondary;
  static const Color textMuted = SamanHomeTokens.textMuted;

  // ─── Monogram Dimensions ─────────────────────────────────────────────
  static const double headerMonogramSize = 22.0;
  static const double heroMonogramSize = 42.0;
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
    color: Color(0xFFD5D8E0),
  );

  static const TextStyle chipLabel = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    color: Color(0xFFC0C5CF),
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

  /// Adaptive Light / Dark palette resolved from the active [ThemeData.brightness].
  static SamanChatPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? SamanChatPalette.dark
        : SamanChatPalette.light;
  }
}

/// Adaptive token snapshot for Saman Chat screens (1-to-1 Light / Dark parity).
@immutable
class SamanChatPalette {
  const SamanChatPalette({
    required this.isDark,
    required this.canvas,
    required this.surface,
    required this.surfaceElevated,
    required this.iconContainerBg,
    required this.chipBackground,
    required this.drawerBg,
    required this.drawerScrim,
    required this.actionRowBg,
    required this.actionRowBorder,
    required this.actionRowIconColor,
    required this.actionRowChevronColor,
    required this.actionRowHoverBg,
    required this.actionRowFocusBg,
    required this.actionRowPressedBg,
    required this.actionRowLabelColor,
    required this.rapidChipBg,
    required this.rapidChipBorder,
    required this.rapidChipIconColor,
    required this.rapidChipTextColor,
    required this.contextCardBg,
    required this.contextCardBorder,
    required this.border,
    required this.borderSubtle,
    required this.userBubble,
    required this.userBubbleBorder,
    required this.assistantBubble,
    required this.assistantBubbleBorder,
    required this.composerBg,
    required this.composerBorder,
    required this.composerSendBg,
    required this.composerSendIcon,
    required this.composerSendDisabledBg,
    required this.composerSendDisabledIcon,
    required this.composerStopBg,
    required this.composerStopIcon,
    required this.greenAccent,
    required this.amberAccent,
    required this.violetAccent,
    required this.menuSurface,
    required this.menuBorder,
    required this.menuDivider,
    required this.menuGroupHeader,
    required this.menuItemHover,
    required this.menuItemText,
    required this.menuItemIcon,
    required this.menuChevron,
    required this.sparkleWhite,
    required this.textWhite,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });

  final bool isDark;
  final Color canvas;
  final Color surface;
  final Color surfaceElevated;
  final Color iconContainerBg;
  final Color chipBackground;
  final Color drawerBg;
  final Color drawerScrim;
  final Color actionRowBg;
  final Color actionRowBorder;
  final Color actionRowIconColor;
  final Color actionRowChevronColor;
  final Color actionRowHoverBg;
  final Color actionRowFocusBg;
  final Color actionRowPressedBg;
  final Color actionRowLabelColor;
  final Color rapidChipBg;
  final Color rapidChipBorder;
  final Color rapidChipIconColor;
  final Color rapidChipTextColor;
  final Color contextCardBg;
  final Color contextCardBorder;
  final Color border;
  final Color borderSubtle;
  final Color userBubble;
  final Color userBubbleBorder;
  final Color assistantBubble;
  final Color assistantBubbleBorder;
  final Color composerBg;
  final Color composerBorder;
  final Color composerSendBg;
  final Color composerSendIcon;
  final Color composerSendDisabledBg;
  final Color composerSendDisabledIcon;
  final Color composerStopBg;
  final Color composerStopIcon;
  final Color greenAccent;
  final Color amberAccent;
  final Color violetAccent;
  final Color menuSurface;
  final Color menuBorder;
  final Color menuDivider;
  final Color menuGroupHeader;
  final Color menuItemHover;
  final Color menuItemText;
  final Color menuItemIcon;
  final Color menuChevron;
  final Color sparkleWhite;
  final Color textWhite;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  static const SamanChatPalette dark = SamanChatPalette(
    isDark: true,
    canvas: SamanChatTokens.canvas,
    surface: SamanChatTokens.surface,
    surfaceElevated: SamanChatTokens.surfaceElevated,
    iconContainerBg: SamanChatTokens.iconContainerBg,
    chipBackground: SamanChatTokens.chipBackground,
    drawerBg: SamanChatTokens.drawerBg,
    drawerScrim: SamanChatTokens.drawerScrim,
    actionRowBg: SamanChatTokens.actionRowBg,
    actionRowBorder: SamanChatTokens.actionRowBorder,
    actionRowIconColor: SamanChatTokens.actionRowIconColor,
    actionRowChevronColor: SamanChatTokens.actionRowChevronColor,
    actionRowHoverBg: SamanChatTokens.actionRowHoverBg,
    actionRowFocusBg: SamanChatTokens.actionRowFocusBg,
    actionRowPressedBg: SamanChatTokens.actionRowPressedBg,
    actionRowLabelColor: Color(0xFFD5D8E0),
    rapidChipBg: SamanChatTokens.rapidChipBg,
    rapidChipBorder: SamanChatTokens.rapidChipBorder,
    rapidChipIconColor: SamanChatTokens.rapidChipIconColor,
    rapidChipTextColor: SamanChatTokens.rapidChipTextColor,
    contextCardBg: SamanChatTokens.contextCardBg,
    contextCardBorder: SamanChatTokens.contextCardBorder,
    border: SamanChatTokens.border,
    borderSubtle: SamanChatTokens.borderSubtle,
    userBubble: SamanChatTokens.userBubble,
    userBubbleBorder: SamanChatTokens.userBubbleBorder,
    assistantBubble: SamanChatTokens.assistantBubble,
    assistantBubbleBorder: SamanChatTokens.assistantBubbleBorder,
    composerBg: SamanChatTokens.composerBg,
    composerBorder: SamanChatTokens.composerBorder,
    composerSendBg: SamanChatTokens.composerSendBg,
    composerSendIcon: SamanChatTokens.composerSendIcon,
    composerSendDisabledBg: SamanChatTokens.composerSendDisabledBg,
    composerSendDisabledIcon: SamanChatTokens.composerSendDisabledIcon,
    composerStopBg: SamanChatTokens.composerStopBg,
    composerStopIcon: SamanChatTokens.composerStopIcon,
    greenAccent: SamanChatTokens.greenAccent,
    amberAccent: SamanChatTokens.amberAccent,
    violetAccent: SamanChatTokens.violetAccent,
    menuSurface: SamanChatTokens.menuSurface,
    menuBorder: SamanChatTokens.menuBorder,
    menuDivider: SamanChatTokens.menuDivider,
    menuGroupHeader: SamanChatTokens.menuGroupHeader,
    menuItemHover: SamanChatTokens.menuItemHover,
    menuItemText: SamanChatTokens.menuItemText,
    menuItemIcon: SamanChatTokens.menuItemIcon,
    menuChevron: SamanChatTokens.menuChevron,
    sparkleWhite: SamanChatTokens.sparkleWhite,
    textWhite: SamanChatTokens.textWhite,
    textPrimary: SamanChatTokens.textPrimary,
    textSecondary: SamanChatTokens.textSecondary,
    textMuted: SamanChatTokens.textMuted,
  );

  static const SamanChatPalette light = SamanChatPalette(
    isDark: false,
    canvas: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF1F5F9),
    iconContainerBg: Color(0xFFF1F5F9),
    chipBackground: Color(0xFFFFFFFF),
    drawerBg: Color(0xFFFFFFFF),
    drawerScrim: Color(0x660F172A),
    actionRowBg: Color(0xFFFFFFFF),
    actionRowBorder: Color(0xFFE2E8F0),
    actionRowIconColor: Color(0xFF475569),
    actionRowChevronColor: Color(0xFF64748B),
    actionRowHoverBg: Color(0xFFF1F5F9),
    actionRowFocusBg: Color(0xFFE2E8F0),
    actionRowPressedBg: Color(0xFFE2E8F0),
    actionRowLabelColor: Color(0xFF0F172A),
    rapidChipBg: Color(0xFFFFFFFF),
    rapidChipBorder: Color(0xFFE2E8F0),
    rapidChipIconColor: Color(0xFF475569),
    rapidChipTextColor: Color(0xFF0F172A),
    contextCardBg: Color(0xF2FFFFFF),
    contextCardBorder: Color(0xFFE2E8F0),
    border: Color(0xFFE2E8F0),
    borderSubtle: Color(0xFFE2E8F0),
    userBubble: Color(0xFFF1F5F9),
    userBubbleBorder: Color(0xFFE2E8F0),
    assistantBubble: Color(0xFFFFFFFF),
    assistantBubbleBorder: Color(0xFFE2E8F0),
    composerBg: Color(0xFFFFFFFF),
    composerBorder: Color(0xFFE2E8F0),
    composerSendBg: Color(0xFF059669),
    composerSendIcon: Color(0xFFFFFFFF),
    composerSendDisabledBg: Color(0xFFE2E8F0),
    composerSendDisabledIcon: Color(0xFF64748B),
    composerStopBg: Color(0xFFE2E8F0),
    composerStopIcon: Color(0xFF0F172A),
    greenAccent: Color(0xFF059669),
    amberAccent: Color(0xFFD97706),
    violetAccent: Color(0xFFE11D48),
    menuSurface: Color(0xFFFFFFFF),
    menuBorder: Color(0xFFE2E8F0),
    menuDivider: Color(0xFFE2E8F0),
    menuGroupHeader: Color(0xFF64748B),
    menuItemHover: Color(0xFFF1F5F9),
    menuItemText: Color(0xFF0F172A),
    menuItemIcon: Color(0xFF475569),
    menuChevron: Color(0xFF64748B),
    sparkleWhite: Color(0xFF0F172A),
    textWhite: Color(0xFF0F172A),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF64748B),
  );

  TextStyle get headerTitle => TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: textPrimary,
      );

  TextStyle get heroTitle => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: textWhite,
        height: 1.25,
      );

  TextStyle get heroSubtitle => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.1,
        color: textSecondary,
        height: 1.4,
      );

  TextStyle get contextCardOverline => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textSecondary,
      );

  TextStyle get contextCardTitle => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: textWhite,
      );

  TextStyle get contextCardSubtitle => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: textSecondary,
      );

  TextStyle get actionRowLabel => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        color: actionRowLabelColor,
      );

  TextStyle get chipLabel => TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        color: rapidChipTextColor,
      );

  TextStyle get composerInput => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: textPrimary,
      );

  TextStyle get composerHint => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: textMuted,
      );

  TextStyle get userMessage => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: textWhite,
        height: 1.45,
      );

  TextStyle get assistantName => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: textSecondary,
      );

  TextStyle get assistantBody => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: textWhite,
        height: 1.55,
      );

  TextStyle get assistantHelper => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: textMuted,
        height: 1.4,
      );
}
