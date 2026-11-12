import 'dart:async';
import 'dart:math' as math;

import 'package:curved_labeled_navigation_bar/curved_navigation_bar.dart';
import 'package:curved_labeled_navigation_bar/curved_navigation_bar_item.dart';
import 'package:flutter/material.dart';
import '../../public/landing_page.dart';
import '../documents/documents_page.dart';
import '../groups/browse_groups_page.dart';
import '../groups/group_invest_page.dart';
import '../groups/group_investments_page.dart';
import '../help/help_center_page.dart';
import '../profit/profit_returns_page.dart';
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
import '../../../services/email_service.dart';
import '../../../services/push_service.dart';
import '../../../services/language_service.dart';
import 'membership_tier.dart';
import '../../../theme/app_colors.dart';

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

  /// Data ante parini (net nei / server error) — 0 dekhiye bhul bujhabo na
  bool _loadFailed = false;
  Map<String, dynamic>? _user;

  // ─── Palette — website er globals.css er rong (lib/theme/app_colors.dart) ───
  // Purono nam gulo rakha holo jate page er baki code na bodlay;
  // proti ta ekhon website er ekta token.
  static const Color emerald = BC.primary; // --primary (brand-600)
  static const Color emeraldDeep = BC.brand800;
  static const Color emeraldBright = BC.brand500; // logo teal
  static const Color emeraldSoft = BC.secondary;

  static const Color gold = BC.harvest500;
  static const Color goldDeep = BC.harvest600;
  static const Color goldLight = BC.harvest400;
  static const Color goldSoft = BC.accent;

  static const Color turquoise = BC.chart4;
  static const Color turquoiseBright = BC.chart4Light;
  static const Color turquoiseSoft = BC.chart4Muted;

  static const Color lapis = BC.finance600;
  static const Color lapisDeep = BC.finance700;
  static const Color lapisSoft = BC.finance50;

  static const Color terracotta = BC.destructive;
  static const Color terracottaLight = BC.destructiveLight;
  static const Color terracottaSoft = BC.destructiveMuted;

  static const Color amethyst = BC.info;
  static const Color amethystSoft = BC.infoMuted;

  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color danger = BC.destructive;

  static const List<(Color, Color)> _accents = [
    (emerald, emeraldSoft),
    (turquoise, turquoiseSoft),
    (lapis, lapisSoft),
    (goldDeep, goldSoft),
    (terracotta, terracottaSoft),
    (amethyst, amethystSoft),
  ];

  /// Category rong — website er chart palette theke
  static const Map<String, Color> _catColors = {
    'REAL_ESTATE': BC.chart1,
    'TRADE_FINANCE': BC.chart2,
    'SME': BC.chart3,
    'TECHNOLOGY': BC.finance500,
    'INFRASTRUCTURE': BC.chart5,
    'OTHER': BC.neutral,
    'FMCG': BC.chart4,
    'FOOD_AGRO': BC.brand400,
    'PRINTING_PACKAGING': BC.harvest600,
    'COMMUNITY': BC.finance700,
    'GROUP': BC.harvest600,
  };

  // Recent Investments: ekbare koyta dekhabe, r protita row er height
  static const int _recentVisibleCount = 3;
  static const double _recentItemHeight = 58;

  // ─── Data (summary) ───────────────────────────────────────
  String? _avatarUrl;
  int _unreadNotificationCount = 0;
  double _totalInvested = 0.0;
  double _projectInvested = 0.0;
  double _groupInvested = 0.0;
  double _returnsEarned = 0.0;
  int _activeCount = 0;
  int _pendingTransactions = 0;
  double _pendingAmount = 0.0;

  List<Map<String, dynamic>> _openProjects = [];
  List<Map<String, dynamic>> _recentInvestments = [];

  /// Business group er tier gulo (invest kora jay emon) — project er pore carousel e
  List<Map<String, dynamic>> _groupTiers = [];

  /// User er shesh notification — "Latest update" banner e dekhay
  Map<String, dynamic>? _latestNotif;

  // ─── Data (extras — website dashboard er baki section) ────
  bool _hasExtras = false;
  int _projActive = 0;
  int _groupActive = 0;
  int _groupPending = 0;
  int _groupCompleted = 0;
  int _completedCount = 0;
  double _committed = 0;
  double _fullyPaid = 0;

  // Payments in progress (installment / review cholche)
  int _progCount = 0;
  bool _progHasProject = false;
  double _progVerified = 0;
  double _progReview = 0;
  double _progOutstanding = 0;

  // Chart
  List<DateTime> _months = [];
  List<double> _monthInvested = [];
  List<double> _monthReturned = [];
  List<(String, double, Color)> _categorySlices = [];
  List<(String, double, Color)> _statusSlices = [];

  List<Map<String, dynamic>> _groupRecent = [];
  List<Map<String, dynamic>> _updates = [];
  List<Map<String, dynamic>> _documents = [];

  /// Membership tier (Star / Diamond / Crown) — query fail korle null, card lukano
  PrestigeHoldings? _prestige;

  /// Analytics card e kon chart khola
  int _chartTab = 0;

  final ScrollController _recentScrollController = ScrollController();
  final ScrollController _homeScroll = ScrollController();

  /// Bottom nav er kon tab khola (0 = Home)
  int _tab = 0;

  /// Je tab ekbar khola hoyeche shudhu shegulo-i build hoy — app khulle
  /// sob page ek sathe DB query kore na
  final Set<int> _openedTabs = {0};

  /// App khola thakle proti minute e approve/cancel/reject mail check
  Timer? _mailTimer;

  // ─── Cache ───
  static Map<String, dynamic>? _cachedSummary;
  static Map<String, dynamic>? _cachedExtras;
  static Map<String, dynamic>? _cachedUser;
  static Map<String, dynamic>? _cachedLatestNotif;
  static List<Map<String, dynamic>>? _cachedGroupTiers;

  static void clearCache() {
    _cachedSummary = null;
    _cachedExtras = null;
    _cachedUser = null;
    _cachedLatestNotif = null;
    _cachedGroupTiers = null;
  }

  @override
  void initState() {
    super.initState();
    _registerPush();
    _mailTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final u = await AuthService.getUserData();
      final id = u?['id']?.toString() ?? '';
      if (id.isNotEmpty) EmailService.checkStatusMails(id);
    });
    if (_cachedSummary != null && _cachedSummary!.isNotEmpty && _cachedUser != null) {
      _applySummary(_cachedSummary!, _cachedUser);
      if (_cachedExtras != null) _applyExtras(_cachedExtras!);
      _latestNotif = _cachedLatestNotif;
      _groupTiers = _cachedGroupTiers ?? [];
      _isLoading = false;
      _loadDashboardData(background: true);
    } else {
      _loadDashboardData();
    }
  }

  /// Push er jonno ei phone er token save (login er por dashboard-i prothom page)
  Future<void> _registerPush() async {
    final u = await AuthService.getUserData();
    final id = u?['id']?.toString() ?? '';
    // Push e tap korle kon page khulbe — page gulo ekhane import kora ache
    PushService.pageFor = (data) {
      final kind = data['kind']?.toString() ?? '';
      if (kind.isEmpty || kind == 'WELCOME') return const NotificationsPage();
      return data['group']?.toString() == 'true'
          ? const GroupInvestmentsPage()
          : const InvestmentsPage();
    };
    if (id.isNotEmpty) unawaited(PushService.registerForUser(id));
  }

  void _applySummary(Map<String, dynamic> summary, Map<String, dynamic>? userData) {
    _user = userData ?? _user;
    _avatarUrl = summary['avatarUrl']?.toString();
    _unreadNotificationCount = (summary['unreadNotificationCount'] as int? ?? 0);
    _totalInvested = (summary['totalInvested'] as double? ?? 0.0);
    _projectInvested = (summary['projectInvested'] as double? ?? 0.0);
    _groupInvested = (summary['groupInvested'] as double? ?? 0.0);
    _returnsEarned = (summary['totalReturns'] as double? ?? 0.0);
    _activeCount = (summary['activeInvestmentsCount'] as int? ?? 0);
    _pendingTransactions = (summary['pendingTransactionsCount'] as int? ?? 0);
    _pendingAmount = (summary['pendingInvestmentsAmount'] as double? ?? 0.0);
    // Deadline periye gele "Open for Investment" e dekhabo na
    _openProjects = (summary['openProjects'] as List<Map<String, dynamic>>? ?? [])
        .where((p) => p['acceptingInvestment'] != false)
        .toList();
    _recentInvestments = (summary['recentInvestments'] as List<Map<String, dynamic>>? ?? []);
  }

  /// Sob hishab DB er asol row theke — kono banano shongkha nei
  void _applyExtras(Map<String, dynamic> x) {
    final invs = (x['investments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final dists = (x['distributions'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    int projActive = 0, groupActive = 0, groupPending = 0, groupCompleted = 0, completed = 0;
    double committed = 0, fullyPaid = 0;
    int progCount = 0;
    bool progHasProject = false;
    double progVerified = 0, progReview = 0, progOutstanding = 0;

    // Shesh 12 mash (ei mash shoho)
    final now = DateTime.now();
    final months = List.generate(12, (i) => DateTime(now.year, now.month - 11 + i, 1));
    int key(DateTime d) => d.year * 12 + d.month;
    final idx = {for (var i = 0; i < months.length; i++) key(months[i]): i};
    final invested = List<double>.filled(12, 0);
    final returned = List<double>.filled(12, 0);

    final catMap = <String, double>{};
    final statusMap = <String, int>{};

    for (final inv in invs) {
      final kind = inv['kind']?.toString() ?? 'PROJECT';
      final status = (inv['status']?.toString() ?? '').toUpperCase();
      final amount = (inv['amount'] as num?)?.toDouble() ?? 0;
      final approved = (inv['approved'] as num?)?.toDouble() ?? 0;
      final review = (inv['review'] as num?)?.toDouble() ?? 0;
      final live = status != 'CANCELLED' && status != 'REFUNDED';
      final confirmed = status == 'ACTIVE' || status == 'MATURED' || status == 'COMPLETED';

      if (status.isNotEmpty) statusMap[status] = (statusMap[status] ?? 0) + 1;

      if (kind == 'GROUP') {
        if (status == 'ACTIVE') groupActive++;
        if (status == 'PENDING' || status == 'PAYMENT_PENDING') groupPending++;
        if (status == 'COMPLETED') groupCompleted++;
      } else {
        if (status == 'ACTIVE') projActive++;
      }
      if (status == 'COMPLETED' || status == 'MATURED') completed++;

      if (live) {
        committed += amount;
        if (confirmed || (amount > 0 && approved >= amount - 0.5)) fullyPaid += amount;

        final cat = kind == 'GROUP' ? 'GROUP' : (inv['category']?.toString() ?? 'OTHER');
        catMap[cat] = (catMap[cat] ?? 0) + amount;

        final d = DateTime.tryParse(inv['createdAt']?.toString() ?? '')?.toLocal();
        if (d != null) {
          final i = idx[key(d)];
          if (i != null) invested[i] += amount;
        }
      }

      if (status == 'PENDING' || status == 'PAYMENT_PENDING') {
        progCount++;
        if (kind != 'GROUP') progHasProject = true;
        progVerified += approved;
        progReview += review;
        progOutstanding += math.max(0.0, amount - approved - review);
      }
    }

    for (final d in dists) {
      final at = DateTime.tryParse(d['at']?.toString() ?? '')?.toLocal();
      if (at == null) continue;
      final i = idx[key(at)];
      if (i != null) returned[i] += (d['amount'] as num?)?.toDouble() ?? 0;
    }

    final cats = catMap.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final statusOrder = ['ACTIVE', 'PAYMENT_PENDING', 'PENDING', 'MATURED', 'COMPLETED', 'CANCELLED', 'REFUNDED'];
    final sts = statusMap.entries.toList()
      ..sort((a, b) {
        final ia = statusOrder.indexOf(a.key), ib = statusOrder.indexOf(b.key);
        return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
      });

    _hasExtras = x['ok'] == true;
    _projActive = projActive;
    _groupActive = groupActive;
    _groupPending = groupPending;
    _groupCompleted = groupCompleted;
    _completedCount = completed;
    _committed = committed;
    _fullyPaid = fullyPaid;
    _progCount = progCount;
    _progHasProject = progHasProject;
    _progVerified = progVerified;
    _progReview = progReview;
    _progOutstanding = progOutstanding;
    _months = months;
    _monthInvested = invested;
    _monthReturned = returned;
    _categorySlices = cats
        .map((e) => (
    e.key == 'GROUP'
        ? LanguageService.tr('Business groups', 'বিজনেস গ্রুপ')
        : _categoryLabel(e.key),
    e.value,
    _catColors[e.key] ?? muted,
    ))
        .toList();
    _statusSlices = sts
        .map((e) => (_statusLabel(e.key), e.value.toDouble(), _statusColor(e.key)))
        .toList();
    _groupRecent = (x['groupRecent'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    _updates = (x['updates'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    _documents = (x['documents'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final pr = x['prestige'];
    _prestige = pr is Map
        ? PrestigeHoldings(
      stars: (pr['stars'] as num?)?.toInt() ?? 0,
      diamonds: math.min((pr['diamonds'] as num?)?.toInt() ?? 0, kMaxDiamonds),
      crowns: (pr['crowns'] as num?)?.toInt() ?? 0,
    )
        : null;
  }

  @override
  void dispose() {
    _mailTimer?.cancel();
    _recentScrollController.dispose();
    _homeScroll.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData({bool background = false}) async {
    if (!background) {
      setState(() => _isLoading = true);
    }

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    final userEmail = userData?['email']?.toString() ?? '';

    // Login chara onner data kokhono dekhabo na
    if (userId.isEmpty) {
      clearCache();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LandingPage()),
            (route) => false,
      );
      return;
    }

    // Admin website e approve / cancel / reject korle mail (background e)
    unawaited(EmailService.checkStatusMails(userId));

    final results = await Future.wait<dynamic>([
      DatabaseService.getDashboardSummary(userId, email: userEmail),
      DatabaseService.getNotificationsData(userId, limit: 1),
      DatabaseService.getDashboardExtras(userId, email: userEmail),
      DatabaseService.getBusinessGroupsWithTiers(),
    ]);
    final summary = results[0] as Map<String, dynamic>;
    final notifs = results[1] as List<Map<String, dynamic>>;
    final extras = results[2] as Map<String, dynamic>;
    final latest = notifs.isNotEmpty ? notifs.first : null;
    final tiers = _flattenTiers(results[3] as List<Map<String, dynamic>>);

    if (!mounted) return;
    if (summary['ok'] == true) {
      _cachedSummary = summary;
      _cachedUser = userData;
      _cachedLatestNotif = latest;
      if (extras['ok'] == true) _cachedExtras = extras;
      if (tiers.isNotEmpty) _cachedGroupTiers = tiers;
      setState(() {
        if (tiers.isNotEmpty) _groupTiers = tiers;
        _applySummary(summary, userData);
        if (extras['ok'] == true) _applyExtras(extras);
        _latestNotif = latest;
        _isLoading = false;
        _loadFailed = false;
      });
    } else if (!background || _cachedSummary == null) {
      // Ager data na thakle error dekhai; thakle sheta-i rakhi
      setState(() {
        _user = userData;
        _latestNotif = latest;
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  /// Group → entity → tier theke ek list. Bank account ache emon tier age
  /// (sheta-i invest kora jay), baki gulo "Coming Soon" hishebe pore.
  static List<Map<String, dynamic>> _flattenTiers(List<Map<String, dynamic>> groups) {
    final out = <Map<String, dynamic>>[];
    for (final g in groups) {
      for (final e in (g['entities'] as List? ?? [])) {
        final entity = Map<String, dynamic>.from(e as Map);
        for (final t in (entity['tiers'] as List? ?? [])) {
          out.add({
            'tier': Map<String, dynamic>.from(t as Map),
            'groupName': g['name']?.toString() ?? '',
            'groupSlug': g['slug']?.toString() ?? '',
            'entityName': entity['name']?.toString() ?? '',
          });
        }
      }
    }
    out.sort((a, b) {
      final ao = (a['tier'] as Map)['bank'] != null ? 0 : 1;
      final bo = (b['tier'] as Map)['bank'] != null ? 0 : 1;
      return ao.compareTo(bo);
    });
    return out;
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  static String _fmt(double amount) {
    if (amount >= 10000000) {
      return '৳${(amount / 10000000).toStringAsFixed(2)} Cr';
    } else if (amount >= 100000) {
      return '৳${(amount / 100000).toStringAsFixed(2)}L';
    } else if (amount >= 1000) {
      return '৳${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '৳${amount.toStringAsFixed(0)}';
  }

  /// Website er category nam
  static String _categoryLabel(String c) {
    switch (c) {
      case 'REAL_ESTATE': return LanguageService.tr('Real Estate', 'রিয়েল এস্টেট');
      case 'TRADE_FINANCE': return LanguageService.tr('Trade Finance', 'ট্রেড ফাইন্যান্স');
      case 'SME': return 'SME';
      case 'TECHNOLOGY': return LanguageService.tr('Technology', 'প্রযুক্তি');
      case 'INFRASTRUCTURE': return LanguageService.tr('Infrastructure', 'অবকাঠামো');
      case 'FMCG': return 'FMCG';
      case 'FOOD_AGRO': return LanguageService.tr('Food & Agro', 'খাদ্য ও কৃষি');
      case 'PRINTING_PACKAGING': return LanguageService.tr('Printing & Packaging', 'প্রিন্টিং ও প্যাকেজিং');
      case 'COMMUNITY': return LanguageService.tr('Community', 'কমিউনিটি');
      case 'OTHER': return LanguageService.tr('Other', 'অন্যান্য');
      default: return c.replaceAll('_', ' ');
    }
  }

  static String _statusLabel(String s) {
    switch (s.toUpperCase()) {
      case 'PENDING': return LanguageService.tr('Pending', 'অপেক্ষমান');
      case 'PAYMENT_PENDING': return LanguageService.tr('Awaiting payment', 'পেমেন্ট বাকি');
      case 'ACTIVE': return LanguageService.tr('Active', 'চলমান');
      case 'MATURED': return LanguageService.tr('Matured', 'মেয়াদপূর্ণ');
      case 'COMPLETED': return LanguageService.tr('Completed', 'সম্পন্ন');
      case 'CANCELLED': return LanguageService.tr('Cancelled', 'বাতিল');
      case 'REFUNDED': return LanguageService.tr('Refunded', 'ফেরত');
      default: return s.replaceAll('_', ' ');
    }
  }

  static Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('pend') || s.contains('review')) return gold;
    if (s.contains('reject') || s.contains('cancel') || s.contains('fail')) return danger;
    if (s.contains('refund')) return muted;
    if (s.contains('complete')) return lapis;
    if (s.contains('matur')) return turquoise;
    return emeraldBright;
  }

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String _fmtDate(String raw, {bool year = true}) {
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return '';
    return year
        ? '${d.day} ${_monthNames[d.month - 1]} ${d.year}'
        : '${d.day} ${_monthNames[d.month - 1]}';
  }

  double get _roi =>
      _totalInvested > 0 ? ((_returnsEarned / _totalInvested) * 100) : 0.0;

  // DB te 0.16 thakle 16%, 16 thakle o 16% dekhabe
  double _asPercent(double v) => v <= 1 ? v * 100 : v;

  /// Website er groupLogo() — assets/Group logos/
  static String? _groupLogo(String slug) {
    switch (slug.toUpperCase()) {
      case 'MARINERS': return 'assets/Group logos/Mariners Group logo.png';
      case 'MOHS': return 'assets/Group logos/MOHS Group logo.png';
      case 'MARINOZZ': return 'assets/Group logos/Marinozz Group logo.png';
      case 'COMMUNITY_VENTURES': return 'assets/Group logos/Community Ventures Logo.png';
      case 'VENTURE_ALLIANCES': return 'assets/Group logos/Venture Alliance Logo.png';
      default: return null;
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => page));
    // Fire ashle chupchap refresh — spinner diye pura page dhake na
    if (mounted) _loadDashboardData(background: true);
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final String name = _user?['name']?.toString() ?? '';

    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return PopScope(
          // Onno tab e thakle back chaple age Home e ashe, tarpor app theke ber hoy
          canPop: _tab == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _tab != 0) _selectTab(0);
          },
          child: Scaffold(
            backgroundColor: ivory,
            // Home e curve er pichone dashboard dekha jay; onno page e na
            extendBody: _tab == 0,
            drawer: _tab == 0 ? _buildAppSidebar(context) : null,
            appBar: _tab == 0 ? _buildAppBar(name) : null,
            body: IndexedStack(
              index: _tab,
              children: [
                _buildHomeTab(),
                _lazyTab(1, const MyProjectsPage()),
                _lazyTab(2, const BrowseGroupsPage()),
                _lazyTab(3, const InvestmentsPage()),
                _lazyTab(4, const ProfilePage()),
              ],
            ),
            bottomNavigationBar: _buildBottomNav(),
          ),
        );
      },
    );
  }

  Widget _lazyTab(int i, Widget page) =>
      _openedTabs.contains(i) ? page : const SizedBox.shrink();

  void _selectTab(int i) {
    if (i == _tab) {
      // Home e thakle abar Home chaple upore niye jay
      if (i == 0 && _homeScroll.hasClients) {
        _homeScroll.animateTo(0,
            duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
      }
      return;
    }
    setState(() {
      _tab = i;
      _openedTabs.add(i);
    });
    // Onno tab e kichu bodlale (invest / payment) Home e fire notun data
    if (i == 0) _loadDashboardData(background: true);
  }

  // ─── Bottom Navigation (curved_labeled_navigation_bar) ────
  Widget _buildBottomNav() {
    // Sobuj bar, sada icon — kono sonali nei
    Widget icon(IconData on, IconData off, int i) => Icon(
      _tab == i ? on : off,
      size: 22,
      color: _tab == i ? Colors.white : Colors.white.withAlpha(200),
    );
    const label = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white);

    return CurvedNavigationBar(
      index: _tab,
      height: 64,
      color: emerald, // card gular moto sobuj
      buttonBackgroundColor: emeraldBright, // bubble o sobuj, icon sada
      backgroundColor: Colors.transparent,
      animationCurve: Curves.easeOutCubic,
      animationDuration: const Duration(milliseconds: 450),
      items: [
        CurvedNavigationBarItem(
          child: icon(Icons.home_rounded, Icons.home_outlined, 0),
          label: LanguageService.tr('Home', 'হোম'),
          labelStyle: label,
        ),
        CurvedNavigationBarItem(
          child: icon(Icons.explore_rounded, Icons.explore_outlined, 1),
          label: LanguageService.tr('Projects', 'প্রজেক্ট'),
          labelStyle: label,
        ),
        CurvedNavigationBarItem(
          child: icon(Icons.apartment_rounded, Icons.apartment_outlined, 2),
          label: LanguageService.tr('Groups', 'গ্রুপ'),
          labelStyle: label,
        ),
        CurvedNavigationBarItem(
          child: icon(Icons.pie_chart_rounded, Icons.pie_chart_outline_rounded, 3),
          label: LanguageService.tr('Invested', 'বিনিয়োগ'),
          labelStyle: label,
        ),
        CurvedNavigationBarItem(
          child: icon(Icons.person_rounded, Icons.person_outline_rounded, 4),
          label: LanguageService.tr('Profile', 'প্রোফাইল'),
          labelStyle: label,
        ),
      ],
      onTap: _selectTab,
    );
  }

  // ─── Home tab (dashboard) ─────────────────────────────────
  Widget _buildHomeTab() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4),
        ),
      );
    }
    if (_loadFailed) return _buildErrorState();

    return RefreshIndicator(
      onRefresh: () => _loadDashboardData(background: true),
      color: emerald,
      child: ListView(
        controller: _homeScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        // niche curved nav er jonno extra jayga
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 104),
        children: [
          _buildHeroCard(),
          if (_documents.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildDocumentsCard(),
          ],
          // Website er motoi — hero er porei membership tier
          if (_prestige != null) ...[
            const SizedBox(height: 14),
            MembershipTierCard(holdings: _prestige!),
          ],
          const SizedBox(height: 14),
          _buildStatsGrid(),
          const SizedBox(height: 20),
          _buildQuickActionsSection(),
          if (_groupRecent.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildGroupInvestmentsSection(),
          ],
          const SizedBox(height: 20),
          _buildAvailableProjectsSection(),
          if (_groupTiers.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildGroupTiersSection(),
          ],
          if (_hasExtras) ...[
            const SizedBox(height: 20),
            _buildAnalyticsSection(),
          ],
          const SizedBox(height: 20),
          _buildRecentInvestmentsSection(),
          const SizedBox(height: 20),
          _buildProjectUpdatesSection(),
          const SizedBox(height: 12),
          _buildLatestNotificationBanner(),
        ],
      ),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'B';

    return AppBar(
      backgroundColor: ivory,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 56,
      leadingWidth: 58,
      leading: Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.only(left: 16),
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
        'assets/logo.png',
        height: 40,
        fit: BoxFit.contain,
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
                  constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: terracotta,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: ivory, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _unreadNotificationCount > 9 ? '9+' : '$_unreadNotificationCount',
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
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _selectTab(4),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: gold, width: 1.4),
            ),
            child: _avatar(initial, 15),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _iconSquare({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: const BorderSide(color: line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: SizedBox(width: 36, height: 36, child: Icon(icon, color: ink, size: 18)),
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

  // ─── Error (data ana jayni) ───────────────────────────────
  Widget _buildErrorState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 110),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: terracottaSoft, shape: BoxShape.circle),
            child: const Icon(Icons.wifi_off_rounded, color: terracotta, size: 28),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          LanguageService.tr('Could not load your dashboard', 'ড্যাশবোর্ড লোড করা যায়নি'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
        ),
        const SizedBox(height: 6),
        Text(
          LanguageService.tr('Please check your internet connection and try again.',
              'ইন্টারনেট সংযোগ দেখে আবার চেষ্টা করুন।'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: muted, height: 1.4),
        ),
        const SizedBox(height: 18),
        Center(
          child: FilledButton.icon(
            onPressed: () => _loadDashboardData(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(LanguageService.tr('Try again', 'আবার চেষ্টা করুন')),
            style: FilledButton.styleFrom(
              backgroundColor: emerald,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════
  // HERO — website er "Portfolio hero"
  // ═════════════════════════════════════════════════════════
  Widget _buildHeroCard() {
    final projActive = _hasExtras ? _projActive : _activeCount;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: emerald.withAlpha(70), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [emeraldBright, emerald],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          LanguageService.tr('TOTAL INVESTED', 'মোট বিনিয়োগ'),
                          style: TextStyle(
                            color: Colors.white.withAlpha(200),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.north_east_rounded, size: 11, color: emeraldDeep),
                              const SizedBox(width: 4),
                              Text(
                                '${_roi.toStringAsFixed(1)}% ROI',
                                style: const TextStyle(
                                  color: emeraldDeep,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _fmt(_totalInvested),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _hasExtras
                          ? LanguageService.tr(
                          '$projActive project${projActive == 1 ? '' : 's'} · $_groupActive group investment${_groupActive == 1 ? '' : 's'} active',
                          '$projActive টি প্রজেক্ট · $_groupActive টি গ্রুপ বিনিয়োগ চলমান')
                          : LanguageService.tr('$_activeCount active investments', '$_activeCount টি চলমান বিনিয়োগ'),
                      style: TextStyle(color: Colors.white.withAlpha(175), fontSize: 11.5),
                    ),
                    if (_progCount > 0) ...[
                      const SizedBox(height: 12),
                      _buildPaymentsInProgress(),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _heroButton(
                            label: LanguageService.tr('Invest in a project', 'প্রজেক্টে বিনিয়োগ'),
                            icon: Icons.arrow_forward_rounded,
                            filled: true,
                            onTap: () => _selectTab(1),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _heroButton(
                            label: LanguageService.tr('Invest in Groups', 'গ্রুপে বিনিয়োগ'),
                            icon: Icons.apartment_rounded,
                            filled: false,
                            onTap: () => _selectTab(2),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildHeroMetricsGrid(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroButton({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
          decoration: BoxDecoration(
            color: filled ? Colors.white : Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(11),
            border: filled ? null : Border.all(color: Colors.white.withAlpha(45)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!filled) ...[
                Icon(icon, size: 14, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: filled ? emeraldDeep : Colors.white,
                  ),
                ),
              ),
              if (filled) ...[
                const SizedBox(width: 6),
                Icon(icon, size: 14, color: emeraldDeep),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Installment / review cholche emon investment er hishab (website er motoi)
  Widget _buildPaymentsInProgress() {
    final owed = _progVerified + _progReview + _progOutstanding;
    double frac(double v) => owed > 0 ? (v / owed).clamp(0.0, 1.0) : 0.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (_progHasProject) {
            _selectTab(3);
          } else {
            _open(const GroupInvestmentsPage());
          }
        },
        child: Ink(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(16),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withAlpha(28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      LanguageService.tr(
                          'Payments in progress · $_progCount investment${_progCount == 1 ? '' : 's'}',
                          'পেমেন্ট চলছে · $_progCount টি বিনিয়োগ'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withAlpha(220),
                      ),
                    ),
                  ),
                  Text(
                    LanguageService.tr('${_fmt(_progVerified)} of ${_fmt(owed)} paid',
                        '${_fmt(owed)} এর ${_fmt(_progVerified)} পরিশোধিত'),
                    style: TextStyle(fontSize: 10.5, color: Colors.white.withAlpha(140)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 6,
                  child: LayoutBuilder(
                    builder: (context, c) => Stack(
                      children: [
                        Container(color: Colors.white.withAlpha(25)),
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: c.maxWidth * frac(_progVerified),
                          child: Container(color: BC.brand300),
                        ),
                        Positioned(
                          left: c.maxWidth * frac(_progVerified),
                          top: 0,
                          bottom: 0,
                          width: c.maxWidth * frac(_progReview),
                          child: Container(color: Colors.white.withAlpha(170)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _progLegend(LanguageService.tr('Verified', 'যাচাইকৃত'), _progVerified, BC.brand300),
                  _progLegend(LanguageService.tr('Under review', 'যাচাই চলছে'), _progReview, Colors.white.withAlpha(170)),
                  _progLegend(LanguageService.tr('Still to pay', 'বাকি'), _progOutstanding, Colors.white.withAlpha(90)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progLegend(String label, double value, Color dot) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: Colors.white.withAlpha(140)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _fmt(value),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ],
      ),
    );
  }

  /// Website er 6 ta ghor: Project invested / Fully paid / Committed /
  /// Group invested / Returns earned / Completed
  Widget _buildHeroMetricsGrid() {
    final items = <(String, String, Color)>[
      (LanguageService.tr('Projects', 'প্রজেক্ট'), _fmt(_projectInvested), BC.brand300),
      if (_hasExtras)
        (LanguageService.tr('Fully paid', 'সম্পূর্ণ পরিশোধিত'), _fmt(_fullyPaid), Colors.white),
      if (_hasExtras)
        (LanguageService.tr('Committed', 'প্রতিশ্রুত'), _fmt(_committed), BC.financeLight),
      (LanguageService.tr('Groups', 'গ্রুপ'), _fmt(_groupInvested), BC.chart4Light),
      (LanguageService.tr('Returns', 'রিটার্ন'), _fmt(_returnsEarned), BC.brand200),
      if (_hasExtras)
        (LanguageService.tr('Completed', 'সম্পন্ন'), '$_completedCount', BC.destructiveOnDark),
    ];

    // 3 kolam e 2 sari — kom jaygay sob
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 3) {
      if (i > 0) rows.add(Container(height: 1, color: Colors.white.withAlpha(20)));
      rows.add(IntrinsicHeight(
        child: Row(
          children: [
            for (var j = i; j < i + 3; j++) ...[
              if (j > i) Container(width: 1, color: Colors.white.withAlpha(20)),
              Expanded(child: j < items.length ? _heroCell(items[j]) : const SizedBox()),
            ],
          ],
        ),
      ));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(children: rows),
    );
  }

  Widget _heroCell((String, String, Color) item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: item.$3, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  item.$1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              item.$2,
              style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // DOCUMENTS — confirmed investment er receipt / deed
  // ═════════════════════════════════════════════════════════
  Widget _buildDocumentsCard() {
    final shown = _documents.take(3).toList();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: emeraldBright.withAlpha(70)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [emeraldSoft, BC.brand50]),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [emeraldBright, emerald]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.verified_outlined, color: Colors.white, size: 17),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LanguageService.tr('Confirmed investments', 'নিশ্চিত বিনিয়োগ'),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink),
                      ),
                      Text(
                        LanguageService.tr('Receipt & deed numbers of your investments',
                            'আপনার বিনিয়োগের রসিদ ও দলিল নম্বর'),
                        style: const TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _open(const DocumentsPage()),
                  style: TextButton.styleFrom(
                    foregroundColor: emerald,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text(
                    LanguageService.tr('Documents', 'ডকুমেন্টস'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: line, indent: 14, endIndent: 14),
            InkWell(
              onTap: () => _selectTab(3),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shown[i]['title']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _miniChip(_fmt((shown[i]['amount'] as num?)?.toDouble() ?? 0), emerald, emeraldSoft),
                              if ((shown[i]['receiptNumber']?.toString() ?? '').isNotEmpty)
                                _miniChip(shown[i]['receiptNumber'].toString(), goldDeep, goldSoft, mono: true),
                              if ((shown[i]['deedNumber']?.toString() ?? '').isNotEmpty)
                                _miniChip('${LanguageService.tr('Deed', 'দলিল')} ${shown[i]['deedNumber']}',
                                    lapis, lapisSoft, mono: true),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: muted, size: 17),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniChip(String text, Color color, Color soft, {bool mono = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(8)),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
          fontFamily: mono ? 'monospace' : null,
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // STAT CARDS — Project Portfolio / ROI / Group / Pending
  // ═════════════════════════════════════════════════════════
  Widget _buildStatsGrid() {
    final projActive = _hasExtras ? _projActive : _activeCount;
    final groupPendingCount = _hasExtras ? _groupPending : 0;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(
                icon: Icons.bar_chart_rounded,
                title: LanguageService.tr('Project Portfolio', 'প্রজেক্ট পোর্টফোলিও'),
                value: _fmt(_projectInvested + _returnsEarned),
                sub: LanguageService.tr('$projActive active project${projActive == 1 ? '' : 's'}',
                    '$projActive টি চলমান প্রজেক্ট'),
                colors: const [emeraldBright, emerald],
                onTap: () => _open(const PortfolioPage()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                icon: Icons.trending_up_rounded,
                title: 'ROI',
                value: '${_roi.toStringAsFixed(1)}%',
                sub: LanguageService.tr('From distributed returns', 'বিতরণকৃত রিটার্ন থেকে'),
                colors: const [emeraldBright, emerald],
                onTap: () => _open(const PortfolioPage()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _statCard(
                icon: Icons.apartment_rounded,
                title: LanguageService.tr('Group Investments', 'গ্রুপ বিনিয়োগ'),
                value: _fmt(_groupInvested),
                sub: _hasExtras
                    ? LanguageService.tr('$_groupActive active · $groupPendingCount pending',
                    '$_groupActive চলমান · $groupPendingCount অপেক্ষমান')
                    : LanguageService.tr('Business groups', 'বিজনেস গ্রুপ'),
                colors: const [emeraldBright, emerald],
                onTap: () => _open(const GroupInvestmentsPage()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                icon: Icons.hourglass_top_rounded,
                title: LanguageService.tr('Pending', 'অপেক্ষমান'),
                value: '$_pendingTransactions',
                sub: _pendingAmount > 0
                    ? LanguageService.tr('Awaiting approval · ${_fmt(_pendingAmount)}',
                    'অনুমোদনের অপেক্ষায় · ${_fmt(_pendingAmount)}')
                    : LanguageService.tr('Awaiting approval', 'অনুমোদনের অপেক্ষায়'),
                colors: const [emeraldBright, emerald],
                onTap: () => _selectTab(3),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required String title,
    required String value,
    required String sub,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: colors.last.withAlpha(45), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(45),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(icon, size: 14, color: Colors.white),
                          ),
                          const Spacer(),
                          Icon(Icons.arrow_outward_rounded, size: 13, color: Colors.white.withAlpha(200)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.white.withAlpha(215),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9.5, color: Colors.white.withAlpha(190)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Section Header ───────────────────────────────────────
  Widget _sectionHeader(String title, {String? subtitle, VoidCallback? onViewAll, String? viewAllLabel}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [goldLight, gold])),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: ink,
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(subtitle, style: const TextStyle(fontSize: 10.5, color: muted)),
            ],
          ),
        ),
        if (onViewAll != null)
          InkWell(
            onTap: onViewAll,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: emeraldSoft, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  Text(
                    viewAllLabel ?? LanguageService.tr('View all', 'সব দেখুন'),
                    style: const TextStyle(fontSize: 11, color: emerald, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.arrow_forward_rounded, size: 12, color: emerald),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════
  // QUICK ACTIONS — rongin tile
  // ═════════════════════════════════════════════════════════
  Widget _buildQuickActionsSection() {
    final actions = <(String, IconData, List<Color>, VoidCallback)>[
      (LanguageService.tr('Browse & invest', 'প্রজেক্ট দেখুন'), Icons.explore_rounded,
      const [emeraldBright, emerald], () => _selectTab(1)),
      (LanguageService.tr('Invest in Groups', 'গ্রুপে বিনিয়োগ'), Icons.apartment_rounded,
      const [BC.harvest400, BC.harvest600], () => _selectTab(2)),
      (LanguageService.tr('All investments', 'সব বিনিয়োগ'), Icons.pie_chart_rounded,
      const [BC.finance500, BC.finance700], () => _selectTab(3)),
      (LanguageService.tr('Group Invest', 'গ্রুপ বিনিয়োগ'), Icons.diversity_3_rounded,
      const [BC.chart4, BC.chart4Deep], () => _open(const GroupInvestmentsPage())),
      (LanguageService.tr('Portfolio', 'পোর্টফোলিও'), Icons.donut_large_rounded,
      const [BC.info, BC.finance700], () => _open(const PortfolioPage())),
      (LanguageService.tr('Documents', 'ডকুমেন্টস'), Icons.description_rounded,
      const [BC.harvest500, BC.harvest600], () => _open(const DocumentsPage())),
      (LanguageService.tr('Reports', 'রিপোর্টস'), Icons.bar_chart_rounded,
      const [BC.destructiveLight, BC.destructiveDeep], () => _open(const ReportsPage())),
      (LanguageService.tr('Notifications', 'নোটিফিকেশন'), Icons.notifications_rounded,
      const [BC.brand500, BC.brand700], () => _open(const NotificationsPage())),
    ];

    Widget tile((String, IconData, List<Color>, VoidCallback) a) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: a.$4,
          child: Column(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: a.$3,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(color: a.$3.last.withAlpha(55), blurRadius: 6, offset: const Offset(0, 3)),
                  ],
                ),
                child: Stack(
                  children: [
                    Center(child: Icon(a.$2, color: Colors.white, size: 19)),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                a.$1,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(fontSize: 9.8, color: ink, fontWeight: FontWeight.w600, height: 1.2),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(LanguageService.tr('Quick actions', 'দ্রুত কাজ')),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: line),
          ),
          child: Column(
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: actions.take(4).map(tile).toList()),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: actions.skip(4).map(tile).toList()),
            ],
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════
  // GROUP INVESTMENTS — website er table er motoi
  // ═════════════════════════════════════════════════════════
  Widget _buildGroupInvestmentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          LanguageService.tr('Group Investments', 'গ্রুপ বিনিয়োগ'),
          subtitle: LanguageService.tr(
              '$_groupActive active · $_groupPending pending · $_groupCompleted completed',
              '$_groupActive চলমান · $_groupPending অপেক্ষমান · $_groupCompleted সম্পন্ন'),
          onViewAll: () => _open(const GroupInvestmentsPage()),
        ),
        const SizedBox(height: 10),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _groupRecent.length; i++) ...[
                if (i > 0) const Divider(height: 1, thickness: 1, color: line, indent: 60),
                _groupRow(_groupRecent[i], i),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _groupRow(Map<String, dynamic> g, int index) {
    final slug = g['slug']?.toString() ?? '';
    final groupName = g['groupName']?.toString() ?? '';
    final entity = g['entityName']?.toString() ?? '';
    final tier = g['tierName']?.toString() ?? '';
    final date = _fmtDate(g['createdAt']?.toString() ?? '', year: false);
    final status = g['status']?.toString() ?? '';
    final sc = _statusColor(status);
    final logo = _groupLogo(slug);
    final accent = _accents[index % _accents.length];
    final initial = groupName.isNotEmpty ? groupName[0].toUpperCase() : 'G';

    final fallback = Container(
      color: accent.$2,
      alignment: Alignment.center,
      child: Text(initial, style: TextStyle(fontWeight: FontWeight.w800, color: accent.$1, fontSize: 16)),
    );

    return InkWell(
      onTap: () => _open(const GroupInvestmentsPage()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: line),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: logo != null
                    ? Image.asset(logo, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback)
                    : fallback,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [groupName, entity].where((e) => e.isNotEmpty).join(' — '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [tier, date].where((e) => e.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _fmt((g['amount'] as num?)?.toDouble() ?? 0),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ink),
                ),
                const SizedBox(height: 4),
                _statusPill(status, sc),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String status, Color sc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: sc.withAlpha(28), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(color: sc, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(
            _statusLabel(status),
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: sc),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // OPEN PROJECTS
  // ═════════════════════════════════════════════════════════
  Widget _buildAvailableProjectsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          LanguageService.tr('Open for Investment', 'বিনিয়োগের জন্য উন্মুক্ত'),
          subtitle: LanguageService.tr('Vetted projects currently raising capital.',
              'যাচাইকৃত প্রজেক্ট, এখন বিনিয়োগ নিচ্ছে'),
          onViewAll: () => _selectTab(1),
        ),
        const SizedBox(height: 10),
        _openProjects.isEmpty
            ? _emptyState(
          Icons.inventory_2_outlined,
          LanguageService.tr('No open projects at the moment', 'বর্তমানে কোনো উন্মুক্ত প্রজেক্ট নেই'),
        )
            : SizedBox(
          height: 286,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: _openProjects.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _projectCard(_openProjects[index], index),
          ),
        ),
      ],
    );
  }

  Widget _projectCard(Map<String, dynamic> p, int index) {
    final double progress = (p['progress'] as double? ?? 0.0).clamp(0.0, 1.0);
    final pctInt = (progress * 100).toInt();
    final coverUrl = p['coverImageUrl']?.toString() ?? '';
    final location = p['location']?.toString() ?? '';
    final daysLeft = p['daysLeft'] as int? ?? 0;
    final hasDeadline = p['hasDeadline'] == true;
    final durationDays = p['durationDays'] as int? ?? 0;
    final title = p['title']?.toString() ?? '';
    final investorsCount = p['investorsCount'] as int? ?? 0;
    final goal = (p['fundingGoalBdt'] as double? ?? 0.0);
    final minInv = (p['minInvestmentBdt'] as double? ?? 0.0);
    final category = p['category']?.toString() ?? '';
    final rLo = _asPercent((p['returnMin'] as num?)?.toDouble() ?? 0.0);
    final rHi = _asPercent((p['returnMax'] as num?)?.toDouble() ?? 0.0);
    final catColor = _catColors[category] ?? _accents[index % _accents.length].$1;

    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [catColor, emeraldDeep]),
      ),
    );

    return GestureDetector(
      onTap: () => _open(ProjectDetailPage(projectIdOrSlug: p['id'].toString())),
      child: Container(
        width: 222,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: line),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 96,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  coverUrl.isEmpty
                      ? placeholder
                      : Image.network(coverUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder),
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
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: catColor, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        _categoryLabel(category).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                  if (hasDeadline)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: goldLight, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule_rounded, size: 11, color: emeraldDeep),
                            const SizedBox(width: 4),
                            Text(
                              daysLeft > 1
                                  ? LanguageService.tr('$daysLeft days left', '$daysLeft দিন বাকি')
                                  : daysLeft == 1
                                  ? LanguageService.tr('Closes tomorrow', 'কাল শেষ দিন')
                                  : LanguageService.tr('Closes today', 'আজ শেষ দিন'),
                              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: emeraldDeep),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink, letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 3),
                    if (location.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.place_outlined, size: 13, color: catColor),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10.5, color: muted),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('$pctInt%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: emerald)),
                        const SizedBox(width: 4),
                        Text(LanguageService.tr('funded', 'সংগৃহীত'), style: const TextStyle(fontSize: 10, color: muted)),
                        const Spacer(),
                        Text(
                          goal > 0 ? '${LanguageService.tr('Goal', 'লক্ষ্য')} ${_fmt(goal)}' : '',
                          style: const TextStyle(fontSize: 10, color: ink, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    _gradientProgress(progress),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _projectMetric(
                          LanguageService.tr('Return', 'রিটার্ন'),
                          rHi <= 0
                              ? '—'
                              : (rLo <= 0 || rLo == rHi)
                              ? '${rHi.toStringAsFixed(0)}%'
                              : '${rLo.toStringAsFixed(0)}–${rHi.toStringAsFixed(0)}%',
                          emerald,
                          emeraldSoft,
                        ),
                        const SizedBox(width: 6),
                        _projectMetric(
                          LanguageService.tr('Tenure', 'মেয়াদ'),
                          durationDays <= 0
                              ? '—'
                              : durationDays >= 60
                              ? LanguageService.tr('${(durationDays / 30).round()} mo', '${(durationDays / 30).round()} মাস')
                              : LanguageService.tr('${durationDays}d', '$durationDays দিন'),
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
                              LanguageService.tr('Minimum investment', 'সর্বনিম্ন বিনিয়োগ'),
                              style: const TextStyle(fontSize: 9, color: muted),
                            ),
                            Text(
                              minInv > 0 ? _fmt(minInv) : '—',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ink),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [emeraldBright, emerald]),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Text(
                                LanguageService.tr('Details', 'বিস্তারিত'),
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.white),
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
      height: 5,
      decoration: BoxDecoration(color: BC.muted, borderRadius: BorderRadius.circular(4)),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value == 0 ? 0.02 : value,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [emeraldBright, turquoiseBright]),
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
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
        decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(8)),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 8.5, color: color.withAlpha(190)),
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // GROUP INVESTMENT — tier gulo dane-baame scroll
  // ═════════════════════════════════════════════════════════
  static String _tierTypeLabel(String t) {
    switch (t.toUpperCase()) {
      case 'SHAREHOLDER': return LanguageService.tr('Shareholder', 'শেয়ারহোল্ডার');
      case 'DIRECTORSHIP': return LanguageService.tr('Directorship', 'ডিরেক্টরশিপ');
      case 'PLOT_BOOKING': return LanguageService.tr('Plot Booking', 'প্লট বুকিং');
      case 'LAND_SHARE': return LanguageService.tr('Land Share', 'জমির শেয়ার');
      default: return LanguageService.tr('Investor', 'বিনিয়োগকারী');
    }
  }

  static (Color, Color) _tierColors(String t) {
    switch (t.toUpperCase()) {
      case 'SHAREHOLDER': return (BC.finance600, BC.finance500);
      case 'DIRECTORSHIP': return (BC.finance700, BC.info);
      case 'PLOT_BOOKING': return (terracotta, terracottaLight);
      case 'LAND_SHARE': return (BC.brand700, BC.brand500);
      default: return (turquoise, turquoiseBright);
    }
  }

  Future<void> _openGroupTier(Map<String, dynamic> t) async {
    final tier = t['tier'] as Map<String, dynamic>;
    if (tier['availableUnits'] != null && (tier['availableUnits'] as num) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(LanguageService.tr('This tier is sold out.', 'এই টিয়ারের সব ইউনিট বিক্রি হয়ে গেছে।')),
        backgroundColor: goldDeep,
      ));
      return;
    }
    if (tier['bank'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(LanguageService.tr('Coming soon — payment details for this tier are not ready yet.',
            'শীঘ্রই আসছে — এই টিয়ারের পেমেন্ট তথ্য এখনো প্রস্তুত নয়।')),
        backgroundColor: goldDeep,
      ));
      return;
    }
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupInvestPage(
          tier: tier,
          groupName: t['groupName']?.toString() ?? '',
          entityName: t['entityName']?.toString() ?? '',
        ),
      ),
    );
    if (!mounted) return;
    _loadDashboardData(background: true);
    if (ok == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(LanguageService.tr('Submitted! Your group investment is pending admin approval.',
            'জমা হয়েছে! অ্যাডমিন অনুমোদনের পর গ্রুপ বিনিয়োগ চালু হবে।')),
        backgroundColor: emerald,
      ));
    }
  }

  Widget _buildGroupTiersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          LanguageService.tr('Invest in Business Groups', 'বিজনেস গ্রুপে বিনিয়োগ'),
          subtitle: LanguageService.tr('Shares, directorships and plots — swipe to see all',
              'শেয়ার, ডিরেক্টরশিপ ও প্লট — সব দেখতে পাশে টানুন'),
          onViewAll: () => _selectTab(2),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 236,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: _groupTiers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _groupTierCard(_groupTiers[i]),
          ),
        ),
      ],
    );
  }

  Widget _groupTierCard(Map<String, dynamic> t) {
    final tier = t['tier'] as Map<String, dynamic>;
    final groupName = t['groupName']?.toString() ?? '';
    final entityName = t['entityName']?.toString() ?? '';
    final slug = t['groupSlug']?.toString() ?? '';
    final type = tier['type']?.toString() ?? 'INVESTOR';
    final colors = _tierColors(type);
    // Unit er hishab thakle 0 = bikri shesh
    final soldOut = tier['availableUnits'] != null && (tier['availableUnits'] as num) <= 0;
    final open = tier['bank'] != null && !soldOut;
    final minAmt = (tier['minAmountBdt'] as num?)?.toDouble() ?? 0;
    final maxAmt = (tier['maxAmountBdt'] as num?)?.toDouble();
    final ret = _asPercent((tier['expectedReturnPct'] as num?)?.toDouble() ?? 0);
    final months = (tier['durationMonths'] as num?)?.toInt() ?? 0;
    final logo = _groupLogo(slug);
    final showEntity = entityName.isNotEmpty && entityName.toLowerCase() != groupName.toLowerCase();
    final initial = groupName.isNotEmpty ? groupName[0].toUpperCase() : 'G';

    return GestureDetector(
      onTap: () => _openGroupTier(t),
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: line),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Rongin matha — tier er dhoron onujayi rong, majhe group er logo
            SizedBox(
              height: 74,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colors.$1, colors.$2],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
                      width: 70,
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
                      alignment: Alignment.center,
                      child: logo != null
                          ? Image.asset(logo,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Text(initial,
                              style: TextStyle(fontWeight: FontWeight.w800, color: colors.$1, fontSize: 15)))
                          : Text(initial, style: TextStyle(fontWeight: FontWeight.w800, color: colors.$1, fontSize: 15)),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(235),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _tierTypeLabel(type).toUpperCase(),
                        style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: colors.$1, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                  if (!open)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: goldLight, borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          LanguageService.tr('COMING SOON', 'শীঘ্রই আসছে'),
                          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: emeraldDeep),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tier['name']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      showEntity ? '$groupName · $entityName' : groupName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: muted),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _projectMetric(
                          LanguageService.tr('Return', 'রিটার্ন'),
                          ret > 0 ? '${ret.toStringAsFixed(ret == ret.roundToDouble() ? 0 : 1)}%' : '—',
                          emerald,
                          emeraldSoft,
                        ),
                        const SizedBox(width: 6),
                        _projectMetric(
                          LanguageService.tr('Tenure', 'মেয়াদ'),
                          months > 0 ? LanguageService.tr('$months mo', '$months মাস') : '—',
                          lapis,
                          lapisSoft,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(LanguageService.tr('Investment', 'বিনিয়োগ'),
                                  style: const TextStyle(fontSize: 9, color: muted)),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  minAmt <= 0
                                      ? '—'
                                      : (maxAmt != null && maxAmt > minAmt)
                                      ? '${_fmt(minAmt)} – ${_fmt(maxAmt)}'
                                      : LanguageService.tr('From ${_fmt(minAmt)}', '${_fmt(minAmt)} থেকে'),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ink),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: open ? LinearGradient(colors: [colors.$2, colors.$1]) : null,
                            color: open ? null : ivory,
                            borderRadius: BorderRadius.circular(10),
                            border: open ? null : Border.all(color: line),
                          ),
                          child: Text(
                            open
                                ? LanguageService.tr('Invest', 'বিনিয়োগ')
                                : soldOut
                                ? LanguageService.tr('Sold out', 'শেষ')
                                : LanguageService.tr('Soon', 'শীঘ্রই'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: open ? Colors.white : muted,
                            ),
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

  // ═════════════════════════════════════════════════════════
  // ANALYTICS — website er 4 ta chart
  // ═════════════════════════════════════════════════════════
  Widget _buildAnalyticsSection() {
    final tabs = <(String, IconData)>[
      (LanguageService.tr('Activity', 'কার্যক্রম'), Icons.show_chart_rounded),
      (LanguageService.tr('Distributions', 'বিতরণ'), Icons.bar_chart_rounded),
      (LanguageService.tr('Allocation', 'বরাদ্দ'), Icons.donut_large_rounded),
      (LanguageService.tr('Status', 'স্ট্যাটাস'), Icons.pie_chart_rounded),
    ];

    Widget body;
    switch (_chartTab) {
      case 1:
        body = _distributionChart();
        break;
      case 2:
        body = _donutChart(
          _categorySlices,
          LanguageService.tr('By category', 'ক্যাটাগরি অনুযায়ী'),
          money: true,
          empty: LanguageService.tr('No investments yet.', 'এখনো কোনো বিনিয়োগ নেই।'),
        );
        break;
      case 3:
        body = _donutChart(
          _statusSlices,
          LanguageService.tr('Investments', 'বিনিয়োগ'),
          money: false,
          empty: LanguageService.tr('No investments yet.', 'এখনো কোনো বিনিয়োগ নেই।'),
        );
        break;
      default:
        body = _activityChart();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          LanguageService.tr('Analytics', 'বিশ্লেষণ'),
          subtitle: LanguageService.tr('Your last 12 months at a glance', 'শেষ ১২ মাসের হিসাব এক নজরে'),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < tabs.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _chartTab = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: _chartTab == i
                                  ? const LinearGradient(colors: [emeraldBright, emerald])
                                  : null,
                              color: _chartTab == i ? null : ivory,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _chartTab == i ? Colors.transparent : line),
                            ),
                            child: Row(
                              children: [
                                Icon(tabs[i].$2, size: 12, color: _chartTab == i ? goldLight : muted),
                                const SizedBox(width: 5),
                                Text(
                                  tabs[i].$1,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _chartTab == i ? Colors.white : ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: KeyedSubtree(key: ValueKey(_chartTab), child: body),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chartEmpty(String text) {
    return SizedBox(
      height: 110,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: goldSoft, shape: BoxShape.circle),
              child: const Icon(Icons.insights_rounded, color: goldDeep, size: 18),
            ),
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(fontSize: 12, color: muted)),
          ],
        ),
      ),
    );
  }

  Widget _monthLabels() {
    return Row(
      children: [
        for (var i = 0; i < _months.length; i++)
          Expanded(
            child: Text(
              // Jayga kom — ek mash por por nam
              i.isEven || i == _months.length - 1 ? _monthNames[_months[i].month - 1] : '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, color: muted),
            ),
          ),
      ],
    );
  }

  Widget _legendDot(Color c, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11.5, color: muted)),
        const SizedBox(width: 5),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ink)),
      ],
    );
  }

  /// Investment Activity — mashik invested vs returns
  Widget _activityChart() {
    final has = _monthInvested.any((v) => v > 0) || _monthReturned.any((v) => v > 0);
    if (!has) return _chartEmpty(LanguageService.tr('No activity yet.', 'এখনো কোনো কার্যক্রম নেই।'));
    final maxV = [..._monthInvested, ..._monthReturned].fold<double>(0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            _legendDot(emeraldBright, LanguageService.tr('Invested', 'বিনিয়োগ'),
                _fmt(_monthInvested.fold(0.0, (a, b) => a + b))),
            _legendDot(gold, LanguageService.tr('Returns', 'রিটার্ন'),
                _fmt(_monthReturned.fold(0.0, (a, b) => a + b))),
          ],
        ),
        const SizedBox(height: 8),
        Text(_fmt(maxV), style: const TextStyle(fontSize: 9.5, color: muted)),
        const SizedBox(height: 4),
        SizedBox(
          height: 120,
          width: double.infinity,
          child: CustomPaint(
            painter: _AreaChartPainter(
              series: [_monthInvested, _monthReturned],
              colors: const [emeraldBright, gold],
              gridColor: line,
            ),
          ),
        ),
        const SizedBox(height: 6),
        _monthLabels(),
      ],
    );
  }

  /// Distribution History — mashe koto profit pelen
  Widget _distributionChart() {
    final has = _monthReturned.any((v) => v > 0);
    if (!has) {
      return _chartEmpty(LanguageService.tr('No distributions yet.', 'এখনো কোনো রিটার্ন বিতরণ হয়নি।'));
    }
    final maxV = _monthReturned.fold<double>(0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _legendDot(gold, LanguageService.tr('Received in 12 months', '১২ মাসে প্রাপ্ত'),
            _fmt(_monthReturned.fold(0.0, (a, b) => a + b))),
        const SizedBox(height: 8),
        Text(_fmt(maxV), style: const TextStyle(fontSize: 9.5, color: muted)),
        const SizedBox(height: 4),
        SizedBox(
          height: 120,
          width: double.infinity,
          child: CustomPaint(
            painter: _BarChartPainter(values: _monthReturned, colors: const [goldLight, goldDeep], gridColor: line),
          ),
        ),
        const SizedBox(height: 6),
        _monthLabels(),
      ],
    );
  }

  /// Portfolio Allocation / Investment Status — donut + legend
  Widget _donutChart(List<(String, double, Color)> slices, String centerLabel,
      {required bool money, required String empty}) {
    if (slices.isEmpty) return _chartEmpty(empty);
    final total = slices.fold<double>(0, (a, s) => a + s.$2);
    return Column(
      children: [
        SizedBox(
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: CustomPaint(painter: _DonutPainter(slices: slices)),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    money ? _fmt(total) : total.toStringAsFixed(0),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink),
                  ),
                  Text(centerLabel, style: const TextStyle(fontSize: 11, color: muted)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (final s in slices)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: s.$3, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(s.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: ink, fontWeight: FontWeight.w600)),
                ),
                Text(
                  money ? _fmt(s.$2) : s.$2.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: ink),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${total > 0 ? (s.$2 / total * 100).round() : 0}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: s.$3),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════
  // RECENT INVESTMENTS
  // ═════════════════════════════════════════════════════════
  Widget _buildRecentInvestmentsSection() {
    final int count = _recentInvestments.length;
    final bool scrollable = count > _recentVisibleCount;
    // 3 ta porjonto sob dekhabe, tar beshi hole 3 ta row er height e scroll hobe
    final double listHeight = (scrollable ? _recentVisibleCount : count) * _recentItemHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          LanguageService.tr('Recent Investments', 'সাম্প্রতিক বিনিয়োগ'),
          onViewAll: () => _selectTab(3),
        ),
        const SizedBox(height: 10),
        _recentInvestments.isEmpty
            ? _emptyState(
          Icons.receipt_long_outlined,
          LanguageService.tr('You have not invested yet', 'এখনো কোনো বিনিয়োগ করা হয়নি'),
          actionLabel: LanguageService.tr('Browse projects', 'প্রজেক্ট দেখুন'),
          onAction: () => _selectTab(1),
        )
            : Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
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
                physics: scrollable ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
                itemCount: count,
                itemBuilder: (context, index) => _recentRow(index, count),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _recentRow(int index, int count) {
    final item = _recentInvestments[index];
    final isGroup = item['kind'] == 'GROUP';
    final title = item['title']?.toString() ?? '';
    final subtitle = item['subtitle']?.toString() ?? '';
    final status = item['status']?.toString() ?? '';
    final date = _fmtDate(item['createdAt']?.toString() ?? '');
    final meta = [
      isGroup ? LanguageService.tr('Group', 'গ্রুপ') : LanguageService.tr('Project', 'প্রজেক্ট'),
      if (subtitle.isNotEmpty) subtitle,
      if (date.isNotEmpty) date,
    ].join(' · ');
    final sc = _statusColor(status);
    final accent = _accents[index % _accents.length];
    final bool isLast = index == count - 1;

    return InkWell(
      onTap: () {
        if (isGroup) {
          _open(const GroupInvestmentsPage());
        } else {
          _selectTab(3);
        }
      },
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [accent.$2, accent.$2.withAlpha(150)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      isGroup ? Icons.diversity_3_rounded : Icons.business_center_rounded,
                      size: 17,
                      color: accent.$1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _fmt(item['amountBdt'] as double? ?? 0.0),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ink),
                      ),
                      const SizedBox(height: 4),
                      _statusPill(status, sc),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (!isLast) const Divider(height: 1, thickness: 1, color: line, indent: 58),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // PROJECT UPDATES — user je project e invest koreche
  // ═════════════════════════════════════════════════════════
  String _updateWhen(String raw) {
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return LanguageService.tr('Today', 'আজ');
    if (diff == 1) return LanguageService.tr('Yesterday', 'গতকাল');
    return '${d.day} ${_monthNames[d.month - 1]}';
  }

  (String, Color, IconData) _updateType(String t) {
    switch (t.toUpperCase()) {
      case 'MILESTONE':
        return (LanguageService.tr('Milestone', 'মাইলফলক'), goldDeep, Icons.flag_rounded);
      case 'ISSUE':
        return (LanguageService.tr('Issue', 'সমস্যা'), terracotta, Icons.report_gmailerrorred_rounded);
      case 'FINANCIAL_REPORT':
        return (LanguageService.tr('Financial report', 'আর্থিক রিপোর্ট'), lapis, Icons.receipt_long_rounded);
      default:
        return (LanguageService.tr('Update', 'আপডেট'), emeraldBright, Icons.campaign_rounded);
    }
  }

  Widget _buildProjectUpdatesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          LanguageService.tr('Project updates', 'প্রজেক্ট আপডেট'),
          onViewAll: () => _open(const NotificationsPage()),
          viewAllLabel: LanguageService.tr('All', 'সব'),
        ),
        const SizedBox(height: 10),
        _updates.isEmpty
            ? _emptyState(Icons.campaign_outlined, LanguageService.tr('No updates yet.', 'এখনো কোনো আপডেট নেই।'))
            : Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _updates.length; i++) ...[
                if (i > 0) const Divider(height: 1, thickness: 1, color: line, indent: 56),
                _updateRow(_updates[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _updateRow(Map<String, dynamic> u) {
    final t = _updateType(u['type']?.toString() ?? '');
    final projectId = u['projectId']?.toString() ?? '';
    final when = _updateWhen(u['at']?.toString() ?? '');
    return InkWell(
      onTap: projectId.isEmpty ? null : () => _open(ProjectDetailPage(projectIdOrSlug: projectId)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: t.$2.withAlpha(30), borderRadius: BorderRadius.circular(12)),
              child: Icon(t.$3, size: 16, color: t.$2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    u['title']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(t.$1, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: t.$2)),
                      Flexible(
                        child: Text(
                          '  ·  ${u['projectTitle'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (when.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(when, style: const TextStyle(fontSize: 10.5, color: muted)),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Latest notification banner ───────────────────────────
  // Kono notification na thakle banner dekhay-i na — banano lekha nei
  Widget _buildLatestNotificationBanner() {
    final n = _latestNotif;
    if (n == null) return const SizedBox.shrink();

    final title = n['title']?.toString() ?? '';
    final body = n['body']?.toString() ?? '';
    final when = _updateWhen(n['createdAt']?.toString() ?? '');
    final isNew = n['isRead'] == false;

    return GestureDetector(
      onTap: () => _open(const NotificationsPage()),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [BC.finance500, BC.finance700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [goldLight, gold]),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(Icons.notifications_active_outlined, color: lapisDeep, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                isNew
                                    ? LanguageService.tr('NEW NOTIFICATION', 'নতুন নোটিফিকেশন')
                                    : LanguageService.tr('LATEST NOTIFICATION', 'সর্বশেষ নোটিফিকেশন'),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: goldLight,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              if (when.isNotEmpty)
                                Text(
                                  '  ·  $when',
                                  style: TextStyle(fontSize: 10, color: Colors.white.withAlpha(150)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            title.isNotEmpty ? title : body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: Colors.white.withAlpha(180), size: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String text, {String? actionLabel, VoidCallback? onAction}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(color: goldSoft, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: goldDeep),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: ink, fontWeight: FontWeight.w500),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                backgroundColor: emeraldSoft,
                foregroundColor: emerald,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(actionLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // DRAWER — website er sidebar er motoi 3 bhag e
  // ═════════════════════════════════════════════════════════
  Widget _buildAppSidebar(BuildContext context) {
    final String name = _user?['name']?.toString() ?? '';
    // Email optional — na thakle phone dekhai
    final String emailRaw = _user?['email']?.toString() ?? '';
    final String subtitle = emailRaw.isNotEmpty ? emailRaw : (_user?['phone']?.toString() ?? '');
    final String initial = name.isNotEmpty ? name[0].toUpperCase() : 'B';

    // (label, icon, tab index — null hole page push hoy, page)
    final groups = <(String, List<(String, IconData, int?, Widget?)>)>[
      (
      LanguageService.tr('OVERVIEW', 'ওভারভিউ'),
      [
        (LanguageService.tr('Overview', 'ওভারভিউ'), Icons.space_dashboard_outlined, 0, null),
        (LanguageService.tr('Portfolio', 'পোর্টফোলিও'), Icons.donut_large_outlined, null, const PortfolioPage()),
        (LanguageService.tr('Reports', 'রিপোর্টস'), Icons.bar_chart_rounded, null, const ReportsPage()),
      ],
      ),
      (
      LanguageService.tr('INVESTING', 'বিনিয়োগ'),
      [
        (LanguageService.tr('Investments', 'ইনভেস্টমেন্টস'), Icons.trending_up_rounded, 3, null),
        (LanguageService.tr('Group Invest', 'গ্রুপ ইনভেস্ট'), Icons.apartment_rounded, null, const GroupInvestmentsPage()),
        (LanguageService.tr('Profit Returns', 'প্রফিট রিটার্নস'), Icons.savings_outlined, null, const ProfitReturnsPage()),
        (LanguageService.tr('Projects', 'প্রজেক্টস'), Icons.folder_open_rounded, 1, null),
      ],
      ),
      (
      LanguageService.tr('ACCOUNT', 'অ্যাকাউন্ট'),
      [
        (LanguageService.tr('Documents', 'ডকুমেন্টস'), Icons.description_outlined, null, const DocumentsPage()),
        (LanguageService.tr('Notifications', 'নোটিফিকেশনস'), Icons.notifications_none_rounded, null, const NotificationsPage()),
        (LanguageService.tr('Help Center', 'হেল্প সেন্টার'), Icons.support_agent_rounded, null, const HelpCenterPage()),
        (LanguageService.tr('Profile', 'প্রোফাইল'), Icons.person_outline_rounded, 4, null),
        (LanguageService.tr('Settings', 'সেটিংস'), Icons.settings_outlined, null, const SettingsPage()),
      ],
      ),
    ];

    Widget item((String, IconData, int?, Widget?) it) {
      // Je tab e achen sheta-i highlight (age shudhu Overview hoto)
      final active = it.$3 != null && it.$3 == _tab;
      final showBadge = it.$4 is NotificationsPage && _unreadNotificationCount > 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: Material(
          color: active ? Colors.white.withAlpha(34) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              Navigator.pop(context);
              if (it.$3 != null) {
                _selectTab(it.$3!);
              } else if (it.$4 != null) {
                _open(it.$4!);
              }
            },
            child: SizedBox(
              height: 38,
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      color: active ? goldLight : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Icon(it.$2, size: 18, color: active ? goldLight : Colors.white.withAlpha(150)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      it.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? Colors.white : Colors.white.withAlpha(215),
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (showBadge)
                    Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(color: terracotta, borderRadius: BorderRadius.circular(9)),
                      child: Text(
                        _unreadNotificationCount > 9 ? '9+' : '$_unreadNotificationCount',
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 5),
      child: Text(
        title,
        style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.6),
      ),
    );

    // Dashboard er card / navbar er motoi sobuj (emeraldBright → emerald)
    return Drawer(
      width: math.min(300, MediaQuery.of(context).size.width * 0.82),
      backgroundColor: emerald,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(22)),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [emeraldBright, emerald],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 200,
              child: IgnorePointer(
                child: ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.transparent],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: CustomPaint(
                    painter: _IslamicPatternPainter(color: Colors.white.withAlpha(14), cell: 40),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  // ── Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 6, 10),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: goldLight.withAlpha(150), width: 1),
                          ),
                          child: Image.asset(
                            'assets/logo.png',
                            color: goldLight,
                            colorBlendMode: BlendMode.srcIn,
                            errorBuilder: (_, __, ___) => const Icon(Icons.show_chart_rounded, color: goldLight, size: 17),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Biniyog Club',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              Text(
                                LanguageService.tr('Investor Dashboard', 'বিনিয়োগকারী ড্যাশবোর্ড'),
                                style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 10.5),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 19),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.white.withAlpha(30), indent: 16, endIndent: 16),

                  // ── Menu (lomba phone e scroll, kintu kichu nicher card er niche dhake na)
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
                      children: [
                        for (final g in groups) ...[
                          section(g.$1),
                          for (final it in g.$2) item(it),
                        ],
                        const SizedBox(height: 12),
                        // Website er "Explore new projects" — choto ek line
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.pop(context);
                              _selectTab(1);
                            },
                            child: Ink(
                              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: LinearGradient(
                                  colors: [Colors.white.withAlpha(30), Colors.white.withAlpha(12)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(color: goldLight.withAlpha(50)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.auto_awesome_rounded, color: BC.harvest400, size: 16),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          LanguageService.tr('Explore new projects', 'নতুন প্রজেক্ট দেখুন'),
                                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                                        ),
                                        Text(
                                          LanguageService.tr('Vetted opportunities open for investment',
                                              'যাচাইকৃত সুযোগ, বিনিয়োগের জন্য উন্মুক্ত'),
                                          style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 10, height: 1.3),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.arrow_forward_rounded, color: goldLight, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── User (sobshomoy nicher dike, alada)
                  Container(
                    margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(22),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withAlpha(30)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: goldLight, width: 1),
                          ),
                          child: _avatar(initial, 15),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.isNotEmpty ? name : LanguageService.tr('Investor', 'বিনিয়োগকারী'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                              ),
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 10.5),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: LanguageService.tr('Sign out', 'সাইন আউট'),
                          icon: Icon(Icons.logout_rounded, color: Colors.white.withAlpha(170), size: 18),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          title: Text(
            LanguageService.tr('Sign out', 'সাইন আউট'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ink),
          ),
          content: Text(
            LanguageService.tr('Are you sure you want to sign out of your Biniyog Club account?',
                'আপনি কি নিশ্চিত যে আপনি অ্যাকাউন্ট থেকে সাইন আউট করতে চান?'),
            style: const TextStyle(fontSize: 13.5, color: muted, height: 1.45),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                LanguageService.tr('Cancel', 'বাতিল'),
                style: const TextStyle(color: muted, fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                nav.pop();
                // Ei phone e ar ei user er push jabe na
                await PushService.unregister();
                await AuthService.logout();
                clearCache();
                nav.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LandingPage()),
                      (route) => false,
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
  bool shouldRepaint(covariant _IslamicPatternPainter old) => old.color != color || old.cell != cell;
}

class _AreaChartPainter extends CustomPainter {
  final List<List<double>> series;
  final List<Color> colors;
  final Color gridColor;

  _AreaChartPainter({required this.series, required this.colors, required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    double maxV = 0;
    for (final s in series) {
      for (final v in s) {
        if (v > maxV) maxV = v;
      }
    }
    if (maxV <= 0) maxV = 1;

    for (var si = 0; si < series.length; si++) {
      final s = series[si];
      if (s.isEmpty) continue;
      final n = s.length;
      // Protita mash er majhkhane bindu — niche label er sathe mile
      final step = size.width / n;
      final pts = [
        for (var i = 0; i < n; i++)
          Offset(step * i + step / 2, size.height - (s[i] / maxV) * (size.height - 6)),
      ];

      final line = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        final p0 = pts[i - 1], p1 = pts[i];
        final mx = (p0.dx + p1.dx) / 2;
        line.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
      }

      final fill = Path.from(line)
        ..lineTo(pts.last.dx, size.height)
        ..lineTo(pts.first.dx, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colors[si].withAlpha(85), colors[si].withAlpha(0)],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = colors[si]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
      // Shesh mash er bindu
      canvas.drawCircle(pts.last, 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(pts.last, 3, Paint()..color = colors[si]);
    }
  }

  @override
  bool shouldRepaint(covariant _AreaChartPainter old) => old.series != series || old.colors != colors;
}

// ═══════════════════════════════════════════════════════════
// Bar chart (Distribution History)
// ═══════════════════════════════════════════════════════════
class _BarChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final Color gridColor;

  _BarChartPainter({required this.values, required this.colors, required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty) return;
    final maxV = values.fold<double>(0, math.max);
    if (maxV <= 0) return;

    final step = size.width / values.length;
    final barW = step * 0.56;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v <= 0) continue;
      final h = math.max(3.0, (v / maxV) * (size.height - 4));
      final rect = Rect.fromLTWH(step * i + (step - barW) / 2, size.height - h, barW, h);
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(5), topRight: const Radius.circular(5)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) => old.values != values;
}

// ═══════════════════════════════════════════════════════════
// Donut (Allocation / Status)
// ═══════════════════════════════════════════════════════════
class _DonutPainter extends CustomPainter {
  final List<(String, double, Color)> slices;
  _DonutPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (a, s) => a + s.$2);
    if (total <= 0) return;
    const stroke = 22.0;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: math.min(size.width, size.height) / 2 - stroke / 2,
    );

    // Pichoner halka ring
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = BC.muted
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    final gap = slices.length > 1 ? 0.035 : 0.0;
    var start = -math.pi / 2;
    for (final s in slices) {
      final sweep = s.$2 / total * math.pi * 2;
      if (sweep - gap > 0) {
        canvas.drawArc(
          rect,
          start + gap / 2,
          sweep - gap,
          false,
          Paint()
            ..color = s.$3
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.slices != slices;
}