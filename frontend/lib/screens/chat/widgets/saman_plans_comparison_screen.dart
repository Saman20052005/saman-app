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
    final accountMembership = ref.watch(accountMembershipProvider);
    final activeTier = accountMembership.tier;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0D0E),
      appBar: AppBar(
        backgroundColor: SamanChatTokens.drawerBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: SamanChatTokens.textPrimary,
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
            const Text(
              'Các gói Saman',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: SamanChatTokens.textWhite,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF18191E),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF2B2E38)),
              ),
              child: const Text(
                'Bản xem trước',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF10B981),
                ),
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1.0),
          child: Divider(
            height: 1.0,
            thickness: 1.0,
            color: SamanChatTokens.borderSubtle,
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
                color: SamanChatTokens.surface,
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: SamanChatTokens.borderSubtle),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Color(0xFF10B981),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bản xem trước tính năng: Bảng so sánh quyền lợi minh họa, chưa yêu cầu phương thức thanh toán. Bạn có thể chọn bất kỳ gói nào để xem chi tiết.',
                      style: TextStyle(
                        fontSize: 12,
                        color: SamanChatTokens.textSecondary,
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
                child: _buildPlanCard(context, plan, activeTier),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(
    BuildContext context,
    SamanPlanPreviewItem plan,
    MembershipTier activeTier,
  ) {
    final isCurrent = (plan.tier == activeTier) ||
        (plan.tier == MembershipTier.free && activeTier == MembershipTier.free);

    final borderColor = plan.isHighlighted
        ? const Color(0xFF3B4254)
        : SamanChatTokens.borderSubtle;
    final cardBg =
        plan.isHighlighted ? const Color(0xFF16181F) : const Color(0xFF141518);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: plan.isHighlighted
            ? const [
                BoxShadow(
                  color: Color(0x59000000),
                  blurRadius: 18,
                  offset: Offset(0, 4),
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: SamanChatTokens.textWhite,
                    ),
                  ),
                  if (plan.tier == MembershipTier.pro) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: Color(0xFFFBBF24),
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
                    color: const Color(0xFF1B2620),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF164E35)),
                  ),
                  child: const Text(
                    'Gói hiện tại',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF10B981),
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
                    color: const Color(0xFF2B2312),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF52411E)),
                  ),
                  child: const Text(
                    'Khuyên dùng',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFBBF24),
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
                    color: const Color(0xFF1F222B),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF313647)),
                  ),
                  child: Text(
                    plan.badgeText,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFA5B4FC),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8.0),

          // Description
          Text(
            plan.description,
            style: const TextStyle(
              fontSize: 13,
              color: SamanChatTokens.textSecondary,
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
                  const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: Color(0xFFA1A1AA),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    b,
                    style: const TextStyle(
                      fontSize: 11,
                      color: SamanChatTokens.textMuted,
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
                      side: const BorderSide(color: Color(0xFF2B2E36)),
                      backgroundColor: const Color(0xFF1E2026),
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                    ),
                    child: const Text(
                      'Đang sử dụng',
                      style: TextStyle(
                        fontSize: 12,
                        color: SamanChatTokens.textMuted,
                      ),
                    ),
                  )
                : ElevatedButton(
                    onPressed: () => _handleSelectPlan(context, plan),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: plan.isHighlighted
                          ? Colors.white
                          : const Color(0xFF1C1F28),
                      foregroundColor: plan.isHighlighted
                          ? const Color(0xFF111215)
                          : Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0),
                        side: BorderSide(
                          color: plan.isHighlighted
                              ? Colors.transparent
                              : const Color(0xFF2D3242),
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
                                ? const Color(0xFF111215)
                                : Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: plan.isHighlighted
                              ? const Color(0xFF111215)
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
