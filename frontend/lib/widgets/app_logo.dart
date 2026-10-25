import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final Color? color;
  final bool isLightMode;

  const AppLogo({
    super.key,
    this.size = 100,
    this.color,
    this.isLightMode = true,
  });

  @override
  Widget build(BuildContext context) {
    // Logo trên Login/Register: S đen ở nền sáng, S trắng ở nền tối
    final isDark = Theme.of(context).brightness == Brightness.dark || !isLightMode;
    final defaultColor = isDark ? Colors.white : const Color(0xFF1E1E1E);
    final targetColor = color ?? defaultColor;
    final assetPath = isDark
        ? 'assets/logo/saman_s_white.svg'
        : 'assets/logo/saman_s_black.svg';

    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        colorFilter: color != null
            ? ColorFilter.mode(targetColor, BlendMode.srcIn)
            : null,
      ),
    );
  }
}
