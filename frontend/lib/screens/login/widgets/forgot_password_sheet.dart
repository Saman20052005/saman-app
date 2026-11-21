import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../../config/app_theme.dart';
import '../../../config/app_translations.dart';
import '../login_controller.dart';

class ForgotPasswordSheet extends ConsumerStatefulWidget {
  const ForgotPasswordSheet({super.key});

  @override
  ConsumerState<ForgotPasswordSheet> createState() =>
      _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends ConsumerState<ForgotPasswordSheet> {
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  int _step = 1;
  bool _isLoading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  // --- LOGIC GỌI QUA CONTROLLER ---
  void _showNeutralToast(String msg) {
    final palette = SamanPalette.of(context);
    try {
      Fluttertoast.showToast(
        msg: msg,
        backgroundColor: palette.surfaceElevated,
        textColor: palette.textPrimary,
      );
    } catch (_) {}
  }

  Future<void> _handleSendOtp() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showNeutralToast(context.tr('enter_valid_email'));
      return;
    }

    setState(() => _isLoading = true);
    final controller = ref.read(loginControllerProvider.notifier);

    // Gọi hàm sendOtp từ Controller
    final success = await controller.sendOtp(email);

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        _showNeutralToast(context.tr('otp_sent_check_email'));
        setState(() => _step = 2);
      } else {
        // Lỗi đã được handle trong controller hoặc hiển thị qua state listener ở màn hình cha
        // Tuy nhiên ở Sheet này ta check trực tiếp kết quả trả về
        final error = ref.read(loginControllerProvider).errorMessage;
        if (error != null) _showNeutralToast(error);
      }
    }
  }

  Future<void> _handleResetPassword() async {
    final otp = _otpCtrl.text.trim();
    final newPass = _newPassCtrl.text;

    if (otp.length != 6) {
      _showNeutralToast(context.tr('invalid_otp'));
      return;
    }
    if (newPass.length < 6) {
      _showNeutralToast(context.tr('password_min_chars'));
      return;
    }
    if (newPass != _confirmPassCtrl.text) {
      _showNeutralToast(context.tr('passwords_mismatch'));
      return;
    }

    setState(() => _isLoading = true);
    final controller = ref.read(loginControllerProvider.notifier);

    final success =
        await controller.resetPassword(_emailCtrl.text.trim(), otp, newPass);

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        if (!mounted) return;
        Navigator.pop(context); // Đóng modal
        // Toast thành công sẽ được kích hoạt bởi Listener bên LoginScreen
      } else {
        final error = ref.read(loginControllerProvider).errorMessage;
        if (error != null) _showNeutralToast(error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SamanPalette.of(context);

    // Để tránh bàn phím che mất nút
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _step == 1
                    ? context.tr('password_recovery_title')
                    : context.tr('reset_password_title'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _step == 1
                    ? context.tr('enter_email_verification_code')
                    : context.tr('enter_otp_and_new_password'),
                style: TextStyle(color: palette.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (_step == 1) ...[
                _SheetTextField(
                  controller: _emailCtrl,
                  hint: context.tr('email_address_hint'),
                  icon: Icons.email_outlined,
                  palette: palette,
                ),
                const SizedBox(height: AppSpacing.xl),
                _SheetSubmitButton(
                  text: context.tr('send_otp_btn'),
                  isLoading: _isLoading,
                  palette: palette,
                  onPressed: _handleSendOtp,
                ),
              ] else ...[
                _SheetTextField(
                  controller: _otpCtrl,
                  hint: context.tr('otp_code_hint'),
                  icon: Icons.vpn_key_outlined,
                  keyboard: TextInputType.number,
                  palette: palette,
                ),
                const SizedBox(height: AppSpacing.lg),
                _SheetTextField(
                  controller: _newPassCtrl,
                  hint: context.tr('new_pass'),
                  icon: Icons.lock_outline,
                  obscure: _obscureNew,
                  palette: palette,
                  onToggle: () => setState(() => _obscureNew = !_obscureNew),
                ),
                const SizedBox(height: AppSpacing.lg),
                _SheetTextField(
                  controller: _confirmPassCtrl,
                  hint: context.tr('confirm_pass'),
                  icon: Icons.check_circle_outline,
                  obscure: _obscureConfirm,
                  palette: palette,
                  onToggle: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
                const SizedBox(height: AppSpacing.xl),
                _SheetSubmitButton(
                  text: context.tr('reset_password_btn'),
                  isLoading: _isLoading,
                  palette: palette,
                  onPressed: _handleResetPassword,
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final SamanPalette palette;
  final bool obscure;
  final VoidCallback? onToggle;
  final TextInputType? keyboard;

  const _SheetTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.palette,
    this.obscure = false,
    this.onToggle,
    this.keyboard,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: palette.textMuted),
        prefixIcon: Icon(icon, color: palette.textSecondary),
        suffixIcon: onToggle != null
            ? IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: palette.textSecondary,
                ),
                onPressed: onToggle,
              )
            : null,
        filled: true,
        fillColor: palette.surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: palette.primaryCtaBg, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }
}

class _SheetSubmitButton extends StatelessWidget {
  final String text;
  final bool isLoading;
  final SamanPalette palette;
  final VoidCallback onPressed;

  const _SheetSubmitButton({
    required this.text,
    required this.isLoading,
    required this.palette,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primaryCtaBg,
          foregroundColor: palette.primaryCtaText,
          disabledBackgroundColor: palette.surfaceElevated,
          disabledForegroundColor: palette.textMuted,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: palette.primaryCtaText,
                  strokeWidth: 2,
                ),
              )
            : Text(
                text,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
      ),
    );
  }
}
