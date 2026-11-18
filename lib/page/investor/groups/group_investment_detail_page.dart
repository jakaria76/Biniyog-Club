import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/installment_schedule.dart';
import '../../../services/language_service.dart';
import '../../../services/pdf_service.dart';
import '../documents/documents_page.dart'; // PdfViewerScreen, ImageViewerScreen
import '../../../theme/app_colors.dart';
import 'group_invest_page.dart';

/// Ekta group investment er shob tottho — card e chaple khule:
/// overview, payment progress, payment history (proof shoho), receipt,
/// payment kora ar (kichu jama na thakle) cancel. Website er /dashboard/groups
/// ar /dashboard/groups/[id]/pay er tottho ek jaygay.
class GroupInvestmentDetailPage extends StatefulWidget {
  final String groupInvestmentId;

  const GroupInvestmentDetailPage({super.key, required this.groupInvestmentId});

  @override
  State<GroupInvestmentDetailPage> createState() => _GroupInvestmentDetailPageState();
}

class _GroupInvestmentDetailPageState extends State<GroupInvestmentDetailPage> {
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
  static const Color lapis = BC.finance600;

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
  final Set<String> _busy = {};

  /// Kichu bodlale (payment / cancel) — list page abar load korbe
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final user = await AuthService.getUserData();
    final uid = user?['id']?.toString() ?? '';
    final d = await DatabaseService.getGroupInvestmentDetail(widget.groupInvestmentId, uid);
    if (!mounted) return;
    setState(() {
      _userId = uid;
      if (d != null) _d = d;
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

  String _trim(double v, int digits) {
    final s = v.toStringAsFixed(digits);
    return s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
  }

  String _method(String m) => switch (m) {
    'BANK_TRANSFER' || 'BANK' || 'BANK_DEPOSIT' => LanguageService.tr('Bank transfer', 'ব্যাংক ট্রান্সফার'),
    'CHECK' || 'CHEQUE' || 'BANK_CHEQUE' => LanguageService.tr('Cheque', 'চেক'),
    'CASH' || 'CASH_DEPOSIT' => LanguageService.tr('Cash', 'ক্যাশ'),
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

  Future<void> _pay() async {
    final d = _d;
    if (d == null) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupInvestPage(
          existing: d,
          groupName: d['groupName']?.toString() ?? '',
          entityName: d['entityName']?.toString() ?? '',
        ),
      ),
    );
    if (ok == true && mounted) {
      _changed = true;
      _toast(LanguageService.tr('Payment submitted. It will be active after admin approval.',
          'পেমেন্ট জমা হয়েছে। অ্যাডমিন অনুমোদনের পর চালু হবে।'));
      _load();
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(LanguageService.tr('Cancel this investment?', 'এই বিনিয়োগ বাতিল করবেন?'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink)),
        content: Text(
          LanguageService.tr('No payment has been submitted for it. It will be cancelled.',
              'এতে কোনো পেমেন্ট জমা হয়নি। এটি বাতিল হয়ে যাবে।'),
          style: const TextStyle(fontSize: 13, color: muted, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(LanguageService.tr('Keep', 'রাখুন'), style: const TextStyle(color: muted))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: danger, foregroundColor: Colors.white),
            child: Text(LanguageService.tr('Cancel investment', 'বাতিল করুন')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add('cancel'));
    final res = await DatabaseService.cancelGroupInvestment(widget.groupInvestmentId, _userId);
    if (!mounted) return;
    setState(() => _busy.remove('cancel'));
    if (res['success'] == true) {
      _changed = true;
      _toast(LanguageService.tr('Investment cancelled.', 'বিনিয়োগ বাতিল হয়েছে।'));
      _load();
    } else {
      _toast(res['message']?.toString() ?? LanguageService.tr('Could not cancel.', 'বাতিল করা যায়নি।'), error: true);
    }
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.pop(context, _changed);
        },
        child: Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 54,
            iconTheme: const IconThemeData(color: ink),
            title: Text(LanguageService.tr('Group Investment', 'গ্রুপ বিনিয়োগ'),
                style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 17.5)),
          ),
          body: _loading && _d == null
              ? const Center(
              child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4)))
              : _failed
              ? _message()
              : RefreshIndicator(onRefresh: _load, color: emerald, child: _body()),
        ),
      ),
    );
  }

  Widget _message() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 34, color: emerald),
          const SizedBox(height: 10),
          Text(LanguageService.tr('Could not load this investment', 'এই বিনিয়োগ লোড করা যায়নি'),
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

  Widget _body() {
    final d = _d!;
    final status = d['status']?.toString() ?? '';
    final total = _n(d['amountBdt']);
    final approved = _n(d['paidApproved']);
    final pending = _n(d['paidPending']);
    final outstanding = math.max(0.0, total - approved - pending);
    final awaiting = status == 'PENDING' || status == 'PAYMENT_PENDING';
    final payments = (d['payments'] as List).cast<Map<String, dynamic>>();
    final nonRejected = payments.where((p) => p['status'] != 'REJECTED').length;
    final canPay = awaiting && outstanding > 0.5;
    final canCancel = awaiting && nonRejected == 0;
    final rejected = payments.where((p) => p['status'] == 'REJECTED').toList();
    final lastRejected = rejected.isEmpty ? null : rejected.last;
    final receipt = d['receiptNumber']?.toString() ?? '';
    final hasReceipt = receipt.isNotEmpty && (status == 'ACTIVE' || status == 'COMPLETED');

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 2, 16, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        _header(d, status, total, canPay, approved + pending > 0),
        const SizedBox(height: 12),
        if (lastRejected != null && canPay) ...[
          _notice(
            Icons.cancel_outlined,
            danger,
            LanguageService.tr('A payment was rejected', 'একটি পেমেন্ট বাতিল হয়েছে'),
            LanguageService.tr(
              'Reason: ${(lastRejected['rejectionReason']?.toString() ?? '').isEmpty ? 'No reason provided' : lastRejected['rejectionReason']}. Please pay the remaining ${_tk(outstanding)} again.',
              'কারণ: ${(lastRejected['rejectionReason']?.toString() ?? '').isEmpty ? 'কারণ দেওয়া হয়নি' : lastRejected['rejectionReason']}। বাকি ${_tk(outstanding)} আবার দিন।',
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (awaiting && outstanding <= 0.5 && pending > 0) ...[
          _notice(
            Icons.schedule_rounded,
            review,
            LanguageService.tr('Full amount submitted — under review', 'পুরো টাকা জমা হয়েছে — যাচাই চলছে'),
            LanguageService.tr(
                'Our finance team verifies each payment within 1–2 business days. Your investment activates once all of it is verified.',
                'আমাদের ফাইন্যান্স টিম ১–২ কর্মদিবসে প্রতিটি পেমেন্ট যাচাই করে। পুরো টাকা যাচাই হলে বিনিয়োগ চালু হবে।'),
          ),
          const SizedBox(height: 12),
        ],
        _overview(d, status, total),
        if (awaiting || approved + pending > 0) ...[
          const SizedBox(height: 12),
          _progress(total, approved, pending, outstanding, d['paymentPlan'] == 'INSTALLMENT'),
        ],
        if (hasReceipt) ...[
          const SizedBox(height: 12),
          _receipt(receipt),
        ],
        const SizedBox(height: 12),
        _history(payments),
        if (canCancel) ...[
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _busy.contains('cancel') ? null : _cancel,
              style: TextButton.styleFrom(foregroundColor: danger),
              icon: _busy.contains('cancel')
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: danger))
                  : const Icon(Icons.close_rounded, size: 18),
              label: Text(LanguageService.tr('Cancel this investment', 'এই বিনিয়োগ বাতিল করুন'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Header ───────────────────────────────────────────────
  (String, Color) _status(String s) => switch (s) {
    'PENDING' => (LanguageService.tr('Pending', 'অপেক্ষমান'), muted),
    'PAYMENT_PENDING' => (LanguageService.tr('Awaiting Payment', 'পেমেন্ট বাকি'), review),
    'ACTIVE' => (LanguageService.tr('Active', 'চলমান'), emeraldBright),
    'COMPLETED' || 'MATURED' => (LanguageService.tr('Completed', 'সম্পন্ন'), lapis),
    'REFUNDED' => (LanguageService.tr('Refunded', 'ফেরত'), muted),
    _ => (LanguageService.tr('Cancelled', 'বাতিল'), danger),
  };

  Widget _header(Map<String, dynamic> d, String status, double total, bool canPay, bool paidSome) {
    final group = d['groupName']?.toString() ?? '';
    final entity = d['entityName']?.toString() ?? '';
    final title = entity.isEmpty || entity.toLowerCase() == group.toLowerCase() ? group : '$group — $entity';
    final st = _status(status);
    final receipt = d['receiptNumber']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [emeraldBright, emerald], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(title.isEmpty ? '—' : title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Text(st.$1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: st.$2)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text((d['tierName']?.toString() ?? '').isEmpty ? '—' : d['tierName'].toString(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 8),
          Text(_tk(total), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
          if (receipt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined, size: 14, color: Colors.white70),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(receipt,
                      style: const TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: receipt));
                    _toast(LanguageService.tr('Receipt number copied', 'রসিদ নম্বর কপি হয়েছে'));
                  },
                  child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.copy_rounded, size: 13, color: Colors.white70)),
                ),
              ],
            ),
          ],
          if (canPay) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
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
        ],
      ),
    );
  }

  // ─── Overview ─────────────────────────────────────────────
  Widget _overview(Map<String, dynamic> d, String status, double total) {
    final pct = _n(d['expectedReturnPct']);
    final months = _n(d['durationMonths']).toInt();
    final created = parseDbTime(d['createdAt']);
    final confirmed = parseDbTime(d['confirmedAt']);
    final start = confirmed ?? created;
    DateTime? maturity;
    if (start != null && months > 0) {
      final l = start.add(const Duration(hours: 6));
      maturity = DateTime.utc(l.year, l.month + months, l.day);
    }
    final plot = d['plotNumber']?.toString() ?? '';
    final size = _n(d['plotSizeSqft']);
    final share = d['sharePercentage'];
    final notes = d['notes']?.toString() ?? '';
    final installment = d['paymentPlan'] == 'INSTALLMENT';
    final daysLeft = maturity == null ? 0 : math.max(0, maturity.difference(DateTime.now().toUtc()).inDays);

    return _card(
      title: LanguageService.tr('Overview', 'সংক্ষিপ্ত তথ্য'),
      icon: Icons.dashboard_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _grid([
            _cell(LanguageService.tr('Amount', 'পরিমাণ'), _tk(total),
                sub: installment
                    ? LanguageService.tr('Paying in installments', 'কিস্তিতে দিচ্ছেন')
                    : LanguageService.tr('Paying in full', 'একবারে')),
            _cell(LanguageService.tr('Expected return', 'প্রত্যাশিত লাভ'),
                pct > 0 ? '+${_tk(total * pct)}' : LanguageService.tr('Not set', 'নির্ধারিত নয়'),
                sub: pct > 0 ? '${_trim(pct * 100, 2)}% · ${LanguageService.tr('estimate', 'আনুমানিক')}' : null,
                color: pct > 0 ? emerald : null),
            if (pct > 0) _cell(LanguageService.tr('Total at maturity', 'মেয়াদ শেষে মোট'), _tk(total * (1 + pct))),
            _cell(LanguageService.tr('Term', 'মেয়াদ'),
                months > 0 ? LanguageService.tr('$months months', '$months মাস') : '—'),
            _cell(LanguageService.tr('Invested on', 'বিনিয়োগের তারিখ'), _date(d['createdAt'])),
            if (confirmed != null) _cell(LanguageService.tr('Active since', 'চালু হয়েছে'), _date(d['confirmedAt'])),
            if (status == 'ACTIVE' && maturity != null)
              _cell(LanguageService.tr('Matures', 'মেয়াদ শেষ'), fmtDay(dhakaDay(maturity.subtract(const Duration(hours: 6)))),
                  sub: LanguageService.tr('$daysLeft days left', '$daysLeft দিন বাকি')),
            if (plot.isNotEmpty && plot != 'N/A') _cell(LanguageService.tr('Plot No.', 'প্লট নং'), plot),
            if (size > 0) _cell(LanguageService.tr('Plot size', 'আয়তন'), '${_trim(size, 2)} sqft'),
            if (share != null) _cell(LanguageService.tr('Share', 'শেয়ার'), '${_n(share).toStringAsFixed(4)}%'),
            if (d['status'] == 'CANCELLED' && d['cancelledAt'] != null)
              _cell(LanguageService.tr('Cancelled on', 'বাতিলের তারিখ'), _date(d['cancelledAt']), color: danger),
          ]),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(10), border: Border.all(color: line)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(LanguageService.tr('Notes', 'নোট'),
                      style: const TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(notes, style: const TextStyle(fontSize: 12.5, color: ink, height: 1.4)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Payment progress ─────────────────────────────────────
  Widget _progress(double total, double approved, double pending, double outstanding, bool installment) {
    double f(double v) => total > 0 ? (v / total).clamp(0.0, 1.0).toDouble() : 0.0;
    Widget stat(String label, double v, Color c) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: muted))),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_tk(v), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: ink)),
          ),
        ],
      ),
    );
    return _card(
      title: installment
          ? LanguageService.tr('Installment Progress', 'কিস্তির অগ্রগতি')
          : LanguageService.tr('Payment Progress', 'পেমেন্টের অগ্রগতি'),
      icon: Icons.donut_large_rounded,
      trailing: LanguageService.tr('${(f(approved) * 100).floor()}% verified', '${(f(approved) * 100).floor()}% যাচাই'),
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
                    Container(width: c.maxWidth * (f(approved) + f(pending)).clamp(0.0, 1.0), color: BC.harvest500),
                    Container(width: c.maxWidth * f(approved), color: emerald),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              stat(LanguageService.tr('Verified', 'যাচাই হয়েছে'), approved, emerald),
              stat(LanguageService.tr('Under review', 'যাচাই চলছে'), pending, BC.harvest500),
              stat(LanguageService.tr('Left to pay', 'বাকি'), outstanding, ink),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Receipt ──────────────────────────────────────────────
  Widget _receipt(String receipt) {
    final busy = _busy.contains('receipt');
    return _card(
      title: LanguageService.tr('Receipt', 'রসিদ'),
      icon: Icons.receipt_long_outlined,
      child: SizedBox(
        height: 44,
        child: OutlinedButton.icon(
          onPressed: busy
              ? null
              : () => _show(
            'receipt',
            LanguageService.tr('Receipt $receipt', 'রসিদ $receipt'),
                () => DatabaseService.downloadGroupReceipt(userId: _userId, groupInvestmentId: widget.groupInvestmentId),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: emerald,
            side: const BorderSide(color: emerald),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: emerald))
              : const Icon(Icons.download_rounded, size: 18),
          label: Text(LanguageService.tr('View / download receipt', 'রসিদ দেখুন / ডাউনলোড'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  // ─── Payment history ──────────────────────────────────────
  Widget _history(List<Map<String, dynamic>> payments) {
    (String, Color, IconData) st(String s) => switch (s) {
      'APPROVED' => (LanguageService.tr('Verified', 'যাচাইকৃত'), emerald, Icons.check_circle_outline_rounded),
      'REJECTED' => (LanguageService.tr('Rejected', 'বাতিল'), danger, Icons.cancel_outlined),
      _ => (LanguageService.tr('Under review', 'যাচাই চলছে'), review, Icons.schedule_rounded),
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
          for (var i = payments.length - 1; i >= 0; i--) ...[
            if (i < payments.length - 1) const Divider(height: 18, color: line),
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
                                    userId: _userId, kind: 'group', id: p['id'].toString(), n: n),
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
              if (trailing != null)
                Text(trailing, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: emerald)),
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

  Widget _notice(IconData icon, Color c, String title, String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: c == danger ? BC.destructiveMuted : reviewSoft,
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