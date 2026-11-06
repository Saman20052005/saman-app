import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/routes.dart';
import '../../domain/models/journey_models.dart';
import '../providers/journey_providers.dart';

class SamanJourneyCard extends ConsumerWidget {
  final VoidCallback? onCreateJourneyTap;
  final VoidCallback? onViewJourneyTap;

  const SamanJourneyCard({
    super.key,
    this.onCreateJourneyTap,
    this.onViewJourneyTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journeyState = ref.watch(journeyControllerProvider);
    final journey = journeyState.journey;

    if (journey == null || !journey.isActive) {
      return _buildInvitationCard(context);
    }

    return _buildActiveJourneyCard(context, journey);
  }

  Widget _buildInvitationCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF26282F),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x2610B981),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.flag_rounded,
                      size: 13,
                      color: Color(0xFF10B981),
                    ),
                    SizedBox(width: 5),
                    Text(
                      'HÀNH TRÌNH SAMAN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF10B981),
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.auto_awesome,
                size: 16,
                color: Color(0xFFFFB95F),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Khởi đầu thói quen & Bứt phá mục tiêu',
            style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFFF3F4F6),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Cam kết lộ trình 7, 14, 21 hoặc 30 ngày. Tích lũy điểm thưởng mỗi ngày để đổi đặc quyền AI.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF94979E),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () {
                if (onCreateJourneyTap != null) {
                  onCreateJourneyTap!();
                } else {
                  Navigator.of(context).pushNamed(AppRoutes.createJourney);
                }
              },
              icon: const Icon(Icons.play_arrow_rounded, size: 20, color: Color(0xFF0C0D0E)),
              label: const Text(
                'Tham gia ngay',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0C0D0E),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF9FAFB),
                foregroundColor: const Color(0xFF0C0D0E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveJourneyCard(BuildContext context, SamanJourney journey) {
    final today = journey.todayRecord;
    final totalTasks = today?.tasks.length ?? 0;
    final completedTasks = today?.tasks.where((t) => t.isCompleted).length ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF16171B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF26282F),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF212328),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  journey.focus.label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF10B981),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF212328),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department, size: 14, color: Color(0xFFFFB95F)),
                    const SizedBox(width: 4),
                    Text(
                      'Chuỗi ${journey.currentStreak} ngày',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFB95F),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.stars_rounded, size: 16, color: Color(0xFFFFB95F)),
                  const SizedBox(width: 4),
                  Text(
                    '${journey.pointsEarned} điểm',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFFB95F),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ngày ${journey.completedDaysCount + 1} / ${journey.totalDays}',
                style: const TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF3F4F6),
                ),
              ),
              Text(
                'Nhiệm vụ: $completedTasks/$totalTasks',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94979E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: journey.progress,
              minHeight: 6,
              backgroundColor: const Color(0xFF212328),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton(
              onPressed: () {
                if (onViewJourneyTap != null) {
                  onViewJourneyTap!();
                } else {
                  Navigator.of(context).pushNamed(AppRoutes.myJourney);
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF3F4F6),
                side: const BorderSide(color: Color(0xFF26282F), width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Xem chi tiết hành trình',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 16, color: Color(0xFF94979E)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
