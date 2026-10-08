import 'package:flutter/material.dart';
import '../../authentication/login_page.dart';
import '../documents/documents_page.dart';
import '../groups/group_investments_page.dart';
import '../kyc/kyc_page.dart';
import '../notifications/notifications_page.dart';
import '../portfolio/investments_page.dart';
import '../portfolio/portfolio_page.dart';
import '../profile/profile_page.dart';
import '../projects/my_projects_page.dart';
import '../projects/project_detail_page.dart';
import '../reports/reports_page.dart';
import '../settings/settings_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';

class InvestorDashboardPage extends StatefulWidget {
  const InvestorDashboardPage({super.key});

  @override
  State<InvestorDashboardPage> createState() => _InvestorDashboardPageState();
}

class _InvestorDashboardPageState extends State<InvestorDashboardPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _user;

  // Main Bespoke Theme Colors
  static const Color primaryTeal = Color(0xFF047857);
  static const Color primaryDarkTeal = Color(0xFF064E3B);

  // Real Database Fetched State
  String? _avatarUrl;
  int _unreadNotificationCount = 0;
  double _totalInvested = 0.0;
  double _returnsEarned = 0.0;
  double _portfolioValue = 0.0;
  int _activeCount = 0;
  final int _completedCount = 0;
  int _pendingTransactions = 0;
  double _pendingAmount = 0.0;

  List<Map<String, dynamic>> _openProjects = [];
  List<Map<String, dynamic>> _recentInvestments = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    var userData = await AuthService.getUserData();

    // Recover user session from DB if local storage is empty
    if (userData == null || (userData['id'] == null && userData['email'] == null)) {
      final conn = await DatabaseService.getConnection();
      if (conn != null) {
        final res = await conn.execute(
            'SELECT "id", "name", "email", "phone" FROM users ORDER BY "createdAt" DESC LIMIT 1');
        if (res.isNotEmpty) {
          userData = {
            'id': res.first[0].toString(),
            'name': res.first[1].toString(),
            'email': res.first[2].toString(),
            'phone': res.first[3]?.toString() ?? '',
          };
          await AuthService.saveUserData(userData);
        }
      }
    }

    final userId = userData?['id']?.toString() ?? '';
    final userEmail = userData?['email']?.toString() ?? '';

    final summary =
        await DatabaseService.getDashboardSummary(userId, email: userEmail);

    if (mounted) {
      setState(() {
        _user = userData;
        if (summary.isNotEmpty) {
          _avatarUrl = summary['avatarUrl']?.toString();
          _unreadNotificationCount =
              (summary['unreadNotificationCount'] as int? ?? 0);
          _totalInvested = (summary['totalInvested'] as double? ?? 0.0);
          _returnsEarned = (summary['totalReturns'] as double? ?? 0.0);
          _portfolioValue = _totalInvested + _returnsEarned;
          _activeCount = (summary['activeInvestmentsCount'] as int? ?? 0);
          _pendingTransactions =
              (summary['pendingTransactionsCount'] as int? ?? 0);
          _pendingAmount =
              (summary['pendingInvestmentsAmount'] as double? ?? 0.0);

          _openProjects =
              (summary['openProjects'] as List<Map<String, dynamic>>? ?? []);
          _recentInvestments =
              (summary['recentInvestments'] as List<Map<String, dynamic>>? ?? []);
        }
        _isLoading = false;
      });
    }
  }

  String _fmt(double amount) {
    if (amount >= 10000000) {
      return '৳${(amount / 10000000).toStringAsFixed(2)} Cr';
    } else if (amount >= 100000) {
      return '৳${(amount / 100000).toStringAsFixed(2)}L';
    } else if (amount >= 1000) {
      return '৳${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '৳${amount.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final String name = _user?['name'] ?? 'Investor';

    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          drawer: _buildAppSidebar(context),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 1,
            shadowColor: Colors.black.withAlpha(15),
            leading: Builder(
              builder: (context) => Padding(
                padding: const EdgeInsets.only(left: 10, top: 8, bottom: 8),
                child: Material(
                  color: primaryTeal.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Scaffold.of(context).openDrawer(),
                    child: const Icon(Icons.menu_rounded, color: primaryTeal, size: 22),
                  ),
                ),
              ),
            ),
            title: Image.asset(
              'assets/images/logo_full.png',
              height: 38,
              errorBuilder: (context, error, stackTrace) => Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: primaryTeal,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.show_chart_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Biniyog Club',
                    style: TextStyle(
                      color: primaryTeal,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              // Notification Bell with Red Badge Count
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const NotificationsPage()),
                  ).then((_) => _loadDashboardData());
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.notifications_none_rounded,
                          color: primaryTeal, size: 22),
                      if (_unreadNotificationCount > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              '$_unreadNotificationCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Profile Avatar Circle
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfilePage()),
                  ).then((_) => _loadDashboardData());
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: primaryTeal.withAlpha(100), width: 1.5),
                  ),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: primaryTeal,
                    child: ClipOval(
                      child: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                          ? Image.network(
                              _avatarUrl!,
                              width: 28,
                              height: 28,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'I',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'I',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: primaryTeal))
              : RefreshIndicator(
                  onRefresh: _loadDashboardData,
                  color: primaryTeal,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Portfolio Overview Hero Card
                        _buildPortfolioOverviewHeroCard(),
                        const SizedBox(height: 18),

                        // 2. Multi-colored Stat Bento Grid
                        _buildBespokeStatGrid(),
                        const SizedBox(height: 24),

                        // 3. Open for Investment (Available Projects)
                        _buildAvailableProjectsSection(),
                        const SizedBox(height: 24),

                        // 4. Recent Investments
                        _buildRecentInvestmentsSection(),
                        const SizedBox(height: 24),

                        // 5. Project Updates
                        _buildProjectUpdatesSection(),
                        const SizedBox(height: 24),

                        // 6. Quick Actions
                        _buildQuickActionsSection(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  // App Navigation Drawer (Matching Website Sidebar 1:1)
  Widget _buildAppSidebar(BuildContext context) {
    final String name = _user?['name'] ?? 'Investor';
    final String email = _user?['email'] ?? '';
    final String initial = name.isNotEmpty ? name[0].toUpperCase() : 'I';

    final menuItems = [
      {
        'title': LanguageService.tr('Overview', 'ওভারভিউ'),
        'icon': Icons.grid_view_rounded,
        'page': const InvestorDashboardPage(),
      },
      {
        'title': LanguageService.tr('Investments', 'ইনভেস্টমেন্টস'),
        'icon': Icons.pie_chart_rounded,
        'page': const InvestmentsPage(),
      },
      {
        'title': LanguageService.tr('Group Invest', 'গ্রুপ ইনভেস্ট'),
        'icon': Icons.groups_rounded,
        'page': const GroupInvestmentsPage(),
      },
      {
        'title': LanguageService.tr('My Projects', 'আমার প্রজেক্টস'),
        'icon': Icons.business_center_rounded,
        'page': const MyProjectsPage(),
      },
      {
        'title': LanguageService.tr('Portfolio', 'পোর্টফোলিও'),
        'icon': Icons.donut_large_rounded,
        'page': const PortfolioPage(),
      },
      {
        'title': LanguageService.tr('Documents', 'ডকুমেন্টস'),
        'icon': Icons.folder_outlined,
        'page': const DocumentsPage(),
      },
      {
        'title': LanguageService.tr('Reports', 'রিপোর্টস'),
        'icon': Icons.bar_chart_rounded,
        'page': const ReportsPage(),
      },
      {
        'title': LanguageService.tr('Notifications', 'নোটিফিকেশনস'),
        'icon': Icons.notifications_outlined,
        'page': const NotificationsPage(),
      },
      {
        'title': LanguageService.tr('Profile', 'প্রোফাইল'),
        'icon': Icons.person_outline_rounded,
        'page': const ProfilePage(),
      },
      {
        'title': LanguageService.tr('Settings', 'সেটিংস'),
        'icon': Icons.settings_outlined,
        'page': const SettingsPage(),
      },
      {
        'title': LanguageService.tr('KYC', 'কেওয়াইসি'),
        'icon': Icons.shield_outlined,
        'page': const KycPage(),
      },
    ];

    return Drawer(
      backgroundColor: const Color(0xFF062E25),
      child: SafeArea(
        child: Column(
          children: [
            // Top Header Logo & Menu Title
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: primaryTeal,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.show_chart_rounded,
                                color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Biniyog Club',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded,
                            color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'MENU',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Menu List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: menuItems.length,
                itemBuilder: (context, index) {
                  final item = menuItems[index];
                  final String title = item['title'] as String;
                  final IconData icon = item['icon'] as IconData;
                  final Widget page = item['page'] as Widget;

                  final bool isOverview = index == 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: isOverview
                          ? primaryTeal.withAlpha(200)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        icon,
                        color: isOverview ? Colors.white : Colors.white70,
                        size: 20,
                      ),
                      title: Text(
                        title,
                        style: TextStyle(
                          color: isOverview
                              ? Colors.white
                              : Colors.white.withAlpha(220),
                          fontSize: 13,
                          fontWeight: isOverview
                              ? FontWeight.bold
                              : FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context); // Close Drawer
                        if (!isOverview) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => page),
                          ).then((_) => _loadDashboardData());
                        }
                      },
                    ),
                  );
                },
              ),
            ),

            // Bottom User Profile & Logout Action Bar
            const Divider(color: Colors.white12, height: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: primaryTeal,
                    child: ClipOval(
                      child: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                          ? Image.network(
                              _avatarUrl!,
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Text(
                                initial,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            )
                          : Text(
                              initial,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          email,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded,
                        color: Colors.redAccent, size: 20),
                    onPressed: () {
                      _showLogoutConfirmDialog(context);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(LanguageService.tr('Sign Out', 'সাইন আউট')),
          content: Text(LanguageService.tr(
              'Are you sure you want to sign out of your Biniyog Club account?',
              'আপনি কি নিশ্চিত যে আপনি অ্যাকাউন্ট থেকে সাইন আউট করতে চান?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(LanguageService.tr('Cancel', 'বাতিল'),
                  style: const TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                nav.pop(); // Close Dialog
                await AuthService.logout();
                nav.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(LanguageService.tr('Sign Out', 'সাইন আউট')),
            ),
          ],
        );
      },
    );
  }

  // Hero Card: Portfolio Overview / Total Invested
  Widget _buildPortfolioOverviewHeroCard() {
    final double roi =
        _totalInvested > 0 ? ((_returnsEarned / _totalInvested) * 100) : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF064E3B),
            Color(0xFF047857),
            Color(0xFF0D9488),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryDarkTeal.withAlpha(70),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pie_chart_rounded,
                    color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                LanguageService.tr('Portfolio Overview', 'পোর্টফোলিও ওভারভিউ'),
                style: TextStyle(
                  color: Colors.white.withAlpha(230),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Total Invested Display
          Text(
            _fmt(_totalInvested),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            LanguageService.tr('Total Invested', 'মোট বিনিয়োগ'),
            style: TextStyle(
              color: Colors.white.withAlpha(200),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),

          // 4 Grid Sub Stats inside Hero Card
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 2.2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              _buildHeroSubStatBox(
                  LanguageService.tr('Active Projects', 'চলতি প্রজেক্ট'), '$_activeCount'),
              _buildHeroSubStatBox(
                  LanguageService.tr('Returns Earned', 'অর্জিত রিটার্ন'), _fmt(_returnsEarned)),
              _buildHeroSubStatBox(
                  LanguageService.tr('Portfolio Value', 'পোর্টফোলিও ভ্যালু'), _fmt(_portfolioValue)),
              _buildHeroSubStatBox(
                  LanguageService.tr('ROI', 'আর.ও.আই'), '${roi.toStringAsFixed(1)}%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSubStatBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(200),
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // 2. Multi-colored Bespoke Bento Stat Grid
  Widget _buildBespokeStatGrid() {
    final double roi =
        _totalInvested > 0 ? ((_returnsEarned / _totalInvested) * 100) : 0.0;

    final stats = [
      {
        'title': LanguageService.tr('Portfolio Value', 'পোর্টফোলিও ভ্যালু'),
        'value': _fmt(_portfolioValue),
        'sub': LanguageService.tr('$_activeCount active projects', '$_activeCount টি একটিভ প্রজেক্ট'),
        'icon': Icons.account_balance_wallet_rounded,
        'bg': const Color(0xFFECFDF5),
        'border': const Color(0xFFA7F3D0),
        'iconBg': const Color(0xFF059669),
        'textCol': const Color(0xFF065F46),
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const PortfolioPage()),
          );
        },
      },
      {
        'title': LanguageService.tr('ROI', 'আর.ও.আই'),
        'value': '${roi.toStringAsFixed(1)}%',
        'sub': LanguageService.tr('Distributed returns', 'প্রাপ্ত রিটার্ন'),
        'icon': Icons.trending_up_rounded,
        'bg': const Color(0xFFFFFBEB),
        'border': const Color(0xFFFDE68A),
        'iconBg': const Color(0xFFD97706),
        'textCol': const Color(0xFF92400E),
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const PortfolioPage()),
          );
        },
      },
      {
        'title': LanguageService.tr('Completed', 'সম্পন্ন প্রজেক্ট'),
        'value': '$_completedCount',
        'sub': LanguageService.tr('Matured investments', 'মেয়াদোত্তীর্ণ বিনিয়োগ'),
        'icon': Icons.verified_rounded,
        'bg': const Color(0xFFEEF2FF),
        'border': const Color(0xFFC7D2FE),
        'iconBg': const Color(0xFF4F46E5),
        'textCol': const Color(0xFF3730A3),
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const InvestmentsPage()),
          );
        },
      },
      {
        'title': LanguageService.tr('Pending', 'অপেক্ষমান'),
        'value': '$_pendingTransactions',
        'sub': _pendingAmount > 0
            ? _fmt(_pendingAmount)
            : LanguageService.tr('Awaiting approval', 'অনুমোদনের অপেক্ষায়'),
        'icon': Icons.hourglass_top_rounded,
        'bg': const Color(0xFFFEF2F2),
        'border': const Color(0xFFFECDD3),
        'iconBg': const Color(0xFFE11D48),
        'textCol': const Color(0xFF9F1239),
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const InvestmentsPage()),
          );
        },
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stats.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (context, index) {
        final item = stats[index];
        final Color bg = item['bg'] as Color;
        final Color border = item['border'] as Color;
        final Color iconBg = item['iconBg'] as Color;
        final Color textCol = item['textCol'] as Color;
        final VoidCallback? onTap = item['onTap'] as VoidCallback?;

        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: iconBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(item['icon'] as IconData,
                          color: Colors.white, size: 16),
                    ),
                    Icon(Icons.arrow_forward_rounded,
                        color: textCol.withAlpha(180), size: 14),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['value'] as String,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textCol,
                      ),
                    ),
                    Text(
                      item['title'] as String,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: textCol.withAlpha(220),
                      ),
                    ),
                    Text(
                      item['sub'] as String,
                      style: TextStyle(
                          fontSize: 9.5, color: textCol.withAlpha(180)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Open for Investment Projects
  Widget _buildAvailableProjectsSection() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: primaryTeal,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  LanguageService.tr('Open for Investment', 'বিনিয়োগের জন্য উন্মুক্ত'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MyProjectsPage()),
                );
              },
              child: Text(
                LanguageService.tr('View all →', 'সব দেখুন →'),
                style: const TextStyle(color: primaryTeal, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _openProjects.isEmpty
            ? Container(
                padding: const EdgeInsets.all(20),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Center(
                  child: Text(
                    LanguageService.tr('No open projects currently available.', 'বর্তমানে কোনো উন্মুক্ত প্রজেক্ট নেই।'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              )
            : SizedBox(
                height: 310,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _openProjects.length,
                  itemBuilder: (context, index) {
                    final p = _openProjects[index];
                    final double progress = (p['progress'] as double? ?? 0.0);
                    final pctInt = (progress * 100).toInt();
                    final coverUrl = p['coverImageUrl']?.toString() ?? '';
                    final location = p['location']?.toString() ?? 'Narayanganj';
                    final daysLeft = p['daysLeft'] as int? ?? 116;
                    final investorsCount = p['investorsCount'] as int? ?? 1;

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProjectDetailPage(
                              projectIdOrSlug: p['id'].toString(),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: 270,
                        margin: const EdgeInsets.only(right: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(8),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top Media Image Container with Badges
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(18)),
                                  child: Image.network(
                                    coverUrl,
                                    height: 120,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        height: 120,
                                        width: double.infinity,
                                        color: Colors.teal.shade900,
                                        child: const Center(
                                          child: Icon(
                                              Icons.image_not_supported_outlined,
                                              color: Colors.white54,
                                              size: 32),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                // Top Badges
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withAlpha(150),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: Text(
                                      p['category'] as String? ?? 'SME',
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withAlpha(150),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.access_time_rounded,
                                            size: 11, color: Colors.amber),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${daysLeft}d left',
                                          style: const TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Card Details Padding
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p['title'] as String? ?? 'Project',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on_outlined,
                                          size: 12, color: primaryTeal),
                                      const SizedBox(width: 3),
                                      Text(
                                        location,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  // Progress Bar & Raised vs Goal
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '$pctInt% funded',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w600),
                                          ),
                                          Text(
                                            '${_fmt(p['fundingGoalBdt'] as double)} goal',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey[600]),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          minHeight: 5,
                                          backgroundColor: Colors.grey.shade200,
                                          valueColor:
                                              const AlwaysStoppedAnimation<Color>(
                                                  primaryTeal),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  // 3 Bento Stat Boxes
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildBentoStatBox(
                                          LanguageService.tr('Return', 'রিটার্ন'),
                                          '${((p['expectedReturnPct'] as double) * 100).toStringAsFixed(0)}%',
                                          primaryTeal,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _buildBentoStatBox(
                                          LanguageService.tr('Duration', 'মেয়াদ'),
                                          '${p['durationDays']}d',
                                          Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _buildBentoStatBox(
                                          LanguageService.tr('Investors', 'বিনিয়োগকারী'),
                                          '$investorsCount',
                                          Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  Text(
                                    '${LanguageService.tr('Min', 'সর্বনিম্ন')} ${_fmt(p['minInvestmentBdt'] as double)}',
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[700]),
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
              ),
      ],
    );
  }

  Widget _buildBentoStatBox(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Text(
            val,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(fontSize: 8.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // Recent Investments Section
  Widget _buildRecentInvestmentsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                LanguageService.tr('Recent Investments', 'সাম্প্রতিক বিনিয়োগ'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 12),
          _recentInvestments.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Center(
                    child: Text(
                      LanguageService.tr('No investments made yet.', 'এখনো কোনো বিনিয়োগ করা হয়নি।'),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentInvestments.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final item = _recentInvestments[index];
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['title'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                item['createdAt'] as String,
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _fmt(item['amountBdt'] as double),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTeal),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item['status'] as String,
                                style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: primaryTeal),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
        ],
      ),
    );
  }

  // Project Updates
  Widget _buildProjectUpdatesSection() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const NotificationsPage()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_outlined,
                    color: primaryTeal, size: 18),
                const SizedBox(width: 6),
                Text(
                  LanguageService.tr('Project Updates', 'প্রজেক্ট আপডেট'),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF166534)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: primaryTeal,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.campaign_outlined,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LanguageService.tr(
                            'Quarterly profit distribution credited!',
                            'ত্রৈমাসিক মুনাফা ক্রেডিট করা হয়েছে!'),
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF14532D)),
                      ),
                      Text(
                        'Biniyog Club Platform Update',
                        style: TextStyle(
                            fontSize: 11, color: Colors.teal.shade800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Quick Actions (Colorful Soft Bento Cards)
  Widget _buildQuickActionsSection() {
    final actions = [
      {
        'title': LanguageService.tr('Browse Projects', 'প্রজেক্ট ব্রাউজ করুন'),
        'icon': Icons.explore_outlined,
        'bg': const Color(0xFFECFDF5),
        'border': const Color(0xFFA7F3D0),
        'iconColor': const Color(0xFF059669),
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MyProjectsPage()),
          );
        },
      },
      {
        'title': LanguageService.tr('My Portfolio', 'আমার পোর্টফোলিও'),
        'icon': Icons.pie_chart_outline_rounded,
        'bg': const Color(0xFFEEF2FF),
        'border': const Color(0xFFC7D2FE),
        'iconColor': const Color(0xFF4F46E5),
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const PortfolioPage()),
          );
        },
      },
      {
        'title': LanguageService.tr('Group Invest', 'গ্রুপ ইনভেস্ট'),
        'icon': Icons.groups_outlined,
        'bg': const Color(0xFFFFF7ED),
        'border': const Color(0xFFFFEDD5),
        'iconColor': const Color(0xFFEA580C),
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const GroupInvestmentsPage()),
          );
        },
      },
      {
        'title': LanguageService.tr('KYC Verification', 'কেওয়াইসি ভেরিফিকেশন'),
        'icon': Icons.verified_user_outlined,
        'bg': const Color(0xFFF0FDF4),
        'border': const Color(0xFFBBF7D0),
        'iconColor': const Color(0xFF16A34A),
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const KycPage()),
          );
        },
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LanguageService.tr('Quick Actions', 'দ্রুত অ্যাকশন'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.2,
          ),
          itemBuilder: (context, index) {
            final act = actions[index];
            final Color bg = act['bg'] as Color;
            final Color border = act['border'] as Color;
            final Color iconColor = act['iconColor'] as Color;

            return InkWell(
              onTap: act['onTap'] as VoidCallback?,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: iconColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(act['icon'] as IconData,
                          color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        act['title'] as String,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
