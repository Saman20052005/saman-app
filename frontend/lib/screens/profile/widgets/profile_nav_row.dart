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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: Colors.white.withOpacity(0.04),
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
                        color: SamanHomeTokens.iconContainerBg,
                        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
                        border: Border.all(
                          color: SamanHomeTokens.borderSubtle,
                          width: 0.8,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          icon,
                          size: 15,
                          color: SamanHomeTokens.textSecondary,
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
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: SamanHomeTokens.textWhite,
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
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: SamanHomeTokens.textSecondary,
                                  ),
                                ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: SamanHomeTokens.textWhite,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (valueWidget != null)
                                valueWidget!
                              else if (value != null && value!.isNotEmpty)
                                Text(
                                  value!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: SamanHomeTokens.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                  ),

                  // Trailing Chevron
                  if (showChevron) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: SamanHomeTokens.textTertiary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: SamanHomeTokens.spacingLg),
            child: Divider(
              color: SamanHomeTokens.borderSubtle,
              height: 1,
              thickness: 1,
            ),
          ),
      ],
    );
  }
}
