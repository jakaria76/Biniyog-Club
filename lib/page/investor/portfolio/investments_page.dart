import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import '../../../services/pdf_service.dart';
import '../../authentication/login_page.dart';
import '../documents/documents_page.dart'; // PdfViewerScreen
import '../groups/group_invest_page.dart';
import '../projects/project_invest_page.dart';
import '../../../theme/app_colors.dart';

class InvestmentsPage extends StatefulWidget {
  /// 'ALL', 'PROJECT' ba 'GROUP' — dashboard theke direct kono tab e khola jabe
  final String initialType;

  const InvestmentsPage({super.key, this.initialType = 'ALL'});

  @override
  State<InvestmentsPage> createState() => _InvestmentsPageState();
}

class _InvestmentsPageState extends State<InvestmentsPage> {
  bool _isLoading = true;
  bool _needsLogin = false;
  bool _loadFailed = false;

  /// Project + group investment ek list e (kind = 'PROJECT' / 'GROUP')
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _platformBanks = [];

  double _projectInvested = 0.0;
  double _groupInvested = 0.0;
  double _projectPending = 0.0;
  double _groupPending = 0.0;
  int _projectActiveCount = 0;
  int _groupActiveCount = 0;
  double _totalActual = 0.0;
  double _expectedMin = 0.0;
  double _expectedMax = 0.0;

  /// Shob active investment er rate ek hole sheta, na hole null
  String? _totalRateLabel;

  String _typeFilter = 'ALL'; // ALL / PROJECT / GROUP
  String _statusFilter = 'ALL'; // ALL / ACTIVE / PENDING / COMPLETED / CANCELLED

  // ─── Palette — website er rong (lib/theme/app_colors.dart) ───
  static const Color emerald = BC.primary;
  static const Color emeraldDeep = BC.brand800;
  static const Color emeraldBright = BC.brand500;
  static const Color emeraldSoft = BC.secondary;
  // Sonali nei — "baki / opekkhay" er jonno chart-4 (website er rong)
  static const Color pendingTone = BC.chart4Deep;
  static const Color pendingBar = BC.chart4;
  static const Color turquoise = BC.chart4;
  static const Color turquoiseSoft = BC.chart4Muted;
  static const Color lapis = BC.finance600;
  static const Color lapisSoft = BC.finance50;
  static const Color terracotta = BC.destructive;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color danger = BC.destructive;

  /// Website er ProjectCategory
  static const Map<String, String> categoryLabels = {
    'REAL_ESTATE': 'Real Estate',
    'TRADE_FINANCE': 'Trade Finance',
    'SME': 'SME',
    'TECHNOLOGY': 'Technology',
    'INFRASTRUCTURE': 'Infrastructure',
    'FMCG': 'FMCG',
    'FOOD_AGRO': 'Food & Agro',
    'PRINTING_PACKAGING': 'Printing & Packaging',
    'COMMUNITY': 'Community',
    'OTHER': 'Other',
  };

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.initialType;
    _loadInvestmentsData();
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  DateTime? _parseDate(dynamic s) {
    if (s == null) return null;
    return DateTime.tryParse(s.toString())?.toLocal();
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  /// 0.15, 0.15 → "15%"   |   0.16, 0.22 → "16–22%"
  String _pctLabel(double min, double max) {
    String p(double r) {
      final v = r * 100;
      return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    }

    return min == max ? '${p(min)}%' : '${p(min)}–${p(max)}%';
  }

  String _fmtBdt(double amount) {
    return '৳${amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
    )}';
  }

  String _fmtRange(double min, double max) =>
      min == max ? _fmtBdt(min) : '${_fmtBdt(min)} – ${_fmtBdt(max)}';

  bool _countsAsInvested(String status) => status == 'ACTIVE' || status == 'MATURED' || status == 'COMPLETED';

  bool _isAwaiting(String status) => status == 'PENDING' || status == 'PAYMENT_PENDING';

  // ═════════════════════════════════════════════════════════
  // NORMALIZE — project ar group ke ek-i shape e ana
  // ═════════════════════════════════════════════════════════
  Map<String, dynamic> _fromProject(Map<String, dynamic> inv) {
    final durationDays = _num(inv['durationDays']).toInt();
    final start = _parseDate(inv['activatedAt']) ?? _parseDate(inv['createdAt']);
    final goal = _num(inv['fundingGoalBdt']);
    final funded = _num(inv['fundedAmountBdt']);

    return {
      'kind': 'PROJECT',
      'id': inv['id'].toString(),
      'title': inv['title']?.toString() ?? '',
      'category': inv['category']?.toString() ?? 'OTHER',
      'location': inv['location']?.toString() ?? '',
      'amount': _num(inv['amountBdt']),
      'status': inv['status']?.toString() ?? 'PENDING',
      'createdAt': _parseDate(inv['createdAt']),
      'start': start,
      'maturity': (start == null || durationDays <= 0) ? null : start.add(Duration(days: durationDays)),
      'durationDays': durationDays,
      'received': _num(inv['actualReturnBdt']),
      // Project er nijer range (DB). Na thakle 0 — "expected" dekhai na
      'returnMin': _num(inv['returnMin']),
      'returnMax': _num(inv['returnMax']),
      'progress': goal > 0 ? (funded / goal).clamp(0.0, 1.0).toDouble() : 0.0,
      // Shudhu website er asol receipt number — banano number na
      'receipt': inv['receiptNumber']?.toString() ?? '',
      'latestSubmission': inv['latestSubmission'],
      'paymentPlan': inv['paymentPlan']?.toString() ?? 'FULL',
      'paidApproved': _num(inv['paidApproved']),
      'paidPending': _num(inv['paidPending']),
      'bankAccounts': ((inv['bankAccounts'] as List?) ?? []).map((b) => Map<String, dynamic>.from(b as Map)).toList(),
      'websiteCertificate': inv['websiteCertificate'],
    };
  }

  Map<String, dynamic> _fromGroup(Map<String, dynamic> g) {
    final months = _num(g['durationMonths']).toInt();
    final start = _parseDate(g['createdAt']);
    final maturity = (start == null || months <= 0) ? null : DateTime(start.year, start.month + months, start.day);
    final groupName = g['groupName']?.toString() ?? '';
    final entityName = g['entityName']?.toString() ?? '';
    final bank = g['bank'] as Map<String, dynamic>?;
    final plot = g['plotNumber']?.toString() ?? '';
    // Tier er nijer return % — na thakle 0, expected dekhano hoy na
    final tierPct = _num(g['expectedReturnPct']);
    final showEntity = entityName.isNotEmpty && entityName.trim().toLowerCase() != groupName.trim().toLowerCase();

    return {
      'kind': 'GROUP',
      'id': g['id'].toString(),
      'title': showEntity ? '$groupName — $entityName' : groupName,
      'returnMin': tierPct,
      'returnMax': tierPct,
      'tierName': g['tierName']?.toString() ?? '',
      'plotNumber': (plot.isEmpty || plot == 'N/A') ? null : plot,
      'sharePercentage': _num(g['sharePercentage']),
      'amount': _num(g['amountBdt']),
      'status': g['status']?.toString() ?? 'PENDING',
      'createdAt': start,
      'start': start,
      'maturity': maturity,
      'durationMonths': months,
      'received': 0.0,
      'receipt': g['receiptNumber']?.toString() ?? '',
      'latestSubmission': g['latestSubmission'],
      'paymentPlan': g['paymentPlan']?.toString() ?? 'FULL',
      'paidApproved': _num(g['paidApproved']),
      'paidPending': _num(g['paidPending']),
      'bankAccounts': bank != null ? [bank] : <Map<String, dynamic>>[],
    };
  }

  // ═════════════════════════════════════════════════════════
  // DATA
  // ═════════════════════════════════════════════════════════
  Future<void> _loadInvestmentsData() async {
    if (mounted) setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    final userEmail = userData?['email']?.toString() ?? '';

    // Login chara onner data dekhabo na
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

    // Login ache kintu khali — mane server e pouchate pareni, "kichu nei" na
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
      ...((pData['investments'] as List?) ?? []).map((e) => _fromProject(Map<String, dynamic>.from(e as Map))),
      ...gData.map(_fromGroup),
    ]..sort((a, b) {
      final da = a['createdAt'] as DateTime?;
      final db = b['createdAt'] as DateTime?;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    double pInv = 0, gInv = 0, pPen = 0, gPen = 0, actual = 0, eMin = 0, eMax = 0;
    int pAct = 0, gAct = 0;
    final rateLabels = <String>{};

    for (final i in items) {
      final amt = i['amount'] as double;
      final st = i['status'] as String;
      final isProject = i['kind'] == 'PROJECT';
      final rMin = i['returnMin'] as double;
      final rMax = i['returnMax'] as double;

      if (_countsAsInvested(st)) {
        if (isProject) {
          pInv += amt;
          if (st == 'ACTIVE') pAct++;
        } else {
          gInv += amt;
          if (st == 'ACTIVE') gAct++;
        }
        if (st == 'ACTIVE' && rMax > 0) {
          eMin += amt * rMin;
          eMax += amt * rMax;
          rateLabels.add(_pctLabel(rMin, rMax));
        }
      } else if (_isAwaiting(st)) {
        // Website er motoi: kistir je taka jachai hoye geche sheta-o "invested"
        final approved = i['paidApproved'] as double;
        if (isProject) {
          pInv += approved;
          pPen += amt - approved;
        } else {
          gInv += approved;
          gPen += amt - approved;
        }
      }
      actual += i['received'] as double;
    }

    if (!mounted) return;
    setState(() {
      _needsLogin = false;
      _loadFailed = false;
      _items = items;
      _platformBanks =
          ((pData['bankAccounts'] as List?) ?? []).map((b) => Map<String, dynamic>.from(b as Map)).toList();
      _projectInvested = pInv;
      _groupInvested = gInv;
      _projectPending = pPen;
      _groupPending = gPen;
      _projectActiveCount = pAct;
      _groupActiveCount = gAct;
      _totalActual = actual;
      _expectedMin = eMin;
      _expectedMax = eMax;
      _totalRateLabel = rateLabels.length == 1 ? rateLabels.first : null;
      _isLoading = false;
    });
  }

  // ─── Filters ──────────────────────────────────────────────
  List<Map<String, dynamic>> get _typedItems =>
      _typeFilter == 'ALL' ? _items : _items.where((i) => i['kind'] == _typeFilter).toList();

  bool _matchStatus(String s, String filter) {
    switch (filter) {
      case 'ACTIVE':
        return s == 'ACTIVE';
      case 'PENDING':
        return _isAwaiting(s);
      case 'COMPLETED':
        return s == 'COMPLETED' || s == 'MATURED';
      case 'CANCELLED':
        return s == 'CANCELLED' || s == 'REFUNDED';
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> get _visibleItems =>
      _typedItems.where((i) => _matchStatus(i['status'] as String, _statusFilter)).toList();

  // ═════════════════════════════════════════════════════════
  // CERTIFICATE (project — website er data diye)
  // ═════════════════════════════════════════════════════════
  Future<void> _openWebsiteCertificate(Map<String, dynamic> item) async {
    final cert = item['websiteCertificate'] as Map<String, dynamic>?;
    if (cert == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LanguageService.tr('Your certificate is being prepared. Pull down to refresh in a few minutes.',
              'সার্টিফিকেট তৈরি হচ্ছে। কিছুক্ষণ পর নিচে টেনে রিফ্রেশ করুন।')),
          backgroundColor: emerald,
        ),
      );
      return;
    }
    try {
      final bytes = await PdfService.buildWebsiteCertificate(cert);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            title: LanguageService.tr('Investment Certificate', 'ইনভেস্টমেন্ট সার্টিফিকেট'),
            bytes: bytes,
            fileName: 'Certificate_${cert['certificateNo']}.pdf',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF error: $e'), backgroundColor: danger),
      );
    }
  }

  // ═════════════════════════════════════════════════════════
  // SUBMIT PAYMENT — invest korar page-i, ager investment er jonno
  // ═════════════════════════════════════════════════════════
  Future<void> _openPayment(Map<String, dynamic> item) async {
    final isGroup = item['kind'] == 'GROUP';
    final itemBanks = item['bankAccounts'] as List<Map<String, dynamic>>;
    final banks = itemBanks.isNotEmpty ? itemBanks : _platformBanks;

    final bool? ok;
    if (isGroup) {
      ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => GroupInvestPage(
            existing: {
              'id': item['id'],
              'amountBdt': item['amount'],
              'tierName': item['tierName'],
              'expectedReturnPct': item['returnMin'],
              'durationMonths': item['durationMonths'],
              'bank': itemBanks.isNotEmpty ? itemBanks.first : null,
              'paymentPlan': item['paymentPlan'],
              'paidApproved': item['paidApproved'],
              'paidPending': item['paidPending'],
            },
            groupName: item['title']?.toString() ?? '',
            entityName: '',
          ),
        ),
      );
    } else {
      ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ProjectInvestPage(
            existing: {
              'id': item['id'],
              'title': item['title'],
              'amount': item['amount'],
              'returnMin': item['returnMin'],
              'returnMax': item['returnMax'],
              'bankAccounts': banks,
              'paymentPlan': item['paymentPlan'],
              'paidApproved': item['paidApproved'],
              'paidPending': item['paidPending'],
            },
          ),
        ),
      );
    }

    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LanguageService.tr('Payment submitted. It will be active after admin approval.',
              'পেমেন্ট জমা হয়েছে। অ্যাডমিন অনুমোদনের পর চালু হবে।')),
          backgroundColor: emerald,
        ),
      );
      _loadInvestmentsData();
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
        final projectCount = _items.where((i) => i['kind'] == 'PROJECT').length;
        final groupCount = _items.length - projectCount;
        final visible = _visibleItems;

        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 54,
            iconTheme: const IconThemeData(color: ink),
            // Back button — page push kore khulle pichone jay; dashboard er tab hole
            // dashboard er PopScope dhore Home tab e fire ashe
            leading: IconButton(
              tooltip: LanguageService.tr('Back', 'পিছনে'),
              icon: const Icon(Icons.arrow_back_rounded, color: ink, size: 22),
              onPressed: () => Navigator.maybePop(context),
            ),
            title: Text(
              LanguageService.tr('My Investments', 'আমার বিনিয়োগ'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 17.5),
            ),
          ),
          body: _isLoading
              ? const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4),
            ),
          )
              : _needsLogin
              ? _buildMessage(
            Icons.lock_outline_rounded,
            LanguageService.tr('Please log in to see your investments', 'আপনার বিনিয়োগ দেখতে লগইন করুন'),
            LanguageService.tr('Log in', 'লগইন'),
                () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
            ),
          )
              : _loadFailed
              ? _buildMessage(
            Icons.wifi_off_rounded,
            LanguageService.tr('Could not load your investments', 'বিনিয়োগ লোড করা যায়নি'),
            LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
            _loadInvestmentsData,
          )
              : RefreshIndicator(
            onRefresh: _loadInvestmentsData,
            color: emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              // dashboard er curved navbar er jonno niche jayga
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 104),
              children: [
                _buildSummaryCard(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _splitCard(
                        kind: 'PROJECT',
                        label: LanguageService.tr('Projects', 'প্রজেক্ট'),
                        amount: _projectInvested,
                        activeCount: _projectActiveCount,
                        pending: _projectPending,
                        icon: Icons.trending_up_rounded,
                        color: emerald,
                        soft: emeraldSoft,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _splitCard(
                        kind: 'GROUP',
                        label: LanguageService.tr('Groups', 'গ্রুপ'),
                        amount: _groupInvested,
                        activeCount: _groupActiveCount,
                        pending: _groupPending,
                        icon: Icons.apartment_rounded,
                        color: emerald,
                        soft: emeraldSoft,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildTypeSelector(projectCount, groupCount),
                const SizedBox(height: 8),
                _buildStatusFilterBar(),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  _buildEmptyInvestmentsCard()
                else
                  ...visible.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildInvestmentCard(item),
                  )),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Summary (mot biniyog + return + expected) ────────────
  Widget _buildSummaryCard() {
    final total = _projectInvested + _groupInvested;
    final hasExpected = _expectedMax > 0;

    Widget cell(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(160))),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
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
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        LanguageService.tr('TOTAL INVESTED', 'মোট বিনিয়োগ'),
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white.withAlpha(200), letterSpacing: 1.3),
                      ),
                      const Spacer(),
                      Text(
                        LanguageService.tr('${_items.length} investments', '${_items.length} টি বিনিয়োগ'),
                        style: TextStyle(fontSize: 11.5, color: Colors.white.withAlpha(150)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _fmtBdt(total),
                      style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(height: 1, color: Colors.white.withAlpha(25)),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      cell(LanguageService.tr('Returns received', 'প্রাপ্ত লাভ'), _fmtBdt(_totalActual), Colors.white),
                      const SizedBox(width: 10),
                      cell(
                        _totalRateLabel != null
                            ? LanguageService.tr('Expected ($_totalRateLabel)', 'প্রত্যাশিত ($_totalRateLabel)')
                            : LanguageService.tr('Expected return', 'প্রত্যাশিত লাভ'),
                        hasExpected ? _fmtRange(_expectedMin, _expectedMax) : '—',
                        BC.brand300,
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

  Widget _splitCard({
    required String kind,
    required String label,
    required double amount,
    required int activeCount,
    required double pending,
    required IconData icon,
    required Color color,
    required Color soft,
  }) {
    final bool selected = _typeFilter == kind;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _typeFilter = selected ? 'ALL' : kind),
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? color : line, width: selected ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 15, color: color),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$label · ${LanguageService.tr('$activeCount active', '$activeCount চলমান')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: muted, fontWeight: FontWeight.w600),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(_fmtBdt(amount),
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
                    ),
                    if (pending > 0.5)
                      Text(
                        LanguageService.tr('${_fmtBdt(pending)} to pay', '${_fmtBdt(pending)} বাকি'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: terracotta),
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

  // ─── Type Selector (All / Projects / Groups) ──────────────
  Widget _buildTypeSelector(int projectCount, int groupCount) {
    final types = [
      ('ALL', LanguageService.tr('All', 'সব'), _items.length),
      ('PROJECT', LanguageService.tr('Projects', 'প্রজেক্ট'), projectCount),
      ('GROUP', LanguageService.tr('Groups', 'গ্রুপ'), groupCount),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: line),
      ),
      child: Row(
        children: types.map((t) {
          final bool sel = _typeFilter == t.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _typeFilter = t.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: sel ? const LinearGradient(colors: [emeraldBright, emerald]) : null,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '${t.$2} (${t.$3})',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? Colors.white : ink,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Status Filter Bar ────────────────────────────────────
  Widget _buildStatusFilterBar() {
    final typed = _typedItems;
    int count(String filter) => typed.where((i) => _matchStatus(i['status'] as String, filter)).length;

    final filters = [
      ('ALL', 'All', 'সব'),
      ('ACTIVE', 'Active', 'চলমান'),
      ('PENDING', 'Pending', 'অপেক্ষমান'),
      ('COMPLETED', 'Completed', 'সম্পন্ন'),
      ('CANCELLED', 'Cancelled', 'বাতিল'),
    ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final f = filters[index];
          final bool isSel = _statusFilter == f.$1;
          final int n = count(f.$1);

          return GestureDetector(
            onTap: () => setState(() => _statusFilter = f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSel ? emeraldSoft : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSel ? emerald : line),
              ),
              child: Row(
                children: [
                  Text(
                    LanguageService.tr(f.$2, f.$3),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      color: isSel ? emerald : ink,
                    ),
                  ),
                  if (n > 0) ...[
                    const SizedBox(width: 5),
                    Text(
                      '$n',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: isSel ? emerald : muted),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Status chip (card er upore dane) ─────────────────────
  (String, Color, IconData) _statusInfo({
    required String status,
    required bool awaiting,
    required bool underReview,
    required bool rejected,
    required bool partlyPaid,
  }) {
    if (rejected) return (LanguageService.tr('Rejected', 'বাতিল'), danger, Icons.cancel_rounded);
    if (underReview) return (LanguageService.tr('Under review', 'যাচাই চলছে'), lapis, Icons.hourglass_top_rounded);
    if (awaiting && partlyPaid) return (LanguageService.tr('Partly paid', 'আংশিক পরিশোধ'), pendingTone, Icons.timelapse_rounded);
    if (awaiting) return (LanguageService.tr('Awaiting payment', 'পেমেন্ট বাকি'), pendingTone, Icons.error_outline_rounded);
    if (status == 'ACTIVE') return (LanguageService.tr('Active', 'চলমান'), emeraldBright, Icons.verified_rounded);
    if (status == 'COMPLETED' || status == 'MATURED') {
      return (LanguageService.tr('Completed', 'সম্পন্ন'), lapis, Icons.task_alt_rounded);
    }
    if (status == 'REFUNDED') return (LanguageService.tr('Refunded', 'ফেরত'), muted, Icons.undo_rounded);
    return (LanguageService.tr('Cancelled', 'বাতিল'), danger, Icons.block_rounded);
  }

  // ─── Investment Card ──────────────────────────────────────
  Widget _buildInvestmentCard(Map<String, dynamic> item) {
    final bool isGroup = item['kind'] == 'GROUP';
    final String status = item['status'] as String;
    final Color accent = emerald;
    final Color accentSoft = emeraldSoft;

    final double principal = item['amount'] as double;
    final double rMin = item['returnMin'] as double;
    final double rMax = item['returnMax'] as double;
    final double expMin = principal * rMin;
    final double expMax = principal * rMax;
    final double received = item['received'] as double;
    final String receipt = item['receipt']?.toString() ?? '';

    final DateTime? start = item['start'] as DateTime?;
    final DateTime? maturity = item['maturity'] as DateTime?;
    final int daysLeft = maturity == null ? 0 : maturity.difference(DateTime.now()).inDays.clamp(0, 100000);

    final sub = item['latestSubmission'] as Map<String, dynamic>?;
    final String? subStatus = sub?['status']?.toString();
    final String? rejectionReason = sub?['rejectionReason']?.toString();

    final bool awaiting = _isAwaiting(status);
    final bool activeLike = _countsAsInvested(status);

    // Website er motoi: jachai hoye geche / jachai cholche / baki
    final double paidApproved = (item['paidApproved'] as num?)?.toDouble() ?? 0;
    final double paidPending = (item['paidPending'] as num?)?.toDouble() ?? 0;
    final double outstanding = (principal - paidApproved - paidPending).clamp(0, double.infinity).toDouble();
    final bool installment = item['paymentPlan'] == 'INSTALLMENT';
    final bool canPay = awaiting && outstanding > 0.5;

    final bool rejected = awaiting && subStatus == 'REJECTED' && paidPending <= 0;
    final bool underReview = awaiting && paidPending > 0;
    final bool partlyPaid = awaiting && paidApproved > 0;
    final st = _statusInfo(
      status: status,
      awaiting: awaiting,
      underReview: underReview,
      rejected: rejected,
      partlyPaid: partlyPaid,
    );

    final String subtitle;
    if (isGroup) {
      final plot = item['plotNumber'] as String?;
      subtitle = [
        item['tierName']?.toString() ?? '',
        if (plot != null) '${LanguageService.tr('Plot', 'প্লট')} $plot',
      ].where((s) => s.isNotEmpty).join(' · ');
    } else {
      subtitle = [
        categoryLabels[item['category']] ?? item['category'].toString(),
        item['location']?.toString() ?? '',
      ].where((s) => s.isNotEmpty).join(' · ');
    }

    final int durDays = item['durationDays'] as int? ?? 0;
    final int durMonths = item['durationMonths'] as int? ?? 0;
    final String durationText = isGroup
        ? (durMonths > 0 ? LanguageService.tr('$durMonths months', '$durMonths মাস') : '—')
        : (durDays <= 0
        ? '—'
        : durDays >= 60
        ? LanguageService.tr('${(durDays / 30).round()} months', '${(durDays / 30).round()} মাস')
        : LanguageService.tr('$durDays days', '$durDays দিন'));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: rejected ? danger.withAlpha(120) : line, width: rejected ? 1.3 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: icon + nam + status
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: accentSoft, borderRadius: BorderRadius.circular(10)),
                  child: Icon(isGroup ? Icons.apartment_rounded : Icons.trending_up_rounded, size: 18, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['title']?.toString() ?? '').isEmpty ? '—' : item['title'].toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: ink, height: 1.25),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          isGroup ? LanguageService.tr('Group', 'গ্রুপ') : LanguageService.tr('Project', 'প্রজেক্ট'),
                          if (subtitle.isNotEmpty) subtitle,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: st.$2.withAlpha(24), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(st.$3, size: 13, color: st.$2),
                      const SizedBox(width: 3),
                      Text(st.$1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: st.$2)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Amount strip: mul, expected, mot
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent, emeraldDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _stripCell(LanguageService.tr('Principal', 'মূলধন'), _fmtBdt(principal), Colors.white),
                  _stripDivider(),
                  _stripCell(
                    rMax > 0
                        ? LanguageService.tr('Expected (${_pctLabel(rMin, rMax)})', 'প্রত্যাশিত (${_pctLabel(rMin, rMax)})')
                        : LanguageService.tr('Expected', 'প্রত্যাশিত'),
                    rMax > 0 ? '+${_fmtRange(expMin, expMax)}' : LanguageService.tr('Not set', 'নির্ধারিত নয়'),
                    BC.brand200,
                  ),
                  _stripDivider(),
                  _stripCell(
                    LanguageService.tr('Received', 'প্রাপ্ত'),
                    received > 0 ? _fmtBdt(received) : '—',
                    BC.brand300,
                  ),
                ],
              ),
            ),
          ),

          // ── Payment er obostha (shudhu jokhon kichu bolar ache)
          if (awaiting) ...[
            const SizedBox(height: 8),
            _paymentNote(
              rejected: rejected,
              underReview: underReview,
              partlyPaid: partlyPaid,
              reason: rejectionReason,
              pendingBdt: paidPending,
              leftBdt: outstanding,
            ),
          ],
          if (awaiting && (paidApproved + paidPending > 0 || installment)) ...[
            const SizedBox(height: 8),
            _paymentProgress(
              total: principal,
              approved: paidApproved,
              pending: paidPending,
              left: outstanding,
              installment: installment,
            ),
          ],

          // ── Details: 4 ta choto ghor
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                _detail(LanguageService.tr('Invested', 'বিনিয়োগ'), _fmtDate(item['createdAt'] as DateTime?)),
                _detail(
                  LanguageService.tr('Active from', 'চালু'),
                  activeLike && start != null ? _fmtDate(start) : '—',
                ),
                _detail(LanguageService.tr('Term', 'মেয়াদ'), durationText),
                _detail(
                  LanguageService.tr('Matures', 'মেয়াদ শেষ'),
                  activeLike && maturity != null ? _fmtDate(maturity) : '—',
                  sub: activeLike && maturity != null && status == 'ACTIVE'
                      ? LanguageService.tr('$daysLeft days left', '$daysLeft দিন বাকি')
                      : null,
                ),
              ],
            ),
          ),
          if (isGroup && (item['sharePercentage'] as double) > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _infoLine(Icons.pie_chart_outline_rounded,
                  '${LanguageService.tr('Share', 'শেয়ার')}: ${_shareText(item['sharePercentage'] as double)}'),
            ),
          if (!isGroup) ...[
            const SizedBox(height: 9),
            _fundedBar(item['progress'] as double),
          ],

          // ── Footer: receipt + action
          const SizedBox(height: 10),
          const Divider(height: 1, color: line),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: receipt.isNotEmpty
                      ? Row(
                    children: [
                      const Icon(Icons.receipt_long_outlined, size: 15, color: muted),
                      const SizedBox(width: 4),
                      Flexible(
                        child: SelectableText(
                          receipt,
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 12, color: ink, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  )
                      : Text(
                    _footerText(awaiting: awaiting, underReview: underReview && !canPay, rejected: rejected),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ),
                if (canPay)
                  _actionButton(
                    icon: Icons.upload_file_rounded,
                    label: rejected
                        ? LanguageService.tr('Pay Again', 'আবার দিন')
                        : (paidApproved + paidPending > 0)
                        ? (installment
                        ? LanguageService.tr('Next Installment', 'পরের কিস্তি')
                        : LanguageService.tr('Pay Remaining', 'বাকি দিন'))
                        : LanguageService.tr('Submit Payment', 'পেমেন্ট দিন'),
                    color: accent,
                    filled: true,
                    onTap: () => _openPayment(item),
                  )
                else if (activeLike && !isGroup)
                  _actionButton(
                    icon: Icons.workspace_premium_outlined,
                    label: LanguageService.tr('Certificate', 'সার্টিফিকেট'),
                    color: emerald,
                    filled: false,
                    onTap: () => _openWebsiteCertificate(item),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stripCell(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: Colors.white.withAlpha(165))),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: valueColor)),
          ),
        ],
      ),
    );
  }

  Widget _stripDivider() => Container(
    width: 1,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: Colors.white.withAlpha(30),
  );

  Widget _detail(String label, String value, {String? sub}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink)),
          ),
          if (sub != null)
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: emerald, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _infoLine(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: turquoise),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 12.5, color: ink, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool filled,
    required VoidCallback onTap,
  }) {
    final style = filled
        ? FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      minimumSize: const Size(0, 36),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    )
        : OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: emerald.withAlpha(110)),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      minimumSize: const Size(0, 36),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      ],
    );
    return filled
        ? FilledButton(onPressed: onTap, style: style, child: child)
        : OutlinedButton(onPressed: onTap, style: style, child: child);
  }

  /// Payment baki thakle ek line e ki korte hobe
  Widget _paymentNote({
    required bool rejected,
    required bool underReview,
    required bool partlyPaid,
    String? reason,
    double pendingBdt = 0,
    double leftBdt = 0,
  }) {
    final Color c;
    final String text;
    if (rejected) {
      c = danger;
      text = (reason != null && reason.isNotEmpty)
          ? LanguageService.tr('Payment rejected — $reason', 'পেমেন্ট বাতিল — $reason')
          : LanguageService.tr('Payment rejected. Please check and submit again.', 'পেমেন্ট বাতিল। যাচাই করে আবার জমা দিন।');
    } else if (underReview) {
      c = lapis;
      text = leftBdt > 0.5
          ? LanguageService.tr('${_fmtBdt(pendingBdt)} under review · ${_fmtBdt(leftBdt)} still to pay',
          '${_fmtBdt(pendingBdt)} যাচাই চলছে · আরও ${_fmtBdt(leftBdt)} বাকি')
          : LanguageService.tr('Admin is checking your payment. It activates after approval.',
          'অ্যাডমিন পেমেন্ট যাচাই করছেন। অনুমোদনের পর চালু হবে।');
    } else if (partlyPaid) {
      c = pendingTone;
      text = LanguageService.tr('${_fmtBdt(leftBdt)} still to pay — it activates once the full amount is verified.',
          'আরও ${_fmtBdt(leftBdt)} বাকি — পুরো টাকা যাচাই হলে চালু হবে।');
    } else {
      c = pendingTone;
      text = LanguageService.tr('Pay by bank, cash or cheque, then tap "Submit Payment".',
          'ব্যাংক, ক্যাশ বা চেকে টাকা দিয়ে "পেমেন্ট দিন" চাপুন।');
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: c.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withAlpha(45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: c),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c, height: 1.35)),
          ),
        ],
      ),
    );
  }

  /// Website er "Your Investment Progress" — sobuj = jachai hoyeche, neel-sobuj = jachai cholche
  Widget _paymentProgress({
    required double total,
    required double approved,
    required double pending,
    required double left,
    required bool installment,
  }) {
    double f(double v) => total > 0 ? (v / total).clamp(0.0, 1.0).toDouble() : 0.0;
    Widget stat(String label, double v, Color c) => Expanded(
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Flexible(
            child: Text('$label ${_fmtBdt(v)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: ink, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                installment
                    ? LanguageService.tr('INSTALLMENTS', 'কিস্তি')
                    : LanguageService.tr('PAYMENT PROGRESS', 'পেমেন্টের অগ্রগতি'),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: muted, letterSpacing: 0.8),
              ),
              const Spacer(),
              Text(
                LanguageService.tr('${(f(approved) * 100).floor()}% verified', '${(f(approved) * 100).floor()}% যাচাই'),
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: emerald),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: LayoutBuilder(
                builder: (_, c) => Stack(
                  children: [
                    Container(color: line),
                    Container(width: c.maxWidth * (f(approved) + f(pending)).clamp(0.0, 1.0), color: pendingBar),
                    Container(width: c.maxWidth * f(approved), color: emerald),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              stat(LanguageService.tr('Verified', 'যাচাই'), approved, emerald),
              stat(LanguageService.tr('Review', 'চলছে'), pending, pendingBar),
              stat(LanguageService.tr('Left', 'বাকি'), left, ink),
            ],
          ),
        ],
      ),
    );
  }

  String _footerText({required bool awaiting, required bool underReview, required bool rejected}) {
    if (underReview) return LanguageService.tr('Admin is reviewing your payment', 'এডমিন পেমেন্ট যাচাই করছেন');
    if (rejected) return LanguageService.tr('Resubmit a valid payment proof', 'সঠিক পেমেন্ট প্রুফ আবার দিন');
    if (awaiting) return LanguageService.tr('Submit payment to activate', 'চালু করতে পেমেন্ট দিন');
    return LanguageService.tr('Receipt will appear after approval', 'অনুমোদনের পর রসিদ নম্বর আসবে');
  }

  String _shareText(double share) {
    final s = share == share.roundToDouble() ? share.toStringAsFixed(0) : share.toStringAsFixed(2);
    return '$s%';
  }

  Widget _fundedBar(double progress) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            LanguageService.tr('Project funded', 'প্রজেক্ট ফান্ডেড'),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: BC.muted,
                valueColor: const AlwaysStoppedAnimation<Color>(emeraldBright),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(progress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: emerald),
          ),
        ],
      ),
    );
  }

  // ─── Empty / Message ──────────────────────────────────────
  Widget _buildEmptyInvestmentsCard() {
    final bool groupsOnly = _typeFilter == 'GROUP';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(color: emeraldSoft, shape: BoxShape.circle),
            child: Icon(groupsOnly ? Icons.apartment_rounded : Icons.inventory_2_outlined, size: 20, color: emerald),
          ),
          const SizedBox(height: 10),
          Text(
            LanguageService.tr('No investments found', 'কোনো বিনিয়োগ পাওয়া যায়নি'),
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: ink),
          ),
          const SizedBox(height: 3),
          Text(
            groupsOnly
                ? LanguageService.tr('Browse business groups to make a group investment.',
                'গ্রুপ বিনিয়োগের জন্য বিজনেস গ্রুপসমূহ দেখুন।')
                : LanguageService.tr('Browse open projects to make your first investment.',
                'আপনার প্রথম বিনিয়োগের জন্য প্রজেক্টসমূহ দেখুন।'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: muted),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(IconData icon, String text, String buttonLabel, VoidCallback onTap) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: emerald),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}