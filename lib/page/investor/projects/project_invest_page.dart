import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/cloudinary_service.dart';
import '../../../services/database_service.dart';
import '../../../services/installment_schedule.dart';
import '../../../services/language_service.dart';
import '../portfolio/investments_page.dart';
import '../../../theme/app_colors.dart';

/// Project e invest: taka + payment er dhoron + proof — ek page e.
/// Confirm korle investment "Pending" hoy, admin approve korle dashboard e ashe.
/// Website er motoi: ekbare (FULL) ba kistite (INSTALLMENT) deya jay; protita
/// madhyom (bank / cash / cheque) alada part hishebe jachai hoy.
///
/// Kisti: project er niyome (installmentSettings) ekta schedule — koyta kisti,
/// kon tarikhe koto. Prothom kisti ekhon dite hoy, baki gula tarikh moto
/// (website er InstallmentPlanner + installment.service er hubohu niyom).
class ProjectInvestPage extends StatefulWidget {
  /// ProjectDetailPage er _project map (getProjectDetail theke) — notun invest
  final Map<String, dynamic>? project;

  /// Payment baki thaka investment (InvestmentsPage er item ba
  /// DatabaseService.getInvestmentForPayment: id, title, amount, returnMin,
  /// returnMax, bankAccounts, paymentPlan, paidApproved, paidPending; share
  /// order hole subtitle + isShare).
  /// Thakle shudhu baki taka deya hoy, shofol hole pop(true).
  final Map<String, dynamic>? existing;

  const ProjectInvestPage({super.key, this.project, this.existing})
      : assert(project != null || existing != null);

  @override
  State<ProjectInvestPage> createState() => _ProjectInvestPageState();
}

class _ProjectInvestPageState extends State<ProjectInvestPage> {
  // ─── Palette — website er rong (lib/theme/app_colors.dart) ───
  static const Color emerald = BC.primary;
  static const Color emeraldBright = BC.brand500; // home page er moto
  static const Color emeraldSoft = BC.secondary;
  static const Color terracotta = BC.destructive;
  static const Color terracottaSoft = BC.destructiveMuted;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color danger = BC.destructive;
  static const Color dangerSoft = BC.destructiveMuted;

  /// Website er split-payment.ts er 6 ta option (ek bar e shorbochcho 2 ta madhyom)
  static const List<(String, Set<String>)> _options = [
    ('BANK', {'BANK'}),
    ('CHEQUE', {'CHEQUE'}),
    ('CASH', {'CASH'}),
    ('BANK_CASH', {'BANK', 'CASH'}),
    ('BANK_CHEQUE', {'BANK', 'CHEQUE'}),
    ('CHEQUE_CASH', {'CHEQUE', 'CASH'}),
  ];

  /// Website er CASH_RECEIVERS — DB te value (CEO / MD / CHAIRMAN / FINANCE_TEAM)
  static const List<(String, String, String)> _cashReceivers = [
    ('CEO', 'CEO', 'সিইও'),
    ('MD', 'Managing Director (MD)', 'ব্যবস্থাপনা পরিচালক (এমডি)'),
    ('CHAIRMAN', 'Chairman', 'চেয়ারম্যান'),
    ('FINANCE_TEAM', 'Finance Team', 'ফাইন্যান্স টিম'),
  ];

  /// Protita madhyom e shorbochcho koyta proof (website MAX_PROOF_FILES)
  static const int _maxProofs = 3;

  /// Kistir shorbonimno taka (website MIN_INSTALLMENT_BDT), shesh kisti baad e
  static const double _minInstallment = 1000;

  final _amountController = TextEditingController();
  final _payNowController = TextEditingController();
  final _bankAmountController = TextEditingController();
  final _cashAmountController = TextEditingController();
  final _chequeAmountController = TextEditingController();
  final _trxController = TextEditingController();
  final _chequeNoController = TextEditingController();
  final _cashReceiptController = TextEditingController();
  final _picker = ImagePicker();

  String _plan = 'FULL'; // FULL / INSTALLMENT
  String? _option; // _options er key
  int _bankIndex = 0;
  String? _cashReceiver;

  /// Madhyom → proof chobi (bytes + file), protita te 3 ta porjonto
  final Map<String, List<(Uint8List, File)>> _proofs = {'BANK': [], 'CHEQUE': [], 'CASH': []};

  bool _submitting = false;
  String _stage = '';
  String? _error;

  // ─── Kisti-r schedule (website er InstallmentPlanner) ───
  InstallmentSettings _settings = InstallmentSettings.defaults;

  /// Project kisti nay + plan ekhono khola (admin er tarikh periye jayni)
  bool _installmentsAllowed = false;
  final String _today = dhakaDay();

  /// Notun schedule: protita kisti-r tarikh ("YYYY-MM-DD") ar takar ghor
  final List<String> _dates = [];
  final List<TextEditingController> _amts = [];

  /// User nije "ekhon dicchen" bodlale ar automatic bodlai na
  bool _payNowTouched = false;

  /// Baki thaka investment er schedule (getInvestmentSchedule) — null = nei / ekhono ase nai
  Map<String, dynamic>? _schedule;
  bool _scheduleLoading = false;

  /// Baki investment: kon kisti porjonto dicchen (website ?installment=n)
  int? _payUpTo;

  @override
  void dispose() {
    for (final c in [
      _amountController,
      _payNowController,
      _bankAmountController,
      _cashAmountController,
      _chequeAmountController,
      _trxController,
      _chequeNoController,
      _cashReceiptController,
      ..._amts,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  late final Map<String, dynamic> _project;

  bool get _isExisting => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isExisting) {
      final e = widget.existing!;
      final total = _num(e['amount']);
      _plan = (e['paymentPlan']?.toString() ?? 'FULL').toUpperCase() == 'INSTALLMENT' ? 'INSTALLMENT' : 'FULL';
      _project = {
        'title': e['title']?.toString() ?? '',
        'returnMin': e['returnMin'],
        'returnMax': e['returnMax'],
        'bankAccounts': e['bankAccounts'] ?? const [],
        'minInvestmentBdt': 0,
        'maxInvestmentBdt': null,
        'remainingBdt': total,
        'subtitle': e['subtitle'],
        'isShare': e['isShare'] == true,
      };
      _amountController.text = total.toStringAsFixed(0);
      _payNowController.text = _outstanding.toStringAsFixed(0);
      _loadSchedule();
    } else {
      _project = widget.project!;
      _settings = InstallmentSettings.fromJson(_project['installmentSettings']);
      _installmentsAllowed =
          _project['installmentsEnabled'] == true && installmentPlanOpen(_settings, _today);
      final minInv = _num(_project['minInvestmentBdt']);
      if (minInv > 0 && minInv <= _cap) _amountController.text = minInv.toStringAsFixed(0);
      // Shuru thekei jaanai — deadline periye gele confirm kaj korbe na
      _error = _closedReason;
    }
  }

  // ═════════════════════════════════════════════════════════
  // KISTI-R SCHEDULE
  // ═════════════════════════════════════════════════════════
  String _amtText(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// Baki thaka investment er kisti (thakle) — website er getScheduleState
  Future<void> _loadSchedule() async {
    final user = await AuthService.getUserData();
    final uid = user?['id']?.toString() ?? '';
    if (uid.isEmpty || !mounted) return;
    setState(() => _scheduleLoading = true);
    final s = await DatabaseService.getInvestmentSchedule(widget.existing!['id'].toString(), uid);
    if (!mounted) return;
    setState(() {
      _scheduleLoading = false;
      if (s != null && s['hasSchedule'] == true) {
        _schedule = s;
        _plan = 'INSTALLMENT';
        _setPayNowFor((s['summary'] as ScheduleSummary).next?.number);
        if (s['awaitingApproval'] == true) _payNowController.text = '0';
      }
    });
  }

  ScheduleSummary? get _summary => _schedule?['summary'] as ScheduleSummary?;

  /// Baki investment e ekhon shorbochcho koto (schedule thakle tar niyome)
  double get _maxNow {
    if (!_isExisting) return _amount;
    final s = _schedule;
    if (s == null) return _outstanding;
    return math.min(_outstanding, _num(s['maxPayableNowBdt']));
  }

  bool get _datesBlocked => _isExisting && _schedule?['awaitingApproval'] == true;

  /// n-tom kisti porjonto: ager shob khola kisti + eta (website er pay page er motoi).
  /// Ekhon deya jay tar beshi hole shudhu prothom khola kisti.
  void _setPayNowFor(int? n) {
    final sum = _summary;
    if (sum == null || n == null) return;
    final open = sum.installments.where((a) => a.openPaisa > 0).toList();
    if (open.isEmpty) return;
    final max = toPaisa(_maxNow);
    var idx = open.indexWhere((a) => a.number == n);
    if (idx < 0) idx = 0;
    var amount = open.take(idx + 1).fold<int>(0, (t, a) => t + a.openPaisa);
    var target = open[idx].number;
    if (amount > max) {
      target = open.first.number;
      amount = math.min(open.first.openPaisa, max);
    }
    _payUpTo = target;
    _payNowController.text = _amtText(amount / 100);
  }

  String? get _installmentIdToPay {
    final ids = _schedule?['installmentIds'];
    if (ids is! Map || _payUpTo == null) return null;
    return ids[_payUpTo]?.toString();
  }

  /// Notun investment er kisti plan banacche
  bool get _planning => !_isExisting && _installment;

  List<(String, double)> get _rows =>
      [for (var i = 0; i < _dates.length; i++) (_dates[i], double.tryParse(_amts[i].text.trim()) ?? 0)];

  bool get _editableDates => _settings.allowCustomDates && _settings.fixedDates == null;

  ScheduleCheck? get _check => _planning && _amount > 0 && _dates.isNotEmpty
      ? checkSchedule(_amount, _rows, _settings, _today, LanguageService.tr)
      : null;

  /// Nijer beche neya tarikh: age admin approve korbe, tarpor taka (website needsScheduleApproval)
  bool get _needsApproval => _planning && _dates.isNotEmpty && needsScheduleApproval(_settings, _rows, _today);

  /// Ekhon kono taka neya hobe na (approval er opekkhay)
  bool get _noPaymentNow => _needsApproval || _datesBlocked;

  /// Shoman bhag, aj theke mashik (ba project er tarikh) — website suggestedRows
  void _suggest({int? count}) {
    if (!_planning || _amount <= 0) {
      _setRows(const []);
      return;
    }
    // Age theke (offline e deya) shuru-r tarikh thakle sheta rakhi
    final start = _dates.isNotEmpty && _dates.first.compareTo(_today) <= 0 ? _dates.first : _today;
    final n = count ?? (_dates.isEmpty ? _settings.minCount : _dates.length);
    _setRows(suggestSchedule(_amount, n, start, _settings.fixedDates));
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
    _syncPayNow();
  }

  /// Notun kisti plan: "ekhon dicchen" = prothom kisti (user nije na bodlale)
  void _syncPayNow() {
    if (!_planning || _payNowTouched) return;
    _payNowController.text = _amts.isEmpty ? '' : _amts.first.text;
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
        // Mashik tarikh: shuru bodlale baki gula-o shathe shore
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
  // HELPERS
  // ═════════════════════════════════════════════════════════
  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
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

  String _pctRange(double lo, double hi) {
    String p(double r) => _trim(r * 100, 1);
    if (lo <= 0 && hi <= 0) return '—';
    return lo == hi ? '${p(hi)}%' : '${p(lo)}–${p(hi)}%';
  }

  double get _minInv => _num(_project['minInvestmentBdt']);
  double get _maxInv => _project['maxInvestmentBdt'] == null ? 0 : _num(_project['maxInvestmentBdt']);
  double get _remaining => _num(_project['remainingBdt']);

  /// Sobcheye beshi joto deya jay
  double get _cap {
    double c = _remaining;
    if (_maxInv > 0 && _maxInv < c) c = _maxInv;
    return c;
  }

  double get _amount => double.tryParse(_amountController.text.trim()) ?? 0;

  // ─── Payment er hishab (website er "Payment Progress") ───
  double get _paidApproved => _isExisting ? _num(widget.existing!['paidApproved']) : 0;
  double get _paidPending => _isExisting ? _num(widget.existing!['paidPending']) : 0;
  double get _outstanding => _isExisting
      ? (_num(widget.existing!['amount']) - _paidApproved - _paidPending).clamp(0, double.infinity).toDouble()
      : _amount;

  bool get _installment => _plan == 'INSTALLMENT';

  /// Ekhon joto taka dicchen — ekbare hole puro (ba puro baki), kistite user er lekha
  double get _payNow {
    if (!_installment) return _isExisting ? _outstanding : _amount;
    return double.tryParse(_payNowController.text.trim()) ?? 0;
  }

  Set<String> get _methods => _options.firstWhere((o) => o.$1 == _option, orElse: () => ('', <String>{})).$2;

  bool get _isSplit => _methods.length > 1;

  double _part(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  double get _splitTotalRaw =>
      (_methods.contains('BANK') ? _part(_bankAmountController) : 0) +
          (_methods.contains('CASH') ? _part(_cashAmountController) : 0) +
          (_methods.contains('CHEQUE') ? _part(_chequeAmountController) : 0);

  List<Map<String, dynamic>> get _banks => ((_project['bankAccounts'] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  String _optionLabel(String key) {
    switch (key) {
      case 'BANK_CASH':
        return LanguageService.tr('Bank + Cash', 'ব্যাংক + ক্যাশ');
      case 'BANK_CHEQUE':
        return LanguageService.tr('Bank + Cheque', 'ব্যাংক + চেক');
      case 'CHEQUE_CASH':
        return LanguageService.tr('Cheque + Cash', 'চেক + ক্যাশ');
      case 'BANK':
        return LanguageService.tr('Bank', 'ব্যাংক');
      case 'CASH':
        return LanguageService.tr('Cash', 'ক্যাশ');
      default:
        return LanguageService.tr('Cheque', 'চেক');
    }
  }

  IconData _optionIcon(String key) {
    if (key == 'BANK') return Icons.account_balance_outlined;
    if (key == 'CASH') return Icons.payments_outlined;
    if (key == 'CHEQUE') return Icons.receipt_long_outlined;
    return Icons.call_split_rounded;
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? danger : emerald),
    );
  }

  // ═════════════════════════════════════════════════════════
  // IMAGES
  // ═════════════════════════════════════════════════════════
  Future<void> _pick(String key) async {
    if (_proofs[key]!.length >= _maxProofs) {
      _toast(LanguageService.tr('Only $_maxProofs files allowed.', 'সর্বোচ্চ $_maxProofs টি ফাইল দেওয়া যাবে।'), error: true);
      return;
    }
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        _toast(LanguageService.tr('Image is larger than 10 MB.', 'ছবি ১০ MB এর বেশি।'), error: true);
        return;
      }
      setState(() {
        _error = null;
        _proofs[key]!.add((bytes, File(picked.path)));
      });
    } catch (e) {
      _toast(LanguageService.tr('Could not open the image.', 'ছবি খোলা যায়নি।'), error: true);
    }
  }

  Future<String?> _upload(Uint8List bytes, String folder) async {
    for (int i = 0; i < 2; i++) {
      try {
        final url = await CloudinaryService.uploadImage(bytes, folder: folder);
        if (url != null && url.isNotEmpty) return url;
      } catch (e) {
        debugPrint('Upload error: $e');
      }
    }
    return null;
  }

  // ═════════════════════════════════════════════════════════
  // SUBMIT
  // ═════════════════════════════════════════════════════════
  /// Notun invest: project ekhono khola ache? (status + deadline, website er motoi)
  String? get _closedReason {
    if (_isExisting) return null; // ager investment er baki taka deya jay
    final status = _project['status']?.toString() ?? '';
    if (status.isNotEmpty && status != 'FUNDRAISING') {
      return LanguageService.tr('This project is not open for investment right now.',
          'এই প্রজেক্টে এখন বিনিয়োগ করা যাবে না।');
    }
    if (DatabaseService.deadlinePassed(_project['fundingDeadline'])) {
      return LanguageService.tr('The funding deadline for this project has passed. New investments are closed.',
          'এই প্রজেক্টের অর্থায়নের শেষ সময় পেরিয়ে গেছে। নতুন বিনিয়োগ বন্ধ।');
    }
    return null;
  }

  String? _validate() {
    final closed = _closedReason;
    if (closed != null) return closed;
    final a = _amount;
    if (a <= 0) return LanguageService.tr('Please enter the amount.', 'পরিমাণ লিখুন।');
    if (!_isExisting) {
      if (_minInv > 0 && a < _minInv) {
        return LanguageService.tr('Minimum investment is ${_fmtFull(_minInv)}.', 'সর্বনিম্ন বিনিয়োগ ${_fmtFull(_minInv)}।');
      }
      if (a > _cap) {
        return LanguageService.tr('Maximum you can invest here is ${_fmtFull(_cap)}.', 'এখানে সর্বোচ্চ ${_fmtFull(_cap)} বিনিয়োগ করা যাবে।');
      }
    } else if (_outstanding <= 0.5) {
      return LanguageService.tr('The full amount is already submitted and under review.',
          'পুরো টাকা জমা হয়েছে, যাচাই চলছে।');
    }
    // Baki investment: tarikh approval er opekkhay / bad (website assertScheduledAmount)
    if (_datesBlocked) {
      return _schedule?['approval'] == 'REJECTED'
          ? LanguageService.tr("This installment schedule was not approved, so it can't be paid.",
          'এই কিস্তির সময়সূচি অনুমোদিত হয়নি, তাই টাকা দেওয়া যাবে না।')
          : LanguageService.tr('Your installment dates are waiting for approval by our team. You can pay once they are approved.',
          'আপনার কিস্তির তারিখ আমাদের টিমের অনুমোদনের অপেক্ষায়। অনুমোদন হলে টাকা দিতে পারবেন।');
    }
    // Notun kisti plan: project er niyom (website checkSchedule)
    double? planMax;
    if (_planning) {
      if (!_installmentsAllowed) {
        return LanguageService.tr('This project accepts full payment only.', 'এই প্রজেক্টে শুধু একবারে পরিশোধ করা যায়।');
      }
      final c = _check;
      if (c == null) return LanguageService.tr('Set up your installment schedule.', 'কিস্তির সময়সূচি ঠিক করুন।');
      if (c.errors.isNotEmpty) return c.errors.first;
      // Tarikh age approve hobe — ekhon kono taka na
      if (_needsApproval) return null;
      final fresh = summarizeSchedule(
          [for (var i = 0; i < _rows.length; i++) (i + 1, _rows[i].$1, _rows[i].$2)], 0, 0, _today, _settings.graceDays);
      planMax = maxPayableNowPaisa(fresh, _today, _settings.allowEarly) / 100;
    }
    final pay = _payNow;
    final maxNow = _isExisting ? _maxNow : (planMax ?? a);
    if (pay <= 0) {
      return LanguageService.tr('Enter how much you are paying now.', 'এখন কত টাকা দিচ্ছেন লিখুন।');
    }
    if (pay > maxNow + 0.5) {
      return LanguageService.tr('You can pay at most ${_fmtFull(maxNow)} now.', 'এখন সর্বোচ্চ ${_fmtFull(maxNow)} দেওয়া যাবে।');
    }
    // Website: kisti kompokkhe ৳1,000 (ba baki er cheye kom hole puro baki)
    if (_installment) {
      final base = _planning ? a : maxNow;
      final minInst = base < _minInstallment ? base : _minInstallment;
      if (pay + 0.5 < minInst) {
        return LanguageService.tr('An installment must be at least ${_fmtFull(minInst)}.',
            'প্রতি কিস্তি কমপক্ষে ${_fmtFull(minInst)} হতে হবে।');
      }
    }
    if (_option == null) return LanguageService.tr('Please choose how you will pay.', 'পেমেন্টের ধরন বেছে নিন।');

    final m = _methods;
    if (_isSplit) {
      for (final (key, c) in [
        ('BANK', _bankAmountController),
        ('CASH', _cashAmountController),
        ('CHEQUE', _chequeAmountController),
      ]) {
        if (m.contains(key) && _part(c) <= 0) {
          return LanguageService.tr('Enter the ${_optionLabel(key)} amount.', '${_optionLabel(key)} এর পরিমাণ লিখুন।');
        }
      }
      if ((_splitTotalRaw - pay).abs() > 0.5) {
        return LanguageService.tr('The parts add up to ${_fmtFull(_splitTotalRaw)}, but you are paying ${_fmtFull(pay)}.',
            'ভাগগুলোর যোগফল ${_fmtFull(_splitTotalRaw)}, কিন্তু দিচ্ছেন ${_fmtFull(pay)}।');
      }
    }
    if (m.contains('BANK')) {
      if (_banks.isEmpty) {
        return LanguageService.tr('No bank account is set for this project. Choose Cash or Cheque.',
            'এই প্রজেক্টে কোনো ব্যাংক অ্যাকাউন্ট নেই। ক্যাশ বা চেক বেছে নিন।');
      }
      // TxID optional (website er motoi), receipt/screenshot lagbei
      if (_proofs['BANK']!.isEmpty) {
        return LanguageService.tr('Upload the transfer receipt or screenshot.', 'ট্রান্সফার রসিদ বা স্ক্রিনশট দিন।');
      }
    }
    if (m.contains('CASH') && _cashReceiver == null) {
      return LanguageService.tr('Select who received the cash.', 'ক্যাশ কে গ্রহণ করেছেন বেছে নিন।');
    }
    if (m.contains('CHEQUE')) {
      if (_chequeNoController.text.trim().isEmpty) {
        return LanguageService.tr('Enter the cheque number.', 'চেক নম্বর দিন।');
      }
      if (_proofs['CHEQUE']!.isEmpty) {
        return LanguageService.tr('Upload a photo of the cheque or deposit slip.', 'চেক বা ডিপোজিট স্লিপের ছবি দিন।');
      }
    }
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    if (!mounted) return;
    if (userId.isEmpty) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
      return;
    }

    // Nijer beche neya tarikh: age admin approve korbe — ekhon payment / chobi na
    if (_needsApproval) {
      setState(() {
        _submitting = true;
        _error = null;
        _stage = LanguageService.tr('Submitting…', 'জমা হচ্ছে…');
      });
      final res = await DatabaseService.investWithPayment(
        userId: userId,
        projectId: _project['id'].toString(),
        amountBdt: _amount,
        payNowBdt: 0,
        paymentPlan: 'INSTALLMENT',
        methods: const [],
        schedule: _rows,
      );
      if (!mounted) return;
      if (res['success'] != true) {
        setState(() {
          _submitting = false;
          _stage = '';
          _error = res['message']?.toString() ??
              LanguageService.tr('Could not submit. Please try again.', 'জমা দেওয়া যায়নি। আবার চেষ্টা করুন।');
        });
        return;
      }
      _toast(LanguageService.tr(
          "Your installment dates were sent for approval. You can pay once they're approved — we'll notify you.",
          'আপনার কিস্তির তারিখ অনুমোদনের জন্য পাঠানো হয়েছে। অনুমোদন হলে টাকা দিতে পারবেন — আমরা জানাব।'));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const InvestmentsPage(initialType: 'PROJECT')),
      );
      return;
    }

    final m = _methods;
    setState(() {
      _submitting = true;
      _error = null;
      _stage = LanguageService.tr('Uploading images…', 'ছবি আপলোড হচ্ছে…');
    });

    // Je madhyom bacha hoyeche shudhu tar chobi — sob ek shathe upload
    final keys = ['BANK', 'CHEQUE', 'CASH'].where(m.contains).toList();
    final jobs = <(String, Future<String?>)>[
      for (final k in keys)
        for (final f in _proofs[k]!) (k, _upload(f.$1, 'payment_proofs')),
    ];
    final urls = await Future.wait(jobs.map((j) => j.$2));
    if (!mounted) return;
    final proofUrls = <String, List<String>>{'BANK': [], 'CHEQUE': [], 'CASH': []};
    var uploadFailed = false;
    for (var i = 0; i < jobs.length; i++) {
      final u = urls[i];
      if (u == null) {
        uploadFailed = true;
      } else {
        proofUrls[jobs[i].$1]!.add(u);
      }
    }
    if (uploadFailed) {
      setState(() {
        _submitting = false;
        _stage = '';
        _error = LanguageService.tr('Could not upload the image. Check your internet and try again.',
            'ছবি আপলোড হয়নি। ইন্টারনেট চেক করে আবার চেষ্টা করুন।');
      });
      return;
    }

    setState(() => _stage = LanguageService.tr('Submitting…', 'জমা হচ্ছে…'));

    final bank = m.contains('BANK') ? _banks[_bankIndex.clamp(0, _banks.length - 1)] : null;
    final acc = bank?['accountNumber']?.toString() ?? '';
    final label = bank == null
        ? null
        : '${bank['bankName'] ?? ''}${acc.length > 4 ? ' (…${acc.substring(acc.length - 4)})' : ''}';
    final pay = _payNow;
    final bankAmt = _isSplit ? _part(_bankAmountController) : pay;
    final cashAmt = _isSplit ? _part(_cashAmountController) : pay;
    final chequeAmt = _isSplit ? _part(_chequeAmountController) : pay;
    final fallbackBank = _banks.isEmpty ? null : _banks.first['id']?.toString();

    final res = _isExisting
        ? await DatabaseService.submitProjectPaymentMulti(
      investmentId: widget.existing!['id'].toString(),
      userId: userId,
      amountBdt: pay,
      methods: m.toList(),
      bankAmount: bankAmt,
      cashAmount: cashAmt,
      chequeAmount: chequeAmt,
      bankAccountId: bank?['id']?.toString(),
      bankAccountLabel: label,
      bankTransactionId: _trxController.text.trim(),
      bankProofUrls: proofUrls['BANK']!,
      cashReceiver: _cashReceiver,
      cashReceiptNo: _cashReceiptController.text.trim(),
      cashProofUrls: proofUrls['CASH']!,
      chequeNumber: _chequeNoController.text.trim(),
      chequeProofUrls: proofUrls['CHEQUE']!,
      defaultBankAccountId: fallbackBank,
      installmentId: _installmentIdToPay,
    )
        : await DatabaseService.investWithPayment(
      userId: userId,
      projectId: _project['id'].toString(),
      amountBdt: _amount,
      payNowBdt: pay,
      paymentPlan: _plan,
      methods: m.toList(),
      bankAmount: bankAmt,
      cashAmount: cashAmt,
      chequeAmount: chequeAmt,
      bankAccountId: bank?['id']?.toString(),
      bankAccountLabel: label,
      bankTransactionId: _trxController.text.trim(),
      bankProofUrls: proofUrls['BANK']!,
      cashReceiver: _cashReceiver,
      cashReceiptNo: _cashReceiptController.text.trim(),
      cashProofUrls: proofUrls['CASH']!,
      chequeNumber: _chequeNoController.text.trim(),
      chequeProofUrls: proofUrls['CHEQUE']!,
      defaultBankAccountId: fallbackBank,
      schedule: _installment ? _rows : null,
    );

    if (!mounted) return;
    if (res['success'] != true) {
      setState(() {
        _submitting = false;
        _stage = '';
        _error = res['message']?.toString() ??
            LanguageService.tr('Could not submit. Please try again.', 'জমা দেওয়া যায়নি। আবার চেষ্টা করুন।');
      });
      return;
    }

    if (_isExisting) {
      Navigator.pop(context, true);
      return;
    }
    _toast(LanguageService.tr('Submitted! Your investment is pending admin approval.',
        'জমা হয়েছে! অ্যাডমিন অনুমোদনের পর বিনিয়োগ চালু হবে।'));
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const InvestmentsPage(initialType: 'PROJECT')),
    );
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        final m = _methods;
        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 54,
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              _isExisting
                  ? LanguageService.tr('Make a Payment', 'পেমেন্ট করুন')
                  : LanguageService.tr('Invest', 'বিনিয়োগ'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 17.5),
            ),
          ),
          bottomNavigationBar: _buildBottomBar(),
          body: AbsorbPointer(
            absorbing: _submitting,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
              children: [
                _buildProjectHero(),
                const SizedBox(height: 10),
                if (_isExisting) ...[
                  _buildProgressCard(),
                  const SizedBox(height: 10),
                  if (_schedule != null) ...[
                    _buildScheduleCard(),
                    const SizedBox(height: 10),
                  ] else if (_scheduleLoading) ...[
                    const LinearProgressIndicator(minHeight: 2, color: emerald, backgroundColor: Colors.transparent),
                    const SizedBox(height: 10),
                  ],
                ],
                _buildAmountCard(),
                if (_planning) ...[
                  const SizedBox(height: 10),
                  _buildPlannerCard(),
                ],
                if (!_noPaymentNow) ...[
                  const SizedBox(height: 10),
                  _buildBankDetailsCard(),
                  const SizedBox(height: 10),
                  _buildMethodCard(),
                  if (_isSplit) ...[
                    const SizedBox(height: 10),
                    _buildSplitCard(),
                  ],
                  if (m.contains('BANK')) ...[
                    const SizedBox(height: 10),
                    _buildBankProofCard(),
                  ],
                  if (m.contains('CASH')) ...[
                    const SizedBox(height: 10),
                    _buildCashCard(),
                  ],
                  if (m.contains('CHEQUE')) ...[
                    const SizedBox(height: 10),
                    _buildChequeCard(),
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  _errorBox(_error!),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Project hero ─────────────────────────────────────────
  Widget _buildProjectHero() {
    final lo = _num(_project['returnMin']);
    final hi = _num(_project['returnMax']);
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
                  Text(
                    LanguageService.tr('PROJECT', 'প্রজেক্ট'),
                    style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.3),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    (_project['title']?.toString() ?? '').isEmpty ? '—' : _project['title'].toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800, height: 1.3),
                  ),
                  if ((_project['subtitle']?.toString() ?? '').isNotEmpty)
                    Text(_project['subtitle'].toString(),
                        style: TextStyle(color: Colors.white.withAlpha(190), fontSize: 12, fontFamily: 'monospace')),
                  const SizedBox(height: 10),
                  Container(height: 1, color: Colors.white.withAlpha(25)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _project['isShare'] == true
                            ? _heroStat(LanguageService.tr('Verified', 'যাচাইকৃত'), _fmtFull(_paidApproved))
                            : _heroStat(LanguageService.tr('Expected return', 'প্রত্যাশিত লাভ'), _pctRange(lo, hi)),
                      ),
                      Expanded(
                        child: _isExisting
                            ? _heroStat(LanguageService.tr('Your commitment', 'আপনার বিনিয়োগ'), _fmtFull(_amount))
                            : _heroStat(LanguageService.tr('Still open', 'বাকি আছে'), _fmtFull(_remaining)),
                      ),
                      Expanded(
                        child: _isExisting
                            ? _heroStat(LanguageService.tr('Left to pay', 'বাকি'), _fmtFull(_outstanding))
                            : _heroStat(LanguageService.tr('Minimum', 'সর্বনিম্ন'), _minInv > 0 ? _fmtFull(_minInv) : '—'),
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

  Widget _heroStat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white.withAlpha(165), fontSize: 11)),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
      ),
    ],
  );

  // ─── Payment progress (baki thaka investment) ────────────
  Widget _buildProgressCard() {
    final total = _amount;
    double pct(double v) => total > 0 ? (v / total).clamp(0.0, 1.0).toDouble() : 0.0;
    final aW = pct(_paidApproved);
    final pW = pct(_paidPending);
    return _card(
      title: LanguageService.tr('Payment Progress', 'পেমেন্টের অগ্রগতি'),
      subtitle: _installment
          ? LanguageService.tr('Paying in installments', 'কিস্তিতে দিচ্ছেন')
          : LanguageService.tr('Paying in full', 'একবারে দিচ্ছেন'),
      icon: Icons.donut_large_rounded,
      tint: emerald,
      tintSoft: emeraldSoft,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 6,
            child: LayoutBuilder(
              builder: (_, c) => Stack(
                children: [
                  Container(color: line),
                  Container(width: c.maxWidth * (aW + pW).clamp(0.0, 1.0), color: BC.chart4),
                  Container(width: c.maxWidth * aW, color: emerald),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _progStat(LanguageService.tr('Verified', 'যাচাই হয়েছে'), _paidApproved, emerald)),
            Expanded(child: _progStat(LanguageService.tr('Under review', 'যাচাই চলছে'), _paidPending, BC.chart4Deep)),
            Expanded(child: _progStat(LanguageService.tr('Left to pay', 'বাকি'), _outstanding, ink)),
          ],
        ),
        if (_paidPending > 0) ...[
          const SizedBox(height: 10),
          Text(
            LanguageService.tr(
                'Payments under review are held back from what you can pay now, so you never pay twice.',
                'যাচাই চলা টাকা এখনকার পেমেন্ট থেকে বাদ রাখা হয়, যাতে দুবার না দেন।'),
            style: const TextStyle(fontSize: 12, color: muted, height: 1.35),
          ),
        ],
      ],
    );
  }

  Widget _progStat(String label, double v, Color c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: muted)),
          ),
        ],
      ),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(_fmtFull(v), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
      ),
    ],
  );

  // ─── Amount + payment plan ────────────────────────────────
  Widget _buildAmountCard() {
    final lo = _num(_project['returnMin']);
    final hi = _num(_project['returnMax']);
    final a = _amount;

    Widget planChip(String key, String en, String bn, IconData icon) {
      final on = _plan == key;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() {
            _plan = key;
            _error = null;
            if (key == 'INSTALLMENT') {
              _payNowTouched = false;
              _suggest();
            } else if (!_isExisting) {
              _payNowController.text = a > 0 ? a.toStringAsFixed(0) : '';
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
              color: on ? emerald : ivory,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: on ? emerald : line),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: on ? Colors.white : emerald),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(LanguageService.tr(en, bn),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : ink)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final payField = TextField(
      controller: _payNowController,
      readOnly: !_installment,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => setState(() {
        _error = null;
        _payNowTouched = true;
      }),
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
      decoration: _dec(LanguageService.tr('Paying now (BDT)', 'এখন দিচ্ছেন (টাকা)'), Icons.savings_outlined).copyWith(
        prefixText: '৳ ',
        helperText: _isExisting
            ? LanguageService.tr('Available to pay now: ${_fmtFull(_maxNow)}',
            'এখন দেওয়া যাবে: ${_fmtFull(_maxNow)}')
            : LanguageService.tr('Usually the 1st installment — pay the rest on their dates from Investments',
            'সাধারণত ১ম কিস্তি — বাকিগুলো তারিখ অনুযায়ী Investments থেকে দিন'),
      ),
    );

    return _card(
      step: 1,
      title: _isExisting
          ? LanguageService.tr('How much are you paying?', 'কত টাকা দিচ্ছেন?')
          : LanguageService.tr('How much do you want to invest?', 'কত টাকা বিনিয়োগ করবেন?'),
      children: [
        TextField(
          controller: _amountController,
          readOnly: _isExisting,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {
            _error = null;
            // Website: mot taka bodlale notun schedule
            if (_planning) _suggest();
          }),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink),
          decoration: _dec(
              _isExisting
                  ? LanguageService.tr('Total commitment (BDT)', 'মোট বিনিয়োগ (টাকা)')
                  : LanguageService.tr('Amount (BDT)', 'পরিমাণ (টাকা)'),
              Icons.payments_outlined)
              .copyWith(
            prefixText: '৳ ',
            helperText: _isExisting
                ? null
                : [
              if (_minInv > 0) LanguageService.tr('Min ${_fmtFull(_minInv)}', 'সর্বনিম্ন ${_fmtFull(_minInv)}'),
              LanguageService.tr('Max ${_fmtFull(_cap)}', 'সর্বোচ্চ ${_fmtFull(_cap)}'),
            ].join(' · '),
          ),
        ),
        if (a > 0 && hi > 0) ...[
          const SizedBox(height: 8),
          Text(
            LanguageService.tr(
              'Annual expected return: ${lo == hi || lo <= 0 ? _fmtFull(a * hi) : '${_fmtFull(a * lo)} – ${_fmtFull(a * hi)}'} (estimate, not guaranteed)',
              'বার্ষিক প্রত্যাশিত লাভ: ${lo == hi || lo <= 0 ? _fmtFull(a * hi) : '${_fmtFull(a * lo)} – ${_fmtFull(a * hi)}'} (আনুমানিক, নিশ্চিত নয়)',
            ),
            style: const TextStyle(fontSize: 12.5, color: emerald, fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 12),
        if (!_isExisting && _installmentsAllowed) ...[
          Text(LanguageService.tr('Payment preference', 'পেমেন্টের ধরন'),
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink)),
          const SizedBox(height: 6),
          Row(
            children: [
              planChip('FULL', 'Pay in full', 'একবারে', Icons.done_all_rounded),
              const SizedBox(width: 8),
              planChip('INSTALLMENT', 'Installments', 'কিস্তিতে', Icons.calendar_month_outlined),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _installment
                ? LanguageService.tr(
                'You pay only the first installment now and the rest on the dates you agree. Your investment becomes active — your deed is issued and profit starts — once every installment is verified.',
                'এখন শুধু প্রথম কিস্তি দিন, বাকিগুলো ঠিক করা তারিখে। সব কিস্তি যাচাই হলে বিনিয়োগ চালু হবে — ডিড দেওয়া হবে ও লাভ শুরু হবে।')
                : LanguageService.tr('Pay the whole amount now. It activates once your payment is verified.',
                'এখন পুরো টাকা দিন। যাচাইয়ের পর বিনিয়োগ চালু হবে।'),
            style: const TextStyle(fontSize: 12, color: muted, height: 1.35),
          ),
        ],
        if ((_isExisting || _installment) && !_noPaymentNow) ...[
          const SizedBox(height: 10),
          // Ekbare hole baki puro taka-i (initState e boshano, bodlano jay na)
          payField,
        ],
      ],
    );
  }

  // ─── Kisti-r schedule banano (website er InstallmentPlanner) ───
  Widget _buildPlannerCard() {
    final st = _settings;
    final fixed = st.fixedDates != null;
    final counts = [for (var n = st.minCount; n <= st.maxCount; n++) n];
    final check = _check;
    final backdated = _dates.isNotEmpty && isBackdated(_rows, _today);
    final remaining = check?.remainingPaisa ?? 0;
    final otherErrors = (check?.errors ?? const <String>[])
        .where((e) => !e.startsWith('The total installment amount') && !e.startsWith('কিস্তিগুলোর যোগফল'))
        .toList();

    return _card(
      title: LanguageService.tr('Installment schedule', 'কিস্তির সময়সূচি'),
      subtitle: st.summary(LanguageService.tr),
      icon: Icons.calendar_month_outlined,
      children: [
        if (_amount <= 0)
          Text(
            LanguageService.tr('Enter the total amount above to plan your installments.',
                'কিস্তি ঠিক করতে উপরে মোট টাকা লিখুন।'),
            style: const TextStyle(fontSize: 12.5, color: muted),
          )
        else ...[
          // Koyta kisti + shoman bhag
          Row(
            children: [
              Text(LanguageService.tr('Installments', 'কিস্তি'),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() {
                  _payNowTouched = false;
                  _suggest(count: _dates.isEmpty ? null : _dates.length);
                }),
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
          if (counts.length > 1) ...[
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
                      _payNowTouched = false;
                      _suggest(count: n);
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on ? emerald : ivory,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: on ? emerald : line),
                      ),
                      child: Text('$n',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? Colors.white : ink)),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Protita kisti: tarikh + taka
          for (var i = 0; i < _dates.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 36,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 11),
                    child: Text(ordinal(i + 1),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ink)),
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
                                      style: TextStyle(
                                          fontSize: 13, fontWeight: FontWeight.w600, color: canEdit ? ink : muted)),
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
                                : fixed
                                ? LanguageService.tr('Paid now', 'এখন দিচ্ছেন')
                                : LanguageService.tr('Paid now — or pick the earlier day you paid',
                                'এখন দিচ্ছেন — বা আগে যেদিন দিয়েছেন সেই দিন বাছুন'),
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
                    onChanged: (_) => setState(() {
                      _error = null;
                      if (i == 0) _syncPayNow();
                    }),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink),
                    decoration: InputDecoration(
                      prefixText: '৳ ',
                      isDense: true,
                      filled: true,
                      fillColor: ivory,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line)),
                      enabledBorder:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: emerald, width: 1.4)),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // Mot mile kina
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: remaining == 0 ? emeraldSoft : BC.chart4Muted,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              remaining == 0
                  ? LanguageService.tr('Adds up to ${_fmtFull(_amount)} · ${_dates.length} installments',
                  '${_fmtFull(_amount)} মিলেছে · ${_dates.length} টি কিস্তি')
                  : remaining > 0
                  ? LanguageService.tr('${tkPaisa(remaining)} still to schedule', 'আরও ${tkPaisa(remaining)} ভাগ করা বাকি')
                  : LanguageService.tr('${tkPaisa(-remaining)} more than the total', 'মোটের চেয়ে ${tkPaisa(-remaining)} বেশি'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: remaining == 0 ? emerald : BC.chart4Deep,
              ),
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
                color: BC.chart4Muted,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BC.chart4Deep.withAlpha(50)),
              ),
              child: Text(
                backdated
                    ? LanguageService.tr(
                    'Your schedule starts on ${fmtDay(_dates.first)}. Our team reviews it first; once it is approved, upload the proof of each installment you already paid.',
                    'আপনার সময়সূচি ${fmtDay(_dates.first)} থেকে শুরু। আগে আমাদের টিম যাচাই করবে; অনুমোদন হলে আগে দেওয়া কিস্তির প্রুফ দিন।')
                    : LanguageService.tr(
                    'You chose your own dates, so our team reviews them first. You can pay the first installment once they are approved — we\'ll notify you.',
                    'আপনি নিজে তারিখ বেছেছেন, তাই আগে আমাদের টিম যাচাই করবে। অনুমোদন হলে প্রথম কিস্তি দিতে পারবেন — আমরা জানাব।'),
                style: const TextStyle(fontSize: 12, color: BC.chart4Deep, height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            LanguageService.tr('Once confirmed, the schedule can only be changed by our team. A missed date is only marked overdue — no penalty.',
                'নিশ্চিত করার পর সময়সূচি শুধু আমাদের টিম বদলাতে পারবে। তারিখ পেরোলে শুধু "মেয়াদোত্তীর্ণ" দেখায় — জরিমানা নেই।'),
            style: const TextStyle(fontSize: 11.5, color: muted, height: 1.35),
          ),
        ],
      ],
    );
  }

  // ─── Baki investment er kisti (website er InstallmentScheduleCard) ───
  Widget _buildScheduleCard() {
    final s = _schedule!;
    final sum = s['summary'] as ScheduleSummary;
    final blocked = _datesBlocked;
    final rejected = s['approval'] == 'REJECTED';
    final paidCount = sum.installments.where((a) => a.status == 'PAID').length;

    Color tone(String st) => switch (st) {
      'PAID' => emerald,
      'OVERDUE' => danger,
      'DUE' => BC.chart4Deep,
      'PENDING_VERIFICATION' => BC.finance600,
      _ => muted,
    };

    return _card(
      title: LanguageService.tr('Installment schedule', 'কিস্তির সময়সূচি'),
      subtitle: LanguageService.tr('$paidCount of ${sum.installments.length} paid · ${sum.progressPct.toStringAsFixed(0)}% verified',
          '${sum.installments.length} টির মধ্যে $paidCount টি পরিশোধিত · ${sum.progressPct.toStringAsFixed(0)}% যাচাইকৃত'),
      icon: Icons.calendar_month_outlined,
      children: [
        if (blocked) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (rejected ? danger : BC.chart4Deep).withAlpha(16),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: (rejected ? danger : BC.chart4Deep).withAlpha(50)),
            ),
            child: Text(
              rejected
                  ? LanguageService.tr(
                  'Your installment dates were not approved.${(s['reviewNote']?.toString() ?? '').isNotEmpty ? ' Reason: ${s['reviewNote']}' : ''} You can start a new investment with different dates.',
                  'আপনার কিস্তির তারিখ অনুমোদিত হয়নি।${(s['reviewNote']?.toString() ?? '').isNotEmpty ? ' কারণ: ${s['reviewNote']}' : ''} অন্য তারিখ দিয়ে নতুন করে বিনিয়োগ করতে পারেন।')
                  : LanguageService.tr(
                  "Your installment dates are being reviewed. We'll notify you as soon as they're approved — then you can pay. Nothing can be paid until then.",
                  'আপনার কিস্তির তারিখ যাচাই চলছে। অনুমোদন হলেই জানাব — তারপর টাকা দিতে পারবেন। তার আগে কিছু দেওয়া যাবে না।'),
              style: TextStyle(fontSize: 12, height: 1.4, color: rejected ? danger : BC.chart4Deep),
            ),
          ),
          const SizedBox(height: 10),
        ],
        for (final a in sum.installments)
          Builder(builder: (_) {
            final open = a.openPaisa > 0 && !blocked;
            final selected = !blocked && _payUpTo != null && a.openPaisa > 0 && a.number <= _payUpTo!;
            final label = installmentStatusLabel[a.status];
            final c = tone(a.status);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: open
                    ? () => setState(() {
                  _error = null;
                  _setPayNowFor(a.number);
                })
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? emeraldSoft : ivory,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selected ? emerald.withAlpha(110) : line),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text(ordinal(a.number),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ink)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fmtDay(a.dueDate), style: const TextStyle(fontSize: 12.5, color: ink)),
                            if ((a.paidPaisa > 0 && a.paidPaisa < a.amountPaisa) || a.pendingPaisa > 0)
                              Text(
                                [
                                  if (a.paidPaisa > 0) LanguageService.tr('${tkPaisa(a.paidPaisa)} paid', '${tkPaisa(a.paidPaisa)} পরিশোধ'),
                                  if (a.pendingPaisa > 0)
                                    LanguageService.tr('${tkPaisa(a.pendingPaisa)} in review', '${tkPaisa(a.pendingPaisa)} যাচাই চলছে'),
                                ].join(' · '),
                                style: const TextStyle(fontSize: 11, color: muted),
                              ),
                          ],
                        ),
                      ),
                      Text(tkPaisa(a.amountPaisa),
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ink)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: c.withAlpha(24), borderRadius: BorderRadius.circular(20)),
                        child: Text(label == null ? a.status : LanguageService.tr(label.$1, label.$2),
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        if (!blocked && sum.next != null) ...[
          const SizedBox(height: 2),
          Text(
            LanguageService.tr('Tap an installment to pay up to it. Payments cover installments oldest first.',
                'যে কিস্তি পর্যন্ত দিতে চান সেটি চাপুন। টাকা আগের কিস্তি থেকে ধরা হয়।'),
            style: const TextStyle(fontSize: 11.5, color: muted, height: 1.35),
          ),
        ],
        if (sum.fullyPaid) ...[
          const SizedBox(height: 2),
          Text(LanguageService.tr('Every installment is verified.', 'সব কিস্তি যাচাই হয়েছে।'),
              style: const TextStyle(fontSize: 12, color: emerald, fontWeight: FontWeight.w700)),
        ],
      ],
    );
  }

  // ─── Bank details (shob shomoy dekhay) ────────────────────
  Widget _buildBankDetailsCard() {
    final banks = _banks;
    if (banks.isEmpty) {
      return _card(
        title: LanguageService.tr('Bank Details', 'ব্যাংক তথ্য'),
        icon: Icons.account_balance_outlined,
        children: [
          Text(
            LanguageService.tr('No bank account has been added for this project yet. You can pay by cash or cheque.',
                'এই প্রজেক্টে এখনো কোনো ব্যাংক অ্যাকাউন্ট যোগ করা হয়নি। ক্যাশ বা চেকে দিতে পারেন।'),
            style: const TextStyle(fontSize: 12.5, color: muted, height: 1.35),
          ),
        ],
      );
    }

    final idx = _bankIndex.clamp(0, banks.length - 1);
    final bank = banks[idx];
    String v(String k) => bank[k]?.toString() ?? '';
    final rows = <(String, String, bool)>[
      (LanguageService.tr('Bank', 'ব্যাংক'), v('bankName'), false),
      (LanguageService.tr('Account name', 'অ্যাকাউন্টের নাম'), v('accountName'), true),
      (LanguageService.tr('Account number', 'অ্যাকাউন্ট নম্বর'), v('accountNumber'), true),
      (LanguageService.tr('Branch', 'শাখা'), v('branchName'), false),
      (LanguageService.tr('Routing number', 'রাউটিং নম্বর'), v('routingNumber'), true),
      (LanguageService.tr('SWIFT code', 'সুইফট কোড'), v('swiftCode'), true),
      (LanguageService.tr('Mobile', 'মোবাইল'), v('mobileNumber'), true),
      (LanguageService.tr('Branch address', 'শাখার ঠিকানা'), v('branchAddress'), false),
    ].where((r) => r.$2.isNotEmpty).toList();

    return _card(
      title: LanguageService.tr('Bank Details', 'ব্যাংক তথ্য'),
      subtitle: LanguageService.tr('Only pay into these official accounts.', 'শুধু এই অফিসিয়াল অ্যাকাউন্টে টাকা দিন।'),
      icon: Icons.account_balance_outlined,
      children: [
        if (banks.length > 1) ...[
          SizedBox(
            height: 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: banks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final on = i == idx;
                final name = banks[i]['bankName']?.toString() ?? '';
                return GestureDetector(
                  onTap: () => setState(() => _bankIndex = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? emerald : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: on ? emerald : line),
                    ),
                    child: Text(
                      name.isEmpty ? LanguageService.tr('Account ${i + 1}', 'অ্যাকাউন্ট ${i + 1}') : name,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? Colors.white : ink),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
        for (final r in rows) _copyRow(r.$1, r.$2, r.$3),
      ],
    );
  }

  Widget _copyRow(String label, String value, bool copyable) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 1),
                SelectableText(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
              ],
            ),
          ),
          if (copyable)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: value));
                _toast(LanguageService.tr('$label copied', '$label কপি হয়েছে'));
              },
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: emeraldSoft, borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.copy_rounded, size: 16, color: emerald),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Payment method ───────────────────────────────────────
  Widget _buildMethodCard() {
    return _card(
      step: 2,
      title: LanguageService.tr('How will you pay?', 'কীভাবে টাকা দেবেন?'),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _options.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: 42,
          ),
          itemBuilder: (_, i) {
            final key = _options[i].$1;
            final on = _option == key;
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() {
                _option = key;
                _error = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: on ? emerald : ivory,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: on ? emerald : line, width: on ? 1.4 : 1),
                ),
                child: Row(
                  children: [
                    Icon(_optionIcon(key), size: 15, color: on ? Colors.white : emerald),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _optionLabel(key),
                        maxLines: 2,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : ink, height: 1.2),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ─── Split (ekadhik method hole) ──────────────────────────
  Widget _buildSplitCard() {
    final m = _methods;
    final left = _payNow - _splitTotalRaw;
    Widget field(String key, TextEditingController c) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() => _error = null),
        decoration: _dec(LanguageService.tr('${_optionLabel(key)} amount', '${_optionLabel(key)} এর পরিমাণ'),
            _optionIcon(key))
            .copyWith(prefixText: '৳ '),
      ),
    );

    return _card(
      title: LanguageService.tr('Split the amount', 'টাকা ভাগ করুন'),
      subtitle: LanguageService.tr('How much through each method', 'কোন মাধ্যমে কত টাকা'),
      icon: Icons.call_split_rounded,
      children: [
        if (m.contains('BANK')) field('BANK', _bankAmountController),
        if (m.contains('CASH')) field('CASH', _cashAmountController),
        if (m.contains('CHEQUE')) field('CHEQUE', _chequeAmountController),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: left.abs() <= 0.5 ? emeraldSoft : BC.chart4Muted,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            left.abs() <= 0.5
                ? LanguageService.tr('Matches ${_fmtFull(_payNow)}', '${_fmtFull(_payNow)} এর সাথে মিলেছে')
                : left > 0
                ? LanguageService.tr('${_fmtFull(left)} still to assign', 'আরো ${_fmtFull(left)} ভাগ করা বাকি')
                : LanguageService.tr('${_fmtFull(-left)} more than the total', 'মোটের চেয়ে ${_fmtFull(-left)} বেশি'),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: left.abs() <= 0.5 ? emerald : BC.chart4Deep,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Bank proof ───────────────────────────────────────────
  Widget _buildBankProofCard() {
    final banks = _banks;
    final bank = banks.isEmpty ? null : banks[_bankIndex.clamp(0, banks.length - 1)];
    return _card(
      title: LanguageService.tr('Bank payment', 'ব্যাংক পেমেন্ট'),
      icon: Icons.account_balance_outlined,
      tint: emerald,
      tintSoft: emeraldSoft,
      children: [
        if (bank != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              LanguageService.tr('Paid into: ${bank['bankName'] ?? ''} — change above if different',
                  'যে অ্যাকাউন্টে দিয়েছেন: ${bank['bankName'] ?? ''} — ভিন্ন হলে উপরে বদলান'),
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          ),
        TextField(
          controller: _trxController,
          onChanged: (_) => setState(() => _error = null),
          decoration: _dec(LanguageService.tr('Transaction reference / TxID (optional)', 'ট্রানজেকশন নম্বর / TxID (ঐচ্ছিক)'),
              Icons.tag_rounded),
        ),
        const SizedBox(height: 10),
        _proofList('BANK', LanguageService.tr('Transfer receipt or screenshot *', 'ট্রান্সফার রসিদ বা স্ক্রিনশট *')),
      ],
    );
  }

  // ─── Cash ─────────────────────────────────────────────────
  Widget _buildCashCard() {
    return _card(
      title: LanguageService.tr('Cash payment', 'ক্যাশ পেমেন্ট'),
      subtitle: LanguageService.tr('Who received the cash? *', 'ক্যাশ কে গ্রহণ করেছেন? *'),
      icon: Icons.payments_outlined,
      tint: emerald,
      tintSoft: emeraldSoft,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _cashReceivers.map((r) {
            final on = _cashReceiver == r.$1;
            return ChoiceChip(
              label: Text(LanguageService.tr(r.$2, r.$3)),
              selected: on,
              showCheckmark: false,
              selectedColor: emerald,
              backgroundColor: ivory,
              side: BorderSide(color: on ? emerald : line),
              labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : ink),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onSelected: (_) => setState(() {
                _cashReceiver = r.$1;
                _error = null;
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _cashReceiptController,
          onChanged: (_) => setState(() => _error = null),
          decoration: _dec(LanguageService.tr('Money receipt number (optional)', 'মানি রসিদ নম্বর (ঐচ্ছিক)'),
              Icons.confirmation_number_outlined),
        ),
        const SizedBox(height: 10),
        _proofList('CASH', LanguageService.tr('Photo of the money receipt (optional)', 'মানি রসিদের ছবি (ঐচ্ছিক)')),
      ],
    );
  }

  // ─── Cheque ───────────────────────────────────────────────
  Widget _buildChequeCard() {
    return _card(
      title: LanguageService.tr('Cheque payment', 'চেক পেমেন্ট'),
      icon: Icons.receipt_long_outlined,
      tint: emerald,
      tintSoft: emeraldSoft,
      children: [
        TextField(
          controller: _chequeNoController,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() => _error = null),
          decoration: _dec(LanguageService.tr('Cheque number *', 'চেক নম্বর *'), Icons.pin_outlined),
        ),
        const SizedBox(height: 10),
        _proofList('CHEQUE', LanguageService.tr('Photo of the cheque or deposit slip *', 'চেক বা ডিপোজিট স্লিপের ছবি *')),
      ],
    );
  }

  // ─── Bottom bar ───────────────────────────────────────────
  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: line))),
        child: SizedBox(
          height: 46,
          child: FilledButton(
            onPressed: _submitting || _datesBlocked ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: emerald,
              foregroundColor: Colors.white,
              disabledBackgroundColor: emerald.withAlpha(140),
              disabledForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _submitting
                ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text(_stage, style: const TextStyle(fontSize: 14)),
              ],
            )
                : Text(
              _needsApproval
                  ? LanguageService.tr('Submit for Approval', 'অনুমোদনের জন্য জমা দিন')
                  : _datesBlocked
                  ? LanguageService.tr('Waiting for date approval', 'তারিখ অনুমোদনের অপেক্ষায়')
                  : _payNow > 0
                  ? LanguageService.tr('Confirm ${_fmtFull(_payNow)}', '${_fmtFull(_payNow)} নিশ্চিত করুন')
                  : LanguageService.tr('Confirm', 'নিশ্চিত করুন'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // SHARED
  // ═════════════════════════════════════════════════════════
  Widget _card({
    int? step,
    required String title,
    String? subtitle,
    IconData? icon,
    Color tint = emerald,
    Color tintSoft = emeraldSoft,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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
              if (step != null)
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [emeraldBright, emerald]),
                    shape: BoxShape.circle,
                  ),
                  child: Text('$step',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
                )
              else if (icon != null)
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: tintSoft, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 16, color: tint),
                )
              else
                Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(width: 7, height: 7, color: emerald),
                ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
              ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 35, top: 1),
              child: Text(subtitle, style: const TextStyle(fontSize: 12, color: muted)),
            ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: muted),
      prefixIcon: Icon(icon, color: emerald, size: 19),
      prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      helperStyle: const TextStyle(fontSize: 11.5, color: muted),
      isDense: true,
      filled: true,
      fillColor: ivory,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line)),
      focusedBorder:
      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: emerald, width: 1.4)),
    );
  }

  /// Ek madhyom er proof chobi — 3 ta porjonto, protitar kone ✕
  Widget _proofList(String key, String label) {
    final files = _proofs[key]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink)),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < _maxProofs; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              SizedBox(
                width: 64,
                height: 64,
                child: i < files.length
                    ? Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(files[i].$1, fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: GestureDetector(
                        onTap: () => setState(() => files.removeAt(i)),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(color: Colors.black.withAlpha(160), shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, size: 15, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                )
                    : i == files.length
                    ? GestureDetector(
                  onTap: () => _pick(key),
                  child: Container(
                    decoration: BoxDecoration(
                      color: ivory,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: emerald.withAlpha(110)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_a_photo_outlined, color: emerald, size: 20),
                        const SizedBox(height: 2),
                        Text(LanguageService.tr('Add', 'যোগ করুন'),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: emerald)),
                      ],
                    ),
                  ),
                )
                    : Container(
                  decoration: BoxDecoration(
                    color: ivory.withAlpha(120),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: line),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          LanguageService.tr('Up to $_maxProofs images · JPG / PNG · max 10 MB each',
              'সর্বোচ্চ $_maxProofs টি ছবি · JPG / PNG · প্রতিটি ১০ MB পর্যন্ত'),
          style: const TextStyle(fontSize: 11, color: muted),
        ),
      ],
    );
  }

  Widget _errorBox(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: dangerSoft, borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 17, color: danger),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, color: danger, height: 1.35))),
        ],
      ),
    );
  }
}