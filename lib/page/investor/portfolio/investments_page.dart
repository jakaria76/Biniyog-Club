import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import '../../../services/pdf_service.dart';
import '../../authentication/login_page.dart';
import '../documents/documents_page.dart'; // PdfViewerScreen

class InvestmentsPage extends StatefulWidget {
  /// 'ALL', 'PROJECT' ba 'GROUP' — dashboard theke direct kono tab e khola jabe
  final String initialType;

  const InvestmentsPage({super.key, this.initialType = 'ALL'});

  @override
  State<InvestmentsPage> createState() => _InvestmentsPageState();
}

class _InvestmentsPageState extends State<InvestmentsPage> {
  // ═════════════════════════════════════════════════════════
  // EXPECTED RETURN RANGE — ekhane change korlei shob jaygay bodlabe
  // (project + group dui tai ei range e hisab hoy)
  // ═════════════════════════════════════════════════════════
  static const double minReturnRate = 0.16; // 16%
  static const double maxReturnRate = 0.22; // 22%

  bool _isLoading = true;
  bool _needsLogin = false;

  /// Project + group investment ek list e (kind = 'PROJECT' / 'GROUP')
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _platformBanks = [];

  double _projectInvested = 0.0;
  double _groupInvested = 0.0;
  double _projectPending = 0.0;
  double _groupPending = 0.0;
  int _projectActiveCount = 0;
  int _groupActiveCount = 0;
  double _totalActual = 0.0;
  double _expectedMin = 0.0;
  double _expectedMax = 0.0;

  String _typeFilter = 'ALL'; // ALL / PROJECT / GROUP
  String _statusFilter = 'ALL'; // ALL / ACTIVE / PENDING / COMPLETED / CANCELLED

  // ─── Palette ───
  static const Color emerald = Color(0xFF0E4A37);
  static const Color emeraldDeep = Color(0xFF0A3327);
  static const Color emeraldSoft = Color(0xFFE3F0E9);
  static const Color gold = Color(0xFFB8935A);
  static const Color goldLight = Color(0xFFD9BE8C);
  static const Color goldDeep = Color(0xFF8A6A3A);
  static const Color goldSoft = Color(0xFFF6EEDF);
  static const Color turquoise = Color(0xFF167A80);
  static const Color turquoiseSoft = Color(0xFFE0F1F1);
  static const Color lapis = Color(0xFF26437A);
  static const Color lapisSoft = Color(0xFFE5EAF4);
  static const Color terracotta = Color(0xFFA5523A);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);
  static const Color danger = Color(0xFFB4413A);

  static const Map<String, String> categoryLabels = {
    'REAL_ESTATE': 'Real Estate',
    'TRADE_FINANCE': 'Trade Finance',
    'SME': 'SME Business',
    'TECHNOLOGY': 'Technology',
    'INFRASTRUCTURE': 'Infrastructure',
    'CROP_FARMING': 'Crop Farming',
    'LIVESTOCK': 'Livestock',
    'AQUACULTURE': 'Aquaculture',
    'POULTRY': 'Poultry',
    'DAIRY': 'Dairy',
    'HORTICULTURE': 'Horticulture',
    'AGRO_PROCESSING': 'Agro Processing',
    'OTHER': 'Other',
  };

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.initialType;
    _loadInvestmentsData();
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  DateTime? _parseDate(dynamic s) {
    if (s == null) return null;
    return DateTime.tryParse(s.toString())?.toLocal();
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// 0.15, 0.15 → "15%"   |   0.16, 0.22 → "16–22%"
  String _pctLabel(double min, double max) {
    String p(double r) {
      final v = r * 100;
      return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    }

    return min == max ? '${p(min)}%' : '${p(min)}–${p(max)}%';
  }

  /// Upore KPI card er label: shob active investment er rate ek hole sheta,
  /// na hole shudhu "Expected Return"
  String? _totalRateLabel;

  String _fmtBdt(double amount) {
    return '৳${amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
    )}';
  }

  String _fmtRange(double min, double max) => '${_fmtBdt(min)} – ${_fmtBdt(max)}';

  String _shortId(String id) =>
      id.substring(0, id.length >= 12 ? 12 : id.length).toUpperCase();

  bool _countsAsInvested(String status) =>
      status == 'ACTIVE' || status == 'MATURED' || status == 'COMPLETED';

  bool _isAwaiting(String status) =>
      status == 'PENDING' || status == 'PAYMENT_PENDING';

  // ═════════════════════════════════════════════════════════
  // NORMALIZE — project ar group ke ek-i shape e ana
  // ═════════════════════════════════════════════════════════
  Map<String, dynamic> _fromProject(Map<String, dynamic> inv) {
    final id = inv['id'].toString();
    final durationDays = _num(inv['durationDays']).toInt();
    final start = _parseDate(inv['activatedAt']) ?? _parseDate(inv['createdAt']);
    final goal = _num(inv['fundingGoalBdt']);
    final funded = _num(inv['fundedAmountBdt']);
    final receipt = inv['receiptNumber']?.toString() ?? '';

    return {
      'kind': 'PROJECT',
      'id': id,
      'title': inv['title']?.toString() ?? 'Biniyog Project',
      'category': inv['category']?.toString() ?? 'OTHER',
      'location': inv['location']?.toString() ?? 'Bangladesh',
      'amount': _num(inv['amountBdt']),
      'status': inv['status']?.toString() ?? 'PENDING',
      'createdAt': _parseDate(inv['createdAt']),
      'start': start,
      'maturity': start?.add(Duration(days: durationDays)),
      'durationDays': durationDays,
      'received': _num(inv['actualReturnBdt']),
      // Project: website er motoi project er nijer range (DB theke),
      // na thakle 16–22%
      'returnMin': _num(inv['returnMin']) > 0 ? _num(inv['returnMin']) : minReturnRate,
      'returnMax': _num(inv['returnMax']) > 0 ? _num(inv['returnMax']) : maxReturnRate,
      'progress': goal > 0 ? (funded / goal).clamp(0.0, 1.0).toDouble() : 0.0,
      // Website er certificate e asol receiptNumber thake — oita-i dekhai
      'certNo': receipt.isNotEmpty ? receipt : 'BC-${_shortId(id)}',
      'latestSubmission': inv['latestSubmission'],
      'bankAccounts': ((inv['bankAccounts'] as List?) ?? [])
          .map((b) => Map<String, dynamic>.from(b as Map))
          .toList(),
      'websiteCertificate': inv['websiteCertificate'],
    };
  }

  Map<String, dynamic> _fromGroup(Map<String, dynamic> g) {
    final id = g['id'].toString();
    final months = _num(g['durationMonths']).toInt();
    final start = _parseDate(g['createdAt']);
    final maturity = (start == null || months <= 0)
        ? null
        : DateTime(start.year, start.month + months, start.day);
    final receipt = g['receiptNumber']?.toString() ?? '';
    final groupName = g['groupName']?.toString() ?? 'Business Group';
    final entityName = g['entityName']?.toString() ?? '';
    final bank = g['bank'] as Map<String, dynamic>?;
    final plot = g['plotNumber']?.toString() ?? '';

    // Group: tier er nijer return % (jemon Investor Tier = 15%).
    // Tier e % na thakle tobei standard range.
    final tierPct = _num(g['expectedReturnPct']);
    final rMin = tierPct > 0 ? tierPct : minReturnRate;
    final rMax = tierPct > 0 ? tierPct : maxReturnRate;

    // "Mariners Group — Mariners Group" er moto ek nam dui bar na
    final showEntity = entityName.isNotEmpty &&
        entityName.trim().toLowerCase() != groupName.trim().toLowerCase();

    return {
      'kind': 'GROUP',
      'id': id,
      'title': showEntity ? '$groupName — $entityName' : groupName,
      'returnMin': rMin,
      'returnMax': rMax,
      'tierName': g['tierName']?.toString() ?? 'Tier',
      'plotNumber': (plot.isEmpty || plot == 'N/A') ? null : plot,
      'sharePercentage': _num(g['sharePercentage']),
      'amount': _num(g['amountBdt']),
      'status': g['status']?.toString() ?? 'PENDING',
      'createdAt': start,
      'start': start,
      'maturity': maturity,
      'durationMonths': months,
      'received': 0.0,
      'certNo': receipt.isNotEmpty ? receipt : 'GRP-${_shortId(id)}',
      'latestSubmission': g['latestSubmission'],
      'bankAccounts': bank != null ? [bank] : <Map<String, dynamic>>[],
    };
  }

  // ═════════════════════════════════════════════════════════
  // DATA
  // ═════════════════════════════════════════════════════════
  Future<void> _loadInvestmentsData() async {
    if (mounted) setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    final userEmail = userData?['email']?.toString() ?? '';

    // Login chara onner data dekhabo na
    if (userId.isEmpty) {
      if (mounted) {
        setState(() {
          _needsLogin = true;
          _isLoading = false;
        });
      }
      return;
    }

    final results = await Future.wait<dynamic>([
      DatabaseService.getPortfolioData(userId, email: userEmail),
      DatabaseService.getGroupInvestmentsData(userId, email: userEmail),
    ]);

    final pData = results[0] as Map<String, dynamic>;
    final gData = results[1] as List<Map<String, dynamic>>;

    final items = <Map<String, dynamic>>[
      ...((pData['investments'] as List?) ?? [])
          .map((e) => _fromProject(Map<String, dynamic>.from(e as Map))),
      ...gData.map(_fromGroup),
    ];

    items.sort((a, b) {
      final da = a['createdAt'] as DateTime?;
      final db = b['createdAt'] as DateTime?;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    double pInv = 0, gInv = 0, pPen = 0, gPen = 0, actual = 0, eMin = 0, eMax = 0;
    int pAct = 0, gAct = 0;
    final rateLabels = <String>{};

    for (final i in items) {
      final amt = i['amount'] as double;
      final st = i['status'] as String;
      final isProject = i['kind'] == 'PROJECT';
      final rMin = i['returnMin'] as double;
      final rMax = i['returnMax'] as double;

      if (_countsAsInvested(st)) {
        if (isProject) {
          pInv += amt;
          pAct++;
        } else {
          gInv += amt;
          gAct++;
        }
        eMin += amt * rMin;
        eMax += amt * rMax;
        rateLabels.add(_pctLabel(rMin, rMax));
      } else if (_isAwaiting(st)) {
        if (isProject) {
          pPen += amt;
        } else {
          gPen += amt;
        }
      }
      actual += i['received'] as double;
    }

    if (!mounted) return;
    setState(() {
      _needsLogin = false;
      _items = items;
      _platformBanks = ((pData['bankAccounts'] as List?) ?? [])
          .map((b) => Map<String, dynamic>.from(b as Map))
          .toList();
      _projectInvested = pInv;
      _groupInvested = gInv;
      _projectPending = pPen;
      _groupPending = gPen;
      _projectActiveCount = pAct;
      _groupActiveCount = gAct;
      _totalActual = actual;
      _expectedMin = eMin;
      _expectedMax = eMax;
      _totalRateLabel = rateLabels.length == 1 ? rateLabels.first : null;
      _isLoading = false;
    });
  }

  // ─── Filters ──────────────────────────────────────────────
  List<Map<String, dynamic>> get _typedItems => _typeFilter == 'ALL'
      ? _items
      : _items.where((i) => i['kind'] == _typeFilter).toList();

  bool _matchStatus(String s, String filter) {
    switch (filter) {
      case 'ACTIVE':
        return s == 'ACTIVE';
      case 'PENDING':
        return _isAwaiting(s);
      case 'COMPLETED':
        return s == 'COMPLETED' || s == 'MATURED';
      case 'CANCELLED':
        return s == 'CANCELLED' || s == 'REJECTED';
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> get _visibleItems => _typedItems
      .where((i) => _matchStatus(i['status'] as String, _statusFilter))
      .toList();

  // ═════════════════════════════════════════════════════════
  // WEBSITE CERTIFICATE (shudhu project investment)
  // ═════════════════════════════════════════════════════════
  Future<void> _openWebsiteCertificate(Map<String, dynamic> item) async {
    final cert = item['websiteCertificate'] as Map<String, dynamic>?;
    if (cert == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LanguageService.tr(
              'Your certificate is being prepared. Pull down to refresh in a few minutes.',
              'সার্টিফিকেট তৈরি হচ্ছে। কিছুক্ষণ পর নিচে টেনে রিফ্রেশ করুন।')),
          backgroundColor: goldDeep,
        ),
      );
      return;
    }
    try {
      final bytes = await PdfService.buildWebsiteCertificate(cert);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            title: LanguageService.tr('Investment Certificate', 'ইনভেস্টমেন্ট সার্টিফিকেট'),
            bytes: bytes,
            fileName: 'Certificate_${cert['certificateNo']}.pdf',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF error: $e'), backgroundColor: danger),
      );
    }
  }

  // ═════════════════════════════════════════════════════════
  // SUBMIT PROOF — project ar group dui tar jonno ek-i modal
  // ═════════════════════════════════════════════════════════
  void _showSubmitProofModal(Map<String, dynamic> item) {
    final bool isGroup = item['kind'] == 'GROUP';
    final pageMessenger = ScaffoldMessenger.of(context);

    final itemBanks = item['bankAccounts'] as List<Map<String, dynamic>>;
    final banks = itemBanks.isNotEmpty ? itemBanks : _platformBanks;

    if (banks.isEmpty) {
      pageMessenger.showSnackBar(
        SnackBar(
          content: Text(LanguageService.tr(
              'No bank account found for this investment. Please contact support.',
              'এই বিনিয়োগের জন্য কোনো ব্যাংক অ্যাকাউন্ট পাওয়া যায়নি। সাপোর্টে যোগাযোগ করুন।')),
          backgroundColor: danger,
        ),
      );
      return;
    }

    final trxRefController = TextEditingController();
    final notesController = TextEditingController();
    String selectedBankId = banks.first['id'].toString();
    bool submitting = false;
    File? selectedProofFile;
    String? proofBase64;
    final ImagePicker picker = ImagePicker();
    final double principal = item['amount'] as double;

    InputDecoration deco(String label, String hint) => InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: ivory,
      labelStyle: const TextStyle(color: muted, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: emerald, width: 1.4),
      ),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final selectedBank = banks.firstWhere(
                  (b) => b['id'].toString() == selectedBankId,
              orElse: () => banks.first,
            );

            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isGroup
                                ? LanguageService.tr('Submit Group Payment Proof',
                                'গ্রুপ পেমেন্ট প্রুফ সাবমিট করুন')
                                : LanguageService.tr('Submit Payment Proof',
                                'পেমেন্ট প্রুফ সাবমিট করুন'),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700, color: ink),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    Text(
                      '${item['title']} · ${_fmtBdt(principal)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isGroup ? turquoise : emerald,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      LanguageService.tr('Bank account you paid into',
                          'যে ব্যাংক অ্যাকাউন্টে টাকা পাঠিয়েছেন'),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: ink),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: ivory,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: line),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedBankId,
                          isExpanded: true,
                          items: banks.map((b) {
                            return DropdownMenuItem<String>(
                              value: b['id'].toString(),
                              child: Text(
                                '${b['bankName']} (${b['accountNumber']})',
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setModalState(() => selectedBankId = val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: goldSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _bankLine(LanguageService.tr('Account Name', 'অ্যাকাউন্টের নাম'),
                              selectedBank['accountName']?.toString() ?? '—'),
                          _bankLine(LanguageService.tr('Account No.', 'অ্যাকাউন্ট নম্বর'),
                              selectedBank['accountNumber']?.toString() ?? '—'),
                          if ((selectedBank['branchName']?.toString() ?? '').isNotEmpty)
                            _bankLine(LanguageService.tr('Branch', 'শাখা'),
                                selectedBank['branchName'].toString()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: trxRefController,
                      decoration: deco(
                        LanguageService.tr('Deposit Slip No / Transaction Ref *',
                            'ডিপোজিট স্লিপ নম্বর / ট্রানজেকশন রেফ *'),
                        'e.g. TRX987654321',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: deco(
                        LanguageService.tr('Notes / Depositor Name (optional)',
                            'নোটস / জমাদানকারীর নাম (ঐচ্ছিক)'),
                        'e.g. Transferred from City Bank',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      LanguageService.tr('Upload Payment Receipt / Deposit Slip *',
                          'পেমেন্ট রসিদ / ডিপোজিট স্লিপ আপলোড করুন *'),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: ink),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () async {
                        try {
                          final XFile? picked = await picker.pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 1600,
                            maxHeight: 1600,
                            imageQuality: 85,
                          );
                          if (picked != null) {
                            final file = File(picked.path);
                            final bytes = await file.readAsBytes();
                            final b64 = 'data:image/png;base64,${base64Encode(bytes)}';
                            setModalState(() {
                              selectedProofFile = file;
                              proofBase64 = b64;
                            });
                          }
                        } catch (e) {
                          debugPrint('Error picking proof image: $e');
                        }
                      },
                      child: Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: ivory,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: line),
                        ),
                        child: selectedProofFile != null
                            ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(selectedProofFile!,
                              fit: BoxFit.cover, width: double.infinity),
                        )
                            : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_upload_outlined,
                                size: 32, color: emerald),
                            const SizedBox(height: 6),
                            Text(
                              LanguageService.tr('Tap to upload receipt image',
                                  'রসিদের ছবি আপলোড করতে ট্যাপ করুন'),
                              style: const TextStyle(fontSize: 12, color: muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: submitting
                          ? null
                          : () async {
                        final ref = trxRefController.text.trim();
                        if (ref.isEmpty) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(
                              content: Text(LanguageService.tr(
                                  'Please enter transaction reference / deposit slip no.',
                                  'ট্রানজেকশন রেফারেন্স বা জমা স্লিপ নম্বর লিখুন।')),
                              backgroundColor: danger,
                            ),
                          );
                          return;
                        }
                        if (proofBase64 == null || proofBase64!.isEmpty) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(
                              content: Text(LanguageService.tr(
                                  'Please upload payment receipt / deposit slip image.',
                                  'অনুগ্রহ করে পেমেন্ট রসিদ বা ডিপোজিট স্লিপের ছবি আপলোড করুন।')),
                              backgroundColor: danger,
                            ),
                          );
                          return;
                        }

                        setModalState(() => submitting = true);

                        final userData = await AuthService.getUserData();
                        final userId = userData?['id']?.toString() ?? '';
                        final notes = notesController.text.trim();

                        final Map<String, dynamic> res = isGroup
                            ? await DatabaseService.submitGroupInvestmentPayment(
                          groupInvestmentId: item['id'].toString(),
                          userId: userId,
                          amountBdt: principal,
                          bankAccountId: selectedBankId,
                          transactionRef: ref,
                          proofFileUrl: proofBase64!,
                          notes: notes.isEmpty ? null : notes,
                        )
                            : await DatabaseService.submitManualPaymentProof(
                          investmentId: item['id'].toString(),
                          userId: userId,
                          amountBdt: principal,
                          transactionRef: ref,
                          bankAccountId: selectedBankId,
                          proofFileUrl: proofBase64!,
                          notes: notes.isEmpty ? null : notes,
                        );

                        if (!sheetContext.mounted) return;
                        Navigator.pop(sheetContext);

                        if (res['success'] == true) {
                          pageMessenger.showSnackBar(
                            SnackBar(
                              content: Text(LanguageService.tr(
                                  'Payment proof submitted! Pending admin review.',
                                  'পেমেন্ট প্রুফ সাবমিট হয়েছে! এডমিন পর্যালোচনার অপেক্ষায়।')),
                              backgroundColor: emerald,
                            ),
                          );
                          _loadInvestmentsData();
                        } else {
                          pageMessenger.showSnackBar(
                            SnackBar(
                              content: Text(res['message']?.toString() ??
                                  'Failed to submit.'),
                              backgroundColor: danger,
                            ),
                          );
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: emerald,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: submitting
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                          : Text(
                        LanguageService.tr('Submit Payment Proof', 'পেমেন্ট প্রুফ জমা দিন'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _bankLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: muted)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: ink),
            ),
          ),
        ],
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
      builder: (context, lang, child) {
        final projectCount = _items.where((i) => i['kind'] == 'PROJECT').length;
        final groupCount = _items.length - projectCount;
        final visible = _visibleItems;

        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              LanguageService.tr('Investments', 'ইনভেস্টমেন্টস'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          body: _isLoading
              ? const Center(
              child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4))
              : _needsLogin
              ? _buildNeedsLogin()
              : RefreshIndicator(
            onRefresh: _loadInvestmentsData,
            color: emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                Text(
                  LanguageService.tr(
                      '${_items.length} total investments · $projectCount project · $groupCount group',
                      'মোট ${_items.length} টি বিনিয়োগ · প্রজেক্ট $projectCount · গ্রুপ $groupCount'),
                  style: const TextStyle(fontSize: 13, color: muted),
                ),
                const SizedBox(height: 14),
                _buildKpiSection(),
                const SizedBox(height: 18),
                _buildTypeSelector(projectCount, groupCount),
                const SizedBox(height: 12),
                _buildStatusFilterBar(),
                const SizedBox(height: 18),
                if (visible.isEmpty)
                  _buildEmptyInvestmentsCard()
                else
                  ...visible.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildInvestmentCard(item),
                  )),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── KPI Section ──────────────────────────────────────────
  Widget _buildKpiSection() {
    final total = _projectInvested + _groupInvested;

    return Column(
      children: [
        // Total + returns
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [emerald, emeraldDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LanguageService.tr('TOTAL INVESTED', 'মোট বিনিয়োগ'),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: goldLight,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _fmtBdt(total),
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                    Text(
                      LanguageService.tr('Project + Group', 'প্রজেক্ট + গ্রুপ'),
                      style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(170)),
                    ),
                  ],
                ),
              ),
              Container(
                width: 0.8,
                height: 44,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: Colors.white.withAlpha(40),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    LanguageService.tr('Returns Received', 'প্রাপ্ত লাভ'),
                    style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(170)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _fmtBdt(_totalActual),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700, color: goldLight),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Project vs Group
        Row(
          children: [
            Expanded(
              child: _splitCard(
                kind: 'PROJECT',
                label: LanguageService.tr('Project Invested', 'প্রজেক্ট ইনভেস্টেড'),
                amount: _projectInvested,
                activeCount: _projectActiveCount,
                pending: _projectPending,
                icon: Icons.trending_up_rounded,
                color: emerald,
                soft: emeraldSoft,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _splitCard(
                kind: 'GROUP',
                label: LanguageService.tr('Group Invested', 'গ্রুপ ইনভেস্টেড'),
                amount: _groupInvested,
                activeCount: _groupActiveCount,
                pending: _groupPending,
                icon: Icons.apartment_rounded,
                color: turquoise,
                soft: turquoiseSoft,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Expected return range
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: goldSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: gold.withAlpha(70)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: goldDeep,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.show_chart_rounded, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _totalRateLabel != null
                          ? LanguageService.tr('Expected Return ($_totalRateLabel)',
                          'প্রত্যাশিত লাভ ($_totalRateLabel)')
                          : LanguageService.tr('Expected Return', 'প্রত্যাশিত লাভ'),
                      style: TextStyle(
                        fontSize: 11,
                        color: goldDeep.withAlpha(220),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _fmtRange(_expectedMin, _expectedMax),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700, color: goldDeep),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _splitCard({
    required String kind,
    required String label,
    required double amount,
    required int activeCount,
    required double pending,
    required IconData icon,
    required Color color,
    required Color soft,
  }) {
    final bool selected = _typeFilter == kind;

    return Material(
      color: soft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _typeFilter = selected ? 'ALL' : kind),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 1.4,
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
                      color: color,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, size: 16, color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    LanguageService.tr('$activeCount active', '$activeCount টি চলমান'),
                    style: TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _fmtBdt(amount),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: color.withAlpha(200)),
              ),
              const SizedBox(height: 6),
              Text(
                pending > 0
                    ? LanguageService.tr('Pending ${_fmtBdt(pending)}',
                    'অপেক্ষমান ${_fmtBdt(pending)}')
                    : LanguageService.tr('No pending', 'অপেক্ষমান নেই'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: pending > 0 ? terracotta : muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Type Selector (All / Projects / Groups) ──────────────
  Widget _buildTypeSelector(int projectCount, int groupCount) {
    final types = [
      ('ALL', LanguageService.tr('All', 'সব'), _items.length),
      ('PROJECT', LanguageService.tr('Projects', 'প্রজেক্ট'), projectCount),
      ('GROUP', LanguageService.tr('Groups', 'গ্রুপ'), groupCount),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line),
      ),
      child: Row(
        children: types.map((t) {
          final bool sel = _typeFilter == t.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _typeFilter = t.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? emerald : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${t.$2} (${t.$3})',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? Colors.white : ink,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Status Filter Bar ────────────────────────────────────
  Widget _buildStatusFilterBar() {
    final typed = _typedItems;
    int count(String filter) =>
        typed.where((i) => _matchStatus(i['status'] as String, filter)).length;

    final filters = [
      ('ALL', 'All', 'সব'),
      ('ACTIVE', 'Active', 'একটিভ'),
      ('PENDING', 'Pending', 'অপেক্ষমান'),
      ('COMPLETED', 'Completed', 'সম্পন্ন'),
      ('CANCELLED', 'Cancelled', 'বাতিল'),
    ];

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final f = filters[index];
          final bool isSel = _statusFilter == f.$1;
          final int n = count(f.$1);

          return GestureDetector(
            onTap: () => setState(() => _statusFilter = f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSel ? emerald : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSel ? emerald : line),
              ),
              child: Row(
                children: [
                  Text(
                    LanguageService.tr(f.$2, f.$3),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      color: isSel ? Colors.white : ink,
                    ),
                  ),
                  if (n > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSel ? gold : ivory,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$n',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isSel ? Colors.white : ink,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _kindBadge(bool isGroup) {
    final c = isGroup ? turquoise : emerald;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withAlpha(22),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isGroup ? Icons.apartment_rounded : Icons.trending_up_rounded,
              size: 12, color: c),
          const SizedBox(width: 4),
          Text(
            isGroup
                ? LanguageService.tr('GROUP', 'গ্রুপ')
                : LanguageService.tr('PROJECT', 'প্রজেক্ট'),
            style: TextStyle(
                fontSize: 9.5, fontWeight: FontWeight.w800, color: c, letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }

  // ─── Payment status banner (boro, bold) ───────────────────
  Widget _paymentStatusBanner({
    required String status,
    required bool awaiting,
    required bool underReview,
    required bool rejected,
    String? reason,
  }) {
    final IconData icon;
    final Color c;
    final String title;
    final String desc;

    if (rejected) {
      icon = Icons.cancel_rounded;
      c = danger;
      title = LanguageService.tr('Payment Rejected', 'পেমেন্ট বাতিল হয়েছে');
      desc = (reason != null && reason.isNotEmpty)
          ? LanguageService.tr('Reason: $reason', 'কারণ: $reason')
          : LanguageService.tr('Please check and submit your payment again.', 'যাচাই করে আবার পেমেন্ট জমা দিন।');
    } else if (underReview) {
      icon = Icons.hourglass_top_rounded;
      c = lapis;
      title = LanguageService.tr('Payment Under Review', 'পেমেন্ট যাচাই চলছে');
      desc = LanguageService.tr('Admin is checking your payment. It becomes active after approval.',
          'অ্যাডমিন আপনার পেমেন্ট যাচাই করছেন। অনুমোদনের পর চালু হবে।');
    } else if (awaiting) {
      icon = Icons.error_outline_rounded;
      c = goldDeep;
      title = LanguageService.tr('Payment Not Submitted', 'পেমেন্ট জমা হয়নি');
      desc = LanguageService.tr('Send the money and submit your payment proof below.',
          'টাকা পাঠিয়ে নিচে পেমেন্ট প্রুফ জমা দিন।');
    } else if (status == 'ACTIVE') {
      icon = Icons.verified_rounded;
      c = emerald;
      title = LanguageService.tr('Payment Approved · Active', 'পেমেন্ট অনুমোদিত · চালু');
      desc = LanguageService.tr('Your investment is running.', 'আপনার বিনিয়োগ চলছে।');
    } else if (status == 'COMPLETED' || status == 'MATURED') {
      icon = Icons.task_alt_rounded;
      c = lapis;
      title = LanguageService.tr('Completed', 'সম্পন্ন');
      desc = LanguageService.tr('This investment has finished its term.', 'এই বিনিয়োগের মেয়াদ শেষ।');
    } else {
      icon = Icons.block_rounded;
      c = danger;
      title = LanguageService.tr('Cancelled', 'বাতিল');
      desc = LanguageService.tr('This investment was cancelled.', 'এই বিনিয়োগ বাতিল হয়েছে।');
    }

    // Bam pashe rong er dag — borderRadius + ek pasher border Flutter e
    // assert kore, tai alada strip
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.withAlpha(22),
        borderRadius: BorderRadius.circular(14),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: c),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: c, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: c, height: 1.2),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            desc,
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600, color: c.withAlpha(220), height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Investment Card ──────────────────────────────────────
  Widget _buildInvestmentCard(Map<String, dynamic> item) {
    final bool isGroup = item['kind'] == 'GROUP';
    final String status = item['status'] as String;
    final Color accent = isGroup ? turquoise : emerald;

    final double principal = item['amount'] as double;
    final double rMin = item['returnMin'] as double;
    final double rMax = item['returnMax'] as double;
    final String rateLabel = _pctLabel(rMin, rMax);
    final double expMin = principal * rMin;
    final double expMax = principal * rMax;
    final double received = item['received'] as double;

    final DateTime? start = item['start'] as DateTime?;
    final DateTime? maturity = item['maturity'] as DateTime?;
    final int daysLeft = maturity == null
        ? 0
        : maturity.difference(DateTime.now()).inDays.clamp(0, 100000);

    final sub = item['latestSubmission'] as Map<String, dynamic>?;
    final String? subStatus = sub?['status']?.toString();
    final String? subRef = sub?['transactionRef']?.toString();
    final String? rejectionReason = sub?['rejectionReason']?.toString();

    final bool awaiting = _isAwaiting(status);
    final bool activeLike = _countsAsInvested(status);
    final bool rejected = awaiting && subStatus == 'REJECTED';
    final bool underReview = awaiting && sub != null && !rejected;

    final String subtitle;
    if (isGroup) {
      final plot = item['plotNumber'] as String?;
      subtitle = plot != null
          ? '${item['tierName']} · ${LanguageService.tr('Plot', 'প্লট')} $plot'
          : item['tierName'].toString();
    } else {
      final cat = categoryLabels[item['category']] ?? item['category'].toString();
      subtitle = '$cat · ${item['location']}';
    }

    final String durationText = isGroup
        ? LanguageService.tr('${item['durationMonths']} months', '${item['durationMonths']} মাস')
        : LanguageService.tr('${item['durationDays']} days', '${item['durationDays']} দিন');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: rejected ? danger.withAlpha(120) : line,
          width: rejected ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kindBadge(isGroup),
                      const SizedBox(height: 8),
                      Text(
                        item['title'].toString(),
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w700, color: ink),
                      ),
                      const SizedBox(height: 3),
                      Text(subtitle, style: const TextStyle(fontSize: 11.5, color: muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      item['certNo'].toString(),
                      style: const TextStyle(
                          fontSize: 9.5, color: muted, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Payment er obostha — boro kore, jate ek nojore bojha jay
          _paymentStatusBanner(
            status: status,
            awaiting: awaiting,
            underReview: underReview,
            rejected: rejected,
            reason: rejectionReason,
          ),
          const SizedBox(height: 12),

          // Return breakdown
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent, emeraldDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _breakdownRow(LanguageService.tr('Principal', 'মূলধন'), _fmtBdt(principal)),
                const SizedBox(height: 10),
                _breakdownRow(
                  LanguageService.tr('Expected return ($rateLabel)',
                      'প্রত্যাশিত লাভ ($rateLabel)'),
                  expMin == expMax
                      ? '+ ${_fmtBdt(expMin)}'
                      : '+ ${_fmtRange(expMin, expMax)}',
                  valueColor: goldLight,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(height: 0.8, color: Colors.white.withAlpha(40)),
                ),
                _breakdownRow(
                  LanguageService.tr('Total value', 'মোট মূল্য'),
                  expMin == expMax
                      ? _fmtBdt(principal + expMin)
                      : _fmtRange(principal + expMin, principal + expMax),
                  bold: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Details grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _detailBox(
                        LanguageService.tr('INVESTED ON', 'বিনিয়োগের তারিখ'),
                        _fmtDate(item['createdAt'] as DateTime?),
                        activeLike && start != null
                            ? '${LanguageService.tr('Active', 'একটিভ')} ${_fmtDate(start)}'
                            : LanguageService.tr('Not active yet', 'এখনো একটিভ নয়'),
                        accent: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _detailBox(
                        LanguageService.tr('MATURITY DATE', 'মেয়াদ শেষ'),
                        activeLike ? _fmtDate(maturity) : '—',
                        activeLike
                            ? (maturity == null
                            ? '—'
                            : LanguageService.tr('$daysLeft days left', '$daysLeft দিন বাকি'))
                            : LanguageService.tr('Starts after payment', 'পেমেন্টের পর শুরু'),
                        accent: goldDeep,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _detailBox(
                        LanguageService.tr('DURATION', 'মেয়াদ'),
                        durationText,
                        LanguageService.tr('Investment term', 'বিনিয়োগের মেয়াদ'),
                        accent: lapis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: isGroup
                          ? _detailBox(
                        LanguageService.tr('SHARE', 'শেয়ার'),
                        _shareText(item['sharePercentage'] as double),
                        item['plotNumber'] != null
                            ? '${LanguageService.tr('Plot', 'প্লট')} ${item['plotNumber']}'
                            : LanguageService.tr('Group share', 'গ্রুপ শেয়ার'),
                        accent: turquoise,
                      )
                          : _detailBox(
                        LanguageService.tr('DISTRIBUTIONS', 'বিতরণ'),
                        received > 0 ? _fmtBdt(received) : '—',
                        received > 0
                            ? LanguageService.tr('Received so far', 'এ পর্যন্ত প্রাপ্ত')
                            : LanguageService.tr('None yet', 'এখনো নেই'),
                      ),
                    ),
                  ],
                ),
                if (!isGroup) ...[
                  const SizedBox(height: 8),
                  _fundedBar(item['progress'] as double),
                ],
              ],
            ),
          ),

          // Payment submission status (shudhu pending investment e)
          if (awaiting && sub != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: rejected ? danger.withAlpha(18) : goldSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: rejected ? danger.withAlpha(80) : gold.withAlpha(90),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        rejected ? Icons.error_outline_rounded : Icons.hourglass_top_rounded,
                        size: 16,
                        color: rejected ? danger : goldDeep,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        rejected
                            ? LanguageService.tr('Proof Rejected', 'প্রুফ বাতিল হয়েছে')
                            : LanguageService.tr('Proof under review', 'প্রুফ পর্যালোচনায় আছে'),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: rejected ? danger : goldDeep,
                        ),
                      ),
                      const Spacer(),
                      if (subRef != null && subRef.isNotEmpty)
                        Flexible(
                          child: Text(
                            'Ref: $subRef',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10.5, color: muted),
                          ),
                        ),
                    ],
                  ),
                  if (rejectionReason != null && rejectionReason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      rejectionReason,
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w600, color: danger),
                    ),
                  ],
                ],
              ),
            ),

          // Footer
          const SizedBox(height: 12),
          const Divider(height: 1, color: line),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _footerText(
                      isGroup: isGroup,
                      awaiting: awaiting,
                      underReview: underReview,
                      rejected: rejected,
                      activeLike: activeLike,
                    ),
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ),
                if (awaiting && !underReview)
                  FilledButton.icon(
                    onPressed: () => _showSubmitProofModal(item),
                    icon: const Icon(Icons.upload_file_rounded, size: 15),
                    label: Text(
                      rejected
                          ? LanguageService.tr('Resubmit', 'পুনরায় পাঠান')
                          : LanguageService.tr('Submit Proof', 'প্রুফ দিন'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  )
                else if (activeLike && !isGroup)
                  OutlinedButton.icon(
                    onPressed: () => _openWebsiteCertificate(item),
                    icon: const Icon(Icons.workspace_premium_outlined, size: 15),
                    label: Text(
                      LanguageService.tr('Certificate', 'সার্টিফিকেট'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: goldDeep,
                      side: BorderSide(color: gold.withAlpha(150)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _footerText({
    required bool isGroup,
    required bool awaiting,
    required bool underReview,
    required bool rejected,
    required bool activeLike,
  }) {
    if (underReview) {
      return LanguageService.tr('Admin is reviewing your payment',
          'এডমিন আপনার পেমেন্ট যাচাই করছেন');
    }
    if (rejected) {
      return LanguageService.tr('Please resubmit a valid payment proof',
          'সঠিক পেমেন্ট প্রুফ আবার জমা দিন');
    }
    if (awaiting) {
      return LanguageService.tr('Submit payment proof to activate',
          'একটিভ করতে পেমেন্ট প্রুফ দিন');
    }
    if (activeLike) {
      return isGroup
          ? LanguageService.tr('Group investment is active', 'গ্রুপ বিনিয়োগ চলমান')
          : LanguageService.tr('Investment certificate available',
          'ইনভেস্টমেন্ট সার্টিফিকেট প্রস্তুত');
    }
    return LanguageService.tr('This investment was cancelled', 'এই বিনিয়োগ বাতিল হয়েছে');
  }

  String _shareText(double share) {
    if (share <= 0) return '—';
    final s = share == share.roundToDouble()
        ? share.toStringAsFixed(0)
        : share.toStringAsFixed(2);
    return '$s%';
  }

  Widget _fundedBar(double progress) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ivory,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                LanguageService.tr('PROJECT FUNDED', 'প্রজেক্ট ফান্ডেড'),
                style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: muted,
                    letterSpacing: 0.4),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: emerald),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: const Color(0xFFEDE8DE),
              valueColor: const AlwaysStoppedAnimation<Color>(emerald),
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow(String label, String value,
      {Color? valueColor, bool bold = false}) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Text(
            label,
            style: TextStyle(
              fontSize: bold ? 12.5 : 11.5,
              color: Colors.white.withAlpha(bold ? 230 : 170),
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: TextStyle(
                fontSize: bold ? 16 : 14,
                fontWeight: FontWeight.w700,
                color: valueColor ?? Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailBox(String label, String value, String sub, {Color accent = emerald}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ivory,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: muted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: accent),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9.5, color: muted),
          ),
        ],
      ),
    );
  }

  // ─── Empty / Login ────────────────────────────────────────
  Widget _buildEmptyInvestmentsCard() {
    final bool groupsOnly = _typeFilter == 'GROUP';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(color: goldSoft, shape: BoxShape.circle),
            child: Icon(
              groupsOnly ? Icons.apartment_rounded : Icons.inventory_2_outlined,
              size: 28,
              color: goldDeep,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            LanguageService.tr('No investments found', 'কোনো বিনিয়োগ পাওয়া যায়নি'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
          ),
          const SizedBox(height: 4),
          Text(
            groupsOnly
                ? LanguageService.tr('Browse business groups to make a group investment.',
                'গ্রুপ বিনিয়োগের জন্য বিজনেস গ্রুপসমূহ দেখুন।')
                : LanguageService.tr('Browse open projects to make your first investment.',
                'আপনার প্রথম বিনিয়োগের জন্য প্রজেক্টসমূহ দেখুন।'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }

  Widget _buildNeedsLogin() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 40, color: goldDeep),
            const SizedBox(height: 12),
            Text(
              LanguageService.tr('Please log in to see your investments',
                  'আপনার বিনিয়োগ দেখতে লগইন করুন'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                      (route) => false,
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(LanguageService.tr('Log in', 'লগইন')),
            ),
          ],
        ),
      ),
    );
  }
}