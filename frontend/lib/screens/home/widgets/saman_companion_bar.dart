import 'package:flutter/material.dart';
import '../tokens/saman_home_tokens.dart';

/// Contextual AI coaching line for the Saman Home screen.
///
/// Features:
/// - Dark obsidian pill surface with hairline border
/// - Athletic lightning glyph
/// - Bold "Saman:" prefix with quiet authoritative coaching guidance
/// - "Ask Saman →" action leading to the conversational coaching surface
class SamanCompanionBar extends StatelessWidget {
  const SamanCompanionBar({
    super.key,
    this.message = 'Leg Day ready. Aim for 40g protein before 2 PM.',
    this.onAskSamanTap,
  });

  final String message;
  final VoidCallback? onAskSamanTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SamanHomeTokens.spacingLg,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: SamanHomeTokens.companionSurface,
          borderRadius: BorderRadius.circular(SamanHomeTokens.radiusMd),
          border: Border.all(
            color: SamanHomeTokens.borderSubtle,
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.bolt_rounded,
              size: 16,
              color: SamanHomeTokens.textSecondary,
            ),
            const SizedBox(width: SamanHomeTokens.spacingSm),
            Expanded(
              child: RichText(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: SamanHomeTokens.textSecondary,
                  ),
                  children: [
                    const TextSpan(
                      text: 'Saman: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: SamanHomeTokens.textWhite,
                      ),
                    ),
                    TextSpan(text: message),
                  ],
                ),
              ),
            ),
            const SizedBox(width: SamanHomeTokens.spacingSm),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAskSamanTap,
                borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ask Saman',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: SamanHomeTokens.textSecondary,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 13,
                        color: SamanHomeTokens.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
