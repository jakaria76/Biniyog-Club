import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import 'investments_page.dart';

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  // ═════════════════════════════════════════════════════════
  // EXPECTED RETURN — Investments page er sathe hubohu ek
  // Project: 16–22%. Group: tier er nijer % (na thakle 16–22%).
  // ═════════════════════════════════════════════════════════
  static const double minReturnRate = 0.16;
  static const double maxReturnRate = 0.22;

  // ─── Palette ───
  static const Color emerald = Color(0xFF0E4A37);
  static const Color emeraldDeep = Color(0xFF0A3327);
  static const Color emeraldSoft = Color(0xFFE3F0E9);
  static const Color gold = Color(0xFFB8935A);
  static const Color goldLight = Color(0xFFD9BE8C);
  static const Color goldDeep = Color(0xFF8A6A3A);
  static const Color goldSoft = Color(0xFFF6EEDF);
  static const Color turquoise = Color(0xFF167A80);
  static const Color turquoiseSoft = Color(0xFFE0F1F1);
  static const Color lapis = Color(0xFF26437A);
  static const Color lapisSoft = Color(0xFFE5EAF4);
  static const Color terracotta = Color(0xFFA5523A);
  static const Color plum = Color(0xFF6B3E5E);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);
  static const Color danger = Color(0xFFB4413A);

  static const List<Color> _chartColors = [emerald, gold, turquoise, lapis, terracotta, plum];

  static const Map<String, String> categoryLabels = {
    'REAL_ESTATE': 'Real Estate',
    'TRADE_FINANCE': 'Trade Finance',
    'SME': 'SME Business',
    'TECHNOLOGY': 'Technology',
    'INFRASTRUCTURE': 'Infrastructure',
    'CROP_FARMING': 'Crop Farming',
    'LIVESTOCK': 'Livestock',
    'AQUACULTURE': 'Aquaculture',
    'POULTRY': 'Poultry',
    'DAIRY': 'Dairy',
    'HORTICULTURE': 'Horticulture',
    'AGRO_PROCESSING': 'Agro Processing',
    'OTHER': 'Other',
  };

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  bool _isLoading = true;
  bool _needsLogin = false;
  bool _loadFailed = false;

  /// Project + group ek list e
  List<Map<String, dynamic>> _items = [];

  double _totalInvested = 0.0; // ACTIVE + MATURED + COMPLETED
  double _projectInvested = 0.0;
  double _groupInvested = 0.0;
  double _activePrincipal = 0.0; // shudhu ACTIVE
  double _expectedMin = 0.0; // shudhu ACTIVE er upor
  double _expectedMax = 0.0;
  double _totalReceived = 0.0;
  int _activeCount = 0;
  String? _activeRateLabel;

  final Map<String, double> _allocation = {};
  final Map<String, int> _statusCounts = {};
  List<(DateTime, double)> _monthly = [];

  @override
  void initState() {
    super.initState();
    _loadPortfolioData();
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  bool _countsAsInvested(String s) => s == 'ACTIVE' || s == 'MATURED' || s == 'COMPLETED';

  /// Status ke 4 ta bhag e: ACTIVE, AWAITING, COMPLETED, CANCELLED
  String _bucket(String s) {
    switch (s) {
      case 'ACTIVE':
        return 'ACTIVE';
      case 'PENDING':
      case 'PAYMENT_PENDING':
        return 'AWAITING';
      case 'COMPLETED':
      case 'MATURED':
        return 'COMPLETED';
      default:
        return 'CANCELLED';
    }
  }

  DateTime? _parseDate(dynamic s) {
    if (s == null) return null;
    return DateTime.tryParse(s.toString())?.toLocal();
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '';
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _pctLabel(double min, double max) {
    String p(double r) {
      final v = r * 100;
      return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    }

    return min == max ? '${p(min)}%' : '${p(min)}–${p(max)}%';
  }

  String _trim(double v, int digits) {
    final s = v.toStringAsFixed(digits);
    return s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
  }

  String _fmtBdt(double amount) {
    if (amount >= 10000000) return '৳${_trim(amount / 10000000, 2)} Cr';
    if (amount >= 100000) return '৳${_trim(amount / 100000, 2)}L';
    if (amount >= 1000) return '৳${_trim(amount / 1000, 1)}K';
    return '৳${amount.toStringAsFixed(0)}';
  }

  String _fmtRange(double min, double max) =>
      min == max ? _fmtBdt(min) : '${_fmtBdt(min)} – ${_fmtBdt(max)}';

  String _bucketText(String b) {
    switch (b) {
      case 'ACTIVE':
        return LanguageService.tr('Active', 'একটিভ');
      case 'AWAITING':
        return LanguageService.tr('Awaiting Payment', 'পেমেন্ট অপেক্ষমান');
      case 'COMPLETED':
        return LanguageService.tr('Completed', 'সম্পন্ন');
      default:
        return LanguageService.tr('Cancelled', 'বাতিল');
    }
  }

  Color _bucketColor(String b) {
    switch (b) {
      case 'ACTIVE':
        return emerald;
      case 'AWAITING':
        return goldDeep;
      case 'COMPLETED':
        return lapis;
      default:
        return danger;
    }
  }

  // ═════════════════════════════════════════════════════════
  // DATA
  // ═════════════════════════════════════════════════════════
  Map<String, dynamic> _fromProject(Map<String, dynamic> inv) {
    final cat = inv['category']?.toString() ?? 'OTHER';
    return {
      'kind': 'PROJECT',
      'title': inv['title']?.toString() ?? 'Biniyog Project',
      'subtitle': categoryLabels[cat] ?? cat,
      'allocationKey': categoryLabels[cat] ?? cat,
      'amount': _num(inv['amountBdt']),
      'status': inv['status']?.toString() ?? 'PENDING',
      'createdAt': _parseDate(inv['createdAt']),
      'start': _parseDate(inv['activatedAt']) ?? _parseDate(inv['createdAt']),
      // Project er nijer range (DB), na thakle 16–22%
      'rMin': _num(inv['returnMin']) > 0 ? _num(inv['returnMin']) : minReturnRate,
      'rMax': _num(inv['returnMax']) > 0 ? _num(inv['returnMax']) : maxReturnRate,
      'received': _num(inv['actualReturnBdt']),
    };
  }

  Map<String, dynamic> _fromGroup(Map<String, dynamic> g) {
    final group = g['groupName']?.toString() ?? 'Business Group';
    final entity = g['entityName']?.toString() ?? '';
    final tierPct = _num(g['expectedReturnPct']);
    final showEntity = entity.isNotEmpty && entity.toLowerCase() != group.toLowerCase();
    return {
      'kind': 'GROUP',
      'title': showEntity ? '$group — $entity' : group,
      'subtitle': g['tierName']?.toString() ?? '',
      'allocationKey': '$group (${LanguageService.tr('Group', 'গ্রুপ')})',
      'amount': _num(g['amountBdt']),
      'status': g['status']?.toString() ?? 'PENDING',
      'createdAt': _parseDate(g['createdAt']),
      'start': _parseDate(g['createdAt']),
      'rMin': tierPct > 0 ? tierPct : minReturnRate,
      'rMax': tierPct > 0 ? tierPct : maxReturnRate,
      'received': 0.0,
    };
  }

  Future<void> _loadPortfolioData() async {
    if (mounted) setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    final userEmail = userData?['email']?.toString() ?? '';

    // Login chara onner portfolio kokhono na
    if (userId.isEmpty) {
      if (mounted) {
        setState(() {
          _needsLogin = true;
          _isLoading = false;
        });
      }
      return;
    }

    final results = await Future.wait<dynamic>([
      DatabaseService.getPortfolioData(userId, email: userEmail),
      DatabaseService.getGroupInvestmentsData(userId, email: userEmail),
    ]);
    final pData = results[0] as Map<String, dynamic>;
    final gData = results[1] as List<Map<String, dynamic>>;

    // getPortfolioData login thakleo khali map dile mane server e pouchate pareni
    if (pData.isEmpty) {
      if (mounted) {
        setState(() {
          _loadFailed = true;
          _isLoading = false;
        });
      }
      return;
    }

    final items = <Map<String, dynamic>>[
      ...((pData['investments'] as List?) ?? [])
          .map((e) => _fromProject(Map<String, dynamic>.from(e as Map))),
      ...gData.map(_fromGroup),
    ]..sort((a, b) {
      final da = a['createdAt'] as DateTime?;
      final db = b['createdAt'] as DateTime?;
      if (da == null || db == null) return 0;
      return db.compareTo(da);
    });

    double invested = 0, projectInv = 0, groupInv = 0;
    double activePrincipal = 0, expMin = 0, expMax = 0, received = 0;
    int active = 0;
    final rateLabels = <String>{};
    final alloc = <String, double>{};
    final counts = <String, int>{};

    final now = DateTime.now();
    final monthKeys = List.generate(12, (i) => DateTime(now.year, now.month - 11 + i));
    final monthTotals = {for (final m in monthKeys) '${m.year}-${m.month}': 0.0};

    for (final it in items) {
      final st = it['status'] as String;
      final amt = it['amount'] as double;
      final isProject = it['kind'] == 'PROJECT';

      counts[_bucket(st)] = (counts[_bucket(st)] ?? 0) + 1;
      received += it['received'] as double;

      if (_countsAsInvested(st)) {
        invested += amt;
        if (isProject) {
          projectInv += amt;
        } else {
          groupInv += amt;
        }

        final key = it['allocationKey'] as String;
        alloc[key] = (alloc[key] ?? 0) + amt;

        final d = it['start'] as DateTime?;
        if (d != null) {
          final mk = '${d.year}-${d.month}';
          if (monthTotals.containsKey(mk)) monthTotals[mk] = monthTotals[mk]! + amt;
        }
      }

      // Expected return shudhu chalu (ACTIVE) investment er — shesh hoye
      // jawa gular lav already "Returns Received" e ache
      if (st == 'ACTIVE') {
        active++;
        activePrincipal += amt;
        expMin += amt * (it['rMin'] as double);
        expMax += amt * (it['rMax'] as double);
        rateLabels.add(_pctLabel(it['rMin'] as double, it['rMax'] as double));
      }
    }

    final sortedAlloc = alloc.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    if (!mounted) return;
    setState(() {
      _items = items;
      _totalInvested = invested;
      _projectInvested = projectInv;
      _groupInvested = groupInv;
      _activePrincipal = activePrincipal;
      _expectedMin = expMin;
      _expectedMax = expMax;
      _totalReceived = received;
      _activeCount = active;
      _activeRateLabel = rateLabels.length == 1 ? rateLabels.first : null;

      _allocation
        ..clear()
        ..addEntries(sortedAlloc);
      _statusCounts
        ..clear()
        ..addAll(counts);
      _monthly = monthKeys.map((m) => (m, monthTotals['${m.year}-${m.month}'] ?? 0.0)).toList();

      _needsLogin = false;
      _loadFailed = false;
      _isLoading = false;
    });
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        final projectCount = _items.where((i) => i['kind'] == 'PROJECT').length;
        final groupCount = _items.length - projectCount;

        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              LanguageService.tr('Portfolio', 'পোর্টফোলিও'),
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
            Icons.lock_outline_rounded,
            LanguageService.tr('Please log in to see your portfolio',
                'পোর্টফোলিও দেখতে লগইন করুন'),
            null,
            LanguageService.tr('Log in', 'লগইন'),
                () async {
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
            Icons.wifi_off_rounded,
            LanguageService.tr('Could not load your portfolio',
                'পোর্টফোলিও লোড করা যায়নি'),
            LanguageService.tr('Please check your internet connection.',
                'ইন্টারনেট সংযোগ চেক করুন।'),
            LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
            _loadPortfolioData,
          )
              : RefreshIndicator(
            onRefresh: _loadPortfolioData,
            color: emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                Text(
                  LanguageService.tr(
                      '${_items.length} investments · $projectCount project · $groupCount group',
                      'মোট ${_items.length} টি বিনিয়োগ · প্রজেক্ট $projectCount · গ্রুপ $groupCount'),
                  style: const TextStyle(fontSize: 13, color: muted),
                ),
                const SizedBox(height: 14),
                _buildHeroCard(),
                const SizedBox(height: 12),
                _buildKpiRow(),
                const SizedBox(height: 22),
                _buildAllocationCard(),
                const SizedBox(height: 16),
                _buildStatusCard(),
                const SizedBox(height: 16),
                _buildHistoryChartCard(),
                const SizedBox(height: 16),
                _buildInvestmentListCard(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Hero: active investment er sombhabbo mullo ──────────
  Widget _buildHeroCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
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
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: gold.withAlpha(80), width: 0.8),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          LanguageService.tr('PROJECTED VALUE AT MATURITY',
                              'মেয়াদ শেষে সম্ভাব্য মূল্য'),
                          style: const TextStyle(
                            color: goldLight,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.3,
                          ),
                        ),
                      ),
                      if (_activeRateLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [goldLight, gold]),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _activeRateLabel!,
                            style: const TextStyle(
                              color: emeraldDeep,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _activeCount == 0
                          ? _fmtBdt(0)
                          : _fmtRange(_activePrincipal + _expectedMin,
                          _activePrincipal + _expectedMax),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _activeCount == 0
                        ? LanguageService.tr('No active investments right now.',
                        'এই মুহূর্তে কোনো চলমান বিনিয়োগ নেই।')
                        : LanguageService.tr(
                        '${_fmtBdt(_activePrincipal)} active principal + ${_fmtRange(_expectedMin, _expectedMax)} expected return',
                        '${_fmtBdt(_activePrincipal)} চলমান মূলধন + ${_fmtRange(_expectedMin, _expectedMax)} প্রত্যাশিত লাভ'),
                    style: TextStyle(
                      color: Colors.white.withAlpha(170),
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    LanguageService.tr(
                        'Estimated, not guaranteed. Final returns depend on project performance.',
                        'আনুমানিক, নিশ্চিত নয়। চূড়ান্ত লাভ প্রজেক্টের ফলাফলের উপর নির্ভর করে।'),
                    style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 10, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── KPI ──────────────────────────────────────────────────
  Widget _buildKpiRow() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                LanguageService.tr('Total Invested', 'মোট বিনিয়োগ'),
                _fmtBdt(_totalInvested),
                LanguageService.tr('Project ${_fmtBdt(_projectInvested)} · Group ${_fmtBdt(_groupInvested)}',
                    'প্রজেক্ট ${_fmtBdt(_projectInvested)} · গ্রুপ ${_fmtBdt(_groupInvested)}'),
                Icons.account_balance_wallet_outlined,
                emerald,
                emeraldSoft,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _kpiCard(
                LanguageService.tr('Returns Received', 'প্রাপ্ত লাভ'),
                _fmtBdt(_totalReceived),
                LanguageService.tr('Distributed so far', 'এ পর্যন্ত প্রাপ্ত'),
                Icons.savings_outlined,
                lapis,
                lapisSoft,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _kpiCard(
          _activeRateLabel != null
              ? LanguageService.tr('Expected Return ($_activeRateLabel)',
              'প্রত্যাশিত লাভ ($_activeRateLabel)')
              : LanguageService.tr('Expected Return', 'প্রত্যাশিত লাভ'),
          _fmtRange(_expectedMin, _expectedMax),
          LanguageService.tr('From $_activeCount active investments',
              '$_activeCount টি চলমান বিনিয়োগ থেকে'),
          Icons.trending_up_rounded,
          goldDeep,
          goldSoft,
          wide: true,
        ),
      ],
    );
  }

  Widget _kpiCard(String label, String value, String sub, IconData icon, Color color, Color soft,
      {bool wide = false}) {
    final iconBox = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 16, color: Colors.white),
    );

    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: color.withAlpha(210), fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color),
          ),
        ),
        Text(
          sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: color.withAlpha(170)),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(16)),
      child: wide
          ? Row(children: [iconBox, const SizedBox(width: 12), Expanded(child: texts)])
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [iconBox, const SizedBox(height: 10), texts],
      ),
    );
  }

  // ─── Card shell ───────────────────────────────────────────
  Widget _card({required String title, String? subtitle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
              Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [goldLight, gold]),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: ink),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 17),
              child: Text(subtitle, style: const TextStyle(fontSize: 11, color: muted)),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _emptyText(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12.5, color: muted),
      ),
    ),
  );

  // ─── Allocation (shudhu invested taka) ────────────────────
  Widget _buildAllocationCard() {
    final double base = _allocation.values.fold(0.0, (a, b) => a + b);
    final entries = _allocation.entries.toList();

    return _card(
      title: LanguageService.tr('Where Your Money Is', 'আপনার টাকা কোথায় আছে'),
      subtitle: LanguageService.tr('Active and completed investments',
          'চলমান ও সম্পন্ন বিনিয়োগ'),
      child: entries.isEmpty || base <= 0
          ? _emptyText(LanguageService.tr('No active investments yet.',
          'এখনো কোনো চলমান বিনিয়োগ নেই।'))
          : Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (int i = 0; i < entries.length; i++)
                    Expanded(
                      flex: ((entries[i].value / base) * 1000).round().clamp(1, 1000),
                      child: Container(color: _chartColors[i % _chartColors.length]),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < entries.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _chartColors[i % _chartColors.length],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entries[i].key,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink),
                    ),
                  ),
                  Text(
                    _fmtBdt(entries[i].value),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink),
                  ),
                  Container(
                    width: 54,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${(entries[i].value / base * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _chartColors[i % _chartColors.length],
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

  // ─── Status ───────────────────────────────────────────────
  Widget _buildStatusCard() {
    const order = ['ACTIVE', 'AWAITING', 'COMPLETED', 'CANCELLED'];
    final entries = order
        .where((k) => (_statusCounts[k] ?? 0) > 0)
        .map((k) => MapEntry(k, _statusCounts[k]!))
        .toList();
    final total = entries.fold(0, (a, e) => a + e.value);

    return _card(
      title: LanguageService.tr('Investment Status', 'বিনিয়োগের অবস্থা'),
      child: entries.isEmpty
          ? _emptyText(LanguageService.tr('No investments yet.', 'এখনো কোনো বিনিয়োগ নেই।'))
          : Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: entries
                    .map((e) => Expanded(
                  flex: e.value,
                  child: Container(color: _bucketColor(e.key)),
                ))
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entries.map((e) {
              final c = _bucketColor(e.key);
              final pct = total > 0 ? e.value / total * 100 : 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: c.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _bucketText(e.key),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${e.value}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '(${pct.toStringAsFixed(0)}%)',
                      style: TextStyle(fontSize: 10.5, color: c.withAlpha(180)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─── 12 masher chart ──────────────────────────────────────
  Widget _buildHistoryChartCard() {
    final maxVal = _monthly.fold<double>(0, (m, e) => e.$2 > m ? e.$2 : m);

    return _card(
      title: LanguageService.tr('Investment History', 'বিনিয়োগের ইতিহাস'),
      subtitle: LanguageService.tr('Amount activated per month · last 12 months',
          'মাসভিত্তিক একটিভ হওয়া বিনিয়োগ · গত ১২ মাস'),
      child: maxVal <= 0
          ? _emptyText(LanguageService.tr('No active investments in the last 12 months.',
          'গত ১২ মাসে কোনো একটিভ বিনিয়োগ নেই।'))
          : SizedBox(
        height: 170,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: _monthly.map((e) {
            final ratio = e.$2 / maxVal;
            final isMax = e.$2 == maxVal;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isMax)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: FittedBox(
                          child: Text(
                            _fmtBdt(e.$2),
                            style: const TextStyle(
                                fontSize: 9, fontWeight: FontWeight.w700, color: emerald),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: e.$2 > 0 ? ratio.clamp(0.04, 1.0) : 0.02,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: e.$2 > 0
                                  ? const LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [emerald, turquoise],
                              )
                                  : null,
                              color: e.$2 > 0 ? null : line,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_months[e.$1.month - 1],
                        style: const TextStyle(fontSize: 9, color: muted)),
                    Text(
                      "'${(e.$1.year % 100).toString().padLeft(2, '0')}",
                      style: TextStyle(fontSize: 8, color: muted.withAlpha(150)),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─── Shob investment ──────────────────────────────────────
  Widget _buildInvestmentListCard() {
    return _card(
      title: LanguageService.tr('All Investments', 'সকল বিনিয়োগ'),
      child: _items.isEmpty
          ? _emptyText(LanguageService.tr('No investments yet.', 'এখনো কোনো বিনিয়োগ নেই।'))
          : Column(
        children: [
          for (int i = 0; i < _items.length; i++) ...[
            if (i > 0) const Divider(height: 20, color: line),
            _investmentRow(_items[i], i),
          ],
        ],
      ),
    );
  }

  Widget _investmentRow(Map<String, dynamic> it, int index) {
    final isGroup = it['kind'] == 'GROUP';
    final bucket = _bucket(it['status'] as String);
    final c = _bucketColor(bucket);
    final amt = it['amount'] as double;
    final title = it['title'] as String;
    final sub = it['subtitle'] as String;
    final date = _fmtDate(it['createdAt'] as DateTime?);
    final rMin = it['rMin'] as double;
    final rMax = it['rMax'] as double;
    final received = it['received'] as double;
    final accent = isGroup ? turquoise : _chartColors[index % _chartColors.length];

    // Status onujayi ki dekhabo — kono fake "expected" na
    String? note;
    Color noteColor = goldDeep;
    if (bucket == 'ACTIVE') {
      note = '${LanguageService.tr('Expected', 'প্রত্যাশিত')} +${_fmtRange(amt * rMin, amt * rMax)} (${_pctLabel(rMin, rMax)})';
    } else if (bucket == 'COMPLETED') {
      note = received > 0
          ? '${LanguageService.tr('Received', 'প্রাপ্ত')} +${_fmtBdt(received)}'
          : null;
      noteColor = lapis;
    } else if (bucket == 'AWAITING') {
      note = LanguageService.tr('Starts after payment is approved', 'পেমেন্ট অনুমোদনের পর শুরু হবে');
      noteColor = muted;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => InvestmentsPage(initialType: isGroup ? 'GROUP' : 'PROJECT')),
      ).then((_) => _loadPortfolioData()),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isGroup ? Icons.apartment_rounded : Icons.trending_up_rounded,
              color: accent,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    isGroup ? LanguageService.tr('Group', 'গ্রুপ') : LanguageService.tr('Project', 'প্রজেক্ট'),
                    if (sub.isNotEmpty) sub,
                    if (date.isNotEmpty) date,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
                if (note != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    note,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: noteColor),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmtBdt(amt),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
              ),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.withAlpha(25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _bucketText(bucket),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(
      IconData icon, String title, String? subtitle, String buttonLabel, VoidCallback onTap) {
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
              Text(subtitle,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: muted)),
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