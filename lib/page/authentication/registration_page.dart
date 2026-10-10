import 'package:flutter/material.dart';
import '../../screens/home_screen.dart';
import '../../services/auth_service.dart';
import '../../services/language_service.dart';
import 'login_page.dart';
import 'widgets/auth_card.dart';
import 'widgets/quote_banner.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nidController = TextEditingController();
  final _nomineeNidController = TextEditingController();
  final _nomineeRelationController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _agreeToTerms = false;
  bool _isLoading = false;

  static const Color primaryTeal = Color(0xFF047857);

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _nidController.dispose();
    _nomineeNidController.dispose();
    _nomineeRelationController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleRegister() async {
    if (_formKey.currentState!.validate()) {
      if (!_agreeToTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LanguageService.tr(
                'Please accept the Terms of Service & Privacy Policy to register.',
                'রেজিস্ট্রেশনের জন্য ব্যবহার বিধি মেনে নিতে টিক চিহ্ন দিন।')),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      setState(() => _isLoading = true);

      final result = await AuthService.register(
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text.trim(),
        nidNumber: _nidController.text.trim(),
        nomineeNidNumber: _nomineeNidController.text.trim(),
        nomineeRelation: _nomineeRelationController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LanguageService.tr(
                'Account created successfully! Welcome to Biniyog Club.',
                'অ্যাকাউন্ট সফলভাবে তৈরি হয়েছে! বিনোয়োগ ক্লাবে আপনাকে স্বাগতম।')),
            backgroundColor: primaryTeal,
          ),
        );

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Registration failed'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F7F6),
          body: SafeArea(
            child: SingleChildScrollView(
              child: AuthCard(
                title: LanguageService.tr('Create your account', 'অ্যাকাউন্ট খুলুন'),
                description: LanguageService.tr(
                    "Join Bangladesh's leading investment platform",
                    'বাংলাদেশের শীর্ষস্থানীয় ইনভেস্টমেন্ট প্ল্যাটফর্মে যুক্ত হোন'),
                quoteBanner: const QuoteBanner(
                  quote:
                      'Track every taka in real time. Our double-entry ledger ensures your funds are always accounted for.',
                  quoteAuthor: 'Biniyog Club',
                ),
                footer: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      LanguageService.tr(
                          'Already have an account? ', 'পূর্বেই অ্যাকাউন্ট আছে? '),
                      style: TextStyle(color: Colors.grey[700], fontSize: 13.5),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LoginPage(),
                          ),
                        );
                      },
                      child: Text(
                        LanguageService.tr('Sign in', 'সাইন ইন'),
                        style: const TextStyle(
                          color: primaryTeal,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
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
                      // 1. FULL NAME *
                      TextFormField(
                        controller: _fullNameController,
                        decoration: _buildInputDecoration(
                          label: LanguageService.tr('FULL NAME *', 'পূর্ণ নাম *'),
                          hint: 'Mohammad Arif',
                          icon: Icons.person_outline,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your full name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // 2. EMAIL ADDRESS *
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _buildInputDecoration(
                          label: LanguageService.tr('EMAIL ADDRESS *', 'ইমেইল ঠিকানা *'),
                          hint: 'investor@example.com',
                          icon: Icons.email_outlined,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your email address';
                          }
                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                              .hasMatch(value.trim())) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // 3. PHONE NUMBER *
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: _buildInputDecoration(
                          label: LanguageService.tr('PHONE NUMBER *', 'ফোন নম্বর *'),
                          hint: '01712345678',
                          icon: Icons.phone_outlined,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your phone number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // 4. NID NUMBER *
                      TextFormField(
                        controller: _nidController,
                        keyboardType: TextInputType.number,
                        decoration: _buildInputDecoration(
                          label: LanguageService.tr('NID NUMBER *', 'এনআইডি নম্বর *'),
                          hint: '10 or 17 digit NID number',
                          icon: Icons.badge_outlined,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your NID number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // 5. NOMINEE DETAILS ACCENT BOX (Exact Website Matching 1:1!)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.person_pin_outlined,
                                    color: Color(0xFFD97706), size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  LanguageService.tr('NOMINEE DETAILS', 'নমিনীর বিবরণ'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFB45309),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              LanguageService.tr(
                                  'Your nominee will receive your investment in case of an emergency.',
                                  'জরুরী পরিস্থিতিতে আপনার ইনভেস্টমেন্ট আপনার মনোনীত ব্যক্তি পাবেন।'),
                              style: TextStyle(
                                  fontSize: 10.5, color: Colors.grey[700]),
                            ),
                            const SizedBox(height: 12),

                            // Nominee NID Number *
                            TextFormField(
                              controller: _nomineeNidController,
                              keyboardType: TextInputType.number,
                              decoration: _buildInputDecoration(
                                label: LanguageService.tr('NOMINEE NID NUMBER *', 'নমিনীর এনআইডি নম্বর *'),
                                hint: "Nominee's NID number",
                                icon: Icons.badge_outlined,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter nominee NID number';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),

                            // Relation with Nominee *
                            TextFormField(
                              controller: _nomineeRelationController,
                              decoration: _buildInputDecoration(
                                label: LanguageService.tr('RELATION WITH NOMINEE *', 'নমিনীর সাথে সম্পর্ক *'),
                                hint: 'e.g. Father, Mother, Spouse',
                                icon: Icons.family_restroom_outlined,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter relationship with nominee';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 6. CREATE PASSWORD *
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        decoration: _buildInputDecoration(
                          label: LanguageService.tr('CREATE PASSWORD *', 'পাসওয়ার্ড *'),
                          hint: 'Min. 8 characters',
                          icon: Icons.lock_outline,
                          suffix: IconButton(
                            icon: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey[600],
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // 7. CONFIRM PASSWORD *
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: !_isConfirmPasswordVisible,
                        decoration: _buildInputDecoration(
                          label: LanguageService.tr('CONFIRM PASSWORD *', 'পাসওয়ার্ড নিশ্চিত করুন *'),
                          hint: 'Repeat password',
                          icon: Icons.lock_reset_outlined,
                          suffix: IconButton(
                            icon: Icon(
                              _isConfirmPasswordVisible
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey[600],
                            ),
                            onPressed: () {
                              setState(() {
                                _isConfirmPasswordVisible =
                                    !_isConfirmPasswordVisible;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (value != _passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Terms Agreement Checkbox
                      Row(
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: _agreeToTerms,
                              activeColor: primaryTeal,
                              onChanged: (bool? value) {
                                setState(() {
                                  _agreeToTerms = value ?? false;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              LanguageService.tr(
                                  'By registering, you agree to Biniyog Club\'s Terms of Service and Privacy Policy.',
                                  'রেজিস্ট্রেশনের মাধ্যমে আপনি বিয়োগ ক্লাবের ব্যবহারের শর্তাবলী ও প্রাইভেসী পলিসি মেনে নিচ্ছেন।'),
                              style:
                                  TextStyle(fontSize: 11.5, color: Colors.grey[700]),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Register Button
                      ElevatedButton(
                        onPressed: _isLoading ? null : _handleRegister,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 1,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                '${LanguageService.tr("Create Free Investor Account", "ফ্রি ইনভেস্টর অ্যাকাউন্ট তৈরি করুন")} →',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
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

  InputDecoration _buildInputDecoration({
    required String label,
    required String hint,
    IconData? icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
      hintText: hint,
      prefixIcon:
          icon != null ? Icon(icon, color: primaryTeal, size: 20) : null,
      suffixIcon: suffix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryTeal, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
