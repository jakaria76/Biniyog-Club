import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import 'reset_password_page.dart';
import 'widgets/auth_card.dart';

const _emerald = Color(0xFF0F4D3A);
const _goldDeep = Color(0xFF8A6A1F);
const _bg = Color(0xFFF6F1E7);
const _danger = Color(0xFFB3261E);

class OtpVerificationPage extends StatefulWidget {
  final String email;

  const OtpVerificationPage({super.key, required this.email});

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();

  bool _isLoading = false;
  bool _isResending = false;
  String? _error;

  int _resendSeconds = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  void _startResendTimer() {
    setState(() => _resendSeconds = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds > 0) {
        setState(() => _resendSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  String get _maskedEmail {
    final e = widget.email;
    final at = e.indexOf('@');
    if (at <= 2) return e;
    return '${e.substring(0, 2)}${'•' * (at - 2).clamp(1, 6)}${e.substring(at)}';
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

  Future<void> _handleResendOtp() async {
    if (_resendSeconds > 0 || _isResending) return;
    setState(() {
      _isResending = true;
      _error = null;
    });

    final res = await AuthService.forgotPassword(email: widget.email);
    if (!mounted) return;
    setState(() => _isResending = false);

    if (res['success'] == true) {
      _otpController.clear();
      _snack(res['message']?.toString() ?? 'New code sent to ${widget.email}');
      _startResendTimer();
    } else {
      _snack(res['message']?.toString() ?? 'Failed to resend the code.', ok: false);
    }
  }

  Future<void> _handleVerifyOtp() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final otp = _otpController.text.trim();
    final res = await AuthService.verifyOtp(email: widget.email, otp: otp);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResetPasswordPage(email: widget.email, otp: otp),
        ),
      );
    } else {
      setState(() => _error = res['message']?.toString() ?? 'Invalid or expired code.');
      _otpController.clear();
    }
  }

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
            title: 'Enter the code',
            description:
            'We emailed a 6-digit code to $_maskedEmail. It is valid for 15 minutes.',
            footer: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Didn't get the email? ",
                    style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                TextButton(
                  onPressed: (_resendSeconds == 0 && !_isResending) ? _handleResendOtp : null,
                  child: Text(
                    _isResending
                        ? 'Sending...'
                        : (_resendSeconds > 0 ? 'Resend in ${_resendSeconds}s' : 'Resend code'),
                    style: TextStyle(
                      color: _resendSeconds == 0 ? _emerald : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _otpController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 10,
                      color: _emerald,
                    ),
                    onChanged: (v) {
                      if (_error != null) setState(() => _error = null);
                      if (v.length == 6) _handleVerifyOtp();
                    },
                    decoration: InputDecoration(
                      hintText: '••••••',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: _error != null ? _danger : Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: _error != null ? _danger : _emerald, width: 2),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().length != 6) {
                        return 'Please enter the 6-digit code';
                      }
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 18, color: _danger),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: _danger, fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Check your Spam / Promotions folder if the email is not in your inbox.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: _goldDeep),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleVerifyOtp,
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
                        : const Text('Verify & Continue',
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