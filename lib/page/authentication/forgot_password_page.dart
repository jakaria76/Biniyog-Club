import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import 'login_page.dart';
import 'otp_verification_page.dart';
import 'widgets/auth_card.dart';

const _emerald = Color(0xFF0F4D3A);
const _gold = Color(0xFFC9A24A);
const _bg = Color(0xFFF6F1E7);
const _danger = Color(0xFFB3261E);

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool ok = true}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: ok ? _emerald : _danger,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _handleSendOtp() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final email = _emailController.text.trim().toLowerCase();
    final result = await AuthService.forgotPassword(email: email);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      _snack(result['message']?.toString() ?? 'Code sent to $email');
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OtpVerificationPage(email: email)),
      );
    } else {
      _snack(result['message']?.toString() ?? 'Failed to send the code.', ok: false);
    }
  }

  InputDecoration _decoration() => InputDecoration(
    labelText: 'Email Address',
    hintText: 'name@example.com',
    prefixIcon: const Icon(Icons.email_outlined, color: _emerald),
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
            title: 'Forgot your password?',
            description:
            "Enter the email address you registered with. We'll email you a 6-digit code to reset your password.",
            footer: GestureDetector(
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
              ),
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
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.send,
                    onFieldSubmitted: (_) {
                      if (!_isLoading) _handleSendOtp();
                    },
                    decoration: _decoration(),
                    validator: (value) {
                      final v = (value ?? '').trim();
                      if (v.isEmpty) return 'Please enter your email address';
                      if (!RegExp(r'^[\w.+\-]+@([\w\-]+\.)+[A-Za-z]{2,}$').hasMatch(v)) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _gold.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _gold.withAlpha(90)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF8A6A1F)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'The email comes from noreply@biniyogclub.com. If you do not see it in a minute, check your Spam / Promotions folder.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF5E4A17), height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleSendOtp,
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
                        : const Text('Send Code',
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