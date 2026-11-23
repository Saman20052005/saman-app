import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/routes.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';
import '../../domain/models/journey_models.dart';
import '../providers/journey_providers.dart';
import '../../../../widgets/saman_feedback_snackbar.dart';

class WalletRewardsScreen extends ConsumerStatefulWidget {
  const WalletRewardsScreen({super.key});

  @override
  ConsumerState<WalletRewardsScreen> createState() => _WalletRewardsScreenState();
}

class _WalletRewardsScreenState extends ConsumerState<WalletRewardsScreen> {
  RewardItem? _selectedReward;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(walletControllerProvider.notifier).loadWalletData();
    });
  }

  void _showConfirmBottomSheet(BuildContext context, RewardItem reward, WalletState walletState) {
    final tokens = SamanHomeTokens.of(context);
    final sheetBg =
        tokens.isDark ? const Color(0xFF16171B) : tokens.cardSurface;
    final borderColor =
        tokens.isDark ? const Color(0xFF26282F) : tokens.border;
    final textPrimary =
        tokens.isDark ? const Color(0xFFF3F4F6) : tokens.textPrimary;
    final textSecondary =
        tokens.isDark ? const Color(0xFF94979E) : tokens.textSecondary;
    final summaryBg =
        tokens.isDark ? const Color(0xFF0C0D0E) : tokens.secondarySurface;
    final cyanColor =
        tokens.isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    final ctaBg =
        tokens.isDark ? const Color(0xFFF9FAFB) : const Color(0xFF059669);
    final ctaFg =
        tokens.isDark ? const Color(0xFF0C0D0E) : Colors.white;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final newPoints = walletState.balance - reward.pointsCost;
        final newCredits = walletState.aiCredits + reward.aiCredits;

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: borderColor, width: 1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Đổi ${reward.title}?',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Sử dụng ${reward.pointsCost} điểm',
                style: TextStyle(
                  fontSize: 13,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 18),

              // Summary Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: summaryBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1),
                ),
                alignment: Alignment.center,
                child: Text.rich(
                  TextSpan(
                    text: 'Sau khi đổi: ',
                    style: TextStyle(fontSize: 13, color: textSecondary),
                    children: [
                      TextSpan(
                        text: '$newPoints điểm',
                        style: TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
                      ),
                      const TextSpan(text: ' · '),
                      TextSpan(
                        text: '$newCredits lượt AI',
                        style: TextStyle(fontWeight: FontWeight.w600, color: cyanColor),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final success = await ref
                        .read(walletControllerProvider.notifier)
                        .redeemReward(reward);
                    if (!mounted) return;
                    if (success) {
                      SamanFeedbackSnackBar.show(
                        context,
                        message: 'Đã đổi thành công ${reward.title}.',
                        type: FeedbackType.success,
                      );
                    } else {
                      final err = ref.read(walletControllerProvider).errorMessage ?? 'Đổi quà thất bại.';
                      SamanFeedbackSnackBar.show(
                        context,
                        message: err,
                        type: FeedbackType.error,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ctaBg,
                    foregroundColor: ctaFg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Xác nhận đổi', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Để sau', style: TextStyle(color: textSecondary, fontSize: 13)),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SamanHomeTokens.of(context);
    final scaffoldBg =
        tokens.isDark ? const Color(0xFF0C0D0E) : tokens.canvas;
    final cardBg =
        tokens.isDark ? const Color(0xFF16171B) : tokens.cardSurface;
    final borderColor =
        tokens.isDark ? const Color(0xFF26282F) : tokens.border;
    final textPrimary =
        tokens.isDark ? const Color(0xFFF3F4F6) : tokens.textPrimary;
    final textSecondary =
        tokens.isDark ? const Color(0xFF94979E) : tokens.textSecondary;
    final emerald =
        tokens.isDark ? const Color(0xFF10B981) : tokens.greenAccent;
    final cyanColor =
        tokens.isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    final selectedOfferBg =
        tokens.isDark ? const Color(0x0810B981) : const Color(0x0D059669);
    final unselectedRadioBorder =
        tokens.isDark ? const Color(0xFF383A42) : tokens.borderHigh;
    final ctaBg =
        tokens.isDark ? const Color(0xFFF9FAFB) : const Color(0xFF059669);
    final ctaFg =
        tokens.isDark ? const Color(0xFF0C0D0E) : Colors.white;
    final ctaDisabledBg =
        tokens.isDark ? const Color(0xFF212328) : tokens.secondarySurface;
    final ctaDisabledFg =
        tokens.isDark ? const Color(0xFF94979E) : tokens.textMuted;

    final walletState = ref.watch(walletControllerProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // Pick first available reward as default if not selected
    if (_selectedReward == null && walletState.catalog.isNotEmpty) {
      _selectedReward = walletState.catalog.firstWhere(
        (r) => r.isAvailable,
        orElse: () => walletState.catalog.first,
      );
    }

    final selected = _selectedReward;
    final canRedeem = selected != null &&
        selected.isAvailable &&
        walletState.balance >= selected.pointsCost &&
        !walletState.isRedeeming;

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // TOP HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: textSecondary),
                        onPressed: () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          } else {
                            Navigator.of(context).pushReplacementNamed(AppRoutes.main);
                          }
                        },
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Ví điểm & Lượt AI',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.info_outline_rounded, color: textSecondary, size: 20),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: cardBg,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: Text('Thông tin đổi điểm', style: TextStyle(color: textPrimary, fontSize: 16)),
                          content: Text(
                            'Điểm Saman Points (SP) được tích lũy khi bạn hoàn thành đầy đủ nhiệm vụ mỗi ngày (+20 điểm/ngày). '
                            'Khi đổi điểm lấy lượt AI, hệ thống sẽ cộng trực tiếp lượt bonus vào hạn mức AI hôm nay của bạn (Core 3, Pro 3, Food Vision).',
                            style: TextStyle(color: textSecondary, fontSize: 13, height: 1.4),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text('Đã hiểu', style: TextStyle(color: emerald)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // MAIN SCROLLABLE CONTENT
            Expanded(
              child: RefreshIndicator(
                color: emerald,
                backgroundColor: cardBg,
                onRefresh: () => ref.read(walletControllerProvider.notifier).loadWalletData(),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),

                      // 1. DUAL BALANCE CARD
                      Column(
                        children: [
                          Text(
                            'Điểm tích lũy',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${walletState.balance}',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                              letterSpacing: -1.0,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: borderColor, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.smart_toy_rounded, color: cyanColor, size: 15),
                                const SizedBox(width: 6),
                                Text(
                                  '${walletState.aiCredits} lượt AI',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'khả dụng',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // 2. EXCHANGE OFFERS SECTION
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Đổi lượt AI',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Dùng điểm để đổi lượt phân tích AI.',
                            style: TextStyle(fontSize: 12, color: textSecondary),
                          ),
                          const SizedBox(height: 12),

                          // Offers List
                          Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderColor, width: 1),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: walletState.catalog.length,
                                separatorBuilder: (_, __) => Divider(color: borderColor, height: 1),
                                itemBuilder: (context, index) {
                                  final item = walletState.catalog[index];
                                  final isSelected = selected?.id == item.id;
                                  final hasEnoughPoints = walletState.balance >= item.pointsCost;
                                  final isAvailable = item.isAvailable;

                                  return InkWell(
                                    onTap: isAvailable
                                        ? () => setState(() => _selectedReward = item)
                                        : () {
                                            SamanFeedbackSnackBar.show(
                                              context,
                                              message: '${item.title}: ${item.statusNote}',
                                              type: FeedbackType.info,
                                              duration: const Duration(seconds: 2),
                                            );
                                          },
                                    child: Opacity(
                                      opacity: isAvailable ? 1.0 : 0.45,
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        color: isSelected && isAvailable
                                            ? selectedOfferBg
                                            : Colors.transparent,
                                        child: Row(
                                          children: [
                                            // Radio Indicator
                                            Container(
                                              width: 20,
                                              height: 20,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isSelected && isAvailable
                                                      ? emerald
                                                      : unselectedRadioBorder,
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: isSelected && isAvailable
                                                  ? Center(
                                                      child: Container(
                                                        width: 10,
                                                        height: 10,
                                                        decoration: BoxDecoration(
                                                          shape: BoxShape.circle,
                                                          color: emerald,
                                                        ),
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(width: 14),

                                            // Title & Description
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    item.title,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w500,
                                                      color: textPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    !isAvailable
                                                        ? item.statusNote
                                                        : (!hasEnoughPoints
                                                            ? 'Còn thiếu ${item.pointsCost - walletState.balance} điểm để đổi gói này'
                                                            : item.description),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Price
                                            Text(
                                              '${item.pointsCost} điểm',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: hasEnoughPoints && isAvailable
                                                    ? textPrimary
                                                    : textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Đổi điểm Saman Points để cộng trực tiếp lượt bonus vào hạn mức AI hôm nay (Core 3, Pro 3, Food Vision).',
                            style: TextStyle(fontSize: 11, color: textSecondary, height: 1.4),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // 3. RECENT ACTIVITY LEDGER
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lịch sử giao dịch',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),

                          if (walletState.transactions.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor, width: 1),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.receipt_long_rounded, color: textSecondary, size: 28),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Chưa có giao dịch nào',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Điểm thưởng và lịch sử đổi lượt AI sẽ xuất hiện tại đây.',
                                    style: TextStyle(fontSize: 12, color: textSecondary),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor, width: 1),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: walletState.transactions.length,
                                  separatorBuilder: (_, __) => Divider(color: borderColor, height: 1),
                                  itemBuilder: (context, index) {
                                    final tx = walletState.transactions[index];
                                    final isPositive = tx.amount > 0;

                                    return Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  tx.description,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                    color: textPrimary,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  tx.createdAt.split('T').first,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            isPositive ? '+${tx.amount} điểm' : '${tx.amount} điểm',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: isPositive ? emerald : textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 100), // Spacing for sticky CTA
                    ],
                  ),
                ),
              ),
            ),

            // STICKY BOTTOM PRIMARY ACTION
            Container(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottomInset),
              decoration: BoxDecoration(
                color: scaffoldBg,
                border: Border(top: BorderSide(color: borderColor, width: 1)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: canRedeem
                      ? () => _showConfirmBottomSheet(context, selected, walletState)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ctaBg,
                    foregroundColor: ctaFg,
                    disabledBackgroundColor: ctaDisabledBg,
                    disabledForegroundColor: ctaDisabledFg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: walletState.isRedeeming
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: ctaFg),
                        )
                      : Text(
                          selected != null && selected.isAvailable
                              ? 'Đổi ${selected.title} với ${selected.pointsCost} điểm'
                              : 'Chọn gói khả dụng để đổi',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
