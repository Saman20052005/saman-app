import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../features/membership/domain/models/membership_plan.dart';
import '../../../../features/membership/presentation/providers/membership_providers.dart';
import '../../../../features/membership/presentation/screens/plan_detail_screen.dart';
import '../tokens/saman_chat_tokens.dart';

/// Data model defining preview subscription plan tiers for Saman AI Chat.
class SamanPlanPreviewItem {
  final MembershipTier tier;
  final String title;
  final String badgeText;
  final String description;
  final List<String> bulletPoints;
  final bool isHighlighted;

  const SamanPlanPreviewItem({
    required this.tier,
    required this.title,
    required this.badgeText,
    required this.description,
    required this.bulletPoints,
    this.isHighlighted = false,
  });

  static const List<SamanPlanPreviewItem> defaultPlans = [
    SamanPlanPreviewItem(
      tier: MembershipTier.free,
      title: 'Saman Free',
      badgeText: 'Gói hiện tại',
      description:
          'Chat cơ bản — Tư vấn lịch tập, dinh dưỡng tổng quát và ghi chép nhật ký thể lực hàng ngày.',
      bulletPoints: ['Lịch sử 7 ngày', 'Nhắc nhở cơ bản'],
    ),
    SamanPlanPreviewItem(
      tier: MembershipTier.plus,
      title: 'Saman Plus',
      badgeText: 'Nâng cấp AI',
      description:
          'Phân tích ảnh món ăn nâng cao — Nhận diện chính xác khẩu phần, thành phần macro calo/đạm/chất béo từ ảnh chụp thực tế.',
      bulletPoints: [
        'Tất cả quyền lợi Free',
        'Vision AI món ăn',
        'Lịch sử 30 ngày',
      ],
    ),
    SamanPlanPreviewItem(
      tier: MembershipTier.pro,
      title: 'Saman Pro',
      badgeText: 'Khuyên dùng',
      description:
          'Quyền lợi Plus và hạn mức Workout-CV theo gói — Chấm điểm tư thế tập luyện qua video camera tự động, feedback form chuẩn.',
      bulletPoints: [
        'Tất cả quyền lợi Plus',
        'Workout-CV Computer Vision',
        'Phản hồi thời gian thực',
      ],
      isHighlighted: true,
    ),
    SamanPlanPreviewItem(
      tier: MembershipTier.ultra,
      title: 'Saman Ultra',
      badgeText: 'Chuyên sâu',
      description:
          'Hạn mức cao hơn và phân tích chuyên sâu hơn — Dự đoán xu hướng chấn thương, chu kỳ siêu bù (supercompensation) và huấn luyện viên 1-1.',
      bulletPoints: [
        'Không giới hạn token phân tích',
        'Mô hình sinh học chuyên sâu',
      ],
    ),
  ];
}

/// Screen showing vertical plan comparison cards for Saman AI (Frame 2).
class SamanPlansComparisonScreen extends ConsumerWidget {
  final VoidCallback? onBack;

  const SamanPlansComparisonScreen({
    super.key,
    this.onBack,
  });

  void _handleSelectPlan(BuildContext context, SamanPlanPreviewItem plan) {
    if (plan.tier.isFree) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(name: '/membership/detail/${plan.tier.name}'),
        builder: (_) => PlanDetailScreen(
          tier: plan.tier,
          onBackToMembership: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SamanChatTokens.of(context);
    final accountMembership = ref.watch(accountMembershipProvider);
    final activeTier = accountMembership.tier;

    return Scaffold(
      backgroundColor: t.canvas,
      appBar: AppBar(
        backgroundColor: t.drawerBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: t.textPrimary,
          ),
          tooltip: 'Quay lại',
          onPressed: () {
            if (onBack != null) {
              onBack!();
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Row(
          children: [
            Text(
              'Các gói Saman',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: t.textWhite,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: t.isDark ? const Color(0xFF18191E) : t.surfaceElevated,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: t.isDark ? const Color(0xFF2B2E38) : t.border,
                ),
              ),
              child: Text(
                'Bản xem trước',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: t.greenAccent,
                ),
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Divider(
            height: 1.0,
            thickness: 1.0,
            color: t.borderSubtle,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
          children: [
            // Preview Notice Banner
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: t.borderSubtle),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: t.greenAccent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bản xem trước tính năng: Bảng so sánh quyền lợi minh họa, chưa yêu cầu phương thức thanh toán. Bạn có thể chọn bất kỳ gói nào để xem chi tiết.',
                      style: TextStyle(
                        fontSize: 12,
                        color: t.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16.0),

            // Plan Cards
            for (final plan in SamanPlanPreviewItem.defaultPlans)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildPlanCard(context, t, plan, activeTier),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(
    BuildContext context,
    SamanChatPalette t,
    SamanPlanPreviewItem plan,
    MembershipTier activeTier,
  ) {
    final isCurrent = (plan.tier == activeTier) ||
        (plan.tier == MembershipTier.free && activeTier == MembershipTier.free);

    final borderColor = plan.isHighlighted
        ? (t.isDark ? const Color(0xFF3B4254) : t.greenAccent.withOpacity(0.45))
        : t.borderSubtle;
    final cardBg = plan.isHighlighted
        ? (t.isDark ? const Color(0xFF16181F) : t.surface)
        : (t.isDark ? const Color(0xFF141518) : t.surface);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: plan.isHighlighted
            ? [
                BoxShadow(
                  color: t.isDark
                      ? const Color(0x59000000)
                      : const Color(0x120F172A),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    plan.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: t.textWhite,
                    ),
                  ),
                  if (plan.tier == MembershipTier.pro) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: t.isDark ? const Color(0xFFFBBF24) : t.amberAccent,
                    ),
                  ],
                ],
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: t.isDark
                        ? const Color(0xFF1B2620)
                        : t.greenAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: t.isDark
                          ? const Color(0xFF164E35)
                          : t.greenAccent.withOpacity(0.35),
                    ),
                  ),
                  child: Text(
                    'Gói hiện tại',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: t.greenAccent,
                    ),
                  ),
                )
              else if (plan.isHighlighted)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: t.isDark
                        ? const Color(0xFF2B2312)
                        : t.amberAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: t.isDark
                          ? const Color(0xFF52411E)
                          : t.amberAccent.withOpacity(0.35),
                    ),
                  ),
                  child: Text(
                    'Khuyên dùng',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: t.isDark ? const Color(0xFFFBBF24) : t.amberAccent,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: t.isDark ? const Color(0xFF1F222B) : t.surfaceElevated,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: t.isDark ? const Color(0xFF313647) : t.border,
                    ),
                  ),
                  child: Text(
                    plan.badgeText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: t.isDark ? const Color(0xFFA5B4FC) : t.textSecondary,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8.0),

          // Description
          Text(
            plan.description,
            style: TextStyle(
              fontSize: 13,
              color: t.textSecondary,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 10.0),

          // Bullets
          Wrap(
            spacing: 12.0,
            runSpacing: 4.0,
            children: plan.bulletPoints.map((b) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: t.isDark ? const Color(0xFFA1A1AA) : t.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    b,
                    style: TextStyle(
                      fontSize: 11,
                      color: t.textMuted,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),

          const SizedBox(height: 14.0),

          // Action CTA
          SizedBox(
            width: double.infinity,
            child: isCurrent
                ? OutlinedButton(
                    onPressed: null,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: t.isDark ? const Color(0xFF2B2E36) : t.border,
                      ),
                      backgroundColor: t.isDark
                          ? const Color(0xFF1E2026)
                          : t.surfaceElevated,
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                    ),
                    child: Text(
                      'Đang sử dụng',
                      style: TextStyle(
                        fontSize: 12,
                        color: t.textMuted,
                      ),
                    ),
                  )
                : ElevatedButton(
                    onPressed: () => _handleSelectPlan(context, plan),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: plan.isHighlighted
                          ? (t.isDark ? Colors.white : t.greenAccent)
                          : (t.isDark
                              ? const Color(0xFF1C1F28)
                              : const Color(0xFF0F172A)),
                      foregroundColor: plan.isHighlighted
                          ? (t.isDark ? const Color(0xFF111215) : Colors.white)
                          : Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0),
                        side: BorderSide(
                          color: plan.isHighlighted
                              ? Colors.transparent
                              : (t.isDark
                                  ? const Color(0xFF2D3242)
                                  : Colors.transparent),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Xem chi tiết gói',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: plan.isHighlighted
                                ? (t.isDark
                                    ? const Color(0xFF111215)
                                    : Colors.white)
                                : Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: plan.isHighlighted
                              ? (t.isDark
                                  ? const Color(0xFF111215)
                                  : Colors.white)
                              : Colors.white,
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
