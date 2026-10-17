import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import 'browse_groups_page.dart';
import 'group_invest_page.dart';

class GroupInvestmentsPage extends StatefulWidget {
  const GroupInvestmentsPage({super.key});

  @override
  State<GroupInvestmentsPage> createState() => _GroupInvestmentsPageState();
}

class _GroupInvestmentsPageState extends State<GroupInvestmentsPage> {
  // ─── Palette ───
  static const Color emerald = Color(0xFF0E4A37);
  static const Color emeraldDeep = Color(0xFF0A3327);
  static const Color emeraldSoft = Color(0xFFE3F0E9);
  static const Color gold = Color(0xFFB8935A);
  static const Color goldLight = Color(0xFFD9BE8C);
  static const Color goldDeep = Color(0xFF8A6A3A);
  static const Color goldSoft = Color(0xFFF6EEDF);
  static const Color lapis = Color(0xFF26437A);
  static const Color lapisSoft = Color(0xFFE5EAF4);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);
  static const Color danger = Color(0xFFB4413A);
  static const Color dangerSoft = Color(0xFFFBEAE8);

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  bool _isLoading = true;
  bool _needsLogin = false;
  bool _loadFailed = false;
  List<Map<String, dynamic>> _groupInvestments = [];

  double _investedTotal = 0; // ACTIVE + COMPLETED
  double _awaitingTotal = 0; // PENDING + PAYMENT_PENDING
  int _activeCount = 0;
  int _awaitingCount = 0;

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

  String _fmtDate(dynamic s) {
    final d = _parseDate(s);
    if (d == null) return '—';
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
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

  String _fmtFull(double amount) {
    final s = amount.toStringAsFixed(0);
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '৳$b';
  }

  String _pct(double r) {
    final v = r * 100;
    return '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}%';
  }

  String _statusText(String s) {
    switch (s) {
      case 'PENDING':
      case 'PAYMENT_PENDING':
        return LanguageService.tr('Awaiting Payment', 'পেমেন্ট অপেক্ষমান');
      case 'ACTIVE':
        return LanguageService.tr('Active', 'একটিভ');
      case 'COMPLETED':
        return LanguageService.tr('Completed', 'সম্পন্ন');
      case 'CANCELLED':
        return LanguageService.tr('Cancelled', 'বাতিল');
      default:
        return s;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'PENDING':
      case 'PAYMENT_PENDING':
        return goldDeep;
      case 'ACTIVE':
        return emerald;
      case 'COMPLETED':
        return lapis;
      default:
        return danger;
    }
  }

  String _title(Map<String, dynamic> inv) {
    final group = inv['groupName']?.toString() ?? '';
    final entity = inv['entityName']?.toString() ?? '';
    if (entity.isEmpty || entity.toLowerCase() == group.toLowerCase()) return group;
    return '$group — $entity';
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

    double invested = 0, awaiting = 0;
    int active = 0, awaitingCount = 0;
    for (final inv in list) {
      final st = inv['status']?.toString() ?? '';
      final amt = _num(inv['amountBdt']);
      if (st == 'ACTIVE' || st == 'COMPLETED') invested += amt;
      if (st == 'ACTIVE') active++;
      if (st == 'PENDING' || st == 'PAYMENT_PENDING') {
        awaiting += amt;
        awaitingCount++;
      }
    }

    if (!mounted) return;
    setState(() {
      _groupInvestments = list;
      _investedTotal = invested;
      _awaitingTotal = awaiting;
      _activeCount = active;
      _awaitingCount = awaitingCount;
      _needsLogin = false;
      _loadFailed = failed;
      _isLoading = false;
    });
  }

  Future<void> _openBrowse() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BrowseGroupsPage()),
    );
    if (mounted) _loadGroupInvestments();
  }

  // ═════════════════════════════════════════════════════════
  // SUBMIT PROOF
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
        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              LanguageService.tr('Group Investments', 'গ্রুপ বিনিয়োগ'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 18),
            ),
            actions: [
              if (!_needsLogin)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton.icon(
                    onPressed: _openBrowse,
                    icon: const Icon(Icons.add_rounded, size: 17, color: emerald),
                    label: Text(
                      LanguageService.tr('Browse', 'গ্রুপ দেখুন'),
                      style: const TextStyle(color: emerald, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ),
            ],
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
            LanguageService.tr('Please log in to see your group investments',
                'গ্রুপ বিনিয়োগ দেখতে লগইন করুন'),
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
            LanguageService.tr('Could not load your group investments',
                'গ্রুপ বিনিয়োগ লোড করা যায়নি'),
            LanguageService.tr(
                'Please check your internet connection.', 'ইন্টারনেট সংযোগ চেক করুন।'),
            LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
            _loadGroupInvestments,
          )
              : RefreshIndicator(
            onRefresh: _loadGroupInvestments,
            color: emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                if (_groupInvestments.isEmpty)
                  _buildEmptyState()
                else ...[
                  _buildSummary(),
                  const SizedBox(height: 18),
                  for (final inv in _groupInvestments) ...[
                    _buildGroupCard(inv),
                    const SizedBox(height: 14),
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
                    LanguageService.tr('INVESTED IN GROUPS', 'গ্রুপে বিনিয়োগ'),
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
                      _fmtFull(_investedTotal),
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _heroStat(
                          LanguageService.tr('Active', 'একটিভ'),
                          '$_activeCount',
                        ),
                      ),
                      Container(width: 0.8, height: 30, color: gold.withAlpha(90)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _heroStat(
                          LanguageService.tr('Awaiting payment', 'পেমেন্ট অপেক্ষমান'),
                          _awaitingCount == 0
                              ? '0'
                              : '$_awaitingCount · ${_fmtBdt(_awaitingTotal)}',
                        ),
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

  Widget _heroStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }

  // ─── Investment card ──────────────────────────────────────
  Widget _buildGroupCard(Map<String, dynamic> inv) {
    final status = inv['status']?.toString() ?? '';
    final c = _statusColor(status);
    final amount = _num(inv['amountBdt']);
    final pct = _num(inv['expectedReturnPct']);
    final months = (inv['durationMonths'] as num?)?.toInt() ?? 0;
    final receipt = inv['receiptNumber']?.toString() ?? '';
    final plot = inv['plotNumber']?.toString() ?? '';
    final share = _num(inv['sharePercentage']);
    final plotSize = _num(inv['plotSizeSqft']);
    final awaiting = status == 'PENDING' || status == 'PAYMENT_PENDING';

    final facts = <(String, String)>[
      if (pct > 0) (LanguageService.tr('Expected return', 'প্রত্যাশিত লাভ'), _pct(pct)),
      if (months > 0) (LanguageService.tr('Term', 'মেয়াদ'), LanguageService.tr('$months months', '$months মাস')),
      if (plot.isNotEmpty) (LanguageService.tr('Plot no.', 'প্লট নম্বর'), plot),
      if (plotSize > 0) (LanguageService.tr('Plot size', 'প্লটের আয়তন'), '${_trim(plotSize, 0)} sqft'),
      if (share > 0) (LanguageService.tr('Share', 'শেয়ার'), '${_trim(share, 2)}%'),
    ];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: goldSoft, borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.groups_2_outlined, color: goldDeep, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title(inv),
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${inv['tierName'] ?? ''} · ${_fmtDate(inv['createdAt'])}',
                        style: const TextStyle(fontSize: 11, color: muted),
                      ),
                      if (receipt.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        SelectableText(
                          LanguageService.tr('Receipt: $receipt', 'রসিদ: $receipt'),
                          style: const TextStyle(fontSize: 10.5, color: muted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _fmtBdt(amount),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: c.withAlpha(22), borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        _statusText(status),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (facts.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Color(0xFFFBF9F5),
                border: Border(top: BorderSide(color: line)),
              ),
              child: Wrap(
                spacing: 22,
                runSpacing: 10,
                children: facts
                    .map((f) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.$1.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w700, color: muted, letterSpacing: 0.6),
                    ),
                    const SizedBox(height: 2),
                    Text(f.$2,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink)),
                  ],
                ))
                    .toList(),
              ),
            ),
          if (status == 'ACTIVE' && pct > 0)
            _footNote(
              LanguageService.tr(
                  'Expected return ${_fmtBdt(amount * pct)} (estimate, not guaranteed)',
                  'প্রত্যাশিত লাভ ${_fmtBdt(amount * pct)} (আনুমানিক, নিশ্চিত নয়)'),
              emerald,
              Icons.trending_up_rounded,
            ),
          if (awaiting) _buildPaymentState(inv),
        ],
      ),
    );
  }

  /// Pending investment er payment kon obosthay ache — shotti ja, tai dekhai
  Widget _buildPaymentState(Map<String, dynamic> inv) {
    final sub = inv['latestSubmission'] as Map<String, dynamic>?;
    final subStatus = sub?['status']?.toString() ?? '';
    final ref = sub?['transactionRef']?.toString() ?? '';

    if (subStatus == 'SUBMITTED') {
      return _footNote(
        LanguageService.tr(
          'Payment proof under review${ref.isNotEmpty ? ' · Ref $ref' : ''} · sent ${_fmtDate(sub?['createdAt'])}',
          'পেমেন্ট প্রুফ যাচাই চলছে${ref.isNotEmpty ? ' · Ref $ref' : ''} · জমা ${_fmtDate(sub?['createdAt'])}',
        ),
        goldDeep,
        Icons.hourglass_top_rounded,
      );
    }

    if (subStatus == 'APPROVED') {
      return _footNote(
        LanguageService.tr('Payment approved — your investment will be activated shortly.',
            'পেমেন্ট অনুমোদিত — শীঘ্রই বিনিয়োগ চালু হবে।'),
        emerald,
        Icons.verified_outlined,
      );
    }

    final rejected = subStatus == 'REJECTED';
    final reason = sub?['rejectionReason']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rejected) ...[
            _errorBox(
              reason.isNotEmpty
                  ? LanguageService.tr('Payment proof rejected: $reason', 'পেমেন্ট প্রুফ বাতিল: $reason')
                  : LanguageService.tr('Your last payment proof was rejected. Please submit again.',
                  'আপনার আগের পেমেন্ট প্রুফ বাতিল হয়েছে। আবার জমা দিন।'),
            ),
            const SizedBox(height: 10),
          ] else ...[
            Text(
              LanguageService.tr('Pay by bank, cash or cheque, then submit the payment details.',
                  'ব্যাংক, ক্যাশ বা চেকে টাকা দিয়ে পেমেন্টের তথ্য জমা দিন।'),
              style: const TextStyle(fontSize: 11.5, color: muted),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openPayment(inv),
              icon: const Icon(Icons.upload_file_rounded, size: 17),
              label: Text(rejected
                  ? LanguageService.tr('Submit Again', 'আবার জমা দিন')
                  : LanguageService.tr('Submit Payment', 'পেমেন্ট জমা দিন')),
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footNote(String text, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
      decoration: BoxDecoration(
        color: color.withAlpha(14),
        border: const Border(top: BorderSide(color: line)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: dangerSoft, borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: danger),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: danger))),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: goldSoft, borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.groups_2_outlined, color: goldDeep, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            LanguageService.tr('No group investments yet', 'এখনো কোনো গ্রুপ বিনিয়োগ নেই'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
          ),
          const SizedBox(height: 4),
          Text(
            LanguageService.tr('Browse business groups and choose a tier to invest in.',
                'বিজনেস গ্রুপ দেখে একটি টিয়ারে বিনিয়োগ করুন।'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: muted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openBrowse,
            icon: const Icon(Icons.search_rounded, size: 17),
            label: Text(LanguageService.tr('Browse Groups', 'গ্রুপ দেখুন')),
            style: FilledButton.styleFrom(
              backgroundColor: emerald,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
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
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: muted)),
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