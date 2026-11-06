import 'package:flutter/material.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/community_post.dart';

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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF292A2B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF3C4A42).withOpacity(0.5),
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
                    color: SamanHomeTokens.greenAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color: SamanHomeTokens.greenAccent,
                      ),
                      SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'BUỔI TẬP ĐÃ HOÀN THÀNH',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: SamanHomeTokens.greenAccent,
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
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFBBCAAF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            attachment.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: SamanHomeTokens.textWhite,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            attachment.summaryFormatted,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: SamanHomeTokens.greenAccent,
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
                          color: const Color(0xFF343536),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.fitness_center_rounded,
                            size: 26,
                            color: SamanHomeTokens.greenAccent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        exercise.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE3E2E3),
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
                color: const Color(0xFF0D0E0F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF343536),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Xem buổi tập',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SamanHomeTokens.greenAccent,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: SamanHomeTokens.greenAccent,
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
