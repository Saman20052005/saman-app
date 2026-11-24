import 'package:flutter/material.dart';

import '../../../../presentation/tokens/saman_workout_tokens.dart';
import '../../domain/services/cv_hardware_radar_service.dart';

/// Opens the Hardware Radar bottom sheet to display real device specs & AI FPS.
Future<bool?> showCvHardwareRadarSheet(
  BuildContext context, {
  CvHardwareRadarService? service,
  bool isVietnamese = true,
  bool forceRerun = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return CvHardwareRadarSheet(
        service: service,
        isVietnamese: isVietnamese,
        forceRerun: forceRerun,
      );
    },
  );
}

/// Bottom sheet displaying real on-device hardware specs & measured pose FPS.
class CvHardwareRadarSheet extends StatefulWidget {
  const CvHardwareRadarSheet({
    super.key,
    this.service,
    this.isVietnamese = true,
    this.forceRerun = false,
  });

  final CvHardwareRadarService? service;
  final bool isVietnamese;
  final bool forceRerun;

  @override
  State<CvHardwareRadarSheet> createState() => _CvHardwareRadarSheetState();
}

class _CvHardwareRadarSheetState extends State<CvHardwareRadarSheet> {
  static const String _fontFamily = 'Manrope';

  late final CvHardwareRadarService _service;
  CvHardwareReport? _report;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? CvHardwareRadarService();
    _initEvaluation();
  }

  Future<void> _initEvaluation() async {
    if (!widget.forceRerun) {
      final cached = await _service.loadCachedReport();
      if (cached != null) {
        if (!mounted) return;
        setState(() {
          _report = cached;
          _isLoading = false;
        });
        return;
      }
    }
    await _runBenchmark();
  }

  Future<void> _runBenchmark() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    final report = await _service.runEvaluation();
    if (!mounted) return;
    setState(() {
      _report = report;
      _isLoading = false;
    });
  }

  Future<void> _handleAcknowledge() async {
    final report = _report;
    if (report == null || _isSaving) return;
    setState(() {
      _isSaving = true;
    });
    await _service.markAcknowledged(report);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SamanWorkoutTokens.of(context);
    final vi = widget.isVietnamese;

    return Container(
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SamanWorkoutTokens.radiusXl),
        ),
        border: Border(
          top: BorderSide(color: tokens.border),
          left: BorderSide(color: tokens.border),
          right: BorderSide(color: tokens.border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            SamanWorkoutTokens.spacingXl,
            SamanWorkoutTokens.spacingSm,
            SamanWorkoutTokens.spacingXl,
            SamanWorkoutTokens.spacingLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.borderHover,
                    borderRadius: BorderRadius.circular(
                      SamanWorkoutTokens.radiusPill,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SamanWorkoutTokens.spacingMd),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tokens.surfaceElevated,
                      borderRadius: BorderRadius.circular(
                        SamanWorkoutTokens.radiusMd,
                      ),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Icon(
                      Icons.radar_rounded,
                      color: tokens.tealAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: SamanWorkoutTokens.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vi ? 'Hardware Radar' : 'Hardware Radar',
                          style: TextStyle(
                            fontFamily: _fontFamily,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          vi
                              ? 'Đo hiệu năng AI thực tế trên thiết bị'
                              : 'Real on-device AI performance check',
                          style: TextStyle(
                            fontFamily: _fontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SamanWorkoutTokens.spacingMd),
              if (_isLoading || _report == null)
                _RadarLoadingView(tokens: tokens, isVietnamese: vi)
              else
                _RadarReportView(
                  tokens: tokens,
                  report: _report!,
                  isVietnamese: vi,
                  isSaving: _isSaving,
                  onAcknowledge: _handleAcknowledge,
                  onRerun: _runBenchmark,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadarLoadingView extends StatelessWidget {
  const _RadarLoadingView({
    required this.tokens,
    required this.isVietnamese,
  });

  final SamanWorkoutPalette tokens;
  final bool isVietnamese;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: SamanWorkoutTokens.spacingXxl,
        horizontal: SamanWorkoutTokens.spacingLg,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(tokens.tealAccent),
            ),
          ),
          const SizedBox(height: SamanWorkoutTokens.spacingLg),
          Text(
            isVietnamese
                ? 'Đang đo tốc độ xử lý AI thực tế trên máy (~2 giây)...'
                : 'Measuring real on-device AI speed (~2s)...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _RadarReportView extends StatelessWidget {
  const _RadarReportView({
    required this.tokens,
    required this.report,
    required this.isVietnamese,
    required this.isSaving,
    required this.onAcknowledge,
    required this.onRerun,
  });

  final SamanWorkoutPalette tokens;
  final CvHardwareReport report;
  final bool isVietnamese;
  final bool isSaving;
  final VoidCallback onAcknowledge;
  final VoidCallback onRerun;

  @override
  Widget build(BuildContext context) {
    final tierColor = _tierColor(report.tier);
    final tierLabel = _tierLabel(report.tier, isVietnamese);
    final fpsText = '${report.measuredFps.toStringAsFixed(1)} FPS';
    final latencyText = report.avgInferenceMs > 0
        ? (isVietnamese
            ? 'Độ trễ trung bình ~${report.avgInferenceMs.round()} ms/frame'
            : 'Avg latency ~${report.avgInferenceMs.round()} ms/frame')
        : (isVietnamese
            ? 'Chưa đo được độ trễ frame'
            : 'Frame latency unavailable');

    final deviceTitle = _formatDeviceName(
      report.manufacturer,
      report.deviceModel,
    );
    final ramText = _formatRam(report.totalRamMb, isVietnamese);
    final cpuText = _formatCpu(report.cpuCores, report.socHardware, isVietnamese);
    final sdkText = report.androidSdk > 0
        ? 'API ${report.androidSdk}'
        : (isVietnamese ? 'Không xác định' : 'N/A');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Prominent FPS + Tier Badge Card
        Container(
          padding: const EdgeInsets.all(SamanWorkoutTokens.spacingLg),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isVietnamese ? 'Tốc độ đo thực tế' : 'Measured AI Speed',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fpsText,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      latencyText,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: SamanWorkoutTokens.spacingMd,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: tierColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(
                    SamanWorkoutTokens.radiusPill,
                  ),
                  border: Border.all(color: tierColor.withOpacity(0.45)),
                ),
                child: Text(
                  tierLabel,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: tierColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SamanWorkoutTokens.spacingMd),

        // Real Hardware Spec Rows
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SamanWorkoutTokens.spacingLg,
            vertical: SamanWorkoutTokens.spacingMd,
          ),
          decoration: BoxDecoration(
            color: tokens.canvas,
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusLg),
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Column(
            children: [
              _SpecRow(
                tokens: tokens,
                label: isVietnamese ? 'Thiết bị' : 'Device',
                value: deviceTitle,
              ),
              Divider(color: tokens.divider, height: 12),
              _SpecRow(
                tokens: tokens,
                label: 'RAM',
                value: ramText,
              ),
              Divider(color: tokens.divider, height: 12),
              _SpecRow(
                tokens: tokens,
                label: 'CPU',
                value: cpuText,
              ),
              Divider(color: tokens.divider, height: 12),
              _SpecRow(
                tokens: tokens,
                label: 'Android SDK',
                value: sdkText,
              ),
            ],
          ),
        ),
        const SizedBox(height: SamanWorkoutTokens.spacingMd),

        // Honest Tempo Recommendation Box
        Container(
          padding: const EdgeInsets.all(SamanWorkoutTokens.spacingMd),
          decoration: BoxDecoration(
            color: tierColor.withOpacity(0.10),
            borderRadius: BorderRadius.circular(SamanWorkoutTokens.radiusMd),
            border: Border.all(color: tierColor.withOpacity(0.32)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                report.tier == CvHardwareTier.limited
                    ? Icons.warning_amber_rounded
                    : Icons.info_outline_rounded,
                size: 18,
                color: tierColor,
              ),
              const SizedBox(width: SamanWorkoutTokens.spacingSm),
              Expanded(
                child: Text(
                  _recommendationText(report, isVietnamese),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: tokens.textPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SamanWorkoutTokens.spacingLg),

        // Action Buttons
        SizedBox(
          height: 48,
          child: ElevatedButton(
            key: const ValueKey('cv_hardware_radar_ack_button'),
            onPressed: isSaving ? null : onAcknowledge,
            style: ElevatedButton.styleFrom(
              backgroundColor: tokens.buttonPrimary,
              foregroundColor: tokens.buttonPrimaryText,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  SamanWorkoutTokens.radiusMd,
                ),
              ),
            ),
            child: Text(
              isVietnamese
                  ? 'Tôi hiểu và tiếp tục'
                  : 'I understand & continue',
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: SamanWorkoutTokens.spacingSm),
        SizedBox(
          height: 44,
          child: OutlinedButton(
            key: const ValueKey('cv_hardware_radar_rerun_button'),
            onPressed: isSaving ? null : onRerun,
            style: OutlinedButton.styleFrom(
              foregroundColor: tokens.textPrimary,
              side: BorderSide(color: tokens.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  SamanWorkoutTokens.radiusMd,
                ),
              ),
            ),
            child: Text(
              isVietnamese ? 'Đo lại hiệu năng' : 'Re-run benchmark',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _tierColor(CvHardwareTier tier) {
    switch (tier) {
      case CvHardwareTier.optimal:
        return tokens.emeraldAccent;
      case CvHardwareTier.standard:
        return tokens.amberAccent;
      case CvHardwareTier.limited:
        return tokens.crimsonAccent;
    }
  }

  String _tierLabel(CvHardwareTier tier, bool vi) {
    switch (tier) {
      case CvHardwareTier.optimal:
        return vi ? 'Tối ưu' : 'Optimal';
      case CvHardwareTier.standard:
        return vi ? 'Đạt chuẩn' : 'Standard';
      case CvHardwareTier.limited:
        return vi ? 'Giới hạn phần cứng' : 'Hardware Limited';
    }
  }

  String _recommendationText(CvHardwareReport report, bool vi) {
    final fpsStr = report.measuredFps.toStringAsFixed(1);
    switch (report.tier) {
      case CvHardwareTier.optimal:
        return vi
            ? 'Tối ưu: Theo dõi mượt cả nhịp tập nhanh và chậm.'
            : 'Optimal: Smooth tracking for both fast and slow tempos.';
      case CvHardwareTier.standard:
        return vi
            ? 'Đạt chuẩn: Đếm chuẩn với nhịp tập kiểm soát vừa phải.'
            : 'Standard: Accurate counting with a controlled, moderate tempo.';
      case CvHardwareTier.limited:
        return vi
            ? 'Giới hạn phần cứng: Máy xử lý chậm (~$fpsStr FPS). Khuyến nghị tập chậm 2–3 giây/rep; có thể hụt rep nếu vung tạ quá nhanh.'
            : 'Hardware Limited: Device processes slowly (~$fpsStr FPS). Recommended slow tempo of 2–3s/rep; fast swings may miss reps.';
    }
  }

  String _formatDeviceName(String manufacturer, String model) {
    final mfg = manufacturer.trim();
    final mdl = model.trim();
    if (mfg.isEmpty && mdl.isEmpty) return 'Unknown';
    if (mfg.isEmpty) return mdl;
    if (mdl.isEmpty) return mfg;
    if (mdl.toLowerCase().startsWith(mfg.toLowerCase())) return mdl;
    return '$mfg $mdl';
  }

  String _formatRam(int totalRamMb, bool vi) {
    if (totalRamMb <= 0) {
      return vi ? 'Không xác định' : 'N/A';
    }
    final gb = (totalRamMb / 1024.0).toStringAsFixed(1);
    return '$gb GB ($totalRamMb MB)';
  }

  String _formatCpu(int cores, String soc, bool vi) {
    final corePart = cores > 0
        ? (vi ? '$cores nhân' : '$cores cores')
        : (vi ? 'N/A nhân' : 'N/A cores');
    final cleanSoc = soc.trim();
    if (cleanSoc.isEmpty || cleanSoc == 'Unknown') {
      return corePart;
    }
    return '$corePart · $cleanSoc';
  }
}

class _SpecRow extends StatelessWidget {
  const _SpecRow({
    required this.tokens,
    required this.label,
    required this.value,
  });

  final SamanWorkoutPalette tokens;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: tokens.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: SamanWorkoutTokens.spacingSm),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
