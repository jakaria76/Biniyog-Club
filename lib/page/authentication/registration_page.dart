import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../screens/home_screen.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/language_service.dart';
import '../investor/settings/legal_web_page.dart';
import 'login_page.dart';
import 'widgets/auth_card.dart';
import 'widgets/quote_banner.dart';

/// Website er "Create your account" er motoi:
/// Nam, mobile, email, jonmo tarikh, password (kompokkhe 6 okkhor), confirm.
/// NID, thikana, nominee — pore Profile → Edit theke.
class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  // ─── Palette (app er Islamic design) ───
  static const Color emerald = Color(0xFF0E4A37);
  static const Color emeraldSoft = Color(0xFFE3F0E9);
  static const Color gold = Color(0xFFB8935A);
  static const Color goldDeep = Color(0xFF8A6A3A);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);
  static const Color danger = Color(0xFFB4413A);

  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  DateTime? _dob;
  bool _dobError = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  String? _formError;

  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = () => _openLegal('Terms of Service', '/terms');
    _privacyTap = TapGestureRecognizer()..onTap = () => _openLegal('Privacy Policy', '/privacy');
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  void _openLegal(String title, String path) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LegalWebPage(title: title, url: 'https://www.biniyogclub.com$path')),
    );
  }

  // ═════════════════════════════════════════════════════════
  // PASSWORD — user er ichchha moto, shudhu kompokkhe 6 okkhor
  // ═════════════════════════════════════════════════════════
  String? _passwordValidator(String? v) {
    final t = v ?? '';
    if (t.isEmpty) return LanguageService.tr('Please create a password', 'পাসওয়ার্ড দিন');
    if (t.length < 6) {
      return LanguageService.tr('Use at least 6 characters', 'কমপক্ষে ৬ অক্ষর দিন');
    }
    return null;
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  String get _req => LanguageService.tr('Required', 'আবশ্যক');

  String _cleanPhone(String v) => DatabaseService.normalizeBdPhone(v);

  String _fmtDob(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  bool _isAdult(DateTime d) {
    final now = DateTime.now();
    return !d.isAfter(DateTime(now.year - 18, now.month, now.day));
  }

  Future<void> _pickDob() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: LanguageService.tr('Date of birth', 'জন্ম তারিখ'),
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobError = false;
      });
    }
  }

  // ═════════════════════════════════════════════════════════
  // SUBMIT
  // ═════════════════════════════════════════════════════════
  Future<void> _handleRegister() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _formError = null;
      _dobError = _dob == null || !_isAdult(_dob!);
    });
    final formOk = _formKey.currentState!.validate();
    if (!formOk || _dobError) return;

    setState(() => _isLoading = true);

    final result = await DatabaseService.registerUser(
      name: _fullNameController.text.trim(),
      email: _emailController.text.trim().toLowerCase(),
      phone: _cleanPhone(_phoneController.text.trim()),
      // Password e kono kata-chhata na — ja likheche hubohu tai
      password: _passwordController.text,
      dateOfBirth: _dob!,
    );

    // Account hole session save — tarpor shorasori app e
    if (result['success'] == true && result['data'] is Map) {
      await AuthService.saveUserData(Map<String, dynamic>.from(result['data'] as Map));
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LanguageService.tr(
              'Account created! You can add your NID, address and nominee from your profile.',
              'অ্যাকাউন্ট তৈরি হয়েছে! এনআইডি, ঠিকানা ও নমিনী প্রোফাইল থেকে যোগ করতে পারবেন।')),
          backgroundColor: emerald,
        ),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
      );
    } else {
      setState(() => _formError = result['message']?.toString() ??
          LanguageService.tr('Registration failed. Please try again.', 'রেজিস্ট্রেশন হয়নি। আবার চেষ্টা করুন।'));
    }
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: ivory,
          body: SafeArea(
            child: SingleChildScrollView(
              child: AuthCard(
                title: LanguageService.tr('Create your account', 'অ্যাকাউন্ট খুলুন'),
                description: LanguageService.tr(
                    "Join Bangladesh's leading investment platform",
                    'বাংলাদেশের শীর্ষস্থানীয় বিনিয়োগ প্ল্যাটফর্মে যুক্ত হোন'),
                quoteBanner: const QuoteBanner(
                  quote: 'Every taka you invest is tracked from your payment to your return.',
                  quoteAuthor: 'Biniyog Club',
                ),
                footer: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      LanguageService.tr('Already have an account? ', 'আগেই অ্যাকাউন্ট আছে? '),
                      style: const TextStyle(color: muted, fontSize: 13.5),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      ),
                      child: Text(
                        LanguageService.tr('Sign in', 'সাইন ইন'),
                        style: const TextStyle(color: emerald, fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ─── Full name ───
                      _label(LanguageService.tr('FULL NAME', 'পূর্ণ নাম'), isRequired: true),
                      TextFormField(
                        controller: _fullNameController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        decoration: _dec('Mohammad Arif', Icons.person_outline),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return _req;
                          if (t.length < 3) return LanguageService.tr('Name is too short', 'নাম খুব ছোট');
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // ─── Phone ───
                      _label(LanguageService.tr('PHONE NUMBER', 'মোবাইল নম্বর'), isRequired: true),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                          LengthLimitingTextInputFormatter(16),
                        ],
                        decoration: _dec('01712345678', Icons.phone_outlined),
                        validator: (v) {
                          final t = _cleanPhone((v ?? '').trim());
                          if (t.isEmpty) return _req;
                          if (!RegExp(r'^01[3-9]\d{8}$').hasMatch(t)) {
                            return LanguageService.tr('Enter a valid number (01XXXXXXXXX)', 'সঠিক নম্বর দিন (01XXXXXXXXX)');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // ─── Email (deya na-deya user er ichchha — kono "optional" lekha nei) ───
                      _label(LanguageService.tr('EMAIL', 'ইমেইল')),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: _dec('investor@example.com', Icons.mail_outline_rounded),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return null;
                          if (!RegExp(r'^[\w.+-]+@([\w-]+\.)+[A-Za-z]{2,}$').hasMatch(t)) {
                            return LanguageService.tr('Enter a valid email address', 'সঠিক ইমেইল দিন');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // ─── Date of birth ───
                      _label(LanguageService.tr('DATE OF BIRTH', 'জন্ম তারিখ'), isRequired: true),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _pickDob,
                        child: InputDecorator(
                          decoration: _dec('', Icons.calendar_month_outlined).copyWith(
                            errorText: _dobError
                                ? (_dob == null
                                ? _req
                                : LanguageService.tr('You must be at least 18 years old', 'বয়স কমপক্ষে ১৮ বছর হতে হবে'))
                                : null,
                          ),
                          child: Text(
                            _dob == null ? 'DD/MM/YYYY' : _fmtDob(_dob!),
                            style: TextStyle(fontSize: 14, color: _dob == null ? muted.withAlpha(150) : ink),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ─── Password ───
                      _label(LanguageService.tr('CREATE PASSWORD', 'পাসওয়ার্ড তৈরি করুন'), isRequired: true),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: _dec(LanguageService.tr('Min. 6 characters', 'কমপক্ষে ৬ অক্ষর'), Icons.lock_outline)
                            .copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(_isPasswordVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: muted, size: 20),
                            onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                          ),
                        ),
                        validator: _passwordValidator,
                      ),
                      const SizedBox(height: 16),

                      // ─── Confirm ───
                      _label(LanguageService.tr('CONFIRM PASSWORD', 'পাসওয়ার্ড নিশ্চিত করুন'), isRequired: true),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: !_isConfirmPasswordVisible,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _isLoading ? null : _handleRegister(),
                        decoration: _dec(LanguageService.tr('Re-enter your password', 'আবার পাসওয়ার্ড লিখুন'),
                            Icons.lock_outline)
                            .copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                                _isConfirmPasswordVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: muted,
                                size: 20),
                            onPressed: () => setState(() => _isConfirmPasswordVisible = !_isConfirmPasswordVisible),
                          ),
                        ),
                        validator: (v) {
                          if ((v ?? '').isEmpty) return _req;
                          if (v != _passwordController.text) {
                            return LanguageService.tr('Passwords do not match', 'পাসওয়ার্ড মিলছে না');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      // ─── Note + terms (website er motoi, checkbox chara) ───
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(fontSize: 12.5, color: muted, height: 1.6),
                          children: [
                            TextSpan(
                                text: LanguageService.tr(
                                    'You can add your NID, address and nominee later from your profile. By registering, you agree to Biniyog Club\'s ',
                                    'এনআইডি, ঠিকানা ও নমিনী পরে প্রোফাইল থেকে যোগ করতে পারবেন। রেজিস্টার করে আপনি বিনিয়োগ ক্লাবের ')),
                            TextSpan(
                              text: LanguageService.tr('Terms of Service', 'শর্তাবলী'),
                              style: const TextStyle(color: ink, fontWeight: FontWeight.w700),
                              recognizer: _termsTap,
                            ),
                            TextSpan(text: LanguageService.tr(' and ', ' ও ')),
                            TextSpan(
                              text: LanguageService.tr('Privacy Policy', 'প্রাইভেসি পলিসি'),
                              style: const TextStyle(color: ink, fontWeight: FontWeight.w700),
                              recognizer: _privacyTap,
                            ),
                            TextSpan(text: LanguageService.tr('.', ' মেনে নিচ্ছেন।')),
                          ],
                        ),
                      ),

                      if (_formError != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFBEAE8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline_rounded, size: 17, color: danger),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_formError!, style: const TextStyle(fontSize: 12.5, color: danger))),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 54,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _handleRegister,
                          style: FilledButton.styleFrom(
                            backgroundColor: emerald,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: emerald.withAlpha(120),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                          )
                              : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  LanguageService.tr('Create Free Investor Account', 'ফ্রি বিনিয়োগকারী অ্যাকাউন্ট খুলুন'),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, size: 19),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Shared ───────────────────────────────────────────────
  Widget _label(String text, {bool isRequired = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7, left: 2),
      child: Text.rich(
        TextSpan(
          text: text,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: ink, letterSpacing: 0.9),
          children: [
            if (isRequired) const TextSpan(text: ' *', style: TextStyle(color: danger)),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint.isEmpty ? null : hint,
      hintStyle: TextStyle(fontSize: 14, color: muted.withAlpha(150)),
      prefixIcon: Icon(icon, color: muted, size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
      focusedBorder:
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: emerald, width: 1.4)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: danger)),
      focusedErrorBorder:
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: danger, width: 1.4)),
    );
  }
}