import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../authentication/login_page.dart';
import '../../../services/app_lock_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import '../dashboard/investor_dashboard_page.dart';
import 'legal_web_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // ═════════════════════════════════════════════════════════
  // CONTACT + WEBSITE — biniyogclub.com e ja ache, hubohu tai
  // ═════════════════════════════════════════════════════════
  static const String _site = 'https://www.biniyogclub.com';
  static const String _hotlineDisplay = '+880 1335-149033';
  static const String _hotlineTel = 'tel:+8801335149033';
  static const String _supportEmail = 'info@biniyogclub.com';
  static const String _officeAddress = 'MG SAM Center, 12 Mohakhali C/A, Dhaka-1212';

  /// App Play Store e publish hole true koro — tokhon "Update" button dekhabe
  static const bool _publishedOnPlayStore = false;

  // ─── Palette (dashboard er moto) ───
  static const Color emerald = Color(0xFF0E4A37);
  static const Color emeraldDeep = Color(0xFF0A3327);
  static const Color emeraldSoft = Color(0xFFE3F0E9);
  static const Color gold = Color(0xFFB8935A);
  static const Color goldDeep = Color(0xFF8A6A3A);
  static const Color goldLight = Color(0xFFD9BE8C);
  static const Color goldSoft = Color(0xFFF6EEDF);
  static const Color turquoise = Color(0xFF167A80);
  static const Color turquoiseSoft = Color(0xFFE0F1F1);
  static const Color lapis = Color(0xFF26437A);
  static const Color lapisSoft = Color(0xFFE5EAF4);
  static const Color terracotta = Color(0xFFA5523A);
  static const Color terracottaSoft = Color(0xFFF7E6DF);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);
  static const Color danger = Color(0xFFB4413A);
  static const Color dangerSoft = Color(0xFFFBEAE8);

  bool _isLoading = true;
  bool _needsLogin = false;
  bool _checkingDelete = false;

  String _userId = '';
  String _name = 'Investor';
  String _email = '';
  String? _avatarUrl;
  String _phone = '';


  String _version = '';
  String _buildNumber = '';
  String _packageName = '';

  bool _lockSupported = false;
  bool _lockEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettingsData();
  }

  // ═════════════════════════════════════════════════════════
  // DATA
  // ═════════════════════════════════════════════════════════
  Future<void> _loadSettingsData() async {
    if (mounted) setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    final userEmail = userData?['email']?.toString() ?? '';

    if (userId.isEmpty) {
      if (mounted) {
        setState(() {
          _needsLogin = true;
          _isLoading = false;
        });
      }
      return;
    }

    // Ekta jinish fail korleo jeno page atke na thake —
    // protita alada try/catch, fail hole default value
    Future<T> safe<T>(Future<T> Function() task, T fallback) async {
      try {
        return await task();
      } catch (e) {
        debugPrint('Settings load warning: $e');
        return fallback;
      }
    }

    final results = await Future.wait<dynamic>([
      safe<Map<String, dynamic>>(
              () => DatabaseService.getUserProfileFull(userId, email: userEmail), {}),
      safe<PackageInfo?>(() => PackageInfo.fromPlatform(), null),
      safe<bool>(() => AppLockService.isSupported(), false),
      safe<bool>(() => AppLockService.isEnabled(), false),
    ]);

    final profile = results[0] as Map<String, dynamic>;
    final info = results[1] as PackageInfo?;

    if (!mounted) return;
    setState(() {
      _userId = profile['id']?.toString() ?? userId;
      _name = profile['name']?.toString() ?? userData?['name']?.toString() ?? 'Investor';
      _email = profile['email']?.toString() ?? userEmail;
      _phone = profile['phone']?.toString() ?? userData?['phone']?.toString() ?? '';
      _avatarUrl = profile['avatarUrl']?.toString();

      _version = info?.version ?? '';
      _buildNumber = info?.buildNumber ?? '';
      _packageName = info?.packageName ?? '';

      _lockSupported = results[2] as bool;
      _lockEnabled = results[3] as bool;

      _needsLogin = false;
      _isLoading = false;
    });
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? danger : emerald),
    );
  }

  Future<void> _open(String url, {LaunchMode mode = LaunchMode.platformDefault}) async {
    bool ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: mode);
    } catch (e) {
      debugPrint('Launch error: $e');
    }
    if (!ok) {
      _snack(
        LanguageService.tr('Could not open. Please try again.', 'খোলা যায়নি। আবার চেষ্টা করুন।'),
        error: true,
      );
    }
  }

  void _openLegal(String title, String path) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LegalWebPage(title: title, url: '$_site$path')),
    );
  }

  Future<void> _goToLogin() async {
    await AppLockService.setEnabled(false);
    await AuthService.logout();
    InvestorDashboardPage.clearCache();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  InputDecoration _fieldDeco(String label, {Widget? suffix}) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: ivory,
    labelStyle: const TextStyle(color: muted, fontSize: 13),
    prefixIcon: const Icon(Icons.lock_outline_rounded, color: emerald, size: 20),
    suffixIcon: suffix,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: emerald, width: 1.4),
    ),
  );

  Widget _eye(bool visible, VoidCallback onTap) => IconButton(
    icon: Icon(
      visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      color: muted,
      size: 20,
    ),
    onPressed: onTap,
  );

  // ═════════════════════════════════════════════════════════
  // CHANGE PASSWORD
  // ═════════════════════════════════════════════════════════
  void _showChangePasswordModal() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool showCurrent = false, showNew = false, showConfirm = false;
    bool saving = false;
    final pageMessenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            void fail(String msg) {
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(content: Text(msg), backgroundColor: danger),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            LanguageService.tr('Change Password', 'পাসওয়ার্ড পরিবর্তন'),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700, color: ink),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    Text(
                      LanguageService.tr('Use at least 8 characters.',
                          'কমপক্ষে ৮ অক্ষরের পাসওয়ার্ড দিন।'),
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: currentCtrl,
                      obscureText: !showCurrent,
                      decoration: _fieldDeco(
                        LanguageService.tr('Current Password', 'বর্তমান পাসওয়ার্ড'),
                        suffix: _eye(showCurrent,
                                () => setModalState(() => showCurrent = !showCurrent)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newCtrl,
                      obscureText: !showNew,
                      decoration: _fieldDeco(
                        LanguageService.tr('New Password', 'নতুন পাসওয়ার্ড'),
                        suffix: _eye(showNew, () => setModalState(() => showNew = !showNew)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmCtrl,
                      obscureText: !showConfirm,
                      decoration: _fieldDeco(
                        LanguageService.tr('Confirm New Password', 'নতুন পাসওয়ার্ড আবার দিন'),
                        suffix: _eye(showConfirm,
                                () => setModalState(() => showConfirm = !showConfirm)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                        // Password e space thakte pare — trim kora hoy na
                        final current = currentCtrl.text;
                        final next = newCtrl.text;
                        final confirm = confirmCtrl.text;

                        if (current.isEmpty) {
                          fail(LanguageService.tr('Enter your current password.',
                              'বর্তমান পাসওয়ার্ড দিন।'));
                          return;
                        }
                        if (next.length < 8) {
                          fail(LanguageService.tr(
                              'New password must be at least 8 characters.',
                              'নতুন পাসওয়ার্ড কমপক্ষে ৮ অক্ষরের হতে হবে।'));
                          return;
                        }
                        if (next == current) {
                          fail(LanguageService.tr(
                              'New password must be different from the current one.',
                              'নতুন পাসওয়ার্ড বর্তমানটির থেকে আলাদা হতে হবে।'));
                          return;
                        }
                        if (next != confirm) {
                          fail(LanguageService.tr(
                              'Passwords do not match.', 'পাসওয়ার্ড দুটি মিলছে না।'));
                          return;
                        }

                        setModalState(() => saving = true);
                        final res = await DatabaseService.changePassword(
                          userId: _userId,
                          oldPassword: current,
                          newPassword: next,
                        );

                        if (!sheetContext.mounted) return;

                        if (res['success'] == true) {
                          Navigator.pop(sheetContext);
                          pageMessenger.showSnackBar(
                            SnackBar(
                              content: Text(LanguageService.tr(
                                  'Password updated successfully!',
                                  'পাসওয়ার্ড সফলভাবে পরিবর্তিত হয়েছে!')),
                              backgroundColor: emerald,
                            ),
                          );
                        } else {
                          // Sheet khola thake — bhul password abar dite parbe
                          setModalState(() => saving = false);
                          fail(res['message']?.toString() ?? 'Error');
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: emerald,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: saving
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                          : Text(
                        LanguageService.tr('Update Password', 'পাসওয়ার্ড আপডেট করুন'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ═════════════════════════════════════════════════════════
  // APP LOCK
  // ═════════════════════════════════════════════════════════
  Future<void> _toggleAppLock(bool value) async {
    final ok = await AppLockService.authenticate(
      value
          ? LanguageService.tr('Confirm to turn on app lock', 'অ্যাপ লক চালু করতে নিশ্চিত করুন')
          : LanguageService.tr('Confirm to turn off app lock', 'অ্যাপ লক বন্ধ করতে নিশ্চিত করুন'),
    );
    if (!ok) {
      _snack(LanguageService.tr('Verification failed.', 'যাচাই করা যায়নি।'), error: true);
      return;
    }
    await AppLockService.setEnabled(value);
    if (mounted) setState(() => _lockEnabled = value);
    _snack(value
        ? LanguageService.tr('App lock is on.', 'অ্যাপ লক চালু হয়েছে।')
        : LanguageService.tr('App lock is off.', 'অ্যাপ লক বন্ধ হয়েছে।'));
  }

  // ═════════════════════════════════════════════════════════
  // SIGN OUT
  // ═════════════════════════════════════════════════════════
  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          LanguageService.tr('Sign out', 'সাইন আউট'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ink),
        ),
        content: Text(
          LanguageService.tr(
              'Are you sure you want to sign out of your Biniyog Club account?',
              'আপনি কি নিশ্চিত যে অ্যাকাউন্ট থেকে সাইন আউট করতে চান?'),
          style: const TextStyle(fontSize: 13.5, color: muted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(LanguageService.tr('Cancel', 'বাতিল'),
                style: const TextStyle(color: muted, fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _goToLogin();
            },
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(LanguageService.tr('Sign out', 'সাইন আউট')),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // DELETE ACCOUNT
  // Age check kori: chalu ba pending investment thakle delete na.
  // ═════════════════════════════════════════════════════════
  Future<void> _startDeleteFlow() async {
    setState(() => _checkingDelete = true);
    final summary = await DatabaseService.getOpenInvestmentSummary(_userId);
    if (!mounted) return;
    setState(() => _checkingDelete = false);

    if (summary['ok'] != true) {
      _snack(
        LanguageService.tr('Could not reach the server. Please check your internet connection.',
            'সার্ভারে সংযোগ করা যায়নি। ইন্টারনেট সংযোগ চেক করুন।'),
        error: true,
      );
      return;
    }

    if ((summary['totalOpen'] as int) > 0) {
      _showDeleteBlockedDialog(summary['projectOpen'] as int, summary['groupOpen'] as int);
      return;
    }

    _showDeleteAccountDialog();
  }

  void _showDeleteBlockedDialog(int projectOpen, int groupOpen) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: goldDeep, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                LanguageService.tr('Account can’t be deleted yet', 'এখন অ্যাকাউন্ট ডিলিট করা যাবে না'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LanguageService.tr(
                  'You still have active or pending investments. Your money and returns are linked to this account, so it can’t be deleted until they are settled.',
                  'আপনার এখনো চলমান বা অপেক্ষমান বিনিয়োগ আছে। আপনার টাকা ও লভ্যাংশ এই অ্যাকাউন্টের সাথে যুক্ত, তাই সেগুলো নিষ্পত্তি না হওয়া পর্যন্ত অ্যাকাউন্ট ডিলিট করা যাবে না।'),
              style: const TextStyle(fontSize: 13, color: muted, height: 1.45),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: goldSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (projectOpen > 0)
                    Text(
                      LanguageService.tr('Project investments: $projectOpen',
                          'প্রজেক্ট বিনিয়োগ: $projectOpen টি'),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: goldDeep),
                    ),
                  if (groupOpen > 0)
                    Text(
                      LanguageService.tr('Group investments: $groupOpen',
                          'গ্রুপ বিনিয়োগ: $groupOpen টি'),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: goldDeep),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(LanguageService.tr('Close', 'বন্ধ করুন'),
                style: const TextStyle(color: muted, fontWeight: FontWeight.w600)),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _open(_hotlineTel);
            },
            icon: const Icon(Icons.call_rounded, size: 18),
            label: Text(LanguageService.tr('Call support', 'সাপোর্টে কল করুন')),
            style: FilledButton.styleFrom(
              backgroundColor: emerald,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog() {
    final passwordCtrl = TextEditingController();
    bool visible = false;
    bool deleting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: danger, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      LanguageService.tr('Delete Account', 'অ্যাকাউন্ট ডিলিট করুন'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: danger),
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
                          'Your account will be scheduled for deletion in 30 days.',
                          'আপনার অ্যাকাউন্ট ৩০ দিন পর ডিলিট হওয়ার জন্য শিডিউল করা হবে।'),
                      style: const TextStyle(fontSize: 13, color: ink, height: 1.45),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: goldSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: gold.withAlpha(90)),
                      ),
                      child: Text(
                        LanguageService.tr(
                            'Logging in within 30 days will cancel the deletion and restore your account.',
                            '৩০ দিনের মধ্যে লগইন করলে ডিলিট বাতিল হবে এবং অ্যাকাউন্ট ফিরে পাবেন।'),
                        style: const TextStyle(fontSize: 11.5, color: goldDeep, height: 1.35),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: !visible,
                      decoration: _fieldDeco(
                        LanguageService.tr('Enter your password', 'আপনার পাসওয়ার্ড দিন'),
                        suffix: _eye(visible, () => setDialogState(() => visible = !visible)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: deleting ? null : () => Navigator.pop(dialogContext),
                  child: Text(LanguageService.tr('Cancel', 'বাতিল'),
                      style: const TextStyle(color: muted, fontWeight: FontWeight.w600)),
                ),
                FilledButton(
                  onPressed: deleting
                      ? null
                      : () async {
                    final pass = passwordCtrl.text;
                    if (pass.isEmpty) {
                      _snack(
                        LanguageService.tr('Please enter your password to confirm.',
                            'কনফার্ম করতে পাসওয়ার্ড দিন।'),
                        error: true,
                      );
                      return;
                    }

                    setDialogState(() => deleting = true);
                    final res = await DatabaseService.requestAccountDeletion(
                      userId: _userId,
                      password: pass,
                    );
                    if (!dialogContext.mounted) return;

                    if (res['success'] == true) {
                      Navigator.pop(dialogContext);
                      _snack(LanguageService.tr(
                          'Account deletion requested. Log in within 30 days to restore.',
                          'ডিলিট রিকোয়েস্ট গৃহীত হয়েছে। ৩০ দিনের মধ্যে লগইন করলে অ্যাকাউন্ট ফিরে পাবেন।'));
                      await _goToLogin();
                    } else {
                      setDialogState(() => deleting = false);
                      _snack(res['message']?.toString() ?? 'Deletion failed.', error: true);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: danger,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: deleting
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                      : Text(LanguageService.tr('Delete', 'ডিলিট করুন')),
                ),
              ],
            );
          },
        );
      },
    );
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
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              LanguageService.tr('Settings', 'সেটিংস'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          body: _isLoading
              ? const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4),
            ),
          )
              : _needsLogin
              ? _buildNeedsLogin()
              : RefreshIndicator(
            onRefresh: _loadSettingsData,
            color: emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 40),
              children: [
                _buildProfileCard(),
                const SizedBox(height: 24),
                _sectionHeader(LanguageService.tr('Preferences', 'পছন্দসমূহ')),
                const SizedBox(height: 12),
                _buildLanguageCard(),
                const SizedBox(height: 24),
                _sectionHeader(LanguageService.tr('Security', 'নিরাপত্তা')),
                const SizedBox(height: 12),
                _buildSecurityCard(),
                const SizedBox(height: 24),
                _sectionHeader(LanguageService.tr('Help & Support', 'সাহায্য ও সাপোর্ট')),
                const SizedBox(height: 12),
                _buildSupportCard(),
                const SizedBox(height: 24),
                _sectionHeader(LanguageService.tr('Legal', 'আইনি তথ্য')),
                const SizedBox(height: 12),
                _buildLegalCard(),
                const SizedBox(height: 24),
                _buildSignOutButton(),
                const SizedBox(height: 14),
                _buildDangerCard(),
                const SizedBox(height: 24),
                _buildAppInfo(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Shared pieces ────────────────────────────────────────
  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [goldLight, gold]),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ink,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _divider() => const Divider(height: 1, thickness: 1, color: line, indent: 66);

  Widget _tile({
    required IconData icon,
    required Color color,
    required Color soft,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: soft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11.5, color: muted, height: 1.3),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing]
            else if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: muted.withAlpha(150), size: 22),
          ],
        ),
      ),
    );
  }

  // ─── Profile card ─────────────────────────────────────────
  Widget _buildProfileCard() {
    final initial = _name.isNotEmpty ? _name[0].toUpperCase() : 'I';
    // Email optional — na thakle phone dekhai
    final contact = _email.isNotEmpty ? _email : _phone;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF125A43), emeraldDeep, Color(0xFF0B2A3A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _IslamicPatternPainter(color: Colors.white.withAlpha(16), cell: 44),
              ),
            ),
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: gold.withAlpha(80), width: 0.8),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: gold, width: 1.4),
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: emerald,
                      child: ClipOval(
                        child: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                            ? Image.network(
                          _avatarUrl!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Text(
                            initial,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
                          ),
                        )
                            : Text(
                          initial,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          contact,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Language ─────────────────────────────────────────────
  Widget _buildLanguageCard() {
    final bool isBangla = LanguageService.isBangla;

    Widget option(String label, bool selected, String code) {
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (!selected) {
              LanguageService.setLanguage(code);
              setState(() {});
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? emerald : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : ink,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: lapisSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.translate_rounded, color: lapis, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Language / ভাষা',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: ivory,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                option('English', !isBangla, 'en'),
                option('বাংলা', isBangla, 'bn'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Security ─────────────────────────────────────────────
  Widget _buildSecurityCard() {
    return _card([
      _tile(
        icon: Icons.lock_reset_rounded,
        color: emerald,
        soft: emeraldSoft,
        title: LanguageService.tr('Change Password', 'পাসওয়ার্ড পরিবর্তন'),
        subtitle: LanguageService.tr('Update your account password',
            'আপনার অ্যাকাউন্টের পাসওয়ার্ড বদলান'),
        onTap: _showChangePasswordModal,
      ),
      if (_lockSupported) ...[
        _divider(),
        _tile(
          icon: Icons.fingerprint_rounded,
          color: turquoise,
          soft: turquoiseSoft,
          title: LanguageService.tr('App Lock', 'অ্যাপ লক'),
          subtitle: LanguageService.tr(
              'Ask for fingerprint, face or phone PIN when opening the app',
              'অ্যাপ খুলতে ফিঙ্গারপ্রিন্ট, ফেস বা ফোনের পিন লাগবে'),
          trailing: Switch(
            value: _lockEnabled,
            activeThumbColor: Colors.white,
            activeTrackColor: emerald,
            onChanged: _toggleAppLock,
          ),
        ),
      ],
    ]);
  }

  // ─── Help & Support (shudhu tottho, kono button na) ───────
  Widget _buildSupportCard() {
    Widget row(IconData icon, Color color, Color soft, String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: soft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: muted,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Long-press kore copy kora jay
                  SelectableText(
                    value,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: ink,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          row(Icons.call_rounded, emerald, emeraldSoft,
              LanguageService.tr('Hotline', 'হটলাইন'), _hotlineDisplay),
          row(Icons.mail_outline_rounded, lapis, lapisSoft,
              LanguageService.tr('Email', 'ইমেইল'), _supportEmail),
          row(Icons.schedule_rounded, goldDeep, goldSoft,
              LanguageService.tr('Office Hours', 'অফিস সময়'),
              LanguageService.tr('Saturday – Thursday, 9:00 AM – 6:00 PM',
                  'শনিবার – বৃহস্পতিবার, সকাল ৯টা – সন্ধ্যা ৬টা')),
          row(Icons.location_on_outlined, terracotta, terracottaSoft,
              LanguageService.tr('Office Address', 'অফিসের ঠিকানা'),
              '$_officeAddress, Bangladesh'),
          row(Icons.language_rounded, turquoise, turquoiseSoft,
              LanguageService.tr('Website', 'ওয়েবসাইট'), 'www.biniyogclub.com'),
        ],
      ),
    );
  }

  // ─── Legal — website er page app er bhitorei dekhay ───────
  // Lekha website theke ashe, tai app ar website e shob shomoy ek-i thake
  Widget _buildLegalCard() {
    return _card([
      _tile(
        icon: Icons.description_outlined,
        color: emerald,
        soft: emeraldSoft,
        title: LanguageService.tr('Terms of Service', 'ব্যবহারের শর্তাবলী'),
        subtitle: LanguageService.tr('Rules for using Biniyog Club',
            'বিনিয়োগ ক্লাব ব্যবহারের নিয়ম'),
        onTap: () => _openLegal(
            LanguageService.tr('Terms of Service', 'ব্যবহারের শর্তাবলী'), '/terms'),
      ),
      _divider(),
      _tile(
        icon: Icons.privacy_tip_outlined,
        color: lapis,
        soft: lapisSoft,
        title: LanguageService.tr('Privacy Policy', 'গোপনীয়তা নীতি'),
        subtitle: LanguageService.tr('How your data is collected and used',
            'আপনার তথ্য কীভাবে সংগ্রহ ও ব্যবহার হয়'),
        onTap: () => _openLegal(
            LanguageService.tr('Privacy Policy', 'গোপনীয়তা নীতি'), '/privacy'),
      ),
      _divider(),
      _tile(
        icon: Icons.gpp_maybe_outlined,
        color: terracotta,
        soft: terracottaSoft,
        title: LanguageService.tr('About & Risk Disclosures', 'আমাদের সম্পর্কে ও ঝুঁকি'),
        subtitle: LanguageService.tr('Investment risks you should know',
            'বিনিয়োগের ঝুঁকি সম্পর্কে জানুন'),
        onTap: () => _openLegal(
            LanguageService.tr('About & Risk Disclosures', 'আমাদের সম্পর্কে ও ঝুঁকি'), '/about'),
      ),
      _divider(),
      _tile(
        icon: Icons.verified_user_outlined,
        color: goldDeep,
        soft: goldSoft,
        title: LanguageService.tr('FAQ', 'সাধারণ প্রশ্নোত্তর'),
        subtitle: LanguageService.tr('Security and common questions',
            'নিরাপত্তা ও সাধারণ প্রশ্ন'),
        onTap: () => _openLegal(
            LanguageService.tr('FAQ', 'সাধারণ প্রশ্নোত্তর'), '/faq'),
      ),
    ]);
  }

  // ─── Sign out + Danger ────────────────────────────────────
  Widget _buildSignOutButton() {
    return OutlinedButton.icon(
      onPressed: _confirmSignOut,
      icon: const Icon(Icons.logout_rounded, size: 18),
      label: Text(LanguageService.tr('Sign out', 'সাইন আউট')),
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: const BorderSide(color: line),
        backgroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildDangerCard() {
    return Container(
      decoration: BoxDecoration(
        color: dangerSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: danger.withAlpha(60)),
      ),
      clipBehavior: Clip.antiAlias,
      child: _tile(
        icon: Icons.delete_forever_rounded,
        color: danger,
        soft: Colors.white,
        title: LanguageService.tr('Delete Account', 'অ্যাকাউন্ট ডিলিট করুন'),
        subtitle: LanguageService.tr(
            'Only possible with no active or pending investments. 30-day recovery period.',
            'চলমান বা অপেক্ষমান বিনিয়োগ না থাকলেই সম্ভব। ৩০ দিনের মধ্যে ফেরত আনা যাবে।'),
        trailing: _checkingDelete
            ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(color: danger, strokeWidth: 2),
        )
            : const Icon(Icons.chevron_right_rounded, color: danger, size: 22),
        onTap: _checkingDelete ? null : _startDeleteFlow,
      ),
    );
  }

  // ─── App info (asol version) ──────────────────────────────
  Widget _buildAppInfo() {
    final showStoreButton = _publishedOnPlayStore && Platform.isAndroid && _packageName.isNotEmpty;

    return Column(
      children: [
        Image.asset(
          'assets/images/logo_full.png',
          height: 30,
          errorBuilder: (_, __, ___) => const Text(
            'Biniyog Club',
            style: TextStyle(color: emerald, fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        if (_version.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '${LanguageService.tr('Version', 'ভার্সন')} $_version ($_buildNumber)',
            style: const TextStyle(fontSize: 11.5, color: muted),
          ),
        ],
        if (showStoreButton) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => _open(
              'https://play.google.com/store/apps/details?id=$_packageName',
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.system_update_alt_rounded, size: 18, color: emerald),
            label: Text(
              LanguageService.tr('Check for updates on Play Store', 'প্লে স্টোরে আপডেট দেখুন'),
              style: const TextStyle(color: emerald, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNeedsLogin() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 40, color: goldDeep),
            const SizedBox(height: 12),
            Text(
              LanguageService.tr('Please log in to see your settings',
                  'সেটিংস দেখতে লগইন করুন'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _goToLogin,
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(LanguageService.tr('Log in', 'লগইন')),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Islamic geometric pattern (dashboard er moto 8-point star)
// ═══════════════════════════════════════════════════════════
class _IslamicPatternPainter extends CustomPainter {
  final Color color;
  final double cell;

  _IslamicPatternPainter({required this.color, required this.cell});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    final r = cell * 0.34;

    for (double y = 0; y <= size.height + cell; y += cell) {
      final offsetRow = ((y / cell).round() % 2) * cell / 2;
      for (double x = -cell; x <= size.width + cell; x += cell) {
        final c = Offset(x + offsetRow, y);
        for (final start in [0.0, math.pi / 4]) {
          final path = Path();
          for (int i = 0; i < 4; i++) {
            final a = start + i * math.pi / 2;
            final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
            i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
          }
          path.close();
          canvas.drawPath(path, paint);
        }
        canvas.drawCircle(c, r * 0.32, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IslamicPatternPainter old) =>
      old.color != color || old.cell != cell;
}