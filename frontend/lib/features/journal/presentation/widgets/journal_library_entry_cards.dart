import 'package:flutter/material.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/journal_article.dart';
import 'journal_preview_sheet.dart';

/// 2-column knowledge library cards (Exercises, Foods) in R01.
class JournalLibraryEntryCards extends StatelessWidget {
  const JournalLibraryEntryCards({
    super.key,
    required this.entries,
    this.onViewAllTap,
  });

  final List<JournalLibraryEntry> entries;
  final VoidCallback? onViewAllTap;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final tokens = SamanHomeTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Thư viện',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: tokens.textWhite,
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onViewAllTap ??
                    () {
                      JournalPreviewSheet.show(
                        context,
                        title: 'Thư viện tri thức Saman',
                        categoryLabel: 'Bộ sưu tập',
                        description:
                            'Bao gồm 128 chuyển động bài tập và 240+ dữ liệu dinh dưỡng chuẩn hóa được tích hợp trực tiếp.',
                        notice:
                            'Tính năng Thư viện đầy đủ đang được xây dựng theo lộ trình.',
                      );
                    },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Xem tất cả',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: tokens.greenAccent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: entries.map((entry) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: entry == entries.first ? 6 : 0,
                  left: entry == entries.last ? 6 : 0,
                ),
                child: _LibraryCard(entry: entry),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({required this.entry});

  final JournalLibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          JournalPreviewSheet.show(
            context,
            title: entry.title,
            categoryLabel: 'Thư viện',
            description: entry.routeDescription ??
                'Dữ liệu chuẩn hóa với ${entry.itemCountLabel}.',
            metricLabel: entry.itemCountLabel,
            imageAsset: entry.coverImageAsset,
            icon: entry.icon,
            notice:
                'Màn duyệt chi tiết của Thư viện đang được xây dựng theo lộ trình phát triển.',
          );
        },
        borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
        child: Container(
          height: 165,
          decoration: BoxDecoration(
            color: tokens.cardSurface,
            borderRadius: BorderRadius.circular(SamanHomeTokens.radiusLg),
            border: Border.all(
              color: tokens.borderSubtle,
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                entry.coverImageAsset,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: tokens.cardSurfaceElevated,
                  child: Center(
                    child: Icon(
                      entry.icon,
                      size: 32,
                      color: tokens.greenAccent,
                    ),
                  ),
                ),
              ),
              // Dark scrim gradient kept in both light & dark mode for legible text over cover photo
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Color(0x660C0D0E),
                        Color(0xF20C0D0E),
                      ],
                      stops: [0.2, 0.65, 1.0],
                    ),
                  ),
                ),
              ),
              // Content
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B2127).withOpacity(0.85),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        entry.icon,
                        size: 16,
                        color: const Color(0xFF5BBFA0),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF9FAFB),
                        height: 1.25,
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.itemCountLabel,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFFCBD5E1),
                        fontWeight: FontWeight.w400,
                      ),
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
