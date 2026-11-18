import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/installment_schedule.dart';
import '../../../services/language_service.dart';
import '../../../services/pdf_service.dart';
import '../../../services/profit_accrual.dart';
import '../documents/documents_page.dart'; // PdfViewerScreen, ImageViewerScreen
import '../portfolio/investment_detail_page.dart';
import '../../../theme/app_colors.dart';

/// Website er "My Investment Profit Overview" (dashboard) — protita approved
/// investment koto lav earned, koto deya hoyeche, koto baki, ar profit
/// disbursement er history (receipt / transfer proof shoho).
class ProfitOverviewPage extends StatefulWidget {
  const ProfitOverviewPage({super.key});

  @override
  State<ProfitOverviewPage> createState() => _ProfitOverviewPageState();
}

class _ProfitOverviewPageState extends State<ProfitOverviewPage> {
  static const Color emerald = BC.primary;
  static const Color emeraldBright = BC.brand500;
  static const Color emeraldSoft = BC.secondary;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color danger = BC.destructive;

  bool _loading = true;
  bool _failed = false;
  String _userId = '';
  Map<String, dynamic>? _d;
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
    final d = await DatabaseService.getProfitOverview(uid);
    if (!mounted) return;
    setState(() {
      _userId = uid;
      if (d != null) _d = d;
      _failed = _d == null;
      _loading = false;
    });
  }

  double _n(dynamic v) => v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0);

  Future<void> _show(String key, String title, Future<({Uint8List bytes, String fileName, String mimeType})?> Function() fetch) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    final res = await fetch();
    if (!mounted) return;
    setState(() => _busy.remove(key));
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(DatabaseService.lastDownloadError ??
            LanguageService.tr('Download failed. Check your internet.', 'ডাউনলোড হয়নি। ইন্টারনেট চেক করুন।')),
        backgroundColor: danger,
      ));
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
          title: Text(LanguageService.tr('Profit Overview', 'লাভের সংক্ষেপ'),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 34, color: emerald),
            const SizedBox(height: 10),
            Text(LanguageService.tr('Could not load your profit', 'লাভের তথ্য লোড করা যায়নি'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(backgroundColor: emerald, foregroundColor: Colors.white),
              child: Text(LanguageService.tr('Try again', 'আবার চেষ্টা করুন')),
            ),
          ],
        ),
      );
    }
    final d = _d!;
    final rows = (d['rows'] as List).cast<Map<String, dynamic>>();
    final payouts = (d['payouts'] as List).cast<Map<String, dynamic>>();
    return RefreshIndicator(
      onRefresh: _load,
      color: emerald,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
        children: [
          Text(
            LanguageService.tr("Profit accrues daily at your agreed rate; this month's share is earned but not yet paid.",
                'চুক্তির হারে প্রতিদিন লাভ জমে; চলতি মাসের লাভ অর্জিত, তবে এখনো দেওয়া হয়নি।'),
            style: const TextStyle(fontSize: 12.5, color: muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty && payouts.isEmpty)
            _empty()
          else ...[
            ProfitOverviewStats(data: d),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(LanguageService.tr('By investment', 'বিনিয়োগ অনুযায়ী'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 8),
              for (final r in rows) ...[_rowCard(r), const SizedBox(height: 10)],
            ],
            if (payouts.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(LanguageService.tr('Profit Disbursement History', 'লাভ বিতরণের ইতিহাস'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(height: 8),
              _payoutList(payouts),
            ],
          ],
        ],
      ),
    );
  }

  Widget _empty() => Container(
    padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
    child: Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(color: emeraldSoft, shape: BoxShape.circle),
          child: const Icon(Icons.trending_up_rounded, color: emerald, size: 21),
        ),
        const SizedBox(height: 10),
        Text(
          LanguageService.tr('Profit appears here once an investment is approved.', 'বিনিয়োগ অনুমোদন হলে লাভ এখানে দেখাবে।'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
        ),
      ],
    ),
  );

  Widget _rowCard(Map<String, dynamic> r) {
    final earned = _n(r['earnedBdt']);
    final paid = _n(r['paidBdt']);
    final rate = _n(r['annualRatePct']);
    final max = r['rateMaxPct'] == null ? null : _n(r['rateMaxPct']);
    String p(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    final lines = <(String, String, bool)>[
      (LanguageService.tr('Investment', 'বিনিয়োগ'), tk2(_n(r['principalBdt'])), false),
      (LanguageService.tr('Annual rate', 'বার্ষিক হার'), '${p(rate)}%${max != null && max > 0 ? LanguageService.tr(' (up to ${p(max)}%)', ' (সর্বোচ্চ ${p(max)}%)') : ''}', false),
      (LanguageService.tr('Monthly profit', 'মাসিক লাভ'), tk2(_n(r['monthlyProfitBdt'])), false),
      (LanguageService.tr('Earned', 'অর্জিত'), tk2(earned), false),
      (LanguageService.tr('Disbursed', 'বিতরণ হয়েছে'), tk2(paid), true),
      (LanguageService.tr('Undisbursed', 'বাকি'), tk2(((earned - paid) * 100).round() / 100), false),
    ];
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => InvestmentDetailPage(investmentId: r['investmentId'].toString())),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r['projectTitle']?.toString() ?? '—',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ink)),
              Text(
                '${(r['receiptNumber']?.toString() ?? '').isEmpty ? r['investmentId'].toString().substring(0, 8).toUpperCase() : r['receiptNumber']}'
                    ' · ${LanguageService.tr('effective', 'কার্যকর')} ${fmtDay(r['effectiveDate']?.toString() ?? '')}',
                style: const TextStyle(fontSize: 11, color: muted, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text(l.$1, style: const TextStyle(fontSize: 12, color: muted))),
                      Text(l.$2,
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700, color: l.$3 ? emerald : ink, fontFamily: 'monospace')),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(LanguageService.tr('Monthly breakdown', 'মাসভিত্তিক হিসাব'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: emerald)),
                  const SizedBox(width: 3),
                  const Icon(Icons.arrow_forward_rounded, size: 14, color: emerald),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _payoutList(List<Map<String, dynamic>> list) {
    Color tone(String k) => switch (k) {
      'PAID' => emerald,
      'FAILED' || 'REVERSED' => danger,
      'AWAITING_PAYMENT' => BC.chart4Deep,
      _ => muted,
    };
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: line)),
      child: Column(
        children: [
          for (var i = 0; i < list.length; i++)
            Builder(builder: (_) {
              final p = list[i];
              final key = p['statusKey']?.toString() ?? '';
              final c = tone(key);
              final ps = p['periodStart']?.toString() ?? '';
              final pe = p['periodEnd']?.toString() ?? '';
              final paid = key == 'PAID';
              final method = payoutMethodLabels[p['method']] ?? p['method']?.toString();
              return Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: line))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(p['projectTitle']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
                        ),
                        Text(tk2(_n(p['amountBdt'])),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink, fontFamily: 'monospace')),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            [
                              if (ps.isNotEmpty && pe.isNotEmpty) '${fmtDay(ps)} – ${fmtDay(pe)}',
                              if (paid && p['paidAt'] != null) LanguageService.tr('paid ${fmtDay(dhakaDayOf(p['paidAt']))}', '${fmtDay(dhakaDayOf(p['paidAt']))} এ দেওয়া'),
                              if (paid && method != null) method,
                            ].join(' · '),
                            style: const TextStyle(fontSize: 11.5, color: muted),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: c.withAlpha(24), borderRadius: BorderRadius.circular(20)),
                          child: Text(LanguageService.tr(p['statusEn'].toString(), p['statusBn'].toString()),
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
                        ),
                      ],
                    ),
                    if (p['status'] == 'PAID') ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          _linkChip('rc-${p['id']}', Icons.receipt_long_outlined, LanguageService.tr('Receipt', 'রসিদ'),
                                  () => DatabaseService.downloadProfitReceipt(userId: _userId, lineId: p['id'].toString())),
                          if (p['hasProof'] == true)
                            _linkChip('pf-${p['id']}', Icons.image_outlined, LanguageService.tr('Transfer proof', 'ট্রান্সফার প্রুফ'),
                                    () => DatabaseService.downloadPaymentProof(userId: _userId, kind: 'payout', id: p['id'].toString())),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _linkChip(String key, IconData icon, String label,
      Future<({Uint8List bytes, String fileName, String mimeType})?> Function() fetch) {
    final busy = _busy.contains(key);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: busy ? null : () => _show(key, label, fetch),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: emeraldSoft, borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            busy
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.8, color: emerald))
                : Icon(icon, size: 14, color: emerald),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: emerald)),
          ],
        ),
      ),
    );
  }
}

/// Website er 8 ta profit ghor — Home card ar Profit Overview page duita-tei
class ProfitOverviewStats extends StatelessWidget {
  final Map<String, dynamic> data;

  /// Home e choto (4 ta), page e puro (8 ta)
  final bool compact;

  const ProfitOverviewStats({super.key, required this.data, this.compact = false});

  double _n(dynamic v) => v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0);

  @override
  Widget build(BuildContext context) {
    final t = Map<String, dynamic>.from(data['totals'] as Map);
    final payouts = (data['payouts'] as List).cast<Map<String, dynamic>>();
    final latest = payouts.isEmpty ? null : payouts.first;
    final next = data['nextDistribution']?.toString();
    final earned = _n(t['earned']);
    final paid = _n(t['paid']);
    final accruing = _n(t['accruing']);
    final reserved = _n(t['reserved']);

    final cells = <(String, String, String?, bool)>[
      (LanguageService.tr('Total approved investment', 'মোট অনুমোদিত বিনিয়োগ'), tk2(_n(t['principal'])), null, false),
      if (!compact)
        (LanguageService.tr('Agreed annual profit', 'চুক্তির বার্ষিক লাভ'), tk2(_n(t['annual'])),
        LanguageService.tr('${data['rateLabel']} p.a.', 'বছরে ${data['rateLabel']}'), false),
      (LanguageService.tr('Estimated monthly profit', 'আনুমানিক মাসিক লাভ'), tk2(_n(t['monthly'])), null, false),
      (
      LanguageService.tr('Total earned profit', 'মোট অর্জিত লাভ'),
      tk2(earned),
      accruing > 0 ? LanguageService.tr('incl. ${tk2(accruing)} this month', 'এ মাসের ${tk2(accruing)} সহ') : null,
      false
      ),
      (LanguageService.tr('Total disbursed', 'মোট বিতরণ'), tk2(paid), null, true),
      if (!compact) ...[
        (
        LanguageService.tr('Undisbursed profit', 'বাকি লাভ'),
        tk2(((earned - paid) * 100).round() / 100),
        reserved > 0
            ? LanguageService.tr('${tk2(reserved)} being processed', '${tk2(reserved)} প্রক্রিয়াধীন')
            : LanguageService.tr('earned, not yet paid', 'অর্জিত, এখনো দেওয়া হয়নি'),
        false
        ),
        (
        LanguageService.tr('Next disbursement', 'পরের বিতরণ'),
        next == null ? LanguageService.tr('As announced', 'ঘোষণা অনুযায়ী') : fmtDay(next),
        next == null ? null : LanguageService.tr('earliest expected date', 'সবচেয়ে আগের সম্ভাব্য তারিখ'),
        false
        ),
        (
        LanguageService.tr('Latest disbursement', 'সর্বশেষ বিতরণ'),
        latest == null ? LanguageService.tr('None yet', 'এখনো নেই') : LanguageService.tr(latest['statusEn'].toString(), latest['statusBn'].toString()),
        latest == null ? null : '${tk2(_n(latest['amountBdt']))} · ${latest['projectTitle']}',
        false
        ),
      ],
    ];

    return LayoutBuilder(builder: (_, c) {
      final w = (c.maxWidth - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final x in cells)
            Container(
              width: w,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: x.$4 ? BC.secondary : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: x.$4 ? BC.primary.withAlpha(50) : BC.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(x.$1, maxLines: 2, style: const TextStyle(fontSize: 10.5, color: BC.mutedForeground, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(x.$2,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: x.$4 ? BC.primary : BC.foreground)),
                  ),
                  if (x.$3 != null)
                    Text(x.$3!, maxLines: 2, style: const TextStyle(fontSize: 10.5, color: BC.mutedForeground, height: 1.3)),
                ],
              ),
            ),
        ],
      );
    });
  }
}

/// Home er card: choto 4 ta ghor + "See details"
class ProfitOverviewCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const ProfitOverviewCard({super.key, required this.data});

  static bool shouldShow(Map<String, dynamic>? d) =>
      d != null && (((d['rows'] as List?) ?? []).isNotEmpty || ((d['payouts'] as List?) ?? []).isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: BC.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [BC.brand500, BC.primary]),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.trending_up_rounded, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(LanguageService.tr('My Investment Profit', 'আমার বিনিয়োগের লাভ'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: BC.foreground)),
              ),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfitOverviewPage())),
                style: TextButton.styleFrom(
                  foregroundColor: BC.primary,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                child: Text(LanguageService.tr('Details →', 'বিস্তারিত →')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ProfitOverviewStats(data: data, compact: true),
        ],
      ),
    );
  }
}