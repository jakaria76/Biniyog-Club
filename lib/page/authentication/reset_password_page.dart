import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/language_service.dart';
import 'forgot_password_page.dart';
import 'login_page.dart';
import 'widgets/auth_card.dart';
import '../../theme/app_colors.dart';

/// Notun password — website ar registration er motoi kompokkhe 6 okkhor.
class ResetPasswordPage extends StatefulWidget {
  final String email;
  final String otp;

  const ResetPasswordPage({super.key, required this.email, required this.otp});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  // ─── Palette — website er rong (lib/theme/app_colors.dart) ───
  static const Color emerald = BC.primary;
  static const Color emeraldSoft = BC.secondary;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color danger = BC.destructive;
  static const Color dangerSoft = BC.destructiveMuted;

  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmVisible = false;
  bool _isLoading = false;
  String? _error;
  bool _needNewCode = false;

  @override
  void initState() {
    super.initState();
    // Niche live tick dekhate
    _newPasswordController.addListener(_refresh);
    _confirmPasswordController.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

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

  void _getNewCode() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
          (route) => route.isFirst,
    );
  }

  Future<void> _handleResetPassword() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _needNewCode = false;
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final res = await AuthService.resetPassword(
      email: widget.email,
      otp: widget.otp,
      // Password e kono kata-chhata na — ja likheche hubohu tai
      newPassword: _newPasswordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    final msg = res['message']?.toString() ?? '';
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(LanguageService.tr(
            'Password changed! Please sign in with your new password.',
            'পাসওয়ার্ড বদলানো হয়েছে! নতুন পাসওয়ার্ড দিয়ে সাইন ইন করুন।')),
        backgroundColor: emerald,
        behavior: SnackBarBehavior.floating,
      ));
      _goLogin();
      return;
    }

    // Code expire / onekbar vul hole notun code nite hobe
    final low = msg.toLowerCase();
    setState(() {
      _needNewCode = low.contains('expired') || low.contains('request a new') || low.contains('no active code');
      _error = msg.isNotEmpty
          ? msg
          : LanguageService.tr('Could not reset the password. Please try again.',
          'পাসওয়ার্ড বদলানো যায়নি। আবার চেষ্টা করুন।');
    });
  }

  InputDecoration _decoration(String label, bool visible, VoidCallback toggle) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 14.5, color: muted),
      hintText: '••••••••',
      prefixIcon: const Icon(Icons.lock_outline, color: muted, size: 20),
      suffixIcon: IconButton(
        icon: Icon(visible ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: muted, size: 20),
        onPressed: toggle,
      ),
      filled: true,
      fillColor: ivory,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
      focusedBorder:
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: emerald, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: danger)),
      focusedErrorBorder:
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: danger, width: 1.5)),
    );
  }

  Widget _hint(bool ok, String text) {
    return Row(
      children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 15, color: ok ? emerald : muted.withAlpha(140)),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
                fontSize: 12.5, color: ok ? emerald : muted, fontWeight: ok ? FontWeight.w700 : FontWeight.w500)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, _) {
        final pw = _newPasswordController.text;
        final cpw = _confirmPasswordController.text;

        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: emerald),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SafeArea(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: AuthCard(
                  title: LanguageService.tr('Create a new password', 'নতুন পাসওয়ার্ড দিন'),
                  description: LanguageService.tr(
                    'Choose a password with at least 6 characters for ${widget.email}.',
                    '${widget.email} এর জন্য কমপক্ষে ৬ অক্ষরের পাসওয়ার্ড দিন।',
                  ),
                  footer: InkWell(
                    onTap: _goLogin,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        LanguageService.tr('Back to sign in', 'সাইন ইনে ফিরে যান'),
                        style: const TextStyle(color: emerald, fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ),
                  ),
                  child: Form(
                    key: _formKey,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _newPasswordController,
                            obscureText: !_isPasswordVisible,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: _decoration(
                              LanguageService.tr('New password', 'নতুন পাসওয়ার্ড'),
                              _isPasswordVisible,
                                  () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                            ),
                            validator: (value) {
                              final v = value ?? '';
                              if (v.isEmpty) return LanguageService.tr('Please enter a new password', 'নতুন পাসওয়ার্ড দিন');
                              if (v.length < 6) {
                                return LanguageService.tr('Use at least 6 characters', 'কমপক্ষে ৬ অক্ষর দিন');
                              }
                              if (v.trim() != v) {
                                return LanguageService.tr('Password cannot start or end with a space',
                                    'পাসওয়ার্ডের শুরু বা শেষে স্পেস দেওয়া যাবে না');
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          _hint(pw.length >= 6, LanguageService.tr('At least 6 characters', 'কমপক্ষে ৬ অক্ষর')),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: !_isConfirmVisible,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _handleResetPassword(),
                            decoration: _decoration(
                              LanguageService.tr('Confirm new password', 'নতুন পাসওয়ার্ড আবার দিন'),
                              _isConfirmVisible,
                                  () => setState(() => _isConfirmVisible = !_isConfirmVisible),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return LanguageService.tr('Please confirm your new password', 'পাসওয়ার্ড আবার দিন');
                              }
                              if (value != _newPasswordController.text) {
                                return LanguageService.tr('Passwords do not match', 'পাসওয়ার্ড মিলছে না');
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          _hint(cpw.isNotEmpty && cpw == pw,
                              LanguageService.tr('Passwords match', 'পাসওয়ার্ড মিলেছে')),

                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: dangerSoft, borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.error_outline_rounded, size: 17, color: danger),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(_error!,
                                            style: const TextStyle(fontSize: 13.5, color: danger, height: 1.4)),
                                      ),
                                    ],
                                  ),
                                  if (_needNewCode) ...[
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: _getNewCode,
                                        icon: const Icon(Icons.refresh_rounded, size: 17, color: emerald),
                                        label: Text(
                                          LanguageService.tr('Get a new code', 'নতুন কোড নিন'),
                                          style: const TextStyle(color: emerald, fontWeight: FontWeight.w800),
                                        ),
                                        style: TextButton.styleFrom(backgroundColor: emeraldSoft),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 22),
                          SizedBox(
                            height: 54,
                            child: FilledButton(
                              onPressed: _isLoading ? null : _handleResetPassword,
                              style: FilledButton.styleFrom(
                                backgroundColor: emerald,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: emerald.withAlpha(140),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                              )
                                  : Text(
                                LanguageService.tr('Reset Password', 'পাসওয়ার্ড বদলান'),
                                style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Choto note
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              LanguageService.tr('You will be signed out and asked to sign in again.',
                                  'বদলানোর পর আবার সাইন ইন করতে হবে।'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12.5, color: ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}