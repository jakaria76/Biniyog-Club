import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../screens/home_screen.dart';
import '../../services/auth_service.dart';
import '../../services/bd_location_service.dart';
import '../../services/database_service.dart';
import '../../services/language_service.dart';
import '../investor/settings/legal_web_page.dart';
import 'login_page.dart';
import 'widgets/auth_card.dart';
import 'widgets/quote_banner.dart';

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
  static const Color goldSoft = Color(0xFFF6EEDF);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);
  static const Color danger = Color(0xFFB4413A);

  /// Nominee er sathe sompork — DB te English e jay (website er sathe mile)
  static const List<(String, String)> relations = [
    ('Father', 'বাবা'),
    ('Mother', 'মা'),
    ('Spouse', 'স্বামী/স্ত্রী'),
    ('Son', 'ছেলে'),
    ('Daughter', 'মেয়ে'),
    ('Brother', 'ভাই'),
    ('Sister', 'বোন'),
    ('Other', 'অন্যান্য'),
  ];

  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nidController = TextEditingController();
  // Thikana: basha/rasta + bibhag → jela → upazila (+ post code)
  final _addressController = TextEditingController();
  final _otherAreaController = TextEditingController();
  final _postCodeController = TextEditingController();
  String? _division;
  String? _district;
  String? _upazila; // _otherKey = list e nei, nije likhbe
  static const String _otherKey = '__other__';
  final _nomineeNidController = TextEditingController();
  DateTime? _dob;
  bool _dobError = false;
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _nomineeRelation;

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _agreeToTerms = false;
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
    _emailController.dispose();
    _phoneController.dispose();
    _nidController.dispose();
    _addressController.dispose();
    _otherAreaController.dispose();
    _postCodeController.dispose();
    _nomineeNidController.dispose();
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
  // VALIDATION (Bangladesh er niyom)
  // ═════════════════════════════════════════════════════════
  String get _req => LanguageService.tr('Required', 'আবশ্যক');

  String _cleanPhone(String v) => v.replaceAll(RegExp(r'[\s-]'), '').replaceFirst(RegExp(r'^\+?88'), '');

  String? _nidValidator(String? v, {bool nominee = false}) {
    final t = (v ?? '').trim();
    // Nominee optional — khali thakle thik ache
    if (t.isEmpty) return nominee ? null : _req;
    if (!RegExp(r'^(\d{10}|\d{13}|\d{17})$').hasMatch(t)) {
      return LanguageService.tr('NID must be 10, 13 or 17 digits', 'এনআইডি ১০, ১৩ বা ১৭ সংখ্যার হতে হবে');
    }
    if (nominee && t == _nidController.text.trim()) {
      return LanguageService.tr('Nominee NID cannot be your own NID', 'নমিনীর এনআইডি আপনার নিজের হতে পারবে না');
    }
    return null;
  }

  String _fmtDob(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// DB te ek line e: "Basha 12, Road 5, Mirpur, Dhaka, Dhaka Division - 1216"
  String _composedAddress() {
    final area = _upazila == _otherKey ? _otherAreaController.text.trim() : (_upazila ?? '');
    final parts = <String>[
      _addressController.text.trim(),
      if (area.isNotEmpty) area,
      if (_district != null) _district!,
      if (_division != null) '${_division!} Division',
    ];
    final post = _postCodeController.text.trim();
    return post.isEmpty ? parts.join(', ') : '${parts.join(', ')} - $post';
  }

  bool _isAdult(DateTime d) {
    final now = DateTime.now();
    return !d.isAfter(DateTime(now.year - 18, now.month, now.day));
  }

  Future<void> _pickDob() async {
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

  Future<void> _handleRegister() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _formError = null;
      _dobError = _dob == null || !_isAdult(_dob!);
    });
    final formOk = _formKey.currentState!.validate();
    if (!formOk || _dobError) {
      if (formOk && _dobError) {
        setState(() => _formError = _dob == null
            ? LanguageService.tr('Please select your date of birth.', 'জন্ম তারিখ বাছাই করুন।')
            : LanguageService.tr('You must be at least 18 years old.', 'বয়স কমপক্ষে ১৮ বছর হতে হবে।'));
      }
      return;
    }

    if (!_agreeToTerms) {
      setState(() => _formError = LanguageService.tr(
          'Please accept the Terms of Service & Privacy Policy to register.',
          'রেজিস্ট্রেশনের জন্য শর্তাবলী ও প্রাইভেসি পলিসিতে সম্মতি দিন।'));
      return;
    }

    setState(() => _isLoading = true);

    final nomineeNid = _nomineeNidController.text.trim();
    final result = await DatabaseService.registerUser(
      name: _fullNameController.text.trim(),
      email: _emailController.text.trim().toLowerCase(),
      phone: _cleanPhone(_phoneController.text.trim()),
      // Password e kono kata-chhata na — ja likheche hubohu tai
      password: _passwordController.text,
      nidNumber: _nidController.text.trim(),
      dateOfBirth: _dob!,
      address: _composedAddress(),
      city: _district,
      nomineeNidNumber: nomineeNid,
      nomineeRelation: nomineeNid.isEmpty ? '' : (_nomineeRelation ?? ''),
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
          content: Text(LanguageService.tr('Account created! Welcome to Biniyog Club.',
              'অ্যাকাউন্ট তৈরি হয়েছে! বিনিয়োগ ক্লাবে আপনাকে স্বাগতম।')),
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
                      TextFormField(
                        controller: _fullNameController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: _dec(LanguageService.tr('Full name (as on NID) *', 'পূর্ণ নাম (এনআইডি অনুযায়ী) *'),
                            Icons.person_outline),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return _req;
                          if (t.length < 3) return LanguageService.tr('Name is too short', 'নাম খুব ছোট');
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: _dec(LanguageService.tr('Email address *', 'ইমেইল ঠিকানা *'), Icons.email_outlined),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return _req;
                          if (!RegExp(r'^[\w.+-]+@([\w-]+\.)+[A-Za-z]{2,}$').hasMatch(t)) {
                            return LanguageService.tr('Enter a valid email address', 'সঠিক ইমেইল দিন');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: _dec(LanguageService.tr('Mobile number *', 'মোবাইল নম্বর *'), Icons.phone_outlined)
                            .copyWith(hintText: '01XXXXXXXXX'),
                        validator: (v) {
                          final t = _cleanPhone((v ?? '').trim());
                          if (t.isEmpty) return _req;
                          if (!RegExp(r'^01[3-9]\d{8}$').hasMatch(t)) {
                            return LanguageService.tr('Enter a valid number (01XXXXXXXXX)', 'সঠিক নম্বর দিন (01XXXXXXXXX)');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _nidController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(17)],
                        decoration: _dec(LanguageService.tr('Your NID number *', 'আপনার এনআইডি নম্বর *'), Icons.badge_outlined)
                            .copyWith(hintText: LanguageService.tr('10, 13 or 17 digits', '১০, ১৩ বা ১৭ সংখ্যা')),
                        validator: (v) => _nidValidator(v),
                      ),
                      const SizedBox(height: 14),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _pickDob,
                        child: InputDecorator(
                          decoration: _dec(LanguageService.tr('Date of birth *', 'জন্ম তারিখ *'), Icons.cake_outlined)
                              .copyWith(
                            errorText: _dobError
                                ? (_dob == null
                                ? _req
                                : LanguageService.tr('Must be 18 or older', 'বয়স ১৮ বা তার বেশি হতে হবে'))
                                : null,
                            suffixIcon: const Icon(Icons.calendar_month_outlined, color: muted, size: 20),
                          ),
                          child: Text(
                            _dob == null ? LanguageService.tr('Select date', 'তারিখ বাছাই করুন') : _fmtDob(_dob!),
                            style: TextStyle(fontSize: 14, color: _dob == null ? muted : ink),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildAddressSection(),
                      const SizedBox(height: 16),

                      // ─── Nominee (optional) ───
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: goldSoft,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: gold.withAlpha(90)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.family_restroom_outlined, color: goldDeep, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  LanguageService.tr('NOMINEE (OPTIONAL)', 'নমিনী (ঐচ্ছিক)'),
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w800, color: goldDeep, letterSpacing: 0.8),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              LanguageService.tr(
                                  'The person who receives your investment if something happens to you.',
                                  'আপনার অবর্তমানে যিনি আপনার বিনিয়োগ পাবেন।'),
                              style: const TextStyle(fontSize: 11, color: muted),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _nomineeNidController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(17),
                              ],
                              decoration: _dec(LanguageService.tr('Nominee NID number', 'নমিনীর এনআইডি নম্বর'),
                                  Icons.person_pin_outlined, fill: Colors.white),
                              onChanged: (_) => setState(() {}),
                              validator: (v) => _nidValidator(v, nominee: true),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _nomineeRelation,
                              decoration: _dec(
                                  _nomineeNidController.text.trim().isEmpty
                                      ? LanguageService.tr('Relation with nominee', 'নমিনীর সাথে সম্পর্ক')
                                      : LanguageService.tr('Relation with nominee *', 'নমিনীর সাথে সম্পর্ক *'),
                                  Icons.people_outline,
                                  fill: Colors.white),
                              items: relations
                                  .map((r) => DropdownMenuItem(
                                value: r.$1,
                                child: Text(LanguageService.tr(r.$1, r.$2),
                                    style: const TextStyle(fontSize: 13.5)),
                              ))
                                  .toList(),
                              onChanged: (v) => setState(() => _nomineeRelation = v),
                              // NID dile tobei sompork lagbe
                              validator: (v) =>
                              v == null && _nomineeNidController.text.trim().isNotEmpty ? _req : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        textInputAction: TextInputAction.next,
                        decoration: _dec(LanguageService.tr('Create password *', 'পাসওয়ার্ড *'), Icons.lock_outline)
                            .copyWith(
                          hintText: LanguageService.tr('At least 8 characters', 'কমপক্ষে ৮ অক্ষর'),
                          suffixIcon: IconButton(
                            icon: Icon(_isPasswordVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: muted),
                            onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                          ),
                        ),
                        validator: (v) {
                          final t = v ?? '';
                          if (t.isEmpty) return _req;
                          // Label e "8" lekha chilo, kintu check hoto 6 — ekhon 8
                          if (t.length < 8) {
                            return LanguageService.tr('Use at least 8 characters', 'কমপক্ষে ৮ অক্ষর দিন');
                          }
                          if (t != t.trim()) {
                            return LanguageService.tr('Remove spaces at the start or end', 'শুরু বা শেষের স্পেস মুছুন');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: !_isConfirmPasswordVisible,
                        decoration: _dec(LanguageService.tr('Confirm password *', 'পাসওয়ার্ড নিশ্চিত করুন *'),
                            Icons.lock_reset_outlined)
                            .copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                                _isConfirmPasswordVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: muted),
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
                      const SizedBox(height: 12),

                      // ─── Terms (website er ashol page khule) ───
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: _agreeToTerms,
                              activeColor: emerald,
                              onChanged: (v) => setState(() {
                                _agreeToTerms = v ?? false;
                                _formError = null;
                              }),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: const TextStyle(fontSize: 12, color: muted, height: 1.45),
                                children: [
                                  TextSpan(text: LanguageService.tr('I agree to Biniyog Club\'s ', 'আমি বিনিয়োগ ক্লাবের ')),
                                  TextSpan(
                                    text: LanguageService.tr('Terms of Service', 'শর্তাবলী'),
                                    style: const TextStyle(color: emerald, fontWeight: FontWeight.w700),
                                    recognizer: _termsTap,
                                  ),
                                  TextSpan(text: LanguageService.tr(' and ', ' ও ')),
                                  TextSpan(
                                    text: LanguageService.tr('Privacy Policy', 'প্রাইভেসি পলিসি'),
                                    style: const TextStyle(color: emerald, fontWeight: FontWeight.w700),
                                    recognizer: _privacyTap,
                                  ),
                                  TextSpan(text: LanguageService.tr('.', ' মেনে নিচ্ছি।')),
                                ],
                              ),
                            ),
                          ),
                        ],
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
                        height: 52,
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
                              : Text(
                            LanguageService.tr('Create Free Account', 'ফ্রি অ্যাকাউন্ট খুলুন'),
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
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

  // ─── Thikana ──────────────────────────────────────────────
  Widget _buildAddressSection() {
    // DB te English naam, screen e bhasha onujayi
    DropdownMenuItem<String> item(String key) => DropdownMenuItem(
      value: key,
      child: Text(BdLocationService.localize(key),
          overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
    );

    final districts = BdLocationService.districtKeys(_division);
    final upazilas = BdLocationService.upazilaKeys(_division, _district);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.home_outlined, color: goldDeep, size: 18),
              const SizedBox(width: 8),
              Text(
                LanguageService.tr('PRESENT ADDRESS *', 'বর্তমান ঠিকানা *'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: goldDeep, letterSpacing: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('reg-division'),
            isExpanded: true,
            initialValue: _division,
            decoration: _dec(LanguageService.tr('Division *', 'বিভাগ *'), Icons.map_outlined),
            items: BdLocationService.divisionKeys().map(item).toList(),
            onChanged: (v) => setState(() {
              _division = v;
              _district = null;
              _upazila = null;
            }),
            validator: (v) => v == null ? _req : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // Bibhag bodlale jela notun kore — key bodle field reset hoy
            key: ValueKey('reg-district-$_division'),
            isExpanded: true,
            initialValue: _district,
            decoration: _dec(LanguageService.tr('District *', 'জেলা *'), Icons.location_city_outlined),
            items: districts.map(item).toList(),
            onChanged: _division == null
                ? null
                : (v) => setState(() {
              _district = v;
              _upazila = null;
            }),
            validator: (v) => v == null ? _req : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('reg-upazila-$_division-$_district'),
            isExpanded: true,
            initialValue: _upazila,
            decoration: _dec(LanguageService.tr('Upazila / Thana *', 'উপজেলা / থানা *'), Icons.place_outlined),
            items: [
              ...upazilas.map(item),
              // Shob thana list e nei — tai nije likhar upay
              DropdownMenuItem(
                value: _otherKey,
                child: Text(LanguageService.tr('Other (type it)', 'অন্যান্য (লিখে দিন)'),
                    style: const TextStyle(fontSize: 13.5, color: goldDeep, fontWeight: FontWeight.w600)),
              ),
            ],
            onChanged: _district == null ? null : (v) => setState(() => _upazila = v),
            validator: (v) => v == null ? _req : null,
          ),
          if (_upazila == _otherKey) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _otherAreaController,
              textCapitalization: TextCapitalization.words,
              decoration: _dec(LanguageService.tr('Upazila / Thana name *', 'উপজেলা / থানার নাম *'), Icons.edit_location_alt_outlined),
              validator: (v) => (v ?? '').trim().length < 2 ? _req : null,
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _addressController,
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 3,
            decoration: _dec(LanguageService.tr('House / road / village *', 'বাসা / রোড / গ্রাম *'), Icons.signpost_outlined)
                .copyWith(
              hintText: LanguageService.tr('e.g. House 12, Road 5, Block C', 'যেমন: বাসা ১২, রোড ৫, ব্লক সি'),
              alignLabelWithHint: true,
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return _req;
              if (t.length < 4) return LanguageService.tr('Please write your house / road / village', 'বাসা / রোড / গ্রাম লিখুন');
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _postCodeController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            decoration: _dec(LanguageService.tr('Post code (optional)', 'পোস্ট কোড (ঐচ্ছিক)'), Icons.markunread_mailbox_outlined),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return null;
              return t.length == 4 ? null : LanguageService.tr('Post code is 4 digits', 'পোস্ট কোড ৪ সংখ্যার');
            },
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon, {Color fill = ivory}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: muted),
      prefixIcon: Icon(icon, color: goldDeep, size: 20),
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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