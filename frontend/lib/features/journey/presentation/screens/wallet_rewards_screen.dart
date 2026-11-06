import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/routes.dart';
import '../../domain/models/journey_models.dart';
import '../providers/journey_providers.dart';

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
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final newPoints = walletState.balance - reward.pointsCost;
        final newCredits = walletState.aiCredits + reward.aiCredits;

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: const BoxDecoration(
            color: Color(0xFF16171B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: Color(0xFF26282F), width: 1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF26282F),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Đổi ${reward.title}?',
                style: const TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF3F4F6),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Sử dụng ${reward.pointsCost} điểm',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF94979E),
                ),
              ),
              const SizedBox(height: 18),

              // Summary Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C0D0E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF26282F), width: 1),
                ),
                alignment: Alignment.center,
                child: Text.rich(
                  TextSpan(
                    text: 'Sau khi đổi: ',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF94979E)),
                    children: [
                      TextSpan(
                        text: '$newPoints điểm',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFF3F4F6)),
                      ),
                      const TextSpan(text: ' · '),
                      TextSpan(
                        text: '$newCredits lượt AI',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF38BDF8)),
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
                      messenger.showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF212328),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0x4D10B981)),
                          ),
                          content: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Đã đổi thành công ${reward.title}.',
                                  style: const TextStyle(color: Color(0xFFF3F4F6), fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    } else {
                      final err = ref.read(walletControllerProvider).errorMessage ?? 'Đổi quà thất bại.';
                      messenger.showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF212328),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0x4DEF4444)),
                          ),
                          content: Text(err, style: const TextStyle(color: Color(0xFFF3F4F6))),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF9FAFB),
                    foregroundColor: const Color(0xFF0C0D0E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Xác nhận đổi', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Để sau', style: TextStyle(color: Color(0xFF94979E), fontSize: 13)),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
      backgroundColor: const Color(0xFF0C0D0E),
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
                        icon: const Icon(Icons.arrow_back, color: Color(0xFF94979E)),
                        onPressed: () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          } else {
                            Navigator.of(context).pushReplacementNamed(AppRoutes.main);
                          }
                        },
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Ví điểm & Lượt AI',
                        style: TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF3F4F6),
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.info_outline_rounded, color: Color(0xFF94979E), size: 20),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: const Color(0xFF16171B),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text('Thông tin đổi điểm', style: TextStyle(color: Color(0xFFF3F4F6), fontSize: 16)),
                          content: const Text(
                            'Điểm Saman Points (SP) được tích lũy khi bạn hoàn thành đầy đủ nhiệm vụ mỗi ngày (+20 điểm/ngày). '
                            'Hạ tầng quy đổi lượt AI đang trong giai đoạn kết nối và sẽ mở trong phiên bản tiếp theo.',
                            style: TextStyle(color: Color(0xFF94979E), fontSize: 13, height: 1.4),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Đã hiểu', style: TextStyle(color: Color(0xFF10B981))),
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
                color: const Color(0xFF10B981),
                backgroundColor: const Color(0xFF16171B),
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
                          const Text(
                            'Điểm tích lũy',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF94979E),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${walletState.balance}',
                            style: const TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF3F4F6),
                              letterSpacing: -1.0,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16171B),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF26282F), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.smart_toy_rounded, color: Color(0xFF38BDF8), size: 15),
                                const SizedBox(width: 6),
                                Text(
                                  '${walletState.aiCredits} lượt AI',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFF3F4F6),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'khả dụng',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94979E),
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
                          const Text(
                            'Đổi lượt AI',
                            style: TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFF3F4F6),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Dùng điểm để đổi lượt phân tích AI.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF94979E)),
                          ),
                          const SizedBox(height: 12),

                          // Offers List
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF16171B),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF26282F), width: 1),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: walletState.catalog.length,
                                separatorBuilder: (_, __) => const Divider(color: Color(0xFF26282F), height: 1),
                                itemBuilder: (context, index) {
                                  final item = walletState.catalog[index];
                                  final isSelected = selected?.id == item.id;
                                  final hasEnoughPoints = walletState.balance >= item.pointsCost;
                                  final isAvailable = item.isAvailable;

                                  return InkWell(
                                    onTap: isAvailable
                                        ? () => setState(() => _selectedReward = item)
                                        : () {
                                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                backgroundColor: const Color(0xFF212328),
                                                duration: const Duration(seconds: 2),
                                                content: Text(
                                                  '${item.title}: Gói đổi sắp ra mắt (đang kết nối hạ tầng AI quota)',
                                                  style: const TextStyle(fontSize: 13, color: Color(0xFFF3F4F6)),
                                                ),
                                              ),
                                            );
                                          },
                                    child: Opacity(
                                      opacity: isAvailable ? 1.0 : 0.45,
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        color: isSelected && isAvailable
                                            ? const Color(0x0810B981)
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
                                                      ? const Color(0xFF10B981)
                                                      : const Color(0xFF383A42),
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: isSelected && isAvailable
                                                  ? Center(
                                                      child: Container(
                                                        width: 10,
                                                        height: 10,
                                                        decoration: const BoxDecoration(
                                                          shape: BoxShape.circle,
                                                          color: Color(0xFF10B981),
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
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w500,
                                                      color: Color(0xFFF3F4F6),
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
                                                      color: !isAvailable || !hasEnoughPoints
                                                          ? const Color(0xFF94979E)
                                                          : const Color(0xFF94979E),
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
                                                    ? const Color(0xFFF3F4F6)
                                                    : const Color(0xFF94979E),
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
                          const Text(
                            'Điểm thưởng Saman Points ghi nhận kỷ luật rèn luyện của bạn. Tính năng quy đổi lượt AI đang trong quá trình kết nối hạ tầng.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF94979E), height: 1.4),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // 3. RECENT ACTIVITY LEDGER
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Lịch sử giao dịch',
                            style: TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFF3F4F6),
                            ),
                          ),
                          const SizedBox(height: 12),

                          if (walletState.transactions.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16171B),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFF26282F), width: 1),
                              ),
                              child: const Column(
                                children: [
                                  Icon(Icons.receipt_long_rounded, color: Color(0xFF94979E), size: 28),
                                  SizedBox(height: 8),
                                  Text(
                                    'Chưa có giao dịch nào',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFFF3F4F6),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Điểm thưởng và lịch sử đổi lượt AI sẽ xuất hiện tại đây.',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF94979E)),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF16171B),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFF26282F), width: 1),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: walletState.transactions.length,
                                  separatorBuilder: (_, __) => const Divider(color: Color(0xFF26282F), height: 1),
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
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                    color: Color(0xFFF3F4F6),
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  tx.createdAt.split('T').first,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF94979E),
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
                                              color: isPositive
                                                  ? const Color(0xFF10B981)
                                                  : const Color(0xFFF3F4F6),
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
              decoration: const BoxDecoration(
                color: Color(0xFF0C0D0E),
                border: Border(top: BorderSide(color: Color(0xFF26282F), width: 1)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: canRedeem
                      ? () => _showConfirmBottomSheet(context, selected, walletState)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF9FAFB),
                    foregroundColor: const Color(0xFF0C0D0E),
                    disabledBackgroundColor: const Color(0xFF212328),
                    disabledForegroundColor: const Color(0xFF94979E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: walletState.isRedeeming
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0C0D0E)),
                        )
                      : Text(
                          selected != null && selected.isAvailable
                              ? 'Đổi ${selected.title} với ${selected.pointsCost} điểm'
                              : 'Các gói đổi sắp ra mắt',
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
