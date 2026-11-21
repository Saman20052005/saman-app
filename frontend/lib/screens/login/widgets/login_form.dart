import 'package:flutter/material.dart';

import '../../../config/app_theme.dart';

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

  static String? validateEmail(String? v) {
    final trimmed = v?.trim() ?? '';
    if (trimmed.isEmpty) return 'Email is required';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(trimmed)) {
      return 'Invalid email';
    }
    return null;
  }

  static String? validatePassword(String? v, {required bool isLoginMode}) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (!isLoginMode && v.length < 8) {
      return 'Min 8 chars';
    }
    return null;
  }

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
    final palette = SamanPalette.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
        boxShadow: [context.cardShadow],
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
                _FieldLabel(text: "Full Name", palette: palette),
                _ModernTextField(
                  controller: _fullNameController,
                  hint: 'Ex: An Sam',
                  icon: Icons.person_outline,
                  palette: palette,
                ),
                const SizedBox(height: AppSpacing.lg),
                _FieldLabel(text: "Phone Number", palette: palette),
                _ModernTextField(
                  controller: _phoneController,
                  hint: 'Ex: 0901234567',
                  icon: Icons.phone_outlined,
                  keyboard: TextInputType.phone,
                  palette: palette,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              _FieldLabel(text: "Email", palette: palette),
              _ModernTextField(
                controller: _emailController,
                hint: 'name@example.com',
                icon: Icons.email_outlined,
                keyboard: TextInputType.emailAddress,
                palette: palette,
                validator: LoginForm.validateEmail,
              ),
              const SizedBox(height: AppSpacing.lg),
              _FieldLabel(text: "Password", palette: palette),
              _ModernTextField(
                controller: _passwordController,
                hint: widget.isLoginMode ? '••••••' : '••••••••',
                icon: Icons.lock_outline,
                obscure: _obscurePassword,
                isPassword: true,
                palette: palette,
                onToggleObscure: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                validator: (v) => LoginForm.validatePassword(v,
                    isLoginMode: widget.isLoginMode),
              ),
              if (!widget.isLoginMode) ...[
                const SizedBox(height: AppSpacing.lg),
                _FieldLabel(text: "Confirm Password", palette: palette),
                _ModernTextField(
                  controller: _confirmPasswordController,
                  hint: '••••••••',
                  icon: Icons.lock_outline,
                  obscure: _obscureConfirmPassword,
                  isPassword: true,
                  palette: palette,
                  onToggleObscure: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword),
                  validator: (v) => v != _passwordController.text
                      ? 'Passwords do not match'
                      : null,
                ),
              ],
              if (widget.isLoginMode)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: widget.onForgotPassword,
                    child: Text(
                      "Forgot Password?",
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: widget.isLoading ? null : _submit,
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
                  child: widget.isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: palette.primaryCtaText,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          widget.isLoginMode ? 'Log In' : 'Sign Up',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final SamanPalette palette;

  const _FieldLabel({required this.text, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
      ),
    );
  }
}

class _ModernTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final SamanPalette palette;
  final bool obscure;
  final bool isPassword;
  final TextInputType? keyboard;
  final VoidCallback? onToggleObscure;
  final String? Function(String?)? validator;

  const _ModernTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.palette,
    this.obscure = false,
    this.isPassword = false,
    this.keyboard,
    this.onToggleObscure,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      style: TextStyle(
        fontWeight: FontWeight.w500,
        color: palette.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: palette.textMuted, fontSize: 14),
        prefixIcon: Icon(icon, color: palette.textSecondary, size: 22),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: palette.textSecondary,
                  size: 20,
                ),
                onPressed: onToggleObscure,
              )
            : null,
        filled: true,
        fillColor: palette.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: palette.primaryCtaBg, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: palette.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: palette.danger, width: 1.5),
        ),
        errorStyle: TextStyle(color: palette.danger),
      ),
      validator: validator,
    );
  }
}
