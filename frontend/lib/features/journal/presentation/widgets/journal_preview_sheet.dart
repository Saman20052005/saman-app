import 'package:flutter/material.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';

/// Minimal preview modal bottom sheet for items that do not yet have
/// an approved full-screen detail destination in this checkpoint.
///
/// Prevents silent/dead taps while strictly honoring checkpoint boundaries
/// without building out-of-scope detail screens.
class JournalPreviewSheet extends StatelessWidget {
  const JournalPreviewSheet({
    super.key,
    required this.title,
    required this.categoryLabel,
    required this.description,
    this.metricLabel,
    this.imageAsset,
    this.icon,
    this.notice,
  });

  final String title;
  final String categoryLabel;
  final String description;
  final String? metricLabel;
  final String? imageAsset;
  final IconData? icon;
  final String? notice;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String categoryLabel,
    required String description,
    String? metricLabel,
    String? imageAsset,
    IconData? icon,
    String? notice,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => JournalPreviewSheet(
        title: title,
        categoryLabel: categoryLabel,
        description: description,
        metricLabel: metricLabel,
        imageAsset: imageAsset,
        icon: icon,
        notice: notice,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: SamanHomeTokens.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: SamanHomeTokens.border, width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        left: SamanHomeTokens.spacingLg,
        right: SamanHomeTokens.spacingLg,
        top: SamanHomeTokens.spacingMd,
        bottom: MediaQuery.paddingOf(context).bottom + SamanHomeTokens.spacingLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: SamanHomeTokens.borderHigh,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: SamanHomeTokens.spacingMd),

          // Category Badge & Metric
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SamanHomeTokens.greenBadgeBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: SamanHomeTokens.greenBadgeBorder),
                ),
                child: Text(
                  categoryLabel.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: SamanHomeTokens.greenAccent,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (metricLabel != null) ...[
                const SizedBox(width: 8),
                Text(
                  metricLabel!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: SamanHomeTokens.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Title
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: SamanHomeTokens.textWhite,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),

          // Description
          Text(
            description,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              color: SamanHomeTokens.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: SamanHomeTokens.spacingMd),

          // Notice (e.g. preview boundary note)
          if (notice != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SamanHomeTokens.canvas,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SamanHomeTokens.borderSubtle),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: SamanHomeTokens.greenAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notice!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SamanHomeTokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: SamanHomeTokens.spacingLg),

          // Close button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: SamanHomeTokens.actionButtonSurface,
                foregroundColor: SamanHomeTokens.textWhite,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: SamanHomeTokens.border),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'Đóng',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
