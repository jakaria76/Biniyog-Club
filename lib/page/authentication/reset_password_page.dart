import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import 'forgot_password_page.dart';
import 'login_page.dart';
import 'widgets/auth_card.dart';

const _emerald = Color(0xFF0F4D3A);
const _bg = Color(0xFFF6F1E7);
const _danger = Color(0xFFB3261E);

class ResetPasswordPage extends StatefulWidget {
  final String email;
  final String otp;

  const ResetPasswordPage({super.key, required this.email, required this.otp});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _goLogin() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  Future<void> _handleResetPassword() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final res = await AuthService.resetPassword(
      email: widget.email,
      otp: widget.otp,
      newPassword: _newPasswordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    final msg = res['message']?.toString() ?? '';
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg.isNotEmpty ? msg : 'Password changed! Please sign in.'),
        backgroundColor: _emerald,
        behavior: SnackBarBehavior.floating,
      ));
      _goLogin();
      return;
    }

    // Code expire / onekbar vul hole notun code nite hobe
    final needNewCode = msg.toLowerCase().contains('expired') ||
        msg.toLowerCase().contains('request a new');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg.isNotEmpty ? msg : 'Failed to reset password.'),
      backgroundColor: _danger,
      behavior: SnackBarBehavior.floating,
      action: needNewCode
          ? SnackBarAction(
        label: 'GET NEW CODE',
        textColor: Colors.white,
        onPressed: () => Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
              (route) => route.isFirst,
        ),
      )
          : null,
    ));
  }

  InputDecoration _decoration(String label, bool visible, VoidCallback toggle) =>
      InputDecoration(
        labelText: label,
        hintText: '••••••••',
        prefixIcon: const Icon(Icons.lock_outline, color: _emerald),
        suffixIcon: IconButton(
          icon: Icon(
            visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: Colors.grey[600],
          ),
          onPressed: toggle,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _emerald, width: 2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _emerald),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: AuthCard(
            title: 'Create a new password',
            description: 'Choose a password with at least 8 characters for ${widget.email}.',
            footer: GestureDetector(
              onTap: _goLogin,
              child: const Text(
                'Back to sign in',
                style: TextStyle(color: _emerald, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _newPasswordController,
                    obscureText: !_isPasswordVisible,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: _decoration('New Password', _isPasswordVisible,
                            () => setState(() => _isPasswordVisible = !_isPasswordVisible)),
                    validator: (value) {
                      final v = value ?? '';
                      if (v.isEmpty) return 'Please enter a new password';
                      if (v.length < 8) return 'Password must be at least 8 characters';
                      if (v.trim() != v) return 'Password cannot start or end with a space';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: !_isConfirmVisible,
                    decoration: _decoration('Confirm New Password', _isConfirmVisible,
                            () => setState(() => _isConfirmVisible = !_isConfirmVisible)),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please confirm your new password';
                      if (value != _newPasswordController.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleResetPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _emerald,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _emerald.withAlpha(120),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : const Text('Reset Password',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}