import 'package:flutter/material.dart';
import '../../home/tokens/saman_home_tokens.dart';

/// Container for grouped profile settings and navigation items.
///
/// Features:
/// - Uppercase micro-typography section header (e.g. "HEALTH & GOALS", "PREFERENCES")
/// - Matte card container with 1px hairline border and rounded corners
/// - Clips children to match card curvature
///
/// Hardened behavior:
/// - Safe handling of null or empty titles without extra gaps.
/// - Text truncation safety for long section headers.
class ProfileSectionGroup extends StatelessWidget {
  const ProfileSectionGroup({
    super.key,
    this.title,
    required this.children,
  });

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final hasTitle = title != null && title!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SamanHomeTokens.spacingLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasTitle) ...[
            Text(
              title!.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SamanHomeTokens.sectionHeader,
            ),
            const SizedBox(height: SamanHomeTokens.spacingSm),
          ],
          Container(
            decoration: BoxDecoration(
              color: SamanHomeTokens.cardSurface,
              borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
              border: Border.all(
                color: SamanHomeTokens.border,
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}
