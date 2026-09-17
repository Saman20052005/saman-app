import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
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
  Future<void> _handleSendOtp() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      Fluttertoast.showToast(msg: "Please enter a valid email");
      return;
    }

    setState(() => _isLoading = true);
    final controller = ref.read(loginControllerProvider.notifier);

    // Gọi hàm sendOtp từ Controller
    final success = await controller.sendOtp(email);

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Fluttertoast.showToast(msg: "OTP sent! Check your email.");
        setState(() => _step = 2);
      } else {
        // Lỗi đã được handle trong controller hoặc hiển thị qua state listener ở màn hình cha
        // Tuy nhiên ở Sheet này ta check trực tiếp kết quả trả về
        final error = ref.read(loginControllerProvider).errorMessage;
        if (error != null) Fluttertoast.showToast(msg: error);
      }
    }
  }

  Future<void> _handleResetPassword() async {
    final otp = _otpCtrl.text.trim();
    final newPass = _newPassCtrl.text;

    if (otp.length != 6) {
      Fluttertoast.showToast(msg: "Invalid OTP (6 digits)");
      return;
    }
    if (newPass.length < 6) {
      Fluttertoast.showToast(msg: "Password min 6 chars");
      return;
    }
    if (newPass != _confirmPassCtrl.text) {
      Fluttertoast.showToast(msg: "Passwords mismatch");
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
        if (error != null) Fluttertoast.showToast(msg: error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Để tránh bàn phím che mất nút
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Text(
                _step == 1 ? "Password Recovery" : "Reset Password",
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E1E1E)),
              ),
              const SizedBox(height: 8),
              Text(
                _step == 1
                    ? "Enter your email to receive a verification code."
                    : "Enter the OTP sent to your email and set a new password.",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              const SizedBox(height: 24),
              if (_step == 1) ...[
                _buildTextField(
                    _emailCtrl, "Email Address", Icons.email_outlined),
                const SizedBox(height: 24),
                _buildButton("Send OTP", _handleSendOtp),
              ] else ...[
                _buildTextField(
                    _otpCtrl, "OTP Code (6 digits)", Icons.vpn_key_outlined,
                    keyboard: TextInputType.number),
                const SizedBox(height: 16),
                _buildTextField(
                    _newPassCtrl, "New Password", Icons.lock_outline,
                    obscure: _obscureNew,
                    onToggle: () => setState(() => _obscureNew = !_obscureNew)),
                const SizedBox(height: 16),
                _buildTextField(_confirmPassCtrl, "Confirm New Password",
                    Icons.check_circle_outline,
                    obscure: _obscureConfirm,
                    onToggle: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm)),
                const SizedBox(height: 24),
                _buildButton("Reset Password", _handleResetPassword),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String hint, IconData icon,
      {bool obscure = false, VoidCallback? onToggle, TextInputType? keyboard}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboard,
      style:
          const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400),
        prefixIcon: Icon(icon, color: Colors.grey.shade500),
        suffixIcon: onToggle != null
            ? IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey.shade500),
                onPressed: onToggle)
            : null,
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }

  Widget _buildButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Text(text,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}
