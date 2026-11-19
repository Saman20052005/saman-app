import 'package:flutter/material.dart';

enum FeedbackType {
  success,
  info,
  warning,
  error,
}

class SamanFeedbackSnackBar {
  SamanFeedbackSnackBar._();

  static const Color darkBg = Color(0xFF26282D);
  static const Color darkBorder = Color(0xFF383A40);
  static const Color darkText = Color(0xFFF3F4F6);
  static const Color darkSubtext = Color(0xFF94979E);

  static const Color lightBg = Color(0xFFF2F3F5);
  static const Color lightBorder = Color(0xFFDADCE0);
  static const Color lightText = Color(0xFF1A1A18);
  static const Color lightSubtext = Color(0xFF6B6862);

  static const Color successGreen = Color(0xFF10B981);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color errorRed = Color(0xFFEF4444);
  static const Color infoBlue = Color(0xFF3B82F6);

  static IconData _iconForType(FeedbackType type) {
    switch (type) {
      case FeedbackType.success:
        return Icons.check_circle_rounded;
      case FeedbackType.warning:
        return Icons.warning_amber_rounded;
      case FeedbackType.error:
        return Icons.error_outline_rounded;
      case FeedbackType.info:
        return Icons.info_outline_rounded;
    }
  }

  static Color _iconColorForType(FeedbackType type) {
    switch (type) {
      case FeedbackType.success:
        return successGreen;
      case FeedbackType.warning:
        return warningOrange;
      case FeedbackType.error:
        return errorRed;
      case FeedbackType.info:
        return infoBlue;
    }
  }

  static SnackBar build({
    required BuildContext context,
    required String message,
    FeedbackType type = FeedbackType.info,
    String? subtitle,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    Key? key,
    EdgeInsetsGeometry? margin,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? darkBg : lightBg;
    final border = isDark ? darkBorder : lightBorder;
    final textColor = isDark ? darkText : lightText;
    final subtextColor = isDark ? darkSubtext : lightSubtext;
    final iconColor = _iconColorForType(type);
    final iconData = _iconForType(type);

    final screenWidth = MediaQuery.maybeSizeOf(context)?.width ?? 400.0;
    final double horizontalMargin =
        screenWidth > 540.0 ? (screenWidth - 500.0) / 2.0 : 16.0;
    final effectiveMargin = margin ??
        EdgeInsets.fromLTRB(horizontalMargin, 0, horizontalMargin, 16.0);

    SnackBarAction? effectiveAction;
    if (action != null) {
      effectiveAction = SnackBarAction(
        key: action.key,
        label: action.label,
        textColor: action.textColor ?? successGreen,
        disabledTextColor: action.disabledTextColor,
        backgroundColor: action.backgroundColor,
        disabledBackgroundColor: action.disabledBackgroundColor,
        onPressed: action.onPressed,
      );
    }

    return SnackBar(
      key: key,
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      elevation: 3.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(color: border, width: 1.0),
      ),
      margin: effectiveMargin,
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      duration: duration,
      action: effectiveAction,
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            iconData,
            size: 18.0,
            color: iconColor,
          ),
          const SizedBox(width: 10.0),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                    height: 1.25,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2.0),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      color: subtextColor,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    BuildContext context, {
    required String message,
    FeedbackType type = FeedbackType.info,
    String? subtitle,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    Key? key,
    EdgeInsetsGeometry? margin,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    return messenger.showSnackBar(
      build(
        context: context,
        message: message,
        type: type,
        subtitle: subtitle,
        duration: duration,
        action: action,
        key: key,
        margin: margin,
      ),
    );
  }
}

