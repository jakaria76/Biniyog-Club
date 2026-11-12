import 'package:flutter/material.dart';

import '../../screens/home_screen.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/language_service.dart';
import 'forgot_password_page.dart';
import 'registration_page.dart';
import 'widgets/auth_shell.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const Color emerald = AuthShell.emerald;
  static const Color muted = AuthShell.muted;

  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    // Phone na email — lekhar shathe shathe icon bodlay
    _idController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _looksLikeEmail => _idController.text.contains('@');

  String? _idValidator(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) {
      return LanguageService.tr('Enter your phone number or email', 'মোবাইল নম্বর বা ইমেইল দিন');
    }
    if (t.contains('@')) {
      if (!RegExp(r'^[\w.+-]+@([\w-]+\.)+[A-Za-z]{2,}$').hasMatch(t)) {
        return LanguageService.tr('Enter a valid email address', 'সঠিক ইমেইল দিন');
      }
      return null;
    }
    // Je kono desh: BD hole 01… cholbe, onno desh hole +code shoho (+44…, +971…)
    if (!RegExp(r'^[+\d\s\-().]+$').hasMatch(t)) {
      return LanguageService.tr('Enter a valid phone number or email', 'সঠিক মোবাইল নম্বর বা ইমেইল দিন');
    }
    final phone = DatabaseService.canonicalPhone(t);
    if (!DatabaseService.isValidPhone(phone)) {
      return phone.startsWith('+')
          ? LanguageService.tr('Enter a valid phone number', 'সঠিক ফোন নম্বর দিন')
          : LanguageService.tr('Outside Bangladesh? Add the country code, e.g. +44…',
          'বাংলাদেশের বাইরের নম্বর হলে দেশের কোড দিন, যেমন +44…');
    }
    return null;
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    setState(() => _formError = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    // AuthService phone ar email duitai nite pare
    final result = await AuthService.login(
      email: _idController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() => _formError = result['message']?.toString() ??
          LanguageService.tr('Login failed. Please try again.', 'লগইন হয়নি। আবার চেষ্টা করুন।'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return AuthShell(
          eyebrow: 'Biniyog Club',
          title: LanguageService.tr('Welcome back', 'আবার স্বাগতম'),
          subtitle: LanguageService.tr(
            'Sign in to track your investments, payments and returns.',
            'আপনার বিনিয়োগ, পেমেন্ট ও লাভ দেখতে সাইন ইন করুন।',
          ),
          highlights: [
            (Icons.verified_outlined, LanguageService.tr('Admin-reviewed projects', 'অ্যাডমিন যাচাইকৃত প্রজেক্ট')),
            (Icons.receipt_long_outlined, LanguageService.tr('Every taka tracked', 'প্রতিটি টাকার হিসাব')),
          ],
          footer: AuthShell.switchLink(
            question: LanguageService.tr("Don't have an account? ", 'অ্যাকাউন্ট নেই? '),
            action: LanguageService.tr('Create one', 'খুলুন'),
            onTap: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const RegistrationPage()),
            ),
          ),
          child: Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    LanguageService.tr('Sign in', 'সাইন ইন'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AuthShell.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    LanguageService.tr('Use the phone number or email you registered with.',
                        'যে মোবাইল নম্বর বা ইমেইল দিয়ে রেজিস্টার করেছেন সেটি দিন।'),
                    style: const TextStyle(fontSize: 13.5, color: muted, height: 1.4),
                  ),
                  const SizedBox(height: 20),

                  // ─── Phone / email ───
                  AuthShell.label(LanguageService.tr('PHONE OR EMAIL', 'মোবাইল বা ইমেইল')),
                  TextFormField(
                    controller: _idController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.telephoneNumber, AutofillHints.email],
                    decoration: AuthShell.dec(
                      LanguageService.tr('01712345678 or email', '01712345678 বা ইমেইল'),
                      _looksLikeEmail ? Icons.mail_outline_rounded : Icons.phone_outlined,
                    ).copyWith(
                      helperText: LanguageService.tr('Outside Bangladesh? Start with +country code',
                          'বাংলাদেশের বাইরের নম্বর হলে + দেশের কোড দিয়ে লিখুন'),
                      helperStyle: const TextStyle(fontSize: 12.5, color: muted),
                    ),
                    validator: _idValidator,
                  ),
                  const SizedBox(height: 16),

                  // ─── Password ───
                  Row(
                    children: [
                      Expanded(child: AuthShell.label(LanguageService.tr('PASSWORD', 'পাসওয়ার্ড'))),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
                          ),
                          child: Text(
                            LanguageService.tr('Forgot password?', 'পাসওয়ার্ড ভুলে গেছেন?'),
                            style: const TextStyle(color: emerald, fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) {
                      if (!_isLoading) _handleLogin();
                    },
                    decoration: AuthShell.dec('••••••••', Icons.lock_outline).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: muted,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                      ),
                    ),
                    validator: (v) {
                      if ((v ?? '').isEmpty) {
                        return LanguageService.tr('Please enter your password', 'পাসওয়ার্ড দিন');
                      }
                      return null;
                    },
                  ),

                  if (_formError != null) ...[
                    const SizedBox(height: 14),
                    AuthShell.errorBox(_formError!),
                  ],
                  const SizedBox(height: 22),
                  AuthShell.primaryButton(
                    text: LanguageService.tr('Sign In', 'সাইন ইন'),
                    loading: _isLoading,
                    onPressed: _handleLogin,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_rounded, size: 13, color: muted),
                      const SizedBox(width: 6),
                      Text(
                        LanguageService.tr('Your password is encrypted', 'আপনার পাসওয়ার্ড এনক্রিপ্টেড'),
                        style: const TextStyle(fontSize: 12.5, color: muted),
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
}