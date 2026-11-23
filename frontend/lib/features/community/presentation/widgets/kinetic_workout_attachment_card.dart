import 'package:flutter/material.dart';
import '../../domain/models/community_post.dart';
import '../tokens/saman_ig_tokens.dart';

class KineticWorkoutAttachmentCard extends StatelessWidget {
  final PostWorkoutAttachment attachment;
  final VoidCallback? onViewWorkout;

  const KineticWorkoutAttachmentCard({
    super.key,
    required this.attachment,
    this.onViewWorkout,
  });

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ig.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ig.primaryAction.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color: ig.primaryAction,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'BUỔI TẬP ĐÃ HOÀN THÀNH',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: SamanIgTokens.fontFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: ig.primaryAction,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                attachment.category,
                style: TextStyle(
                  fontFamily: SamanIgTokens.fontFamily,
                  fontSize: 12,
                  color: ig.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            attachment.title,
            style: TextStyle(
              fontFamily: SamanIgTokens.fontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: ig.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            attachment.summaryFormatted,
            style: TextStyle(
              fontFamily: SamanIgTokens.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: ig.primaryAction,
            ),
          ),
          const SizedBox(height: 14),
          // Exercise thumbnails strip
          Row(
            children: attachment.exercises.map((exercise) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 64,
                        decoration: BoxDecoration(
                          color: ig.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ig.border),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.fitness_center_rounded,
                            size: 26,
                            color: ig.primaryAction,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        exercise.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: SamanIgTokens.fontFamily,
                          fontSize: 11,
                          color: ig.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // Action button
          InkWell(
            onTap: onViewWorkout,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              height: 44,
              decoration: BoxDecoration(
                color: ig.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: ig.border,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Xem buổi tập',
                    style: TextStyle(
                      fontFamily: SamanIgTokens.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ig.primaryAction,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: ig.primaryAction,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
