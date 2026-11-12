import 'dart:math' as math;

import 'package:curved_labeled_navigation_bar/curved_navigation_bar.dart';
import 'package:curved_labeled_navigation_bar/curved_navigation_bar_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../screens/home_screen.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/language_service.dart';
import '../authentication/login_page.dart';
import '../authentication/registration_page.dart';
import '../investor/groups/browse_groups_page.dart';
import '../investor/help/help_center_page.dart';
import '../investor/projects/project_detail_page.dart';
import '../investor/settings/legal_web_page.dart';
import '../../theme/app_colors.dart';

/// biniyogclub.com er home page er app version — niche bottom navbar:
/// Home · Projects · Groups · Account. Shob shonkha DB theke (kono banano data nei).
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

// ═══════════════════════════════════════════════════════════
// PALETTE — website er rong (lib/theme/app_colors.dart), dashboard er moto.
// Kono sonali nei.
// ═══════════════════════════════════════════════════════════
class _C {
  static const Color emerald = BC.primary;
  static const Color emeraldBright = BC.brand500; // dashboard card er gradient
  static const Color emeraldDeep = BC.brand800;
  static const Color emeraldSoft = BC.secondary;
  static const Color emeraldLight = BC.brand200; // sobuj er upor halka lekha
  static const Color onDark = Colors.white; // sobuj er upor lekha / icon
  static const Color ivory = BC.background;
  static const Color tint = BC.muted;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color danger = BC.destructive;
  static const Color dangerSoft = BC.destructiveMuted;
  static const Color lapis = BC.finance600;
  static const Color notice = BC.chart4Deep; // "notun / ghoshona" er rong
  static const Color noticeSoft = BC.chart4Muted;
}

// ═══════════════════════════════════════════════════════════
// ASSETS — website er public folder theke ana (assets/ e)
// ═══════════════════════════════════════════════════════════
class _A {
  static const logo = 'assets/logo.png';
  static const logoFull = 'assets/images/logo_full.png';
  static const logoIcon = 'assets/Biniyog Club Logo Icon PNG.png';
  static const about = 'assets/images/biniyog.png';
  static const transparency = 'assets/images/Transparency in Fintech Accountability.png';
  static const agro = 'assets/images/smart-agro-farm.jpg';
  static const coldChain = 'assets/images/cold-chain-sme.jpg';
  static const contract = 'assets/images/contract-security.jpg';
  static const wallet = 'assets/images/wallet-returns-payout.jpg';
  static const kyc = 'assets/images/digital-kyc-verify.jpg';
  static const community = 'assets/images/investor-community.jpg';
  static const dueDiligence = 'assets/images/about-due-diligence.jpg';

  // About er 4 pillar (website er /icons)
  static const iconSecure = 'assets/icons/secure-platform.jpg';
  static const iconTransparent = 'assets/icons/transparent-process.jpg';
  static const iconTech = 'assets/icons/modern-technology.jpg';
  static const iconUser = 'assets/icons/user-experience.jpg';

  // Stats er icon (website er MetricsDock)
  static const iconInvestment = 'assets/icons/investment.png';
  static const iconInvestors = 'assets/icons/user.png';
  static const iconProjects = 'assets/icons/search-engine.png';
  static const iconIncome = 'assets/icons/income.png';

  /// Website er groupLogo() — assets/Group logos/
  static String? groupLogo(String slug) {
    switch (slug.toUpperCase()) {
      case 'MARINERS':
        return 'assets/Group logos/Mariners Group logo.png';
      case 'MOHS':
        return 'assets/Group logos/MOHS Group logo.png';
      case 'MARINOZZ':
        return 'assets/Group logos/Marinozz Group logo.png';
      case 'COMMUNITY_VENTURES':
        return 'assets/Group logos/Community Ventures Logo.png';
      case 'VENTURE_ALLIANCES':
        return 'assets/Group logos/Venture Alliance Logo.png';
      default:
        return null;
    }
  }

  /// Website er "One Ecosystem" grid — 6 ta logo, website er ek-i kroma.
  /// (DB te shob group nao thakte pare — tai logo gulo website er motoi fixed.)
  static const List<(String, String, String)> ecosystem = [
    // (nam, app asset, website path)
    ('Mariners Group', 'assets/Group logos/Mariners Group logo.png', '/Group logos/Mariners Group logo.png'),
    ('MOHS Group', 'assets/Group logos/MOHS Group logo.png', '/Group logos/MOHS Group logo.png'),
    ('Marinozz Group', 'assets/Group logos/Marinozz Group logo.png', '/Group logos/Marinozz Group logo.png'),
    ('Community Ventures', 'assets/Group logos/Community Ventures Logo.png', '/Group logos/Community Ventures Logo.png'),
    ('Venture Alliance', 'assets/Group logos/Venture Alliance Logo.png', '/Group logos/Venture Alliance Logo.png'),
    ('Venture System', 'assets/Group logos/Venture system .png', '/Group logos/Venture system .png'),
  ];

  /// Website er GROUP_VISUAL_MAP er cover
  static String groupCover(String slug) {
    switch (slug.toUpperCase()) {
      case 'MARINERS':
        return 'assets/4.png';
      case 'MOHS':
        return 'assets/2.png';
      case 'MARINOZZ':
        return 'assets/3.png';
      case 'COMMUNITY_VENTURES':
        return community;
      case 'VENTURE_ALLIANCES':
        return dueDiligence;
      default:
        return 'assets/1..png';
    }
  }

  /// Website er getProjectFallbackImage — project er nijer chobi na thakle
  static String projectFallback(String category, String id) {
    final c = category.toUpperCase();
    if (c.contains('AGRO') || c.contains('FARM') || c.contains('FOOD')) return agro;
    if (c.contains('LOGISTICS') || c.contains('COLD') || c.contains('SUPPLY') || c == 'INFRASTRUCTURE') {
      return coldChain;
    }
    if (c.contains('TECH') || c.contains('DIGITAL')) return kyc;
    if (c.contains('RETAIL') || c.contains('COMMERCE') || c.contains('TRADE') || c == 'FMCG') return wallet;
    if (c == 'COMMUNITY') return community;
    const rotation = [agro, coldChain, contract, wallet, kyc];
    return rotation[id.hashCode.abs() % rotation.length];
  }
}

/// Asset chobi — file na thakle sobuj box (app crash kore na)
Widget _assetImage(String path, {BoxFit fit = BoxFit.cover, Widget? fallback}) {
  return Image.asset(
    path,
    fit: fit,
    errorBuilder: (_, __, ___) => fallback ?? const _ImageFallbackBox(),
  );
}

String _tr(String en, String bn) => LanguageService.tr(en, bn);

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0.0;
}

String _trimNum(double v, int digits) {
  final s = v.toStringAsFixed(digits);
  return s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
}

String _bdtShort(double n) {
  if (n >= 10000000) return '৳${_trimNum(n / 10000000, 1)} Cr';
  if (n >= 100000) return '৳${_trimNum(n / 100000, 1)}L';
  if (n >= 1000) return '৳${_trimNum(n / 1000, 0)}K';
  return '৳${n.toStringAsFixed(0)}';
}

String _pctRange(double lo, double hi) {
  String p(double r) => _trimNum(r * 100, 1);
  if (lo <= 0 && hi <= 0) return '—';
  if (lo <= 0 || lo == hi) return '${p(hi)}%';
  return '${p(lo)}–${p(hi)}%';
}

String _categoryLabel(String c) {
  if (c.isEmpty) return '';
  return c
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0]}${w.substring(1).toLowerCase()}')
      .join(' ');
}

String _fmtDate(String raw) {
  var t = raw.trim().replaceFirst(' ', 'T');
  if (t.contains('T') && !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(t)) t = '${t}Z';
  final d = DateTime.tryParse(t)?.toLocal();
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

class _LandingPageState extends State<LandingPage> {
  int _tab = 0;
  bool _loading = true;
  bool _failed = false;
  bool _loggedIn = false;

  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _updates = [];
  int _investors = 0;

  final _homeScroll = ScrollController();
  final _howKey = GlobalKey();
  String _projectFilter = 'ALL';

  /// Website er event banner er motoi — 2 Nov 2026 er por nijei lukay
  static final DateTime _eventEndsAt = DateTime.utc(2026, 11, 2, 18); // 3 Nov 00:00 Dhaka
  static const String _vipPassUrl = 'https://ceremony2026.marinersgroupbd.com/';
  static const String _site = 'https://biniyogclub.com';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _homeScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = _projects.isEmpty;
        _failed = false;
      });
    }
    final res = await Future.wait<dynamic>([
      DatabaseService.getLandingData(),
      DatabaseService.getBusinessGroupsWithTiers(),
      AuthService.isLoggedIn(),
    ]);
    if (!mounted) return;
    final data = res[0] as Map<String, dynamic>;
    final groups = res[1] as List<Map<String, dynamic>>;
    final projects = ((data['projects'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    setState(() {
      _projects = projects;
      _groups = groups;
      _updates = ((data['updates'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _investors = (data['totalInvestors'] as num?)?.toInt() ?? 0;
      _loggedIn = res[2] as bool;
      _failed = data['ok'] == false && projects.isEmpty && groups.isEmpty;
      _loading = false;
    });
  }

  // ═════════════════════════════════════════════════════════
  // NAVIGATION
  // ═════════════════════════════════════════════════════════
  void _open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  void _openWeb(String title, String url) => _open(LegalWebPage(title: title, url: url));

  void _openProject(Map<String, dynamic> p) => _open(ProjectDetailPage(projectIdOrSlug: p['id'].toString()));

  void _goLogin() => _open(const LoginPage());

  void _goRegister() => _open(const RegistrationPage());

  void _goDashboard() => Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
  );

  void _scrollToHow() {
    final ctx = _howKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 550), curve: Curves.easeOutCubic);
    }
  }

  double get _minEntry {
    // Shudhu je project e ekhon invest kora jay
    final mins = _projects
        .where((p) => p['acceptingInvestment'] == true)
        .map((p) => _num(p['minInvestmentBdt']))
        .where((v) => v > 0)
        .toList();
    if (mins.isEmpty) return 0;
    return mins.reduce(math.min);
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, _) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          // GaRho app bar er upor status bar er icon shada
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            backgroundColor: _C.ivory,
            // Curve er pichone page dekha jay
            extendBody: true,
            appBar: _buildAppBar(),
            body: _loading
                ? const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(color: _C.emerald, strokeWidth: 2.4),
              ),
            )
                : IndexedStack(
              index: _tab,
              children: [
                _buildHomeTab(),
                _buildProjectsTab(),
                _buildGroupsTab(),
                _buildAccountTab(),
              ],
            ),
            bottomNavigationBar: _buildBottomNav(),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    // Niche nav bar er sathe mil rekhe: dashboard er sobuj
    return AppBar(
      backgroundColor: _C.emerald,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 16,
      // Website er motoi gaRho background e logo shada
      title: ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        child: Image.asset(
          _A.logo,
          height: 32,
          errorBuilder: (_, __, ___) => Image.asset(
            _A.logoFull,
            height: 30,
            errorBuilder: (_, __, ___) => const Text(
              'Biniyog Club',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
            ),
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _loggedIn
              ? FilledButton.icon(
            onPressed: _goDashboard,
            icon: const Icon(Icons.dashboard_outlined, size: 16),
            label: Text(_tr('Dashboard', 'ড্যাশবোর্ড')),
            style: _smallFilled(),
          )
              : FilledButton(
            onPressed: _goLogin,
            style: _smallFilled(),
            child: Text(_tr('Sign in', 'সাইন ইন')),
          ),
        ),
      ],
    );
  }

  ButtonStyle _smallFilled() => FilledButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: _C.emerald,
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
  );

  Widget _buildBottomNav() {
    // Dashboard er moto: sobuj bar, sobuj bubble, sada icon — kono sonali nei
    Widget icon(IconData data, int i) =>
        Icon(data, size: 25, color: _tab == i ? Colors.white : Colors.white.withAlpha(200));
    const label = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white);

    return CurvedNavigationBar(
      index: _tab,
      height: 70,
      color: _C.emerald,
      buttonBackgroundColor: _C.emeraldBright,
      backgroundColor: Colors.transparent,
      animationCurve: Curves.easeOutCubic,
      animationDuration: const Duration(milliseconds: 450),
      items: [
        CurvedNavigationBarItem(
          child: icon(_tab == 0 ? Icons.home_rounded : Icons.home_outlined, 0),
          label: _tr('Home', 'হোম'),
          labelStyle: label,
        ),
        CurvedNavigationBarItem(
          child: icon(Icons.trending_up_rounded, 1),
          label: _tr('Projects', 'প্রজেক্ট'),
          labelStyle: label,
        ),
        CurvedNavigationBarItem(
          child: icon(_tab == 2 ? Icons.apartment_rounded : Icons.apartment_outlined, 2),
          label: _tr('Groups', 'গ্রুপ'),
          labelStyle: label,
        ),
        CurvedNavigationBarItem(
          child: icon(_tab == 3 ? Icons.person_rounded : Icons.person_outline_rounded, 3),
          label: _tr('Account', 'অ্যাকাউন্ট'),
          labelStyle: label,
        ),
      ],
      onTap: (i) {
        // Home e thakle abar Home chaple upore niye jay
        if (i == _tab && i == 0 && _homeScroll.hasClients) {
          _homeScroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
        }
        if (i != _tab) setState(() => _tab = i);
      },
    );
  }

  // ═════════════════════════════════════════════════════════
  // HOME TAB — website er section gulo, ek-i kroma
  // ═════════════════════════════════════════════════════════
  Widget _buildHomeTab() {
    final showEvent = DateTime.now().toUtc().isBefore(_eventEndsAt);
    final featured = _projects.take(6).toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: _C.emerald,
      child: ListView(
        controller: _homeScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          if (_failed) _offlineBar(),
          if (showEvent) _eventBanner(),
          _hero(),
          _ecosystemBand(),
          _section(child: _about()),
          _section(tinted: true, child: _featuredProjects(featured)),
          _section(key: _howKey, child: _howItWorks()),
          if (_groups.isNotEmpty) _section(tinted: true, child: _groupsPreview()),
          _section(child: _transparency()),
          _section(tinted: true, child: _governance()),
          if (_updates.isNotEmpty) _section(child: _latestUpdates()),
          _section(tinted: _updates.isNotEmpty ? false : true, child: _faq()),
          _finalCta(),
          _footer(),
        ],
      ),
    );
  }

  Widget _section({Key? key, bool tinted = false, required Widget child}) {
    return Container(
      key: key,
      color: tinted ? _C.tint : _C.ivory,
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 28),
      child: child,
    );
  }

  Widget _offlineBar() {
    return Container(
      color: _C.dangerSoft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 17, color: _C.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_tr('Could not load live data. Pull down to retry.', 'তথ্য লোড হয়নি। নিচে টেনে আবার চেষ্টা করুন।'),
                style: const TextStyle(fontSize: 13.5, color: _C.danger, fontWeight: FontWeight.w600)),
          ),
          TextButton(onPressed: _load, child: Text(_tr('Retry', 'আবার'))),
        ],
      ),
    );
  }

  // ─── Event banner ─────────────────────────────────────────
  Widget _eventBanner() {
    return Container(
      color: _C.noticeSoft,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: _C.notice, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BINIYOG CLUB Official Ceremony 2026',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _C.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  _tr('Investment Partners’ Gathering · 2 Nov 2026, IDEB Kakrail',
                      'ইনভেস্টমেন্ট পার্টনারস গ্যাদারিং · ২ নভেম্বর ২০২৬, আইডিইবি কাকরাইল'),
                  style: const TextStyle(fontSize: 12.5, color: _C.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => _openWeb('VIP Pass', _vipPassUrl),
            style: FilledButton.styleFrom(
              backgroundColor: _C.emerald,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            child: Text(_tr('VIP Pass', 'ভিআইপি পাস')),
          ),
        ],
      ),
    );
  }

  // ─── 01 Hero ──────────────────────────────────────────────
  Widget _hero() {
    final minEntry = _minEntry;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.emeraldBright, _C.emerald],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 34),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: _C.onDark.withAlpha(110)),
                    color: Colors.white.withAlpha(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: _C.onDark, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _tr("BANGLADESH'S DIRECT INVESTMENT PLATFORM", 'বাংলাদেশের সরাসরি বিনিয়োগ প্ল্যাটফর্ম'),
                          style: const TextStyle(
                              color: _C.onDark, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  _tr('Your Gateway to', 'আপনার প্রবেশদ্বার'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 29, fontWeight: FontWeight.w300, height: 1.15),
                ),
                Text(
                  _tr('Real Business Opportunities', 'বাস্তব ব্যবসার সুযোগে'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _C.onDark, fontSize: 29, fontWeight: FontWeight.w800, height: 1.15),
                ),
                const SizedBox(height: 14),
                Text(
                  _tr(
                    'Invest directly in vetted Bangladeshi businesses — from real estate to food and hospitality — with legally binding agreements, segregated capital and transparent reporting at every step.',
                    'রিয়েল এস্টেট থেকে ফুড ও হসপিটালিটি — যাচাই করা বাংলাদেশি ব্যবসায় সরাসরি বিনিয়োগ করুন। আইনি চুক্তি, আলাদা রাখা মূলধন আর প্রতিটি ধাপে স্বচ্ছ রিপোর্ট।',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 14.5, height: 1.55),
                ),
                if (minEntry > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    _tr('Projects open from ${_bdtShort(minEntry)}', '${_bdtShort(minEntry)} থেকে প্রজেক্টে বিনিয়োগ'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _C.onDark, fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ],
                const SizedBox(height: 22),
                // Website er motoi: dui button opore-niche, puro chowra
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () => setState(() => _tab = 1),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _C.emerald,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_tr('Explore Opportunities', 'সুযোগ দেখুন'),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_rounded, size: 17),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _scrollToHow,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withAlpha(110)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(_tr('How It Works', 'কীভাবে কাজ করে'),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 02 Operating groups band — website er motoi 3 column grid, scroll nei ─
  Widget _ecosystemBand() {
    final groups = _A.ecosystem;

    // App er asset → na thakle website theke → tao na hole nam
    Widget logoOf((String, String, String) g) {
      final name = Text(
        g.$1,
        textAlign: TextAlign.center,
        maxLines: 2,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _C.emerald),
      );
      return _assetImage(
        g.$2,
        fit: BoxFit.contain,
        fallback: Image.network(
          'https://www.biniyogclub.com${Uri.encodeFull(g.$3)}',
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => name,
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _C.ivory,
        border: Border(bottom: BorderSide(color: _C.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        children: [
          Text(
            _tr('ONE ECOSYSTEM · ${groups.length} BUSINESS SEGMENTS · REAL OPERATING COMPANIES',
                'এক ইকোসিস্টেম · ${groups.length}টি ব্যবসায়িক খাত · বাস্তব প্রতিষ্ঠান'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w800, color: _C.ink, letterSpacing: 1.6, height: 1.7),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => _tab = 2),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_tr('Explore the groups', 'গ্রুপগুলো দেখুন'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _C.emerald)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded, size: 15, color: _C.emerald),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // 3 column, dorkar moto row — kono scroll na
          LayoutBuilder(
            builder: (context, c) {
              const cols = 3;
              // Bairer border 1px + 1px — round down jeno 3 ta ek line e dhore
              final w = ((c.maxWidth - 2) / cols).floorToDouble();
              final h = w * 0.88;
              return Container(
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _C.line)),
                child: Wrap(
                  children: [
                    for (int i = 0; i < groups.length; i++)
                      InkWell(
                        onTap: () => setState(() => _tab = 2),
                        child: Container(
                          width: w,
                          height: h,
                          padding: const EdgeInsets.all(12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              right: i % cols == cols - 1
                                  ? BorderSide.none
                                  : const BorderSide(color: _C.line),
                              bottom: i >= ((groups.length - 1) ~/ cols) * cols
                                  ? BorderSide.none
                                  : const BorderSide(color: _C.line),
                            ),
                          ),
                          child: logoOf(groups[i]),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }


  // ─── Section heading (website er SectionHeading) ─────────
  Widget _heading({
    required String eyebrow,
    required String title,
    String? highlight,
    String? description,
    bool dark = false,
    bool center = false,
  }) {
    final align = center ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final tAlign = center ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: align,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 20, height: 1, color: dark ? _C.onDark : _C.emeraldBright),
            const SizedBox(width: 8),
            Text(
              eyebrow.toUpperCase(),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
                color: dark ? _C.onDark : _C.emerald,
              ),
            ),
            if (center) ...[
              const SizedBox(width: 8),
              Container(width: 20, height: 1, color: dark ? _C.onDark : _C.emeraldBright),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: 22,
              height: 1.22,
              fontWeight: FontWeight.w300,
              color: dark ? Colors.white : _C.ink,
            ),
            children: [
              TextSpan(text: title),
              if (highlight != null)
                TextSpan(
                  text: ' $highlight',
                  style: TextStyle(fontWeight: FontWeight.w800, color: dark ? _C.onDark : _C.emerald),
                ),
            ],
          ),
          textAlign: tAlign,
        ),
        if (description != null) ...[
          const SizedBox(height: 10),
          Text(
            description,
            textAlign: tAlign,
            style: TextStyle(fontSize: 13.5, height: 1.55, color: dark ? Colors.white.withAlpha(190) : _C.muted),
          ),
        ],
      ],
    );
  }

  Widget _linkButton(String text, VoidCallback onTap, {bool filled = false}) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 6),
        const Icon(Icons.arrow_forward_rounded, size: 16),
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return SizedBox(
      width: double.infinity,
      child: filled
          ? FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: _C.emerald,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: shape,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        child: child,
      )
          : OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: _C.ink,
          backgroundColor: Colors.white,
          side: const BorderSide(color: _C.line),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: shape,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        child: child,
      ),
    );
  }

  Widget _iconBox(IconData icon, {Color bg = _C.emeraldSoft, Color fg = _C.emerald, double size = 40}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
      child: Icon(icon, size: size * 0.5, color: fg),
    );
  }

  // ─── 03 About ─────────────────────────────────────────────
  Widget _about() {
    final pillars = <(String, IconData, String, String)>[
      (
      _A.iconSecure,
      Icons.shield_outlined,
      _tr('Secure Platform', 'নিরাপদ প্ল্যাটফর্ম'),
      _tr('Due diligence on every project and capital kept separate for each allocation.',
          'প্রতিটি প্রজেক্ট যাচাই করা হয় এবং প্রতিটি বিনিয়োগের টাকা আলাদা রাখা হয়।'),
      ),
      (
      _A.iconTransparent,
      Icons.visibility_outlined,
      _tr('Transparent Process', 'স্বচ্ছ প্রক্রিয়া'),
      _tr('Milestone updates, clear return terms and no hidden deductions.',
          'মাইলস্টোন আপডেট, পরিষ্কার লাভের শর্ত, কোনো গোপন কর্তন নেই।'),
      ),
      (
      _A.iconTech,
      Icons.memory_rounded,
      _tr('Modern Technology', 'আধুনিক প্রযুক্তি'),
      _tr('A double-entry ledger keeps every taka balanced and reconciled.',
          'ডাবল-এন্ট্রি লেজার প্রতিটি টাকার হিসাব মিলিয়ে রাখে।'),
      ),
      (
      _A.iconUser,
      Icons.person_pin_outlined,
      _tr('User-Focused Experience', 'ব্যবহারকারী-বান্ধব'),
      _tr('Quick sign-up, a real-time dashboard and payouts to your bank or mobile wallet.',
          'দ্রুত রেজিস্ট্রেশন, রিয়েল-টাইম ড্যাশবোর্ড আর ব্যাংক বা মোবাইল ওয়ালেটে পেমেন্ট।'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          eyebrow: _tr('About Biniyog Club', 'বিনিয়োগ ক্লাব সম্পর্কে'),
          title: _tr('Discover the Power of', 'আবিষ্কার করুন'),
          highlight: _tr('Collective Opportunities', 'সম্মিলিত সুযোগের শক্তি'),
          description: _tr(
            'Biniyog Club bridges conscientious co-investors and vetted, high-potential commercial opportunities in Bangladesh — with financial analysis, enforceable legal agreements and an immutable double-entry ledger.',
            'বিনিয়োগ ক্লাব সচেতন বিনিয়োগকারীদের সাথে বাংলাদেশের যাচাই করা, সম্ভাবনাময় ব্যবসার সংযোগ ঘটায় — আর্থিক বিশ্লেষণ, আইনি চুক্তি আর অপরিবর্তনীয় ডাবল-এন্ট্রি লেজারের মাধ্যমে।',
          ),
        ),
        const SizedBox(height: 20),
        // Website er "Invest today, reap tomorrow" chobi
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: _C.line),
            boxShadow: [BoxShadow(color: _C.emeraldDeep.withAlpha(25), blurRadius: 22, offset: const Offset(0, 10))],
          ),
          child: AspectRatio(aspectRatio: 4 / 5, child: _assetImage(_A.about)),
        ),
        const SizedBox(height: 20),
        for (final p in pillars)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _C.line)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: _C.emeraldSoft,
                    border: Border.all(color: _C.emerald.withAlpha(70)),
                  ),
                  child: _assetImage(p.$1, fallback: _iconBox(p.$2, size: 46)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.$3, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _C.ink)),
                      const SizedBox(height: 3),
                      Text(p.$4, style: const TextStyle(fontSize: 13.5, color: _C.muted, height: 1.45)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        _linkButton(_tr('Our Methodology & Team', 'আমাদের পদ্ধতি ও টিম'),
                () => _openWeb(_tr('About', 'আমাদের সম্পর্কে'), '$_site/about'),
            filled: true),
      ],
    );
  }

  // ─── 05 Featured projects ─────────────────────────────────
  Widget _featuredProjects(List<Map<String, dynamic>> featured) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          eyebrow: _tr('Investment opportunities', 'বিনিয়োগের সুযোগ'),
          title: _tr('Explore Businesses', 'যে ব্যবসাগুলোর'),
          highlight: _tr('You Can Be Part Of', 'অংশ হতে পারেন'),
          description: _tr(
            'Admin-vetted, asset-backed ventures with legally binding contracts and transparent distributions.',
            'অ্যাডমিন-যাচাইকৃত, সম্পদ-সমর্থিত ব্যবসা — আইনি চুক্তি ও স্বচ্ছ লাভ বণ্টন সহ।',
          ),
        ),
        const SizedBox(height: 18),
        if (featured.isEmpty)
          _emptyBox(_tr('New vetted project listings are being reviewed.', 'নতুন প্রজেক্ট যাচাই চলছে।'))
        else
          SizedBox(
            height: 352,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: featured.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => SizedBox(width: 280, child: _projectCard(featured[i])),
            ),
          ),
        const SizedBox(height: 18),
        _linkButton(_tr('View All Projects', 'সব প্রজেক্ট দেখুন'), () => setState(() => _tab = 1)),
      ],
    );
  }

  Widget _emptyBox(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _C.line)),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: _C.muted)),
    );
  }

  (String, Color) _statusMeta(String s) {
    switch (s) {
      case 'FUNDRAISING':
        return (_tr('Fundraising', 'ফান্ড সংগ্রহ চলছে'), _C.emerald);
      case 'FUNDED':
        return (_tr('Funded', 'ফান্ড পূর্ণ'), _C.lapis);
      case 'ACTIVE':
        return (_tr('Active', 'চলমান'), BC.chart4Deep);
      case 'HARVESTING':
        return (_tr('Harvesting', 'হারভেস্টিং'), _C.emerald);
      case 'COMPLETED':
        return (_tr('Completed', 'সম্পন্ন'), _C.muted);
      default:
        return (_categoryLabel(s), _C.muted);
    }
  }

  Widget _projectCard(Map<String, dynamic> p, {bool full = false}) {
    final img = p['coverImageUrl']?.toString() ?? '';
    final closedByDeadline = p['status'] == 'FUNDRAISING' && p['deadlinePassed'] == true;
    final (label, color) = closedByDeadline
        ? (_tr('Funding closed', 'বিনিয়োগ বন্ধ'), _C.danger)
        : _statusMeta(p['status']?.toString() ?? '');
    final progress = _num(p['progress']).clamp(0.0, 1.0).toDouble();
    final minInv = _num(p['minInvestmentBdt']);
    final days = (p['durationDays'] as num?)?.toInt() ?? 0;
    final months = days > 0 ? (days / 30).round() : 0;
    final group = p['groupName']?.toString() ?? '';
    final location = p['location']?.toString() ?? '';
    final deadlineDays = (p['deadlineDays'] as num?)?.toInt();
    final open = p['acceptingInvestment'] == true;

    return InkWell(
      onTap: () => _openProject(p),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _C.line),
          boxShadow: [BoxShadow(color: _C.emeraldDeep.withAlpha(10), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: full ? 170 : 140,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  img.startsWith('http')
                      ? Image.network(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _projectFallback(p))
                      : _projectFallback(p),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x99000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: Colors.white,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
                        ],
                      ),
                    ),
                  ),
                  if ((p['category']?.toString() ?? '').isNotEmpty)
                    Positioned(
                      left: 10,
                      bottom: 8,
                      child: Text(
                        _categoryLabel(p['category'].toString()).toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['title']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _C.ink, height: 1.25),
                  ),
                  if (group.isNotEmpty || location.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      [group, location].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: _C.muted),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _fact(_tr('Return', 'লাভ'), _pctRange(_num(p['returnMin']), _num(p['returnMax'])), _C.emerald),
                      _fact(_tr('Min', 'সর্বনিম্ন'), minInv > 0 ? _bdtShort(minInv) : '—', _C.ink),
                      _fact(_tr('Term', 'মেয়াদ'), months > 0 ? _tr('$months mo', '$months মাস') : '—', _C.ink),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: _C.line,
                      valueColor: const AlwaysStoppedAnimation(_C.emeraldBright),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        _tr('${(progress * 100).round()}% funded', '${(progress * 100).round()}% সংগৃহীত'),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _C.emerald),
                      ),
                      const Spacer(),
                      if (open && deadlineDays != null)
                        Text(
                          deadlineDays > 1
                              ? _tr('$deadlineDays days left', '$deadlineDays দিন বাকি')
                              : deadlineDays == 1
                              ? _tr('Closes tomorrow', 'কাল শেষ দিন')
                              : _tr('Closes today', 'আজ শেষ দিন'),
                          style: const TextStyle(fontSize: 12.5, color: _C.muted),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fact(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _C.muted, letterSpacing: 0.7)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  /// Project er chobi na thakle website er motoi category onujayi chobi
  Widget _projectFallback(Map<String, dynamic> p) => _assetImage(
    _A.projectFallback(p['category']?.toString() ?? '', p['id']?.toString() ?? ''),
  );

  Widget _imagePlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.emeraldBright, _C.emerald],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: Icon(Icons.image_outlined, color: Colors.white.withAlpha(120), size: 30)),
    );
  }

  // ─── 06 How it works ──────────────────────────────────────
  Widget _howItWorks() {
    const stepImages = [_A.kyc, _A.agro, _A.contract, _A.wallet];
    final steps = <(String, IconData, String, String, String)>[
      (
      '01',
      Icons.person_add_alt_1_outlined,
      _tr('Create Your Account', 'অ্যাকাউন্ট খুলুন'),
      _tr('Register in under 2 minutes with your name, phone number and date of birth.',
          'নাম, মোবাইল নম্বর আর জন্ম তারিখ দিয়ে ২ মিনিটেরও কম সময়ে রেজিস্টার করুন।'),
      _tr('Fast onboarding', 'দ্রুত শুরু'),
      ),
      (
      '02',
      Icons.travel_explore_rounded,
      _tr('Explore Vetted Portfolios', 'যাচাই করা প্রজেক্ট দেখুন'),
      _tr('Compare reviewed projects and business group tiers with clear returns and disclosures.',
          'পরিষ্কার লাভ ও তথ্যসহ যাচাই করা প্রজেক্ট ও বিজনেস গ্রুপ টিয়ার তুলনা করুন।'),
      _tr('Vetted portfolios', 'যাচাইকৃত'),
      ),
      (
      '03',
      Icons.history_edu_outlined,
      _tr('Pay & Get Your Contract', 'পেমেন্ট ও চুক্তি'),
      _tr('Pay by bank, cash or cheque. After admin approval you receive a receipt and a numbered deed.',
          'ব্যাংক, ক্যাশ বা চেকে টাকা দিন। অ্যাডমিন অনুমোদনের পর রসিদ ও নম্বরসহ ডিড পাবেন।'),
      _tr('Legally protected', 'আইনি সুরক্ষা'),
      ),
      (
      '04',
      Icons.payments_outlined,
      _tr('Receive Return Payouts', 'লাভ গ্রহণ করুন'),
      _tr('Track progress in real time and receive scheduled returns from your dashboard.',
          'রিয়েল-টাইমে অগ্রগতি দেখুন আর নির্ধারিত সময়ে লাভ পান।'),
      _tr('Scheduled returns', 'নির্ধারিত লাভ'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          eyebrow: _tr('Four simple steps', 'চারটি সহজ ধাপ'),
          title: _tr('Your Investment Journey,', 'আপনার বিনিয়োগ যাত্রা,'),
          highlight: _tr('Simplified', 'সহজভাবে'),
          description: _tr('From registration to scheduled profit payouts into your bank or mobile wallet.',
              'রেজিস্ট্রেশন থেকে ব্যাংক বা মোবাইল ওয়ালেটে লাভ পাওয়া পর্যন্ত।'),
        ),
        const SizedBox(height: 22),
        for (int i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 44,
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [_C.emeraldBright, _C.emerald]),
                          shape: BoxShape.circle,
                        ),
                        child: Text(steps[i].$1,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
                      ),
                      if (i < steps.length - 1) Expanded(child: Container(width: 2, color: _C.emeraldBright.withAlpha(90))),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _C.line)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Website er step chobi
                        SizedBox(
                          height: 120,
                          width: double.infinity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _assetImage(stepImages[i]),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Color(0xB3020617)],
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  color: const Color(0xCC0F172A),
                                  child: Text('STEP ${steps[i].$1}',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(steps[i].$2, size: 19, color: _C.emerald),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(steps[i].$3,
                                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: _C.ink)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(steps[i].$4, style: const TextStyle(fontSize: 13.5, color: _C.muted, height: 1.45)),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          color: _C.emeraldSoft,
                          child: Text(steps[i].$5.toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w800, color: _C.emerald, letterSpacing: 0.8)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        _linkButton(_tr('Explore Detailed Investment Guide', 'বিস্তারিত গাইড দেখুন'),
                () => _openWeb(_tr('How it works', 'কীভাবে কাজ করে'), '$_site/how-it-works')),
      ],
    );
  }

  // ─── 07 Business groups preview ───────────────────────────
  Widget _groupsPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          eyebrow: _tr('Our portfolio', 'আমাদের পোর্টফোলিও'),
          title: _tr('Explore the Businesses', 'সুযোগের পেছনের'),
          highlight: _tr('Behind the Opportunities', 'ব্যবসাগুলো দেখুন'),
          description: _tr(
            'Partner with vetted corporate enterprises and multi-sector groups driving growth across Bangladesh.',
            'বাংলাদেশজুড়ে প্রবৃদ্ধি আনা যাচাই করা প্রতিষ্ঠান ও বহুমুখী গ্রুপের অংশীদার হোন।',
          ),
        ),
        const SizedBox(height: 18),
        for (final g in _groups.take(3)) _groupCard(g),
        const SizedBox(height: 4),
        _linkButton(_tr('View All Groups', 'সব গ্রুপ দেখুন'), () => setState(() => _tab = 2)),
      ],
    );
  }

  int _projectsInGroup(String groupId) => _projects.where((p) => p['groupId'] == groupId).length;

  Widget _groupCard(Map<String, dynamic> g) {
    final entities = ((g['entities'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final tiers = [
      for (final e in entities) ...((e['tiers'] as List?) ?? []).map((t) => Map<String, dynamic>.from(t as Map)),
    ];
    // Bank ache + unit shesh hoyni — tobei invest kora jay
    final openTiers = tiers.where((t) {
      final b = t['bank'];
      final u = t['availableUnits'];
      return b is Map && (b['accountNumber']?.toString() ?? '').isNotEmpty && !(u is num && u <= 0);
    }).length;
    final mins = tiers.map((t) => _num(t['minAmountBdt'])).where((v) => v > 0).toList();
    final minAmt = mins.isEmpty ? 0.0 : mins.reduce(math.min);
    final logo = g['logoUrl']?.toString() ?? '';
    final localLogo = _A.groupLogo(g['slug']?.toString() ?? '');
    final hasLogo = localLogo != null || logo.startsWith('http');
    final tagline = (g['tagline']?.toString() ?? '').trim();
    final desc = (g['description']?.toString() ?? '').trim();
    final projectsCount = _projectsInGroup(g['id']?.toString() ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _C.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Website er card er motoi: shada background e logo (3:1),
          // logo na thakle group er cover chobi
          hasLogo
              ? DecoratedBox(
            decoration: const BoxDecoration(color: Colors.white),
            child: Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _C.line))),
              child: AspectRatio(
                aspectRatio: 3,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: localLogo != null
                      ? _assetImage(localLogo, fit: BoxFit.contain, fallback: _groupTitle(g))
                      : Image.network(logo, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _groupTitle(g)),
                ),
              ),
            ),
          )
              : SizedBox(
            height: 150,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _assetImage(_A.groupCover(g['slug']?.toString() ?? '')),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC00463A)], // BC.brand800 er moto
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Text(
                    g['name']?.toString() ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasLogo)
                  Text(g['name']?.toString() ?? '',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _C.ink)),
                if (tagline.isNotEmpty || desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    tagline.isNotEmpty ? tagline : desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, color: _C.muted, height: 1.4),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (entities.isNotEmpty)
                      _chip(Icons.business_outlined, _tr('${entities.length} companies', '${entities.length}টি প্রতিষ্ঠান')),
                    if (tiers.isNotEmpty) _chip(Icons.layers_outlined, _tr('${tiers.length} tiers', '${tiers.length}টি টিয়ার')),
                    if (projectsCount > 0)
                      _chip(Icons.workspaces_outline, _tr('$projectsCount projects', '$projectsCount প্রজেক্ট')),
                    if (minAmt > 0) _chip(Icons.payments_outlined, _tr('From ${_bdtShort(minAmt)}', '${_bdtShort(minAmt)} থেকে')),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: openTiers > 0
                      ? FilledButton(
                    onPressed: () => _open(const BrowseGroupsPage()),
                    style: FilledButton.styleFrom(
                      backgroundColor: _C.emerald,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(_tr('Explore ${g['name'] ?? ''} Tiers', '${g['name'] ?? ''} টিয়ার দেখুন'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  )
                      : Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _C.emeraldSoft, border: Border.all(color: _C.emeraldBright.withAlpha(90))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.schedule_rounded, size: 15, color: _C.emerald),
                        const SizedBox(width: 6),
                        Text(_tr('Coming Soon', 'শীঘ্রই আসছে'),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _C.emerald)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupTitle(Map<String, dynamic> g) => Text(
    g['name']?.toString() ?? '',
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _C.emerald),
  );

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: _C.ivory, border: Border.all(color: _C.line)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _C.emerald),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _C.ink)),
        ],
      ),
    );
  }

  // ─── 08 Transparency ──────────────────────────────────────
  Widget _transparency() {
    final items = <(IconData, String, String)>[
      (
      Icons.lock_outline_rounded,
      _tr('Double-Entry Ledger', 'ডাবল-এন্ট্রি লেজার'),
      _tr('Every transaction is recorded with debit-credit balance checks — no phantom balances.',
          'প্রতিটি লেনদেন ডেবিট-ক্রেডিট মিলিয়ে লেখা হয় — কোনো ভুয়া ব্যালান্স নয়।'),
      ),
      (
      Icons.fact_check_outlined,
      _tr('Legally Binding Agreements', 'আইনি চুক্তি'),
      _tr('Every confirmed allocation is backed by a timestamped agreement under the Contract Act of Bangladesh.',
          'প্রতিটি নিশ্চিত বিনিয়োগ বাংলাদেশের চুক্তি আইনের অধীনে তারিখসহ চুক্তি দ্বারা সমর্থিত।'),
      ),
      (
      Icons.shield_outlined,
      _tr('Segregated Capital', 'আলাদা রাখা মূলধন'),
      _tr('Investor capital is tracked per project and kept separate from company operations.',
          'বিনিয়োগকারীর টাকা প্রজেক্ট অনুযায়ী আলাদা রাখা হয়, কোম্পানির খরচের সাথে মেশানো হয় না।'),
      ),
      (
      Icons.verified_user_outlined,
      _tr('Finance Officer Checks', 'ফাইন্যান্স অফিসারের যাচাই'),
      _tr('Bank, cash and cheque payments are checked and approved by finance officers before allocation.',
          'ব্যাংক, ক্যাশ ও চেক পেমেন্ট ফাইন্যান্স অফিসার যাচাই ও অনুমোদন করেন।'),
      ),
      (
      Icons.dns_outlined,
      _tr('Data Confidentiality', 'তথ্যের গোপনীয়তা'),
      _tr('Personal records are encrypted and only visible to authorised staff.',
          'ব্যক্তিগত তথ্য এনক্রিপ্টেড, শুধু অনুমোদিত কর্মীরা দেখতে পারেন।'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          eyebrow: _tr('Transparency', 'স্বচ্ছতা'),
          title: _tr('Clarity, Accountability', 'স্পষ্টতা, জবাবদিহিতা'),
          highlight: _tr('& Informed Decisions', 'ও সচেতন সিদ্ধান্ত'),
          description: _tr(
            'Biniyog Club pairs ledger precision with enforceable legal contracts to safeguard your capital at every step.',
            'লেজারের নির্ভুলতা আর আইনি চুক্তি দিয়ে প্রতিটি ধাপে আপনার টাকা সুরক্ষিত রাখা হয়।',
          ),
        ),
        const SizedBox(height: 18),
        for (final it in items)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _C.line)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _iconBox(it.$1, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.$2, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: _C.ink)),
                      const SizedBox(height: 3),
                      Text(it.$3, style: const TextStyle(fontSize: 13.5, color: _C.muted, height: 1.45)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        // Website er transparency infographic — chap dile boro kore dekha jay
        GestureDetector(
          onTap: () => _showImage(_A.transparency),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: _C.line),
              boxShadow: [BoxShadow(color: _C.emeraldDeep.withAlpha(22), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: AspectRatio(aspectRatio: 1122 / 1402, child: _assetImage(_A.transparency)),
          ),
        ),
        const SizedBox(height: 16),
        _linkButton(_tr('Our Due Diligence Approach', 'আমাদের যাচাই পদ্ধতি'),
                () => _openWeb(_tr('About', 'আমাদের সম্পর্কে'), '$_site/about'),
            filled: true),
      ],
    );
  }

  /// Chobi puro screen e — pinch kore zoom
  void _showImage(String asset) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(220),
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(child: _assetImage(asset, fit: BoxFit.contain)),
            ),
          ),
          Positioned(
            top: MediaQuery.of(ctx).padding.top + 8,
            right: 8,
            child: IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 09 Governance ────────────────────────────────────────
  Widget _governance() {
    final stages = <(IconData, String, String, String, List<String>)>[
      (
      Icons.search_rounded,
      '01',
      _tr('Sourcing', 'উৎস নির্বাচন'),
      _tr('Opportunities originate inside our operating groups, where management already runs the business.',
          'সুযোগগুলো আমাদের নিজস্ব গ্রুপ থেকে আসে, যেখানে ব্যবস্থাপনা আগে থেকেই ব্যবসা চালায়।'),
      [_tr('Business plan & capital need', 'ব্যবসা পরিকল্পনা ও মূলধন'), _tr('Asset and location review', 'সম্পদ ও লোকেশন যাচাই')],
      ),
      (
      Icons.fact_check_outlined,
      '02',
      _tr('Due diligence', 'যাচাই-বাছাই'),
      _tr('Financials, ownership documents and projected cash flows are examined first.',
          'আর্থিক হিসাব, মালিকানার কাগজ ও সম্ভাব্য আয় আগে পরীক্ষা করা হয়।'),
      [_tr('Legal & title documents', 'আইনি ও মালিকানার কাগজ'), _tr('Return and risk assessment', 'লাভ ও ঝুঁকি মূল্যায়ন')],
      ),
      (
      Icons.gavel_rounded,
      '03',
      _tr('Approval & listing', 'অনুমোদন ও প্রকাশ'),
      _tr('Each project is approved internally, then published with its terms, tiers and bank details.',
          'প্রতিটি প্রজেক্ট অনুমোদনের পর শর্ত, টিয়ার ও ব্যাংক তথ্যসহ প্রকাশ করা হয়।'),
      [_tr('Fixed minimums & durations', 'নির্দিষ্ট সর্বনিম্ন ও মেয়াদ'), _tr('Dedicated payment accounts', 'আলাদা পেমেন্ট অ্যাকাউন্ট')],
      ),
      (
      Icons.bar_chart_rounded,
      '04',
      _tr('Monitoring & reporting', 'পর্যবেক্ষণ ও রিপোর্ট'),
      _tr('Funded projects publish milestone updates and investors track every taka from their dashboard.',
          'প্রজেক্ট মাইলস্টোন আপডেট দেয়, বিনিয়োগকারী ড্যাশবোর্ডে প্রতিটি টাকা দেখেন।'),
      [_tr('Project updates & disclosures', 'আপডেট ও তথ্য প্রকাশ'), _tr('Receipts and deed certificates', 'রসিদ ও ডিড সার্টিফিকেট')],
      ),
    ];

    final principles = <(IconData, String, String)>[
      (Icons.balance_rounded, _tr('Segregated capital', 'আলাদা মূলধন'),
      _tr('Funds are tracked per project, never pooled with operating expenses.', 'টাকা প্রজেক্ট অনুযায়ী আলাদা থাকে।')),
      (Icons.visibility_outlined, _tr('Full disclosure', 'পূর্ণ তথ্য প্রকাশ'),
      _tr('Terms, risks and progress are visible to every investor.', 'শর্ত, ঝুঁকি ও অগ্রগতি সবাই দেখতে পান।')),
      (Icons.account_balance_outlined, _tr('Documented ownership', 'নথিভুক্ত মালিকানা'),
      _tr('Every confirmed investment has a receipt and a numbered deed.', 'প্রতিটি নিশ্চিত বিনিয়োগে রসিদ ও নম্বরসহ ডিড।')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          eyebrow: _tr('Governance', 'গভর্ন্যান্স'),
          title: _tr('A disciplined', 'একটি সুশৃঙ্খল'),
          highlight: _tr('investment lifecycle', 'বিনিয়োগ প্রক্রিয়া'),
          description: _tr(
            'Every opportunity follows the same four-stage process, so you can judge each one on a consistent standard.',
            'প্রতিটি সুযোগ একই চার ধাপ পার হয়, তাই সব একই মানদণ্ডে বিচার করা যায়।',
          ),
        ),
        const SizedBox(height: 18),
        // Grid er fixed uchchotay lekha kete jeto — tai ek column e, puro lekha
        for (final s in stages)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _C.line)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _iconBox(s.$1, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(s.$3,
                                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: _C.ink)),
                          ),
                          Text(s.$2,
                              style: const TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w300, color: _C.line)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(s.$4, style: const TextStyle(fontSize: 13, color: _C.muted, height: 1.45)),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final pt in s.$5)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              color: _C.emeraldSoft,
                              child: Text(pt,
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w700, color: _C.emerald)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        for (final p in principles)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: _C.ivory, border: Border.all(color: _C.line)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(p.$1, size: 19, color: _C.emerald),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _C.ink)),
                      const SizedBox(height: 2),
                      Text(p.$3, style: const TextStyle(fontSize: 13, color: _C.muted, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ─── 11 Latest updates (DB) ───────────────────────────────
  Widget _latestUpdates() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          eyebrow: _tr('Latest updates', 'সর্বশেষ আপডেট'),
          title: _tr('Live project', 'প্রজেক্টের'),
          highlight: _tr('disclosures', 'সর্বশেষ খবর'),
          description: _tr('Milestones, results and operational reports directly from active ventures.',
              'চলমান প্রজেক্ট থেকে সরাসরি মাইলস্টোন ও রিপোর্ট।'),
        ),
        const SizedBox(height: 18),
        for (final u in _updates)
          InkWell(
            onTap: (u['projectId']?.toString() ?? '').isEmpty
                ? null
                : () => _open(ProjectDetailPage(projectIdOrSlug: u['projectId'].toString())),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _C.line)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if ((u['coverImageUrl']?.toString() ?? '').startsWith('http'))
                    SizedBox(
                      height: 130,
                      child: Image.network(u['coverImageUrl'].toString(),
                          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _imagePlaceholder()),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              color: _C.emeraldSoft,
                              child: Text(_categoryLabel(u['type']?.toString() ?? 'GENERAL'),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _C.emerald)),
                            ),
                            const Spacer(),
                            Text(_fmtDate(u['publishedAt']?.toString() ?? ''),
                                style: const TextStyle(fontSize: 12.5, color: _C.muted)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(u['title']?.toString() ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: _C.ink)),
                        const SizedBox(height: 4),
                        Text(u['content']?.toString() ?? '',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5, color: _C.muted, height: 1.45)),
                        const SizedBox(height: 8),
                        Text(u['projectTitle']?.toString() ?? '',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _C.emerald)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ─── 12 FAQ ───────────────────────────────────────────────
  Widget _faq() {
    final minEntry = _minEntry;
    final faqs = <(String, String)>[
      (
      _tr('Who can invest?', 'কারা বিনিয়োগ করতে পারবেন?'),
      _tr(
          'Anyone aged 18 or over, from Bangladesh or abroad. Sign up with your name, phone number, date of birth and a password. Your NID, address and nominee can be added later from your profile.',
          '১৮ বছর বা তার বেশি বয়সী যে কেউ, দেশ বা বিদেশ থেকে। নাম, মোবাইল নম্বর, জন্ম তারিখ ও পাসওয়ার্ড দিয়ে রেজিস্টার করুন। এনআইডি, ঠিকানা ও নমিনী পরে প্রোফাইল থেকে দেওয়া যাবে।'),
      ),
      (
      _tr('What is the minimum investment?', 'সর্বনিম্ন কত টাকা বিনিয়োগ করা যায়?'),
      minEntry > 0
          ? _tr('Each project sets its own minimum. Right now projects open from ${_bdtShort(minEntry)}.',
          'প্রতিটি প্রজেক্টের নিজস্ব সর্বনিম্ন আছে। এখন ${_bdtShort(minEntry)} থেকে শুরু।')
          : _tr('Each project and tier sets its own minimum, shown on its page.',
          'প্রতিটি প্রজেক্ট ও টিয়ারের নিজস্ব সর্বনিম্ন তার পেজে দেখানো থাকে।'),
      ),
      (
      _tr('How do I pay?', 'কীভাবে টাকা দেব?'),
      _tr(
          'By bank transfer, cash or cheque — or a mix. For bank, add the transaction number and receipt photo; for cash, choose who received it; for cheque, upload a photo of the cheque.',
          'ব্যাংক, ক্যাশ বা চেক — বা একসাথে কয়েকটি। ব্যাংকে ট্রানজেকশন নম্বর ও রসিদের ছবি, ক্যাশে কে নিয়েছেন তা, আর চেকে চেকের ছবি দিন।'),
      ),
      (
      _tr('When does my investment become active?', 'বিনিয়োগ কখন চালু হয়?'),
      _tr(
          'It shows as pending until a finance officer verifies your payment. Once approved it becomes active and appears on your dashboard.',
          'ফাইন্যান্স অফিসার পেমেন্ট যাচাই না করা পর্যন্ত পেন্ডিং থাকে। অনুমোদনের পর চালু হয়ে ড্যাশবোর্ডে দেখা যায়।'),
      ),
      (
      _tr('Are returns guaranteed?', 'লাভ কি নিশ্চিত?'),
      _tr(
          'No. Each project shows its expected return range, set by its agreement. Actual returns depend on the business’s performance.',
          'না। প্রতিটি প্রজেক্ট চুক্তি অনুযায়ী প্রত্যাশিত লাভের হার দেখায়। আসল লাভ ব্যবসার ফলাফলের ওপর নির্ভর করে।'),
      ),
      (
      _tr('What documents do I get?', 'কী কী কাগজ পাব?'),
      _tr('A receipt number and a numbered deed certificate for every confirmed investment, available in Documents.',
          'প্রতিটি নিশ্চিত বিনিয়োগের রসিদ নম্বর ও নম্বরসহ ডিড সার্টিফিকেট, ডকুমেন্টস-এ পাবেন।'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          eyebrow: 'FAQ',
          title: _tr('Everything you need to', 'যা জানা দরকার'),
          highlight: _tr('know', 'সবকিছু'),
          description: _tr('Clear answers on payments, returns and documents.', 'পেমেন্ট, লাভ ও কাগজপত্র নিয়ে পরিষ্কার উত্তর।'),
        ),
        const SizedBox(height: 16),
        // ExpansionTile er bhitore ListTile — tai Container na, Material
        Material(
          color: Colors.white,
          shape: const RoundedRectangleBorder(side: BorderSide(color: _C.line)),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Column(
              children: [
                for (int i = 0; i < faqs.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: _C.line),
                  ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    iconColor: _C.emerald,
                    collapsedIconColor: _C.muted,
                    expandedAlignment: Alignment.centerLeft,
                    title: Text(faqs[i].$1,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _C.ink)),
                    children: [
                      Text(faqs[i].$2, style: const TextStyle(fontSize: 13, color: _C.muted, height: 1.5)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _C.line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_tr('Still have questions?', 'আরও প্রশ্ন আছে?'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _C.ink)),
              const SizedBox(height: 4),
              Text(
                _tr('Our investor relations team can help with contracts, bank transfers and deeds.',
                    'চুক্তি, ব্যাংক ট্রান্সফার ও ডিড নিয়ে আমাদের টিম সাহায্য করবে।'),
                style: const TextStyle(fontSize: 13.5, color: _C.muted, height: 1.45),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _openWeb(_tr('Contact', 'যোগাযোগ'), '$_site/contact'),
                      icon: const Icon(Icons.phone_in_talk_outlined, size: 16),
                      label: Text(_tr('Talk to an advisor', 'পরামর্শ নিন'), overflow: TextOverflow.ellipsis),
                      style: FilledButton.styleFrom(
                        backgroundColor: _C.emerald,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _openWeb('FAQ', '$_site/faq'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _C.ink,
                        side: const BorderSide(color: _C.line),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(_tr('All FAQs', 'সব প্রশ্ন')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── 13 Final CTA (dark) ──────────────────────────────────
  Widget _finalCta() {
    return Container(
      color: _C.emerald,
      child: Stack(
        children: [
          // Website er motoi: khamar er chobi halka kore, upore gaRho gradient
          Positioned.fill(child: Opacity(opacity: 0.25, child: _assetImage(_A.agro))),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [_C.emerald, _C.emerald.withAlpha(230), _C.emeraldBright.withAlpha(205)],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _C.emerald.withAlpha(160),
                    border: Border.all(color: _C.onDark.withAlpha(80)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: _C.onDark, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _investors > 0
                              ? _tr('Join $_investors investors on Biniyog Club', 'বিনিয়োগ ক্লাবের $_investors জন বিনিয়োগকারীর সাথে যোগ দিন')
                              : _tr('Now accepting investors', 'এখন বিনিয়োগকারী নেওয়া হচ্ছে'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _C.onDark, fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(_tr('Join the Biniyog Club', 'যোগ দিন বিনিয়োগ ক্লাব'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w300)),
                Text(_tr('Ecosystem', 'ইকোসিস্টেমে'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _C.onDark, fontSize: 30, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(
                  _tr(
                    'Create your investor account in under 2 minutes and get direct access to admin-vetted projects, business groups and legally protected contracts.',
                    '২ মিনিটে বিনিয়োগকারী অ্যাকাউন্ট খুলুন — যাচাই করা প্রজেক্ট, বিজনেস গ্রুপ আর আইনি সুরক্ষিত চুক্তিতে সরাসরি প্রবেশ।',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withAlpha(190), fontSize: 14.5, height: 1.55),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loggedIn ? _goDashboard : _goRegister,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _C.emerald,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _loggedIn
                          ? _tr('Go to my dashboard', 'আমার ড্যাশবোর্ডে যান')
                          : _tr('Create Free Investor Account', 'ফ্রি অ্যাকাউন্ট খুলুন'),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _openWeb(_tr('Contact', 'যোগাযোগ'), '$_site/contact'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withAlpha(80)),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(_tr('Talk to Our Advisory Team', 'আমাদের টিমের সাথে কথা বলুন')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    Widget link(String t, String path) => InkWell(
      onTap: () => _openWeb(t, '$_site$path'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(t, style: const TextStyle(fontSize: 13, color: _C.muted, fontWeight: FontWeight.w600)),
      ),
    );
    return Container(
      color: Colors.white,
      // Niche curved nav bar er pichone jate lekha na lukay
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              link(_tr('About', 'আমাদের সম্পর্কে'), '/about'),
              link(_tr('Terms', 'শর্তাবলী'), '/terms'),
              link(_tr('Privacy', 'প্রাইভেসি'), '/privacy'),
              link(_tr('Contact', 'যোগাযোগ'), '/contact'),
            ],
          ),
          const SizedBox(height: 6),
          Text('© ${DateTime.now().year} Biniyog Club · biniyogclub.com',
              style: const TextStyle(fontSize: 12.5, color: _C.muted)),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // PROJECTS TAB — shob public project, filter shoho
  // ═════════════════════════════════════════════════════════
  Widget _buildProjectsTab() {
    final filters = <(String, String)>[
      ('ALL', _tr('All', 'সব')),
      ('FUNDRAISING', _tr('Open', 'চলমান ফান্ড')),
      ('ACTIVE', _tr('Active', 'চলমান')),
      ('FUNDED', _tr('Funded', 'ফান্ড পূর্ণ')),
      ('COMPLETED', _tr('Completed', 'সম্পন্ন')),
    ];
    // "Open" = ekhon invest kora jay (deadline periye gele ar "Open" na)
    final list = _projectFilter == 'ALL'
        ? _projects
        : _projectFilter == 'FUNDRAISING'
        ? _projects.where((p) => p['acceptingInvestment'] == true).toList()
        : _projects.where((p) => p['status'] == _projectFilter).toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: _C.emerald,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 110), // niche nav bar er jayga
        children: [
          _heading(
            eyebrow: _tr('Investment opportunities', 'বিনিয়োগের সুযোগ'),
            title: _tr('All', 'সব'),
            highlight: _tr('Projects', 'প্রজেক্ট'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = filters[i];
                final on = f.$1 == _projectFilter;
                final count = f.$1 == 'ALL'
                    ? _projects.length
                    : f.$1 == 'FUNDRAISING'
                    ? _projects.where((p) => p['acceptingInvestment'] == true).length
                    : _projects.where((p) => p['status'] == f.$1).length;
                return ChoiceChip(
                  label: Text('${f.$2} ($count)'),
                  selected: on,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _projectFilter = f.$1),
                  selectedColor: _C.emerald,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: on ? _C.emerald : _C.line),
                  labelStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: on ? Colors.white : _C.ink),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            _emptyBox(_projects.isEmpty
                ? _tr('No projects are listed right now.', 'এই মুহূর্তে কোনো প্রজেক্ট নেই।')
                : _tr('No projects in this filter.', 'এই ফিল্টারে কোনো প্রজেক্ট নেই।'))
          else
            for (final p in list)
              Padding(padding: const EdgeInsets.only(bottom: 14), child: _projectCard(p, full: true)),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // GROUPS TAB
  // ═════════════════════════════════════════════════════════
  Widget _buildGroupsTab() {
    return RefreshIndicator(
      onRefresh: _load,
      color: _C.emerald,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 110), // niche nav bar er jayga
        children: [
          _heading(
            eyebrow: _tr('Our portfolio', 'আমাদের পোর্টফোলিও'),
            title: _tr('Business', 'বিজনেস'),
            highlight: _tr('Groups', 'গ্রুপ'),
            description: _tr('Invest at the group level through tiers with their own terms.',
                'নিজস্ব শর্তসহ টিয়ারের মাধ্যমে গ্রুপে বিনিয়োগ করুন।'),
          ),
          const SizedBox(height: 16),
          if (_groups.isEmpty)
            _emptyBox(_tr('Business groups will appear here.', 'বিজনেস গ্রুপ এখানে দেখা যাবে।'))
          else
            for (final g in _groups) _groupCard(g),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // ACCOUNT TAB
  // ═════════════════════════════════════════════════════════
  Widget _buildAccountTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 110),
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_C.emeraldBright, _C.emerald],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _C.onDark.withAlpha(150)),
                      ),
                      child: _assetImage(_A.logoIcon,
                          fit: BoxFit.contain,
                          fallback: const Icon(Icons.account_circle_outlined, color: _C.emerald, size: 30)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _loggedIn
                          ? _tr('You are signed in', 'আপনি সাইন ইন করা আছেন')
                          : _tr('Start investing today', 'আজই বিনিয়োগ শুরু করুন'),
                      style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _loggedIn
                          ? _tr('Open your dashboard to see your investments, payments and returns.',
                          'বিনিয়োগ, পেমেন্ট ও লাভ দেখতে ড্যাশবোর্ড খুলুন।')
                          : _tr('Create a free account or sign in to invest, submit payments and track returns.',
                          'বিনিয়োগ, পেমেন্ট ও লাভ দেখতে ফ্রি অ্যাকাউন্ট খুলুন বা সাইন ইন করুন।'),
                      style: TextStyle(color: Colors.white.withAlpha(195), fontSize: 14, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_loggedIn)
          _linkButton(_tr('Go to my dashboard', 'আমার ড্যাশবোর্ডে যান'), _goDashboard, filled: true)
        else ...[
          _linkButton(_tr('Create Free Investor Account', 'ফ্রি অ্যাকাউন্ট খুলুন'), _goRegister, filled: true),
          const SizedBox(height: 10),
          _linkButton(_tr('Sign in', 'সাইন ইন'), _goLogin),
        ],
        if (_loggedIn) ...[
          const SizedBox(height: 10),
          _linkButton(_tr('Help Center', 'হেল্প সেন্টার'), () => _open(const HelpCenterPage())),
        ],
        const SizedBox(height: 22),
        Text(_tr('MORE', 'আরও'),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _C.muted, letterSpacing: 1.4)),
        const SizedBox(height: 8),
        // Material (Container na) — ListTile er background ar tap er ripple
        // nikotsho Material e aanka hoy; Container e rakhle Flutter error dey
        Material(
          color: Colors.white,
          shape: const RoundedRectangleBorder(side: BorderSide(color: _C.line)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _menuRow(Icons.info_outline_rounded, _tr('About Biniyog Club', 'বিনিয়োগ ক্লাব সম্পর্কে'), '/about'),
              const Divider(height: 1, color: _C.line),
              _menuRow(Icons.help_outline_rounded, _tr('How it works', 'কীভাবে কাজ করে'), '/how-it-works'),
              const Divider(height: 1, color: _C.line),
              _menuRow(Icons.quiz_outlined, 'FAQ', '/faq'),
              const Divider(height: 1, color: _C.line),
              _menuRow(Icons.support_agent_outlined, _tr('Contact us', 'যোগাযোগ'), '/contact'),
              const Divider(height: 1, color: _C.line),
              _menuRow(Icons.description_outlined, _tr('Terms of Service', 'শর্তাবলী'), '/terms'),
              const Divider(height: 1, color: _C.line),
              _menuRow(Icons.privacy_tip_outlined, _tr('Privacy Policy', 'প্রাইভেসি পলিসি'), '/privacy'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _menuRow(IconData icon, String title, String path) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: _C.emerald, size: 19),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _C.ink)),
      trailing: const Icon(Icons.chevron_right_rounded, color: _C.muted),
      onTap: () => _openWeb(title, '$_site$path'),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Chobi na pele shudhu sobuj box (kono pattern nei)
// ═══════════════════════════════════════════════════════════
class _ImageFallbackBox extends StatelessWidget {
  const _ImageFallbackBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.emeraldBright, _C.emerald],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: Icon(Icons.image_outlined, color: Colors.white.withAlpha(120), size: 30)),
    );
  }
}