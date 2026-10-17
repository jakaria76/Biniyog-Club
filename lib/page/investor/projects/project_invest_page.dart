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
import '../portfolio/investments_page.dart';

/// Project e invest: taka + payment er dhoron + proof — ek page e.
/// Confirm korle investment "Pending" hoy, admin approve korle dashboard e ashe.
class ProjectInvestPage extends StatefulWidget {
  /// ProjectDetailPage er _project map (getProjectDetail theke)
  final Map<String, dynamic> project;

  const ProjectInvestPage({super.key, required this.project});

  @override
  State<ProjectInvestPage> createState() => _ProjectInvestPageState();
}

class _ProjectInvestPageState extends State<ProjectInvestPage> {
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
  static const Color terracotta = Color(0xFFA5523A);
  static const Color terracottaSoft = Color(0xFFF7E6DF);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);
  static const Color danger = Color(0xFFB4413A);
  static const Color dangerSoft = Color(0xFFFBEAE8);

  /// User er bola kroma onujayi 7 ta option
  static const List<(String, Set<String>)> _options = [
    ('BANK_CASH', {'BANK', 'CASH'}),
    ('BANK_CHEQUE', {'BANK', 'CHEQUE'}),
    ('CHEQUE_CASH', {'CHEQUE', 'CASH'}),
    ('BANK_CASH_CHEQUE', {'BANK', 'CASH', 'CHEQUE'}),
    ('BANK', {'BANK'}),
    ('CASH', {'CASH'}),
    ('CHEQUE', {'CHEQUE'}),
  ];

  /// Cash ke grohon korechen — ei char jon-er ekjon
  static const List<(String, String)> _cashReceivers = [
    ('MD Sir', 'এমডি স্যার'),
    ('Chairman Sir', 'চেয়ারম্যান স্যার'),
    ('CEO', 'সিইও'),
    ('Finance', 'ফাইন্যান্স'),
  ];

  final _amountController = TextEditingController();
  final _bankAmountController = TextEditingController();
  final _cashAmountController = TextEditingController();
  final _chequeAmountController = TextEditingController();
  final _trxController = TextEditingController();
  final _picker = ImagePicker();

  String? _option; // _options er key
  int _bankIndex = 0;
  String? _cashReceiver;

  Uint8List? _bankReceipt;
  File? _bankReceiptFile;
  Uint8List? _chequeImage;
  File? _chequeImageFile;

  bool _submitting = false;
  String _stage = '';
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _amountController,
      _bankAmountController,
      _cashAmountController,
      _chequeAmountController,
      _trxController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final minInv = _num(widget.project['minInvestmentBdt']);
    if (minInv > 0 && minInv <= _cap) _amountController.text = minInv.toStringAsFixed(0);
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

  double get _minInv => _num(widget.project['minInvestmentBdt']);
  double get _maxInv => widget.project['maxInvestmentBdt'] == null ? 0 : _num(widget.project['maxInvestmentBdt']);
  double get _remaining => _num(widget.project['remainingBdt']);

  /// Sobcheye beshi joto deya jay
  double get _cap {
    double c = _remaining;
    if (_maxInv > 0 && _maxInv < c) c = _maxInv;
    return c;
  }

  double get _amount => double.tryParse(_amountController.text.trim()) ?? 0;

  Set<String> get _methods => _options.firstWhere((o) => o.$1 == _option, orElse: () => ('', <String>{})).$2;

  bool get _isSplit => _methods.length > 1;

  double _part(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  double get _splitTotal =>
      (_methods.contains('BANK') ? _part(_bankAmountController) : 0) +
          (_methods.contains('CASH') ? _part(_cashAmountController) : 0) +
          (_methods.contains('CHEQUE') ? _part(_chequeAmountController) : 0);

  List<Map<String, dynamic>> get _banks => ((widget.project['bankAccounts'] as List?) ?? [])
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
      case 'BANK_CASH_CHEQUE':
        return LanguageService.tr('Bank + Cash + Cheque', 'ব্যাংক + ক্যাশ + চেক');
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
  Future<void> _pick(bool cheque) async {
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
        if (cheque) {
          _chequeImage = bytes;
          _chequeImageFile = File(picked.path);
        } else {
          _bankReceipt = bytes;
          _bankReceiptFile = File(picked.path);
        }
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
    final a = _amount;
    if (a <= 0) return LanguageService.tr('Please enter the amount.', 'পরিমাণ লিখুন।');
    if (_minInv > 0 && a < _minInv) {
      return LanguageService.tr('Minimum investment is ${_fmtFull(_minInv)}.', 'সর্বনিম্ন বিনিয়োগ ${_fmtFull(_minInv)}।');
    }
    if (a > _cap) {
      return LanguageService.tr('Maximum you can invest here is ${_fmtFull(_cap)}.', 'এখানে সর্বোচ্চ ${_fmtFull(_cap)} বিনিয়োগ করা যাবে।');
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
      if ((_splitTotal - a).abs() > 0.5) {
        return LanguageService.tr('The parts add up to ${_fmtFull(_splitTotal)}, but the total is ${_fmtFull(a)}.',
            'ভাগগুলোর যোগফল ${_fmtFull(_splitTotal)}, কিন্তু মোট ${_fmtFull(a)}।');
      }
    }
    if (m.contains('BANK')) {
      if (_banks.isEmpty) {
        return LanguageService.tr('No bank account is set for this project. Choose Cash or Cheque.',
            'এই প্রজেক্টে কোনো ব্যাংক অ্যাকাউন্ট নেই। ক্যাশ বা চেক বেছে নিন।');
      }
      if (_trxController.text.trim().isEmpty) {
        return LanguageService.tr('Enter the bank transaction number.', 'ব্যাংক ট্রানজেকশন নম্বর দিন।');
      }
      if (_bankReceipt == null) {
        return LanguageService.tr('Upload the bank receipt image.', 'ব্যাংক রসিদের ছবি দিন।');
      }
    }
    if (m.contains('CASH') && _cashReceiver == null) {
      return LanguageService.tr('Select who received the cash.', 'ক্যাশ কে গ্রহণ করেছেন বেছে নিন।');
    }
    if (m.contains('CHEQUE') && _chequeImage == null) {
      return LanguageService.tr('Upload the cheque image.', 'চেকের ছবি দিন।');
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
      await AuthService.logout();
      if (!mounted) return;
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

    // Chobi gulo ek shathe upload
    final uploads = await Future.wait<String?>([
      m.contains('BANK') ? _upload(_bankReceipt!, 'payment_proofs') : Future.value(null),
      m.contains('CHEQUE') ? _upload(_chequeImage!, 'payment_proofs') : Future.value(null),
    ]);
    if (!mounted) return;
    if ((m.contains('BANK') && uploads[0] == null) || (m.contains('CHEQUE') && uploads[1] == null)) {
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
    final res = await DatabaseService.investWithPayment(
      userId: userId,
      projectId: widget.project['id'].toString(),
      amountBdt: _amount,
      methods: m.toList(),
      bankAmount: _isSplit ? _part(_bankAmountController) : _amount,
      cashAmount: _isSplit ? _part(_cashAmountController) : _amount,
      chequeAmount: _isSplit ? _part(_chequeAmountController) : _amount,
      bankAccountId: bank?['id']?.toString(),
      bankAccountLabel: bank == null
          ? null
          : '${bank['bankName'] ?? ''}${acc.length > 4 ? ' (…${acc.substring(acc.length - 4)})' : ''}',
      bankTransactionId: _trxController.text.trim(),
      bankReceiptUrl: uploads[0],
      cashReceiver: _cashReceiver,
      chequeImageUrl: uploads[1],
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
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              LanguageService.tr('Invest', 'বিনিয়োগ'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          bottomNavigationBar: _buildBottomBar(),
          body: AbsorbPointer(
            absorbing: _submitting,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _buildProjectHero(),
                const SizedBox(height: 16),
                _buildAmountCard(),
                const SizedBox(height: 16),
                _buildBankDetailsCard(),
                const SizedBox(height: 16),
                _buildMethodCard(),
                if (_isSplit) ...[
                  const SizedBox(height: 16),
                  _buildSplitCard(),
                ],
                if (m.contains('BANK')) ...[
                  const SizedBox(height: 16),
                  _buildBankProofCard(),
                ],
                if (m.contains('CASH')) ...[
                  const SizedBox(height: 16),
                  _buildCashCard(),
                ],
                if (m.contains('CHEQUE')) ...[
                  const SizedBox(height: 16),
                  _buildChequeCard(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
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
    final lo = _num(widget.project['returnMin']);
    final hi = _num(widget.project['returnMax']);
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
              child: CustomPaint(painter: _IslamicPatternPainter(color: Colors.white.withAlpha(16), cell: 44)),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.project['title']?.toString() ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _heroStat(LanguageService.tr('Expected return', 'প্রত্যাশিত লাভ'), _pctRange(lo, hi))),
                      Expanded(child: _heroStat(LanguageService.tr('Still open', 'বাকি আছে'), _fmtFull(_remaining))),
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
      Text(label, style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 11)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: goldLight, fontSize: 15, fontWeight: FontWeight.w700)),
    ],
  );

  // ─── Amount ───────────────────────────────────────────────
  Widget _buildAmountCard() {
    final lo = _num(widget.project['returnMin']);
    final hi = _num(widget.project['returnMax']);
    final a = _amount;
    return _card(
      step: 1,
      title: LanguageService.tr('How much do you want to invest?', 'কত টাকা বিনিয়োগ করবেন?'),
      children: [
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() => _error = null),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ink),
          decoration: _dec(LanguageService.tr('Amount (BDT)', 'পরিমাণ (টাকা)'), Icons.payments_outlined).copyWith(
            prefixText: '৳ ',
            helperText: [
              if (_minInv > 0) LanguageService.tr('Min ${_fmtFull(_minInv)}', 'সর্বনিম্ন ${_fmtFull(_minInv)}'),
              LanguageService.tr('Max ${_fmtFull(_cap)}', 'সর্বোচ্চ ${_fmtFull(_cap)}'),
            ].join(' · '),
          ),
        ),
        if (a > 0 && hi > 0) ...[
          const SizedBox(height: 10),
          Text(
            LanguageService.tr(
              'Expected return: ${lo == hi ? _fmtFull(a * hi) : '${_fmtFull(a * lo)} – ${_fmtFull(a * hi)}'} (estimate, not guaranteed)',
              'প্রত্যাশিত লাভ: ${lo == hi ? _fmtFull(a * hi) : '${_fmtFull(a * lo)} – ${_fmtFull(a * hi)}'} (আনুমানিক, নিশ্চিত নয়)',
            ),
            style: const TextStyle(fontSize: 12, color: emerald, fontWeight: FontWeight.w600),
          ),
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
            style: const TextStyle(fontSize: 12.5, color: muted, height: 1.4),
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
            height: 34,
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
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? Colors.white : ink),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final r in rows) _copyRow(r.$1, r.$2, r.$3),
      ],
    );
  }

  Widget _copyRow(String label, String value, bool copyable) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10.5, color: muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: goldSoft, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.copy_rounded, size: 16, color: goldDeep),
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
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.6,
          ),
          itemBuilder: (_, i) {
            final key = _options[i].$1;
            final on = _option == key;
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() {
                _option = key;
                _error = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: on ? emerald : ivory,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: on ? emerald : line, width: on ? 1.4 : 1),
                ),
                child: Row(
                  children: [
                    Icon(_optionIcon(key), size: 18, color: on ? goldLight : goldDeep),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _optionLabel(key),
                        maxLines: 2,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : ink),
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
    final left = _amount - _splitTotal;
    Widget field(String key, TextEditingController c) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: left.abs() <= 0.5 ? emeraldSoft : goldSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            left.abs() <= 0.5
                ? LanguageService.tr('Matches the total ${_fmtFull(_amount)}', 'মোট ${_fmtFull(_amount)} এর সাথে মিলেছে')
                : left > 0
                ? LanguageService.tr('${_fmtFull(left)} still to assign', 'আরো ${_fmtFull(left)} ভাগ করা বাকি')
                : LanguageService.tr('${_fmtFull(-left)} more than the total', 'মোটের চেয়ে ${_fmtFull(-left)} বেশি'),
            style: TextStyle(
              fontSize: 12,
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
      tint: lapis,
      tintSoft: lapisSoft,
      children: [
        if (bank != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              LanguageService.tr('Paid into: ${bank['bankName'] ?? ''} — change above if different',
                  'যে অ্যাকাউন্টে দিয়েছেন: ${bank['bankName'] ?? ''} — ভিন্ন হলে উপরে বদলান'),
              style: const TextStyle(fontSize: 11.5, color: muted),
            ),
          ),
        TextField(
          controller: _trxController,
          onChanged: (_) => setState(() => _error = null),
          decoration: _dec(LanguageService.tr('Transaction number *', 'ট্রানজেকশন নম্বর *'), Icons.tag_rounded),
        ),
        const SizedBox(height: 12),
        _imageBox(
          label: LanguageService.tr('Bank receipt image *', 'ব্যাংক রসিদের ছবি *'),
          file: _bankReceiptFile,
          onTap: () => _pick(false),
        ),
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
          spacing: 8,
          runSpacing: 8,
          children: _cashReceivers.map((r) {
            final on = _cashReceiver == r.$1;
            return ChoiceChip(
              label: Text(LanguageService.tr(r.$1, r.$2)),
              selected: on,
              showCheckmark: false,
              selectedColor: emerald,
              backgroundColor: ivory,
              side: BorderSide(color: on ? emerald : line),
              labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? Colors.white : ink),
              onSelected: (_) => setState(() {
                _cashReceiver = r.$1;
                _error = null;
              }),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── Cheque ───────────────────────────────────────────────
  Widget _buildChequeCard() {
    return _card(
      title: LanguageService.tr('Cheque payment', 'চেক পেমেন্ট'),
      icon: Icons.receipt_long_outlined,
      tint: terracotta,
      tintSoft: terracottaSoft,
      children: [
        _imageBox(
          label: LanguageService.tr('Cheque image *', 'চেকের ছবি *'),
          file: _chequeImageFile,
          onTap: () => _pick(true),
        ),
      ],
    );
  }

  // ─── Bottom bar ───────────────────────────────────────────
  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: line))),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: emerald,
              foregroundColor: Colors.white,
              disabledBackgroundColor: emerald.withAlpha(140),
              disabledForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _submitting
                ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text(_stage),
              ],
            )
                : Text(
              _amount > 0
                  ? LanguageService.tr('Confirm ${_fmtFull(_amount)}', '${_fmtFull(_amount)} নিশ্চিত করুন')
                  : LanguageService.tr('Confirm', 'নিশ্চিত করুন'),
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (step != null)
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [goldLight, gold]),
                    shape: BoxShape.circle,
                  ),
                  child: Text('$step',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                )
              else if (icon != null)
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: tintSoft, borderRadius: BorderRadius.circular(9)),
                  child: Icon(icon, size: 17, color: tint),
                )
              else
                Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(width: 7, height: 7, color: gold),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
              ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 2),
              child: Text(subtitle, style: const TextStyle(fontSize: 11.5, color: muted)),
            ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: muted),
      prefixIcon: Icon(icon, color: goldDeep, size: 20),
      helperStyle: const TextStyle(fontSize: 11, color: muted),
      filled: true,
      fillColor: ivory,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
      focusedBorder:
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: emerald, width: 1.4)),
    );
  }

  Widget _imageBox({required String label, required File? file, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: file != null ? emeraldSoft : ivory,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: file != null ? emerald : line, width: file != null ? 1.4 : 1),
        ),
        child: file != null
            ? Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.file(file, fit: BoxFit.cover),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.black.withAlpha(150), borderRadius: BorderRadius.circular(20)),
                child: Text(LanguageService.tr('Change', 'বদলান'),
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
          ],
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined, color: goldDeep, size: 28),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink)),
            const SizedBox(height: 2),
            Text(LanguageService.tr('JPG / PNG · up to 10 MB', 'JPG / PNG · ১০ MB পর্যন্ত'),
                style: const TextStyle(fontSize: 10.5, color: muted)),
          ],
        ),
      ),
    );
  }

  Widget _errorBox(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: dangerSoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 17, color: danger),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, color: danger))),
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