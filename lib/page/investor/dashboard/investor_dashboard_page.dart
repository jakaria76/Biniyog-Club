import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../authentication/login_page.dart';
import '../documents/documents_page.dart';
import '../groups/browse_groups_page.dart';
import '../groups/group_investments_page.dart';
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

  /// Sign out / account delete er por dakte hobe — na hole porer user
  /// kichukkhon ager user er dashboard dekhte pay
  static void clearCache() => _InvestorDashboardPageState.clearCache();

  @override
  State<InvestorDashboardPage> createState() => _InvestorDashboardPageState();
}

class _InvestorDashboardPageState extends State<InvestorDashboardPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _user;

  // ─── Palette (Islamic: emerald, gold, turquoise, lapis, terracotta) ───
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
  static const Color lapisDeep = Color(0xFF1A2F57);
  static const Color lapisSoft = Color(0xFFE5EAF4);

  static const Color terracotta = Color(0xFFA5523A);
  static const Color terracottaSoft = Color(0xFFF7E6DF);

  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);
  static const Color danger = Color(0xFFB4413A);

  static const List<(Color, Color)> _accents = [
    (emerald, emeraldSoft),
    (turquoise, turquoiseSoft),
    (lapis, lapisSoft),
    (goldDeep, goldSoft),
    (terracotta, terracottaSoft),
  ];

  // Recent Investments: ekbare koyta dekhabe, r protita row er height
  static const int _recentVisibleCount = 3;
  static const double _recentItemHeight = 70;

  // ─── Data ─────────────────────────────────────────────────
  String? _avatarUrl;
  int _unreadNotificationCount = 0;
  double _totalInvested = 0.0;
  double _projectInvested = 0.0;
  double _groupInvested = 0.0;
  double _returnsEarned = 0.0;
  double _portfolioValue = 0.0;
  int _activeCount = 0;
  int _pendingTransactions = 0;
  double _pendingAmount = 0.0;

  List<Map<String, dynamic>> _openProjects = [];
  List<Map<String, dynamic>> _recentInvestments = [];

  /// User er shesh notification — "Latest update" banner e dekhay
  Map<String, dynamic>? _latestNotif;

  final ScrollController _recentScrollController = ScrollController();

  // ─── Cache ───
  static Map<String, dynamic>? _cachedSummary;
  static Map<String, dynamic>? _cachedUser;
  static Map<String, dynamic>? _cachedLatestNotif;

  static void clearCache() {
    _cachedSummary = null;
    _cachedUser = null;
    _cachedLatestNotif = null;
  }

  @override
  void initState() {
    super.initState();
    if (_cachedSummary != null && _cachedSummary!.isNotEmpty && _cachedUser != null) {
      _applySummary(_cachedSummary!, _cachedUser);
      _latestNotif = _cachedLatestNotif;
      _isLoading = false;
      _loadDashboardData(background: true);
    } else {
      _loadDashboardData();
    }
  }

  void _applySummary(Map<String, dynamic> summary, Map<String, dynamic>? userData) {
    _user = userData ?? _user;
    _avatarUrl = summary['avatarUrl']?.toString();
    _unreadNotificationCount = (summary['unreadNotificationCount'] as int? ?? 0);
    _totalInvested = (summary['totalInvested'] as double? ?? 0.0);
    _projectInvested = (summary['projectInvested'] as double? ?? 0.0);
    _groupInvested = (summary['groupInvested'] as double? ?? 0.0);
    _returnsEarned = (summary['totalReturns'] as double? ?? 0.0);
    _portfolioValue = _totalInvested + _returnsEarned;
    _activeCount = (summary['activeInvestmentsCount'] as int? ?? 0);
    _pendingTransactions = (summary['pendingTransactionsCount'] as int? ?? 0);
    _pendingAmount = (summary['pendingInvestmentsAmount'] as double? ?? 0.0);
    _openProjects = (summary['openProjects'] as List<Map<String, dynamic>>? ?? []);
    _recentInvestments = (summary['recentInvestments'] as List<Map<String, dynamic>>? ?? []);
  }

  @override
  void dispose() {
    _recentScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData({bool background = false}) async {
    if (!background) {
      setState(() => _isLoading = true);
    }

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    final userEmail = userData?['email']?.toString() ?? '';

    // Login chara onner data kokhono dekhabo na — login page e pathai
    if (userId.isEmpty) {
      clearCache();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
      return;
    }

    final results = await Future.wait<dynamic>([
      DatabaseService.getDashboardSummary(userId, email: userEmail),
      DatabaseService.getNotificationsData(userId, limit: 1),
    ]);
    final summary = results[0] as Map<String, dynamic>;
    final notifs = results[1] as List<Map<String, dynamic>>;
    final latest = notifs.isNotEmpty ? notifs.first : null;

    if (mounted) {
      if (summary.isNotEmpty) {
        _cachedSummary = summary;
        _cachedUser = userData;
        _cachedLatestNotif = latest;
        setState(() {
          _applySummary(summary, userData);
          _latestNotif = latest;
          _isLoading = false;
        });
      } else if (!background) {
        setState(() {
          _user = userData;
          _latestNotif = latest;
          _isLoading = false;
        });
      }
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

  double get _roi =>
      _totalInvested > 0 ? ((_returnsEarned / _totalInvested) * 100) : 0.0;

  // DB te 0.16 thakle 16%, 16 thakle o 16% dekhabe
  double _asPercent(double v) => v <= 1 ? v * 100 : v;

  Future<void> _open(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
    if (mounted) _loadDashboardData();
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final String name = _user?['name'] ?? 'Investor';

    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: ivory,
          drawer: _buildAppSidebar(context),
          appBar: _buildAppBar(name),
          body: _isLoading
              ? const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                  color: emerald, strokeWidth: 2.4),
            ),
          )
              : RefreshIndicator(
            onRefresh: _loadDashboardData,
            color: emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              // niche bottom nav er jonno extra jayga
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 120),
              children: [
                _buildGreeting(name),
                const SizedBox(height: 18),
                _buildHeroCard(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _open(const InvestmentsPage()),
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                        label: Text(LanguageService.tr('Invest in a project', 'প্রজেক্টে ইনভেস্ট করুন')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: emerald,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _open(const BrowseGroupsPage()),
                        icon: const Icon(Icons.apartment_rounded, size: 16, color: emerald),
                        label: Text(LanguageService.tr('Invest in Groups', 'গ্রুপে ইনভেস্ট করুন'), style: const TextStyle(color: emerald)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: emerald),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildStatsGrid(),
                const SizedBox(height: 28),
                _buildQuickActionsSection(),
                const SizedBox(height: 28),
                _buildAvailableProjectsSection(),
                const SizedBox(height: 28),
                _buildRecentInvestmentsSection(),
                const SizedBox(height: 20),
                _buildProjectUpdatesSection(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── AppBar ───────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'I';

    return AppBar(
      backgroundColor: ivory,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 64,
      leadingWidth: 64,
      leading: Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Center(
            child: _iconSquare(
              icon: Icons.notes_rounded,
              onTap: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
      ),
      titleSpacing: 6,
      title: Image.asset(
        'assets/images/logo_full.png',
        height: 34,
        errorBuilder: (context, error, stackTrace) => const Text(
          'Biniyog Club',
          style: TextStyle(
            color: emerald,
            fontWeight: FontWeight.w700,
            fontSize: 18,
            letterSpacing: -0.2,
          ),
        ),
      ),
      actions: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            _iconSquare(
              icon: Icons.notifications_none_rounded,
              onTap: () => _open(const NotificationsPage()),
            ),
            if (_unreadNotificationCount > 0)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  constraints:
                  const BoxConstraints(minWidth: 17, minHeight: 17),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: terracotta,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: ivory, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _unreadNotificationCount > 9
                        ? '9+'
                        : '$_unreadNotificationCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => _open(const ProfilePage()),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: gold, width: 1.4),
            ),
            child: _avatar(initial, 17),
          ),
        ),
        const SizedBox(width: 18),
      ],
    );
  }

  Widget _iconSquare({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: ink, size: 20),
        ),
      ),
    );
  }

  Widget _avatar(String initial, double radius) {
    final fallback = Text(
      initial,
      style: TextStyle(
        color: Colors.white,
        fontSize: radius * 0.8,
        fontWeight: FontWeight.w600,
      ),
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: emerald,
      child: ClipOval(
        child: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
            ? Image.network(
          _avatarUrl!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallback,
        )
            : fallback,
      ),
    );
  }

  // ─── Greeting ─────────────────────────────────────────────
  Widget _buildGreeting(String name) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: emeraldSoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: emerald,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                LanguageService.tr('Investor', 'বিনিয়োগকারী'),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: emerald,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Hero Card ────────────────────────────────────────────
  Widget _buildHeroCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: emerald.withAlpha(60),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
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
                  painter: _IslamicPatternPainter(
                    color: Colors.white.withAlpha(16),
                    cell: 46,
                  ),
                ),
              ),
              Positioned(
                top: -60,
                right: -40,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [gold.withAlpha(90), gold.withAlpha(0)],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border:
                    Border.all(color: gold.withAlpha(80), width: 0.8),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          LanguageService.tr(
                              'TOTAL INVESTED', 'মোট বিনিয়োগ'),
                          style: const TextStyle(
                            color: goldLight,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [goldLight, gold],
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.north_east_rounded,
                                  size: 12, color: emeraldDeep),
                              const SizedBox(width: 4),
                              Text(
                                'ROI ${_roi.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  color: emeraldDeep,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _fmt(_totalInvested),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 38,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      LanguageService.tr(
                        '$_activeCount active projects',
                        '$_activeCount টি চলমান প্রজেক্ট',
                      ),
                      style: TextStyle(
                        color: Colors.white.withAlpha(170),
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(18),
                        borderRadius: BorderRadius.circular(14),
                        border:
                        Border.all(color: Colors.white.withAlpha(25)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _heroMetric(
                              LanguageService.tr('Returns', 'রিটার্ন'),
                              _fmt(_returnsEarned),
                              const Color(0xFF7FD6C2),
                            ),
                          ),
                          _heroDivider(),
                          Expanded(
                            child: _heroMetric(
                              LanguageService.tr('Portfolio', 'পোর্টফোলিও'),
                              _fmt(_portfolioValue),
                              goldLight,
                            ),
                          ),
                          _heroDivider(),
                          Expanded(
                            child: _heroMetric(
                              LanguageService.tr('Active', 'চলমান'),
                              '$_activeCount',
                              const Color(0xFF9DB5E8),
                            ),
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
      ),
    );
  }

  Widget _heroDivider() => Container(
    width: 0.8,
    height: 30,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    color: Colors.white.withAlpha(35),
  );

  Widget _heroMetric(String label, String value, Color dot) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withAlpha(160),
                  fontSize: 10.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Colorful Stats Grid ──────────────────────────────────
  Widget _buildStatsGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(
                icon: Icons.trending_up_rounded,
                value: _fmt(_projectInvested),
                label: LanguageService.tr('Project Invested', 'প্রজেক্ট ইনভেস্টেড'),
                color: emerald,
                soft: emeraldSoft,
                onTap: () => _open(const InvestmentsPage()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                icon: Icons.apartment_rounded,
                value: _fmt(_groupInvested),
                label: LanguageService.tr('Group Invested', 'গ্রুপ ইনভেস্টেড'),
                color: turquoise,
                soft: turquoiseSoft,
                onTap: () => _open(const GroupInvestmentsPage()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _statCard(
                icon: Icons.show_chart_rounded,
                value: '${_roi.toStringAsFixed(1)}%',
                label: LanguageService.tr('Return (ROI)', 'রিটার্ন (ROI)'),
                color: goldDeep,
                soft: goldSoft,
                onTap: () => _open(const PortfolioPage()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                icon: Icons.schedule_rounded,
                value: '$_pendingTransactions',
                label: _pendingAmount > 0
                    ? '${LanguageService.tr('Pending', 'অপেক্ষমান')} · ${_fmt(_pendingAmount)}'
                    : LanguageService.tr('Pending', 'অপেক্ষমান'),
                color: terracotta,
                soft: terracottaSoft,
                onTap: () => _open(const InvestmentsPage()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    required Color soft,
    required VoidCallback onTap,
  }) {
    return Material(
      color: soft,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              right: -18,
              bottom: -18,
              width: 80,
              height: 80,
              child: CustomPaint(
                painter: _IslamicPatternPainter(
                  color: color.withAlpha(30),
                  cell: 40,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(icon, size: 17, color: Colors.white),
                      ),
                      const Spacer(),
                      Icon(Icons.arrow_outward_rounded,
                          size: 16, color: color.withAlpha(160)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: color.withAlpha(200),
                      fontWeight: FontWeight.w500,
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

  // ─── Section Header ───────────────────────────────────────
  Widget _sectionHeader(String title, {VoidCallback? onViewAll}) {
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
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              color: ink,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (onViewAll != null)
          InkWell(
            onTap: onViewAll,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: emeraldSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Text(
                    LanguageService.tr('View all', 'সব দেখুন'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: emerald,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 13, color: emerald),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ─── Quick Actions ────────────────────────────────────────
  Widget _buildQuickActionsSection() {
    final actions = [
      (
      LanguageService.tr('Projects', 'প্রজেক্ট'),
      Icons.explore_outlined,
      const MyProjectsPage() as Widget,
      emerald,
      emeraldSoft,
      ),
      (
      LanguageService.tr('Portfolio', 'পোর্টফোলিও'),
      Icons.donut_large_outlined,
      const PortfolioPage() as Widget,
      turquoise,
      turquoiseSoft,
      ),
      (
      LanguageService.tr('Group Invest', 'গ্রুপ ইনভেস্ট'),
      Icons.diversity_3_outlined,
      const GroupInvestmentsPage() as Widget,
      lapis,
      lapisSoft,
      ),
      (
      LanguageService.tr('Documents', 'ডকুমেন্টস'),
      Icons.folder_outlined,
      const DocumentsPage() as Widget,
      goldDeep,
      goldSoft,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: actions.map((a) {
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _open(a.$3),
              child: Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: a.$5,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(a.$2, color: a.$4, size: 24),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    a.$1,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: ink,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Open Projects ────────────────────────────────────────
  Widget _buildAvailableProjectsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          LanguageService.tr('Open for Investment', 'বিনিয়োগের জন্য উন্মুক্ত'),
          onViewAll: () => _open(const MyProjectsPage()),
        ),
        const SizedBox(height: 14),
        _openProjects.isEmpty
            ? _emptyState(
          Icons.inventory_2_outlined,
          LanguageService.tr('No open projects at the moment',
              'বর্তমানে কোনো উন্মুক্ত প্রজেক্ট নেই'),
        )
            : SizedBox(
          height: 384,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: _openProjects.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) =>
                _projectCard(_openProjects[index], index),
          ),
        ),
      ],
    );
  }

  Widget _projectCard(Map<String, dynamic> p, int index) {
    final double progress =
    (p['progress'] as double? ?? 0.0).clamp(0.0, 1.0);
    final pctInt = (progress * 100).toInt();
    final coverUrl = p['coverImageUrl']?.toString() ?? '';
    final location = p['location']?.toString() ?? '';
    final daysLeft = p['daysLeft'] as int? ?? 0;
    final investorsCount = p['investorsCount'] as int? ?? 0;
    final goal = (p['fundingGoalBdt'] as double? ?? 0.0);
    final minInv = (p['minInvestmentBdt'] as double? ?? 0.0);
    // Project er nijer range (returnPctMin–Max), ek hole ekta-i
    final rLo = _asPercent((p['returnMin'] as num?)?.toDouble() ?? 0.0);
    final rHi = _asPercent((p['returnMax'] as num?)?.toDouble() ?? 0.0);
    final accent = _accents[index % _accents.length];

    return GestureDetector(
      onTap: () => _open(
        ProjectDetailPage(projectIdOrSlug: p['id'].toString()),
      ),
      child: Container(
        width: 272,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image
            SizedBox(
              height: 128,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: accent.$1,
                      child: CustomPaint(
                        painter: _IslamicPatternPainter(
                          color: Colors.white.withAlpha(25),
                          cell: 34,
                        ),
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0x99000000)],
                        stops: [0.45, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.$1,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        (p['category'] as String? ?? 'SME')
                            .replaceAll('_', ' ')
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: goldLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule_rounded,
                              size: 12, color: emeraldDeep),
                          const SizedBox(width: 4),
                          Text(
                            LanguageService.tr('$daysLeft days left',
                                '$daysLeft দিন বাকি'),
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: emeraldDeep,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p['title'] as String? ?? 'Project',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: ink,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.place_outlined,
                            size: 13, color: accent.$1),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: muted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Funding progress
                    Row(
                      children: [
                        Text(
                          '$pctInt%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: emerald,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          LanguageService.tr('funded', 'সংগৃহীত'),
                          style:
                          const TextStyle(fontSize: 11, color: muted),
                        ),
                        const Spacer(),
                        Text(
                          '${LanguageService.tr('Goal', 'লক্ষ্য')} ${_fmt(goal)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    _gradientProgress(progress),
                    const SizedBox(height: 12),

                    // Metrics
                    Row(
                      children: [
                        _projectMetric(
                          LanguageService.tr('Return', 'রিটার্ন'),
                          rLo == rHi
                              ? '${rHi.toStringAsFixed(0)}%'
                              : '${rLo.toStringAsFixed(0)}–${rHi.toStringAsFixed(0)}%',
                          emerald,
                          emeraldSoft,
                        ),
                        const SizedBox(width: 6),
                        _projectMetric(
                          LanguageService.tr('Tenure', 'মেয়াদ'),
                          LanguageService.tr('${p['durationDays']}d',
                              '${p['durationDays']} দিন'),
                          lapis,
                          lapisSoft,
                        ),
                        const SizedBox(width: 6),
                        _projectMetric(
                          LanguageService.tr('Investors', 'বিনিয়োগকারী'),
                          '$investorsCount',
                          goldDeep,
                          goldSoft,
                        ),
                      ],
                    ),
                    const Spacer(),

                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              LanguageService.tr(
                                  'Minimum investment', 'সর্বনিম্ন বিনিয়োগ'),
                              style: const TextStyle(
                                  fontSize: 10, color: muted),
                            ),
                            Text(
                              _fmt(minInv),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF136247), emerald],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Text(
                                LanguageService.tr('Invest', 'বিনিয়োগ'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_forward_rounded,
                                  size: 14, color: Colors.white),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradientProgress(double value) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: const Color(0xFFEDE8DE),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value == 0 ? 0.02 : value,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [emerald, turquoise]),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _projectMetric(String label, String value, Color color, Color soft) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: soft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9.5, color: color.withAlpha(190)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Recent Investments ───────────────────────────────────
  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('pend') || s.contains('review')) return goldDeep;
    if (s.contains('reject') || s.contains('cancel') || s.contains('fail')) {
      return danger;
    }
    return emerald;
  }

  Widget _buildRecentInvestmentsSection() {
    final int count = _recentInvestments.length;
    final bool scrollable = count > _recentVisibleCount;
    // 3 ta porjonto sob dekhabe, tar beshi hole 3 ta row er height e scroll hobe
    final double listHeight =
        (scrollable ? _recentVisibleCount : count) * _recentItemHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          LanguageService.tr('Recent Investments', 'সাম্প্রতিক বিনিয়োগ'),
          onViewAll: () => _open(const InvestmentsPage()),
        ),
        const SizedBox(height: 14),
        _recentInvestments.isEmpty
            ? _emptyState(
          Icons.receipt_long_outlined,
          LanguageService.tr('You have not invested yet',
              'এখনো কোনো বিনিয়োগ করা হয়নি'),
          actionLabel:
          LanguageService.tr('Explore projects', 'প্রজেক্ট দেখুন'),
          onAction: () => _open(const MyProjectsPage()),
        )
            : Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: line),
          ),
          child: SizedBox(
            height: listHeight,
            child: Scrollbar(
              controller: _recentScrollController,
              thumbVisibility: scrollable,
              child: ListView.builder(
                controller: _recentScrollController,
                padding: EdgeInsets.zero,
                itemExtent: _recentItemHeight,
                physics: scrollable
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                itemCount: count,
                itemBuilder: (context, index) {
                  final item = _recentInvestments[index];
                  final title = item['title']?.toString() ?? '';
                  final status = item['status']?.toString() ?? '';
                  final sc = _statusColor(status);
                  final accent = _accents[index % _accents.length];
                  final bool isLast = index == count - 1;

                  return Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: accent.$2,
                                  borderRadius:
                                  BorderRadius.circular(13),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  title.isNotEmpty
                                      ? title[0].toUpperCase()
                                      : '•',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: accent.$1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment:
                                  MainAxisAlignment.center,
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: ink,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item['createdAt']?.toString() ??
                                          '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11, color: muted),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                mainAxisAlignment:
                                MainAxisAlignment.center,
                                crossAxisAlignment:
                                CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _fmt(item['amountBdt'] as double? ??
                                        0.0),
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: ink,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: sc.withAlpha(25),
                                      borderRadius:
                                      BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      status,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: sc,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!isLast)
                        const Divider(
                          height: 1,
                          thickness: 1,
                          color: line,
                          indent: 70,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Latest update (user er shesh notification) ───────────
  // Kono notification na thakle banner dekhay-i na — banano lekha nei
  String _updateWhen(String raw) {
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (diff == 0) return LanguageService.tr('Today', 'আজ');
    if (diff == 1) return LanguageService.tr('Yesterday', 'গতকাল');
    return '${months[d.month - 1]} ${d.day}';
  }

  Widget _buildProjectUpdatesSection() {
    final n = _latestNotif;
    if (n == null) return const SizedBox.shrink();

    final title = n['title']?.toString() ?? '';
    final body = n['body']?.toString() ?? '';
    final when = _updateWhen(n['createdAt']?.toString() ?? '');
    final isNew = n['isRead'] == false;

    return GestureDetector(
      onTap: () => _open(const NotificationsPage()),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [lapis, lapisDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _IslamicPatternPainter(
                    color: Colors.white.withAlpha(14),
                    cell: 38,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient:
                        const LinearGradient(colors: [goldLight, gold]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.campaign_outlined,
                          color: lapisDeep, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                isNew
                                    ? LanguageService.tr('NEW UPDATE', 'নতুন আপডেট')
                                    : LanguageService.tr('LATEST UPDATE', 'সর্বশেষ আপডেট'),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: goldLight,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              if (when.isNotEmpty) ...[
                                Text(
                                  '  ·  $when',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white.withAlpha(150),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            title.isNotEmpty ? title : body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.white.withAlpha(180), size: 22),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(
      IconData icon,
      String text, {
        String? actionLabel,
        VoidCallback? onAction,
      }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: goldSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: goldDeep),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: ink,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                backgroundColor: emeraldSoft,
                foregroundColor: emerald,
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // DRAWER
  // ═════════════════════════════════════════════════════════
  Widget _buildAppSidebar(BuildContext context) {
    final String name = _user?['name'] ?? 'Investor';
    final String email = _user?['email'] ?? '';
    final String initial = name.isNotEmpty ? name[0].toUpperCase() : 'I';

    final menuItems = [
      (LanguageService.tr('Overview', 'ওভারভিউ'),
      Icons.space_dashboard_outlined,
      const InvestorDashboardPage() as Widget),
      (LanguageService.tr('Investments', 'ইনভেস্টমেন্টস'),
      Icons.pie_chart_outline_rounded, const InvestmentsPage() as Widget),
      (LanguageService.tr('Group Invest', 'গ্রুপ ইনভেস্ট'),
      Icons.diversity_3_outlined, const GroupInvestmentsPage() as Widget),
      (LanguageService.tr('My Projects', 'আমার প্রজেক্টস'),
      Icons.business_center_outlined, const MyProjectsPage() as Widget),
      (LanguageService.tr('Portfolio', 'পোর্টফোলিও'),
      Icons.donut_large_outlined, const PortfolioPage() as Widget),
      (LanguageService.tr('Documents', 'ডকুমেন্টস'), Icons.folder_outlined,
      const DocumentsPage() as Widget),
      (LanguageService.tr('Reports', 'রিপোর্টস'), Icons.bar_chart_rounded,
      const ReportsPage() as Widget),
      (LanguageService.tr('Notifications', 'নোটিফিকেশনস'),
      Icons.notifications_none_rounded,
      const NotificationsPage() as Widget),
      (LanguageService.tr('Profile', 'প্রোফাইল'),
      Icons.person_outline_rounded, const ProfilePage() as Widget),
      (LanguageService.tr('Settings', 'সেটিংস'), Icons.settings_outlined,
      const SettingsPage() as Widget),
    ];

    return Drawer(
      backgroundColor: emeraldDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 220,
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.transparent],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: CustomPaint(
                painter: _IslamicPatternPainter(
                  color: Colors.white.withAlpha(14),
                  cell: 40,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 10, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: gold, width: 1),
                        ),
                        child: const Icon(Icons.show_chart_rounded,
                            color: goldLight, size: 19),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Biniyog Club',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white60, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 18, 24, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'MENU',
                      style: TextStyle(
                        color: goldLight,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: menuItems.length,
                    itemBuilder: (context, index) {
                      final item = menuItems[index];
                      final bool active = index == 0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Material(
                          color: active
                              ? Colors.white.withAlpha(18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.pop(context);
                              if (!active) _open(item.$3);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 3,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color:
                                      active ? gold : Colors.transparent,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(
                                    item.$2,
                                    size: 20,
                                    color: active
                                        ? goldLight
                                        : Colors.white.withAlpha(150),
                                  ),
                                  const SizedBox(width: 14),
                                  Text(
                                    item.$1,
                                    style: TextStyle(
                                      color: active
                                          ? Colors.white
                                          : Colors.white.withAlpha(190),
                                      fontSize: 13.5,
                                      fontWeight: active
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withAlpha(20)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: gold, width: 1),
                        ),
                        child: _avatar(initial, 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withAlpha(130),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.logout_rounded,
                            color: Colors.white.withAlpha(170), size: 19),
                        onPressed: () => _showLogoutConfirmDialog(context),
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

  void _showLogoutConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          title: Text(
            LanguageService.tr('Sign out', 'সাইন আউট'),
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: ink),
          ),
          content: Text(
            LanguageService.tr(
                'Are you sure you want to sign out of your Biniyog Club account?',
                'আপনি কি নিশ্চিত যে আপনি অ্যাকাউন্ট থেকে সাইন আউট করতে চান?'),
            style:
            const TextStyle(fontSize: 13.5, color: muted, height: 1.45),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                LanguageService.tr('Cancel', 'বাতিল'),
                style:
                const TextStyle(color: muted, fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                nav.pop();
                await AuthService.logout();
                clearCache();
                nav.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                      (route) => false,
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: danger,
                foregroundColor: Colors.white,
                padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(LanguageService.tr('Sign out', 'সাইন আউট')),
            ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Islamic geometric pattern (8-point star grid)
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
        _drawStar(canvas, c, r, paint);
        canvas.drawCircle(c, r * 0.32, paint);
      }
    }
  }

  void _drawStar(Canvas canvas, Offset c, double r, Paint paint) {
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
  }

  @override
  bool shouldRepaint(covariant _IslamicPatternPainter old) =>
      old.color != color || old.cell != cell;
}