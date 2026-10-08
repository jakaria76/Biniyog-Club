import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _notifications = [];

  static const Map<String, String> notifTypeIcons = {
    'INVESTMENT_CONFIRMED': '✅',
    'INVESTMENT_MATURED': '🎉',
    'PAYMENT_RECEIVED': '💰',
    'PAYMENT_FAILED': '❌',
    'PROJECT_APPROVED': '✅',
    'PROJECT_FUNDED': '🌾',
    'PROJECT_UPDATE': '📋',
    'KYC_APPROVED': '🛡️',
    'KYC_REJECTED': '⚠️',
    'WITHDRAWAL_APPROVED': '✅',
    'WITHDRAWAL_COMPLETED': '💸',
    'SYSTEM': '🔔',
  };

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';

    final list = await DatabaseService.getNotificationsData(userId);

    // Auto mark all notifications as read in Neon DB when viewing page
    if (userId.isNotEmpty) {
      await DatabaseService.markAllNotificationsAsRead(userId);
    }

    if (mounted) {
      setState(() {
        _notifications = list;
        for (var n in _notifications) {
          n['isRead'] = true;
        }
        _isLoading = false;
      });
    }
  }

  int get _unreadCount =>
      _notifications.where((n) => n['isRead'] == false).length;

  Future<void> _markAllAsRead() async {
    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    if (userId.isNotEmpty) {
      await DatabaseService.markAllNotificationsAsRead(userId);
    }

    setState(() {
      for (var n in _notifications) {
        n['isRead'] = true;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LanguageService.tr('All notifications marked as read.', 'সকল নোটিফিকেশন পড়া হিসেবে চিহ্নিত হয়েছে।')),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F7F6),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.5,
            iconTheme: const IconThemeData(color: Colors.teal),
            title: Text(
              LanguageService.tr('Notifications', 'নোটিফিকেশনস'),
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            actions: [
              if (_unreadCount > 0)
                TextButton(
                  onPressed: _markAllAsRead,
                  child: Text(
                    LanguageService.tr('Mark as read', 'পড়া হয়েছে চিহ্নিত করুন'),
                    style: const TextStyle(color: Colors.teal, fontSize: 12),
                  ),
                ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.teal))
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  color: Colors.teal,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              LanguageService.tr(
                                  '${_notifications.length} total notifications',
                                  'মোট ${_notifications.length} টি নোটিফিকেশন'),
                              style:
                                  TextStyle(fontSize: 13, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        _notifications.isEmpty
                            ? _buildEmptyState()
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _notifications.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final n = _notifications[index];
                                  final bool isRead = n['isRead'] as bool? ?? true;
                                  final String icon =
                                      notifTypeIcons[n['type']] ?? '🔔';

                                  return GestureDetector(
                                    onTap: () async {
                                      setState(() {
                                        n['isRead'] = true;
                                      });
                                      await DatabaseService.markNotificationAsRead(
                                          n['id'].toString());
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: isRead
                                            ? Colors.white
                                            : Colors.teal.shade50,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isRead
                                              ? Colors.grey.shade200
                                              : Colors.teal.shade200,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(icon,
                                              style: const TextStyle(fontSize: 22)),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        n['title'] as String? ??
                                                            'Notification',
                                                        style: TextStyle(
                                                          fontSize: 13.5,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: isRead
                                                              ? Colors.black87
                                                              : Colors.teal.shade900,
                                                        ),
                                                      ),
                                                    ),
                                                    if (!isRead)
                                                      Container(
                                                        width: 8,
                                                        height: 8,
                                                        decoration:
                                                            const BoxDecoration(
                                                          color: Colors.teal,
                                                          shape: BoxShape.circle,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  n['body'] as String? ?? '',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[700],
                                                    height: 1.3,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            const Icon(Icons.notifications_off_outlined,
                size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              LanguageService.tr('No notifications yet', 'কোনো নোটিফিকেশন নেই'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              LanguageService.tr("You'll be notified about your investments here.", 'আপনার বিনিয়োগের যাবতীয় আপডেট এখানে দেখতে পাবেন।'),
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
