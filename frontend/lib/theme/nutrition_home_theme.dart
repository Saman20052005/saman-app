import 'package:flutter/material.dart';

import '../screens/home/tokens/saman_home_tokens.dart';

/// Presentation tokens for Nutrition only; the app theme is never replaced.
@immutable
class NutritionHomeStyle extends ThemeExtension<NutritionHomeStyle> {
  const NutritionHomeStyle({this.brightness = Brightness.dark});

  final Brightness brightness;

  bool get isDark => brightness == Brightness.dark;

  Color get canvas => isDark ? SamanHomeTokens.canvas : const Color(0xFFF8FAFC);
  Color get surface =>
      isDark ? SamanHomeTokens.cardSurface : const Color(0xFFFFFFFF);
  Color get border => isDark ? SamanHomeTokens.border : const Color(0xFFE2E8F0);
  Color get muted =>
      isDark ? const Color(0xFFADB1BA) : const Color(0xFF475569);
  Color get ink =>
      isDark ? SamanHomeTokens.textPrimary : const Color(0xFF0F172A);
  Color get accent =>
      isDark ? SamanHomeTokens.greenAccent : const Color(0xFF059669);
  Color get onAccent =>
      isDark ? const Color(0xFF061B14) : const Color(0xFFFFFFFF);
  Color get carbs =>
      isDark ? SamanHomeTokens.carbsAmber : const Color(0xFFD97706);
  Color get fat =>
      isDark ? SamanHomeTokens.fatViolet : const Color(0xFFE11D48);
  Color get track =>
      isDark ? SamanHomeTokens.progressTrack : const Color(0xFFE2E8F0);
  Color get heroShadow =>
      isDark ? const Color(0xF20C0D0E) : const Color(0xF2F8FAFC);
  BorderRadius get cardRadius => BorderRadius.circular(16);
  BorderRadius get imageRadius => BorderRadius.circular(12);
  BorderRadius get pillRadius => BorderRadius.circular(999);
  TextStyle get title => TextStyle(
      fontSize: 36,
      height: 1.12,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.2,
      color: ink);
  TextStyle get calories => title.copyWith(fontSize: 42, letterSpacing: -1.5);
  TextStyle get section => TextStyle(
      fontSize: 20, height: 1.3, fontWeight: FontWeight.w600, color: ink);
  TextStyle get body => TextStyle(fontSize: 14, height: 1.4, color: ink);
  TextStyle get strong =>
      body.copyWith(fontSize: 15, fontWeight: FontWeight.w600);
  TextStyle get caption => body.copyWith(fontSize: 12, color: muted);
  TextStyle get label => caption.copyWith(
      fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.1);
  ButtonStyle get primaryAction => FilledButton.styleFrom(
        foregroundColor: onAccent,
        backgroundColor: accent,
        minimumSize: const Size(48, 54),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: cardRadius),
        textStyle: body.copyWith(fontWeight: FontWeight.w600),
      );
  ButtonStyle get secondaryAction => OutlinedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: surface,
        minimumSize: const Size(48, 54),
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: cardRadius),
        textStyle: body.copyWith(fontWeight: FontWeight.w600),
      );

  static NutritionHomeStyle of(BuildContext context) {
    final style = Theme.of(context).extension<NutritionHomeStyle>();
    assert(style != null, 'Wrap Nutrition UI in NutritionHomeTheme.');
    return style!;
  }

  @override
  NutritionHomeStyle copyWith({Brightness? brightness}) =>
      NutritionHomeStyle(brightness: brightness ?? this.brightness);

  @override
  NutritionHomeStyle lerp(NutritionHomeStyle? other, double t) {
    if (other is! NutritionHomeStyle) return this;
    return t < 0.5 ? this : other;
  }
}

class NutritionHomeTheme extends StatelessWidget {
  const NutritionHomeTheme({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(extensions: [
          ...Theme.of(context)
              .extensions
              .values
              .where((e) => e is! NutritionHomeStyle),
          NutritionHomeStyle(brightness: Theme.of(context).brightness),
        ]),
        child: child,
      );
}
