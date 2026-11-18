import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import 'browse_groups_page.dart';
import 'group_invest_page.dart';
import 'group_investment_detail_page.dart';
import '../../../theme/app_colors.dart';

class GroupInvestmentsPage extends StatefulWidget {
  const GroupInvestmentsPage({super.key});

  @override
  State<GroupInvestmentsPage> createState() => _GroupInvestmentsPageState();
}

class _GroupInvestmentsPageState extends State<GroupInvestmentsPage> {
  // ─── Palette — website er rong (lib/theme/app_colors.dart) ───
  static const Color emerald = BC.primary;
  static const Color emeraldDeep = BC.brand800;
  static const Color emeraldBright = BC.brand500;
  static const Color emeraldSoft = BC.secondary;
  static const Color gold = BC.harvest500;
  static const Color goldLight = BC.harvest400;
  static const Color goldDeep = BC.harvest600;
  static const Color goldSoft = BC.accent;
  static const Color turquoise = BC.chart4;
  static const Color turquoiseSoft = BC.chart4Muted;
  static const Color lapis = BC.finance600;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color danger = BC.destructive;

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  bool _isLoading = true;
  bool _needsLogin = false;
  bool _loadFailed = false;
  List<Map<String, dynamic>> _groupInvestments = [];

  /// Website rule: ACTIVE/MATURED/COMPLETED er puro + pending er verified kisti
  double _investedTotal = 0;

  /// Pending investment e ekhono je taka dite hobe / jachai cholche
  double _toPayTotal = 0;
  double _expectedTotal = 0;
  int _activeCount = 0;
  int _awaitingCount = 0;

  String _filter = 'ALL'; // ALL / ACTIVE / PENDING / CLOSED

  @override
  void initState() {
    super.initState();
    _loadGroupInvestments();
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  DateTime? _parseDate(dynamic s) {
    final raw = s?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    var t = raw.replaceFirst(' ', 'T');
    if (t.contains('T') && !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(t)) t = '${t}Z';
    return DateTime.tryParse(t)?.toLocal();
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  String _trim(double v, int digits) {
    final s = v.toStringAsFixed(digits);
    return s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
  }

  String _fmtFull(double amount) {
    final s = amount.toStringAsFixed(0);
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '৳$b';
  }

  String _pct(double r) => '${_trim(r * 100, 1)}%';

  bool _isAwaiting(String s) => s == 'PENDING' || s == 'PAYMENT_PENDING';
  bool _isInvested(String s) => s == 'ACTIVE' || s == 'MATURED' || s == 'COMPLETED';

  bool _matchFilter(String s, [String? filter]) {
    switch (filter ?? _filter) {
      case 'ACTIVE':
        return s == 'ACTIVE';
      case 'PENDING':
        return _isAwaiting(s);
      case 'CLOSED':
        return s == 'MATURED' || s == 'COMPLETED' || s == 'CANCELLED' || s == 'REFUNDED';
      default:
        return true;
    }
  }

  String _title(Map<String, dynamic> inv) {
    final group = inv['groupName']?.toString().trim() ?? '';
    final entity = inv['entityName']?.toString().trim() ?? '';
    if (group.isEmpty) return entity.isEmpty ? '—' : entity;
    if (entity.isEmpty || entity.toLowerCase() == group.toLowerCase()) return group;
    return '$group — $entity';
  }

  DateTime? _maturity(Map<String, dynamic> inv) {
    final start = _parseDate(inv['createdAt']);
    final months = _num(inv['durationMonths']).toInt();
    if (start == null || months <= 0) return null;
    return DateTime(start.year, start.month + months, start.day);
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? danger : emerald),
    );
  }

  // ═════════════════════════════════════════════════════════
  // DATA
  // ═════════════════════════════════════════════════════════
  Future<void> _loadGroupInvestments() async {
    if (mounted) setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    final userEmail = userData?['email']?.toString() ?? '';

    if (userId.isEmpty) {
      if (mounted) {
        setState(() {
          _needsLogin = true;
          _isLoading = false;
        });
      }
      return;
    }

    final list = await DatabaseService.getGroupInvestmentsData(userId, email: userEmail);
    // Khali list: "kichu nei" naki "net nei" — alada kori
    final failed = list.isEmpty && DatabaseService.lastRequestFailed;

    double invested = 0, toPay = 0, expected = 0;
    int active = 0, awaitingCount = 0;
    for (final inv in list) {
      final st = inv['status']?.toString() ?? '';
      final amt = _num(inv['amountBdt']);
      if (_isInvested(st)) {
        invested += amt;
        if (st == 'ACTIVE') {
          active++;
          expected += amt * _num(inv['expectedReturnPct']);
        }
      } else if (_isAwaiting(st)) {
        final approved = _num(inv['paidApproved']);
        invested += approved;
        toPay += math.max(0.0, amt - approved);
        awaitingCount++;
      }
    }

    if (!mounted) return;
    setState(() {
      _groupInvestments = list;
      _investedTotal = invested;
      _toPayTotal = toPay;
      _expectedTotal = expected;
      _activeCount = active;
      _awaitingCount = awaitingCount;
      _needsLogin = false;
      _loadFailed = failed;
      _isLoading = false;
    });
  }

  /// Card e chaple — shob tottho, payment history, receipt (website er motoi)
  Future<void> _openDetail(Map<String, dynamic> inv) async {
    final id = inv['id']?.toString() ?? '';
    if (id.isEmpty) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => GroupInvestmentDetailPage(groupInvestmentId: id)),
    );
    if (mounted) _loadGroupInvestments();
  }

  Future<void> _openBrowse() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BrowseGroupsPage()),
    );
    if (mounted) _loadGroupInvestments();
  }

  // ═════════════════════════════════════════════════════════
  // SUBMIT PAYMENT
  // ═════════════════════════════════════════════════════════
  Future<void> _openPayment(Map<String, dynamic> inv) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupInvestPage(
          existing: inv,
          groupName: inv['groupName']?.toString() ?? '',
          entityName: inv['entityName']?.toString() ?? '',
        ),
      ),
    );
    if (ok == true && mounted) {
      _toast(LanguageService.tr('Payment submitted. It will be active after admin approval.',
          'পেমেন্ট জমা হয়েছে। অ্যাডমিন অনুমোদনের পর চালু হবে।'));
      _loadGroupInvestments();
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
        final visible =
        _groupInvestments.where((i) => _matchFilter(i['status']?.toString() ?? '')).toList();

        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 54,
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              LanguageService.tr('Group Investments', 'গ্রুপ বিনিয়োগ'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 16.5),
            ),
            actions: [
              if (!_needsLogin && !_loadFailed)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Material(
                      color: emeraldSoft,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _openBrowse,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add_rounded, size: 15, color: emerald),
                              const SizedBox(width: 3),
                              Text(
                                LanguageService.tr('Invest', 'বিনিয়োগ'),
                                style: const TextStyle(color: emerald, fontWeight: FontWeight.w700, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
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
            LanguageService.tr('Please log in to see your group investments', 'গ্রুপ বিনিয়োগ দেখতে লগইন করুন'),
            null,
            LanguageService.tr('Log in', 'লগইন'),
                () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
            ),
          )
              : _loadFailed
              ? _buildMessage(
            Icons.wifi_off_rounded,
            LanguageService.tr('Could not load your group investments', 'গ্রুপ বিনিয়োগ লোড করা যায়নি'),
            LanguageService.tr('Please check your internet connection.', 'ইন্টারনেট সংযোগ চেক করুন।'),
            LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
            _loadGroupInvestments,
          )
              : RefreshIndicator(
            onRefresh: _loadGroupInvestments,
            color: emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 2, 16, 24 + MediaQuery.of(context).padding.bottom),
              children: [
                if (_groupInvestments.isEmpty)
                  _buildEmptyState()
                else ...[
                  _buildSummary(),
                  const SizedBox(height: 12),
                  _buildFilterBar(),
                  const SizedBox(height: 10),
                  if (visible.isEmpty)
                    _buildNoMatch()
                  else
                    for (final inv in visible) ...[
                      _buildGroupCard(inv),
                      const SizedBox(height: 10),
                    ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Summary hero ─────────────────────────────────────────
  Widget _buildSummary() {
    Widget cell(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 9.5)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w800)),
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
            Positioned.fill(
              child: CustomPaint(painter: _IslamicPatternPainter(color: Colors.white.withAlpha(14), cell: 34)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        LanguageService.tr('INVESTED IN GROUPS', 'গ্রুপে বিনিয়োগ'),
                        style: const TextStyle(
                            color: goldLight, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.3),
                      ),
                      const Spacer(),
                      Text(
                        LanguageService.tr(
                            '${_groupInvestments.length} investments', '${_groupInvestments.length} টি বিনিয়োগ'),
                        style: TextStyle(fontSize: 10, color: Colors.white.withAlpha(150)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _fmtFull(_investedTotal),
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(height: 1, color: Colors.white.withAlpha(25)),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      cell(LanguageService.tr('Active', 'চলমান'), '$_activeCount', Colors.white),
                      const SizedBox(width: 8),
                      cell(
                        LanguageService.tr('To pay ($_awaitingCount)', 'বাকি ($_awaitingCount)'),
                        _toPayTotal > 0.5 ? _fmtFull(_toPayTotal) : '—',
                        goldLight,
                      ),
                      const SizedBox(width: 8),
                      cell(
                        LanguageService.tr('Expected return', 'প্রত্যাশিত লাভ'),
                        _expectedTotal > 0 ? '+${_fmtFull(_expectedTotal)}' : '—',
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

  // ─── Filter chips ─────────────────────────────────────────
  Widget _buildFilterBar() {
    int count(String f) =>
        _groupInvestments.where((i) => _matchFilter(i['status']?.toString() ?? '', f)).length;

    final filters = [
      ('ALL', 'All', 'সব'),
      ('ACTIVE', 'Active', 'চলমান'),
      ('PENDING', 'Pending', 'অপেক্ষমান'),
      ('CLOSED', 'Closed', 'বন্ধ'),
    ];

    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final f = filters[i];
          final sel = _filter == f.$1;
          final n = count(f.$1);
          return GestureDetector(
            onTap: () => setState(() => _filter = f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? goldSoft : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? gold : line),
              ),
              child: Row(
                children: [
                  Text(
                    LanguageService.tr(f.$2, f.$3),
                    style: TextStyle(
                        fontSize: 11, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? goldDeep : ink),
                  ),
                  if (n > 0) ...[
                    const SizedBox(width: 5),
                    Text('$n',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: sel ? goldDeep : muted)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Status (card er upore dane) ──────────────────────────
  (String, Color, IconData) _statusInfo(String status,
      {required bool rejected, required bool underReview, required bool partlyPaid}) {
    if (_isAwaiting(status)) {
      if (rejected) return (LanguageService.tr('Rejected', 'বাতিল'), danger, Icons.cancel_rounded);
      if (underReview) return (LanguageService.tr('Under review', 'যাচাই চলছে'), lapis, Icons.hourglass_top_rounded);
      if (partlyPaid) return (LanguageService.tr('Partly paid', 'আংশিক পরিশোধ'), goldDeep, Icons.timelapse_rounded);
      return (LanguageService.tr('Awaiting payment', 'পেমেন্ট বাকি'), goldDeep, Icons.error_outline_rounded);
    }
    switch (status) {
      case 'ACTIVE':
        return (LanguageService.tr('Active', 'চলমান'), emeraldBright, Icons.verified_rounded);
      case 'MATURED':
      case 'COMPLETED':
        return (LanguageService.tr('Completed', 'সম্পন্ন'), lapis, Icons.task_alt_rounded);
      case 'REFUNDED':
        return (LanguageService.tr('Refunded', 'ফেরত'), muted, Icons.undo_rounded);
      default:
        return (LanguageService.tr('Cancelled', 'বাতিল'), danger, Icons.block_rounded);
    }
  }

  // ─── Investment card ──────────────────────────────────────
  Widget _buildGroupCard(Map<String, dynamic> inv) {
    final status = inv['status']?.toString() ?? '';
    final amount = _num(inv['amountBdt']);
    final pct = _num(inv['expectedReturnPct']);
    final months = _num(inv['durationMonths']).toInt();
    final receipt = inv['receiptNumber']?.toString() ?? '';
    final plot = inv['plotNumber']?.toString() ?? '';
    final share = _num(inv['sharePercentage']);
    final plotSize = _num(inv['plotSizeSqft']);
    final tier = inv['tierName']?.toString() ?? '';
    final created = _parseDate(inv['createdAt']);
    final maturity = _maturity(inv);

    final sub = inv['latestSubmission'] as Map<String, dynamic>?;
    final subStatus = sub?['status']?.toString() ?? '';

    final awaiting = _isAwaiting(status);
    final approved = _num(inv['paidApproved']);
    final pending = _num(inv['paidPending']);
    final left = math.max(0.0, amount - approved - pending);
    final rejected = awaiting && subStatus == 'REJECTED' && pending <= 0;
    final underReview = awaiting && pending > 0;
    final partlyPaid = awaiting && approved > 0;
    final st = _statusInfo(status, rejected: rejected, underReview: underReview, partlyPaid: partlyPaid);

    final facts = <(String, String, String?)>[
      (LanguageService.tr('Invested', 'বিনিয়োগ'), _fmtDate(created), null),
      if (months > 0) (LanguageService.tr('Term', 'মেয়াদ'), LanguageService.tr('$months months', '$months মাস'), null),
      if (status == 'ACTIVE' && maturity != null)
        (
        LanguageService.tr('Matures', 'মেয়াদ শেষ'),
        _fmtDate(maturity),
        LanguageService.tr('${math.max(0, maturity.difference(DateTime.now()).inDays)} days left',
            '${math.max(0, maturity.difference(DateTime.now()).inDays)} দিন বাকি'),
        ),
      if (plot.isNotEmpty && plot != 'N/A') (LanguageService.tr('Plot', 'প্লট'), plot, null),
      if (plotSize > 0) (LanguageService.tr('Plot size', 'আয়তন'), '${_trim(plotSize, 0)} sqft', null),
      if (share > 0) (LanguageService.tr('Share', 'শেয়ার'), '${_trim(share, 2)}%', null),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDetail(inv),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: rejected ? danger.withAlpha(120) : line, width: rejected ? 1.3 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: emeraldSoft, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.apartment_rounded, color: emerald, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title(inv),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink, height: 1.25),
                        ),
                        if (tier.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(tier,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10.5, color: muted)),
                        ],
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
                        Icon(st.$3, size: 11, color: st.$2),
                        const SizedBox(width: 3),
                        Text(st.$1, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: st.$2)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Amount strip
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [emerald, emeraldDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    _stripCell(LanguageService.tr('Amount', 'পরিমাণ'), _fmtFull(amount), Colors.white),
                    _stripDivider(),
                    _stripCell(
                      pct > 0
                          ? LanguageService.tr('Expected (${_pct(pct)})', 'প্রত্যাশিত (${_pct(pct)})')
                          : LanguageService.tr('Expected', 'প্রত্যাশিত'),
                      pct > 0 ? '+${_fmtFull(amount * pct)}' : LanguageService.tr('Not set', 'নির্ধারিত নয়'),
                      goldLight,
                    ),
                    _stripDivider(),
                    _stripCell(
                      LanguageService.tr('Total', 'মোট'),
                      pct > 0 ? _fmtFull(amount * (1 + pct)) : '—',
                      BC.brand300,
                    ),
                  ],
                ),
              ),
            ),

            // ── Facts (choto grid)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: LayoutBuilder(
                builder: (_, c) {
                  final w = (c.maxWidth - 16) / 3;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: facts.map((f) => SizedBox(width: w, child: _fact(f.$1, f.$2, f.$3))).toList(),
                  );
                },
              ),
            ),

            // ── Payment state (shudhu pending e)
            if (awaiting) ...[
              const SizedBox(height: 10),
              _buildPaymentState(
                inv,
                total: amount,
                approved: approved,
                pending: pending,
                left: left,
                rejected: rejected,
                subStatus: subStatus,
              ),
            ],

            // ── Footer: receipt
            const SizedBox(height: 10),
            const Divider(height: 1, color: line),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Icon(receipt.isNotEmpty ? Icons.receipt_long_outlined : Icons.info_outline_rounded,
                      size: 13, color: muted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: receipt.isNotEmpty
                        ? SelectableText(
                      receipt,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 10.5, color: ink, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                    )
                        : Text(
                      LanguageService.tr('Receipt will appear after approval', 'অনুমোদনের পর রসিদ নম্বর আসবে'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: muted),
                    ),
                  ),
                  if (status == 'ACTIVE' && pct > 0)
                    Text(
                      LanguageService.tr('Estimate, not guaranteed', 'আনুমানিক, নিশ্চিত নয়'),
                      style: const TextStyle(fontSize: 9, color: muted, fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
            // ── Details e jawa
            InkWell(
              onTap: () => _openDetail(inv),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: const BoxDecoration(
                  color: emeraldSoft,
                  border: Border(top: BorderSide(color: line)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      LanguageService.tr('View details & payment history', 'বিস্তারিত ও পেমেন্টের ইতিহাস'),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: emerald),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_rounded, size: 14, color: emerald),
                  ],
                ),
              ),
            ),
          ],
        ),
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
              style: TextStyle(fontSize: 9, color: Colors.white.withAlpha(165))),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: valueColor)),
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

  Widget _fact(String label, String value, String? sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9, color: muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ink)),
        ),
        if (sub != null)
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, color: goldDeep, fontWeight: FontWeight.w600)),
      ],
    );
  }

  /// Pending investment er payment kon obosthay ache — shotti ja, tai dekhai
  Widget _buildPaymentState(
      Map<String, dynamic> inv, {
        required double total,
        required double approved,
        required double pending,
        required double left,
        required bool rejected,
        required String subStatus,
      }) {
    final sub = inv['latestSubmission'] as Map<String, dynamic>?;
    final ref = sub?['transactionRef']?.toString() ?? '';
    final reason = sub?['rejectionReason']?.toString() ?? '';
    final installment = inv['paymentPlan'] == 'INSTALLMENT';
    final canPay = left > 0.5;
    final anyPaid = approved + pending > 0;

    // Note
    final Color c;
    final IconData icon;
    final String text;
    if (rejected) {
      c = danger;
      icon = Icons.error_outline_rounded;
      text = reason.isNotEmpty
          ? LanguageService.tr('Payment proof rejected — $reason', 'পেমেন্ট প্রুফ বাতিল — $reason')
          : LanguageService.tr('Your last payment proof was rejected. Please submit again.',
          'আপনার আগের পেমেন্ট প্রুফ বাতিল হয়েছে। আবার জমা দিন।');
    } else if (pending > 0 && !canPay) {
      c = lapis;
      icon = Icons.hourglass_top_rounded;
      text = LanguageService.tr(
        'Payment under review${ref.isNotEmpty ? ' · Ref $ref' : ''} · sent ${_fmtDate(_parseDate(sub?['createdAt']))}',
        'পেমেন্ট যাচাই চলছে${ref.isNotEmpty ? ' · Ref $ref' : ''} · জমা ${_fmtDate(_parseDate(sub?['createdAt']))}',
      );
    } else if (!canPay && subStatus == 'APPROVED') {
      c = emerald;
      icon = Icons.verified_outlined;
      text = LanguageService.tr('Payment approved — your investment will be activated shortly.',
          'পেমেন্ট অনুমোদিত — শীঘ্রই বিনিয়োগ চালু হবে।');
    } else if (anyPaid) {
      c = goldDeep;
      icon = Icons.timelapse_rounded;
      text = LanguageService.tr('${_fmtFull(left)} still to pay — it activates once the full amount is verified.',
          'আরও ${_fmtFull(left)} বাকি — পুরো টাকা যাচাই হলে চালু হবে।');
    } else {
      c = goldDeep;
      icon = Icons.info_outline_rounded;
      text = LanguageService.tr('Pay by bank, cash or cheque, then submit the payment details.',
          'ব্যাংক, ক্যাশ বা চেকে টাকা দিয়ে পেমেন্টের তথ্য জমা দিন।');
    }

    double f(double v) => total > 0 ? (v / total).clamp(0.0, 1.0).toDouble() : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: c.withAlpha(18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.withAlpha(45)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 14, color: c),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600, height: 1.35)),
                ),
              ],
            ),
          ),
          if (anyPaid || installment) ...[
            const SizedBox(height: 8),
            Container(
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
                        style: const TextStyle(
                            fontSize: 8.5, fontWeight: FontWeight.w800, color: muted, letterSpacing: 0.8),
                      ),
                      const Spacer(),
                      Text(
                        LanguageService.tr(
                            '${(f(approved) * 100).floor()}% verified', '${(f(approved) * 100).floor()}% যাচাই'),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: emerald),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 6,
                      child: LayoutBuilder(
                        builder: (_, cons) => Stack(
                          children: [
                            Container(color: line),
                            Container(
                                width: cons.maxWidth * (f(approved) + f(pending)).clamp(0.0, 1.0), color: gold),
                            Container(width: cons.maxWidth * f(approved), color: emerald),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _dotStat(LanguageService.tr('Verified', 'যাচাই'), approved, emerald),
                      _dotStat(LanguageService.tr('Review', 'চলছে'), pending, gold),
                      _dotStat(LanguageService.tr('Left', 'বাকি'), left, ink),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (canPay) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: FilledButton.icon(
                onPressed: () => _openPayment(inv),
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: Text(
                  rejected
                      ? LanguageService.tr('Submit Again', 'আবার জমা দিন')
                      : anyPaid
                      ? (installment
                      ? LanguageService.tr('Pay Next Installment', 'পরের কিস্তি দিন')
                      : LanguageService.tr('Pay Remaining', 'বাকি টাকা দিন'))
                      : LanguageService.tr('Submit Payment', 'পেমেন্ট জমা দিন'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: emerald,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dotStat(String label, double v, Color c) => Expanded(
    child: Row(
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Flexible(
          child: Text('$label ${_fmtFull(v)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9.5, color: ink, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  // ─── Empty / message ──────────────────────────────────────
  Widget _buildNoMatch() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Text(
        LanguageService.tr('No investments in this filter', 'এই ফিল্টারে কোনো বিনিয়োগ নেই'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
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
            decoration: const BoxDecoration(color: goldSoft, shape: BoxShape.circle),
            child: const Icon(Icons.apartment_rounded, color: goldDeep, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            LanguageService.tr('No group investments yet', 'এখনো কোনো গ্রুপ বিনিয়োগ নেই'),
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink),
          ),
          const SizedBox(height: 3),
          Text(
            LanguageService.tr('Browse business groups and choose a tier to invest in.',
                'বিজনেস গ্রুপ দেখে একটি টিয়ারে বিনিয়োগ করুন।'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: muted),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: FilledButton.icon(
              onPressed: _openBrowse,
              icon: const Icon(Icons.search_rounded, size: 15),
              label: Text(LanguageService.tr('Browse Groups', 'গ্রুপ দেখুন'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(IconData icon, String title, String? subtitle, String buttonLabel, VoidCallback onTap) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: goldDeep),
            const SizedBox(height: 10),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: muted)),
            ],
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
  bool shouldRepaint(covariant _IslamicPatternPainter old) => old.color != color || old.cell != cell;
}