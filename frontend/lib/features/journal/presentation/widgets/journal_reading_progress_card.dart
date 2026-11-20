import 'package:flutter/material.dart';
import '../../../../config/app_translations.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/journal_article.dart';
import 'journal_preview_sheet.dart';

/// Card showing current reading progress (Resume reading) in R01.
class JournalReadingProgressCard extends StatelessWidget {
  const JournalReadingProgressCard({
    super.key,
    required this.progress,
    this.onTap,
  });

  final JournalReadingProgress progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              context.tr('journal_continue_reading').toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: tokens.textSecondary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: tokens.cardSurfaceElevated,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: tokens.borderSubtle,
                  width: 0.8,
                ),
              ),
              child: Text(
                context.tr('journal_sample_badge'),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: tokens.greenAccent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap ??
                () {
                  JournalPreviewSheet.show(
                    context,
                    title: progress.title,
                    categoryLabel: context.tr('journal_continue_reading'),
                    description:
                        'Tiến độ minh họa: ${progress.percentDisplay}% bài viết. Thời gian đọc ước tính còn lại: ${progress.remainingMinutes} phút.',
                    metricLabel: 'Đã đọc ${progress.percentDisplay}%',
                    imageAsset: progress.coverImageAsset,
                    notice: context.tr('journal_sample_progress_note'),
                  );
                },
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.cardSurface,
                borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
                border: Border.all(
                  color: tokens.borderSubtle,
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusSm),
                        child: SizedBox(
                          width: 58,
                          height: 58,
                          child: Image.asset(
                            progress.coverImageAsset,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: tokens.cardSurfaceElevated,
                              child: Icon(
                                Icons.menu_book_rounded,
                                size: 24,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Text and metrics
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              progress.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: tokens.textWhite,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Đã đọc ${progress.percentDisplay}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    '•',
                                    style: TextStyle(
                                      color: tokens.textTertiary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Text(
                                  'Còn ${progress.remainingMinutes} phút',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress.progressPercent,
                      backgroundColor: tokens.cardSurfaceElevated,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        tokens.greenAccent,
                      ),
                      minHeight: 3.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
