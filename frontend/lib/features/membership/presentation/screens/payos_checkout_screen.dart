import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../config/api_config.dart';
import '../../../../services/api_client.dart';
import '../../domain/models/membership_plan.dart';
import '../providers/membership_providers.dart';
import '../tokens/membership_tokens.dart';
import '../widgets/membership_app_bar.dart';
import '../widgets/primary_membership_button.dart';
import 'membership_overview_screen.dart';

class PayosOrderData {
  final int orderCode;
  final int amount;
  final String currency;
  final String description;
  final String qrCode;
  final String checkoutUrl;
  final String? bin;
  final String? accountNumber;
  final String? accountName;
  final String status;

  const PayosOrderData({
    required this.orderCode,
    required this.amount,
    required this.currency,
    required this.description,
    required this.qrCode,
    required this.checkoutUrl,
    this.bin,
    this.accountNumber,
    this.accountName,
    this.status = 'pending',
  });

  factory PayosOrderData.fromJson(Map<String, dynamic> json) {
    return PayosOrderData(
      orderCode: (json['order_code'] as num).toInt(),
      amount: (json['amount'] as num).toInt(),
      currency: (json['currency'] as String?) ?? 'VND',
      description: (json['description'] as String?) ?? '',
      qrCode: (json['qr_code'] as String?) ?? '',
      checkoutUrl: (json['checkout_url'] as String?) ?? '',
      bin: json['bin'] as String?,
      accountNumber: json['account_number'] as String?,
      accountName: json['account_name'] as String?,
      status: (json['status'] as String?) ?? 'pending',
    );
  }
}

class PayosCheckoutScreen extends ConsumerStatefulWidget {
  final MembershipTier tier;
  final BillingPeriod? billingPeriod;
  final bool enableAutoPolling;
  final VoidCallback? onSuccessBack;

  const PayosCheckoutScreen({
    super.key,
    required this.tier,
    this.billingPeriod,
    this.enableAutoPolling = true,
    this.onSuccessBack,
  });

  @override
  ConsumerState<PayosCheckoutScreen> createState() =>
      _PayosCheckoutScreenState();
}

class _PayosCheckoutScreenState extends ConsumerState<PayosCheckoutScreen> {
  bool _isLoading = true;
  bool _isCheckingStatus = false;
  bool _isPaid = false;
  String? _errorMessage;
  PayosOrderData? _order;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _createQrOrder();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  BillingPeriod get _effectivePeriod =>
      widget.billingPeriod ?? ref.read(billingPeriodProvider);

  String get _planId => 'plan_${widget.tier.name}';

  Map<String, dynamic> _decodeMap(dynamic raw) {
    if (raw is String) {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {};
  }

  Future<void> _createQrOrder() async {
    _pollTimer?.cancel();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isPaid = false;
    });

    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post(
        '${ApiConfig.baseUrl}/api/payments/create-qr',
        data: {
          'plan_id': _planId,
          'billing_period': _effectivePeriod.name,
        },
      );

      if (!mounted) return;
      final data = _decodeMap(resp.data);
      final order = PayosOrderData.fromJson(data);
      setState(() {
        _order = order;
        _isLoading = false;
      });
      _startPolling();
    } on DioException catch (e) {
      if (!mounted) return;
      final statusCode = e.response?.statusCode;
      String msg = 'Không thể tạo mã thanh toán VietQR. Vui lòng thử lại.';
      if (statusCode == 401) {
        msg = 'Vui lòng đăng nhập trước khi thực hiện thanh toán.';
      } else if (statusCode == 503) {
        msg = 'Cổng thanh toán PayOS hiện chưa sẵn sàng. Vui lòng thử lại sau.';
      }
      setState(() {
        _isLoading = false;
        _errorMessage = msg;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Đã xảy ra lỗi kết nối khi khởi tạo đơn thanh toán.';
      });
    }
  }

  void _startPolling() {
    if (!widget.enableAutoPolling) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkOrderStatus(silent: true);
    });
  }

  Future<void> _checkOrderStatus({bool silent = false}) async {
    final order = _order;
    if (order == null || _isPaid || _isCheckingStatus) return;

    if (!silent) {
      setState(() => _isCheckingStatus = true);
    } else {
      _isCheckingStatus = true;
    }

    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get(
        '${ApiConfig.baseUrl}/api/payments/orders/${order.orderCode}',
      );
      if (!mounted) return;
      final data = _decodeMap(resp.data);
      final status = (data['status'] as String?)?.toLowerCase() ?? 'pending';

      if (status == 'paid') {
        _pollTimer?.cancel();
        final accountId = ref.read(accountMembershipProvider).accountId;
        await ref
            .read(accountMembershipProvider.notifier)
            .loadMembership(accountId: accountId);
        if (!mounted) return;
        setState(() {
          _isPaid = true;
          _isCheckingStatus = false;
        });
        return;
      }

      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Giao dịch đang chờ xác nhận. Vui lòng hoàn tất chuyển khoản VietQR.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể kiểm tra trạng thái đơn hàng lúc này.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingStatus = false);
      } else {
        _isCheckingStatus = false;
      }
    }
  }

  Future<void> _openCheckoutUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyText(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã sao chép $label')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = MembershipTokens.of(context);
    final plan = ref.watch(membershipPlanProvider(widget.tier));
    final period = _effectivePeriod;

    return Scaffold(
      backgroundColor: t.canvas,
      appBar: MembershipAppBar(
        title: 'Thanh toán VietQR · ${plan.name}',
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? _buildLoading(t)
            : _errorMessage != null
                ? _buildError(t)
                : _isPaid
                    ? _buildSuccess(t, plan, period)
                    : _buildCheckoutBody(t, plan, period),
      ),
    );
  }

  Widget _buildLoading(MembershipPalette t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: t.accent),
            const SizedBox(height: 16),
            Text(
              'Đang tạo mã thanh toán VietQR...',
              style: t.body(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: t.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(MembershipPalette t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
            border: Border.all(color: t.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.error_outline, size: 40, color: t.textMuted),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Không thể tạo mã thanh toán.',
                style: t.body(fontSize: 14, color: t.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              PrimaryMembershipButton(
                text: 'Thử lại',
                icon: Icons.refresh,
                onPressed: _createQrOrder,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(
    MembershipPalette t,
    MembershipPlan plan,
    BillingPeriod period,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
              border: Border.all(color: t.accentBorder, width: 1.5),
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: t.accentBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: t.accentBorder),
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 36,
                    color: t.accent,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Nâng cấp thành công!',
                  style: t.headline(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Gói ${plan.name} (${period.isMonthly ? 'Theo tháng' : 'Theo năm'}) đã được kích hoạt cho tài khoản của bạn.',
                  style: t.body(
                    fontSize: 14,
                    color: t.textMuted,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_order != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: t.surfaceHigh,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: t.border),
                    ),
                    child: Text(
                      'Mã đơn #${_order!.orderCode} · ${MembershipPlan.formatVnd(_order!.amount)}',
                      style: t.mono(
                        fontSize: 12,
                        color: t.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          PrimaryMembershipButton(
            text: 'Quay lại ứng dụng',
            icon: Icons.arrow_back,
            onPressed: () {
              if (widget.onSuccessBack != null) {
                widget.onSuccessBack!();
              } else {
                safePopOrNavigateToMembership(context);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutBody(
    MembershipPalette t,
    MembershipPlan plan,
    BillingPeriod period,
  ) {
    final order = _order!;
    final formattedAmount = MembershipPlan.formatVnd(order.amount);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: MembershipTokens.screenGutter,
        vertical: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Order summary header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
              border: Border.all(color: t.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gói Saman ${plan.name}',
                        style: t.headline(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${period.isMonthly ? 'Thanh toán hàng tháng' : 'Thanh toán hàng năm'} · #${order.orderCode}',
                        style: t.body(fontSize: 12, color: t.textMuted),
                      ),
                    ],
                  ),
                ),
                Text(
                  formattedAmount,
                  style: t.mono(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: t.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // VietQR Code card (always white QR frame for reliable camera scan in Light & Dark mode)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
              border: Border.all(color: t.border),
            ),
            child: Column(
              children: [
                Text(
                  'Quét mã VietQR bằng ứng dụng Ngân hàng',
                  style: t.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.border),
                  ),
                  child: order.qrCode.isNotEmpty
                      ? QrImageView(
                          data: order.qrCode,
                          version: QrVersions.auto,
                          size: 210,
                          backgroundColor: Colors.white,
                        )
                      : const SizedBox(
                          width: 210,
                          height: 210,
                          child: Center(
                            child: Icon(Icons.qr_code_2, size: 96),
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Đang chờ thanh toán tự động...',
                      style: t.body(fontSize: 12, color: t.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Bank transfer info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(MembershipTokens.cardRadius),
              border: Border.all(color: t.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'THÔNG TIN CHUYỂN KHOẢN',
                  style: t.mono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: t.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  t,
                  label: 'Số tiền',
                  value: formattedAmount,
                  copyValue: order.amount.toString(),
                ),
                if (order.bin != null && order.bin!.isNotEmpty) ...[
                  Divider(color: t.border, height: 20),
                  _buildInfoRow(t, label: 'Mã ngân hàng (BIN)', value: order.bin!),
                ],
                if (order.accountNumber != null &&
                    order.accountNumber!.isNotEmpty) ...[
                  Divider(color: t.border, height: 20),
                  _buildInfoRow(
                    t,
                    label: 'Số tài khoản',
                    value: order.accountNumber!,
                    copyValue: order.accountNumber!,
                  ),
                ],
                if (order.accountName != null &&
                    order.accountName!.isNotEmpty) ...[
                  Divider(color: t.border, height: 20),
                  _buildInfoRow(
                    t,
                    label: 'Chủ tài khoản',
                    value: order.accountName!,
                  ),
                ],
                Divider(color: t.border, height: 20),
                _buildInfoRow(
                  t,
                  label: 'Nội dung CK',
                  value: order.description,
                  copyValue: order.description,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            height: MembershipTokens.primaryCtaMinHeight,
            child: ElevatedButton(
              onPressed: _isCheckingStatus ? null : () => _checkOrderStatus(),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: t.primaryCtaBg,
                foregroundColor: t.primaryCtaText,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(MembershipTokens.buttonRadius),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _isCheckingStatus
                          ? 'Đang kiểm tra...'
                          : 'Kiểm tra trạng thái thanh toán',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.primaryCtaText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.verified_outlined, size: 18, color: t.primaryCtaText),
                ],
              ),
            ),
          ),
          if (order.checkoutUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: MembershipTokens.minTouchTarget,
              child: OutlinedButton.icon(
                onPressed: () => _openCheckoutUrl(order.checkoutUrl),
                icon: Icon(Icons.open_in_new, size: 18, color: t.textPrimary),
                label: Text(
                  'Mở cổng thanh toán PayOS',
                  style: t.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: t.borderStrong),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(MembershipTokens.buttonRadius),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    MembershipPalette t, {
    required String label,
    required String value,
    String? copyValue,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: t.body(fontSize: 12, color: t.textMuted),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: t.mono(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: t.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (copyValue != null)
          TextButton.icon(
            onPressed: () => _copyText(label, copyValue),
            icon: Icon(Icons.copy, size: 15, color: t.accent),
            label: Text(
              'Copy',
              style: t.mono(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.accent,
              ),
            ),
          ),
      ],
    );
  }
}
