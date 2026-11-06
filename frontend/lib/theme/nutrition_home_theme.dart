import 'package:flutter/material.dart';

import '../screens/home/tokens/saman_home_tokens.dart';

/// Presentation tokens for Nutrition only; the app theme is never replaced.
@immutable
class NutritionHomeStyle extends ThemeExtension<NutritionHomeStyle> {
  const NutritionHomeStyle();
  Color get canvas => SamanHomeTokens.canvas;
  Color get surface => SamanHomeTokens.cardSurface;
  Color get border => SamanHomeTokens.border;
  Color get muted => const Color(0xFFADB1BA);
  Color get ink => SamanHomeTokens.textPrimary;
  Color get accent => SamanHomeTokens.greenAccent;
  Color get onAccent => const Color(0xFF061B14);
  Color get carbs => SamanHomeTokens.carbsAmber;
  Color get fat => SamanHomeTokens.fatViolet;
  Color get track => SamanHomeTokens.progressTrack;
  Color get heroShadow => const Color(0xF20C0D0E);
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
  NutritionHomeStyle copyWith() => this;
  // Fixed Nutrition identity; no theme transition is introduced by this scope.
  @override
  NutritionHomeStyle lerp(NutritionHomeStyle? other, double t) => this;
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
          const NutritionHomeStyle(),
        ]),
        child: child,
      );
}
