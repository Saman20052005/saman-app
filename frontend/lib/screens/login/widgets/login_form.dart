import 'package:flutter/material.dart';

class LoginForm extends StatefulWidget {
  final bool isLoginMode;
  final bool isLoading;
  final Function(String email, String pass, String? name, String? phone)
      onSubmit;
  final VoidCallback onForgotPassword;

  const LoginForm({
    super.key,
    required this.isLoginMode,
    required this.isLoading,
    required this.onSubmit,
    required this.onForgotPassword,
  });

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      widget.onSubmit(
        _emailController.text.trim(),
        _passwordController.text,
        widget.isLoginMode ? null : _fullNameController.text.trim(),
        widget.isLoginMode ? null : _phoneController.text.trim(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlack = Color(0xFF1E1E1E);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 24,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Form(
        key: _formKey,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.isLoginMode) ...[
                _buildLabel("Full Name"),
                _buildModernTextField(
                    _fullNameController, 'Ex: An Sam', Icons.person_outline),
                const SizedBox(height: 16),
                _buildLabel("Phone Number"),
                _buildModernTextField(
                    _phoneController, 'Ex: 0901234567', Icons.phone_outlined,
                    keyboard: TextInputType.phone),
                const SizedBox(height: 16),
              ],
              _buildLabel("Email"),
              _buildModernTextField(
                  _emailController, 'name@example.com', Icons.email_outlined,
                  keyboard: TextInputType.emailAddress,
                  validator: (v) =>
                      (v == null || !v.contains('@')) ? 'Invalid email' : null),
              const SizedBox(height: 16),
              _buildLabel("Password"),
              _buildModernTextField(
                  _passwordController, '••••••', Icons.lock_outline,
                  obscure: _obscurePassword,
                  isPassword: true,
                  onToggleObscure: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  validator: (v) =>
                      (v == null || v.length < 6) ? 'Min 6 chars' : null),
              if (!widget.isLoginMode) ...[
                const SizedBox(height: 16),
                _buildLabel("Confirm Password"),
                _buildModernTextField(
                    _confirmPasswordController, '••••••', Icons.lock_outline,
                    obscure: _obscureConfirmPassword,
                    isPassword: true,
                    onToggleObscure: () => setState(() =>
                        _obscureConfirmPassword = !_obscureConfirmPassword),
                    validator: (v) => v != _passwordController.text
                        ? 'Passwords do not match'
                        : null),
              ],
              if (widget.isLoginMode)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: widget.onForgotPassword,
                    child: const Text("Forgot Password?",
                        style: TextStyle(
                            color: primaryBlack,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: widget.isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlack,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: widget.isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text(widget.isLoginMode ? 'Log In' : 'Sign Up',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87)),
    );
  }

  Widget _buildModernTextField(
      TextEditingController controller, String hint, IconData icon,
      {bool obscure = false,
      bool isPassword = false,
      TextInputType? keyboard,
      VoidCallback? onToggleObscure,
      String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      style: const TextStyle(fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 22),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey.shade500, size: 20),
                onPressed: onToggleObscure)
            : null,
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF1E1E1E), width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.red.shade200)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.red.shade400)),
      ),
      validator: validator,
    );
  }
}
