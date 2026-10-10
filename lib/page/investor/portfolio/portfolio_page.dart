import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  // ═════════════════════════════════════════════════════════
  // EXPECTED RETURN RANGE — investments page er sathe same
  // ═════════════════════════════════════════════════════════
  static const double minReturnRate = 0.16; // 16%
  static const double maxReturnRate = 0.22; // 22%

  bool _isLoading = true;

  double _totalInvested = 0.0;
  double _totalExpectedMin = 0.0;
  double _totalExpectedMax = 0.0;
  double _totalActual = 0.0;
  int _activeCount = 0;

  List<Map<String, dynamic>> _investments = [];
  final Map<String, double> _categoryAllocation = {};
  final Map<String, int> _statusDistribution = {};
  List<(DateTime, double)> _monthly = [];

  // ─── Palette ───
  static const Color emerald = Color(0xFF0E4A37);
  static const Color emeraldDeep = Color(0xFF0A3327);
  static const Color emeraldSoft = Color(0xFFE3F0E9);
  static const Color gold = Color(0xFFB8935A);
  static const Color goldLight = Color(0xFFD9BE8C);
  static const Color goldDeep = Color(0xFF8A6A3A);
  static const Color goldSoft = Color(0xFFF6EEDF);
  static const Color turquoise = Color(0xFF167A80);
  static const Color lapis = Color(0xFF26437A);
  static const Color lapisSoft = Color(0xFFE5EAF4);
  static const Color terracotta = Color(0xFFA5523A);
  static const Color plum = Color(0xFF6B3E5E);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);
  static const Color danger = Color(0xFFB4413A);

  static const List<Color> _chartColors = [
    emerald,
    gold,
    turquoise,
    lapis,
    terracotta,
    plum,
  ];

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

  @override
  void initState() {
    super.initState();
    _loadPortfolioData();
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  bool _countsAsInvested(String s) =>
      s == 'ACTIVE' || s == 'MATURED' || s == 'COMPLETED';

  DateTime? _parseDate(dynamic s) {
    if (s == null) return null;
    return DateTime.tryParse(s.toString())?.toLocal();
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String get _rangeLabel {
    String p(double r) {
      final v = r * 100;
      return v == v.roundToDouble()
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(1);
    }

    return '${p(minReturnRate)}–${p(maxReturnRate)}%';
  }

  String _trim(double v, int digits) {
    final s = v.toStringAsFixed(digits);
    return s.contains('.')
        ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')
        : s;
  }

  String _fmtBdt(double amount) {
    if (amount >= 10000000) return '৳${_trim(amount / 10000000, 2)} Cr';
    if (amount >= 100000) return '৳${_trim(amount / 100000, 2)}L';
    if (amount >= 1000) return '৳${_trim(amount / 1000, 1)}K';
    return '৳${amount.toStringAsFixed(0)}';
  }

  String _fmtRange(double min, double max) =>
      '${_fmtBdt(min)} – ${_fmtBdt(max)}';

  String _statusText(String st) {
    switch (st) {
      case 'ACTIVE':
        return LanguageService.tr('Active', 'একটিভ');
      case 'PAYMENT_PENDING':
        return LanguageService.tr('Awaiting Payment', 'পেমেন্ট অপেক্ষমান');
      case 'COMPLETED':
      case 'MATURED':
        return LanguageService.tr('Completed', 'সম্পন্ন');
      case 'CANCELLED':
        return LanguageService.tr('Cancelled', 'বাতিল');
      default:
        return LanguageService.tr('Draft', 'ড্রাফট');
    }
  }

  Color _statusColor(String st) {
    switch (st) {
      case 'ACTIVE':
        return emerald;
      case 'PAYMENT_PENDING':
        return gold;
      case 'COMPLETED':
      case 'MATURED':
        return lapis;
      case 'CANCELLED':
        return danger;
      default:
        return terracotta;
    }
  }

  // ═════════════════════════════════════════════════════════
  // DATA
  // ═════════════════════════════════════════════════════════
  Future<void> _loadPortfolioData() async {
    setState(() => _isLoading = true);

    var userData = await AuthService.getUserData();

    if (userData == null ||
        (userData['id'] == null && userData['email'] == null)) {
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

    final pData =
    await DatabaseService.getPortfolioData(userId, email: userEmail);

    if (!mounted) return;

    setState(() {
      if (pData.isNotEmpty) {
        _investments =
        (pData['investments'] as List<Map<String, dynamic>>? ?? []);

        double invested = 0, actual = 0;
        int active = 0;
        final Map<String, double> catMap = {};
        final Map<String, int> stMap = {};

        // Last 12 months buckets
        final now = DateTime.now();
        final List<DateTime> monthKeys = List.generate(
          12,
              (i) => DateTime(now.year, now.month - 11 + i),
        );
        final Map<String, double> monthTotals = {
          for (final m in monthKeys) '${m.year}-${m.month}': 0.0,
        };

        for (final inv in _investments) {
          final st = inv['status']?.toString() ?? 'PENDING';
          final amt = (inv['amountBdt'] as num?)?.toDouble() ?? 0.0;
          final cat = inv['category']?.toString() ?? 'SME';

          stMap[st] = (stMap[st] ?? 0) + 1;
          actual += (inv['actualReturnBdt'] as num?)?.toDouble() ?? 0.0;

          if (st != 'CANCELLED') {
            final catName = categoryLabels[cat] ?? cat;
            catMap[catName] = (catMap[catName] ?? 0.0) + amt;
          }

          if (_countsAsInvested(st)) {
            invested += amt;
            if (st == 'ACTIVE') active++;

            final d = _parseDate(inv['activatedAt']) ??
                _parseDate(inv['createdAt']);
            if (d != null) {
              final key = '${d.year}-${d.month}';
              if (monthTotals.containsKey(key)) {
                monthTotals[key] = monthTotals[key]! + amt;
              }
            }
          }
        }

        _totalInvested = invested;
        _totalExpectedMin = invested * minReturnRate;
        _totalExpectedMax = invested * maxReturnRate;
        _totalActual = actual;
        _activeCount = active;

        final sortedCats = catMap.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        _categoryAllocation
          ..clear()
          ..addEntries(sortedCats);

        _statusDistribution
          ..clear()
          ..addAll(stMap);

        _monthly = monthKeys
            .map((m) => (m, monthTotals['${m.year}-${m.month}'] ?? 0.0))
            .toList();
      }
      _isLoading = false;
    });
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final int categoriesCount = _categoryAllocation.length;

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
              LanguageService.tr('Portfolio', 'পোর্টফোলিও'),
              style: const TextStyle(
                color: ink,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
          body: _isLoading
              ? const Center(
              child: CircularProgressIndicator(
                  color: emerald, strokeWidth: 2.4))
              : RefreshIndicator(
            onRefresh: _loadPortfolioData,
            color: emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                Text(
                  LanguageService.tr(
                      '${_investments.length} investments across $categoriesCount categories',
                      '$categoriesCount টি ক্যাটাগরিতে মোট ${_investments.length} টি বিনিয়োগ'),
                  style: const TextStyle(fontSize: 13, color: muted),
                ),
                const SizedBox(height: 14),
                _buildHeroCard(),
                const SizedBox(height: 12),
                _buildKpiRow(),
                const SizedBox(height: 22),
                _buildCategoryAllocationCard(),
                const SizedBox(height: 16),
                _buildStatusDistributionCard(),
                const SizedBox(height: 16),
                _buildHistoryChartCard(),
                const SizedBox(height: 16),
                _buildInvestmentHistoryCard(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Hero: Projected value ────────────────────────────────
  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF125A43), emeraldDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: emerald.withAlpha(50),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                LanguageService.tr(
                    'PROJECTED VALUE AT MATURITY', 'মেয়াদ শেষে সম্ভাব্য মূল্য'),
                style: const TextStyle(
                  color: goldLight,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.3,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [goldLight, gold]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _rangeLabel,
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
              _fmtRange(_totalInvested + _totalExpectedMin,
                  _totalInvested + _totalExpectedMax),
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
            LanguageService.tr(
              '${_fmtBdt(_totalInvested)} principal + ${_fmtRange(_totalExpectedMin, _totalExpectedMax)} expected return',
              '${_fmtBdt(_totalInvested)} মূলধন + ${_fmtRange(_totalExpectedMin, _totalExpectedMax)} প্রত্যাশিত লাভ',
            ),
            style: TextStyle(
              color: Colors.white.withAlpha(170),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ─── KPI Row ──────────────────────────────────────────────
  Widget _buildKpiRow() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                LanguageService.tr('Total Invested', 'মোট বিনিয়োগ'),
                _fmtBdt(_totalInvested),
                LanguageService.tr(
                    '$_activeCount active', '$_activeCount টি একটিভ'),
                Icons.account_balance_wallet_outlined,
                emerald,
                emeraldSoft,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _kpiCard(
                LanguageService.tr('Returns Received', 'প্রাপ্ত লাভ'),
                _fmtBdt(_totalActual),
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
          LanguageService.tr('Expected Returns ($_rangeLabel)',
              'প্রত্যাশিত লাভ ($_rangeLabel)'),
          _fmtRange(_totalExpectedMin, _totalExpectedMax),
          LanguageService.tr('At maturity', 'মেয়াদপূর্তিতে'),
          Icons.trending_up_rounded,
          goldDeep,
          goldSoft,
          wide: true,
        ),
      ],
    );
  }

  Widget _kpiCard(String label, String value, String sub, IconData icon,
      Color color, Color soft,
      {bool wide = false}) {
    final iconBox = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 16, color: Colors.white),
    );

    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: color.withAlpha(210),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: color),
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
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: wide
          ? Row(
        children: [
          iconBox,
          const SizedBox(width: 12),
          Expanded(child: texts),
        ],
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          iconBox,
          const SizedBox(height: 10),
          texts,
        ],
      ),
    );
  }

  // ─── Card shell ───────────────────────────────────────────
  Widget _card({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
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
                angle: 0.785398,
                child: Container(width: 7, height: 7, color: gold),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 17),
              child: Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: muted),
              ),
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
      child: Text(text,
          style: const TextStyle(fontSize: 12.5, color: muted)),
    ),
  );

  // ─── Category Allocation ──────────────────────────────────
  Widget _buildCategoryAllocationCard() {
    final double base =
    _categoryAllocation.values.fold(0.0, (a, b) => a + b);

    return _card(
      title: LanguageService.tr(
          'Allocation by Category', 'ক্যাটাগরি ভিত্তিক বণ্টন'),
      child: _categoryAllocation.isEmpty || base <= 0
          ? _emptyText(LanguageService.tr(
          'No investments yet.', 'এখনো কোনো বিনিয়োগ নেই।'))
          : Column(
        children: [
          // Stacked bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: _categoryAllocation.entries
                    .toList()
                    .asMap()
                    .entries
                    .map((e) {
                  final flex =
                  ((e.value.value / base) * 1000).round().clamp(1, 1000);
                  return Expanded(
                    flex: flex,
                    child: Container(
                      color: _chartColors[e.key % _chartColors.length],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ..._categoryAllocation.entries
              .toList()
              .asMap()
              .entries
              .map((e) {
            final color = _chartColors[e.key % _chartColors.length];
            final pct = (e.value.value / base) * 100;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      e.value.key,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ),
                  Text(
                    _fmtBdt(e.value.value),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 52,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${pct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── Status Distribution ──────────────────────────────────
  Widget _buildStatusDistributionCard() {
    final total = _statusDistribution.values.fold(0, (a, b) => a + b);
    const order = [
      'ACTIVE',
      'PAYMENT_PENDING',
      'PENDING',
      'COMPLETED',
      'MATURED',
      'CANCELLED'
    ];
    final entries = _statusDistribution.entries.toList()
      ..sort((a, b) {
        final ia = order.indexOf(a.key);
        final ib = order.indexOf(b.key);
        return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
      });

    return _card(
      title: LanguageService.tr(
          'Investment Status', 'ইনভেস্টমেন্ট স্ট্যাটাস'),
      child: entries.isEmpty
          ? _emptyText(LanguageService.tr(
          'No investments yet.', 'এখনো কোনো বিনিয়োগ নেই।'))
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
                  child:
                  Container(color: _statusColor(e.key)),
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
              final c = _statusColor(e.key);
              final pct = total > 0 ? (e.value / total) * 100 : 0;
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
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
                      decoration: BoxDecoration(
                          color: c, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _statusText(e.key),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${e.value}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: c,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '(${pct.toStringAsFixed(0)}%)',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: c.withAlpha(180),
                      ),
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

  // ─── 12-Month History Chart ───────────────────────────────
  Widget _buildHistoryChartCard() {
    final maxVal =
    _monthly.fold<double>(0, (m, e) => e.$2 > m ? e.$2 : m);
    final hasData = maxVal > 0;

    return _card(
      title: LanguageService.tr(
          'Investment History', 'বিনিয়োগের হিস্ট্রি'),
      subtitle: LanguageService.tr(
          'Amount invested per month · last 12 months',
          'মাসভিত্তিক বিনিয়োগ · গত ১২ মাস'),
      child: !hasData
          ? _emptyText(LanguageService.tr(
          'No active investments in the last 12 months.',
          'গত ১২ মাসে কোনো একটিভ বিনিয়োগ নেই।'))
          : SizedBox(
        height: 170,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: _monthly.map((e) {
            final ratio = maxVal > 0 ? e.$2 / maxVal : 0.0;
            final isMax = e.$2 == maxVal && e.$2 > 0;
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
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: emerald,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: e.$2 > 0
                              ? ratio.clamp(0.04, 1.0)
                              : 0.02,
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
                    Text(
                      _months[e.$1.month - 1],
                      style: const TextStyle(
                          fontSize: 9, color: muted),
                    ),
                    Text(
                      "'${(e.$1.year % 100).toString().padLeft(2, '0')}",
                      style: TextStyle(
                          fontSize: 8,
                          color: muted.withAlpha(150)),
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

  // ─── Investment List ──────────────────────────────────────
  Widget _buildInvestmentHistoryCard() {
    return _card(
      title: LanguageService.tr('All Investments', 'সকল বিনিয়োগ'),
      child: _investments.isEmpty
          ? _emptyText(LanguageService.tr(
          'No investment history.', 'কোনো ইনভেস্টমেন্ট হিস্ট্রি নেই।'))
          : Column(
        children: _investments.asMap().entries.map((entry) {
          final i = entry.key;
          final inv = entry.value;
          final st = inv['status']?.toString() ?? 'PENDING';
          final c = _statusColor(st);
          final amt = (inv['amountBdt'] as num?)?.toDouble() ?? 0.0;
          final title = inv['title']?.toString() ?? 'Project';
          final cat = categoryLabels[inv['category']] ??
              inv['category']?.toString() ??
              'SME';
          final accent = _chartColors[i % _chartColors.length];

          return Column(
            children: [
              if (i > 0)
                const Divider(height: 24, color: line),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      title.isNotEmpty ? title[0].toUpperCase() : '•',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
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
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$cat · ${_fmtDate(_parseDate(inv['createdAt']))}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: muted),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${LanguageService.tr('Expected', 'প্রত্যাশিত')} +${_fmtRange(amt * minReturnRate, amt * maxReturnRate)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: goldDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _fmtBdt(amt),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.withAlpha(25),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _statusText(st),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: c,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}