import 'package:flutter/material.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/journal_article.dart';
import 'journal_preview_sheet.dart';

/// Featured editorial story card (Hero) in Saman Journal Discover (R01).
class JournalHeroCard extends StatelessWidget {
  const JournalHeroCard({
    super.key,
    required this.article,
    this.onTap,
  });

  final JournalArticle article;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ??
            () {
              JournalPreviewSheet.show(
                context,
                title: article.title,
                categoryLabel: article.badgeLabel ?? 'Phục hồi',
                description: article.contentBody ?? article.summary,
                metricLabel: '${article.readTimeMinutes} phút đọc',
                imageAsset: article.coverImageAsset,
                notice:
                    'Chế độ xem trước nội dung nghiên cứu. Màn đọc toàn văn đầy đủ sẽ được hoàn thiện trong giai đoạn kế tiếp.',
              );
            },
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        child: Container(
          decoration: BoxDecoration(
            color: SamanHomeTokens.cardSurface,
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
            border: Border.all(
              color: SamanHomeTokens.borderSubtle,
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover image with badge & gradient
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      article.coverImageAsset,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: SamanHomeTokens.cardSurfaceElevated,
                        child: const Center(
                          child: Icon(
                            Icons.article_outlined,
                            size: 40,
                            color: SamanHomeTokens.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    // Gradient overlay
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              SamanHomeTokens.cardSurface.withOpacity(0.4),
                              SamanHomeTokens.cardSurface,
                            ],
                            stops: const [0.3, 0.7, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Topic tag
                    Positioned(
                      top: 14,
                      left: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: SamanHomeTokens.greenAccent,
                          borderRadius: BorderRadius.circular(SamanHomeTokens.radiusXs),
                        ),
                        child: Text(
                          (article.badgeLabel ?? 'Phục hồi').toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF003824),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Article content details
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: SamanHomeTokens.textWhite,
                        height: 1.3,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      article.summary,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w400,
                        color: SamanHomeTokens.textSecondary,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 14,
                          color: SamanHomeTokens.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${article.readTimeMinutes} phút đọc',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: SamanHomeTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
