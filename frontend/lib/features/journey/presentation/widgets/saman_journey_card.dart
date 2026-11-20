import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/routes.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
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
    final tokens = SamanHomeTokens.of(context);
    final isDark = tokens.isDark;
    final badgeAccent = isDark ? const Color(0xFF10B981) : tokens.greenAccent;
    final badgeBg = isDark ? const Color(0x2610B981) : tokens.greenBadgeBg;
    final sparkleColor = isDark ? const Color(0xFFFFB95F) : tokens.carbsAmber;
    final titleColor = isDark ? const Color(0xFFF3F4F6) : tokens.textPrimary;
    final subtitleColor =
        isDark ? const Color(0xFF94979E) : tokens.textSecondary;
    final ctaBg = isDark ? const Color(0xFFF9FAFB) : const Color(0xFF059669);
    final ctaFg = isDark ? const Color(0xFF0C0D0E) : Colors.white;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tokens.border,
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
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.flag_rounded,
                      size: 13,
                      color: badgeAccent,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'HÀNH TRÌNH SAMAN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: badgeAccent,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Icon(
                Icons.auto_awesome,
                size: 16,
                color: sparkleColor,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Khởi đầu thói quen & Bứt phá mục tiêu',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: titleColor,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Cam kết lộ trình 7, 14, 21 hoặc 30 ngày. Tích lũy điểm thưởng mỗi ngày để đổi đặc quyền AI.',
            style: TextStyle(
              fontSize: 13,
              color: subtitleColor,
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
              icon: Icon(Icons.play_arrow_rounded, size: 20, color: ctaFg),
              label: Text(
                'Tham gia ngay',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ctaFg,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: ctaBg,
                foregroundColor: ctaFg,
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
    final tokens = SamanHomeTokens.of(context);
    final isDark = tokens.isDark;
    final focusAccent = isDark ? const Color(0xFF54DFAC) : tokens.greenAccent;
    final amberAccent = isDark ? const Color(0xFFFFB95F) : tokens.carbsAmber;
    final titleColor = isDark ? const Color(0xFFF3F4F6) : tokens.textPrimary;

    final today = journey.todayRecord;
    final totalTasks = today?.tasks.length ?? 0;
    final completedTasks = today?.tasks.where((t) => t.isCompleted).length ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tokens.border,
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
                  color: tokens.secondarySurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.border, width: 0.8),
                ),
                child: Text(
                  journey.focus.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: focusAccent,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: tokens.secondarySurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.border, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_fire_department, size: 14, color: amberAccent),
                    const SizedBox(width: 4),
                    Text(
                      'Chuỗi ${journey.currentStreak} ngày',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: amberAccent,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(Icons.stars_rounded, size: 16, color: amberAccent),
                  const SizedBox(width: 4),
                  Text(
                    '${journey.pointsEarned} điểm',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: amberAccent,
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
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
              Text(
                'Nhiệm vụ: $completedTasks/$totalTasks',
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.textSecondary,
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
              backgroundColor: tokens.progressTrack,
              valueColor: AlwaysStoppedAnimation<Color>(focusAccent),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              onPressed: () {
                if (onViewJourneyTap != null) {
                  onViewJourneyTap!();
                } else {
                  Navigator.of(context).pushNamed(AppRoutes.myJourney);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.secondarySurface,
                foregroundColor: tokens.textSecondary,
                elevation: 0,
                side: BorderSide(color: tokens.border, width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Xem chi tiết hành trình',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: tokens.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 16, color: tokens.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
