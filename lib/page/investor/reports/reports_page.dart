import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> with SingleTickerProviderStateMixin {
  // ═════════════════════════════════════════════════════════
  // EXPECTED RETURN — Investments + Portfolio page er sathe ek
  // Project: 16–22%. Group: tier er nijer % (na thakle 16–22%).
  // Shudhu ACTIVE investment er upor.
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
  static const Color terracottaSoft = Color(0xFFF7E6DF);
  static const Color plum = Color(0xFF6B3E5E);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);
  static const Color danger = Color(0xFFB4413A);
  static const Color dangerSoft = Color(0xFFFBEAE8);

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

  late final TabController _tabController;

  bool _isLoading = true;
  bool _needsLogin = false;
  bool _loadFailed = false;
  bool _exporting = false;

  /// Project + group ek list e
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _distributions = [];

  double _totalInvested = 0; // ACTIVE + MATURED + COMPLETED
  double _projectInvested = 0;
  double _groupInvested = 0;
  double _activeCapital = 0;
  double _expectedMin = 0;
  double _expectedMax = 0;
  double _returnsReceived = 0;
  bool _returnsFromDistributions = true;

  double _paidApproved = 0;
  double _underReview = 0;
  int _underReviewCount = 0;

  double _distGross = 0;
  double _distFees = 0;
  double _distNet = 0;

  final Map<String, double> _allocation = {};
  final Map<String, int> _statusCounts = {};

  String _typeFilter = 'ALL'; // ALL, PROJECT, GROUP

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadReportsData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  /// DB er timestamp e timezone thake na (UTC) — tai 'Z' jog kore local e ani
  DateTime? _parseDate(dynamic s) {
    final raw = s?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    var t = raw.replaceFirst(' ', 'T');
    if (t.contains('T') && !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(t)) t = '${t}Z';
    return DateTime.tryParse(t)?.toLocal();
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _fmtDateTime(DateTime? d) {
    if (d == null) return '—';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${_fmtDate(d)} · $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  String _trim(double v, int digits) {
    final s = v.toStringAsFixed(digits);
    return s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
  }

  String _fmtBdt(double amount) {
    final neg = amount < 0;
    final a = amount.abs();
    String s;
    if (a >= 10000000) {
      s = '৳${_trim(a / 10000000, 2)} Cr';
    } else if (a >= 100000) {
      s = '৳${_trim(a / 100000, 2)}L';
    } else if (a >= 1000) {
      s = '৳${_trim(a / 1000, 1)}K';
    } else {
      s = '৳${a.toStringAsFixed(0)}';
    }
    return neg ? '-$s' : s;
  }

  String _fmtRange(double min, double max) =>
      min == max ? _fmtBdt(min) : '${_fmtBdt(min)} – ${_fmtBdt(max)}';

  String _pctLabel(double min, double max) {
    String p(double r) {
      final v = r * 100;
      return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    }

    return min == max ? '${p(min)}%' : '${p(min)}–${p(max)}%';
  }

  bool _countsAsInvested(String s) => s == 'ACTIVE' || s == 'MATURED' || s == 'COMPLETED';

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

  /// Lenden er status: DONE / REVIEW / FAILED
  String _txState(String s) {
    switch (s) {
      case 'APPROVED':
      case 'COMPLETED':
      case 'SUCCESS':
      case 'PAID':
      case 'VERIFIED':
        return 'DONE';
      case 'REJECTED':
      case 'FAILED':
      case 'CANCELLED':
      case 'DECLINED':
        return 'FAILED';
      default:
        return 'REVIEW';
    }
  }

  String _txStatusText(String s) {
    switch (s) {
      case 'SUBMITTED':
        return LanguageService.tr('Under review', 'যাচাই চলছে');
      case 'APPROVED':
        return LanguageService.tr('Approved', 'অনুমোদিত');
      case 'REJECTED':
        return LanguageService.tr('Rejected', 'বাতিল');
      case 'COMPLETED':
        return LanguageService.tr('Completed', 'সম্পন্ন');
      case 'PENDING':
        return LanguageService.tr('Pending', 'অপেক্ষমান');
      case 'PROCESSING':
        return LanguageService.tr('Processing', 'প্রক্রিয়াধীন');
      case 'FAILED':
        return LanguageService.tr('Failed', 'ব্যর্থ');
      case 'CANCELLED':
        return LanguageService.tr('Cancelled', 'বাতিল');
      default:
        if (s.isEmpty) return '—';
        final w = s.replaceAll('_', ' ').toLowerCase();
        return w[0].toUpperCase() + w.substring(1);
    }
  }

  Color _txColor(String state) =>
      state == 'DONE' ? emerald : (state == 'FAILED' ? danger : goldDeep);

  String _txTypeText(String t) {
    switch (t) {
      case 'PROJECT_PAYMENT':
        return LanguageService.tr('Project payment', 'প্রজেক্ট পেমেন্ট');
      case 'GROUP_PAYMENT':
        return LanguageService.tr('Group payment', 'গ্রুপ পেমেন্ট');
      case 'WALLET_IN':
        return LanguageService.tr('Wallet deposit', 'ওয়ালেট জমা');
      case 'WALLET_OUT':
        return LanguageService.tr('Wallet payment', 'ওয়ালেট পেমেন্ট');
      case 'WITHDRAWAL':
        return LanguageService.tr('Withdrawal', 'উত্তোলন');
      default:
        return t;
    }
  }

  IconData _txIcon(String t) {
    switch (t) {
      case 'PROJECT_PAYMENT':
        return Icons.work_outline_rounded;
      case 'GROUP_PAYMENT':
        return Icons.groups_2_outlined;
      case 'WALLET_IN':
        return Icons.south_west_rounded;
      case 'WITHDRAWAL':
        return Icons.account_balance_outlined;
      default:
        return Icons.north_east_rounded;
    }
  }

  // ═════════════════════════════════════════════════════════
  // DATA
  // ═════════════════════════════════════════════════════════
  Map<String, dynamic> _fromProject(Map<String, dynamic> inv) {
    final cat = inv['category']?.toString() ?? 'OTHER';
    final catLabel = categoryLabels[cat] ?? cat;
    return {
      'kind': 'PROJECT',
      'title': inv['title']?.toString() ?? '',
      'subtitle': catLabel,
      'allocationKey': catLabel,
      'amount': _num(inv['amountBdt']),
      'status': inv['status']?.toString() ?? '',
      'createdAt': _parseDate(inv['createdAt']),
      // Project er nijer range (DB), na thakle 16–22%
      'rMin': _num(inv['returnMin']) > 0 ? _num(inv['returnMin']) : minReturnRate,
      'rMax': _num(inv['returnMax']) > 0 ? _num(inv['returnMax']) : maxReturnRate,
      'received': _num(inv['actualReturnBdt']),
    };
  }

  Map<String, dynamic> _fromGroup(Map<String, dynamic> g) {
    final group = g['groupName']?.toString() ?? '';
    final entity = g['entityName']?.toString() ?? '';
    final tierPct = _num(g['expectedReturnPct']);
    final showEntity = entity.isNotEmpty && entity.toLowerCase() != group.toLowerCase();
    return {
      'kind': 'GROUP',
      'title': showEntity ? '$group — $entity' : group,
      'subtitle': g['tierName']?.toString() ?? '',
      'allocationKey': '$group (${LanguageService.tr('Group', 'গ্রুপ')})',
      'amount': _num(g['amountBdt']),
      'status': g['status']?.toString() ?? '',
      'createdAt': _parseDate(g['createdAt']),
      'rMin': tierPct > 0 ? tierPct : minReturnRate,
      'rMax': tierPct > 0 ? tierPct : maxReturnRate,
      'received': 0.0,
    };
  }

  Future<void> _loadReportsData() async {
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

    final data = await DatabaseService.getReportsData(userId);

    if (data['ok'] != true) {
      if (mounted) {
        setState(() {
          _loadFailed = true;
          _isLoading = false;
        });
      }
      return;
    }

    List<Map<String, dynamic>> listOf(String k) => ((data[k] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final items = <Map<String, dynamic>>[
      ...listOf('projects').map(_fromProject),
      ...listOf('groups').map(_fromGroup),
    ]..sort((a, b) {
      final da = a['createdAt'] as DateTime?;
      final db = b['createdAt'] as DateTime?;
      if (da == null || db == null) return 0;
      return db.compareTo(da);
    });

    final transactions = listOf('transactions');
    final distributions = listOf('distributions');

    // ─── Investment er hisab ───
    double invested = 0, projectInv = 0, groupInv = 0, active = 0, expMin = 0, expMax = 0;
    double actualReturnSum = 0;
    final alloc = <String, double>{};
    final counts = <String, int>{};

    for (final it in items) {
      final st = it['status'] as String;
      final amt = it['amount'] as double;
      final b = _bucket(st);
      counts[b] = (counts[b] ?? 0) + 1;
      actualReturnSum += it['received'] as double;

      if (_countsAsInvested(st)) {
        invested += amt;
        if (it['kind'] == 'PROJECT') {
          projectInv += amt;
        } else {
          groupInv += amt;
        }
        final key = it['allocationKey'] as String;
        alloc[key] = (alloc[key] ?? 0) + amt;
      }
      if (st == 'ACTIVE') {
        active += amt;
        expMin += amt * (it['rMin'] as double);
        expMax += amt * (it['rMax'] as double);
      }
    }

    // ─── Distribution ───
    double gross = 0, fees = 0, net = 0;
    for (final d in distributions) {
      gross += _num(d['grossAmountBdt']);
      fees += _num(d['feeBdt']);
      net += _num(d['netAmountBdt']);
    }

    // Returns: distribution table e thakle sheta (dashboard o eta dekhay),
    // na thakle investment e lekha actualReturnBdt
    final fromDist = distributions.isNotEmpty;

    // ─── Lenden ───
    double paid = 0, review = 0;
    int reviewCount = 0;
    for (final t in transactions) {
      final type = t['type'] as String;
      if (type != 'PROJECT_PAYMENT' && type != 'GROUP_PAYMENT') continue;
      final state = _txState(t['status']?.toString() ?? '');
      final amt = _num(t['amountBdt']);
      if (state == 'DONE') paid += amt;
      if (state == 'REVIEW') {
        review += amt;
        reviewCount++;
      }
    }

    final sortedAlloc = alloc.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    if (!mounted) return;
    setState(() {
      _items = items;
      _transactions = transactions;
      _distributions = distributions;

      _totalInvested = invested;
      _projectInvested = projectInv;
      _groupInvested = groupInv;
      _activeCapital = active;
      _expectedMin = expMin;
      _expectedMax = expMax;
      _returnsFromDistributions = fromDist;
      _returnsReceived = fromDist ? net : actualReturnSum;

      _paidApproved = paid;
      _underReview = review;
      _underReviewCount = reviewCount;

      _distGross = gross;
      _distFees = fees;
      _distNet = net;

      _allocation
        ..clear()
        ..addEntries(sortedAlloc);
      _statusCounts
        ..clear()
        ..addAll(counts);

      _needsLogin = false;
      _loadFailed = false;
      _isLoading = false;
    });
  }

  // ═════════════════════════════════════════════════════════
  // EXPORT — ashol CSV file, Excel / Google Sheets e khule
  // ═════════════════════════════════════════════════════════
  String _csv(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  String _iso(DateTime? d) {
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String _buildCsv() {
    final b = StringBuffer();
    void row(List<dynamic> cells) => b.writeln(cells.map(_csv).join(','));

    row(['Biniyog Club — Investor Report']);
    row(['Generated', _iso(DateTime.now())]);
    b.writeln();

    row(['SUMMARY']);
    row(['Total invested (BDT)', _totalInvested.toStringAsFixed(2)]);
    row(['Project invested (BDT)', _projectInvested.toStringAsFixed(2)]);
    row(['Group invested (BDT)', _groupInvested.toStringAsFixed(2)]);
    row(['Active capital (BDT)', _activeCapital.toStringAsFixed(2)]);
    row(['Returns received (BDT)', _returnsReceived.toStringAsFixed(2)]);
    row([
      'Expected return on active (BDT, estimate)',
      '${_expectedMin.toStringAsFixed(2)} - ${_expectedMax.toStringAsFixed(2)}'
    ]);
    b.writeln();

    row(['INVESTMENTS']);
    row(['Date', 'Type', 'Name', 'Category / Tier', 'Amount (BDT)', 'Status', 'Return received (BDT)']);
    for (final it in _items) {
      row([
        _iso(it['createdAt'] as DateTime?),
        it['kind'] == 'PROJECT' ? 'Project' : 'Group',
        it['title'],
        it['subtitle'],
        (it['amount'] as double).toStringAsFixed(2),
        it['status'],
        (it['received'] as double).toStringAsFixed(2),
      ]);
    }
    b.writeln();

    row(['TRANSACTIONS']);
    row(['Date', 'Type', 'Details', 'Amount (BDT)', 'Fee (BDT)', 'Status', 'Reference']);
    for (final t in _transactions) {
      row([
        _iso(_parseDate(t['createdAt'])),
        t['type'],
        t['title'],
        _num(t['amountBdt']).toStringAsFixed(2),
        _num(t['feeBdt']).toStringAsFixed(2),
        t['status'],
        t['reference'],
      ]);
    }
    b.writeln();

    row(['PROFIT DISTRIBUTIONS']);
    row(['Date', 'Project', 'Gross (BDT)', 'Fee (BDT)', 'Net (BDT)']);
    for (final d in _distributions) {
      row([
        _iso(_parseDate(d['date'])),
        d['projectTitle'],
        _num(d['grossAmountBdt']).toStringAsFixed(2),
        _num(d['feeBdt']).toStringAsFixed(2),
        _num(d['netAmountBdt']).toStringAsFixed(2),
      ]);
    }
    return b.toString();
  }

  Future<void> _exportCsv() async {
    if (_exporting || _isLoading || _loadFailed || _needsLogin) return;
    setState(() => _exporting = true);

    try {
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final file = File('${dir.path}/biniyog_report_$stamp.csv');
      // BOM dile Excel e ৳ ar Bangla thik moto dekhay
      await file.writeAsString('﻿${_buildCsv()}', flush: true);

      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Biniyog Club Report',
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LanguageService.tr('Could not export the report. Please try again.',
              'রিপোর্ট এক্সপোর্ট করা যায়নি। আবার চেষ্টা করুন।')),
          backgroundColor: danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
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
        final ready = !_isLoading && !_needsLogin && !_loadFailed;

        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              LanguageService.tr('Reports', 'রিপোর্টস'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 18),
            ),
            actions: [
              if (ready)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: OutlinedButton.icon(
                    onPressed: _exporting ? null : _exportCsv,
                    icon: _exporting
                        ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2, color: emerald),
                    )
                        : const Icon(Icons.ios_share_rounded, size: 15),
                    label: Text(LanguageService.tr('Export CSV', 'CSV এক্সপোর্ট')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: emerald,
                      side: const BorderSide(color: gold),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
            ],
            bottom: ready
                ? TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: emerald,
              unselectedLabelColor: muted,
              indicatorColor: gold,
              indicatorWeight: 3,
              dividerColor: line,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: [
                Tab(text: LanguageService.tr('Overview', 'সারসংক্ষেপ')),
                Tab(text: LanguageService.tr('Investments', 'বিনিয়োগ')),
                Tab(text: LanguageService.tr('Transactions', 'লেনদেন')),
                Tab(text: LanguageService.tr('Returns', 'রিটার্ন')),
              ],
            )
                : null,
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
            LanguageService.tr('Please log in to see your reports', 'রিপোর্ট দেখতে লগইন করুন'),
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
            LanguageService.tr('Could not load your reports', 'রিপোর্ট লোড করা যায়নি'),
            LanguageService.tr(
                'Please check your internet connection.', 'ইন্টারনেট সংযোগ চেক করুন।'),
            LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
            _loadReportsData,
          )
              : TabBarView(
            controller: _tabController,
            children: [
              _tabShell([
                _buildHeroCard(),
                const SizedBox(height: 12),
                _buildOverviewKpis(),
                const SizedBox(height: 18),
                _buildAllocationCard(),
                const SizedBox(height: 16),
                _buildStatusCard(),
                const SizedBox(height: 14),
                _disclaimer(),
              ]),
              _tabShell(_buildInvestmentsTab()),
              _tabShell(_buildTransactionsTab()),
              _tabShell(_buildReturnsTab()),
            ],
          ),
        );
      },
    );
  }

  Widget _tabShell(List<Widget> children) {
    return RefreshIndicator(
      onRefresh: _loadReportsData,
      color: emerald,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: children,
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // 1. OVERVIEW
  // ═════════════════════════════════════════════════════════
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
                  Text(
                    LanguageService.tr('TOTAL INVESTED', 'মোট বিনিয়োগ'),
                    style: const TextStyle(
                      color: goldLight,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _fmtBdt(_totalInvested),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _heroSplit(
                            LanguageService.tr('Projects', 'প্রজেক্ট'), _fmtBdt(_projectInvested)),
                      ),
                      Container(width: 0.8, height: 30, color: gold.withAlpha(90)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _heroSplit(
                            LanguageService.tr('Groups', 'গ্রুপ'), _fmtBdt(_groupInvested)),
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

  Widget _heroSplit(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildOverviewKpis() {
    final roi = _totalInvested > 0 ? (_returnsReceived / _totalInvested) * 100 : 0.0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                LanguageService.tr('Active Capital', 'চলমান মূলধন'),
                _fmtBdt(_activeCapital),
                LanguageService.tr('currently working', 'এখন বিনিয়োগে আছে'),
                Icons.trending_up_rounded,
                emerald,
                emeraldSoft,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _kpiCard(
                LanguageService.tr('Returns Received', 'প্রাপ্ত রিটার্ন'),
                _fmtBdt(_returnsReceived),
                _returnsFromDistributions
                    ? LanguageService.tr('net of fees', 'ফি বাদে')
                    : LanguageService.tr('recorded returns', 'রেকর্ডকৃত রিটার্ন'),
                Icons.payments_outlined,
                goldDeep,
                goldSoft,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                LanguageService.tr('ROI so far', 'এখন পর্যন্ত ROI'),
                '${roi.toStringAsFixed(2)}%',
                LanguageService.tr('received ÷ invested', 'প্রাপ্ত ÷ বিনিয়োগ'),
                Icons.percent_rounded,
                lapis,
                lapisSoft,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _kpiCard(
                LanguageService.tr('Expected Return', 'প্রত্যাশিত লাভ'),
                _activeCapital > 0 ? _fmtRange(_expectedMin, _expectedMax) : _fmtBdt(0),
                LanguageService.tr('on active only', 'শুধু চলমানের উপর'),
                Icons.auto_graph_rounded,
                turquoise,
                turquoiseSoft,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAllocationCard() {
    return _card(
      title: LanguageService.tr('Allocation by Category', 'ক্যাটাগরি ভিত্তিক বণ্টন'),
      subtitle: LanguageService.tr(
          'Only money that is invested (active + completed)', 'শুধু বিনিয়োগকৃত টাকা (চলমান + সম্পন্ন)'),
      child: _allocation.isEmpty || _totalInvested <= 0
          ? _emptyText(LanguageService.tr('No invested money yet.', 'এখনো কোনো বিনিয়োগ নেই।'))
          : Column(
        children: [
          for (int i = 0; i < _allocation.length; i++)
            _allocationRow(
              _allocation.keys.elementAt(i),
              _allocation.values.elementAt(i),
              _chartColors[i % _chartColors.length],
            ),
        ],
      ),
    );
  }

  Widget _allocationRow(String label, double value, Color color) {
    final pct = value / _totalInvested;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ink),
                ),
              ),
              Text(
                '${_fmtBdt(value)} · ${(pct * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: line,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    const order = ['ACTIVE', 'AWAITING', 'COMPLETED', 'CANCELLED'];
    final present = order.where((b) => (_statusCounts[b] ?? 0) > 0).toList();

    return _card(
      title: LanguageService.tr('Investments by Status', 'স্ট্যাটাস অনুসারে বিনিয়োগ'),
      child: present.isEmpty
          ? _emptyText(LanguageService.tr('No investments yet.', 'এখনো কোনো বিনিয়োগ নেই।'))
          : Wrap(
        spacing: 8,
        runSpacing: 8,
        children: present.map((b) {
          final c = _bucketColor(b);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.withAlpha(60)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _bucketText(b),
                  style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_statusCounts[b]}',
                  style: TextStyle(fontSize: 13, color: c, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _disclaimer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        LanguageService.tr(
          'Expected return is an estimate, not guaranteed. Project: its own range, group: tier rate.',
          'প্রত্যাশিত লাভ একটি আনুমানিক হিসাব, নিশ্চিত নয়। প্রজেক্ট: নিজস্ব হার, গ্রুপ: টিয়ারের হার।',
        ),
        style: const TextStyle(fontSize: 11, color: muted, height: 1.4),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // 2. INVESTMENTS
  // ═════════════════════════════════════════════════════════
  List<Widget> _buildInvestmentsTab() {
    final list = _items.where((i) => _typeFilter == 'ALL' || i['kind'] == _typeFilter).toList();

    return [
      Row(
        children: [
          _filterChip('ALL', LanguageService.tr('All', 'সব')),
          const SizedBox(width: 8),
          _filterChip('PROJECT', LanguageService.tr('Project', 'প্রজেক্ট')),
          const SizedBox(width: 8),
          _filterChip('GROUP', LanguageService.tr('Group', 'গ্রুপ')),
          const Spacer(),
          Text(
            LanguageService.tr('${list.length} items', '${list.length} টি'),
            style: const TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
      const SizedBox(height: 14),
      if (list.isEmpty)
        _card(
          title: LanguageService.tr('Investment History', 'বিনিয়োগের ইতিহাস'),
          child: _emptyText(LanguageService.tr('No investments found.', 'কোনো বিনিয়োগ পাওয়া যায়নি।')),
        )
      else
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: line),
          ),
          child: Column(
            children: [
              for (int i = 0; i < list.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: line, indent: 16, endIndent: 16),
                _investmentRow(list[i]),
              ],
            ],
          ),
        ),
    ];
  }

  Widget _filterChip(String value, String label) {
    final selected = _typeFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _typeFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? emerald : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? emerald : line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : ink,
          ),
        ),
      ),
    );
  }

  Widget _investmentRow(Map<String, dynamic> it) {
    final st = it['status'] as String;
    final b = _bucket(st);
    final c = _bucketColor(b);
    final amt = it['amount'] as double;
    final isProject = it['kind'] == 'PROJECT';
    final received = it['received'] as double;
    final subtitle = it['subtitle'] as String;

    // Status onujayi shudhu ja shotti, tai dekhabo
    String? footLabel;
    String? footValue;
    Color footColor = emerald;
    if (b == 'ACTIVE') {
      footLabel = LanguageService.tr('Expected return (${_pctLabel(it['rMin'], it['rMax'])})',
          'প্রত্যাশিত লাভ (${_pctLabel(it['rMin'], it['rMax'])})');
      footValue = _fmtRange(amt * (it['rMin'] as double), amt * (it['rMax'] as double));
    } else if (b == 'COMPLETED' && received > 0) {
      footLabel = LanguageService.tr('Return received', 'প্রাপ্ত রিটার্ন');
      footValue = _fmtBdt(received);
      footColor = lapis;
    } else if (b == 'AWAITING') {
      footLabel = LanguageService.tr(
          'Starts after payment is approved', 'পেমেন্ট অনুমোদনের পর শুরু হবে');
      footColor = goldDeep;
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isProject ? emeraldSoft : goldSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  isProject ? Icons.work_outline_rounded : Icons.groups_2_outlined,
                  size: 18,
                  color: isProject ? emerald : goldDeep,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (it['title'] as String).isEmpty ? '—' : it['title'] as String,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        isProject
                            ? LanguageService.tr('Project', 'প্রজেক্ট')
                            : LanguageService.tr('Group', 'গ্রুপ'),
                        if (subtitle.isNotEmpty) subtitle,
                        _fmtDate(it['createdAt'] as DateTime?),
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmtBdt(amt),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ink),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.withAlpha(22),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _bucketText(b),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (footLabel != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: footColor.withAlpha(14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      footLabel,
                      style: TextStyle(fontSize: 11.5, color: footColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (footValue != null)
                    Text(
                      footValue,
                      style: TextStyle(fontSize: 12.5, color: footColor, fontWeight: FontWeight.w800),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // 3. TRANSACTIONS
  // ═════════════════════════════════════════════════════════
  List<Widget> _buildTransactionsTab() {
    return [
      Row(
        children: [
          Expanded(
            child: _kpiCard(
              LanguageService.tr('Paid & Approved', 'পরিশোধিত ও অনুমোদিত'),
              _fmtBdt(_paidApproved),
              LanguageService.tr('investment payments', 'বিনিয়োগ পেমেন্ট'),
              Icons.verified_outlined,
              emerald,
              emeraldSoft,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _kpiCard(
              LanguageService.tr('Under Review', 'যাচাই চলছে'),
              _fmtBdt(_underReview),
              LanguageService.tr('$_underReviewCount payment(s)', '$_underReviewCount টি পেমেন্ট'),
              Icons.hourglass_top_rounded,
              goldDeep,
              goldSoft,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _card(
        title: LanguageService.tr('All Transactions', 'সব লেনদেন'),
        subtitle: LanguageService.tr(
            '${_transactions.length} records', 'মোট ${_transactions.length} টি'),
        child: _transactions.isEmpty
            ? _emptyText(LanguageService.tr('No transactions yet.', 'এখনো কোনো লেনদেন নেই।'))
            : Column(
          children: [
            for (int i = 0; i < _transactions.length; i++) ...[
              if (i > 0) const Divider(height: 22, color: line),
              _transactionRow(_transactions[i]),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _transactionRow(Map<String, dynamic> t) {
    final type = t['type']?.toString() ?? '';
    final status = t['status']?.toString() ?? '';
    final state = _txState(status);
    final c = _txColor(state);
    final title = t['title']?.toString() ?? '';
    final ref = t['reference']?.toString() ?? '';
    final note = t['note']?.toString() ?? '';
    final fee = _num(t['feeBdt']);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: c.withAlpha(22), borderRadius: BorderRadius.circular(10)),
          child: Icon(_txIcon(type), size: 17, color: c),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _txTypeText(type),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink),
              ),
              if (title.isNotEmpty)
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: ink),
                ),
              const SizedBox(height: 2),
              Text(
                _fmtDateTime(_parseDate(t['createdAt'])),
                style: const TextStyle(fontSize: 10.5, color: muted),
              ),
              if (ref.isNotEmpty)
                SelectableText(
                  'Ref: $ref',
                  style: const TextStyle(fontSize: 10.5, color: muted),
                ),
              if (state == 'FAILED' && note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    note,
                    style: const TextStyle(fontSize: 11, color: danger),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _fmtBdt(_num(t['amountBdt'])),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: state == 'FAILED' ? muted : ink,
                decoration: state == 'FAILED' ? TextDecoration.lineThrough : null,
              ),
            ),
            if (fee > 0)
              Text(
                LanguageService.tr('Fee ${_fmtBdt(fee)}', 'ফি ${_fmtBdt(fee)}'),
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: c.withAlpha(22), borderRadius: BorderRadius.circular(8)),
              child: Text(
                _txStatusText(status),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════
  // 4. RETURNS (profit distribution)
  // ═════════════════════════════════════════════════════════
  List<Widget> _buildReturnsTab() {
    return [
      Row(
        children: [
          Expanded(
            child: _kpiCard(
              LanguageService.tr('Gross', 'মোট'),
              _fmtBdt(_distGross),
              LanguageService.tr('before fees', 'ফি এর আগে'),
              Icons.account_balance_wallet_outlined,
              lapis,
              lapisSoft,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _kpiCard(
              LanguageService.tr('Fees', 'ফি'),
              _fmtBdt(_distFees),
              LanguageService.tr('deducted', 'কাটা হয়েছে'),
              Icons.receipt_outlined,
              terracotta,
              terracottaSoft,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _kpiCard(
              LanguageService.tr('Net', 'নিট'),
              _fmtBdt(_distNet),
              LanguageService.tr('to you', 'আপনার প্রাপ্য'),
              Icons.savings_outlined,
              emerald,
              emeraldSoft,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _card(
        title: LanguageService.tr('Profit Distributions', 'লাভ বণ্টন'),
        subtitle: LanguageService.tr(
            'Profit paid out on your project investments', 'আপনার প্রজেক্ট বিনিয়োগে দেওয়া লাভ'),
        child: _distributions.isEmpty
            ? _emptyText(LanguageService.tr(
            'No profit has been distributed yet.\nIt will show here once a project pays out.',
            'এখনো কোনো লাভ বণ্টন হয়নি।\nপ্রজেক্ট লাভ দিলে এখানে দেখাবে।'))
            : Column(
          children: [
            for (int i = 0; i < _distributions.length; i++) ...[
              if (i > 0) const Divider(height: 22, color: line),
              _distributionRow(_distributions[i]),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _distributionRow(Map<String, dynamic> d) {
    final title = d['projectTitle']?.toString() ?? '';
    final fee = _num(d['feeBdt']);
    final gross = _num(d['grossAmountBdt']);
    final status = d['status']?.toString() ?? '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: emeraldSoft, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.savings_outlined, size: 17, color: emerald),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.isEmpty ? '—' : title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink),
              ),
              const SizedBox(height: 2),
              Text(
                _fmtDate(_parseDate(d['date'])),
                style: const TextStyle(fontSize: 10.5, color: muted),
              ),
              if (fee > 0)
                Text(
                  LanguageService.tr('Gross ${_fmtBdt(gross)} · Fee ${_fmtBdt(fee)}',
                      'মোট ${_fmtBdt(gross)} · ফি ${_fmtBdt(fee)}'),
                  style: const TextStyle(fontSize: 10.5, color: muted),
                ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '+${_fmtBdt(_num(d['netAmountBdt']))}',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: emerald),
            ),
            if (status.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _txStatusText(status),
                style: TextStyle(fontSize: 10, color: _txColor(_txState(status))),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═════════════════════════════════════════════════════════
  Widget _kpiCard(String label, String value, String sub, IconData icon, Color color, Color soft) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
          const SizedBox(height: 10),
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
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: color.withAlpha(170)),
          ),
        ],
      ),
    );
  }

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
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12.5, color: muted, height: 1.4),
      ),
    ),
  );

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