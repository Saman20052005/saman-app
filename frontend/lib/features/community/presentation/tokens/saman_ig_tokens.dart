import 'package:flutter/material.dart';

/// Isolated Instagram-inspired design tokens for the Saman Community module.
///
/// Supports Dark Mode and Light Mode, enforces `Manrope` typography across all
/// text styles, and maintains a minimum interactive touch target of `44.0`.
@immutable
class SamanIgTokens {
  const SamanIgTokens({
    required this.isDark,
    required this.canvas,
    required this.surface,
    required this.surfaceElevated,
    required this.border,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.primaryAction,
    required this.onPrimaryAction,
    required this.likeHeart,
    required this.dmBubbleSent,
    required this.dmBubbleReceived,
    required this.secondaryButtonBg,
    required this.secondaryButtonText,
    required this.danger,
    required this.scrim,
  });

  static const String fontFamily = 'Manrope';
  static const double minTouchTarget = 44.0;

  static const List<Color> storyGradientColors = <Color>[
    Color(0xFFFEDA75),
    Color(0xFFFA7E1E),
    Color(0xFFD62976),
    Color(0xFF962FBF),
    Color(0xFF4F5BD5),
  ];

  static const LinearGradient storyGradient = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: storyGradientColors,
  );

  static const LinearGradient dmSentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFF5B51D8),
      Color(0xFF3797F0),
    ],
  );

  final bool isDark;
  final Color canvas;
  final Color surface;
  final Color surfaceElevated;
  final Color border;
  final Color borderSubtle;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color primaryAction;
  final Color onPrimaryAction;
  final Color likeHeart;
  final Color dmBubbleSent;
  final Color dmBubbleReceived;
  final Color secondaryButtonBg;
  final Color secondaryButtonText;
  final Color danger;
  final Color scrim;

  static const SamanIgTokens dark = SamanIgTokens(
    isDark: true,
    canvas: Color(0xFF000000),
    surface: Color(0xFF121212),
    surfaceElevated: Color(0xFF262626),
    border: Color(0xFF262626),
    borderSubtle: Color(0xFF1C1C1C),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFFA8A8A8),
    textMuted: Color(0xFF737373),
    primaryAction: Color(0xFF0095F6),
    onPrimaryAction: Color(0xFFFFFFFF),
    likeHeart: Color(0xFFFF3040),
    dmBubbleSent: Color(0xFF3797F0),
    dmBubbleReceived: Color(0xFF262626),
    secondaryButtonBg: Color(0xFF262626),
    secondaryButtonText: Color(0xFFF5F5F5),
    danger: Color(0xFFED4956),
    scrim: Color(0x99000000),
  );

  static const SamanIgTokens light = SamanIgTokens(
    isDark: false,
    canvas: Color(0xFFFFFFFF),
    surface: Color(0xFFFAFAFA),
    surfaceElevated: Color(0xFFEFEFEF),
    border: Color(0xFFDBDBDB),
    borderSubtle: Color(0xFFEFEFEF),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF737373),
    textMuted: Color(0xFF8E8E8E),
    primaryAction: Color(0xFF0095F6),
    onPrimaryAction: Color(0xFFFFFFFF),
    likeHeart: Color(0xFFFF3040),
    dmBubbleSent: Color(0xFF3797F0),
    dmBubbleReceived: Color(0xFFEFEFEF),
    secondaryButtonBg: Color(0xFFEFEFEF),
    secondaryButtonText: Color(0xFF000000),
    danger: Color(0xFFED4956),
    scrim: Color(0x80000000),
  );

  static SamanIgTokens of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  TextStyle displayTitle({
    Color? color,
    FontWeight fontWeight = FontWeight.w700,
    double fontSize = 20,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      color: color ?? textPrimary,
      fontWeight: fontWeight,
      fontSize: fontSize,
    );
  }

  TextStyle username({
    Color? color,
    FontWeight fontWeight = FontWeight.w600,
    double fontSize = 14,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      color: color ?? textPrimary,
      fontWeight: fontWeight,
      fontSize: fontSize,
    );
  }

  TextStyle body({
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double fontSize = 14,
    double? height,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      color: color ?? textPrimary,
      fontWeight: fontWeight,
      fontSize: fontSize,
      height: height,
    );
  }

  TextStyle caption({
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double fontSize = 12,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      color: color ?? textSecondary,
      fontWeight: fontWeight,
      fontSize: fontSize,
    );
  }

  TextStyle buttonLabel({
    Color? color,
    FontWeight fontWeight = FontWeight.w600,
    double fontSize = 14,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      color: color ?? onPrimaryAction,
      fontWeight: fontWeight,
      fontSize: fontSize,
    );
  }

  ButtonStyle primaryButtonStyle({
    double minHeight = minTouchTarget,
    double borderRadius = 8,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: primaryAction,
      foregroundColor: onPrimaryAction,
      elevation: 0,
      shadowColor: Colors.transparent,
      minimumSize: Size(minTouchTarget, minHeight),
      tapTargetSize: MaterialTapTargetSize.padded,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      textStyle: buttonLabel(color: onPrimaryAction),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }

  ButtonStyle secondaryButtonStyle({
    double minHeight = minTouchTarget,
    double borderRadius = 8,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: secondaryButtonBg,
      foregroundColor: secondaryButtonText,
      elevation: 0,
      shadowColor: Colors.transparent,
      minimumSize: Size(minTouchTarget, minHeight),
      tapTargetSize: MaterialTapTargetSize.padded,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      textStyle: buttonLabel(color: secondaryButtonText),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }

  InputDecoration inputDecoration({
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    double borderRadius = 10,
    EdgeInsetsGeometry? contentPadding,
  }) {
    final OutlineInputBorder baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: BorderSide(color: borderSubtle, width: 1),
    );
    return InputDecoration(
      hintText: hintText,
      hintStyle: body(color: textMuted),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: surfaceElevated,
      contentPadding: contentPadding ??
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: baseBorder,
      enabledBorder: baseBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide(color: primaryAction, width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide(color: danger, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide(color: danger, width: 1.4),
      ),
    );
  }
}

extension SamanIgThemeContext on BuildContext {
  SamanIgTokens get igTokens => SamanIgTokens.of(this);
}
