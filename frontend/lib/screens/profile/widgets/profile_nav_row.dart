import 'package:flutter/material.dart';
import '../../home/tokens/saman_home_tokens.dart';

/// Navigation row item for grouped profile setting cards.
///
/// Supports:
/// - Single-line layout (title on left, value on right before chevron)
/// - Two-line layout (title on top, supporting value underneath)
/// - Optional leading icon with structured container
/// - Optional custom value widget (e.g. lock icon + text for Private status)
/// - Trailing chevron with clean alignment
class ProfileNavRow extends StatelessWidget {
  const ProfileNavRow({
    super.key,
    required this.title,
    this.value,
    this.valueWidget,
    this.icon,
    this.isTwoLine = false,
    this.showChevron = true,
    this.showDivider = true,
    this.onTap,
  });

  final String title;
  final String? value;
  final Widget? valueWidget;
  final IconData? icon;
  final bool isTwoLine;
  final bool showChevron;
  final bool showDivider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    final chevronColor =
        tokens.isDark ? const Color(0xFF9CA3AF) : tokens.textMuted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: tokens.isDark
                ? Colors.white.withOpacity(0.04)
                : tokens.textPrimary.withOpacity(0.05),
            highlightColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(
                horizontal: SamanHomeTokens.spacingLg,
                vertical: 12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Leading Icon Container (if provided)
                  if (icon != null) ...[
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: tokens.iconContainerBg,
                        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
                        border: Border.all(
                          color: tokens.borderSubtle,
                          width: 0.8,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          icon,
                          size: 15,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: SamanHomeTokens.spacingMd),
                  ],

                  // Main Text Content
                  Expanded(
                    child: isTwoLine
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: tokens.textWhite,
                                  letterSpacing: -0.1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (valueWidget != null)
                                valueWidget!
                              else if (value != null && value!.isNotEmpty)
                                Text(
                                  value!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: tokens.textWhite,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ),
                              if (valueWidget != null) ...[
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 135),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    widthFactor: 1.0,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: valueWidget!,
                                    ),
                                  ),
                                ),
                              ] else if (value != null && value!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 135),
                                  child: Text(
                                    value!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),

                  // Trailing Chevron
                  if (showChevron) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: chevronColor,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: SamanHomeTokens.spacingLg),
            child: Divider(
              color: tokens.borderSubtle,
              height: 1,
              thickness: 1,
            ),
          ),
      ],
    );
  }
}
