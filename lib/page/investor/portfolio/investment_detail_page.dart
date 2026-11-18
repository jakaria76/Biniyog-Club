import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/installment_schedule.dart';
import '../../../services/language_service.dart';
import '../../../services/pdf_service.dart';
import '../../../services/profit_accrual.dart';
import '../documents/documents_page.dart'; // PdfViewerScreen, ImageViewerScreen
import '../projects/project_detail_page.dart';
import '../projects/project_invest_page.dart';
import '../../../theme/app_colors.dart';

/// Website er /dashboard/investments/[id] — ekta investment er shob tottho:
/// overview, kisti-r schedule, payment progress, deed ar certificate, profit
/// (mash e mash e) ar payment history (proof shoho).
class InvestmentDetailPage extends StatefulWidget {
  final String investmentId;

  const InvestmentDetailPage({super.key, required this.investmentId});

  @override
  State<InvestmentDetailPage> createState() => _InvestmentDetailPageState();
}

class _InvestmentDetailPageState extends State<InvestmentDetailPage> {
  static const Color emerald = BC.primary;
  static const Color emeraldBright = BC.brand500;
  static const Color emeraldSoft = BC.secondary;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color danger = BC.destructive;
  static const Color review = BC.chart4Deep;
  static const Color reviewSoft = BC.chart4Muted;

  /// Website er cashReceiverLabel
  static const Map<String, (String, String)> _cashReceivers = {
    'CEO': ('CEO', 'সিইও'),
    'MD': ('Managing Director', 'ব্যবস্থাপনা পরিচালক'),
    'CHAIRMAN': ('Chairman', 'চেয়ারম্যান'),
    'FINANCE_TEAM': ('Finance Team', 'ফাইন্যান্স টিম'),
  };

  bool _loading = true;
  bool _failed = false;
  String _userId = '';
  Map<String, dynamic>? _d;
  Map<String, dynamic>? _schedule;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final user = await AuthService.getUserData();
    final uid = user?['id']?.toString() ?? '';
    final r = await Future.wait([
      DatabaseService.getInvestmentDetail(widget.investmentId, uid),
      DatabaseService.getInvestmentSchedule(widget.investmentId, uid),
    ]);
    if (!mounted) return;
    setState(() {
      _userId = uid;
      final d = r[0];
      if (d != null) _d = d;
      final s = r[1];
      _schedule = s != null && s['hasSchedule'] == true ? s : null;
      _failed = _d == null;
      _loading = false;
    });
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  double _n(dynamic v) => v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0);
  String _tk(num v) => tkPaisa(toPaisa(v));
  String _date(dynamic v) {
    final d = dhakaDayOf(v);
    return d.isEmpty ? '—' : fmtDay(d);
  }

  String _dateTime(dynamic v) {
    final u = parseDbTime(v);
    if (u == null) return '—';
    final l = u.add(const Duration(hours: 6));
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    return '${fmtDay(dhakaDay(u))}, $h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
  }

  String _method(String m) => switch (m) {
    'BANK_TRANSFER' || 'BANK' || 'BANK_DEPOSIT' => LanguageService.tr('Bank transfer', 'ব্যাংক ট্রান্সফার'),
    'CHECK' || 'CHEQUE' || 'BANK_CHEQUE' => LanguageService.tr('Cheque', 'চেক'),
    'CASH' || 'CASH_DEPOSIT' => LanguageService.tr('Cash', 'ক্যাশ'),
    'BKASH' => 'bKash',
    'NAGAD' => 'Nagad',
    _ => m,
  };

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? danger : emerald));
  }

  Future<void> _show(String key, String title, Future<({Uint8List bytes, String fileName, String mimeType})?> Function() fetch) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    final res = await fetch();
    if (!mounted) return;
    setState(() => _busy.remove(key));
    if (res == null) {
      _toast(DatabaseService.lastDownloadError ??
          LanguageService.tr('Download failed. Check your internet.', 'ডাউনলোড হয়নি। ইন্টারনেট চেক করুন।'),
          error: true);
      return;
    }
    final name = res.fileName.contains('.')
        ? res.fileName
        : '${PdfService.safeFileName(title)}.${PdfService.extensionFor(res.bytes, res.fileName)}';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfService.isPdf(res.bytes)
            ? PdfViewerScreen(title: title, bytes: res.bytes, fileName: name)
            : ImageViewerScreen(title: title, bytes: res.bytes, fileName: name),
      ),
    );
  }

  Future<void> _deleteDraft() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(LanguageService.tr('Delete this draft?', 'এই খসড়া মুছবেন?'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink)),
        content: Text(
          LanguageService.tr('Nothing has been paid on it. It will be cancelled and removed from your active investments.',
              'এতে কোনো টাকা দেওয়া হয়নি। এটি বাতিল হয়ে আপনার চলমান বিনিয়োগ থেকে সরে যাবে।'),
          style: const TextStyle(fontSize: 13, color: muted, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(LanguageService.tr('Keep', 'রাখুন'), style: const TextStyle(color: muted))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: danger, foregroundColor: Colors.white),
            child: Text(LanguageService.tr('Delete', 'মুছুন')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add('delete'));
    final res = await DatabaseService.deleteDraftInvestment(widget.investmentId, _userId);
    if (!mounted) return;
    setState(() => _busy.remove('delete'));
    if (res['success'] == true) {
      _toast(LanguageService.tr('Draft deleted.', 'খসড়া মুছে ফেলা হয়েছে।'));
      Navigator.pop(context, true);
    } else {
      _toast(res['message']?.toString() ?? LanguageService.tr('Could not delete.', 'মোছা যায়নি।'), error: true);
    }
  }

  Future<void> _pay() async {
    final data = await DatabaseService.getInvestmentForPayment(widget.investmentId, _userId);
    if (!mounted) return;
    if (data == null) {
      _toast(LanguageService.tr('Could not open the payment. Check your internet.', 'পেমেন্ট খোলা যায়নি। ইন্টারনেট চেক করুন।'),
          error: true);
      return;
    }
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ProjectInvestPage(existing: data)));
    if (ok == true) {
      _toast(LanguageService.tr('Payment submitted. It will be active after admin approval.',
          'পেমেন্ট জমা হয়েছে। অ্যাডমিন অনুমোদনের পর চালু হবে।'));
    }
    if (mounted) _load();
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) => Scaffold(
        backgroundColor: ivory,
        appBar: AppBar(
          backgroundColor: ivory,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 54,
          iconTheme: const IconThemeData(color: ink),
          title: Text(LanguageService.tr('Investment Details', 'বিনিয়োগের বিস্তারিত'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 17.5)),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading && _d == null) {
      return const Center(
          child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4)));
    }
    if (_failed || _d == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 34, color: emerald),
              const SizedBox(height: 10),
              Text(LanguageService.tr('Could not load this investment', 'বিনিয়োগের তথ্য লোড করা যায়নি'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(backgroundColor: emerald, foregroundColor: Colors.white),
                child: Text(LanguageService.tr('Try again', 'আবার চেষ্টা করুন')),
              ),
            ],
          ),
        ),
      );
    }

    final d = _d!;
    final status = d['status']?.toString() ?? '';
    final total = _n(d['amountBdt']);
    final payments = (d['payments'] as List).cast<Map<String, dynamic>>();
    double sumOf(Set<String> st) => payments.where((p) => st.contains(p['status'])).fold(0.0, (s, p) => s + _n(p['amountBdt']));
    final approved = sumOf({'APPROVED'});
    final pending = sumOf({'SUBMITTED', 'UNDER_REVIEW'});
    final outstanding = (total - approved - pending).clamp(0.0, double.infinity).toDouble();

    final awaiting = status == 'PENDING' || status == 'PAYMENT_PENDING';
    final live = const {'ACTIVE', 'MATURED', 'COMPLETED'}.contains(status);
    final closed = status == 'CANCELLED' || status == 'REFUNDED';
    final approval = _schedule?['approval']?.toString();
    final datesPending = _schedule != null && approval == 'PENDING' && awaiting;
    final blocked = _schedule?['awaitingApproval'] == true;
    final canPay = awaiting && outstanding > 0.5 && !blocked;

    // Website er commitment / deed obostha
    final (String, Color) commitment = closed
        ? (status == 'REFUNDED' ? LanguageService.tr('Refunded', 'ফেরত') : LanguageService.tr('Cancelled', 'বাতিল'), danger)
        : live
        ? (LanguageService.tr('Fully funded', 'সম্পূর্ণ পরিশোধিত'), emerald)
        : datesPending
        ? (LanguageService.tr('Dates awaiting approval', 'তারিখ অনুমোদনের অপেক্ষায়'), review)
        : approved > 0
        ? (pending > 0
        ? LanguageService.tr('Partially paid · payment under review', 'আংশিক পরিশোধ · যাচাই চলছে')
        : LanguageService.tr('Partially paid', 'আংশিক পরিশোধ'),
    review)
        : pending > 0
        ? (LanguageService.tr('Payment under review', 'পেমেন্ট যাচাই চলছে'), review)
        : (LanguageService.tr('Awaiting payment', 'পেমেন্টের অপেক্ষায়'), muted);
    final deedId = d['deedId']?.toString();
    final (String, Color) deed = closed
        ? (LanguageService.tr('Not applicable', 'প্রযোজ্য নয়'), muted)
        : !live
        ? (LanguageService.tr('Available after full payment', 'পুরো টাকা দিলে পাবেন'), muted)
        : deedId != null
        ? (LanguageService.tr('Issued', 'দেওয়া হয়েছে'), emerald)
        : (LanguageService.tr('Being prepared', 'তৈরি হচ্ছে'), review);

    return RefreshIndicator(
      onRefresh: _load,
      color: emerald,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
        children: [
          _header(d, commitment, deed, canPay, approved + pending > 0,
              canDelete: awaiting && approved + pending == 0 && d['isShare'] != true),
          const SizedBox(height: 10),
          _overview(d),
          if (_schedule != null && approval == 'REJECTED') ...[
            const SizedBox(height: 10),
            _notice(
              Icons.event_busy_outlined,
              danger,
              LanguageService.tr('Your installment dates were not approved', 'আপনার কিস্তির তারিখ অনুমোদিত হয়নি'),
              (_schedule!['reviewNote']?.toString() ?? '').isNotEmpty
                  ? LanguageService.tr('Reason from our team: ${_schedule!['reviewNote']}. You can start a new investment with different dates.',
                  'আমাদের টিমের কারণ: ${_schedule!['reviewNote']}। অন্য তারিখ দিয়ে নতুন করে বিনিয়োগ করতে পারেন।')
                  : LanguageService.tr('Our team did not give a reason — please contact us.', 'আমাদের টিম কারণ জানায়নি — যোগাযোগ করুন।'),
            ),
          ] else if (datesPending) ...[
            const SizedBox(height: 10),
            _notice(
              Icons.hourglass_top_rounded,
              review,
              LanguageService.tr('Your installment dates are being reviewed', 'আপনার কিস্তির তারিখ যাচাই চলছে'),
              LanguageService.tr(
                  "We'll notify you as soon as they're approved — then you can pay and upload your payment proofs. Nothing can be paid until then.",
                  'অনুমোদন হলেই জানাব — তারপর টাকা দিয়ে প্রুফ দিতে পারবেন। তার আগে কিছু দেওয়া যাবে না।'),
            ),
          ] else if (_schedule != null && approval == 'APPROVED' && awaiting && approved + pending == 0) ...[
            const SizedBox(height: 10),
            _notice(
              Icons.event_available_outlined,
              emerald,
              LanguageService.tr('Your installment dates were approved', 'আপনার কিস্তির তারিখ অনুমোদিত হয়েছে'),
              LanguageService.tr('You can now pay your first installment.', 'এখন প্রথম কিস্তি দিতে পারেন।'),
            ),
          ],
          if (_schedule != null) ...[
            const SizedBox(height: 10),
            _scheduleCard(_schedule!, closed),
          ],
          const SizedBox(height: 10),
          _progress(total, approved, pending, awaiting ? outstanding : 0, closed ? d['cancellationReason']?.toString() : null),
          if (live) ...[
            const SizedBox(height: 10),
            _documents(d),
          ],
          if (d['profit'] is Map) ...[
            const SizedBox(height: 10),
            _profit(Map<String, dynamic>.from(d['profit'] as Map), (d['profitMonths'] as List).cast<Map<String, dynamic>>()),
          ],
          const SizedBox(height: 10),
          _history(payments),
        ],
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────
  Widget _header(Map<String, dynamic> d, (String, Color) commitment, (String, Color) deed, bool canPay, bool paidSome,
      {bool canDelete = false}) {
    final id = d['id'].toString();
    final receipt = d['receiptNumber']?.toString() ?? '';
    final order = d['orderNumber']?.toString() ?? '';
    Widget chip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [emeraldBright, emerald], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              '${LanguageService.tr('Commitment', 'প্রতিশ্রুতি')} ${id.substring(0, 8).toUpperCase()}',
              if (receipt.isNotEmpty) '${LanguageService.tr('Receipt', 'রসিদ')} $receipt',
              if (order.isNotEmpty) '${LanguageService.tr('Order', 'অর্ডার')} $order',
            ].join(' · '),
            style: TextStyle(fontSize: 11.5, color: Colors.white.withAlpha(200), fontFamily: 'monospace'),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ProjectDetailPage(projectIdOrSlug: d['projectId'].toString())),
            ),
            child: Text(d['projectTitle']?.toString() ?? '—',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, height: 1.25)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              chip(commitment.$1),
              chip('${LanguageService.tr('Deed', 'দলিল')}: ${deed.$1}'),
            ],
          ),
          if (canPay) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: FilledButton(
                onPressed: _pay,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: emerald,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  paidSome
                      ? LanguageService.tr('Make Another Payment →', 'আরেকটি পেমেন্ট করুন →')
                      : LanguageService.tr('Make a Payment →', 'পেমেন্ট করুন →'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
          if (canDelete) ...[
            const SizedBox(height: 6),
            Center(
              child: TextButton.icon(
                onPressed: _busy.contains('delete') ? null : _deleteDraft,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: const Icon(Icons.delete_outline_rounded, size: 17),
                label: Text(LanguageService.tr('Delete draft', 'খসড়া মুছুন'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Overview ─────────────────────────────────────────────
  Widget _overview(Map<String, dynamic> d) {
    final share = d['isShare'] == true;
    final lo = _n(d['returnMin']);
    final hi = _n(d['returnMax']);
    final amount = _n(d['amountBdt']);
    String pct(double r) {
      final s = (r * 100).toStringAsFixed(1);
      return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    }

    final items = <(String, String, String?)>[
      (LanguageService.tr('Investor', 'বিনিয়োগকারী'), d['investorName']?.toString() ?? '—', null),
      (LanguageService.tr('Total commitment', 'মোট প্রতিশ্রুতি'), _tk(amount), null),
      (
      LanguageService.tr('Payment preference', 'পেমেন্টের ধরন'),
      d['paymentPlan'] == 'INSTALLMENT' ? LanguageService.tr('Installments', 'কিস্তিতে') : LanguageService.tr('Full payment', 'একবারে'),
      null
      ),
      (LanguageService.tr('Committed on', 'প্রতিশ্রুতির তারিখ'), _date(d['createdAt']), null),
      if (!share && hi > 0)
        (
        LanguageService.tr('Annual expected return', 'বার্ষিক প্রত্যাশিত লাভ'),
        lo > 0 && lo != hi ? '${_tk(amount * lo)} – ${_tk(amount * hi)}' : _tk(amount * hi),
        lo > 0 && lo != hi ? '${pct(lo)}–${pct(hi)}%' : '${pct(hi)}%'
        ),
      if (!share) (LanguageService.tr('Duration', 'মেয়াদ'), LanguageService.tr('${d['durationDays']} days', '${d['durationDays']} দিন'), null),
      (LanguageService.tr('Activated on', 'চালুর তারিখ'), _date(d['activatedAt']), null),
      if ((d['deedNumber']?.toString() ?? '').isNotEmpty) (LanguageService.tr('Deed number', 'দলিল নম্বর'), d['deedNumber'].toString(), null),
      if ((d['deedCount'] as int? ?? 0) > 1)
        (
        LanguageService.tr('Total under this deed', 'এই দলিলে মোট'),
        _tk(_n(d['deedTotalBdt'])),
        LanguageService.tr('${d['deedCount']} investments', '${d['deedCount']} টি বিনিয়োগ')
        ),
    ];
    return _card(
      title: LanguageService.tr('Overview', 'সংক্ষেপ'),
      icon: Icons.receipt_long_outlined,
      child: _grid([for (final it in items) _cell(it.$1, it.$2, sub: it.$3)]),
    );
  }

  // ─── Kisti ────────────────────────────────────────────────
  Widget _scheduleCard(Map<String, dynamic> s, bool closed) {
    final sum = s['summary'] as ScheduleSummary;
    final paidCount = sum.installments.where((a) => a.status == 'PAID').length;
    final next = sum.next;
    Color tone(String st) => switch (st) {
      'PAID' => emerald,
      'OVERDUE' => danger,
      'DUE' => review,
      'PENDING_VERIFICATION' => BC.finance600,
      _ => muted,
    };
    return _card(
      title: LanguageService.tr('Installment schedule', 'কিস্তির সময়সূচি'),
      icon: Icons.calendar_month_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _grid([
            _cell(LanguageService.tr('Verified paid', 'যাচাইকৃত পরিশোধ'), tkPaisa(sum.approvedPaisa),
                sub: LanguageService.tr('$paidCount of ${sum.installments.length} · ${sum.progressPct.toStringAsFixed(0)}%',
                    '${sum.installments.length} এর $paidCount · ${sum.progressPct.toStringAsFixed(0)}%'),
                color: emerald),
            _cell(LanguageService.tr('Remaining', 'বাকি'), tkPaisa(sum.remainingPaisa)),
            _cell(
              LanguageService.tr('Next installment', 'পরের কিস্তি'),
              closed || sum.fullyPaid || next == null ? '—' : tkPaisa(next.openPaisa),
              sub: closed || sum.fullyPaid || next == null
                  ? null
                  : LanguageService.tr('${ordinal(next.number)} · due ${fmtDay(next.dueDate)}', '${next.number} নং · ${fmtDay(next.dueDate)}'),
            ),
            _cell(LanguageService.tr('Overdue', 'মেয়াদোত্তীর্ণ'), '${sum.overdueCount}', color: sum.overdueCount > 0 ? danger : null),
            _cell(LanguageService.tr('Grace period', 'অতিরিক্ত সময়'),
                LanguageService.tr('${s['graceDays']} day${s['graceDays'] == 1 ? '' : 's'}', '${s['graceDays']} দিন'),
                sub: LanguageService.tr('after a due date', 'তারিখের পর')),
            _cell(LanguageService.tr('Paying ahead', 'আগে পরিশোধ'),
                s['allowEarly'] == true ? LanguageService.tr('Allowed', 'করা যায়') : LanguageService.tr('Not allowed', 'করা যায় না')),
          ]),
          const SizedBox(height: 10),
          for (final a in sum.installments)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(10), border: Border.all(color: line)),
                child: Row(
                  children: [
                    SizedBox(
                        width: 34,
                        child: Text(ordinal(a.number), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ink))),
                    Expanded(child: Text(fmtDay(a.dueDate), style: const TextStyle(fontSize: 12.5, color: ink))),
                    Text(tkPaisa(a.amountPaisa), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ink)),
                    const SizedBox(width: 8),
                    _pill(
                      installmentStatusLabel[a.status] == null
                          ? a.status
                          : LanguageService.tr(installmentStatusLabel[a.status]!.$1, installmentStatusLabel[a.status]!.$2),
                      tone(a.status),
                    ),
                  ],
                ),
              ),
            ),
          Text(
            sum.fullyPaid
                ? LanguageService.tr('Every installment is verified.', 'সব কিস্তি যাচাই হয়েছে।')
                : LanguageService.tr(
                'Your deed is issued and profit starts once every installment is verified. Late payment has no penalty — overdue installments get reminders only.',
                'সব কিস্তি যাচাই হলে দলিল দেওয়া হবে ও লাভ শুরু হবে। দেরিতে জরিমানা নেই — শুধু মনে করিয়ে দেওয়া হয়।'),
            style: const TextStyle(fontSize: 11.5, color: muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  // ─── Progress ─────────────────────────────────────────────
  Widget _progress(double total, double approved, double pending, double available, String? reason) {
    double f(double v) => total > 0 ? (v / total).clamp(0.0, 1.0).toDouble() : 0.0;
    return _card(
      title: LanguageService.tr('Your Investment Progress', 'বিনিয়োগের অগ্রগতি'),
      icon: Icons.donut_large_rounded,
      trailing: LanguageService.tr('${(f(approved) * 100).floor()}% verified', '${(f(approved) * 100).floor()}% যাচাইকৃত'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: LayoutBuilder(
                builder: (_, c) => Stack(
                  children: [
                    Container(color: line),
                    Container(width: c.maxWidth * (f(approved) + f(pending)).clamp(0.0, 1.0), color: BC.chart4),
                    Container(width: c.maxWidth * f(approved), color: emerald),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _grid([
            _cell(LanguageService.tr('Total commitment', 'মোট প্রতিশ্রুতি'), _tk(total)),
            _cell(LanguageService.tr('Verified payments', 'যাচাইকৃত পেমেন্ট'), _tk(approved), color: emerald),
            _cell(LanguageService.tr('Pending verification', 'যাচাই চলছে'), _tk(pending), color: review),
            _cell(LanguageService.tr('Remaining to verify', 'যাচাই বাকি'), _tk((total - approved).clamp(0, double.infinity))),
            _cell(LanguageService.tr('Available for new payment', 'নতুন পেমেন্ট দেওয়া যাবে'), _tk(available)),
          ]),
          const SizedBox(height: 8),
          Text(
            LanguageService.tr(
                'Only verified payments count towards your progress. Payments under review are held back from what you can pay now, so you never pay more than your commitment.',
                'শুধু যাচাইকৃত পেমেন্ট অগ্রগতিতে গণনা হয়। যাচাই চলা টাকা এখনকার পেমেন্ট থেকে বাদ রাখা হয়, যাতে প্রতিশ্রুতির বেশি না দেন।'),
            style: const TextStyle(fontSize: 11.5, color: muted, height: 1.4),
          ),
          if ((reason ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(LanguageService.tr('Reason: $reason', 'কারণ: $reason'), style: const TextStyle(fontSize: 12.5, color: danger)),
          ],
        ],
      ),
    );
  }

  // ─── Deed + certificate ───────────────────────────────────
  Widget _documents(Map<String, dynamic> d) {
    final deedId = d['deedId']?.toString();
    final certId = d['certificateId']?.toString();
    Widget btn(String label, IconData icon, String? docId) {
      final busy = docId != null && _busy.contains(docId);
      return Expanded(
        child: OutlinedButton.icon(
          onPressed: docId == null || busy
              ? null
              : () => _show(docId, label, () => DatabaseService.downloadWebsiteDocument(userId: _userId, documentId: docId)),
          style: OutlinedButton.styleFrom(
            foregroundColor: emerald,
            side: BorderSide(color: docId == null ? line : emerald.withAlpha(120)),
            minimumSize: const Size(0, 42),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: busy
              ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: emerald))
              : Icon(icon, size: 17),
          label: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
      );
    }

    return _card(
      title: LanguageService.tr('Investment Documents', 'বিনিয়োগের ডকুমেন্ট'),
      icon: Icons.file_download_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              btn(LanguageService.tr('Deed', 'দলিল'), Icons.gavel_rounded, deedId),
              const SizedBox(width: 8),
              btn(LanguageService.tr('Certificate', 'সার্টিফিকেট'), Icons.workspace_premium_outlined, certId),
            ],
          ),
          if (deedId == null || certId == null) ...[
            const SizedBox(height: 8),
            Text(
              LanguageService.tr('Documents still being prepared appear here once they are issued.',
                  'যে ডকুমেন্ট এখনো তৈরি হচ্ছে, দেওয়া হলে এখানে আসবে।'),
              style: const TextStyle(fontSize: 11.5, color: muted),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Profit (website er Profit section + ProfitMonthsTable) ───
  Widget _profit(Map<String, dynamic> p, List<Map<String, dynamic>> months) {
    final earned = _n(p['earnedBdt']);
    final paid = _n(p['paidBdt']);
    final rate = _n(p['annualRatePct']);
    final rateText = rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toStringAsFixed(2);
    double tot(String k) => months.fold<int>(0, (s, m) => s + toPaisa(_n(m[k]))) / 100;
    return _card(
      title: LanguageService.tr('Profit', 'লাভ'),
      icon: Icons.trending_up_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _grid([
            _cell(LanguageService.tr('Annual profit rate', 'বার্ষিক লাভের হার'), '$rateText%',
                sub: LanguageService.tr('${tk2(_n(p['annualProfitBdt']))} a year', 'বছরে ${tk2(_n(p['annualProfitBdt']))}')),
            _cell(LanguageService.tr('Estimated monthly profit', 'আনুমানিক মাসিক লাভ'), tk2(_n(p['monthlyProfitBdt']))),
            _cell(LanguageService.tr('Earned profit', 'অর্জিত লাভ'), tk2(earned),
                sub: (p['earningFrom']?.toString() ?? '').isEmpty
                    ? null
                    : LanguageService.tr('since ${fmtDay(p['earningFrom'].toString())}', '${fmtDay(p['earningFrom'].toString())} থেকে')),
            _cell(LanguageService.tr('Disbursed', 'বিতরণ হয়েছে'), tk2(paid),
                sub: LanguageService.tr('${tk2(((earned - paid) * 100).round() / 100)} not yet paid',
                    '${tk2(((earned - paid) * 100).round() / 100)} এখনো দেওয়া হয়নি'),
                color: emerald),
          ]),
          const SizedBox(height: 10),
          if (months.isEmpty)
            Text(
              LanguageService.tr("Profit starts the day after your investment's effective date.",
                  'বিনিয়োগ কার্যকর হওয়ার পরের দিন থেকে লাভ শুরু হয়।'),
              style: const TextStyle(fontSize: 12.5, color: muted),
            )
          else
            Container(
              decoration: BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(10), border: Border.all(color: line)),
              child: Column(
                children: [
                  _monthRow(LanguageService.tr('Month', 'মাস'), LanguageService.tr('Days', 'দিন'),
                      LanguageService.tr('Earned', 'অর্জিত'), LanguageService.tr('Paid', 'দেওয়া'),
                      header: true),
                  for (final m in months)
                    _monthRow(
                      _monthName(m['month'].toString()) +
                          (m['running'] == true ? LanguageService.tr(' (running)', ' (চলমান)') : ''),
                      '${m['eligibleDays']}',
                      tk2(_n(m['earnedBdt'])),
                      tk2(_n(m['paidBdt'])),
                      faded: m['running'] == true,
                    ),
                  _monthRow(LanguageService.tr('Total', 'মোট'), '', tk2(tot('earnedBdt')), tk2(tot('paidBdt')), header: true),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            LanguageService.tr(
                "Monthly profit is your annual profit ÷ 12, earned day by day (÷ the days in each month). Profit for the current month is earned but is paid once the month closes.",
                'মাসিক লাভ = বার্ষিক লাভ ÷ ১২, দিন হিসেবে অর্জিত (মাসের দিন দিয়ে ভাগ)। চলতি মাসের লাভ অর্জিত, তবে মাস শেষে দেওয়া হয়।'),
            style: const TextStyle(fontSize: 11.5, color: muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  String _monthName(String day) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (day.length < 7) return day;
    return '${m[int.parse(day.substring(5, 7)) - 1]} ${day.substring(0, 4)}';
  }

  Widget _monthRow(String a, String b, String c, String e, {bool header = false, bool faded = false}) {
    final st = TextStyle(
      fontSize: 12,
      fontWeight: header ? FontWeight.w800 : FontWeight.w500,
      color: faded ? muted : ink,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: header ? const BoxDecoration(color: BC.muted) : const BoxDecoration(border: Border(top: BorderSide(color: line))),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(a, style: st)),
          Expanded(flex: 2, child: Text(b, textAlign: TextAlign.center, style: st)),
          Expanded(flex: 4, child: Text(c, textAlign: TextAlign.right, style: st)),
          Expanded(flex: 4, child: Text(e, textAlign: TextAlign.right, style: st.copyWith(color: header || faded ? st.color : emerald))),
        ],
      ),
    );
  }

  // ─── Payment history ──────────────────────────────────────
  Widget _history(List<Map<String, dynamic>> payments) {
    (String, Color, IconData) st(String s) => switch (s) {
      'APPROVED' => (LanguageService.tr('Verified', 'যাচাইকৃত'), emerald, Icons.check_circle_outline_rounded),
      'REJECTED' => (LanguageService.tr('Rejected', 'বাতিল'), danger, Icons.cancel_outlined),
      'UNDER_REVIEW' => (LanguageService.tr('Under review', 'যাচাই চলছে'), review, Icons.schedule_rounded),
      _ => (LanguageService.tr('Pending verification', 'যাচাইয়ের অপেক্ষায়'), review, Icons.schedule_rounded),
    };
    return _card(
      title: LanguageService.tr('Payment History (${payments.length})', 'পেমেন্টের ইতিহাস (${payments.length})'),
      icon: Icons.history_rounded,
      child: payments.isEmpty
          ? Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(LanguageService.tr('No payments submitted yet.', 'এখনো কোনো পেমেন্ট জমা হয়নি।'),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: muted)),
      )
          : Column(
        children: [
          for (var i = 0; i < payments.length; i++) ...[
            if (i > 0) const Divider(height: 18, color: line),
            Builder(builder: (_) {
              final p = payments[i];
              final s = st(p['status']?.toString() ?? '');
              final method = p['method']?.toString() ?? '';
              final isCash = method.startsWith('CASH');
              final receiver = _cashReceivers[p['cashReceivedBy']?.toString()];
              final ref = p['transactionRef']?.toString() ?? '';
              final proofs = (p['proofCount'] as int?) ?? 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${_method(method)} · ${_tk(_n(p['amountBdt']))}',
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: ink)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: s.$2.withAlpha(24), borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(s.$3, size: 13, color: s.$2),
                            const SizedBox(width: 3),
                            Text(s.$1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: s.$2)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (isCash)
                        LanguageService.tr('Handed to ${receiver?.$1 ?? (p['cashReceivedBy'] ?? '—')}',
                            '${receiver?.$2 ?? (p['cashReceivedBy'] ?? '—')} কে দেওয়া')
                      else if (ref.isNotEmpty && ref != 'CASH')
                        'Ref $ref',
                      LanguageService.tr('Submitted ${_dateTime(p['createdAt'])}', 'জমা ${_dateTime(p['createdAt'])}'),
                      if (p['reviewedAt'] != null)
                        LanguageService.tr('Reviewed ${_dateTime(p['reviewedAt'])}', 'যাচাই ${_dateTime(p['reviewedAt'])}'),
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11.5, color: muted, height: 1.35),
                  ),
                  if (p['status'] == 'REJECTED' && (p['rejectionReason']?.toString() ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(p['rejectionReason'].toString(), style: const TextStyle(fontSize: 12, color: danger)),
                    ),
                  if (proofs > 0) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var n = 0; n < proofs; n++)
                          Builder(builder: (_) {
                            final key = 'proof-${p['id']}-$n';
                            final busy = _busy.contains(key);
                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: busy
                                  ? null
                                  : () => _show(
                                key,
                                LanguageService.tr('Payment proof', 'পেমেন্ট প্রুফ'),
                                    () => DatabaseService.downloadPaymentProof(
                                    userId: _userId, kind: 'manual', id: p['id'].toString(), n: n),
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(color: emeraldSoft, borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    busy
                                        ? const SizedBox(
                                        width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.8, color: emerald))
                                        : const Icon(Icons.image_outlined, size: 14, color: emerald),
                                    const SizedBox(width: 4),
                                    Text(
                                      proofs > 1
                                          ? LanguageService.tr('Proof ${n + 1}', 'প্রুফ ${n + 1}')
                                          : LanguageService.tr('View proof', 'প্রুফ দেখুন'),
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: emerald),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ],
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // SHARED
  // ═════════════════════════════════════════════════════════
  Widget _card({required String title, required IconData icon, String? trailing, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: emeraldSoft, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 15, color: emerald),
              ),
              const SizedBox(width: 9),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink))),
              if (trailing != null) Text(trailing, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: emerald)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _grid(List<Widget> cells) => LayoutBuilder(
    builder: (_, c) {
      final w = (c.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [for (final x in cells) SizedBox(width: w, child: x)]);
    },
  );

  Widget _cell(String label, String value, {String? sub, Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(10), border: Border.all(color: line)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color ?? ink, height: 1.25)),
        if (sub != null) Text(sub, style: const TextStyle(fontSize: 10.5, color: muted, height: 1.3)),
      ],
    ),
  );

  Widget _pill(String text, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: c.withAlpha(24), borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
  );

  Widget _notice(IconData icon, Color c, String title, String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: c == emerald ? emeraldSoft : (c == danger ? BC.destructiveMuted : reviewSoft),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: c.withAlpha(60)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: c),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 2),
              Text(text, style: const TextStyle(fontSize: 12, color: muted, height: 1.4)),
            ],
          ),
        ),
      ],
    ),
  );
}