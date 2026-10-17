import 'package:flutter/material.dart';

import '../../authentication/login_page.dart';
import '../portfolio/investments_page.dart';
import '../projects/my_projects_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  // ─── Palette (dashboard er moto) ───
  static const Color emerald = Color(0xFF0E4A37);
  static const Color emeraldSoft = Color(0xFFE3F0E9);
  static const Color gold = Color(0xFFB8935A);
  static const Color goldDeep = Color(0xFF8A6A3A);
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

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  bool _isLoading = true;
  bool _needsLogin = false;
  bool _loadFailed = false;
  String _userId = '';

  List<Map<String, dynamic>> _notifications = [];

  /// Ei bar page khular shomoy je gulo notun chhilo — highlight thakbe
  final Set<String> _newIds = {};

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  // ═════════════════════════════════════════════════════════
  // DATA
  // ═════════════════════════════════════════════════════════
  Future<void> _loadNotifications() async {
    if (mounted) setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';

    if (userId.isEmpty) {
      if (mounted) {
        setState(() {
          _needsLogin = true;
          _isLoading = false;
        });
      }
      return;
    }

    final list = await DatabaseService.getNotificationsData(userId);
    final failed = list.isEmpty && DatabaseService.lastRequestFailed;

    if (!mounted) return;
    setState(() {
      _userId = userId;
      _needsLogin = false;
      _loadFailed = failed;
      if (!failed) {
        _notifications = list;
        // Notun gulo mone rakhi, jeno ei bar highlight dekhay
        for (final n in list) {
          if (n['isRead'] == false) _newIds.add(n['id'].toString());
        }
      }
      _isLoading = false;
    });

    // Dashboard er badge clear korar jonno server e read kore dei.
    // Screen e notun gulo tobuo highlight thake, karon _newIds e ache.
    if (!failed && _newIds.isNotEmpty) {
      DatabaseService.markAllNotificationsAsRead(userId);
    }
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  bool get _isBn => LanguageService.isBangla;

  String _two(int n) => n.toString().padLeft(2, '0');

  String _time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '$h:${_two(d.minute)} $ampm';
  }

  /// "Today, 2:30 PM" · "Yesterday, 9:10 AM" · "Oct 13" · "Oct 13, 2025"
  String _when(String raw) {
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) return '${_isBn ? 'আজ' : 'Today'}, ${_time(d)}';
    if (diff == 1) return '${_isBn ? 'গতকাল' : 'Yesterday'}, ${_time(d)}';
    if (d.year == now.year) return '${_months[d.month - 1]} ${d.day}';
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// Ki dhoroner notification — icon ar color
  (IconData, Color, Color) _style(String type) {
    switch (type) {
      case 'INVESTMENT_CONFIRMED':
        return (Icons.check_circle_outline_rounded, emerald, emeraldSoft);
      case 'INVESTMENT_MATURED':
        return (Icons.celebration_outlined, goldDeep, goldSoft);
      case 'PAYMENT_RECEIVED':
        return (Icons.payments_outlined, emerald, emeraldSoft);
      case 'PAYMENT_FAILED':
        return (Icons.error_outline_rounded, danger, dangerSoft);
      case 'PROJECT_APPROVED':
      case 'PROJECT_FUNDED':
        return (Icons.agriculture_outlined, turquoise, turquoiseSoft);
      case 'PROJECT_UPDATE':
        return (Icons.campaign_outlined, lapis, lapisSoft);
      case 'KYC_APPROVED':
        return (Icons.verified_user_outlined, emerald, emeraldSoft);
      case 'KYC_REJECTED':
        return (Icons.gpp_bad_outlined, danger, dangerSoft);
      case 'WITHDRAWAL_APPROVED':
      case 'WITHDRAWAL_COMPLETED':
        return (Icons.account_balance_outlined, turquoise, turquoiseSoft);
      default:
        return (Icons.notifications_none_rounded, terracotta, terracottaSoft);
    }
  }

  /// Notification er dhoron dekhe kon page khulbe (na thakle null)
  Widget? _targetPage(String type) {
    if (type.startsWith('INVESTMENT_') || type.startsWith('PAYMENT_')) {
      return const InvestmentsPage();
    }
    if (type.startsWith('PROJECT_')) return const MyProjectsPage();
    return null;
  }

  void _onTap(Map<String, dynamic> n) {
    // Server e already read; tobuo ei notification ta alada kore nishchit kori
    if (n['isRead'] == false) {
      DatabaseService.markNotificationAsRead(n['id'].toString(), userId: _userId);
      n['isRead'] = true;
    }
    final page = _targetPage(n['type']?.toString() ?? '');
    if (page != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
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
        final newCount = _notifications.where((n) => _newIds.contains(n['id'].toString())).length;

        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              LanguageService.tr('Notifications', 'নোটিফিকেশন'),
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
              ? _buildMessage(
            icon: Icons.lock_outline_rounded,
            title: LanguageService.tr('Please log in to see your notifications',
                'নোটিফিকেশন দেখতে লগইন করুন'),
            buttonLabel: LanguageService.tr('Log in', 'লগইন'),
            onTap: () async {
              await AuthService.logout();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginPage()),
                    (route) => false,
              );
            },
          )
              : _loadFailed
              ? _buildMessage(
            icon: Icons.wifi_off_rounded,
            title: LanguageService.tr('Could not load notifications',
                'নোটিফিকেশন লোড করা যায়নি'),
            subtitle: LanguageService.tr(
                'Please check your internet connection.',
                'ইন্টারনেট সংযোগ চেক করুন।'),
            buttonLabel: LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
            onTap: _loadNotifications,
          )
              : RefreshIndicator(
            onRefresh: _loadNotifications,
            color: emerald,
            child: _notifications.isEmpty
                ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 40),
              children: [_buildEmptyState()],
            )
                : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 40),
              itemCount: _notifications.length + 1,
              separatorBuilder: (_, i) =>
                  SizedBox(height: i == 0 ? 14 : 10),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Text(
                    newCount > 0
                        ? LanguageService.tr(
                        '$newCount new · ${_notifications.length} total',
                        '$newCount টি নতুন · মোট ${_notifications.length} টি')
                        : LanguageService.tr(
                        '${_notifications.length} notifications',
                        'মোট ${_notifications.length} টি নোটিফিকেশন'),
                    style: const TextStyle(fontSize: 13, color: muted),
                  );
                }
                return _buildTile(_notifications[i - 1]);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTile(Map<String, dynamic> n) {
    final id = n['id'].toString();
    final type = n['type']?.toString() ?? 'SYSTEM';
    final isNew = _newIds.contains(id);
    final style = _style(type);
    final hasTarget = _targetPage(type) != null;
    final title = n['title']?.toString() ?? '';
    final body = n['body']?.toString() ?? '';
    final when = _when(n['createdAt']?.toString() ?? '');

    return Material(
      color: isNew ? goldSoft : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _onTap(n),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isNew ? gold.withAlpha(110) : line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isNew ? Colors.white : style.$3,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(style.$1, color: style.$2, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title.isEmpty
                                ? LanguageService.tr('Notification', 'নোটিফিকেশন')
                                : title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isNew ? FontWeight.w700 : FontWeight.w600,
                              color: ink,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (isNew) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: goldDeep,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              LanguageService.tr('NEW', 'নতুন'),
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: const TextStyle(fontSize: 12.5, color: muted, height: 1.4),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (when.isNotEmpty)
                          Text(
                            when,
                            style: TextStyle(
                              fontSize: 11,
                              color: muted.withAlpha(200),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        const Spacer(),
                        if (hasTarget)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                LanguageService.tr('View', 'দেখুন'),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: style.$2,
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, size: 16, color: style.$2),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(color: goldSoft, shape: BoxShape.circle),
            child: const Icon(Icons.notifications_none_rounded, size: 28, color: goldDeep),
          ),
          const SizedBox(height: 14),
          Text(
            LanguageService.tr('No notifications yet', 'এখনো কোনো নোটিফিকেশন নেই'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
          ),
          const SizedBox(height: 4),
          Text(
            LanguageService.tr('Updates about your investments will appear here.',
                'আপনার বিনিয়োগ সংক্রান্ত আপডেট এখানে দেখাবে।'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    String? subtitle,
    required String buttonLabel,
    required VoidCallback onTap,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: goldDeep),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: muted),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}