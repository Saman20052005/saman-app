import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../config/app_theme.dart';
import '../../features/membership/domain/models/membership_plan.dart';
import '../../features/membership/presentation/screens/plan_detail_screen.dart';
import '../../features/membership/presentation/widgets/upgrade_bottom_sheet.dart';
import '../../features/nutrition/domain/repositories/nutrition_repository.dart';
import '../../providers/nutrition_provider.dart';
import '../../services/nutrition_service.dart';

class BarcodeScannerScreen extends ConsumerStatefulWidget {
  final INutritionRepository? repository;
  final Future<XFile?> Function(ImageSource source)? imagePicker;
  final bool enableCamera;
  final Widget Function(
    BuildContext context,
    void Function(String barcode) onBarcodeDetected,
  )? scannerBuilder;

  const BarcodeScannerScreen({
    super.key,
    this.repository,
    this.imagePicker,
    this.enableCamera = true,
    this.scannerBuilder,
  });

  @override
  ConsumerState<BarcodeScannerScreen> createState() =>
      _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends ConsumerState<BarcodeScannerScreen> {
  MobileScannerController? _scannerController;
  final ImagePicker _defaultPicker = ImagePicker();

  bool _isLookingUp = false;
  bool _isAnalyzingLabel = false;
  String? _notFoundBarcode;
  String? _notFoundMessage;
  String? _errorMessage;
  String? _lastScannedCode;
  DateTime? _lastScanAt;

  INutritionRepository get _repository =>
      widget.repository ?? ref.read(nutritionRepositoryProvider);

  @override
  void initState() {
    super.initState();
    if (widget.enableCamera && widget.scannerBuilder == null) {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        detectionTimeoutMs: 1000,
      );
    }
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  bool get _isBusy => _isLookingUp || _isAnalyzingLabel;

  void _onBarcodeDetect(BarcodeCapture capture) {
    if (_isBusy || _notFoundBarcode != null) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim() ?? '';
      if (raw.isNotEmpty) {
        _handleBarcode(raw);
        break;
      }
    }
  }

  Future<void> _handleBarcode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty || _isBusy) return;

    final now = DateTime.now();
    if (_lastScannedCode == code &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < const Duration(seconds: 3)) {
      return;
    }

    setState(() {
      _lastScannedCode = code;
      _lastScanAt = now;
      _isLookingUp = true;
      _errorMessage = null;
      _notFoundBarcode = null;
      _notFoundMessage = null;
    });

    try {
      final result = await _repository.lookupBarcode(code);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on BarcodeNotFoundException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLookingUp = false;
        _notFoundBarcode = e.barcode;
        _notFoundMessage = e.message.trim().isNotEmpty
            ? e.message
            : 'Mã vạch ${e.barcode} chưa có trên Open Food Facts.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLookingUp = false;
        _errorMessage = _formatLookupError(e);
      });
    }
  }

  String _formatLookupError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 401) {
        return 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
      }
      final data = error.response?.data;
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
      return 'Không thể tra cứu mã vạch. Vui lòng kiểm tra kết nối và thử lại.';
    }
    return 'Không thể tra cứu mã vạch. Vui lòng thử lại.';
  }

  Future<void> _showManualBarcodeDialog() async {
    if (_isBusy) return;
    final submitted = await showDialog<String>(
      context: context,
      builder: (_) => const _ManualBarcodeDialog(),
    );
    if (submitted != null && submitted.isNotEmpty && mounted) {
      await _handleBarcode(submitted);
    }
  }

  Future<void> _startAiLabelFlow() async {
    if (_isBusy || _notFoundBarcode == null) return;
    final source = await _pickImageSource();
    if (!mounted || source == null) return;

    XFile? picked;
    try {
      picked = await (widget.imagePicker != null
          ? widget.imagePicker!(source)
          : _defaultPicker.pickImage(
              source: source,
              imageQuality: 75,
              maxWidth: 1400,
              maxHeight: 1400,
              preferredCameraDevice: CameraDevice.rear,
            ));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Không thể mở máy ảnh hoặc thư viện ảnh.';
      });
      return;
    }

    if (!mounted || picked == null) return;

    setState(() {
      _isAnalyzingLabel = true;
      _errorMessage = null;
    });

    try {
      final result = await _repository.analyzeNutritionLabel(
        barcode: _notFoundBarcode!,
        imageFile: picked,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAnalyzingLabel = false);

      if (_isPaywallOrQuotaError(e)) {
        await _openUpgradeSheet();
      } else {
        setState(() {
          _errorMessage = _formatAiLabelError(e);
        });
      }
    }
  }

  Future<ImageSource?> _pickImageSource() async {
    if (widget.imagePicker != null) {
      return ImageSource.camera;
    }
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final p = SamanPalette.of(sheetCtx);
        return Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: p.border),
              left: BorderSide(color: p.border),
              right: BorderSide(color: p.border),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: p.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Chọn ảnh bảng thành phần dinh dưỡng',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Chụp rõ mặt bảng Nutrition Facts để AI đọc calo và macro.',
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('ai_label_source_camera'),
                          onPressed: () =>
                              Navigator.of(sheetCtx).pop(ImageSource.camera),
                          icon: Icon(Icons.camera_alt_outlined,
                              size: 18, color: p.accent),
                          label: const Text('Chụp ảnh'),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: p.surfaceElevated,
                            foregroundColor: p.textPrimary,
                            side: BorderSide(color: p.border),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('ai_label_source_gallery'),
                          onPressed: () =>
                              Navigator.of(sheetCtx).pop(ImageSource.gallery),
                          icon: Icon(Icons.photo_library_outlined,
                              size: 18, color: p.accent),
                          label: const Text('Thư viện'),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: p.surfaceElevated,
                            foregroundColor: p.textPrimary,
                            side: BorderSide(color: p.border),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isPaywallOrQuotaError(Object error) {
    if (error is EntitlementRequiredException ||
        error is QuotaExhaustedException) {
      return true;
    }
    if (error is DioException) {
      final code = error.response?.statusCode;
      return code == 403 || code == 429;
    }
    return false;
  }

  String _formatAiLabelError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
    }
    return 'Không thể đọc bảng thành phần dinh dưỡng từ ảnh. Vui lòng chụp rõ hơn và thử lại.';
  }

  Future<void> _openUpgradeSheet() async {
    final selectedTier = await showUpgradeBottomSheet(
      context,
      tier: MembershipTier.plus,
    );
    if (!mounted || selectedTier == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings:
            RouteSettings(name: '/membership/detail/${selectedTier.name}'),
        builder: (_) => PlanDetailScreen(tier: selectedTier),
      ),
    );
  }

  void _resetToScan() {
    setState(() {
      _notFoundBarcode = null;
      _notFoundMessage = null;
      _errorMessage = null;
      _lastScannedCode = null;
      _lastScanAt = null;
    });
  }

  Future<void> _toggleTorch() async {
    final controller = _scannerController;
    if (controller == null) return;
    try {
      await controller.toggleTorch();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = SamanPalette.of(context);

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        backgroundColor: p.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Đóng',
          icon: Icon(Icons.arrow_back, color: p.textPrimary),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        title: Text(
          'Quét mã vạch',
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_scannerController != null)
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: _scannerController!,
              builder: (context, state, _) {
                final torchOn = state.torchState == TorchState.on;
                return IconButton(
                  key: const Key('barcode_flash_toggle'),
                  tooltip: torchOn ? 'Tắt đèn Flash' : 'Bật đèn Flash',
                  icon: Icon(
                    torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: torchOn ? p.amber : p.textSecondary,
                  ),
                  onPressed: state.torchState == TorchState.unavailable
                      ? null
                      : _toggleTorch,
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: p.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildScannerViewport(p),
                          if (_notFoundBarcode != null)
                            _buildNotFoundOverlay(p),
                          if (_isBusy) _buildLoadingOverlay(p),
                        ],
                      ),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      key: const Key('barcode_error_banner'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: p.danger.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.danger.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              size: 18, color: p.danger),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: p.danger,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: p.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: p.surfaceElevated,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: p.border),
                              ),
                              child: Icon(
                                Icons.qr_code_scanner_rounded,
                                size: 20,
                                color: p.accent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Đưa mã vạch vào khung hình',
                                    style: TextStyle(
                                      color: p.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Tự động tra cứu trên Open Food Facts hoặc chụp nhãn AI nếu chưa có.',
                                    style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 46,
                          child: OutlinedButton.icon(
                            key: const Key('manual_barcode_button'),
                            onPressed: _isBusy ? null : _showManualBarcodeDialog,
                            icon: Icon(
                              Icons.keyboard_alt_outlined,
                              size: 18,
                              color: p.textPrimary,
                            ),
                            label: const Text(
                              'Nhập mã vạch thủ công',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: p.surfaceElevated,
                              foregroundColor: p.textPrimary,
                              side: BorderSide(color: p.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScannerViewport(SamanPalette p) {
    if (widget.scannerBuilder != null) {
      return widget.scannerBuilder!(context, _handleBarcode);
    }
    if (!widget.enableCamera || _scannerController == null) {
      return _buildCameraPlaceholder(
        p,
        title: 'Camera tạm ẩn',
        subtitle: 'Dùng nút "Nhập mã vạch thủ công" bên dưới để tra cứu.',
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _onBarcodeDetect,
          placeholderBuilder: (context, _) => _buildCameraPlaceholder(
            p,
            title: 'Đang khởi động camera...',
            subtitle: 'Vui lòng cấp quyền camera để quét mã vạch sản phẩm.',
          ),
          errorBuilder: (context, error, _) => _buildCameraPlaceholder(
            p,
            title: 'Không thể truy cập camera',
            subtitle:
                'Hãy cấp quyền camera trong cài đặt hoặc nhập mã vạch thủ công.',
          ),
        ),
        IgnorePointer(
          child: Center(
            child: Container(
              width: 240,
              height: 150,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: p.accent,
                  width: 2.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraPlaceholder(
    SamanPalette p, {
    required String title,
    required String subtitle,
  }) {
    return Container(
      color: p.surfaceElevated,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_2_rounded, size: 52, color: p.textMuted),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFoundOverlay(SamanPalette p) {
    return Container(
      key: const Key('barcode_not_found_panel'),
      color: p.surface,
      padding: const EdgeInsets.all(20),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: p.amber.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: p.amber.withOpacity(0.35)),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 28,
                    color: p.amber,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Chưa tìm thấy sản phẩm',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _notFoundMessage ??
                    'Mã $_notFoundBarcode chưa có trên Open Food Facts. Bạn có thể chụp bảng thành phần dinh dưỡng để AI tự động đọc.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: p.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: p.border),
                  ),
                  child: Text(
                    'Barcode: $_notFoundBarcode',
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  key: const Key('ai_analyze_label_button'),
                  onPressed: _isBusy ? null : _startAiLabelFlow,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text(
                    'Chụp bảng thành phần dinh dưỡng (AI)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: p.onAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  key: const Key('scan_another_barcode_button'),
                  onPressed: _isBusy ? null : _resetToScan,
                  icon: Icon(Icons.qr_code_scanner_rounded,
                      size: 18, color: p.textPrimary),
                  label: const Text(
                    'Quét mã khác',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: p.surfaceElevated,
                    foregroundColor: p.textPrimary,
                    side: BorderSide(color: p.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay(SamanPalette p) {
    return Container(
      color: p.canvas.withOpacity(0.86),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: p.accent,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _isAnalyzingLabel
                    ? 'AI đang đọc bảng thành phần dinh dưỡng...'
                    : 'Đang tra cứu mã vạch...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualBarcodeDialog extends StatefulWidget {
  const _ManualBarcodeDialog();

  @override
  State<_ManualBarcodeDialog> createState() => _ManualBarcodeDialogState();
}

class _ManualBarcodeDialogState extends State<_ManualBarcodeDialog> {
  final TextEditingController _ctrl = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = SamanPalette.of(context);
    return AlertDialog(
      backgroundColor: p.surface,
      scrollable: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.border),
      ),
      title: Text(
        'Nhập mã vạch thủ công',
        style: TextStyle(
          color: p.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nhập dãy số dưới mã vạch (EAN-8, EAN-13, UPC) để tra cứu nhanh.',
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('manual_barcode_input'),
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Ví dụ: 8934563138165',
                hintStyle: TextStyle(color: p.textMuted),
                filled: true,
                fillColor: p.surfaceElevated,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.accent, width: 1.5),
                ),
              ),
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 8),
              Text(
                _validationError!,
                style: TextStyle(
                  color: p.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text('Hủy', style: TextStyle(color: p.textSecondary)),
        ),
        FilledButton(
          key: const Key('manual_barcode_submit'),
          style: FilledButton.styleFrom(
            backgroundColor: p.primaryCtaBg,
            foregroundColor: p.primaryCtaText,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () {
            final text = _ctrl.text.trim();
            if (text.isEmpty || text.length < 4) {
              setState(() {
                _validationError = 'Vui lòng nhập mã vạch hợp lệ.';
              });
              return;
            }
            Navigator.of(context).pop(text);
          },
          child: const Text('Tra cứu'),
        ),
      ],
    );
  }
}

