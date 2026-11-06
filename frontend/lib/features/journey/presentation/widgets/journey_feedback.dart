import 'package:flutter/material.dart';

class JourneyFeedback {
  /// Feedback 1 & 2: Meal Saved / Meal Saved + Task Completed
  static void showMealSaved(
    BuildContext context, {
    int? calories,
    bool taskCompleted = false,
    VoidCallback? onViewJourney,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF212328),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: taskCompleted ? const Color(0x4D10B981) : const Color(0xFF26282F),
            width: 1,
          ),
        ),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Icon(
              taskCompleted ? Icons.task_alt_rounded : Icons.check_circle_rounded,
              color: const Color(0xFF10B981),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Đã lưu bữa ăn.',
                    style: TextStyle(
                      color: Color(0xFFF3F4F6),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (taskCompleted)
                    const Text(
                      'Hoàn thành nhiệm vụ dinh dưỡng.',
                      style: TextStyle(
                        color: Color(0xFF94979E),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (calories != null && !taskCompleted)
              Text(
                '$calories kcal',
                style: const TextStyle(
                  color: Color(0xFF94979E),
                  fontSize: 12,
                ),
              ),
            if (taskCompleted && onViewJourney != null)
              GestureDetector(
                onTap: () {
                  messenger.hideCurrentSnackBar();
                  onViewJourney();
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Xem',
                      style: TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: Color(0xFF10B981),
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
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF212328),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: taskCompleted ? const Color(0x4D10B981) : const Color(0xFF26282F),
            width: 1,
          ),
        ),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            const Icon(
              Icons.fitness_center_rounded,
              color: Color(0xFF10B981),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Đã lưu buổi tập.',
                    style: TextStyle(
                      color: Color(0xFFF3F4F6),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (taskCompleted)
                    const Text(
                      'Hoàn thành nhiệm vụ rèn luyện.',
                      style: TextStyle(
                        color: Color(0xFF94979E),
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
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Xem',
                      style: TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: Color(0xFF10B981),
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
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF16171B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(
            color: Color(0x4D10B981),
            width: 1,
          ),
        ),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0x3310B981),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: Color(0xFF10B981),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đã hoàn thành hôm nay!',
                    style: TextStyle(
                      color: Color(0xFFF3F4F6),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '20 điểm thưởng sẵn sàng để nhận',
                    style: TextStyle(
                      color: Color(0xFF94979E),
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
                child: const Text(
                  'Nhận thưởng',
                  style: TextStyle(
                    color: Color(0xFF10B981),
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
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF212328),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF26282F), width: 1),
        ),
        margin: const EdgeInsets.all(16),
        content: const Row(
          children: [
            Icon(Icons.wb_sunny_rounded, color: Color(0xFFFFB95F), size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Khởi động lại tràn đầy năng lượng hôm nay.',
                    style: TextStyle(
                      color: Color(0xFFF3F4F6),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Kỷ luật bền bỉ được xây dựng qua thời gian.',
                    style: TextStyle(color: Color(0xFF94979E), fontSize: 11),
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

