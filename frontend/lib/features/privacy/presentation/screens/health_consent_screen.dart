import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:health_ai_app/config/app_theme.dart';
import 'package:health_ai_app/features/privacy/data/privacy_service.dart';

/// Legal consent screen for VN 2026 health-data processing, third-party AI
/// analysis (Google Gemini), and medical disclaimer acknowledgement.
class HealthConsentScreen extends ConsumerStatefulWidget {
  const HealthConsentScreen({
    super.key,
    this.userId,
    this.onAccepted,
    this.readOnlyReview = false,
    this.initialStatus,
  });

  final String? userId;
  final VoidCallback? onAccepted;
  final bool readOnlyReview;
  final ConsentStatus? initialStatus;

  @override
  ConsumerState<HealthConsentScreen> createState() =>
      _HealthConsentScreenState();
}

class _HealthConsentScreenState extends ConsumerState<HealthConsentScreen> {
  bool _acceptedHealthData = false;
  bool _acceptedAiProcessing = false;
  bool _acknowledgedMedical = false;
  bool _isSubmitting = false;
  bool _isLoadingReview = false;
  String? _errorMessage;
  ConsentStatus? _reviewStatus;

  @override
  void initState() {
    super.initState();
    if (widget.readOnlyReview) {
      if (widget.initialStatus != null) {
        _applyReviewStatus(widget.initialStatus!);
      } else {
        _loadReviewStatus();
      }
    }
  }

  void _applyReviewStatus(ConsentStatus status) {
    _reviewStatus = status;
    _acceptedHealthData = status.acceptedHealthData || status.hasConsented;
    _acceptedAiProcessing = status.acceptedAiProcessing || status.hasConsented;
    _acknowledgedMedical =
        status.acknowledgedMedicalDisclaimer || status.hasConsented;
  }

  Future<void> _loadReviewStatus() async {
    setState(() {
      _isLoadingReview = true;
      _errorMessage = null;
    });
    try {
      final status = await ref
          .read(privacyServiceProvider)
          .fetchConsentStatus(userId: widget.userId);
      if (!mounted) return;
      setState(() {
        _applyReviewStatus(status);
        _isLoadingReview = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingReview = false;
        _errorMessage =
            'Không thể tải trạng thái đồng ý. Vui lòng kiểm tra kết nối và thử lại.';
      });
    }
  }

  bool get _canSubmit =>
      !_isSubmitting &&
      _acceptedHealthData &&
      _acceptedAiProcessing &&
      _acknowledgedMedical;

  Future<void> _handleSubmit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final locale = Localizations.maybeLocaleOf(context)?.languageCode ?? 'vi';
      await ref.read(privacyServiceProvider).submitConsent(
            userId: widget.userId ?? '',
            acceptedHealthData: _acceptedHealthData,
            acceptedAiProcessing: _acceptedAiProcessing,
            acknowledgedMedicalDisclaimer: _acknowledgedMedical,
            locale: locale,
          );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      widget.onAccepted?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage =
            'Không thể gửi xác nhận đồng ý. Vui lòng kiểm tra mạng và thử lại.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.samanColors;
    final textPrimary = palette.isDark ? Colors.white : palette.textPrimary;
    final textSecondary =
        palette.isDark ? const Color(0xFFA1A1AA) : palette.textSecondary;
    final cardBg = palette.isDark ? const Color(0xFF151518) : palette.surface;
    final cardBorder =
        palette.isDark ? const Color(0x14FFFFFF) : palette.border;

    return Scaffold(
      key: const Key('health_consent_screen'),
      backgroundColor: palette.isDark ? const Color(0xFF0A0A0C) : palette.canvas,
      appBar: widget.readOnlyReview
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.chevron_left_rounded, color: textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                'Chính sách dữ liệu sức khỏe & AI',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: _isLoadingReview
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: palette.accent.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.verified_user_outlined,
                                  color: palette.accent,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Quyền riêng tư & Dữ liệu sức khỏe (VN 2026)',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Phiên bản ${PrivacyService.requiredConsentVersion}',
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
                          const SizedBox(height: 12),
                          Text(
                            'Để bảo vệ quyền dữ liệu cá nhân nhạy cảm theo quy định pháp luật Việt Nam 2026, vui lòng đọc và xác nhận 3 nội dung dưới đây trước khi sử dụng Saman.',
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: textSecondary,
                            ),
                          ),
                          if (widget.readOnlyReview && _reviewStatus != null) ...[
                            const SizedBox(height: 12),
                            _ReviewStatusBanner(status: _reviewStatus!),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Column(
                        children: [
                          _ConsentCheckboxTile(
                            tileKey: const Key('consent_checkbox_health'),
                            value: _acceptedHealthData,
                            enabled: !widget.readOnlyReview && !_isSubmitting,
                            title: '1. Dữ liệu sức khỏe & tập luyện',
                            subtitle:
                                'Đồng ý cho Saman lưu trữ và xử lý dữ liệu cân nặng, bữa ăn, buổi tập và chỉ số CV nhằm cá nhân hóa lộ trình.',
                            onChanged: (val) => setState(
                              () => _acceptedHealthData = val ?? false,
                            ),
                          ),
                          Divider(height: 1, color: cardBorder),
                          _ConsentCheckboxTile(
                            tileKey: const Key('consent_checkbox_ai'),
                            value: _acceptedAiProcessing,
                            enabled: !widget.readOnlyReview && !_isSubmitting,
                            title: '2. Xử lý AI bên thứ ba (Google Gemini)',
                            subtitle:
                                'Đồng ý gửi ảnh món ăn và câu hỏi tới nhà cung cấp AI bên thứ ba (Google Gemini) để phân tích dinh dưỡng và kỹ thuật tập.',
                            onChanged: (val) => setState(
                              () => _acceptedAiProcessing = val ?? false,
                            ),
                          ),
                          Divider(height: 1, color: cardBorder),
                          _ConsentCheckboxTile(
                            tileKey: const Key('consent_checkbox_medical'),
                            value: _acknowledgedMedical,
                            enabled: !widget.readOnlyReview && !_isSubmitting,
                            title: '3. Miễn trừ trách nhiệm y tế',
                            subtitle:
                                'Xác nhận hiểu rõ Saman chỉ mang tính tham khảo thể hình/dinh dưỡng, không thay thế chẩn đoán hay tư vấn y tế chuyên khoa.',
                            onChanged: (val) => setState(
                              () => _acknowledgedMedical = val ?? false,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.redAccent.withOpacity(0.35),
                          ),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (!widget.readOnlyReview)
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          key: const Key('consent_submit_button'),
                          onPressed: _canSubmit ? _handleSubmit : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: palette.accent,
                            foregroundColor: palette.onAccent,
                            disabledBackgroundColor: palette.isDark
                                ? const Color(0xFF27272A)
                                : palette.border,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Đồng ý & Tiếp tục',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      )
                    else
                      Row(
                        children: [
                          if (_errorMessage != null) ...[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _loadReviewStatus,
                                child: const Text('Thử lại'),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: palette.accent,
                                foregroundColor: palette.onAccent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text('Đóng'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ConsentCheckboxTile extends StatelessWidget {
  const _ConsentCheckboxTile({
    required this.tileKey,
    required this.value,
    required this.enabled,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final Key tileKey;
  final bool value;
  final bool enabled;
  final String title;
  final String subtitle;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.samanColors;
    final textPrimary = palette.isDark ? Colors.white : palette.textPrimary;
    final textSecondary =
        palette.isDark ? const Color(0xFFA1A1AA) : palette.textSecondary;

    return CheckboxListTile(
      key: tileKey,
      value: value,
      onChanged: enabled ? onChanged : null,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: palette.accent,
      checkColor: palette.onAccent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ReviewStatusBanner extends StatelessWidget {
  const _ReviewStatusBanner({required this.status});

  final ConsentStatus status;

  @override
  Widget build(BuildContext context) {
    final accepted = status.hasConsented;
    final badgeColor = accepted ? const Color(0xFF22C55E) : Colors.amber;
    final acceptedAtText = status.acceptedAt != null
        ? 'Thời gian đồng ý: ${status.acceptedAt}'
        : 'Chưa ghi nhận thời gian đồng ý';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: badgeColor.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            accepted
                ? 'Trạng thái: Đã đồng ý (${status.consentVersion ?? status.requiredVersion})'
                : 'Trạng thái: Chưa đồng ý phiên bản ${status.requiredVersion}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            acceptedAtText,
            style: TextStyle(
              fontSize: 12,
              color: context.samanColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
