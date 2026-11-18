import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/installment_schedule.dart';
import '../../../services/language_service.dart';
import '../../../services/share_math.dart';
import '../../../theme/app_colors.dart';
import '../portfolio/investment_detail_page.dart';
import 'project_invest_page.dart';

/// Share kena — puro app er bhetore (website er SharePurchaseForm er motoi):
/// taka ba share er shonkha → coupon → full / kisti → review → confirm.
/// Confirm e share reserve + order (SPO-…) hoy; tarpor sorasori payment page.
class ShareBuyPage extends StatefulWidget {
  /// Project er id ba slug
  final String projectId;

  const ShareBuyPage({super.key, required this.projectId});

  @override
  State<ShareBuyPage> createState() => _ShareBuyPageState();
}

class _ShareBuyPageState extends State<ShareBuyPage> {
  static const Color emerald = BC.primary;
  static const Color emeraldBright = BC.brand500;
  static const Color emeraldSoft = BC.secondary;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color danger = BC.destructive;
  static const Color dangerSoft = BC.destructiveMuted;
  static const Color review = BC.chart4Deep;
  static const Color reviewSoft = BC.chart4Muted;

  bool _loading = true;
  bool _failed = false;
  String _userId = '';
  Map<String, dynamic>? _ctx;

  bool _reviewing = false;
  bool _byAmount = false; // false = share er shonkha likheche
  final _sharesCtl = TextEditingController();
  final _amountCtl = TextEditingController();
  final _couponCtl = TextEditingController();
  CouponTerms? _coupon;
  String? _couponError;
  bool _couponLoading = false;

  String _plan = 'FULL';
  InstallmentSettings _settings = InstallmentSettings.defaults;
  bool _installmentsAllowed = false;
  String _today = dhakaDay();
  final List<String> _dates = [];
  final List<TextEditingController> _amts = [];

  String? _error;
  bool _submitting = false;
  String _idemKey = _newKey();

  static String _newKey() {
    final r = math.Random.secure();
    String hex(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_sharesCtl, _amountCtl, _couponCtl, ..._amts]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final user = await AuthService.getUserData();
    final uid = user?['id']?.toString() ?? '';
    final ctx = await DatabaseService.getShareBuyContext(widget.projectId, uid);
    if (!mounted) return;
    setState(() {
      _userId = uid;
      _loading = false;
      _failed = ctx == null;
      if (ctx != null) {
        final first = _ctx == null;
        _ctx = ctx;
        _settings = InstallmentSettings.fromJson(ctx['installmentSettings']);
        _today = dhakaDay();
        _installmentsAllowed = ctx['installmentsEnabled'] == true && installmentPlanOpen(_settings, _today);
        if (!_installmentsAllowed) _plan = 'FULL';
        final o = _offering;
        if (first && o != null) {
          // Shuru te shob cheye kom joto share kena jay
          final rules = DatabaseService.shareRulesOf(o);
          final min = minSharesFor(rules);
          _sharesCtl.text = '$min';
          _amountCtl.text = paisaToInput(min * rules.pricePaisa);
        }
      }
    });
  }

  // ═════════════════════════════════════════════════════════
  // HISHAB (website er calculator)
  // ═════════════════════════════════════════════════════════
  Map<String, dynamic>? get _offering => _ctx?['offering'] as Map<String, dynamic>?;
  OfferingRules get _rules => DatabaseService.shareRulesOf(_offering!);
  int get _price => _rules.pricePaisa;

  PurchaseCheck get _check {
    final o = _offering!;
    final t = _sharesCtl.text.trim();
    return checkPurchase(
      _rules,
      byAmount: _byAmount,
      amountPaisa: parseBdtToPaisa(_amountCtl.text),
      shares: RegExp(r'^\d+$').hasMatch(t) ? int.tryParse(t) : null,
      available: o['available'] as int,
      heldByInvestor: o['heldByInvestor'] as int,
      today: _today,
      tr: LanguageService.tr,
    );
  }

  /// Coupon kata gele (ar coupon er shorto mille)
  CouponQuote? _quote(PurchaseCheck c) =>
      _coupon != null && c.shares > 0 && c.errors.isEmpty ? applyCoupon(_coupon!, c.shares, _price, LanguageService.tr) : null;

  int _discount(PurchaseCheck c) {
    final q = _quote(c);
    return q != null && q.errors.isEmpty ? q.discountPaisa : 0;
  }

  int _payable(PurchaseCheck c) => c.totalPaisa - _discount(c);

  int _payableFor(int shares, [CouponTerms? coupon]) {
    final cp = coupon ?? _coupon;
    final gross = shares * _price;
    if (cp == null || shares <= 0) return gross;
    final q = applyCoupon(cp, shares, _price, LanguageService.tr);
    return q.errors.isNotEmpty ? gross : q.payablePaisa;
  }

  bool get _installment => _plan == 'INSTALLMENT' && _installmentsAllowed;

  List<(String, double)> get _rows =>
      [for (var i = 0; i < _dates.length; i++) (_dates[i], double.tryParse(_amts[i].text.trim()) ?? 0)];

  ScheduleCheck? _scheduleCheck(int payable) => _installment && payable > 0 && _dates.isNotEmpty
      ? checkSchedule(payable / 100, _rows, _settings, _today, LanguageService.tr)
      : null;

  bool get _needsApproval => _installment && _dates.isNotEmpty && needsScheduleApproval(_settings, _rows, _today);

  bool get _editableDates => _settings.allowCustomDates && _settings.fixedDates == null;

  String _amtText(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// Kisti shoman bhag (website suggest) — taka bodlale abar
  void _suggest(int totalPaisa, {int? count}) {
    if (!_installment || totalPaisa <= 0) {
      if (!_installment) _setRows(const []);
      return;
    }
    _today = dhakaDay();
    final start = _dates.isNotEmpty && _dates.first.compareTo(_today) <= 0 ? _dates.first : _today;
    final n = count ?? (_dates.isEmpty ? _settings.minCount : _dates.length);
    _setRows(suggestSchedule(totalPaisa / 100, n, start, _settings.fixedDates));
  }

  void _setRows(List<(String, double)> rows) {
    _dates
      ..clear()
      ..addAll(rows.map((r) => r.$1));
    while (_amts.length < rows.length) {
      _amts.add(TextEditingController());
    }
    if (_amts.length > rows.length) {
      final extra = _amts.sublist(rows.length);
      _amts.removeRange(rows.length, _amts.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in extra) {
          c.dispose();
        }
      });
    }
    for (var i = 0; i < rows.length; i++) {
      _amts[i].text = _amtText(rows[i].$2);
    }
  }

  void _onShares(String v) {
    setState(() {
      _byAmount = false;
      _error = null;
      final n = RegExp(r'^\d+$').hasMatch(v.trim()) ? int.tryParse(v.trim()) : null;
      _amountCtl.text = n == null ? '' : paisaToInput(n * _price);
      if (n != null && n > 0) _suggest(_payableFor(n));
    });
  }

  void _onAmount(String v) {
    setState(() {
      _byAmount = true;
      _error = null;
      final p = parseBdtToPaisa(v);
      if (p != null && _price > 0 && p % _price == 0) {
        // Kokhono gol kori na — purno share hole tobei shonkha dekhai
        _sharesCtl.text = '${p ~/ _price}';
        if (p > 0) _suggest(_payableFor(p ~/ _price));
      } else {
        _sharesCtl.text = '';
      }
    });
  }

  Future<void> _applyCoupon() async {
    final code = _couponCtl.text.trim();
    if (code.isEmpty || _couponLoading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _couponLoading = true;
      _couponError = null;
    });
    final r = await DatabaseService.previewShareCoupon(userId: _userId, offeringId: _offering!['id'].toString(), code: code);
    if (!mounted) return;
    setState(() {
      _couponLoading = false;
      if (r.terms == null) {
        _coupon = null;
        _couponError = r.error;
        return;
      }
      _coupon = r.terms;
      _couponCtl.text = r.terms!.code;
      _error = null;
      final c = _check;
      if (c.shares > 0) _suggest(_payableFor(c.shares, r.terms));
    });
  }

  void _removeCoupon() {
    setState(() {
      _coupon = null;
      _couponCtl.clear();
      _couponError = null;
      _error = null;
      final c = _check;
      if (c.shares > 0) _suggest(c.shares * _price);
    });
  }

  DateTime _localDate(String day) =>
      DateTime(int.parse(day.substring(0, 4)), int.parse(day.substring(5, 7)), int.parse(day.substring(8, 10)));

  String _dayOfPicked(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(int i) async {
    final first = i == 0 ? DateTime(1990, 1, 1) : _localDate(addDaysToDay(_dates[i - 1], 1));
    final last = i == 0 ? _localDate(_today) : DateTime(2100, 12, 31);
    var initial = _localDate(_dates[i]);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: LanguageService.tr('${ordinal(i + 1)} installment date', '${i + 1} নং কিস্তির তারিখ'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: emerald)),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final day = _dayOfPicked(picked);
    setState(() {
      _error = null;
      if (i == 0 && !_editableDates) {
        final moved = monthlyDates(day, _dates.length);
        for (var k = 0; k < _dates.length; k++) {
          _dates[k] = moved[k];
        }
      } else {
        _dates[i] = day;
      }
    });
  }

  // ═════════════════════════════════════════════════════════
  // REVIEW + CONFIRM
  // ═════════════════════════════════════════════════════════
  void _review() {
    FocusScope.of(context).unfocus();
    final c = _check;
    final q = _quote(c);
    final sc = _scheduleCheck(_payable(c));
    final problem = c.errors.isNotEmpty
        ? c.errors.first
        : (q != null && q.errors.isNotEmpty)
        ? q.errors.first
        : (_installment && _dates.isEmpty)
        ? LanguageService.tr('Set up your installment schedule', 'কিস্তির সময়সূচি ঠিক করুন')
        : (sc != null && sc.errors.isNotEmpty)
        ? sc.errors.first
        : null;
    setState(() {
      _error = problem;
      if (problem == null) _reviewing = true;
    });
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    final c = _check;
    final payable = _payable(c);
    final discount = _discount(c);
    setState(() {
      _submitting = true;
      _error = null;
    });
    final r = await DatabaseService.createSharePurchase(
      userId: _userId,
      projectId: _ctx!['projectId'].toString(),
      shares: c.shares,
      expectedPricePaisa: _price,
      expectedTotalPaisa: payable,
      couponCode: _coupon != null && discount > 0 ? _coupon!.code : null,
      paymentPlan: _installment ? 'INSTALLMENT' : 'FULL',
      schedule: _installment ? _rows : null,
      idempotencyKey: _idemKey,
    );
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() {
        _submitting = false;
        _error = r['message']?.toString() ?? LanguageService.tr('Could not place your order.', 'অর্ডার করা যায়নি।');
      });
      return;
    }

    final investmentId = r['investmentId'].toString();
    final order = r['orderNumber']?.toString() ?? '';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: emerald,
      content: Text(r['needsScheduleApproval'] == true
          ? LanguageService.tr('Order $order placed. Your installment dates were sent for approval.',
          'অর্ডার $order হয়েছে। কিস্তির তারিখ অনুমোদনের জন্য পাঠানো হয়েছে।')
          : LanguageService.tr('Order $order placed. Now pay and upload the proof.',
          'অর্ডার $order হয়েছে। এখন টাকা দিয়ে প্রুফ জমা দিন।')),
    ));

    // Website: dates approval lagle investment page e, na hole sorasori payment e
    Widget next = InvestmentDetailPage(investmentId: investmentId);
    if (r['needsScheduleApproval'] != true) {
      final data = await DatabaseService.getInvestmentForPayment(investmentId, _userId);
      if (!mounted) return;
      if (data != null) next = ProjectInvestPage(existing: data);
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => next));
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) => PopScope(
        canPop: !_reviewing && !_submitting,
        onPopInvokedWithResult: (didPop, _) {
          // Review theke back = form e fire jai (website "← Back")
          if (!didPop && _reviewing && !_submitting) {
            setState(() {
              _reviewing = false;
              _error = null;
              _idemKey = _newKey();
            });
          }
        },
        child: Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 54,
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              _reviewing
                  ? LanguageService.tr('Confirm Purchase', 'কেনা নিশ্চিত করুন')
                  : LanguageService.tr('Buy Shares', 'শেয়ার কিনুন'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 17.5),
            ),
          ),
          bottomNavigationBar: _ctx == null || _offering == null || _closed != null ? null : _bottomBar(),
          body: _loading && _ctx == null
              ? const Center(
              child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4)))
              : _failed && _ctx == null
              ? _message(Icons.wifi_off_rounded, LanguageService.tr('Could not load', 'লোড করা যায়নি'),
              LanguageService.tr('Please check your internet connection.', 'ইন্টারনেট সংযোগ চেক করুন।'), retry: true)
              : _offering == null
              ? _message(Icons.hourglass_empty_rounded,
              LanguageService.tr('Share offering opens soon', 'শেয়ার অফার শীঘ্রই খুলবে'),
              LanguageService.tr('This project is not selling shares yet.', 'এই প্রজেক্টে এখনো শেয়ার বিক্রি শুরু হয়নি।'))
              : AbsorbPointer(absorbing: _submitting, child: _reviewing ? _reviewBody() : _formBody()),
        ),
      ),
    );
  }

  String? get _closed {
    final c = _ctx!;
    if (c['deleted'] == true || c['projectType'] != 'SHARE_BUYING') {
      return LanguageService.tr("This project doesn't sell shares", 'এই প্রজেক্টে শেয়ার বিক্রি হয় না');
    }
    if (c['projectStatus'] != 'FUNDRAISING') {
      return LanguageService.tr('This project is not accepting share purchases right now', 'এই প্রজেক্টে এখন শেয়ার কেনা যাবে না');
    }
    return offeringClosedReason(_rules, _today, LanguageService.tr);
  }

  // ─── Form ─────────────────────────────────────────────────
  Widget _formBody() {
    final closed = _closed;
    final c = _check;
    final discount = _discount(c);
    final payable = _payable(c);
    final quote = _quote(c);
    final couponProblem = quote != null && quote.errors.isNotEmpty ? quote.errors.first : null;
    final showCheckError = c.errors.isNotEmpty && (_amountCtl.text.isNotEmpty || _sharesCtl.text.isNotEmpty);

    return RefreshIndicator(
      onRefresh: _load,
      color: emerald,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
        children: [
          _hero(),
          const SizedBox(height: 12),
          if (closed != null)
            _notice(Icons.lock_clock_outlined, review, LanguageService.tr('Not open for purchase', 'এখন কেনা যাবে না'), closed)
          else ...[
            _card(
              step: 1,
              title: LanguageService.tr('How many shares?', 'কতটি শেয়ার কিনবেন?'),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amountCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^[\d,]*\.?\d{0,2}'))],
                        onChanged: _onAmount,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: ink),
                        decoration: _dec(
                          _coupon != null
                              ? LanguageService.tr('Share value (BDT)', 'শেয়ারের মূল্য (টাকা)')
                              : LanguageService.tr('Amount (BDT)', 'পরিমাণ (টাকা)'),
                          Icons.payments_outlined,
                        ).copyWith(prefixText: '৳ '),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _sharesCtl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: _onShares,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: ink),
                        decoration: _dec(LanguageService.tr('Shares', 'শেয়ার'), Icons.pie_chart_outline_rounded),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  LanguageService.tr('Type either one — the other is worked out from the share price.',
                      'যেকোনো একটি লিখুন — অন্যটি শেয়ারের দাম থেকে হিসাব হবে।'),
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
                const SizedBox(height: 12),
                _couponField(couponProblem),
                const SizedBox(height: 12),
                _summary(c, discount, payable),
              ],
            ),
            if (_installmentsAllowed) ...[
              const SizedBox(height: 10),
              _card(
                step: 2,
                title: LanguageService.tr('How will you pay?', 'কীভাবে পরিশোধ করবেন?'),
                children: [
                  Row(
                    children: [
                      _planChip('FULL', LanguageService.tr('Full payment', 'একবারে'), Icons.account_balance_wallet_outlined, payable),
                      const SizedBox(width: 8),
                      _planChip('INSTALLMENT', LanguageService.tr('Installments', 'কিস্তিতে'), Icons.calendar_month_outlined,
                          payable),
                    ],
                  ),
                  if (_installment) ...[
                    const SizedBox(height: 6),
                    Text(_settings.summary(LanguageService.tr), style: const TextStyle(fontSize: 11, color: muted)),
                  ],
                ],
              ),
            ],
            if (_installment && payable > 0 && c.errors.isEmpty && _dates.isNotEmpty) ...[
              const SizedBox(height: 10),
              _planner(payable),
            ],
            if (_error != null || showCheckError) ...[
              const SizedBox(height: 10),
              _errorBox(_error ?? c.errors.first),
            ],
          ],
        ],
      ),
    );
  }

  Widget _hero() {
    final o = _offering!;
    final r = _rules;
    final held = o['heldByInvestor'] as int;
    final max = r.maxSharesPerInvestor;
    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [emeraldBright, emerald], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(o['legalCompanyName']?.toString() ?? '',
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(_ctx!['title']?.toString() ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, height: 1.25)),
          const SizedBox(height: 10),
          Container(height: 1, color: Colors.white24),
          const SizedBox(height: 10),
          Row(
            children: [
              stat(LanguageService.tr('Share price', 'শেয়ারের দাম'), formatBdtPaisa(r.pricePaisa)),
              stat(LanguageService.tr('Minimum', 'সর্বনিম্ন'), formatBdtPaisa(r.minInvestmentPaisa)),
              stat(LanguageService.tr('Available', 'বাকি শেয়ার'), formatShares(math.max(0, o['available'] as int))),
            ],
          ),
          if (max != null) ...[
            const SizedBox(height: 8),
            Text(
              LanguageService.tr(
                'Limit per investor: ${formatShares(max)} shares${held > 0 ? ' · you hold or have reserved ${formatShares(held)}' : ''}',
                'একজনের সর্বোচ্চ: ${formatShares(max)} টি${held > 0 ? ' · আপনার আছে / রিজার্ভ ${formatShares(held)} টি' : ''}',
              ),
              style: const TextStyle(color: Colors.white70, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _couponField(String? couponProblem) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.confirmation_number_outlined, size: 15, color: muted),
            const SizedBox(width: 4),
            Text(LanguageService.tr('Coupon code (optional)', 'কুপন কোড (ঐচ্ছিক)'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: muted)),
          ],
        ),
        const SizedBox(height: 6),
        if (_coupon != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: emeraldSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: emerald.withAlpha(90)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_rounded, size: 16, color: emerald),
                const SizedBox(width: 6),
                Text(_coupon!.code,
                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, color: ink, fontSize: 13)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('· ${describeCoupon(_coupon!, LanguageService.tr)}',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: muted)),
                ),
                InkWell(
                  onTap: _removeCoupon,
                  child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.close_rounded, size: 17, color: muted)),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _couponCtl,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
                    TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase())),
                  ],
                  onChanged: (_) => setState(() => _couponError = null),
                  onSubmitted: (_) => _applyCoupon(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, fontWeight: FontWeight.w700, color: ink),
                  decoration: _dec(LanguageService.tr('Enter code', 'কোড লিখুন'), Icons.local_offer_outlined),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: _couponCtl.text.trim().isEmpty || _couponLoading ? null : _applyCoupon,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: emerald,
                    side: const BorderSide(color: emerald),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _couponLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: emerald))
                      : Text(LanguageService.tr('Apply', 'প্রয়োগ'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        if (_couponError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_couponError!, style: const TextStyle(fontSize: 11.5, color: danger)),
          ),
        if (couponProblem != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(couponProblem, style: const TextStyle(fontSize: 11.5, color: review)),
          ),
      ],
    );
  }

  Widget _summary(PurchaseCheck c, int discount, int payable) {
    Widget row(String a, String b, {Color? color, bool strike = false, bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Expanded(child: Text(a, style: const TextStyle(fontSize: 12.5, color: muted))),
          Text(b,
              style: TextStyle(
                fontSize: bold ? 14.5 : 13,
                fontWeight: FontWeight.w800,
                color: color ?? ink,
                decoration: strike ? TextDecoration.lineThrough : null,
              )),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(12), border: Border.all(color: line)),
      child: Column(
        children: [
          row(LanguageService.tr('Calculated shares', 'হিসাবকৃত শেয়ার'), c.shares > 0 ? formatShares(c.shares) : '—'),
          if (discount > 0) ...[
            row(LanguageService.tr('Share value', 'শেয়ারের মূল্য'), formatBdtPaisa(c.totalPaisa), color: muted, strike: true),
            row(LanguageService.tr('Coupon discount', 'কুপন ছাড়'), '− ${formatBdtPaisa(discount)}', color: emerald),
          ],
          row(LanguageService.tr('Total payable', 'মোট পরিশোধ'), payable > 0 ? formatBdtPaisa(payable) : '—', bold: true),
          row(LanguageService.tr('Payment plan', 'পরিশোধের ধরন'),
              _installment ? LanguageService.tr('Installments', 'কিস্তিতে') : LanguageService.tr('Full payment', 'একবারে')),
        ],
      ),
    );
  }

  Widget _planChip(String key, String label, IconData icon, int payable) {
    final on = _plan == key;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() {
          _plan = key;
          _error = null;
          if (key == 'INSTALLMENT') {
            _suggest(payable);
          } else {
            _setRows(const []);
          }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
          decoration: BoxDecoration(
            color: on ? emerald : ivory,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? emerald : line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: on ? Colors.white : emerald),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : ink)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Kisti-r planner (website InstallmentPlanner) ─────────
  Widget _planner(int payable) {
    final st = _settings;
    final fixed = st.fixedDates != null;
    final counts = [for (var n = st.minCount; n <= st.maxCount; n++) n];
    final check = _scheduleCheck(payable);
    final backdated = _dates.isNotEmpty && isBackdated(_rows, _today);
    final remaining = check?.remainingPaisa ?? 0;
    final otherErrors = (check?.errors ?? const <String>[])
        .where((e) => !e.startsWith('The total installment amount') && !e.startsWith('কিস্তিগুলোর যোগফল'))
        .toList();

    return _card(
      step: 3,
      title: LanguageService.tr('Installment schedule', 'কিস্তির সময়সূচি'),
      children: [
        Row(
          children: [
            Text(LanguageService.tr('Installments', 'কিস্তি'),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _suggest(payable, count: _dates.isEmpty ? null : _dates.length)),
              style: TextButton.styleFrom(
                foregroundColor: emerald,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
              label: Text(LanguageService.tr('Split evenly', 'সমান ভাগ')),
            ),
          ],
        ),
        if (counts.length > 1 && !fixed) ...[
          const SizedBox(height: 4),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: counts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final n = counts[i];
                final on = _dates.length == n;
                return GestureDetector(
                  onTap: () => setState(() {
                    _error = null;
                    _suggest(payable, count: n);
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? emerald : ivory,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: on ? emerald : line),
                    ),
                    child: Text('$n', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? Colors.white : ink)),
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 10),
        for (var i = 0; i < _dates.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                child: Padding(
                  padding: const EdgeInsets.only(top: 11),
                  child: Text(ordinal(i + 1), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ink)),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(builder: (_) {
                      final canEdit = !fixed && (i == 0 || _editableDates);
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: canEdit ? () => _pickDate(i) : null,
                        child: Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: canEdit ? ivory : BC.muted,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: line),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.event_outlined, size: 16, color: canEdit ? emerald : muted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(fmtDay(_dates[i]),
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: canEdit ? ink : muted)),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    if (i == 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          backdated
                              ? LanguageService.tr('Paid earlier on this day', 'এই দিনে আগেই দেওয়া')
                              : LanguageService.tr('Payable now', 'এখন দেবেন'),
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 118,
                child: TextField(
                  controller: _amts[i],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  onChanged: (_) => setState(() => _error = null),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink),
                  decoration: _dec('', null).copyWith(prefixText: '৳ ', labelText: null),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(color: remaining == 0 ? emeraldSoft : reviewSoft, borderRadius: BorderRadius.circular(9)),
          child: Text(
            remaining == 0
                ? LanguageService.tr('Adds up to ${formatBdtPaisa(payable)} · ${_dates.length} installments',
                '${formatBdtPaisa(payable)} মিলেছে · ${_dates.length} টি কিস্তি')
                : remaining > 0
                ? LanguageService.tr('${tkPaisa(remaining)} still to schedule', 'আরও ${tkPaisa(remaining)} ভাগ করা বাকি')
                : LanguageService.tr('${tkPaisa(-remaining)} more than the total', 'মোটের চেয়ে ${tkPaisa(-remaining)} বেশি'),
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: remaining == 0 ? emerald : review),
          ),
        ),
        for (final e in otherErrors) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, size: 15, color: danger),
              const SizedBox(width: 6),
              Expanded(child: Text(e, style: const TextStyle(fontSize: 12, color: danger, height: 1.35))),
            ],
          ),
        ],
        if (_needsApproval) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: reviewSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: review.withAlpha(50)),
            ),
            child: Text(
              LanguageService.tr(
                  'You chose your own dates, so our team reviews them first. You can pay once they are approved — we\'ll notify you.',
                  'আপনি নিজে তারিখ বেছেছেন, তাই আগে আমাদের টিম যাচাই করবে। অনুমোদন হলে টাকা দিতে পারবেন — আমরা জানাব।'),
              style: const TextStyle(fontSize: 12, color: review, height: 1.4),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Review ───────────────────────────────────────────────
  Widget _reviewBody() {
    final o = _offering!;
    final c = _check;
    final discount = _discount(c);
    final payable = _payable(c);
    final schedule = _rows;
    final company = o['legalCompanyName']?.toString() ?? '';
    final hold = o['reservationHoldDays'] as int?;
    final terms = o['terms']?.toString() ?? '';
    final name = _ctx!['investorName']?.toString() ?? '';

    final lines = <(String, String, Color?)>[
      (LanguageService.tr('Project', 'প্রজেক্ট'), _ctx!['title']?.toString() ?? '', null),
      (LanguageService.tr('Issuing company', 'ইস্যুকারী কোম্পানি'), company, null),
      if (name.isNotEmpty) (LanguageService.tr('Shareholder (buyer)', 'শেয়ারহোল্ডার (ক্রেতা)'), name, null),
      (LanguageService.tr('Share price', 'শেয়ারের দাম'), formatBdtPaisa(_price), null),
      (LanguageService.tr('Number of shares', 'শেয়ারের সংখ্যা'), formatShares(c.shares), null),
      if (discount > 0 && _coupon != null) ...[
        (LanguageService.tr('Share value', 'শেয়ারের মূল্য'), formatBdtPaisa(c.totalPaisa), null),
        (LanguageService.tr('Coupon discount (${_coupon!.code})', 'কুপন ছাড় (${_coupon!.code})'), '− ${formatBdtPaisa(discount)}',
        emerald),
      ],
      (LanguageService.tr('Total payable', 'মোট পরিশোধ'), formatBdtPaisa(payable), emerald),
      (
      LanguageService.tr('Payment plan', 'পরিশোধের ধরন'),
      _installment
          ? LanguageService.tr('Installments (${schedule.length})', 'কিস্তি (${schedule.length})')
          : LanguageService.tr('Full payment', 'একবারে'),
      null
      ),
    ];

    final bullets = <(String, bool)>[
      (
      LanguageService.tr(
          'Your ${formatShares(c.shares)} shares are reserved for you at ${formatBdtPaisa(_price)} each${hold != null ? '; if no payment is submitted within $hold days the reservation is released' : ''}.',
          'আপনার ${formatShares(c.shares)} টি শেয়ার প্রতিটি ${formatBdtPaisa(_price)} দামে রিজার্ভ থাকবে${hold != null ? '; $hold দিনের মধ্যে পেমেন্ট জমা না দিলে রিজার্ভ ছেড়ে দেওয়া হবে' : ''}।'),
      false
      ),
      if (discount > 0 && _coupon != null)
        (
        LanguageService.tr(
            'Coupon ${_coupon!.code} saves you ${formatBdtPaisa(discount)}: you pay ${formatBdtPaisa(payable)} for shares worth ${formatBdtPaisa(c.totalPaisa)}. Your deed records both.',
            'কুপন ${_coupon!.code} এ ${formatBdtPaisa(discount)} সাশ্রয়: ${formatBdtPaisa(c.totalPaisa)} মূল্যের শেয়ারে দেবেন ${formatBdtPaisa(payable)}। ডিডে দুটোই থাকবে।'),
        false
        ),
      (
      LanguageService.tr('Pay by bank transfer, cheque or cash and upload proof; finance verifies each payment and you get a receipt.',
          'ব্যাংক ট্রান্সফার, চেক বা ক্যাশে টাকা দিয়ে প্রুফ দিন; ফাইন্যান্স প্রতিটি পেমেন্ট যাচাই করবে এবং রসিদ পাবেন।'),
      false
      ),
      (
      LanguageService.tr(
          'Payment does not by itself make you a shareholder. Your shares are confirmed only once $company records the allotment in its share register and it is verified.',
          'শুধু টাকা দিলেই শেয়ারহোল্ডার হওয়া যায় না। $company শেয়ার রেজিস্টারে বরাদ্দ লিখে যাচাই করলে তবেই আপনার শেয়ার নিশ্চিত হবে।'),
      true
      ),
      if (_installment)
        (
        schedule.isNotEmpty && schedule.first.$1.compareTo(_today) < 0
            ? LanguageService.tr(
            'Your schedule starts on ${fmtDay(schedule.first.$1)}: after our team approves it, upload the proof of each installment you already paid offline.',
            'আপনার সময়সূচি ${fmtDay(schedule.first.$1)} থেকে: টিম অনুমোদন দিলে আগে দেওয়া প্রতিটি কিস্তির প্রুফ দিন।')
            : LanguageService.tr(
            "Only the first installment is payable now${_needsApproval ? ' (after our team approves your dates)' : ''}; you'll be reminded before each later date.",
            'এখন শুধু প্রথম কিস্তি দিতে হবে${_needsApproval ? ' (টিম তারিখ অনুমোদন দেওয়ার পর)' : ''}; পরের প্রতিটি তারিখের আগে মনে করিয়ে দেওয়া হবে।'),
        false
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
      children: [
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
          child: Column(
            children: [
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: line),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(lines[i].$1, style: const TextStyle(fontSize: 12.5, color: muted))),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(lines[i].$2,
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: lines[i].$3 ?? ink)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_installment) ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
            child: Column(
              children: [
                _schedRow(LanguageService.tr('No.', 'নং'), LanguageService.tr('Date', 'তারিখ'),
                    LanguageService.tr('Amount', 'পরিমাণ'), header: true),
                for (var i = 0; i < schedule.length; i++)
                  _schedRow(
                    '${i + 1}',
                    '${fmtDay(schedule[i].$1)}${i == 0 && schedule[i].$1.compareTo(_today) >= 0 ? (_needsApproval ? LanguageService.tr(' · on approval', ' · অনুমোদনের পর') : LanguageService.tr(' · now', ' · এখন')) : ''}',
                    tkPaisa(toPaisa(schedule[i].$2)),
                  ),
                _schedRow(LanguageService.tr('Total', 'মোট'), '', formatBdtPaisa(payable), header: true),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: emeraldSoft, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final b in bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(Icons.circle, size: 5, color: emerald),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(b.$1,
                            style: TextStyle(
                                fontSize: 12, height: 1.4, color: b.$2 ? ink : muted, fontWeight: b.$2 ? FontWeight.w700 : null)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (terms.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: line)),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                iconColor: emerald,
                collapsedIconColor: muted,
                title: Text(LanguageService.tr('Terms and conditions', 'শর্তাবলী'),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink)),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                children: [
                  Text(terms, style: const TextStyle(fontSize: 12, color: muted, height: 1.45)),
                ],
              ),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          _errorBox(_error!),
        ],
      ],
    );
  }

  Widget _schedRow(String a, String b, String c, {bool header = false}) => Container(
    color: header ? ivory : null,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(a, style: TextStyle(fontSize: 12, fontWeight: header ? FontWeight.w800 : FontWeight.w600, color: ink)),
        ),
        Expanded(child: Text(b, style: TextStyle(fontSize: 12, color: header ? muted : ink))),
        Text(c, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ink)),
      ],
    ),
  );

  // ─── Bottom bar ───────────────────────────────────────────
  Widget _bottomBar() {
    final c = _check;
    final quote = _quote(c);
    final sc = _scheduleCheck(_payable(c));
    final blocked = c.errors.isNotEmpty ||
        (quote != null && quote.errors.isNotEmpty) ||
        (sc != null && sc.errors.isNotEmpty) ||
        (_installment && _dates.isEmpty);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: line))),
        child: SizedBox(
          height: 46,
          child: _reviewing
              ? Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting
                      ? null
                      : () => setState(() {
                    _reviewing = false;
                    _error = null;
                    _idemKey = _newKey();
                  }),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ink,
                    side: const BorderSide(color: line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(LanguageService.tr('← Back', '← ফিরে যান'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _submitting ? null : _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: emerald,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: emerald.withAlpha(140),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(
                    _needsApproval
                        ? LanguageService.tr('Submit for Approval', 'অনুমোদনের জন্য পাঠান')
                        : LanguageService.tr('Confirm Purchase', 'কেনা নিশ্চিত করুন'),
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          )
              : FilledButton(
            onPressed: blocked ? null : _review,
            style: FilledButton.styleFrom(
              backgroundColor: emerald,
              foregroundColor: Colors.white,
              disabledBackgroundColor: emerald.withAlpha(110),
              disabledForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              _payable(c) > 0 && c.errors.isEmpty
                  ? LanguageService.tr('Review ${formatBdtPaisa(_payable(c))} →', '${formatBdtPaisa(_payable(c))} দেখে নিন →')
                  : LanguageService.tr('Review →', 'দেখে নিন →'),
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // SHARED
  // ═════════════════════════════════════════════════════════
  Widget _message(IconData icon, String title, String sub, {bool retry = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: emerald),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
          const SizedBox(height: 3),
          Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: muted)),
          if (retry) ...[
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(backgroundColor: emerald, foregroundColor: Colors.white),
              child: Text(LanguageService.tr('Try again', 'আবার চেষ্টা করুন')),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _card({int? step, required String title, required List<Widget> children}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (step != null)
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: emerald, shape: BoxShape.circle),
                child: Text('$step', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            if (step != null) const SizedBox(width: 9),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink))),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );

  InputDecoration _dec(String label, IconData? icon) => InputDecoration(
    labelText: label.isEmpty ? null : label,
    labelStyle: const TextStyle(fontSize: 12.5, color: muted),
    prefixIcon: icon == null ? null : Icon(icon, color: emerald, size: 18),
    prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
    isDense: true,
    filled: true,
    fillColor: ivory,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line)),
    focusedBorder:
    OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: emerald, width: 1.4)),
  );

  Widget _notice(IconData icon, Color c, String title, String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: reviewSoft, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withAlpha(60))),
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

  Widget _errorBox(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(color: dangerSoft, borderRadius: BorderRadius.circular(10)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, size: 16, color: danger),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, color: danger, height: 1.35))),
      ],
    ),
  );
}