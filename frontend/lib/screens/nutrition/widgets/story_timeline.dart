// lib/screens/nutrition/widgets/story_timeline.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../models/meal_log.dart';
import '../../../providers/daily_story_provider.dart';
import '../../../providers/nutrition_provider.dart';
import '../../../config/app_theme.dart';

class StoryTimeline extends ConsumerWidget {
  final DateTime date;

  const StoryTimeline({
    super.key,
    required this.date,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final asyncStories = ref.watch(dailyStoryControllerProvider(dateStr));

    return asyncStories.when(
      loading: () => Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      error: (err, stack) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.error_outline, color: colors.secondary, size: 30),
            const SizedBox(height: 8),
            Text(
              "Lỗi tải story: ${err.toString()}",
              style: TextStyle(fontSize: 12, color: colors.secondary),
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: () =>
                  ref.invalidate(dailyStoryControllerProvider(dateStr)),
              style: TextButton.styleFrom(
                foregroundColor: colors.primary,
              ),
              child: const Text("Thử lại"),
            )
          ],
        ),
      ),
      data: (logs) {
        if (logs.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.camera_alt_outlined,
                    color: colors.outline, size: 40),
                const SizedBox(height: 8),
                Text(
                  'Chưa có story nào hôm nay.\nHãy chụp lại bữa ăn của bạn!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: colors.onSurface),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final MealLog log = logs[index];

            Widget imageWidget;
            final imageUrl = log.imageUrl;

            if (imageUrl != null && imageUrl.isNotEmpty) {
              if (kIsWeb || imageUrl.startsWith('http')) {
                imageWidget = Image.network(
                  imageUrl,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.broken_image, color: colors.secondary),
                );
              } else if (imageUrl.startsWith('file://')) {
                imageWidget = Image.file(
                  File.fromUri(Uri.parse(imageUrl)),
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.broken_image, color: colors.secondary),
                );
              } else {
                imageWidget = Icon(Icons.image_not_supported,
                    size: 30, color: colors.secondary);
              }
            } else {
              imageWidget = Container(
                width: 60,
                height: 60,
                color: context.surfaceColor,
                child: Icon(Icons.restaurant, color: colors.secondary),
              );
            }

            final timeStr = DateFormat('HH:mm').format(log.loggedAt);

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
              elevation: 0,
              color: context.surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colors.outline),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: imageWidget,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: colors.outline),
                            ),
                            child: Text(
                              log.mealType.displayName.toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                color: colors.secondary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            log.foodName.isNotEmpty
                                ? log.foodName
                                : (log.note != null && log.note!.isNotEmpty)
                                    ? log.note!
                                    : 'Đã log món ăn',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: colors.onSurface),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          timeStr,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colors.onSurface),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _confirmDelete(context, ref, log.id),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Icon(Icons.delete_outline,
                                color: colors.secondary, size: 22),
                          ),
                        )
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String logId) {
    final colors = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text("Xoá nhật ký?",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            )),
        content: Text(
            "Bạn có chắc chắn muốn xoá mục này không? Hành động này không thể hoàn tác.",
            style: TextStyle(fontSize: 14, color: colors.onSurface)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Hủy", style: TextStyle(color: colors.secondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final dateStr = DateFormat('yyyy-MM-dd').format(date);
              await ref
                  .read(dailyStoryControllerProvider(dateStr).notifier)
                  .deleteStory(logId);
              ref
                  .read(nutritionProvider.notifier)
                  .loadDailyPlan(date, forceRefresh: true);
            },
            style: TextButton.styleFrom(
              foregroundColor: colors.primary,
            ),
            child: Text("Xoá",
                style: TextStyle(
                    color: colors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
