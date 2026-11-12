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
import '../../../services/language_service.dart';
import '../../../theme/app_colors.dart';

/// Group tier e invest (ba age kora investment er payment): taka + payment er
/// dhoron + proof — ek page e. Confirm korle "Pending", admin approve korle ACTIVE.
/// Shofol hole `Navigator.pop(context, true)`.
class GroupInvestPage extends StatefulWidget {
  /// getBusinessGroupsWithTiers er tier map (notun invest) — existing thakle lagbe na
  final Map<String, dynamic>? tier;

  /// getGroupInvestmentsData er investment map — payment baki thaka investment
  final Map<String, dynamic>? existing;

  final String groupName;
  final String entityName;

  const GroupInvestPage({
    super.key,
    this.tier,
    this.existing,
    required this.groupName,
    required this.entityName,
  }) : assert(tier != null || existing != null);

  @override
  State<GroupInvestPage> createState() => _GroupInvestPageState();
}

class _GroupInvestPageState extends State<GroupInvestPage> {
  // ─── Palette — website er rong (lib/theme/app_colors.dart) ───
  static const Color emerald = BC.primary;
  static const Color emeraldBright = BC.brand500; // home page er moto
  static const Color emeraldDeep = BC.brand800;
  static const Color emeraldSoft = BC.secondary;
  static const Color gold = BC.harvest500;
  static const Color goldLight = BC.harvest400;
  static const Color goldDeep = BC.harvest600;
  static const Color goldSoft = BC.accent;
  static const Color lapis = BC.finance600;
  static const Color lapisSoft = BC.finance50;
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
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (_isExisting) {
      final e = widget.existing!;
      _plan = (e['paymentPlan']?.toString() ?? 'FULL').toUpperCase() == 'INSTALLMENT' ? 'INSTALLMENT' : 'FULL';
      _amountController.text = _num(e['amountBdt']).toStringAsFixed(0);
      _payNowController.text = _outstanding.toStringAsFixed(0);
    } else if (_minInv > 0) {
      _amountController.text = _minInv.toStringAsFixed(0);
    }
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

  String _pct(double r) => r <= 0 ? '—' : '${_trim(r * 100, 1)}%';

  bool get _isExisting => widget.existing != null;

  Map<String, dynamic> get _src => widget.existing ?? widget.tier!;

  String get _tierName =>
      (_isExisting ? widget.existing!['tierName'] : widget.tier!['name'])?.toString() ?? '';

  double get _returnPct => _num(_src['expectedReturnPct']);
  int get _months => (_src['durationMonths'] as num?)?.toInt() ?? 0;

  double get _minInv => _isExisting ? 0 : _num(widget.tier!['minAmountBdt']);
  double get _maxInv =>
      _isExisting || widget.tier!['maxAmountBdt'] == null ? 0 : _num(widget.tier!['maxAmountBdt']);

  double get _amount => double.tryParse(_amountController.text.trim()) ?? 0;

  // ─── Payment er hishab (website er "Payment Progress") ───
  double get _paidApproved => _isExisting ? _num(widget.existing!['paidApproved']) : 0;
  double get _paidPending => _isExisting ? _num(widget.existing!['paidPending']) : 0;
  double get _outstanding => _isExisting
      ? (_num(widget.existing!['amountBdt']) - _paidApproved - _paidPending).clamp(0, double.infinity).toDouble()
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

  /// Tier er official account (ekta)
  List<Map<String, dynamic>> get _banks {
    final b = _src['bank'];
    if (b is! Map) return [];
    final m = Map<String, dynamic>.from(b);
    return (m['accountNumber']?.toString() ?? '').isEmpty ? [] : [m];
  }

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
  String? _validate() {
    // Notun invest: tier er unit shesh hole bondho (server-o check kore)
    if (!_isExisting) {
      final u = widget.tier!['availableUnits'];
      if (u is num && u <= 0) {
        return LanguageService.tr('This tier is sold out.', 'এই টিয়ারের সব ইউনিট বিক্রি হয়ে গেছে।');
      }
    }
    final a = _amount;
    if (a <= 0) return LanguageService.tr('Please enter the amount.', 'পরিমাণ লিখুন।');
    if (!_isExisting) {
      if (_minInv > 0 && a < _minInv) {
        return LanguageService.tr('Minimum investment is ${_fmtFull(_minInv)}.', 'সর্বনিম্ন বিনিয়োগ ${_fmtFull(_minInv)}।');
      }
      if (_maxInv > 0 && a > _maxInv) {
        return LanguageService.tr('Maximum for this tier is ${_fmtFull(_maxInv)}.', 'এই টিয়ারে সর্বোচ্চ ${_fmtFull(_maxInv)}।');
      }
    } else if (_outstanding <= 0.5) {
      return LanguageService.tr('The full amount is already submitted and under review.',
          'পুরো টাকা জমা হয়েছে, যাচাই চলছে।');
    }
    final pay = _payNow;
    final maxNow = _isExisting ? _outstanding : a;
    if (pay <= 0) {
      return LanguageService.tr('Enter how much you are paying now.', 'এখন কত টাকা দিচ্ছেন লিখুন।');
    }
    if (pay > maxNow + 0.5) {
      return LanguageService.tr('You can pay at most ${_fmtFull(maxNow)} now.', 'এখন সর্বোচ্চ ${_fmtFull(maxNow)} দেওয়া যাবে।');
    }
    // Website: kisti kompokkhe ৳1,000 (ba baki er cheye kom hole puro baki)
    if (_installment) {
      final minInst = maxNow < _minInstallment ? maxNow : _minInstallment;
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
        return LanguageService.tr('No bank account is set for this tier. Choose Cash or Cheque.',
            'এই টিয়ারে কোনো ব্যাংক অ্যাকাউন্ট নেই। ক্যাশ বা চেক বেছে নিন।');
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

    final res = _isExisting
        ? await DatabaseService.submitGroupPaymentMulti(
      groupInvestmentId: widget.existing!['id'].toString(),
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
    )
        : await DatabaseService.groupInvestWithPayment(
      userId: userId,
      tierId: widget.tier!['id'].toString(),
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

    Navigator.pop(context, true);
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
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 16.5),
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
                ],
                _buildAmountCard(),
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

  // ─── Group hero ───────────────────────────────────────────
  Widget _buildProjectHero() {
    final sameName = widget.entityName.isEmpty ||
        widget.entityName.toLowerCase() == widget.groupName.toLowerCase();
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
                  Text(
                    sameName ? widget.groupName : '${widget.groupName} — ${widget.entityName}',
                    style: const TextStyle(color: goldLight, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _tierName.isEmpty ? '—' : _tierName,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Container(height: 1, color: Colors.white.withAlpha(25)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _heroStat(LanguageService.tr('Expected return', 'প্রত্যাশিত লাভ'), _pct(_returnPct))),
                      Expanded(
                        child: _heroStat(
                          LanguageService.tr('Term', 'মেয়াদ'),
                          _months > 0 ? LanguageService.tr('$_months months', '$_months মাস') : '—',
                        ),
                      ),
                      Expanded(
                        child: _heroStat(
                          _isExisting
                              ? LanguageService.tr('Commitment', 'মোট বিনিয়োগ')
                              : LanguageService.tr('Minimum', 'সর্বনিম্ন'),
                          _isExisting
                              ? _fmtFull(_amount)
                              : (_minInv > 0 ? _fmtFull(_minInv) : '—'),
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

  Widget _heroStat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white.withAlpha(165), fontSize: 9.5)),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(value, style: const TextStyle(color: goldLight, fontSize: 13, fontWeight: FontWeight.w800)),
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
                  Container(width: c.maxWidth * (aW + pW).clamp(0.0, 1.0), color: gold),
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
            Expanded(child: _progStat(LanguageService.tr('Under review', 'যাচাই চলছে'), _paidPending, gold)),
            Expanded(child: _progStat(LanguageService.tr('Left to pay', 'বাকি'), _outstanding, ink)),
          ],
        ),
        if (_paidPending > 0) ...[
          const SizedBox(height: 10),
          Text(
            LanguageService.tr(
                'Payments under review are held back from what you can pay now, so you never pay twice.',
                'যাচাই চলা টাকা এখনকার পেমেন্ট থেকে বাদ রাখা হয়, যাতে দুবার না দেন।'),
            style: const TextStyle(fontSize: 10.5, color: muted, height: 1.35),
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
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: muted)),
          ),
        ],
      ),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(_fmtFull(v), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ink)),
      ),
    ],
  );

  // ─── Amount + payment plan ────────────────────────────────
  Widget _buildAmountCard() {
    final pct = _returnPct;
    final a = _amount;

    Widget planChip(String key, String en, String bn, IconData icon) {
      final on = _plan == key;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() {
            _plan = key;
            _error = null;
            if (key == 'INSTALLMENT' && _payNowController.text.isEmpty && a > 0) {
              _payNowController.text = a.toStringAsFixed(0);
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
                Icon(icon, size: 15, color: on ? goldLight : goldDeep),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(LanguageService.tr(en, bn),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: on ? Colors.white : ink)),
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
      onChanged: (_) => setState(() => _error = null),
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
      decoration: _dec(LanguageService.tr('Paying now (BDT)', 'এখন দিচ্ছেন (টাকা)'), Icons.savings_outlined).copyWith(
        prefixText: '৳ ',
        helperText: _isExisting
            ? LanguageService.tr('Available to pay now: ${_fmtFull(_outstanding)}',
            'এখন দেওয়া যাবে: ${_fmtFull(_outstanding)}')
            : LanguageService.tr('Pay the rest later from Investments', 'বাকিটা পরে Investments থেকে দিন'),
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
          onChanged: (_) => setState(() => _error = null),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink),
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
              if (_maxInv > 0) LanguageService.tr('Max ${_fmtFull(_maxInv)}', 'সর্বোচ্চ ${_fmtFull(_maxInv)}'),
            ].join(' · '),
          ),
        ),
        if (a > 0 && pct > 0) ...[
          const SizedBox(height: 8),
          Text(
            LanguageService.tr(
              'Expected return at ${_pct(pct)}: ${_fmtFull(a * pct)} (estimate, not guaranteed)',
              '${_pct(pct)} হারে প্রত্যাশিত লাভ: ${_fmtFull(a * pct)} (আনুমানিক, নিশ্চিত নয়)',
            ),
            style: const TextStyle(fontSize: 11, color: emerald, fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 12),
        if (!_isExisting) ...[
          Text(LanguageService.tr('Payment preference', 'পেমেন্টের ধরন'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ink)),
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
                'Pay in parts on dates that suit you. Your investment activates and the deed is issued once the full amount is verified.',
                'সুবিধামতো তারিখে ভাগে ভাগে দিন। পুরো টাকা যাচাই হলে বিনিয়োগ চালু হবে ও ডিড দেওয়া হবে।')
                : LanguageService.tr('Pay the whole amount now. It activates once your payment is verified.',
                'এখন পুরো টাকা দিন। যাচাইয়ের পর বিনিয়োগ চালু হবে।'),
            style: const TextStyle(fontSize: 10.5, color: muted, height: 1.35),
          ),
        ],
        if (_isExisting || _installment) ...[
          const SizedBox(height: 10),
          // Ekbare hole baki puro taka-i (initState e boshano, bodlano jay na)
          payField,
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
            LanguageService.tr('No bank account has been added for this tier yet. You can pay by cash or cheque.',
                'এই টিয়ারে এখনো কোনো ব্যাংক অ্যাকাউন্ট যোগ করা হয়নি। ক্যাশ বা চেকে দিতে পারেন।'),
            style: const TextStyle(fontSize: 11.5, color: muted, height: 1.35),
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
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: on ? Colors.white : ink),
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
                Text(label, style: const TextStyle(fontSize: 9.5, color: muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 1),
                SelectableText(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink)),
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
                decoration: BoxDecoration(color: goldSoft, borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.copy_rounded, size: 14, color: goldDeep),
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
                    Icon(_optionIcon(key), size: 15, color: on ? goldLight : goldDeep),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _optionLabel(key),
                        maxLines: 2,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: on ? Colors.white : ink, height: 1.2),
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
            color: left.abs() <= 0.5 ? emeraldSoft : goldSoft,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            left.abs() <= 0.5
                ? LanguageService.tr('Matches ${_fmtFull(_payNow)}', '${_fmtFull(_payNow)} এর সাথে মিলেছে')
                : left > 0
                ? LanguageService.tr('${_fmtFull(left)} still to assign', 'আরো ${_fmtFull(left)} ভাগ করা বাকি')
                : LanguageService.tr('${_fmtFull(-left)} more than the total', 'মোটের চেয়ে ${_fmtFull(-left)} বেশি'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: left.abs() <= 0.5 ? emerald : goldDeep,
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
              style: const TextStyle(fontSize: 10.5, color: muted),
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
              labelStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: on ? Colors.white : ink),
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
            onPressed: _submitting ? null : _submit,
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
                Text(_stage, style: const TextStyle(fontSize: 13)),
              ],
            )
                : Text(
              _payNow > 0
                  ? LanguageService.tr('Confirm ${_fmtFull(_payNow)}', '${_fmtFull(_payNow)} নিশ্চিত করুন')
                  : LanguageService.tr('Confirm', 'নিশ্চিত করুন'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
    Color tint = goldDeep,
    Color tintSoft = goldSoft,
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
                    gradient: LinearGradient(colors: [goldLight, gold]),
                    shape: BoxShape.circle,
                  ),
                  child: Text('$step',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                )
              else if (icon != null)
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: tintSoft, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 14, color: tint),
                )
              else
                Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(width: 7, height: 7, color: gold),
                ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
              ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 35, top: 1),
              child: Text(subtitle, style: const TextStyle(fontSize: 10.5, color: muted)),
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
      labelStyle: const TextStyle(fontSize: 12, color: muted),
      prefixIcon: Icon(icon, color: goldDeep, size: 17),
      prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      helperStyle: const TextStyle(fontSize: 10, color: muted),
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
        Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: ink)),
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
                          child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
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
                      border: Border.all(color: goldDeep.withAlpha(110)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_a_photo_outlined, color: goldDeep, size: 18),
                        const SizedBox(height: 2),
                        Text(LanguageService.tr('Add', 'যোগ করুন'),
                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: goldDeep)),
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
          style: const TextStyle(fontSize: 9.5, color: muted),
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
          const Icon(Icons.error_outline_rounded, size: 15, color: danger),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11.5, color: danger, height: 1.35))),
        ],
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