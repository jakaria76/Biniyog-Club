import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import '../kyc/kyc_page.dart';
import 'privacy_policy_page.dart';
import 'terms_and_conditions_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isLoading = true;
  String _userId = '';

  bool _pushNotifications = true;
  bool _emailAlerts = true;

  final Map<String, dynamic> _payoutAccount = {
    'bankName': 'One Bank',
    'bankAccountNumber': '4444555566',
    'mobileProvider': 'bKash',
    'mobileNumber': '01754225684',
  };

  static const Color primaryTeal = Color(0xFF047857);

  @override
  void initState() {
    super.initState();
    _loadSettingsData();
  }

  Future<void> _loadSettingsData() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    _pushNotifications = prefs.getBool('push_notifications') ?? true;
    _emailAlerts = prefs.getBool('email_alerts') ?? true;

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    final userEmail = userData?['email']?.toString() ?? '';

    final profileData =
        await DatabaseService.getUserProfileFull(userId, email: userEmail);

    if (mounted) {
      setState(() {
        if (profileData.isNotEmpty) {
          _userId = profileData['id']?.toString() ?? userId;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _saveNotificationPref(String key, bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, val);
  }

  // Delete Account Confirmation Dialog
  void _showDeleteAccountDialog() {
    final passwordController = TextEditingController();
    bool isPasswordVisible = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.redAccent, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      LanguageService.tr('Delete Account', 'অ্যাকাউন্ট ডিলিট করুন'),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LanguageService.tr(
                          'Are you sure you want to request account deletion? Your account will be scheduled for deletion in 7 days.',
                          'আপনি কি নিশ্চিত যে আপনি আপনার অ্যাকাউন্ট ডিলিট করতে চান? আগামী ৭ দিনের জন্য ডিলেশন শিডিউল করা হবে।'),
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey[800],
                          height: 1.4),
                    ),
                    const SizedBox(height: 10),

                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Text(
                        LanguageService.tr(
                            'Note: Logging into your account within 7 days will automatically cancel deletion and restore your account.',
                            'নোট: আগামী ৭ দিনের মধ্যে লগইন করলে আপনার অ্যাকাউন্ট রিস্টোর বা পুনরুদ্ধার হয়ে যাবে।'),
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber.shade900,
                            height: 1.3),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Confirm Password Input
                    TextField(
                      controller: passwordController,
                      obscureText: !isPasswordVisible,
                      decoration: InputDecoration(
                        labelText: LanguageService.tr(
                            'Enter your password', 'আপনার পাসওয়ার্ড দিন'),
                        prefixIcon:
                            const Icon(Icons.lock_outline, color: Colors.redAccent),
                        suffixIcon: IconButton(
                          icon: Icon(
                            isPasswordVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setDialogState(
                              () => isPasswordVisible = !isPasswordVisible),
                        ),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(LanguageService.tr('Cancel', 'বাতিল'),
                      style: const TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final pass = passwordController.text.trim();
                    if (pass.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(LanguageService.tr(
                              'Please enter your password to confirm.',
                              'কনফার্ম করতে আপনার পাসওয়ার্ড প্রদান করুন।')),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                      return;
                    }

                    final res = await DatabaseService.requestAccountDeletion(
                      userId: _userId,
                      password: pass,
                    );

                    if (!context.mounted) return;
                    Navigator.pop(context); // Close dialog

                    if (res['success'] == true) {
                      // Automatically logout user and redirect to LoginPage
                      await AuthService.logout();

                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(LanguageService.tr(
                              'Account deletion requested! Log in within 7 days to restore.',
                              'অ্যাকাউন্ট ডিলিট রিকোয়েস্ট গৃহীত হয়েছে! ৭ দিনের মধ্যে লগইন করলে অ্যাকাউন্ট রিস্টোর হবে।')),
                          backgroundColor: primaryTeal,
                          duration: const Duration(seconds: 4),
                        ),
                      );

                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const LoginPage()),
                        (route) => false,
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(res['message'] ?? 'Deletion failed.'),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(LanguageService.tr('Delete Account', 'অ্যাকাউন্ট ডিলিট করুন')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Change Password Modal
  void _showChangePasswordModal() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    bool isCurrentVisible = false;
    bool isNewVisible = false;
    bool isConfirmVisible = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 24,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        LanguageService.tr('Change Password', 'পাসওয়ার্ড পরিবর্তন'),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Current Password
                  TextField(
                    controller: currentPasswordController,
                    obscureText: !isCurrentVisible,
                    decoration: InputDecoration(
                      labelText: LanguageService.tr(
                          'Current Password', 'বর্তমান পাসওয়ার্ড'),
                      prefixIcon: const Icon(Icons.lock_outline, color: primaryTeal),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isCurrentVisible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setModalState(
                            () => isCurrentVisible = !isCurrentVisible),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // New Password
                  TextField(
                    controller: newPasswordController,
                    obscureText: !isNewVisible,
                    decoration: InputDecoration(
                      labelText:
                          LanguageService.tr('New Password', 'নতুন পাসওয়ার্ড'),
                      prefixIcon: const Icon(Icons.lock_outline, color: primaryTeal),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isNewVisible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () =>
                            setModalState(() => isNewVisible = !isNewVisible),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Confirm New Password
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: !isConfirmVisible,
                    decoration: InputDecoration(
                      labelText: LanguageService.tr(
                          'Confirm New Password', 'পাসওয়ার্ড নিশ্চিত করুন'),
                      prefixIcon: const Icon(Icons.lock_outline, color: primaryTeal),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isConfirmVisible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setModalState(
                            () => isConfirmVisible = !isConfirmVisible),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: () async {
                      final currentPass =
                          currentPasswordController.text.trim();
                      final newPass = newPasswordController.text.trim();
                      final confirmPass =
                          confirmPasswordController.text.trim();

                      if (currentPass.isEmpty || newPass.length < 6) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(LanguageService.tr(
                                'Password must be at least 6 characters.',
                                'পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের হতে হবে।')),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }

                      if (newPass != confirmPass) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(LanguageService.tr(
                                'Passwords do not match.',
                                'পাসওয়ার্ড দুটি মিলছে না।')),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }

                      final res = await DatabaseService.changePassword(
                        userId: _userId,
                        oldPassword: currentPass,
                        newPassword: newPass,
                      );

                      if (!context.mounted) return;
                      Navigator.pop(context);

                      if (res['success'] == true) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(LanguageService.tr(
                                'Password updated successfully!',
                                'পাসওয়ার্ড সফলভাবে পরিবর্তিত হয়েছে!')),
                            backgroundColor: primaryTeal,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(res['message'] ?? 'Error'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryTeal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      LanguageService.tr('Update Password', 'পাসওয়ার্ড পরিবর্তন করুন'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, currentLang, child) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F7F6),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.5,
            iconTheme: const IconThemeData(color: primaryTeal),
            title: Text(
              LanguageService.tr('Settings', 'সেটিংস'),
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: primaryTeal))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LanguageService.tr('App preferences and account settings',
                            'অ্যাপ পছন্দসমূহ এবং অ্যাকাউন্ট সেটিংস'),
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),

                      // 1. Language Preference Section
                      _buildLanguageSelectorCard(),
                      const SizedBox(height: 16),

                      // 2. Security & Password Section
                      _buildSecuritySectionCard(),
                      const SizedBox(height: 16),

                      // 3. Notifications Preference Section
                      _buildNotificationsSectionCard(),
                      const SizedBox(height: 16),

                      // 4. Saved Payout Bank Accounts Section
                      _buildPayoutAccountsCard(),
                      const SizedBox(height: 16),

                      // 5. Legal & Policies Section
                      _buildLegalSectionCard(),
                      const SizedBox(height: 16),

                      // 6. Danger Zone Section (Account Deletion)
                      _buildDangerZoneCard(),
                      const SizedBox(height: 20),

                      // 7. App Info Card
                      _buildAppInfoCard(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
        );
      },
    );
  }

  // Language Selector Card
  Widget _buildLanguageSelectorCard() {
    final bool isBangla = LanguageService.isBangla;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.language_rounded, color: primaryTeal, size: 20),
              SizedBox(width: 8),
              Text(
                'Language / ভাষা',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('English (US)'),
                  selected: !isBangla,
                  selectedColor: primaryTeal,
                  labelStyle: TextStyle(
                    color: !isBangla ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      LanguageService.setLanguage('en');
                      setState(() {});
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  label: const Text('বাংলা (Bangla)'),
                  selected: isBangla,
                  selectedColor: primaryTeal,
                  labelStyle: TextStyle(
                    color: isBangla ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      LanguageService.setLanguage('bn');
                      setState(() {});
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Security Section Card
  Widget _buildSecuritySectionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LanguageService.tr('Security & Authentication', 'নিরাপত্তা ও অথেন্টিকেশন'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_reset_rounded, color: primaryTeal),
            ),
            title: Text(
              LanguageService.tr('Change Password', 'পাসওয়ার্ড পরিবর্তন'),
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              LanguageService.tr(
                  'Update your account password', 'আপনার অ্যাকাউন্ট পাসওয়ার্ড আপডেট করুন'),
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            onTap: _showChangePasswordModal,
          ),
        ],
      ),
    );
  }

  // Notifications Preference Section
  Widget _buildNotificationsSectionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LanguageService.tr('Notification Preferences', 'নোটিফিকেশন পছন্দসমূহ'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: primaryTeal,
            title: Text(
              LanguageService.tr('Push Notifications', 'পুশ নোটিফিকেশন'),
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              LanguageService.tr('Receive instant alerts for project updates & returns',
                  'প্রজেক্ট আপডেট ও রিটার্নের তাৎক্ষণিক অ্যালার্ট পাবেন'),
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            value: _pushNotifications,
            onChanged: (val) {
              setState(() => _pushNotifications = val);
              _saveNotificationPref('push_notifications', val);
            },
          ),
          const Divider(height: 1),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: primaryTeal,
            title: Text(
              LanguageService.tr('Email Alerts', 'ইমেইল অ্যালার্ট'),
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              LanguageService.tr('Receive investment receipts & distribution statements via email',
                  'বিনিয়োগ রশিদ ও লভ্যাংশ স্টেটমেন্ট ইমেইলে পাবেন'),
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            value: _emailAlerts,
            onChanged: (val) {
              setState(() => _emailAlerts = val);
              _saveNotificationPref('email_alerts', val);
            },
          ),
        ],
      ),
    );
  }

  // Saved Payout Bank Accounts Section
  Widget _buildPayoutAccountsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                LanguageService.tr('Saved Payout Accounts', 'সংরক্ষিত পেআউট ব্যাংক অ্যাকাউন্ট'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const KycPage()),
                  );
                },
                child: Text(
                  LanguageService.tr('Update via KYC', 'KYC-তে আপডেট'),
                  style: const TextStyle(color: primaryTeal, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_rounded,
                    color: primaryTeal, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _payoutAccount['bankName'] as String,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Acc: ${_payoutAccount['bankAccountNumber']}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Legal & Policies Section
  Widget _buildLegalSectionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LanguageService.tr('Legal & Compliance', 'আইনি ও নীতিমালা'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          _buildLegalTile(
            LanguageService.tr('Terms & Conditions', 'ব্যবহারের শর্তাবলী'),
            Icons.description_outlined,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const TermsAndConditionsPage()),
              );
            },
          ),
          const Divider(height: 1),
          _buildLegalTile(
            LanguageService.tr('Privacy Policy', 'প্রাইভেসী পলিসি'),
            Icons.privacy_tip_outlined,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const PrivacyPolicyPage()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLegalTile(String title, IconData icon, {VoidCallback? onTap}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: primaryTeal, size: 20),
      title: Text(title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: onTap,
    );
  }

  // Danger Zone Section (Account Deletion)
  Widget _buildDangerZoneCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.redAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                LanguageService.tr('Danger Zone', 'ডেঞ্জার জোন'),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 12),

          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_forever_rounded,
                  color: Colors.redAccent),
            ),
            title: Text(
              LanguageService.tr('Delete Account', 'অ্যাকাউন্ট ডিলিট করুন'),
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent),
            ),
            subtitle: Text(
              LanguageService.tr(
                  'Schedule account deletion (7-day recovery buffer)',
                  'অ্যাকাউন্ট ডিলিট করুন (৭ দিনের রিকভারি সময় পাবেন)'),
              style: TextStyle(fontSize: 11, color: Colors.red.shade900),
            ),
            trailing:
                const Icon(Icons.chevron_right_rounded, color: Colors.redAccent),
            onTap: _showDeleteAccountDialog,
          ),
        ],
      ),
    );
  }

  // App Info Card
  Widget _buildAppInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Image.asset(
            'assets/images/logo_full.png',
            height: 36,
            errorBuilder: (context, error, stackTrace) => const Text(
              'Biniyog Club',
              style: TextStyle(
                  color: primaryTeal,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Version 1.0.0 (Production)',
            style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(LanguageService.tr(
                      'You are using the latest version!',
                      'আপনি সর্বাধুনিক ভার্সনটি ব্যবহার করছেন!')),
                  backgroundColor: primaryTeal,
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: primaryTeal,
              side: const BorderSide(color: primaryTeal),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(LanguageService.tr('Check for Updates', 'আপডেট চেক করুন')),
          ),
        ],
      ),
    );
  }
}
