import 'package:flutter/material.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';

class JourneyFeedback {
  /// Feedback 1 & 2: Meal Saved / Meal Saved + Task Completed
  static void showMealSaved(
    BuildContext context, {
    int? calories,
    bool taskCompleted = false,
    VoidCallback? onViewJourney,
  }) {
    final tokens = SamanHomeTokens.of(context);
    final bg = tokens.isDark ? const Color(0xFF212328) : Colors.white;
    final borderColor = taskCompleted
        ? (tokens.isDark ? const Color(0x4D10B981) : const Color(0x4D059669))
        : (tokens.isDark ? const Color(0xFF26282F) : const Color(0xFFE2E8F0));
    final accent =
        tokens.isDark ? const Color(0xFF10B981) : const Color(0xFF059669);
    final textColor =
        tokens.isDark ? const Color(0xFFF3F4F6) : const Color(0xFF0F172A);
    final subtextColor =
        tokens.isDark ? const Color(0xFF94979E) : const Color(0xFF475569);

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: borderColor,
            width: 1,
          ),
        ),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Icon(
              taskCompleted ? Icons.task_alt_rounded : Icons.check_circle_rounded,
              color: accent,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đã lưu bữa ăn.',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (taskCompleted)
                    Text(
                      'Hoàn thành nhiệm vụ dinh dưỡng.',
                      style: TextStyle(
                        color: subtextColor,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (calories != null && !taskCompleted)
              Text(
                '$calories kcal',
                style: TextStyle(
                  color: subtextColor,
                  fontSize: 12,
                ),
              ),
            if (taskCompleted && onViewJourney != null)
              GestureDetector(
                onTap: () {
                  messenger.hideCurrentSnackBar();
                  onViewJourney();
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Xem',
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: accent,
                      size: 14,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Feedback 3: Workout Saved + Task Completed
  static void showWorkoutSaved(
    BuildContext context, {
    bool taskCompleted = false,
    VoidCallback? onViewJourney,
  }) {
    final tokens = SamanHomeTokens.of(context);
    final bg = tokens.isDark ? const Color(0xFF212328) : Colors.white;
    final borderColor = taskCompleted
        ? (tokens.isDark ? const Color(0x4D10B981) : const Color(0x4D059669))
        : (tokens.isDark ? const Color(0xFF26282F) : const Color(0xFFE2E8F0));
    final accent =
        tokens.isDark ? const Color(0xFF10B981) : const Color(0xFF059669);
    final textColor =
        tokens.isDark ? const Color(0xFFF3F4F6) : const Color(0xFF0F172A);
    final subtextColor =
        tokens.isDark ? const Color(0xFF94979E) : const Color(0xFF475569);

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: borderColor,
            width: 1,
          ),
        ),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Icon(
              Icons.fitness_center_rounded,
              color: accent,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đã lưu buổi tập.',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (taskCompleted)
                    Text(
                      'Hoàn thành nhiệm vụ rèn luyện.',
                      style: TextStyle(
                        color: subtextColor,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (taskCompleted && onViewJourney != null)
              GestureDetector(
                onTap: () {
                  messenger.hideCurrentSnackBar();
                  onViewJourney();
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Xem',
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: accent,
                      size: 14,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Feedback 5: Daily Completion Banner (Non-blocking)
  static void showDailyCompleted(
    BuildContext context, {
    VoidCallback? onClaim,
  }) {
    final tokens = SamanHomeTokens.of(context);
    final bg = tokens.isDark ? const Color(0xFF16171B) : Colors.white;
    final borderColor =
        tokens.isDark ? const Color(0x4D10B981) : const Color(0x4D059669);
    final accent =
        tokens.isDark ? const Color(0xFF10B981) : const Color(0xFF059669);
    final badgeBg =
        tokens.isDark ? const Color(0x3310B981) : const Color(0x1A059669);
    final textColor =
        tokens.isDark ? const Color(0xFFF3F4F6) : const Color(0xFF0F172A);
    final subtextColor =
        tokens.isDark ? const Color(0xFF94979E) : const Color(0xFF475569);

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: borderColor,
            width: 1,
          ),
        ),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.verified_rounded,
                color: accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đã hoàn thành hôm nay!',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '20 điểm thưởng sẵn sàng để nhận',
                    style: TextStyle(
                      color: subtextColor,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (onClaim != null)
              TextButton(
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  onClaim();
                },
                child: Text(
                  'Nhận thưởng',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Feedback 6: Missed Day Supportive Message
  static void showMissedDaySupport(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    final bg = tokens.isDark ? const Color(0xFF212328) : Colors.white;
    final borderColor =
        tokens.isDark ? const Color(0xFF26282F) : const Color(0xFFE2E8F0);
    final sunColor =
        tokens.isDark ? const Color(0xFFFFB95F) : tokens.carbsAmber;
    final textColor =
        tokens.isDark ? const Color(0xFFF3F4F6) : const Color(0xFF0F172A);
    final subtextColor =
        tokens.isDark ? const Color(0xFF94979E) : const Color(0xFF475569);

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor, width: 1),
        ),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Icon(Icons.wb_sunny_rounded, color: sunColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Khởi động lại tràn đầy năng lượng hôm nay.',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Kỷ luật bền bỉ được xây dựng qua thời gian.',
                    style: TextStyle(color: subtextColor, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

