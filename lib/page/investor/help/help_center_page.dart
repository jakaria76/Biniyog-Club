import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import '../../authentication/login_page.dart';
import '../../../theme/app_colors.dart';

// ═══════════════════════════════════════════════════════════
// HELP CENTER — website er /dashboard/help er motoi:
//  • My requests (status filter + page)
//  • New request (category, subject, details, ichchha hole investment)
//  • Request er conversation + reply (CLOSED hole reply na)
// Data: support_tickets / support_ticket_messages (website er ek-i table)
// ═══════════════════════════════════════════════════════════

// ─── Palette — website er rong (lib/theme/app_colors.dart) ───
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

// Website er SUPPORT_CONTACT (settings page er moto ek-i tottho)
const String _hotlineDisplay = '+880 1335-149033';
const String _hotlineTel = 'tel:+8801335149033';
const String _supportEmail = 'info@biniyogclub.com';

const List<String> _statuses = ['OPEN', 'IN_REVIEW', 'WAITING_FOR_INVESTOR', 'RESOLVED', 'CLOSED'];

/// Website er lib/support/tickets.ts — PROFIT_ISSUE_CATEGORIES
const List<String> _profitCategories = [
  'PROFIT_CALCULATION_DISCREPANCY',
  'INCORRECT_PROFIT_AMOUNT',
  'INCORRECT_CALCULATION_DATE',
  'MISSING_PROFIT_RECORD',
  'PAYMENT_STATUS_ISSUE',
  'MISSING_PROFIT_DISTRIBUTION',
  'OTHER_PROFIT_ISSUE',
];

/// TICKET_CATEGORIES = profit er gulo + GENERAL (website er order)
const List<String> _categories = [..._profitCategories, 'GENERAL'];

bool _isProfitCategory(String c) => _profitCategories.contains(c);

/// Website er CATEGORY_LABEL
String _categoryLabel(String c) {
  switch (c) {
    case 'PROFIT_CALCULATION_DISCREPANCY':
      return LanguageService.tr('Profit calculation discrepancy', 'লাভের হিসাবে গরমিল');
    case 'INCORRECT_PROFIT_AMOUNT':
      return LanguageService.tr('Incorrect profit amount', 'লাভের পরিমাণ ভুল');
    case 'INCORRECT_CALCULATION_DATE':
      return LanguageService.tr('Incorrect calculation date', 'হিসাবের তারিখ ভুল');
    case 'MISSING_PROFIT_RECORD':
      return LanguageService.tr('Missing profit record', 'লাভের রেকর্ড নেই');
    case 'PAYMENT_STATUS_ISSUE':
      return LanguageService.tr('Payment status issue', 'পেমেন্টের অবস্থা নিয়ে সমস্যা');
    case 'MISSING_PROFIT_DISTRIBUTION':
      return LanguageService.tr('Missing profit distribution', 'লাভ বণ্টন পাইনি');
    case 'OTHER_PROFIT_ISSUE':
      return LanguageService.tr('Other profit-related issue', 'লাভ নিয়ে অন্য সমস্যা');
    case 'GENERAL':
      return LanguageService.tr('General question', 'সাধারণ প্রশ্ন');
    default:
      return c.isEmpty ? '—' : c;
  }
}

(String, Color, Color, String) _statusMeta(String s) {
  switch (s) {
    case 'OPEN':
      return (LanguageService.tr('Open', 'খোলা'), _lapis, _lapisSoft,
      LanguageService.tr('Received. A support officer will review it.',
          'পাওয়া গেছে। একজন সাপোর্ট অফিসার দেখবেন।'));
    case 'IN_REVIEW':
      return (LanguageService.tr('In review', 'পর্যালোচনায়'), BC.chart4Deep, BC.chart4Muted,
      LanguageService.tr('A support officer is looking into it.', 'একজন সাপোর্ট অফিসার বিষয়টি দেখছেন।'));
    case 'WAITING_FOR_INVESTOR':
      return (LanguageService.tr('Waiting for you', 'আপনার উত্তরের অপেক্ষায়'), _danger, _dangerSoft,
      LanguageService.tr('Support needs more information from you. Please reply.',
          'সাপোর্টের আপনার কাছ থেকে আরও তথ্য দরকার। উত্তর দিন।'));
    case 'RESOLVED':
      return (LanguageService.tr('Resolved', 'সমাধান হয়েছে'), _emerald, _emeraldSoft,
      LanguageService.tr("Support has resolved this. Reply if it isn't sorted.",
          'সাপোর্ট এটি সমাধান করেছে। ঠিক না হলে উত্তর দিন।'));
    case 'CLOSED':
      return (LanguageService.tr('Closed', 'বন্ধ'), _muted, _ivory,
      LanguageService.tr('This request is closed.', 'অনুরোধটি বন্ধ।'));
    default:
      return (s.isEmpty ? '—' : s, _muted, _ivory, '');
  }
}

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// DB er UTC tarikh → Dhaka (website er moto "8 Nov 2026, 09:28")
DateTime? _dhaka(dynamic s) {
  final raw = s?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  // Shudhu tarikh (period) — sheta-i Dhaka er din
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    final p = raw.split('-').map(int.parse).toList();
    return DateTime.utc(p[0], p[1], p[2]);
  }
  var t = raw.replaceFirst(' ', 'T');
  if (t.contains('T') && !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(t)) t = '${t}Z';
  final d = DateTime.tryParse(t);
  return d?.toUtc().add(const Duration(hours: 6));
}

String _fmtDay(dynamic s) {
  final d = _dhaka(s);
  if (d == null) return '—';
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

String _fmtWhen(dynamic s) {
  final d = _dhaka(s);
  if (d == null) return '—';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.day} ${_months[d.month - 1]} ${d.year}, ${two(d.hour)}:${two(d.minute)}';
}

String _fmtTk(double v) {
  final s = v.toStringAsFixed(0);
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '৳$b';
}

Future<void> _launch(BuildContext context, String url) async {
  bool ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(LanguageService.tr('Could not open. Please try again.', 'খোলা যায়নি। আবার চেষ্টা করুন।')),
      backgroundColor: _danger,
    ));
  }
}

PreferredSizeWidget _appBar(String title, {List<Widget>? actions}) => AppBar(
  backgroundColor: _ivory,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  toolbarHeight: 54,
  iconTheme: const IconThemeData(color: _ink),
  title: Text(title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 17.5)),
  actions: actions,
);

Widget _statusBadge(String status) {
  final m = _statusMeta(status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: m.$3, borderRadius: BorderRadius.circular(20)),
    child: Text(m.$1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: m.$2)),
  );
}

Widget _message(IconData icon, String title, String? sub, String btn, VoidCallback onTap) {
  return Center(
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
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(btn),
          ),
        ],
      ),
    ),
  );
}

void _goLogin(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
  );
}

/// Website er CallHelpCenter — hotline, email, office time
class _ContactCard extends StatelessWidget {
  const _ContactCard();

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String label, String url, Color c) => Expanded(
      child: OutlinedButton.icon(
        onPressed: () => _launch(context, url),
        icon: Icon(icon, size: 17),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side: BorderSide(color: c.withAlpha(90)),
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );

    return Container(
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
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(22),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white.withAlpha(60)),
                ),
                child: const Icon(Icons.support_agent_rounded, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(LanguageService.tr('Call the Help Center', 'হেল্প সেন্টারে কল করুন'),
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white)),
                    Text(
                      LanguageService.tr('Saturday – Thursday, 9:00 AM – 6:00 PM (Friday closed)',
                          'শনিবার – বৃহস্পতিবার, সকাল ৯টা – সন্ধ্যা ৬টা (শুক্রবার বন্ধ)'),
                      style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(170)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                btn(Icons.call_rounded, _hotlineDisplay, _hotlineTel, _emerald),
                const SizedBox(width: 8),
                btn(Icons.mail_outline_rounded, _supportEmail, 'mailto:$_supportEmail', _lapis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 1) HELP CENTER — my requests
// ═══════════════════════════════════════════════════════════
class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key});

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  bool _loading = true;
  bool _needsLogin = false;
  bool _failed = false;
  String _userId = '';
  String? _status;
  int _page = 1;
  int _total = 0;
  int _totalPages = 1;
  List<Map<String, dynamic>> _items = [];

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
    if (_userId.isEmpty) {
      if (mounted) {
        setState(() {
          _needsLogin = true;
          _loading = false;
        });
      }
      return;
    }
    final res = await DatabaseService.getInvestorTickets(_userId, status: _status, page: _page);
    if (!mounted) return;
    setState(() {
      _failed = res['ok'] != true;
      _items = (res['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _total = res['total'] as int? ?? 0;
      _totalPages = res['totalPages'] as int? ?? 1;
      _loading = false;
    });
  }

  void _setStatus(String? s) {
    setState(() {
      _status = s;
      _page = 1;
    });
    _load();
  }

  Future<void> _newRequest() async {
    final id = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const NewTicketPage()));
    if (!mounted) return;
    _page = 1;
    _status = null;
    await _load();
    if (id != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => TicketDetailPage(ticketId: id)))
          .then((_) => _load());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: _ivory,
          appBar: _appBar(LanguageService.tr('Help Center', 'হেল্প সেন্টার')),
          floatingActionButton: _needsLogin || _failed
              ? null
              : FloatingActionButton.extended(
            onPressed: _newRequest,
            backgroundColor: _emerald,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text(LanguageService.tr('New request', 'নতুন অনুরোধ'),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          body: _loading
              ? const Center(
              child: SizedBox(
                  width: 26, height: 26, child: CircularProgressIndicator(color: _emerald, strokeWidth: 2.4)))
              : _needsLogin
              ? _message(Icons.lock_outline_rounded,
              LanguageService.tr('Please log in to use the Help Center', 'হেল্প সেন্টার ব্যবহার করতে লগইন করুন'),
              null, LanguageService.tr('Log in', 'লগইন'), () => _goLogin(context))
              : _failed
              ? _message(
              Icons.wifi_off_rounded,
              LanguageService.tr('Could not load your requests', 'অনুরোধগুলো লোড করা যায়নি'),
              LanguageService.tr('Please check your internet connection.', 'ইন্টারনেট সংযোগ চেক করুন।'),
              LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
              _load)
              : RefreshIndicator(
            onRefresh: _load,
            color: _emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 2, 16, 90 + MediaQuery.of(context).padding.bottom),
              children: [
                Text(
                  LanguageService.tr(
                      'Report a profit calculation issue or ask a question, and follow the answer here.',
                      'লাভের হিসাবের সমস্যা জানান বা প্রশ্ন করুন, আর উত্তর এখানেই দেখুন।'),
                  style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.4),
                ),
                const SizedBox(height: 10),
                const _ContactCard(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(LanguageService.tr('MY REQUESTS', 'আমার অনুরোধ'),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _muted,
                            letterSpacing: 1)),
                    const SizedBox(width: 6),
                    Text('($_total)', style: const TextStyle(fontSize: 12, color: _muted)),
                  ],
                ),
                const SizedBox(height: 8),
                _filterBar(),
                const SizedBox(height: 10),
                if (_items.isEmpty)
                  _empty()
                else
                  for (final t in _items) ...[
                    _ticketCard(t),
                    const SizedBox(height: 8),
                  ],
                if (_totalPages > 1) _pager(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _filterBar() {
    final filters = <(String?, String)>[
      (null, LanguageService.tr('All', 'সব')),
      for (final s in _statuses) (s, _statusMeta(s).$1),
    ];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final f = filters[i];
          final sel = _status == f.$1;
          return GestureDetector(
            onTap: () => _setStatus(f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? _emerald : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? _emerald : _line),
              ),
              child: Text(f.$2,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? Colors.white : _ink)),
            ),
          );
        },
      ),
    );
  }

  Widget _ticketCard(Map<String, dynamic> t) {
    final ctx = t['context'] as Map<String, dynamic>;
    final project = ctx['projectTitle']?.toString() ?? '';
    final reply = t['latestReply']?.toString();
    final subject = t['subject']?.toString() ?? '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TicketDetailPage(ticketId: t['id'] as String)),
        ).then((_) => _load()),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t['status'] == 'WAITING_FOR_INVESTOR' ? _danger.withAlpha(110) : _line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(t['reference']?.toString() ?? '',
                        style: const TextStyle(
                            fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w700, color: _emerald)),
                  ),
                  _statusBadge(t['status'] as String),
                ],
              ),
              const SizedBox(height: 5),
              Text(_categoryLabel(t['category'] as String),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink, height: 1.3)),
              if (subject.isNotEmpty)
                Text(subject, style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.35)),
              if (project.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.folder_open_rounded, size: 14, color: _emerald),
                    const SizedBox(width: 4),
                    Expanded(child: Text(project, style: const TextStyle(fontSize: 12, color: _ink))),
                  ],
                ),
              ],
              const SizedBox(height: 7),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(color: _ivory, borderRadius: BorderRadius.circular(9)),
                child: Text(
                  reply == null || reply.isEmpty
                      ? LanguageService.tr('Awaiting review', 'পর্যালোচনার অপেক্ষায়')
                      : '${LanguageService.tr('Support', 'সাপোর্ট')}: $reply',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: reply == null ? _muted : _ink,
                      fontStyle: reply == null ? FontStyle.italic : FontStyle.normal,
                      height: 1.35),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${LanguageService.tr('Submitted', 'জমা')} ${_fmtDay(t['createdAt'])} · '
                    '${LanguageService.tr('Updated', 'আপডেট')} ${_fmtDay(t['lastActivityAt'])}',
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(color: _emeraldSoft, shape: BoxShape.circle),
            child: const Icon(Icons.support_agent_rounded, size: 20, color: _emerald),
          ),
          const SizedBox(height: 10),
          Text(
            _status != null
                ? LanguageService.tr('No requests with this status.', 'এই অবস্থায় কোনো অনুরোধ নেই।')
                : LanguageService.tr("You haven't contacted the Help Center yet.", 'আপনি এখনো হেল্প সেন্টারে যোগাযোগ করেননি।'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _ink),
          ),
        ],
      ),
    );
  }

  Widget _pager() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text(LanguageService.tr('Page $_page of $_totalPages', 'পৃষ্ঠা $_page / $_totalPages'),
              style: const TextStyle(fontSize: 12.5, color: _muted)),
          const Spacer(),
          if (_page > 1)
            OutlinedButton(
              onPressed: () {
                setState(() => _page--);
                _load();
              },
              style: OutlinedButton.styleFrom(
                  foregroundColor: _ink, side: const BorderSide(color: _line), visualDensity: VisualDensity.compact),
              child: Text(LanguageService.tr('Previous', 'আগের'), style: const TextStyle(fontSize: 12.5)),
            ),
          if (_page < _totalPages) ...[
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: () {
                setState(() => _page++);
                _load();
              },
              style: OutlinedButton.styleFrom(
                  foregroundColor: _ink, side: const BorderSide(color: _line), visualDensity: VisualDensity.compact),
              child: Text(LanguageService.tr('Next', 'পরের'), style: const TextStyle(fontSize: 12.5)),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 2) NEW REQUEST
// ═══════════════════════════════════════════════════════════
class NewTicketPage extends StatefulWidget {
  /// Profit er bishoy theke khulle — default category profit issue
  final bool profitTopic;

  /// Profit Returns er record (getInvestorProfitRecord er 'record') — tottho nijei jog hoy
  final Map<String, dynamic>? record;

  /// Profit payout (distribution line) er id + tar tottho
  final Map<String, dynamic>? payment;

  const NewTicketPage({super.key, this.profitTopic = false, this.record, this.payment});

  @override
  State<NewTicketPage> createState() => _NewTicketPageState();
}

class _NewTicketPageState extends State<NewTicketPage> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _expected = TextEditingController();
  // Website er motoi: shudhu payout hole PAYMENT_STATUS_ISSUE, record/profit hole calculation
  late String _category = widget.payment != null && widget.record == null
      ? 'PAYMENT_STATUS_ISSUE'
      : (widget.profitTopic || widget.record != null)
      ? 'PROFIT_CALCULATION_DISCREPANCY'
      : 'GENERAL';
  String? _investmentId;
  List<Map<String, dynamic>> _investments = [];
  String _userId = '';
  bool _submitting = false;
  String? _error;

  bool get _profitCategory => _isProfitCategory(_category);

  /// Website er "Attached automatically" — record / payout er tottho
  List<(String, String)> get _attached {
    final r = widget.record;
    final p = widget.payment;
    return [
      if (r != null) ...[
        (LanguageService.tr('Project', 'প্রজেক্ট'), r['projectTitle']?.toString() ?? '—'),
        if ((r['receiptNumber'] ?? '').toString().isNotEmpty)
          (LanguageService.tr('Investment ID', 'বিনিয়োগ আইডি'), r['receiptNumber'].toString()),
        (
        LanguageService.tr('Profit period', 'লাভের সময়কাল'),
        '${_fmtDay(r['periodStart'])} – ${_fmtDay(r['periodEnd'])} (${r['eligibleDays']} ${LanguageService.tr('days', 'দিন')})'
        ),
        (LanguageService.tr('Calculated profit', 'হিসাবকৃত লাভ'), _fmtTk((r['calculatedBdt'] as num).toDouble())),
        (LanguageService.tr('Paid', 'পরিশোধিত'), _fmtTk((r['paidBdt'] as num).toDouble())),
      ],
      if (p != null) ...[
        if (r == null) (LanguageService.tr('Project', 'প্রজেক্ট'), p['projectTitle']?.toString() ?? '—'),
        (LanguageService.tr('Payout', 'পেআউট'), '${_fmtTk((p['amountBdt'] as num).toDouble())} · ${p['statusLabel'] ?? ''}'),
      ],
    ];
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final u = await AuthService.getUserData();
    _userId = u?['id']?.toString() ?? '';
    if (_userId.isEmpty) return;
    final list = await DatabaseService.getTicketInvestmentOptions(_userId);
    if (mounted) setState(() => _investments = list);
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    _expected.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_userId.isEmpty) {
      _goLogin(context);
      return;
    }
    if (_subject.text.trim().length < 3) {
      setState(() => _error = LanguageService.tr('Please write a short subject.', 'সংক্ষেপে বিষয় লিখুন।'));
      return;
    }
    if (_body.text.trim().length < 10) {
      setState(() => _error = LanguageService.tr(
          'Please describe the issue in a little more detail.', 'সমস্যাটি আরেকটু বিস্তারিত লিখুন।'));
      return;
    }
    final expected = double.tryParse(_expected.text.trim());

    setState(() {
      _submitting = true;
      _error = null;
    });
    final res = await DatabaseService.createSupportTicket(
      userId: _userId,
      category: _category,
      subject: _subject.text,
      body: _body.text,
      investmentId: _investmentId,
      expectedAmountBdt: _profitCategory && expected != null && expected > 0 ? expected : null,
      profitRecordId: widget.record?['id'] as String?,
      distributionLineId: widget.payment?['id'] as String?,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(LanguageService.tr('Request sent · ${res['reference']}', 'অনুরোধ পাঠানো হয়েছে · ${res['reference']}')),
        backgroundColor: _emerald,
      ));
      Navigator.pop(context, res['ticketId'] as String);
    } else {
      setState(() {
        _submitting = false;
        _error = res['message']?.toString();
      });
    }
  }

  InputDecoration _dec(String label, {String? hint, IconData? icon}) => InputDecoration(
    labelText: label,
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: _ivory,
    labelStyle: const TextStyle(fontSize: 13, color: _muted),
    hintStyle: const TextStyle(fontSize: 13, color: _muted),
    prefixIcon: icon == null ? null : Icon(icon, size: 19, color: _emerald),
    prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _line)),
    enabledBorder:
    OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _line)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _emerald, width: 1.4)),
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: _ivory,
          appBar: _appBar(_profitCategory
              ? LanguageService.tr('Report a Calculation Issue', 'হিসাবের সমস্যা জানান')
              : LanguageService.tr('New request', 'নতুন অনুরোধ')),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _line))),
              child: SizedBox(
                height: 46,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 19),
                  label: Text(LanguageService.tr('Send request', 'অনুরোধ পাঠান'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    backgroundColor: _emerald,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _emerald.withAlpha(140),
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ),
          body: AbsorbPointer(
            absorbing: _submitting,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
              children: [
                Text(
                  LanguageService.tr('Your request goes to the Help Center with a ticket reference you can track.',
                      'আপনার অনুরোধ একটি রেফারেন্স নম্বরসহ হেল্প সেন্টারে যাবে, যা দিয়ে আপনি অবস্থা দেখতে পারবেন।'),
                  style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                if (_attached.isNotEmpty) ...[
                  _section(
                    LanguageService.tr('Attached automatically', 'স্বয়ংক্রিয়ভাবে যুক্ত'),
                    Column(
                      children: [
                        for (final a in _attached)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 110,
                                  child: Text(a.$1, style: const TextStyle(fontSize: 12.5, color: _muted)),
                                ),
                                Expanded(
                                  child: Text(a.$2,
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                _section(
                  LanguageService.tr('What is it about?', 'বিষয় কী?'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _categories.map((c) {
                      final on = _category == c;
                      return ChoiceChip(
                        label: Text(_categoryLabel(c)),
                        selected: on,
                        showCheckmark: false,
                        selectedColor: _emerald,
                        backgroundColor: _ivory,
                        side: BorderSide(color: on ? _emerald : _line),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        labelStyle:
                        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : _ink),
                        onSelected: (_) => setState(() => _category = c),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 10),
                _section(
                  LanguageService.tr('Details', 'বিস্তারিত'),
                  Column(
                    children: [
                      TextField(
                        controller: _subject,
                        maxLength: 200,
                        style: const TextStyle(fontSize: 14),
                        decoration: _dec(LanguageService.tr('Subject *', 'বিষয় *'),
                            hint: LanguageService.tr('e.g. October profit looks lower', 'যেমন: অক্টোবরের লাভ কম মনে হচ্ছে'),
                            icon: Icons.title_rounded),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _body,
                        minLines: 4,
                        maxLines: 8,
                        maxLength: 5000,
                        style: const TextStyle(fontSize: 14, height: 1.4),
                        decoration: _dec(LanguageService.tr('Describe the issue *', 'সমস্যাটি লিখুন *'),
                            hint: LanguageService.tr('What happened, and what did you expect?',
                                'কী হয়েছে, আর আপনি কী আশা করেছিলেন?')),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (widget.record == null && widget.payment == null)
                  _section(
                    LanguageService.tr('Related investment (optional)', 'সংশ্লিষ্ট বিনিয়োগ (ঐচ্ছিক)'),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String?>(
                          initialValue: _investmentId,
                          isExpanded: true,
                          decoration: _dec(LanguageService.tr('Investment', 'বিনিয়োগ'), icon: Icons.folder_open_rounded),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(LanguageService.tr('None', 'কোনোটি না'),
                                  style: const TextStyle(fontSize: 13.5, color: _muted)),
                            ),
                            for (final i in _investments)
                              DropdownMenuItem<String?>(
                                value: i['investmentId'] as String,
                                child: Text(
                                  [
                                    i['projectTitle'] as String,
                                    if ((i['receiptNumber'] ?? '').toString().isNotEmpty) '#${i['receiptNumber']}',
                                  ].join(' · '),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13.5, color: _ink),
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _investmentId = v),
                        ),
                        if (_profitCategory) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _expected,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            style: const TextStyle(fontSize: 14),
                            decoration: _dec(LanguageService.tr('Amount you expected (optional)', 'আপনার প্রত্যাশিত পরিমাণ (ঐচ্ছিক)'),
                                icon: Icons.payments_outlined)
                                .copyWith(prefixText: '৳ '),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: _dangerSoft, borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 17, color: _danger),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(_error!,
                                style: const TextStyle(fontSize: 12.5, color: _danger, height: 1.35))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const _ContactCard(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _section(String title, Widget child) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _muted, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 3) REQUEST DETAIL — conversation + reply
// ═══════════════════════════════════════════════════════════
class TicketDetailPage extends StatefulWidget {
  final String ticketId;

  const TicketDetailPage({super.key, required this.ticketId});

  @override
  State<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends State<TicketDetailPage> {
  bool _loading = true;
  bool _failed = false;
  bool _notFound = false;
  String _userId = '';
  Map<String, dynamic>? _t;
  final _reply = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    if (_userId.isEmpty) {
      final u = await AuthService.getUserData();
      _userId = u?['id']?.toString() ?? '';
    }
    final t = _userId.isEmpty ? null : await DatabaseService.getInvestorTicket(_userId, widget.ticketId);
    if (!mounted) return;
    setState(() {
      _failed = t?['error'] == 'network';
      _notFound = t == null;
      _t = (t == null || _failed) ? null : t;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.length < 2) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    final res = await DatabaseService.replySupportTicket(userId: _userId, ticketId: widget.ticketId, body: text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (res['success'] == true) {
      _reply.clear();
      await _load();
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['message']?.toString() ?? 'Error'),
        backgroundColor: _danger,
      ));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        final t = _t;
        return Scaffold(
          backgroundColor: _ivory,
          appBar: _appBar(t?['reference']?.toString() ?? LanguageService.tr('Help Center', 'হেল্প সেন্টার')),
          bottomNavigationBar: t == null ? null : _bottom(t),
          body: _loading && t == null
              ? const Center(
              child: SizedBox(
                  width: 26, height: 26, child: CircularProgressIndicator(color: _emerald, strokeWidth: 2.4)))
              : _failed
              ? _message(
              Icons.wifi_off_rounded,
              LanguageService.tr('Could not load this request', 'অনুরোধটি লোড করা যায়নি'),
              LanguageService.tr('Please check your internet connection.', 'ইন্টারনেট সংযোগ চেক করুন।'),
              LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
              _load)
              : _notFound || t == null
              ? _message(
              Icons.search_off_rounded,
              LanguageService.tr('Request not found', 'অনুরোধটি পাওয়া যায়নি'),
              null,
              LanguageService.tr('Go back', 'ফিরে যান'),
                  () => Navigator.pop(context))
              : RefreshIndicator(
            onRefresh: _load,
            color: _emerald,
            child: ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
              children: [
                _header(t),
                if ((t['resolution']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _resolution(t['resolution'] as String),
                ],
                const SizedBox(height: 14),
                Text(LanguageService.tr('CONVERSATION', 'কথোপকথন'),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800, color: _muted, letterSpacing: 1)),
                const SizedBox(height: 8),
                ..._conversation(t),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(Map<String, dynamic> t) {
    final ctx = t['context'] as Map<String, dynamic>;
    final meta = _statusMeta(t['status'] as String);
    final expected = t['expectedAmountBdt'] as double?;

    final rows = <(String, String)>[
      (LanguageService.tr('Submitted', 'জমা'), _fmtWhen(t['createdAt'])),
      (LanguageService.tr('Last updated', 'সর্বশেষ আপডেট'), _fmtWhen(t['lastActivityAt'])),
      if ((ctx['projectTitle'] ?? '').toString().isNotEmpty)
        (LanguageService.tr('Project', 'প্রজেক্ট'), ctx['projectTitle'].toString()),
      if ((ctx['receiptNumber'] ?? '').toString().isNotEmpty)
        (LanguageService.tr('Investment ID', 'বিনিয়োগ আইডি'), ctx['receiptNumber'].toString()),
      if (ctx['periodStart'] != null && ctx['periodEnd'] != null)
        (LanguageService.tr('Profit period', 'লাভের সময়কাল'), '${_fmtDay(ctx['periodStart'])} – ${_fmtDay(ctx['periodEnd'])}'),
      if (ctx['calculatedBdt'] is num)
        (LanguageService.tr('Calculated (when reported)', 'হিসাব (জানানোর সময়)'), _fmtTk((ctx['calculatedBdt'] as num).toDouble())),
      if (expected != null) (LanguageService.tr('Amount you expected', 'আপনার প্রত্যাশিত'), _fmtTk(expected)),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
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
                    SelectableText(t['reference']?.toString() ?? '',
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: _muted)),
                    const SizedBox(height: 2),
                    Text(_categoryLabel(t['category'] as String),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink, height: 1.3)),
                    if ((t['subject'] ?? '').toString().isNotEmpty)
                      Text(t['subject'].toString(), style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusBadge(t['status'] as String),
            ],
          ),
          if (meta.$4.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(color: meta.$3, borderRadius: BorderRadius.circular(9)),
              child: Text(meta.$4, style: TextStyle(fontSize: 12, color: meta.$2, fontWeight: FontWeight.w600)),
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1, color: _line),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (_, c) {
            final w = (c.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 8,
              children: rows
                  .map((r) => SizedBox(
                width: w,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.$1, style: const TextStyle(fontSize: 11, color: _muted)),
                    const SizedBox(height: 1),
                    Text(r.$2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink)),
                  ],
                ),
              ))
                  .toList(),
            );
          }),
        ],
      ),
    );
  }

  Widget _resolution(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _emeraldSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _emerald.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, size: 16, color: _emerald),
              const SizedBox(width: 5),
              Text(LanguageService.tr('RESOLUTION', 'সমাধান'),
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _emerald, letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 5),
          Text(text, style: const TextStyle(fontSize: 13, color: _ink, height: 1.45)),
        ],
      ),
    );
  }

  List<Widget> _conversation(Map<String, dynamic> t) {
    final msgs = (t['messages'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (msgs.isEmpty) {
      return [
        Text(LanguageService.tr('No messages yet.', 'এখনো কোনো বার্তা নেই।'),
            style: const TextStyle(fontSize: 12.5, color: _muted)),
      ];
    }
    final phone = t['channel'] == 'PHONE';
    return [
      for (int i = 0; i < msgs.length; i++) _bubble(msgs[i], phoneFirst: phone && i == 0),
    ];
  }

  Widget _bubble(Map<String, dynamic> m, {required bool phoneFirst}) {
    final role = m['authorRole'] as String;
    final body = m['body']?.toString() ?? '';
    // System: majhe choto lekha (shudhu prothom line)
    if (role == 'SYSTEM') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text('${body.split('\n').first} · ${_fmtWhen(m['createdAt'])}',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: _muted)),
      );
    }
    final mine = role == 'INVESTOR';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
          decoration: BoxDecoration(
            color: mine ? _emerald.withAlpha(22) : Colors.white,
            border: mine ? null : Border.all(color: _line),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(mine ? 14 : 4),
              bottomRight: Radius.circular(mine ? 4 : 14),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!mine) ...[
                    Icon(phoneFirst ? Icons.call_rounded : Icons.support_agent_rounded, size: 13, color: _turquoise),
                    const SizedBox(width: 3),
                  ],
                  Flexible(
                    child: Text(
                      '${mine ? LanguageService.tr('You', 'আপনি') : LanguageService.tr('Biniyog Club support', 'বিনিয়োগ ক্লাব সাপোর্ট')} · ${_fmtWhen(m['createdAt'])}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              SelectableText(body, style: const TextStyle(fontSize: 13.5, color: _ink, height: 1.45)),
              if (m['hasAttachment'] == true) ...[
                const SizedBox(height: 5),
                InkWell(
                  onTap: () => _launch(context, m['attachmentPath'] as String),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.attach_file_rounded, size: 15, color: _emerald),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          (m['attachmentName']?.toString() ?? '').isEmpty
                              ? LanguageService.tr('Attachment', 'সংযুক্তি')
                              : m['attachmentName'].toString(),
                          style: const TextStyle(
                              fontSize: 12.5, color: _emerald, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottom(Map<String, dynamic> t) {
    if (t['status'] == 'CLOSED') {
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _line))),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  LanguageService.tr('This request is closed.', 'এই অনুরোধটি বন্ধ।'),
                  style: const TextStyle(fontSize: 13, color: _muted),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final id = await Navigator.push<String>(
                      context, MaterialPageRoute(builder: (_) => const NewTicketPage()));
                  if (id != null && mounted) {
                    Navigator.pushReplacement(
                        context, MaterialPageRoute(builder: (_) => TicketDetailPage(ticketId: id)));
                  }
                },
                child: Text(LanguageService.tr('Open a new request', 'নতুন অনুরোধ করুন'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _emerald)),
              ),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _line))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _reply,
                minLines: 1,
                maxLines: 5,
                maxLength: 5000,
                enabled: !_sending,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: LanguageService.tr('Write a reply…', 'উত্তর লিখুন…'),
                  hintStyle: const TextStyle(fontSize: 13.5, color: _muted),
                  counterText: '',
                  isDense: true,
                  filled: true,
                  fillColor: _ivory,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: _line)),
                  enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: _line)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: _emerald, width: 1.3)),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 42,
              height: 42,
              child: FilledButton(
                onPressed: _sending ? null : _send,
                style: FilledButton.styleFrom(
                  backgroundColor: _emerald,
                  disabledBackgroundColor: _emerald.withAlpha(140),
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                ),
                child: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 20, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}