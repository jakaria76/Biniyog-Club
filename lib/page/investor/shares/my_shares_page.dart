import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/installment_schedule.dart';
import '../../../services/language_service.dart';
import '../../../services/membership_policy.dart';
import '../../../services/pdf_service.dart';
import '../documents/documents_page.dart'; // PdfViewerScreen, ImageViewerScreen
import '../portfolio/investments_page.dart';
import '../projects/my_projects_page.dart';
import '../projects/project_invest_page.dart';
import '../../../theme/app_colors.dart';

/// Website er /dashboard/shares (My Shares) — share order, payment, kisti ar
/// jachai kora allotment. Shudhu company allot kore amader team jachai korle
/// share "shareholding" hoy; tar age "purchased".
class MySharesPage extends StatefulWidget {
  const MySharesPage({super.key});

  @override
  State<MySharesPage> createState() => _MySharesPageState();
}

class _MySharesPageState extends State<MySharesPage> {
  static const Color emerald = BC.primary;
  static const Color emeraldBright = BC.brand500;
  static const Color emeraldDeep = BC.brand800;
  static const Color emeraldSoft = BC.secondary;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color danger = BC.destructive;
  static const Color review = BC.chart4Deep;
  static const Color lapis = BC.finance600;

  /// Website er share-math.ts ORDER_STATUS_LABEL
  static const Map<String, (String, String)> _orderStatus = {
    'DRAFT': ('Draft', 'খসড়া'),
    'PENDING_PAYMENT': ('Pending payment', 'পেমেন্ট বাকি'),
    'PARTIALLY_PAID': ('Partly paid', 'আংশিক পরিশোধ'),
    'FULLY_PAID': ('Fully paid', 'সম্পূর্ণ পরিশোধ'),
    'AWAITING_ALLOTMENT': ('Awaiting allotment', 'বরাদ্দের অপেক্ষায়'),
    'COMPLETED': ('Completed', 'সম্পন্ন'),
    'CANCELED': ('Cancelled', 'বাতিল'),
  };

  /// Website er ALLOTMENT_STATUS_LABEL
  static const Map<String, (String, String)> _allotStatus = {
    'NOT_ALLOTTED': ('Not allotted', 'বরাদ্দ হয়নি'),
    'PENDING_VERIFICATION': ('Allotment pending verification', 'বরাদ্দ যাচাই চলছে'),
    'VERIFIED_ALLOTTED': ('Verified & allotted', 'যাচাইকৃত ও বরাদ্দকৃত'),
    'REJECTED': ('Allotment rejected', 'বরাদ্দ বাতিল'),
    'TRANSFERRED': ('Transferred', 'হস্তান্তরিত'),
    'CANCELED': ('Allotment cancelled', 'বরাদ্দ বাতিল'),
  };

  bool _loading = true;
  bool _failed = false;
  bool _needsLogin = false;
  String _userId = '';
  Map<String, dynamic>? _data;
  final Set<String> _busyDocs = {};
  final Set<String> _openSchedules = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final user = await AuthService.getUserData();
    final uid = user?['id']?.toString() ?? '';
    if (uid.isEmpty) {
      if (mounted) {
        setState(() {
          _needsLogin = true;
          _loading = false;
        });
      }
      return;
    }
    final d = await DatabaseService.getMyShares(uid);
    if (!mounted) return;
    setState(() {
      _userId = uid;
      _needsLogin = false;
      _data = d ?? _data;
      _failed = d == null && _data == null;
      _loading = false;
    });
    if (d == null && _data != null) {
      _toast(LanguageService.tr('Could not refresh. Showing the last loaded data.',
          'রিফ্রেশ করা যায়নি। আগের তথ্য দেখানো হচ্ছে।'));
    }
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  String _tr((String, String) p) => LanguageService.tr(p.$1, p.$2);

  double _d(dynamic v) => v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0);
  int _i(dynamic v) => v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0);

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? danger : emerald),
    );
  }

  /// Pay — oi order er payment page (kisti-r schedule shoho). Na khulle Investments.
  Future<void> _openPay(String investmentId) async {
    final data = investmentId.isEmpty ? null : await DatabaseService.getInvestmentForPayment(investmentId, _userId);
    if (!mounted) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => data == null
            ? const InvestmentsPage(initialType: 'PROJECT')
            : ProjectInvestPage(existing: data),
      ),
    );
    if (ok == true) {
      _toast(LanguageService.tr('Payment submitted. It will be checked by our team.',
          'পেমেন্ট জমা হয়েছে। আমাদের টিম যাচাই করবে।'));
    }
    if (mounted) _load();
  }

  /// Allotment er document (share certificate ityadi) — website er download API
  Future<void> _openDocument(String documentId, String title) async {
    if (_busyDocs.contains(documentId)) return;
    setState(() => _busyDocs.add(documentId));
    final res = await DatabaseService.downloadWebsiteDocument(userId: _userId, documentId: documentId);
    if (!mounted) return;
    setState(() => _busyDocs.remove(documentId));
    if (res == null) {
      _toast(DatabaseService.lastDownloadError ??
          LanguageService.tr('Download failed. Check your internet.', 'ডাউনলোড হয়নি। ইন্টারনেট চেক করুন।'),
          error: true);
      return;
    }
    final Uint8List bytes = res.bytes;
    final fileName = res.fileName.contains('.')
        ? res.fileName
        : '${PdfService.safeFileName(title)}.${PdfService.extensionFor(bytes, res.fileName)}';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfService.isPdf(bytes)
            ? PdfViewerScreen(title: title, bytes: bytes, fileName: fileName)
            : ImageViewerScreen(title: title, bytes: bytes, fileName: fileName),
      ),
    );
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
          title: Text(LanguageService.tr('My Shares', 'আমার শেয়ার'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 17.5)),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading && _data == null) {
      return const Center(
        child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4)),
      );
    }
    if (_needsLogin) {
      return _message(
        Icons.lock_outline_rounded,
        LanguageService.tr('Please log in to see your shares', 'আপনার শেয়ার দেখতে লগইন করুন'),
        LanguageService.tr('Log in', 'লগইন'),
            () => Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
        ),
      );
    }
    if (_failed || _data == null) {
      return _message(
        Icons.wifi_off_rounded,
        LanguageService.tr('Could not load your shares', 'শেয়ারের তথ্য লোড করা যায়নি'),
        LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
        _load,
      );
    }

    final d = _data!;
    final t = Map<String, dynamic>.from(d['totals'] as Map);
    final projects = (d['projects'] as List).cast<Map<String, dynamic>>();
    final upcoming = (d['upcoming'] as List).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _load,
      color: emerald,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
        children: [
          Text(
            LanguageService.tr('Your company share purchases, payments and verified shareholdings',
                'আপনার কোম্পানির শেয়ার কেনা, পেমেন্ট ও যাচাইকৃত শেয়ার'),
            style: const TextStyle(fontSize: 12.5, color: muted),
          ),
          const SizedBox(height: 12),
          if (projects.isEmpty)
            _emptyCard()
          else ...[
            _heroCard(t),
            const SizedBox(height: 10),
            _statsGrid(t),
            const SizedBox(height: 10),
            _note(),
            if (upcoming.isNotEmpty) ...[
              const SizedBox(height: 12),
              _upcomingCard(upcoming),
            ],
            for (final p in projects) ...[
              const SizedBox(height: 12),
              _projectCard(p),
            ],
          ],
        ],
      ),
    );
  }

  // ─── Hero: verified shares ────────────────────────────────
  Widget _heroCard(Map<String, dynamic> t) {
    final nProjects = _i(t['projects']);
    final nGroups = _i(t['groups']);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [emeraldBright, emerald],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.layers_outlined, size: 15, color: Colors.white.withAlpha(210)),
              const SizedBox(width: 6),
              Text(
                LanguageService.tr('VERIFIED SHARES ALLOTTED', 'যাচাইকৃত বরাদ্দকৃত শেয়ার'),
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white.withAlpha(210), letterSpacing: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              groupedNumber(_i(t['verifiedShares'])),
              style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            LanguageService.tr(
              'of ${groupedNumber(_i(t['purchasedShares']))} purchased · $nProjects project${nProjects == 1 ? '' : 's'} in $nGroups group${nGroups == 1 ? '' : 's'}',
              '${groupedNumber(_i(t['purchasedShares']))} টি কেনা শেয়ারের মধ্যে · $nGroups গ্রুপে $nProjects প্রজেক্ট',
            ),
            style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(185)),
          ),
        ],
      ),
    );
  }

  Widget _statsGrid(Map<String, dynamic> t) {
    final left = _i(t['remainingInstallments']);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _stat(
                LanguageService.tr('Value at purchase', 'ক্রয়মূল্যে মান'),
                fmtTaka(_d(t['valueAtPurchaseBdt'])),
                LanguageService.tr('Paid & verified ${fmtTaka(_d(t['paidBdt']))}',
                    'যাচাইকৃত পরিশোধ ${fmtTaka(_d(t['paidBdt']))}'),
                Icons.account_balance_wallet_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _stat(
                LanguageService.tr('Pending payments', 'বাকি পেমেন্ট'),
                fmtTaka(_d(t['dueBdt'])),
                LanguageService.tr(
                  '${fmtTaka(_d(t['pendingBdt']))} under review · $left installment${left == 1 ? '' : 's'} left',
                  '${fmtTaka(_d(t['pendingBdt']))} যাচাই চলছে · $left টি কিস্তি বাকি',
                ),
                Icons.schedule_rounded,
                valueColor: _d(t['dueBdt']) > 0 ? review : emerald,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _stat(
          LanguageService.tr('Shareholder points', 'শেয়ারহোল্ডার পয়েন্ট'),
          groupedNumber(_i(t['points'])),
          LanguageService.tr('1 point per verified allotted share in eligible offerings',
              'যোগ্য অফারে প্রতিটি যাচাইকৃত বরাদ্দকৃত শেয়ারে ১ পয়েন্ট'),
          Icons.stars_rounded,
        ),
      ],
    );
  }

  Widget _stat(String label, String value, String sub, IconData icon, {Color valueColor = emerald}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: emeraldSoft, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 16, color: emerald),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: muted, fontWeight: FontWeight.w600)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: valueColor)),
                ),
                Text(sub, style: const TextStyle(fontSize: 11, color: muted, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _note() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: BC.muted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: line),
      ),
      child: Text(
        LanguageService.tr(
          'Only shares the company has allotted and our team has verified count as your shareholding. Shares you have ordered or paid for are shown as purchased until then.',
          'কোম্পানি বরাদ্দ দিলে এবং আমাদের টিম যাচাই করলেই কেবল শেয়ার আপনার মালিকানা হিসেবে গণ্য হয়। তার আগে অর্ডার বা পরিশোধ করা শেয়ার "কেনা" হিসেবে দেখানো হয়।',
        ),
        style: const TextStyle(fontSize: 12, color: muted, height: 1.4),
      ),
    );
  }

  // ─── Upcoming payments ────────────────────────────────────
  Widget _upcomingCard(List<Map<String, dynamic>> list) {
    return _card(
      title: LanguageService.tr('Upcoming payments', 'আসন্ন পেমেন্ট'),
      icon: Icons.event_note_outlined,
      children: [
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) const Divider(height: 14, color: line),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(list[i]['projectTitle']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
                    Text(
                      '${list[i]['orderNumber']} · ${fmtDay(list[i]['dueDate']?.toString() ?? '')}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: list[i]['status'] == 'OVERDUE' ? danger : muted,
                        fontWeight: list[i]['status'] == 'OVERDUE' ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(fmtTaka(_d(list[i]['amountBdt'])),
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: list[i]['status'] == 'OVERDUE' ? danger : ink)),
              const SizedBox(width: 8),
              _smallButton(LanguageService.tr('Pay', 'দিন'), () => _openPay(list[i]['investmentId']?.toString() ?? '')),
            ],
          ),
        ],
      ],
    );
  }

  // ─── Project card + orders ────────────────────────────────
  Widget _projectCard(Map<String, dynamic> p) {
    final orders = (p['orders'] as List).cast<Map<String, dynamic>>();
    final group = p['groupName']?.toString();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${(group == null || group.isEmpty) ? '—' : group} · ${p['companyName']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: muted),
                ),
                const SizedBox(height: 2),
                Text(p['projectTitle']?.toString() ?? '',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink, height: 1.25)),
              ],
            ),
          ),
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
                  _stripCell(LanguageService.tr('Verified shares', 'যাচাইকৃত শেয়ার'), groupedNumber(_i(p['verifiedShares'])),
                      Colors.white),
                  _stripDivider(),
                  _stripCell(
                    LanguageService.tr('Purchased', 'কেনা'),
                    groupedNumber(_i(p['purchasedShares'])),
                    BC.brand200,
                    sub: fmtTaka(_d(p['valueAtPurchaseBdt'])),
                  ),
                  _stripDivider(),
                  _stripCell(
                    LanguageService.tr('Paid', 'পরিশোধ'),
                    fmtTaka(_d(p['paidBdt'])),
                    BC.brand300,
                    sub: _d(p['dueBdt']) > 0
                        ? LanguageService.tr('Due ${fmtTaka(_d(p['dueBdt']))}', 'বাকি ${fmtTaka(_d(p['dueBdt']))}')
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          for (final o in orders) _orderTile(o, p['projectTitle']?.toString() ?? ''),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _orderTile(Map<String, dynamic> o, String projectTitle) {
    final status = o['status']?.toString() ?? '';
    final approval = o['scheduleApproval']?.toString();
    final canceled = status == 'CANCELED';
    final due = _d(o['dueBdt']);
    final pending = _d(o['pendingBdt']);
    final overdue = _d(o['overdueBdt']);
    final discount = _d(o['discountBdt']);
    final installment = o['paymentPlan'] == 'INSTALLMENT';
    final schedule = o['schedule'] as ScheduleSummary?;
    final allotments = (o['allotments'] as List).cast<Map<String, dynamic>>();
    // Website: tarikh approval er opekkhay / bad hole taka deya jay na
    final canPay = !canceled && due > 0.5 && approval != 'PENDING' && approval != 'REJECTED';

    final (String, Color) st = approval == 'PENDING'
        ? (LanguageService.tr('Dates awaiting approval', 'তারিখ অনুমোদনের অপেক্ষায়'), review)
        : approval == 'REJECTED'
        ? (LanguageService.tr('Dates not approved', 'তারিখ অনুমোদিত হয়নি'), danger)
        : (_orderStatus[status] != null ? _tr(_orderStatus[status]!) : status, _statusColor(status));

    final created = dhakaDayOf(o['createdAt']);
    final id = o['id'].toString();
    final open = _openSchedules.contains(id);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order no + status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(o['orderNumber']?.toString() ?? '',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700, color: ink, fontFamily: 'monospace')),
                    Text(
                      '${created.isEmpty ? '—' : fmtDay(created)} · ${installment ? LanguageService.tr('Installments', 'কিস্তিতে') : LanguageService.tr('Full payment', 'একবারে')}',
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _chip(st.$1, st.$2),
            ],
          ),
          if (approval == 'REJECTED' && (o['scheduleReviewNote']?.toString() ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(LanguageService.tr('Reason: ${o['scheduleReviewNote']}', 'কারণ: ${o['scheduleReviewNote']}'),
                  style: const TextStyle(fontSize: 11.5, color: danger)),
            ),
          const SizedBox(height: 8),

          // Shares × price = total, paid
          Row(
            children: [
              _cell(LanguageService.tr('Shares', 'শেয়ার'), groupedNumber(_i(o['shareCount']))),
              _cell(LanguageService.tr('Price', 'দর'), fmtTaka(_d(o['pricePerShareBdt']))),
              _cell(LanguageService.tr('Total', 'মোট'), fmtTaka(_d(o['totalBdt'])),
                  sub: discount > 0
                      ? LanguageService.tr('after ${fmtTaka(discount)} coupon', '${fmtTaka(discount)} কুপন ছাড়ের পর')
                      : null,
                  subColor: emerald),
              _cell(LanguageService.tr('Paid', 'পরিশোধ'), fmtTaka(_d(o['paidBdt'])),
                  sub: pending > 0
                      ? LanguageService.tr('${fmtTaka(pending)} under review', '${fmtTaka(pending)} যাচাই চলছে')
                      : null,
                  subColor: review),
            ],
          ),
          if (overdue > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(LanguageService.tr('${fmtTaka(overdue)} overdue', '${fmtTaka(overdue)} মেয়াদোত্তীর্ণ'),
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: danger)),
            ),

          // Allotment
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, size: 14, color: muted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _allotStatus[o['allotmentStatus']] != null
                      ? _tr(_allotStatus[o['allotmentStatus']]!)
                      : (o['allotmentStatus']?.toString() ?? ''),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: o['allotmentStatus'] == 'VERIFIED_ALLOTTED' ? emerald : ink,
                  ),
                ),
              ),
            ],
          ),
          for (final a in allotments) _allotmentLine(a, projectTitle),

          // Kisti (schedule thakle)
          if (schedule != null && schedule.installments.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() {
                if (open) {
                  _openSchedules.remove(id);
                } else {
                  _openSchedules.add(id);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_outlined, size: 14, color: emerald),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        LanguageService.tr(
                          'Installments · ${schedule.installments.where((x) => x.status == 'PAID').length} of ${schedule.installments.length} paid',
                          'কিস্তি · ${schedule.installments.length} টির মধ্যে ${schedule.installments.where((x) => x.status == 'PAID').length} টি পরিশোধিত',
                        ),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: emerald),
                      ),
                    ),
                    Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: emerald),
                  ],
                ),
              ),
            ),
            if (open) ...schedule.installments.map(_installmentRow),
          ],

          if (canPay) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: _smallButton(
                installment
                    ? LanguageService.tr('Pay next installment', 'পরের কিস্তি দিন')
                    : LanguageService.tr('Make a payment', 'পেমেন্ট করুন'),
                    () => _openPay(o['investmentId']?.toString() ?? ''),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _allotmentLine(Map<String, dynamic> a, String projectTitle) {
    final docId = a['documentId']?.toString() ?? '';
    final busy = _busyDocs.contains(docId);
    return Padding(
      padding: const EdgeInsets.only(left: 19, top: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              LanguageService.tr(
                '${groupedNumber(_i(a['shares']))} on ${fmtDay(a['allotmentDate']?.toString() ?? '')} · ${a['shareholderNumber']}',
                '${fmtDay(a['allotmentDate']?.toString() ?? '')} এ ${groupedNumber(_i(a['shares']))} টি · ${a['shareholderNumber']}',
              ),
              style: const TextStyle(fontSize: 11.5, color: muted),
            ),
          ),
          if (docId.isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: busy
                  ? null
                  : () => _openDocument(docId, LanguageService.tr('Share allotment — $projectTitle', 'শেয়ার বরাদ্দ — $projectTitle')),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: busy
                    ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.8, color: emerald))
                    : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.description_outlined, size: 14, color: emerald),
                    const SizedBox(width: 3),
                    Text(LanguageService.tr('Document', 'ডকুমেন্ট'),
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: emerald)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _installmentRow(ScheduleInstallment a) {
    final label = installmentStatusLabel[a.status];
    final c = switch (a.status) {
      'PAID' => emerald,
      'OVERDUE' => danger,
      'DUE' => review,
      'PENDING_VERIFICATION' => lapis,
      _ => muted,
    };
    return Padding(
      padding: const EdgeInsets.only(left: 19, top: 5),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('#${a.number}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: ink)),
          ),
          Expanded(child: Text(fmtDay(a.dueDate), style: const TextStyle(fontSize: 11.5, color: ink))),
          Text(fmtTaka(a.amountPaisa / 100),
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: ink)),
          const SizedBox(width: 8),
          _chip(label == null ? a.status : _tr(label), c, small: true),
        ],
      ),
    );
  }

  Color _statusColor(String s) => switch (s) {
    'COMPLETED' || 'FULLY_PAID' => emerald,
    'AWAITING_ALLOTMENT' => lapis,
    'PARTIALLY_PAID' || 'PENDING_PAYMENT' => review,
    'CANCELED' => danger,
    _ => muted,
  };

  // ═════════════════════════════════════════════════════════
  // SHARED
  // ═════════════════════════════════════════════════════════
  Widget _chip(String text, Color c, {bool small = false}) => Container(
    padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
    decoration: BoxDecoration(color: c.withAlpha(24), borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: TextStyle(fontSize: small ? 10.5 : 11, fontWeight: FontWeight.w800, color: c)),
  );

  Widget _cell(String label, String value, {String? sub, Color subColor = muted}) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ink)),
        ),
        if (sub != null)
          Text(sub, style: TextStyle(fontSize: 10, color: subColor, fontWeight: FontWeight.w600, height: 1.25)),
      ],
    ),
  );

  Widget _stripCell(String label, String value, Color valueColor, {String? sub}) => Expanded(
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
        if (sub != null)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(sub, style: TextStyle(fontSize: 10.5, color: Colors.white.withAlpha(170))),
          ),
      ],
    ),
  );

  Widget _stripDivider() => Container(
    width: 1,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: Colors.white.withAlpha(30),
  );

  Widget _smallButton(String label, VoidCallback onTap) => FilledButton(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      backgroundColor: emerald,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      minimumSize: const Size(0, 32),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    ),
    child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
  );

  Widget _card({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
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
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: emeraldSoft, shape: BoxShape.circle),
            child: const Icon(Icons.layers_outlined, size: 21, color: emerald),
          ),
          const SizedBox(height: 10),
          Text(
            LanguageService.tr("You haven't bought any company shares yet.", 'আপনি এখনো কোনো কোম্পানির শেয়ার কেনেননি।'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyProjectsPage())),
            style: OutlinedButton.styleFrom(
              foregroundColor: emerald,
              side: BorderSide(color: emerald.withAlpha(110)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(LanguageService.tr('Browse projects', 'প্রজেক্ট দেখুন')),
          ),
        ],
      ),
    );
  }

  Widget _message(IconData icon, String text, String buttonLabel, VoidCallback onTap) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: emerald),
            const SizedBox(height: 10),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
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