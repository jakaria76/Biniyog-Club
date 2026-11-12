import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import '../../authentication/login_page.dart';
import '../help/help_center_page.dart';
import '../../../theme/app_colors.dart';

// ═══════════════════════════════════════════════════════════
// PROFIT RETURNS — website er /dashboard/profit-returns er app version
//  • Summary: matured / paid / pending (+ pending er bhag)
//  • Profit by project & period (record), filter + page
//  • Profit payment history (finance je taka pathiyeche)
//  • My calculation issues (Help Center)
// Shob taka DB er profit_accruals / profit_allocations / distribution theke.
// ═══════════════════════════════════════════════════════════

const Color _emerald = BC.primary;
const Color _emeraldBright = BC.brand500; // home page er moto
const Color _emeraldSoft = BC.secondary;
const Color _lapis = BC.finance600;
const Color _lapisSoft = BC.finance50;
const Color _turquoise = BC.chart4;
const Color _ivory = BC.background;
const Color _ink = BC.foreground;
const Color _muted = BC.mutedForeground;
const Color _line = BC.border;
const Color _danger = BC.destructive;
const Color _dangerSoft = BC.destructiveMuted;

const String _hotlineDisplay = '+880 1335-149033';
const String _hotlineTel = 'tel:+8801335149033';


const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const List<String> _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

/// "YYYY-MM-DD" (Bangladesh er din) ba timestamp → Dhaka er tarikh
DateTime? _day(dynamic s) {
  final raw = s?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    final p = raw.split('-').map(int.parse).toList();
    return DateTime.utc(p[0], p[1], p[2]);
  }
  var t = raw.replaceFirst(' ', 'T');
  if (t.contains('T') && !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(t)) t = '${t}Z';
  return DateTime.tryParse(t)?.toUtc().add(const Duration(hours: 6));
}

String _dayKey(dynamic s) {
  final d = _day(s);
  return d == null ? '' : d.toIso8601String().substring(0, 10);
}

/// Website er fmtDay: "1 Oct 2026"
String _fmtDay(dynamic s) {
  final d = _day(s);
  return d == null ? '—' : '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// Website er periodLabel: ek mash hole "October 2026", na hole "1 Jul 2026 – 30 Sep 2026"
String _periodLabel(dynamic start, dynamic end) {
  final a = _day(start);
  final b = _day(end);
  if (a == null || b == null) return '—';
  if (a.year == b.year && a.month == b.month) return '${_monthsLong[a.month - 1]} ${a.year}';
  return '${_fmtDay(start)} – ${_fmtDay(end)}';
}

/// Website er tk: "৳1,234.50" (shob shomoy 2 dosomik)
String _tk(num v) {
  final neg = v < 0;
  final parts = v.abs().toStringAsFixed(2).split('.');
  final s = parts[0];
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}৳$b.${parts[1]}';
}

/// Moddhober hishab (taka na) — 4 dosomik
String _tk4(num v) {
  final parts = v.toStringAsFixed(4).split('.');
  final s = parts[0];
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '৳$b.${parts[1]}';
}

/// DB te percent hishebe (15.0000 → "15%")
String _pct(num v) {
  final s = v.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return '$s%';
}

/// Website er RECORD_STATUS (label + help)
(String, Color, Color) _recordStatus(String s) {
  switch (s) {
    case 'ACCRUING':
      return (LanguageService.tr('Accruing', 'জমা হচ্ছে'), const Color(0xFF0369A1), const Color(0xFFE0F2FE));
    case 'IN_APPROVAL':
      return (LanguageService.tr('Being approved', 'অনুমোদন চলছে'), _muted, BC.muted);
    case 'AWAITING_PAYMENT':
      return (LanguageService.tr('Awaiting payment', 'পরিশোধের অপেক্ষায়'), BC.chart4Deep, BC.chart4Muted);
    case 'PARTLY_PAID':
      return (LanguageService.tr('Partly paid', 'আংশিক পরিশোধিত'), _emerald, _emeraldSoft);
    case 'PAID':
      return (LanguageService.tr('Paid', 'পরিশোধিত'), _emerald, _emeraldSoft);
    default:
      return (LanguageService.tr('Matured', 'মেয়াদপূর্ণ'), _emerald, _emeraldSoft);
  }
}

String _recordHelp(String s) {
  switch (s) {
    case 'ACCRUING':
      return LanguageService.tr('Profit is being earned day by day. It matures when the month closes.',
          'প্রতিদিন লাভ জমা হচ্ছে। মাস শেষ হলে মেয়াদপূর্ণ হবে।');
    case 'IN_APPROVAL':
      return LanguageService.tr('Included in a disbursement that the finance team is approving.',
          'একটি বণ্টনে যুক্ত, যা ফাইন্যান্স টিম অনুমোদন করছে।');
    case 'AWAITING_PAYMENT':
      return LanguageService.tr('Approved for payment. The finance team is transferring it to you.',
          'পরিশোধের জন্য অনুমোদিত। ফাইন্যান্স টিম আপনাকে পাঠাচ্ছে।');
    case 'PARTLY_PAID':
      return LanguageService.tr('Part of this profit has been paid; the rest is still to be disbursed.',
          'এই লাভের কিছু অংশ পরিশোধ হয়েছে; বাকিটা এখনো বণ্টন হবে।');
    case 'PAID':
      return LanguageService.tr('Your profit payment has been confirmed by the finance team.',
          'ফাইন্যান্স টিম আপনার লাভ পরিশোধ নিশ্চিত করেছে।');
    default:
      return LanguageService.tr('Your profit has matured and is awaiting a disbursement.',
          'আপনার লাভ মেয়াদপূর্ণ, বণ্টনের অপেক্ষায়।');
  }
}

/// Website er payoutStatus (key DB theke)
(String, Color, Color) _payoutStatus(String key) {
  switch (key) {
    case 'PAID':
      return (LanguageService.tr('Paid', 'পরিশোধিত'), _emerald, _emeraldSoft);
    case 'AWAITING_PAYMENT':
      return (LanguageService.tr('Awaiting payment', 'পরিশোধের অপেক্ষায়'), BC.chart4Deep, BC.chart4Muted);
    case 'FAILED':
      return (LanguageService.tr('Failed', 'ব্যর্থ'), _danger, _dangerSoft);
    case 'REVERSED':
      return (LanguageService.tr('Reversed', 'ফেরত নেওয়া'), _danger, _dangerSoft);
    default:
      return (LanguageService.tr('Being approved', 'অনুমোদন চলছে'), _muted, BC.muted);
  }
}

const List<String> _payoutKeys = ['PAID', 'AWAITING_PAYMENT', 'IN_APPROVAL', 'FAILED', 'REVERSED'];
const List<String> _recordKeys = ['ACCRUING', 'MATURED', 'IN_APPROVAL', 'AWAITING_PAYMENT', 'PARTLY_PAID', 'PAID'];

/// Website er PAYOUT_METHOD
String _methodLabel(String? m) {
  switch (m) {
    case 'BANK_TRANSFER':
      return LanguageService.tr('Bank transfer', 'ব্যাংক ট্রান্সফার');
    case 'BKASH':
      return 'bKash';
    case 'NAGAD':
      return 'Nagad';
    case 'ROCKET':
      return 'Rocket';
    case 'CHEQUE':
      return LanguageService.tr('Cheque', 'চেক');
    case 'CASH':
      return LanguageService.tr('Cash', 'ক্যাশ');
    case null:
    case '':
      return '—';
    default:
      return m;
  }
}


Widget _badge((String, Color, Color) m) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
  decoration: BoxDecoration(color: m.$3, borderRadius: BorderRadius.circular(20)),
  child: Text(m.$1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: m.$2)),
);

PreferredSizeWidget _appBar(String title) => AppBar(
  backgroundColor: _ivory,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  toolbarHeight: 54,
  iconTheme: const IconThemeData(color: _ink),
  title: Text(title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 17.5)),
);

Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(12)}) => Container(
  width: double.infinity,
  padding: padding,
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: _line),
  ),
  child: child,
);

Widget _sectionTitle(String title, {String? sub, Widget? trailing}) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _muted, letterSpacing: 1)),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 12, color: _muted, height: 1.35)),
            ],
          ],
        ),
      ),
      if (trailing != null) trailing,
    ],
  ),
);

/// Website er CallHelpCenter (compact)
Widget _helpCard(BuildContext context, {required String title, required String text, VoidCallback? onReport}) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _emeraldSoft,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _emerald.withAlpha(45)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.support_agent_rounded, size: 18, color: _emerald),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
                  const SizedBox(height: 2),
                  Text(text, style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (onReport != null) ...[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onReport,
                  icon: const Icon(Icons.flag_outlined, size: 17),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(LanguageService.tr('Report an issue', 'সমস্যা জানান'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _emerald,
                    minimumSize: const Size(0, 38),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(_hotlineTel), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.call_rounded, size: 17),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_hotlineDisplay, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _emerald,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: _emerald.withAlpha(80)),
                  minimumSize: const Size(0, 38),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _message(IconData icon, String title, String? sub, String btn, VoidCallback onTap) => Center(
  child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 34, color: _emerald),
        const SizedBox(height: 10),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
        if (sub != null) ...[
          const SizedBox(height: 3),
          Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: _muted)),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: _emerald,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(btn),
        ),
      ],
    ),
  ),
);


// ═══════════════════════════════════════════════════════════
// 1) PROFIT RETURNS
// ═══════════════════════════════════════════════════════════
class ProfitReturnsPage extends StatefulWidget {
  const ProfitReturnsPage({super.key});

  @override
  State<ProfitReturnsPage> createState() => _ProfitReturnsPageState();
}

class _ProfitReturnsPageState extends State<ProfitReturnsPage> {
  static const int _recordsPerPage = 12;
  static const int _paymentsPerPage = 10;

  bool _loading = true;
  bool _needsLogin = false;
  bool _failed = false;
  String _userId = '';

  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _issues = [];
  Map<String, dynamic> _summary = {};

  // Record filter
  String? _rProject;
  String? _rStatus;
  int _rPage = 1;

  // Payment filter (website er motoi: search, tarikh, project, status)
  final _q = TextEditingController();
  DateTimeRange? _hRange;
  String? _hProject;
  String? _hStatus;
  int _hPage = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = _records.isEmpty && _payments.isEmpty);
    if (_userId.isEmpty) {
      final u = await AuthService.getUserData();
      _userId = u?['id']?.toString() ?? '';
    }
    if (_userId.isEmpty) {
      if (mounted) {
        setState(() {
          _needsLogin = true;
          _loading = false;
        });
      }
      return;
    }
    final res = await Future.wait<dynamic>([
      DatabaseService.getInvestorProfitRecords(_userId),
      DatabaseService.getInvestorProfitPayments(_userId),
      // Help Center na pele-o profit er hishab dekhabe
      DatabaseService.getInvestorTickets(_userId, profitOnly: true, pageSize: 5),
    ]);
    final rec = res[0] as Map<String, dynamic>;
    final pay = res[1] as Map<String, dynamic>;
    final tickets = res[2] as Map<String, dynamic>;
    if (!mounted) return;
    setState(() {
      _failed = rec['ok'] != true || pay['ok'] != true;
      _records = ((rec['records'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _upcoming = ((rec['upcoming'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _summary = Map<String, dynamic>.from((rec['summary'] as Map?) ?? {});
      _payments = ((pay['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _issues = ((tickets['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _loading = false;
    });
  }

  double _s(String k) => (_summary[k] as num?)?.toDouble() ?? 0;

  /// Website er motoi: record er project gulo, nam onujayi
  List<(String, String)> get _projects {
    final m = <String, String>{};
    for (final r in _records) {
      m[r['projectId'] as String? ?? ''] = r['projectTitle'] as String;
    }
    final list = m.entries.where((e) => e.key.isNotEmpty).map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    return list;
  }

  Future<void> _report({Map<String, dynamic>? record, Map<String, dynamic>? payment}) async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => NewTicketPage(profitTopic: true, record: record, payment: payment)),
    );
    if (id != null && mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => TicketDetailPage(ticketId: id)));
    }
    if (mounted) _load();
  }

  void _openRecord(String id) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProfitRecordPage(recordId: id))).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        final nothing = _records.isEmpty && _payments.isEmpty;
        return Scaffold(
          backgroundColor: _ivory,
          appBar: _appBar(LanguageService.tr('Profit Returns', 'প্রফিট রিটার্নস')),
          body: _loading
              ? const Center(
              child: SizedBox(
                  width: 26, height: 26, child: CircularProgressIndicator(color: _emerald, strokeWidth: 2.4)))
              : _needsLogin
              ? _message(
              Icons.lock_outline_rounded,
              LanguageService.tr('Please log in to see your profit', 'লাভ দেখতে লগইন করুন'),
              null,
              LanguageService.tr('Log in', 'লগইন'),
                  () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false))
              : _failed && nothing
              ? _message(
              Icons.wifi_off_rounded,
              LanguageService.tr('Could not load your profit returns', 'লাভের তথ্য লোড করা যায়নি'),
              LanguageService.tr('Please check your internet connection.', 'ইন্টারনেট সংযোগ চেক করুন।'),
              LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
              _load)
              : RefreshIndicator(
            onRefresh: _load,
            color: _emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 2, 16, 24 + MediaQuery.of(context).padding.bottom),
              children: [
                Text(
                  LanguageService.tr(
                      'What your investments have earned, how it was calculated, and what has been paid.',
                      'আপনার বিনিয়োগ কত আয় করেছে, কীভাবে হিসাব হয়েছে, আর কত পরিশোধ হয়েছে।'),
                  style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.4),
                ),
                const SizedBox(height: 10),
                if (nothing)
                  _nothing()
                else ...[
                  _summaryCards(),
                  const SizedBox(height: 10),
                  _helpCard(
                    context,
                    title: LanguageService.tr('Does a calculation look wrong?', 'হিসাব ভুল মনে হচ্ছে?'),
                    text: LanguageService.tr(
                        'Report it to the Help Center from the record itself. The details are attached for you, and you can track the answer.',
                        'রেকর্ড থেকেই হেল্প সেন্টারে জানান। তথ্য নিজে থেকেই যুক্ত হবে, আর উত্তর দেখতে পারবেন।'),
                    onReport: () => _report(),
                  ),
                  const SizedBox(height: 16),
                  _recordsSection(),
                  const SizedBox(height: 16),
                  _paymentsSection(),
                ],
                const SizedBox(height: 16),
                _issuesSection(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _nothing() => _card(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
    child: Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(color: _emeraldSoft, shape: BoxShape.circle),
          child: const Icon(Icons.savings_outlined, size: 21, color: _emerald),
        ),
        const SizedBox(height: 10),
        Text(LanguageService.tr('No profit records are available yet.', 'এখনো কোনো লাভের রেকর্ড নেই।'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 3),
        Text(
          LanguageService.tr('Profit starts once your investment is fully approved. It will appear here day by day.',
              'বিনিয়োগ পুরোপুরি অনুমোদনের পর লাভ শুরু হয়। এখানে দিনে দিনে দেখা যাবে।'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.4),
        ),
      ],
    ),
  );

  // ─── Summary (website er 5 card) ──────────────────────────
  Widget _summaryCards() {
    final earned = _s('earnedBdt');
    final accruing = _s('accruingBdt');
    final matured = _s('maturedBdt');
    final paid = _s('paidBdt');
    final pending = _s('pendingBdt');
    final awaiting = _s('awaitingPaymentBdt');
    final approving = _s('inApprovalBdt');
    final notScheduled = _s('notScheduledBdt');
    final upcomingMonth = _upcoming.isNotEmpty ? _upcoming.first['month'] : null;

    Widget small(String label, String value, String sub, Color color, String tip, {bool dashed = false}) => Expanded(
      child: GestureDetector(
        onTap: () => _tip(label, tip),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(
            color: dashed ? _ivory : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dashed ? BC.chart4.withAlpha(110) : _line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _muted, letterSpacing: 0.4)),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.info_outline_rounded, size: 12, color: _muted),
                ],
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
              ),
              Text(sub, maxLines: 2, style: const TextStyle(fontSize: 10.5, color: _muted, height: 1.3)),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Total profit earned — boro card
        GestureDetector(
          onTap: () => _tip(
              LanguageService.tr('Total profit earned', 'মোট অর্জিত লাভ'),
              LanguageService.tr(
                  'All profit your investments have earned so far: matured profit plus what the current month has earned through yesterday.',
                  'এ পর্যন্ত আপনার বিনিয়োগের সব লাভ: মেয়াদপূর্ণ লাভ আর চলতি মাসে গতকাল পর্যন্ত জমা হওয়া লাভ।')),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [_emeraldBright, _emerald],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(LanguageService.tr('TOTAL PROFIT EARNED', 'মোট অর্জিত লাভ'),
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xC8FFFFFF), letterSpacing: 1.3)),
                    const SizedBox(width: 4),
                    Icon(Icons.info_outline_rounded, size: 13, color: Colors.white.withAlpha(200)),
                  ],
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_tk(earned),
                      style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                Text(
                  accruing > 0
                      ? LanguageService.tr('incl. ${_tk(accruing)} accruing this month', 'এর মধ্যে চলতি মাসে জমা হচ্ছে ${_tk(accruing)}')
                      : LanguageService.tr('across all your investments', 'আপনার সব বিনিয়োগ মিলিয়ে'),
                  style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(160)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            small(
              LanguageService.tr('Matured', 'মেয়াদপূর্ণ'),
              _tk(matured),
              LanguageService.tr('closed periods, payable', 'শেষ হওয়া সময়, প্রাপ্য'),
              _ink,
              LanguageService.tr(
                  'Profit for months (or project periods) that have closed. Matured profit is payable; it is paid in the project\'s next disbursement.',
                  'যে মাস (বা প্রজেক্টের সময়) শেষ হয়েছে তার লাভ। এটি প্রাপ্য; প্রজেক্টের পরবর্তী বণ্টনে পরিশোধ হয়।'),
            ),
            const SizedBox(width: 8),
            small(
              LanguageService.tr('Paid', 'পরিশোধিত'),
              _tk(paid),
              LanguageService.tr('confirmed by finance', 'ফাইন্যান্স নিশ্চিত করেছে'),
              _emerald,
              LanguageService.tr('Only profit the finance team has confirmed as transferred to your bank or mobile account.',
                  'শুধু যে লাভ ফাইন্যান্স টিম আপনার ব্যাংক বা মোবাইল অ্যাকাউন্টে পাঠানো নিশ্চিত করেছে।'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            small(
              LanguageService.tr('Pending payment', 'বাকি পরিশোধ'),
              _tk(pending),
              awaiting > 0
                  ? LanguageService.tr('${_tk(awaiting)} being paid now', '${_tk(awaiting)} এখন পরিশোধ হচ্ছে')
                  : approving > 0
                  ? LanguageService.tr('${_tk(approving)} being approved', '${_tk(approving)} অনুমোদন চলছে')
                  : LanguageService.tr('matured, not yet paid', 'মেয়াদপূর্ণ, এখনো দেওয়া হয়নি'),
              BC.chart4Deep,
              LanguageService.tr('Matured profit that hasn\'t been confirmed as paid yet. Matured = paid + pending.',
                  'মেয়াদপূর্ণ লাভ যা এখনো পরিশোধ নিশ্চিত হয়নি। মেয়াদপূর্ণ = পরিশোধিত + বাকি।'),
            ),
            const SizedBox(width: 8),
            small(
              LanguageService.tr('Upcoming estimate', 'আসন্ন আনুমানিক'),
              _upcoming.isEmpty ? '—' : _tk(_s('upcomingEstimateBdt')),
              upcomingMonth != null
                  ? LanguageService.tr('estimate for ${_periodLabel(upcomingMonth, upcomingMonth)} · not guaranteed',
                  '${_periodLabel(upcomingMonth, upcomingMonth)} এর আনুমানিক · নিশ্চিত নয়')
                  : LanguageService.tr('no estimate available', 'কোনো অনুমান নেই'),
              _muted,
              LanguageService.tr(
                  'An estimate of this month\'s profit at your agreed rate if your investments stay active until month end. It is not a confirmed amount and isn\'t included in the totals. Profit-share projects have no estimate: their profit is known only once the period is calculated.',
                  'আপনার বিনিয়োগ মাস শেষ পর্যন্ত চালু থাকলে চুক্তির হারে এই মাসের আনুমানিক লাভ। এটি নিশ্চিত নয় এবং মোট হিসাবে যোগ হয় না। মুনাফা-ভাগ প্রজেক্টের অনুমান নেই: হিসাবের পরেই জানা যায়।'),
              dashed: true,
            ),
          ],
        ),
        if (pending > 0.005) ...[
          const SizedBox(height: 6),
          Text(
            LanguageService.tr(
                'Pending breakdown: ${_tk(awaiting)} awaiting payment · ${_tk(approving)} being approved · ${_tk(notScheduled)} not yet in a disbursement.',
                'বাকির ভাগ: ${_tk(awaiting)} পরিশোধের অপেক্ষায় · ${_tk(approving)} অনুমোদন চলছে · ${_tk(notScheduled)} এখনো বণ্টনে নেই।'),
            style: const TextStyle(fontSize: 12, color: _muted, height: 1.4),
          ),
        ],
      ],
    );
  }

  void _tip(String title, String text) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 6),
              Text(text, style: const TextStyle(fontSize: 13.5, color: _muted, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Shared filter widgets ────────────────────────────────
  Widget _dropdown(String? value, String hint, List<(String, String)> items, ValueChanged<String?> onChanged) {
    return Expanded(
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: value,
            isExpanded: true,
            icon: const Icon(Icons.expand_more_rounded, size: 20, color: _muted),
            style: const TextStyle(fontSize: 12.5, color: _ink),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(hint, style: const TextStyle(fontSize: 12.5, color: _muted))),
              for (final i in items)
                DropdownMenuItem<String?>(
                    value: i.$1, child: Text(i.$2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _pager(int page, int totalPages, ValueChanged<int> go) {
    if (totalPages <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Text(LanguageService.tr('Page $page of $totalPages', 'পৃষ্ঠা $page / $totalPages'),
              style: const TextStyle(fontSize: 12.5, color: _muted)),
          const Spacer(),
          if (page > 1)
            OutlinedButton(
              onPressed: () => go(page - 1),
              style: OutlinedButton.styleFrom(
                  foregroundColor: _ink, side: const BorderSide(color: _line), visualDensity: VisualDensity.compact),
              child: Text(LanguageService.tr('Previous', 'আগের'), style: const TextStyle(fontSize: 12.5)),
            ),
          if (page < totalPages) ...[
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: () => go(page + 1),
              style: OutlinedButton.styleFrom(
                  foregroundColor: _ink, side: const BorderSide(color: _line), visualDensity: VisualDensity.compact),
              child: Text(LanguageService.tr('Next', 'পরের'), style: const TextStyle(fontSize: 12.5)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _link(String text, VoidCallback onTap) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: _emerald,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(0, 28),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
  );

  // ─── Records ──────────────────────────────────────────────
  Widget _recordsSection() {
    final filtered = _records
        .where((r) => (_rProject == null || r['projectId'] == _rProject) && (_rStatus == null || r['status'] == _rStatus))
        .toList();
    final totalPages = (filtered.length / _recordsPerPage).ceil().clamp(1, 100000);
    final page = _rPage.clamp(1, totalPages);
    final pageItems = filtered.skip((page - 1) * _recordsPerPage).take(_recordsPerPage).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          LanguageService.tr('Profit by project and period', 'প্রজেক্ট ও সময় অনুযায়ী লাভ'),
          sub: LanguageService.tr(
              'One row per month (fixed-rate projects) or calculated period (profit-share projects).',
              'প্রতি মাসে এক সারি (নির্দিষ্ট হার) বা হিসাবকৃত সময় (মুনাফা ভাগ)।'),
        ),
        Row(
          children: [
            _dropdown(_rProject, LanguageService.tr('All projects', 'সব প্রজেক্ট'), _projects,
                    (v) => setState(() {
                  _rProject = v;
                  _rPage = 1;
                })),
            const SizedBox(width: 8),
            _dropdown(
              _rStatus,
              LanguageService.tr('All statuses', 'সব অবস্থা'),
              [for (final s in _recordKeys) (s, _recordStatus(s).$1)],
                  (v) => setState(() {
                _rStatus = v;
                _rPage = 1;
              }),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (pageItems.isEmpty)
          _card(
            child: Text(LanguageService.tr('No profit records match these filters.', 'এই ফিল্টারে কোনো রেকর্ড নেই।'),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: _muted)),
          )
        else
          for (final r in pageItems) ...[
            _recordTile(r),
            const SizedBox(height: 8),
          ],
        _pager(page, totalPages, (p) => setState(() => _rPage = p)),
      ],
    );
  }

  Widget _recordTile(Map<String, dynamic> r) {
    final fixed = r['profitModel'] == 'FIXED_RATE';
    final days = r['eligibleDays'] as int;
    final running = r['kind'] == 'RUNNING';
    final receipt = (r['receiptNumber'] ?? '').toString();
    final invShort = receipt.isNotEmpty ? receipt : (r['investmentId'] as String).substring(0, 8).toUpperCase();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openRecord(r['id'] as String),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: running ? const Color(0xFF7DD3FC) : _line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r['projectTitle'] as String,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink, height: 1.3)),
                        Text(
                          '${_periodLabel(r['periodStart'], r['periodEnd'])} · $days ${LanguageService.tr(days == 1 ? 'day' : 'days', 'দিন')}${running ? LanguageService.tr(' so far', ' এ পর্যন্ত') : ''} · $invShort',
                          style: const TextStyle(fontSize: 11.5, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _badge(_recordStatus(r['status'] as String)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _mini(LanguageService.tr('Invested', 'বিনিয়োগ'), _tk(r['principalBdt'] as num)),
                  _mini(LanguageService.tr('Rate', 'হার'),
                      fixed ? _pct(r['annualRatePct'] as num) : LanguageService.tr('Profit share', 'মুনাফা ভাগ')),
                  _mini(LanguageService.tr('Calculated', 'হিসাবকৃত'), _tk(r['calculatedBdt'] as num), bold: true),
                  _mini(LanguageService.tr('Matures', 'প্রাপ্য হবে'), _fmtDay(r['maturesOn'])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mini(String label, String value, {bool bold = false}) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, color: _muted)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: bold ? _emerald : _ink)),
        ),
      ],
    ),
  );

  // ─── Payment history ──────────────────────────────────────
  List<Map<String, dynamic>> get _filteredPayments {
    final q = _q.text.trim().toLowerCase();
    final from = _hRange == null ? null : _hRange!.start.toIso8601String().substring(0, 10);
    final to = _hRange == null ? null : _hRange!.end.toIso8601String().substring(0, 10);
    return _payments.where((p) {
      final day = _dayKey(p['date']);
      if (from != null && day.compareTo(from) < 0) return false;
      if (to != null && day.compareTo(to) > 0) return false;
      if (_hProject != null && p['projectId'] != _hProject) return false;
      if (_hStatus != null && p['status'] != _hStatus) return false;
      if (q.isNotEmpty &&
          ![p['projectTitle'], p['paymentReference'] ?? '', p['receiptNumber'] ?? '']
              .any((s) => s.toString().toLowerCase().contains(q))) {
        return false;
      }
      return true;
    }).toList();
  }

  bool get _hasPaymentFilter =>
      _q.text.trim().isNotEmpty || _hRange != null || _hProject != null || _hStatus != null;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _hRange,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: _emerald)),
        child: child!,
      ),
    );
    if (r != null) {
      setState(() {
        _hRange = r;
        _hPage = 1;
      });
    }
  }

  Widget _paymentsSection() {
    final filtered = _filteredPayments;
    final paidTotal = filtered.where((p) => p['status'] == 'PAID').fold<double>(0, (s, p) => s + (p['amountBdt'] as num));
    final totalPages = (filtered.length / _paymentsPerPage).ceil().clamp(1, 100000);
    final page = _hPage.clamp(1, totalPages);
    final shown = filtered.skip((page - 1) * _paymentsPerPage).take(_paymentsPerPage).toList();
    String d(DateTime x) => '${x.day} ${_months[x.month - 1]}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          LanguageService.tr('Profit payment history', 'লাভ পরিশোধের ইতিহাস'),
          trailing: Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 12, color: _muted),
              children: [
                TextSpan(text: LanguageService.tr('Paid in this view: ', 'এই তালিকায় পরিশোধিত: ')),
                TextSpan(text: _tk(paidTotal), style: const TextStyle(fontWeight: FontWeight.w800, color: _emerald)),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: TextField(
            controller: _q,
            onChanged: (_) => setState(() => _hPage = 1),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: LanguageService.tr('Search project or reference', 'প্রজেক্ট বা রেফারেন্স খুঁজুন'),
              hintStyle: const TextStyle(fontSize: 12.5, color: _muted),
              prefixIcon: const Icon(Icons.search_rounded, size: 19, color: _muted),
              prefixIconConstraints: const BoxConstraints(minWidth: 34),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _line)),
              enabledBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _line)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _emerald)),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _dropdown(_hProject, LanguageService.tr('All projects', 'সব প্রজেক্ট'), _projects,
                    (v) => setState(() {
                  _hProject = v;
                  _hPage = 1;
                })),
            const SizedBox(width: 6),
            _dropdown(
              _hStatus,
              LanguageService.tr('All statuses', 'সব অবস্থা'),
              [for (final k in _payoutKeys) (k, _payoutStatus(k).$1)],
                  (v) => setState(() {
                _hStatus = v;
                _hPage = 1;
              }),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range_rounded, size: 17),
                label: Text(
                  _hRange == null
                      ? LanguageService.tr('Any date', 'যেকোনো তারিখ')
                      : '${d(_hRange!.start)} – ${d(_hRange!.end)} ${_hRange!.end.year}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: _line),
                  minimumSize: const Size(0, 34),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            if (_hasPaymentFilter)
              _link(LanguageService.tr('Clear', 'মুছুন'), () {
                setState(() {
                  _q.clear();
                  _hRange = null;
                  _hProject = null;
                  _hStatus = null;
                  _hPage = 1;
                });
              }),
          ],
        ),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          _card(
            child: Text(
              _payments.isEmpty
                  ? LanguageService.tr('No profit has been disbursed to you yet.', 'এখনো কোনো লাভ পাঠানো হয়নি।')
                  : LanguageService.tr('No payments match these filters.', 'এই ফিল্টারে কোনো পেমেন্ট নেই।'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: _muted),
            ),
          )
        else
          _card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (int i = 0; i < shown.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: _line),
                  _paymentRow(shown[i]),
                ],
              ],
            ),
          ),
        const SizedBox(height: 4),
        _pager(page, totalPages, (p) => setState(() => _hPage = p)),
      ],
    );
  }

  Widget _paymentRow(Map<String, dynamic> p) {
    final st = _payoutStatus(p['status'] as String);
    final ref = (p['paymentReference'] ?? '').toString();
    final period = p['periodStart'] != null && p['periodEnd'] != null ? _periodLabel(p['periodStart'], p['periodEnd']) : '—';
    final recordId = (p['recordId'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['projectTitle'] as String,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink, height: 1.3)),
                    Text(
                      '${_fmtDay(p['date'])} · ${LanguageService.tr('period', 'সময়')} $period',
                      style: const TextStyle(fontSize: 11.5, color: _muted),
                    ),
                    Text(
                      _methodLabel(p['paymentMethod'] as String?),
                      style: const TextStyle(fontSize: 11.5, color: _muted),
                    ),
                    if (ref.isNotEmpty)
                      SelectableText(ref, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: _muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_tk(p['amountBdt'] as num),
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _ink)),
                  const SizedBox(height: 3),
                  _badge(st),
                ],
              ),
            ],
          ),
          Row(
            children: [
              if (recordId.isNotEmpty) _link(LanguageService.tr('Details', 'বিস্তারিত'), () => _openRecord(recordId)),
              _link(
                LanguageService.tr('Report an issue', 'সমস্যা জানান'),
                    () {
                  final rec = _records.where((r) => r['id'] == recordId).toList();
                  _report(payment: {...p, 'statusLabel': st.$1}, record: rec.isEmpty ? null : rec.first);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Issues ───────────────────────────────────────────────
  Widget _issuesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          LanguageService.tr('My calculation issues', 'আমার জানানো সমস্যা'),
          sub: LanguageService.tr('Profit issues you reported to the Help Center.', 'হেল্প সেন্টারে জানানো লাভের সমস্যা।'),
          trailing: _link(LanguageService.tr('Open Help Center →', 'হেল্প সেন্টার →'), () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpCenterPage())).then((_) => _load());
          }),
        ),
        if (_issues.isEmpty)
          _card(
            child: Text(
                LanguageService.tr("You haven't reported any calculation issues.", 'আপনি কোনো হিসাবের সমস্যা জানাননি।'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: _muted)),
          )
        else
          _card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (int i = 0; i < _issues.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: _line),
                  _issueRow(_issues[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _issueRow(Map<String, dynamic> t) {
    final ctx = Map<String, dynamic>.from((t['context'] as Map?) ?? {});
    final status = t['status'] as String;
    final (label, color, soft) = switch (status) {
      'OPEN' => (LanguageService.tr('Open', 'খোলা'), _lapis, _lapisSoft),
      'IN_REVIEW' => (LanguageService.tr('In review', 'পর্যালোচনায়'), BC.chart4Deep, BC.chart4Muted),
      'WAITING_FOR_INVESTOR' => (LanguageService.tr('Waiting for you', 'আপনার উত্তরের অপেক্ষায়'), _danger, _dangerSoft),
      'RESOLVED' => (LanguageService.tr('Resolved', 'সমাধান হয়েছে'), _emerald, _emeraldSoft),
      'CLOSED' => (LanguageService.tr('Closed', 'বন্ধ'), _muted, _ivory),
      _ => (status, _muted, _ivory),
    };
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TicketDetailPage(ticketId: t['id'] as String)),
      ).then((_) => _load()),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t['subject']?.toString() ?? '',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
                  Text(
                    [
                      t['reference']?.toString() ?? '',
                      if ((ctx['projectTitle'] ?? '').toString().isNotEmpty) ctx['projectTitle'].toString(),
                      if (ctx['periodStart'] != null && ctx['periodEnd'] != null)
                        _periodLabel(ctx['periodStart'], ctx['periodEnd']),
                      '${LanguageService.tr('updated', 'আপডেট')} ${_fmtDay(t['lastActivityAt'])}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11.5, color: _muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _badge((label, color, soft)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 2) PROFIT STATEMENT — ekta record, hishab shoho
// ═══════════════════════════════════════════════════════════
class ProfitRecordPage extends StatefulWidget {
  final String recordId;

  const ProfitRecordPage({super.key, required this.recordId});

  @override
  State<ProfitRecordPage> createState() => _ProfitRecordPageState();
}

class _ProfitRecordPageState extends State<ProfitRecordPage> {
  bool _loading = true;
  bool _failed = false;
  String _userId = '';
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    if (_userId.isEmpty) {
      final u = await AuthService.getUserData();
      _userId = u?['id']?.toString() ?? '';
    }
    final d = _userId.isEmpty ? null : await DatabaseService.getInvestorProfitRecord(_userId, widget.recordId);
    if (!mounted) return;
    setState(() {
      _failed = d?['error'] == 'network';
      _data = (d == null || _failed) ? null : d;
      _loading = false;
    });
  }

  Future<void> _report() async {
    final r = _data!['record'] as Map<String, dynamic>;
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => NewTicketPage(profitTopic: true, record: r)),
    );
    if (id != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => TicketDetailPage(ticketId: id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: _ivory,
          appBar: _appBar(LanguageService.tr('Profit statement', 'লাভের বিবরণী')),
          body: _loading
              ? const Center(
              child: SizedBox(
                  width: 26, height: 26, child: CircularProgressIndicator(color: _emerald, strokeWidth: 2.4)))
              : _failed
              ? _message(
              Icons.wifi_off_rounded,
              LanguageService.tr('Could not load this record', 'রেকর্ডটি লোড করা যায়নি'),
              LanguageService.tr('Please check your internet connection.', 'ইন্টারনেট সংযোগ চেক করুন।'),
              LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
              _load)
              : _data == null
              ? _message(Icons.search_off_rounded, LanguageService.tr('Record not found', 'রেকর্ড পাওয়া যায়নি'),
              null, LanguageService.tr('Go back', 'ফিরে যান'), () => Navigator.pop(context))
              : RefreshIndicator(
            onRefresh: _load,
            color: _emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 2, 16, 24 + MediaQuery.of(context).padding.bottom),
              children: _content(),
            ),
          ),
        );
      },
    );
  }

  Widget _row(String k, String v, {bool strong = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3.5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(k, style: const TextStyle(fontSize: 12.5, color: _muted))),
        const SizedBox(width: 10),
        Flexible(
          child: Text(v,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: strong ? 13 : 12,
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
                  color: color ?? (strong ? _emerald : _ink))),
        ),
      ],
    ),
  );

  List<Widget> _content() {
    final r = Map<String, dynamic>.from(_data!['record'] as Map);
    final info = Map<String, dynamic>.from(_data!['info'] as Map);
    final fixed = ((_data!['fixed'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final period = _data!['period'] == null ? null : Map<String, dynamic>.from(_data!['period'] as Map);
    final payments = ((r['payments'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final installments = ((info['installments'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final status = r['status'] as String;
    final running = r['kind'] == 'RUNNING';
    final receipt = (r['receiptNumber'] ?? '').toString();

    return [
      // ── Header
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [_emeraldBright, _emerald],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(r['projectTitle'] as String,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white, height: 1.3)),
                ),
                const SizedBox(width: 8),
                _badge(_recordStatus(status)),
              ],
            ),
            Text(
              '${_periodLabel(r['periodStart'], r['periodEnd'])} · ${r['eligibleDays']} ${LanguageService.tr('days', 'দিন')}${running ? LanguageService.tr(' so far', ' এ পর্যন্ত') : ''}',
              style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(170)),
            ),
            const SizedBox(height: 10),
            Text(
                running
                    ? LanguageService.tr('EARNED SO FAR', 'এ পর্যন্ত অর্জিত')
                    : LanguageService.tr('CALCULATED PROFIT', 'হিসাবকৃত লাভ'),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xC8FFFFFF), letterSpacing: 1.2)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(_tk(r['calculatedBdt'] as num),
                  style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text('${LanguageService.tr('Paid', 'পরিশোধিত')} ${_tk(r['paidBdt'] as num)}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: BC.brand300)),
                ),
                Text('${LanguageService.tr('Outstanding', 'বাকি')} ${_tk(r['outstandingBdt'] as num)}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(color: Colors.white.withAlpha(18), borderRadius: BorderRadius.circular(9)),
              child: Text(
                '${_recordHelp(status)} ${LanguageService.tr('Payable from', 'প্রাপ্য হবে')} ${_fmtDay(r['maturesOn'])}.',
                style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(200), height: 1.4),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),

      // ── Investment
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(LanguageService.tr('Investment', 'বিনিয়োগ')),
            _row(LanguageService.tr('Investment ID', 'বিনিয়োগ আইডি'),
                receipt.isNotEmpty ? receipt : (r['investmentId'] as String).substring(0, 8).toUpperCase()),
            _row(LanguageService.tr('Profit-eligible capital', 'লাভযোগ্য মূলধন'), _tk(r['principalBdt'] as num)),
            if (r['profitModel'] == 'FIXED_RATE')
              _row(
                LanguageService.tr('Agreed annual rate', 'চুক্তির বার্ষিক হার'),
                r['rateMaxPct'] != null
                    ? '${_pct(r['annualRatePct'] as num)} – ${_pct(r['rateMaxPct'] as num)}'
                    : _pct(r['annualRatePct'] as num),
              ),
            if ((info['annualProfitBdt'] as num? ?? 0) > 0)
              _row(LanguageService.tr('Annual profit', 'বার্ষিক লাভ'), _tk(info['annualProfitBdt'] as num)),
            _row(LanguageService.tr('Invested on', 'বিনিয়োগের তারিখ'), _fmtDay(info['investedAt'])),
            if (info['activatedAt'] != null) _row(LanguageService.tr('Activated', 'চালু'), _fmtDay(info['activatedAt'])),
            _row(LanguageService.tr('Profit earns from', 'লাভ শুরু'), _fmtDay(info['earningFrom'])),
            if (info['earningTo'] != null) _row(LanguageService.tr('Last earning day', 'লাভের শেষ দিন'), _fmtDay(info['earningTo'])),
            if (info['contractMaturity'] != null)
              _row(LanguageService.tr('Contract maturity', 'চুক্তির মেয়াদ শেষ'), _fmtDay(info['contractMaturity'])),
            _row(
              LanguageService.tr('Payment plan', 'পেমেন্টের ধরন'),
              info['paymentPlan'] == 'INSTALLMENT'
                  ? LanguageService.tr('Installments', 'কিস্তি')
                  : LanguageService.tr('Paid in full', 'একবারে'),
            ),
            if (installments.length > 1) ...[
              const SizedBox(height: 4),
              for (final p in installments)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text(
                    '• ${_tk(p['amountBdt'] as num)} · ${p['method'] ?? ''} · ${_fmtDay(p['approvedAt'])}',
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 10),

      // ── Calculation
      if (fixed.isNotEmpty)
        for (final f in fixed) ...[
          _fixedCard(f),
          const SizedBox(height: 10),
        ],
      if (period != null) ...[
        _periodCard(period),
        const SizedBox(height: 10),
      ],

      // ── Payouts
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(LanguageService.tr('Payments for this record', 'এই রেকর্ডের পরিশোধ')),
            if (payments.isEmpty)
              Text(
                running
                    ? LanguageService.tr('This month is still running. It becomes payable when it closes.',
                    'এই মাস এখনো চলছে। শেষ হলে প্রাপ্য হবে।')
                    : LanguageService.tr('Not yet in a disbursement. It is paid in the project\'s next disbursement.',
                    'এখনো কোনো বণ্টনে নেই। প্রজেক্টের পরবর্তী বণ্টনে পরিশোধ হবে।'),
                style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.4),
              )
            else
              for (final p in payments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_tk(p['amountBdt'] as num),
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _ink)),
                            Text(
                              [
                                _methodLabel(p['paymentMethod'] as String?),
                                if (p['paidAt'] != null) _fmtDay(p['paidAt']),
                                if ((p['paymentReference'] ?? '').toString().isNotEmpty) p['paymentReference'].toString(),
                              ].join(' · '),
                              style: const TextStyle(fontSize: 11.5, color: _muted),
                            ),
                          ],
                        ),
                      ),
                      _badge(_payoutStatus(p['status'] as String)),
                    ],
                  ),
                ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      _helpCard(
        context,
        title: LanguageService.tr('Need help with this record?', 'এই রেকর্ড নিয়ে সাহায্য লাগবে?'),
        text: LanguageService.tr('Report a calculation issue and this record\'s details are sent with it, or call us.',
            'হিসাবের সমস্যা জানান — এই রেকর্ডের তথ্য সাথে যাবে, অথবা আমাদের কল করুন।'),
        onReport: _report,
      ),
    ];
  }

  /// Website er fixedRateBreakdown: annual ÷ 12 → ÷ mash er din → × din
  Widget _fixedCard(Map<String, dynamic> f) {
    final topup = f['label'] == 'TOPUP';
    final rounding = (f['roundingPaisa'] as num).toInt();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            topup
                ? LanguageService.tr('Realised-rate top-up to ${_pct(f['toRatePct'] as num)}',
                'প্রকৃত হারে টপ-আপ (${_pct(f['toRatePct'] as num)})')
                : LanguageService.tr('Agreed profit — how it was calculated', 'চুক্তির লাভ — কীভাবে হিসাব হয়েছে'),
          ),
          _row(LanguageService.tr('Capital', 'মূলধন'), _tk(f['principalBdt'] as num)),
          _row(topup ? LanguageService.tr('Extra annual rate', 'অতিরিক্ত বার্ষিক হার') : LanguageService.tr('Annual rate', 'বার্ষিক হার'),
              _pct(f['ratePct'] as num)),
          _row(LanguageService.tr('Annual profit', 'বার্ষিক লাভ'), _tk(f['annualProfitBdt'] as num)),
          _row(LanguageService.tr('Monthly (÷ 12)', 'মাসিক (÷ ১২)'), _tk4(f['monthlyProfit'] as num)),
          _row(LanguageService.tr('Daily (÷ ${f['daysInMonth']} days in month)', 'দৈনিক (÷ মাসের ${f['daysInMonth']} দিন)'),
              _tk4(f['dailyProfit'] as num)),
          _row(
            LanguageService.tr('× ${f['eligibleDays']} earning days', '× ${f['eligibleDays']} লাভের দিন'),
            _tk4(f['exactPeriodProfit'] as num),
          ),
          const Divider(height: 14, color: _line),
          _row(LanguageService.tr('Recorded', 'রেকর্ড করা'), _tk(f['amountBdt'] as num), strong: true),
          if (rounding != 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                LanguageService.tr(
                    '${rounding > 0 ? '+' : ''}$rounding paisa from carried rounding — the engine rounds the running total, so the next month evens it out.',
                    'চলমান মোট রাউন্ড করার কারণে ${rounding > 0 ? '+' : ''}$rounding পয়সা — পরের মাসে মিলে যায়।'),
                style: const TextStyle(fontSize: 11.5, color: _muted, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }

  /// Website er projectShareBreakdown: investor pool, capital × din onujayi bhag
  Widget _periodCard(Map<String, dynamic> p) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(LanguageService.tr('Profit share — how it was split', 'মুনাফা ভাগ — কীভাবে ভাগ হয়েছে')),
          _row(LanguageService.tr('Period', 'সময়কাল'), _periodLabel(p['periodStart'], p['periodEnd'])),
          _row(LanguageService.tr('Revenue', 'আয়'), _tk(p['revenueBdt'] as num)),
          _row(LanguageService.tr('Expenses', 'খরচ'), _tk(p['expensesBdt'] as num)),
          _row(LanguageService.tr('Net profit', 'নিট লাভ'), _tk(p['netProfitBdt'] as num)),
          _row(LanguageService.tr('Investors\' share', 'বিনিয়োগকারীদের ভাগ'), _pct(p['investorSharePct'] as num)),
          _row(LanguageService.tr('Investors\' pool', 'বিনিয়োগকারীদের পুল'), _tk(p['poolBdt'] as num)),
          const Divider(height: 14, color: _line),
          _row(LanguageService.tr('Your capital', 'আপনার মূলধন'), _tk(p['principalBdt'] as num)),
          _row(LanguageService.tr('Days invested in the period', 'এই সময়ে বিনিয়োগের দিন'), '${p['activeDays']}'),
          _row(
            LanguageService.tr('Your share (capital × days)', 'আপনার ভাগ (মূলধন × দিন)'),
            '${(p['sharePct'] as num).toStringAsFixed(4)}% · ${p['investorCount']} ${LanguageService.tr('investments', 'বিনিয়োগ')}',
          ),
          const Divider(height: 14, color: _line),
          _row(LanguageService.tr('Recorded', 'রেকর্ড করা'), _tk(p['amountBdt'] as num), strong: true),
          if (p['calculated'] != true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                LanguageService.tr('This amount was entered by the finance team, not from the share above.',
                    'এই পরিমাণটি ফাইন্যান্স টিম দিয়েছে, উপরের ভাগ থেকে নয়।'),
                style: const TextStyle(fontSize: 11.5, color: _muted, height: 1.4),
              ),
            ),
          if ((p['notes'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(p['notes'].toString(), style: const TextStyle(fontSize: 12.5, color: _ink, height: 1.4)),
          ],
        ],
      ),
    );
  }
}