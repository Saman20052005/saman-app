import 'package:flutter/material.dart';
import '../../home/tokens/saman_home_tokens.dart';

/// Container for grouped profile settings and navigation items.
///
/// Features:
/// - Uppercase micro-typography section header (e.g. "HEALTH & GOALS", "PREFERENCES")
/// - Matte card container with 1px hairline border and rounded corners
/// - Clips children to match card curvature
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
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SamanHomeTokens.spacingLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title!.isNotEmpty) ...[
            Text(
              title!,
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
