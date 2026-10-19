import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../screens/home_screen.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/language_service.dart';
import '../investor/settings/legal_web_page.dart';
import 'login_page.dart';
import 'widgets/auth_shell.dart';

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
    // Password er pashe live tick dekhate
    _passwordController.addListener(_refresh);
    _confirmPasswordController.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
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
        final pw = _passwordController.text;
        final cpw = _confirmPasswordController.text;

        return AuthShell(
          eyebrow: 'Biniyog Club',
          title: LanguageService.tr('Create your account', 'অ্যাকাউন্ট খুলুন'),
          subtitle: LanguageService.tr(
            'Free investor account — it takes less than a minute.',
            'ফ্রি বিনিয়োগকারী অ্যাকাউন্ট — এক মিনিটও লাগবে না।',
          ),
          highlights: [
            (Icons.timer_outlined, LanguageService.tr('Under 1 minute', '১ মিনিটের কম')),
            (Icons.receipt_long_outlined, LanguageService.tr('Every taka tracked', 'প্রতিটি টাকার হিসাব')),
          ],
          footer: AuthShell.switchLink(
            question: LanguageService.tr('Already have an account? ', 'আগেই অ্যাকাউন্ট আছে? '),
            action: LanguageService.tr('Sign in', 'সাইন ইন'),
            onTap: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ),
          ),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle(1, LanguageService.tr('Your details', 'আপনার তথ্য')),
                  const SizedBox(height: 16),

                  // ─── Full name ───
                  AuthShell.label(LanguageService.tr('FULL NAME', 'পূর্ণ নাম'), isRequired: true),
                  TextFormField(
                    controller: _fullNameController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    decoration: AuthShell.dec('Mohammad Arif', Icons.person_outline),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return _req;
                      if (t.length < 3) return LanguageService.tr('Name is too short', 'নাম খুব ছোট');
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ─── Phone ───
                  AuthShell.label(LanguageService.tr('PHONE NUMBER', 'মোবাইল নম্বর'), isRequired: true),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                      LengthLimitingTextInputFormatter(16),
                    ],
                    decoration: AuthShell.dec('01712345678', Icons.phone_outlined),
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
                  AuthShell.label(LanguageService.tr('EMAIL', 'ইমেইল')),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: AuthShell.dec('investor@example.com', Icons.mail_outline_rounded),
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
                  AuthShell.label(LanguageService.tr('DATE OF BIRTH', 'জন্ম তারিখ'), isRequired: true),
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _pickDob,
                    child: InputDecorator(
                      decoration: AuthShell.dec('', Icons.calendar_month_outlined).copyWith(
                        suffixIcon: const Icon(Icons.expand_more_rounded, color: muted),
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

                  const SizedBox(height: 24),
                  const Divider(height: 1, color: line),
                  const SizedBox(height: 20),
                  _sectionTitle(2, LanguageService.tr('Secure your account', 'অ্যাকাউন্ট সুরক্ষিত করুন')),
                  const SizedBox(height: 16),

                  // ─── Password ───
                  AuthShell.label(LanguageService.tr('CREATE PASSWORD', 'পাসওয়ার্ড তৈরি করুন'), isRequired: true),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: AuthShell.dec(LanguageService.tr('Min. 6 characters', 'কমপক্ষে ৬ অক্ষর'), Icons.lock_outline)
                        .copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_isPasswordVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: muted, size: 20),
                        onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                      ),
                    ),
                    validator: _passwordValidator,
                  ),
                  const SizedBox(height: 8),
                  _hint(pw.length >= 6, LanguageService.tr('At least 6 characters', 'কমপক্ষে ৬ অক্ষর')),
                  const SizedBox(height: 16),

                  // ─── Confirm ───
                  AuthShell.label(LanguageService.tr('CONFIRM PASSWORD', 'পাসওয়ার্ড নিশ্চিত করুন'), isRequired: true),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: !_isConfirmPasswordVisible,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _isLoading ? null : _handleRegister(),
                    decoration: AuthShell.dec(LanguageService.tr('Re-enter your password', 'আবার পাসওয়ার্ড লিখুন'),
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
                  const SizedBox(height: 8),
                  _hint(cpw.isNotEmpty && cpw == pw, LanguageService.tr('Passwords match', 'পাসওয়ার্ড মিলেছে')),
                  const SizedBox(height: 20),

                  // ─── Note + terms (website er motoi, checkbox chara) ───
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: emeraldSoft.withAlpha(150),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(Icons.info_outline_rounded, size: 17, color: emerald),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: const TextStyle(fontSize: 12, color: ink, height: 1.55),
                              children: [
                                TextSpan(
                                    text: LanguageService.tr(
                                        'You can add your NID, address and nominee later from your profile. By registering, you agree to Biniyog Club\'s ',
                                        'এনআইডি, ঠিকানা ও নমিনী পরে প্রোফাইল থেকে যোগ করতে পারবেন। রেজিস্টার করে আপনি বিনিয়োগ ক্লাবের ')),
                                TextSpan(
                                  text: LanguageService.tr('Terms of Service', 'শর্তাবলী'),
                                  style: const TextStyle(
                                      color: emerald, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                                  recognizer: _termsTap,
                                ),
                                TextSpan(text: LanguageService.tr(' and ', ' ও ')),
                                TextSpan(
                                  text: LanguageService.tr('Privacy Policy', 'প্রাইভেসি পলিসি'),
                                  style: const TextStyle(
                                      color: emerald, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                                  recognizer: _privacyTap,
                                ),
                                TextSpan(text: LanguageService.tr('.', ' মেনে নিচ্ছেন।')),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_formError != null) ...[
                    const SizedBox(height: 14),
                    AuthShell.errorBox(_formError!),
                  ],
                  const SizedBox(height: 20),
                  AuthShell.primaryButton(
                    text: LanguageService.tr('Create Free Investor Account', 'ফ্রি বিনিয়োগকারী অ্যাকাউন্ট খুলুন'),
                    loading: _isLoading,
                    onPressed: _handleRegister,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Shared ───────────────────────────────────────────────
  Widget _sectionTitle(int step, String text) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFFD9BE8C), gold]),
            shape: BoxShape.circle,
          ),
          child: Text('$step',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        const SizedBox(width: 10),
        Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
      ],
    );
  }

  Widget _hint(bool ok, String text) {
    return Row(
      children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 15, color: ok ? emerald : muted.withAlpha(140)),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(fontSize: 11.5, color: ok ? emerald : muted, fontWeight: ok ? FontWeight.w700 : FontWeight.w500)),
      ],
    );
  }
}