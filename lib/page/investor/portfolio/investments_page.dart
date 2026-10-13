import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';

class InvestmentsPage extends StatefulWidget {
  const InvestmentsPage({super.key});

  @override
  State<InvestmentsPage> createState() => _InvestmentsPageState();
}

class _InvestmentsPageState extends State<InvestmentsPage> {
  // ═════════════════════════════════════════════════════════
  // EXPECTED RETURN RANGE — ekhane change korlei shob jaygay bodlabe
  // ═════════════════════════════════════════════════════════
  static const double minReturnRate = 0.16; // 16%
  static const double maxReturnRate = 0.22; // 22%

  bool _isLoading = true;
  Map<String, dynamic>? _user;

  double _totalInvested = 0.0;
  double _totalExpectedMin = 0.0;
  double _totalExpectedMax = 0.0;
  double _totalActual = 0.0;

  String _selectedStatusFilter = 'ALL';

  List<Map<String, dynamic>> _investments = [];
  List<Map<String, dynamic>> _bankAccounts = [];

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
    _loadInvestmentsData();
  }

  // ═════════════════════════════════════════════════════════
  // RETURN CALCULATION LOGIC
  // ═════════════════════════════════════════════════════════

  String get _rangeLabel {
    String p(double r) {
      final v = r * 100;
      return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    }

    return '${p(minReturnRate)}–${p(maxReturnRate)}%';
  }

  DateTime? _parseDate(dynamic s) {
    if (s == null) return null;
    return DateTime.tryParse(s.toString())?.toLocal();
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// Ekta investment er shob hisab
  /// 100000 → return 16000–22000, total 116000–122000
  Map<String, dynamic> _calc(Map<String, dynamic> inv) {
    final double principal = (inv['amountBdt'] as num?)?.toDouble() ?? 0.0;

    final double expectedMin = principal * minReturnRate;
    final double expectedMax = principal * maxReturnRate;
    final double totalMin = principal + expectedMin;
    final double totalMax = principal + expectedMax;

    final int durationDays = (inv['durationDays'] as num?)?.toInt() ?? 0;
    final DateTime? start =
        _parseDate(inv['activatedAt']) ?? _parseDate(inv['createdAt']);
    final DateTime? maturity = start?.add(Duration(days: durationDays));
    final int daysLeft = maturity == null
        ? 0
        : maturity.difference(DateTime.now()).inDays.clamp(0, 100000);

    final double goal = (inv['fundingGoalBdt'] as num?)?.toDouble() ?? 0.0;
    final double funded = (inv['fundedAmountBdt'] as num?)?.toDouble() ?? 0.0;
    final double progress = goal > 0 ? (funded / goal).clamp(0.0, 1.0) : 0.0;

    final double received =
        (inv['actualReturnBdt'] as num?)?.toDouble() ?? 0.0;

    return {
      'principal': principal,
      'expectedMin': expectedMin,
      'expectedMax': expectedMax,
      'totalMin': totalMin,
      'totalMax': totalMax,
      'durationDays': durationDays,
      'start': start,
      'maturity': maturity,
      'daysLeft': daysLeft,
      'progress': progress,
      'received': received,
    };
  }

  bool _countsAsInvested(String status) =>
      status == 'ACTIVE' || status == 'MATURED' || status == 'COMPLETED';

  // ═════════════════════════════════════════════════════════
  // DATA
  // ═════════════════════════════════════════════════════════
  Future<void> _loadInvestmentsData() async {
    setState(() => _isLoading = true);

    var userData = await AuthService.getUserData();

    if (userData == null ||
        (userData['id'] == null && userData['email'] == null)) {
      final conn = await DatabaseService.getConnection();
      if (conn != null) {
        final res = await conn.execute(
            'SELECT "id", "name", "email", "phone" FROM users ORDER BY "createdAt" DESC LIMIT 1');
        if (res.isNotEmpty) {
          userData = {
            'id': res.first[0].toString(),
            'name': res.first[1].toString(),
            'email': res.first[2].toString(),
            'phone': res.first[3]?.toString() ?? '',
          };
          await AuthService.saveUserData(userData);
        }
      }
    }

    final userId = userData?['id']?.toString() ?? '';
    final userEmail = userData?['email']?.toString() ?? '';

    final pData =
    await DatabaseService.getPortfolioData(userId, email: userEmail);

    if (mounted) {
      setState(() {
        _user = userData;
        if (pData.isNotEmpty) {
          _investments =
          (pData['investments'] as List<Map<String, dynamic>>? ?? []);
          _bankAccounts =
          (pData['bankAccounts'] as List<Map<String, dynamic>>? ?? []);

          double invested = 0, expMin = 0, expMax = 0, actual = 0;
          for (final inv in _investments) {
            final c = _calc(inv);
            if (_countsAsInvested(inv['status']?.toString() ?? '')) {
              invested += c['principal'] as double;
              expMin += c['expectedMin'] as double;
              expMax += c['expectedMax'] as double;
            }
            actual += c['received'] as double;
          }
          _totalInvested = invested;
          _totalExpectedMin = expMin;
          _totalExpectedMax = expMax;
          _totalActual = actual;
        }
        _isLoading = false;
      });
    }
  }

  String _fmtBdt(double amount) {
    return '৳${amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
    )}';
  }

  String _formatBdtFull(double amount) {
    return 'BDT ${amount.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
    )}';
  }

  String _fmtRange(double min, double max) =>
      '${_fmtBdt(min)} – ${_fmtBdt(max)}';

  String _fmtRangeFull(double min, double max) =>
      '${_formatBdtFull(min)} – ${_formatBdtFull(max)}';

  String _certNo(Map<String, dynamic> inv) {
    final id = inv['id']?.toString() ?? '';
    return 'BC-${id.substring(0, id.length >= 12 ? 12 : id.length).toUpperCase()}';
  }

  List<Map<String, dynamic>> get _filteredInvestments {
    switch (_selectedStatusFilter) {
      case 'ACTIVE':
        return _investments.where((i) => i['status'] == 'ACTIVE').toList();
      case 'AWAITING_PAYMENT':
        return _investments
            .where((i) => i['status'] == 'PAYMENT_PENDING')
            .toList();
      case 'DRAFT':
        return _investments.where((i) => i['status'] == 'PENDING').toList();
      case 'COMPLETED':
        return _investments
            .where((i) =>
        i['status'] == 'COMPLETED' || i['status'] == 'MATURED')
            .toList();
      case 'CANCELLED':
        return _investments
            .where((i) => i['status'] == 'CANCELLED')
            .toList();
      default:
        return _investments;
    }
  }

  // ═════════════════════════════════════════════════════════
  // CERTIFICATE
  // ═════════════════════════════════════════════════════════
  void _openCertificateViewer(Map<String, dynamic> inv) {
    final c = _calc(inv);
    final String certNo = _certNo(inv);
    final String issuedDate = _fmtDate(_parseDate(inv['createdAt']));
    final String status = inv['status']?.toString() ?? 'CONFIRMED';

    final double amtInvested = c['principal'] as double;
    final double expMin = c['expectedMin'] as double;
    final double expMax = c['expectedMax'] as double;
    final double totMin = c['totalMin'] as double;
    final double totMax = c['totalMax'] as double;

    final String name = _user?['name']?.toString() ?? 'Investor';
    final String email = _user?['email']?.toString() ?? '—';
    final String phone = (_user?['phone']?.toString().isNotEmpty ?? false)
        ? _user!['phone'].toString()
        : '—';

    final String projTitle = inv['title']?.toString() ?? 'Biniyog Project';
    final String location = inv['location']?.toString() ?? 'Bangladesh';
    final String returnType = inv['returnType']?.toString() ?? 'Profit Share';

    final String verifyUrl = 'https://biniyogclub.com/verify/$certNo';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.92,
          decoration: const BoxDecoration(
            color: ivory,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: ink),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        LanguageService.tr('Investment Certificate',
                            'ইনভেস্টমেন্ট সার্টিফিকেট'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.ios_share_rounded,
                          color: emerald),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(LanguageService.tr(
                                'Certificate link copied!',
                                'সার্টিফিকেট লিঙ্ক কপি হয়েছে!')),
                            backgroundColor: emerald,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: gold.withAlpha(110)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 6,
                          decoration: const BoxDecoration(
                            gradient:
                            LinearGradient(colors: [emerald, gold]),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              const Text(
                                'INVESTMENT CERTIFICATE',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: emeraldDeep,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'This document confirms a verified investment on the Biniyog Club platform',
                                textAlign: TextAlign.center,
                                style:
                                TextStyle(fontSize: 11.5, color: muted),
                              ),
                              const SizedBox(height: 18),

                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: ivory,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                        child: _certMeta(
                                            'CERTIFICATE NO.', certNo)),
                                    Expanded(
                                        child: _certMeta(
                                            'ISSUED DATE', issuedDate)),
                                    _statusPill(status),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Principal + expected return range
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: emeraldSoft,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  children: [
                                    _certKpi(
                                      'AMOUNT INVESTED',
                                      _formatBdtFull(amtInvested),
                                      'Principal',
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      child: Container(
                                          height: 1,
                                          color: emerald.withAlpha(35)),
                                    ),
                                    _certKpi(
                                      'EXPECTED RETURN',
                                      _fmtRangeFull(expMin, expMax),
                                      '$_rangeLabel of principal',
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              _buildCertSectionHeader('INVESTOR DETAILS'),
                              _certBlock([
                                _buildCertDetailRow('Full Name', name),
                                _buildCertDetailRow('Email Address', email),
                                _buildCertDetailRow('Phone Number', phone),
                              ]),
                              const SizedBox(height: 18),

                              _buildCertSectionHeader('PROJECT DETAILS'),
                              _certBlock([
                                _buildCertDetailRow(
                                    'Project Title', projTitle),
                                _buildCertDetailRow('Location', location),
                                _buildCertDetailRow(
                                    'Return Type', returnType),
                              ]),
                              const SizedBox(height: 18),

                              _buildCertSectionHeader('INVESTMENT TERMS'),
                              _certBlock([
                                _buildCertDetailRow(
                                    'Investment Date', issuedDate),
                                _buildCertDetailRow('Maturity Date',
                                    _fmtDate(c['maturity'] as DateTime?)),
                                _buildCertDetailRow('Principal Amount',
                                    _formatBdtFull(amtInvested)),
                                _buildCertDetailRow(
                                    'Expected Return Rate', _rangeLabel),
                                _buildCertDetailRow('Expected Return',
                                    _fmtRangeFull(expMin, expMax)),
                                _buildCertDetailRow('Total Expected Value',
                                    _fmtRangeFull(totMin, totMax)),
                              ]),
                              const SizedBox(height: 12),
                              const Text(
                                'Expected return is an estimated range and is not guaranteed. Final returns depend on actual project performance.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: muted,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 18),

                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: goldSoft,
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                  Border.all(color: gold.withAlpha(90)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'VERIFY THIS CERTIFICATE',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: goldDeep,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Scan the QR code or visit the URL below to confirm this certificate is genuine.',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: muted,
                                              height: 1.35,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            verifyUrl,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: emerald,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                        BorderRadius.circular(10),
                                        border: Border.all(color: line),
                                      ),
                                      child: QrImageView(
                                        data: verifyUrl,
                                        version: QrVersions.auto,
                                        size: 72.0,
                                        gapless: false,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),

                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: emeraldDeep,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      'Biniyog Club',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Investment Platform | Dhaka, Bangladesh',
                                      style: TextStyle(
                                        color: Colors.white.withAlpha(200),
                                        fontSize: 9.5,
                                      ),
                                    ),
                                    Text(
                                      'info@biniyogclub.com | www.biniyogclub.com',
                                      style: TextStyle(
                                        color: Colors.white.withAlpha(170),
                                        fontSize: 9,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SafeArea(
                  top: false,
                  child: FilledButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(LanguageService.tr(
                              'Downloading Certificate PDF ($certNo)...',
                              'সার্টিফিকেট পিডিএফ ডাউনলোড করা হচ্ছে...')),
                          backgroundColor: emerald,
                        ),
                      );
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: Text(LanguageService.tr(
                        'Download Certificate PDF',
                        'সার্টিফিকেট ডাউনলোড করুন')),
                    style: FilledButton.styleFrom(
                      backgroundColor: emerald,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _certMeta(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 8.5, color: muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: ink)),
      ],
    );
  }

  Widget _certKpi(String label, String value, String sub) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: muted,
                      letterSpacing: 0.4)),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: emerald)),
              ),
              Text(sub, style: const TextStyle(fontSize: 9.5, color: muted)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _certBlock(List<Widget> rows) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ivory,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i != rows.length - 1) const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }

  Widget _buildCertSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 4, height: 14, color: gold),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: emeraldDeep,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCertDetailRow(String label, String val) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: muted)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            val,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════
  // SUBMIT PROOF
  // ═════════════════════════════════════════════════════════
  void _showSubmitProofModal(Map<String, dynamic> inv) {
    final trxRefController = TextEditingController();
    final notesController = TextEditingController();
    final List<Map<String, dynamic>> projectBankAccounts =
        (inv['bankAccounts'] as List<Map<String, dynamic>>? ?? []).isNotEmpty
            ? (inv['bankAccounts'] as List<Map<String, dynamic>>)
            : _bankAccounts;

    String selectedBankId =
        projectBankAccounts.isNotEmpty ? projectBankAccounts.first['id'].toString() : '';
    bool submitting = false;
    File? selectedProofFile;
    String? proofBase64;
    final ImagePicker picker = ImagePicker();
    final c = _calc(inv);

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
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
                            LanguageService.tr('Submit Payment Proof',
                                'পেমেন্ট প্রুফ সাবমিট করুন'),
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: ink),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    Text(
                      '${inv['title']} · ${_fmtBdt(c['principal'] as double)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: emerald),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      LanguageService.tr('Select Platform Bank Account',
                          'প্ল্যাটফর্মের ব্যাংক অ্যাকাউন্ট বেছে নিন'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ink),
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
                          value: selectedBankId.isNotEmpty
                              ? selectedBankId
                              : null,
                          isExpanded: true,
                          hint: Text(LanguageService.tr(
                              'Choose Bank Account',
                              'ব্যাংক অ্যাকাউন্ট বেছে নিন')),
                          items: projectBankAccounts.map((b) {
                            return DropdownMenuItem<String>(
                              value: b['id'].toString(),
                              child: Text(
                                '${b['bankName']} (${b['accountNumber']})',
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => selectedBankId = val);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: trxRefController,
                      decoration: deco(
                        LanguageService.tr(
                            'Deposit Slip No / Transaction Ref',
                            'ডিপোজিট স্লিপ নম্বর / ট্রানজেকশন রেফ'),
                        'e.g. TRX987654321',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: deco(
                        LanguageService.tr(
                            'Notes / Depositor Name (optional)',
                            'নোটস / জমাদানকারীর নাম (ঐচ্ছিক)'),
                        'e.g. Transferred from City Bank',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      LanguageService.tr('Upload Payment Receipt / Deposit Slip',
                          'পেমেন্ট রসিদ / ডিপোজিট স্লিপ আপলোড করুন'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ink),
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
                                child: Image.file(
                                  selectedProofFile!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.cloud_upload_outlined,
                                      size: 32, color: emerald),
                                  const SizedBox(height: 6),
                                  Text(
                                    LanguageService.tr(
                                        'Tap to upload receipt image',
                                        'রসিদের ছবি আপলোড করতে ট্যাপ করুন'),
                                    style: const TextStyle(
                                        fontSize: 12, color: muted),
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
                          ScaffoldMessenger.of(context).showSnackBar(
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
                          ScaffoldMessenger.of(context).showSnackBar(
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

                        final userData =
                        await AuthService.getUserData();
                        final userId =
                            userData?['id']?.toString() ?? '';

                        final res = await DatabaseService
                            .submitManualPaymentProof(
                          investmentId: inv['id'].toString(),
                          userId: userId,
                          amountBdt: c['principal'] as double,
                          transactionRef: ref,
                          bankAccountId: selectedBankId,
                          proofFileUrl: proofBase64!,
                          notes: notesController.text.trim(),
                        );

                        if (!context.mounted) return;
                        Navigator.pop(context);

                        if (res['success'] == true) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            SnackBar(
                              content: Text(LanguageService.tr(
                                  'Payment proof submitted! Pending admin review.',
                                  'পেমেন্ট প্রুফ সাবমিট হয়েছে! এডমিন পর্যালোচনার অপেক্ষায়।')),
                              backgroundColor: emerald,
                            ),
                          );
                          _loadInvestmentsData();
                        } else {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            SnackBar(
                              content: Text(res['message'] ??
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
                        LanguageService.tr('Submit Payment Proof',
                            'পেমেন্ট প্রুফ জমা দিন'),
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

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              LanguageService.tr('Investments', 'ইনভেস্টমেন্টস'),
              style: const TextStyle(
                color: ink,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
          body: _isLoading
              ? const Center(
              child: CircularProgressIndicator(
                  color: emerald, strokeWidth: 2.4))
              : RefreshIndicator(
            onRefresh: _loadInvestmentsData,
            color: emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                Text(
                  LanguageService.tr(
                      '${_investments.length} total investments',
                      'মোট ${_investments.length} টি বিনিয়োগ'),
                  style: const TextStyle(fontSize: 13, color: muted),
                ),
                const SizedBox(height: 14),
                _buildKpiSection(),
                const SizedBox(height: 18),
                _buildStatusFilterBar(),
                const SizedBox(height: 18),
                if (_filteredInvestments.isEmpty)
                  _buildEmptyInvestmentsCard()
                else
                  ..._filteredInvestments.map((inv) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildInvestmentCard(inv),
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
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                LanguageService.tr('Total Invested', 'মোট বিনিয়োগ'),
                _fmtBdt(_totalInvested),
                Icons.account_balance_wallet_outlined,
                emerald,
                emeraldSoft,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _kpiCard(
                LanguageService.tr('Returns Received', 'প্রাপ্ত লাভ'),
                _fmtBdt(_totalActual),
                Icons.savings_outlined,
                lapis,
                lapisSoft,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Expected return range — full width
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
                child: const Icon(Icons.trending_up_rounded,
                    size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LanguageService.tr(
                          'Expected Return ($_rangeLabel)',
                          'প্রত্যাশিত লাভ ($_rangeLabel)'),
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
                        _fmtRange(_totalExpectedMin, _totalExpectedMax),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: goldDeep,
                        ),
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

  Widget _kpiCard(
      String label, String value, IconData icon, Color color, Color soft) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: color.withAlpha(200)),
          ),
        ],
      ),
    );
  }

  // ─── Filter Bar ───────────────────────────────────────────
  Widget _buildStatusFilterBar() {
    int count(bool Function(String) test) => _investments
        .where((i) => test(i['status']?.toString() ?? ''))
        .length;

    final filters = [
      ('All', 'সব', _investments.length, 'ALL'),
      ('Active', 'একটিভ', count((s) => s == 'ACTIVE'), 'ACTIVE'),
      ('Awaiting Payment', 'পেমেন্ট অপেক্ষমান',
      count((s) => s == 'PAYMENT_PENDING'), 'AWAITING_PAYMENT'),
      ('Draft', 'ড্রাফট', count((s) => s == 'PENDING'), 'DRAFT'),
      ('Completed', 'সম্পন্ন',
      count((s) => s == 'COMPLETED' || s == 'MATURED'), 'COMPLETED'),
      ('Cancelled', 'বাতিল', count((s) => s == 'CANCELLED'), 'CANCELLED'),
    ];

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final f = filters[index];
          final bool isSel = _selectedStatusFilter == f.$4;

          return GestureDetector(
            onTap: () => setState(() => _selectedStatusFilter = f.$4),
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
                    LanguageService.tr(f.$1, f.$2),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      color: isSel ? Colors.white : ink,
                    ),
                  ),
                  if (f.$3 > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSel ? gold : ivory,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${f.$3}',
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

  // ─── Status helpers ───────────────────────────────────────
  String _statusText(String st) {
    switch (st) {
      case 'ACTIVE':
        return LanguageService.tr('Active', 'একটিভ');
      case 'PAYMENT_PENDING':
        return LanguageService.tr('Awaiting Payment', 'পেমেন্ট অপেক্ষমান');
      case 'COMPLETED':
      case 'MATURED':
        return LanguageService.tr('Completed', 'সম্পন্ন');
      case 'CANCELLED':
        return LanguageService.tr('Cancelled', 'বাতিল');
      case 'CONFIRMED':
        return LanguageService.tr('Confirmed', 'নিশ্চিত');
      default:
        return LanguageService.tr('Draft', 'ড্রাফট');
    }
  }

  Color _statusColor(String st) {
    switch (st) {
      case 'ACTIVE':
      case 'CONFIRMED':
        return emerald;
      case 'PAYMENT_PENDING':
        return goldDeep;
      case 'COMPLETED':
      case 'MATURED':
        return lapis;
      case 'CANCELLED':
        return danger;
      default:
        return terracotta;
    }
  }

  Widget _statusPill(String status) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            _statusText(status),
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: c),
          ),
        ],
      ),
    );
  }

  // ─── Investment Card ──────────────────────────────────────
  Widget _buildInvestmentCard(Map<String, dynamic> inv) {
    final c = _calc(inv);
    final String status = inv['status']?.toString() ?? 'PENDING';
    final String catText = categoryLabels[inv['category']] ??
        inv['category']?.toString() ??
        'SME';

    final double principal = c['principal'] as double;
    final double expMin = c['expectedMin'] as double;
    final double expMax = c['expectedMax'] as double;
    final double totMin = c['totalMin'] as double;
    final double totMax = c['totalMax'] as double;
    final double progress = c['progress'] as double;
    final double received = c['received'] as double;
    final int durationDays = c['durationDays'] as int;
    final int daysLeft = c['daysLeft'] as int;
    final DateTime? start = c['start'] as DateTime?;
    final DateTime? maturity = c['maturity'] as DateTime?;

    final latestSub = inv['latestSubmission'] as Map<String, dynamic>?;
    final String? subStatus = latestSub?['status']?.toString();
    final String? subRef = latestSub?['transactionRef']?.toString();
    final String? rejectionReason =
    latestSub?['rejectionReason']?.toString();

    final bool isAwaiting =
        status == 'PAYMENT_PENDING' || status == 'PENDING';
    final bool isActiveLike = _countsAsInvested(status);
    final bool rejected = subStatus == 'REJECTED';

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
                      Text(
                        inv['title'] as String? ?? 'Project',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$catText · ${inv['location'] ?? 'Bangladesh'}',
                        style:
                        const TextStyle(fontSize: 11.5, color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _statusPill(status),
                    const SizedBox(height: 4),
                    Text(
                      _certNo(inv),
                      style: const TextStyle(
                          fontSize: 9.5,
                          color: muted,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Return breakdown
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [emerald, emeraldDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _breakdownRow(
                  LanguageService.tr('Principal', 'মূলধন'),
                  _fmtBdt(principal),
                ),
                const SizedBox(height: 10),
                _breakdownRow(
                  LanguageService.tr('Expected return ($_rangeLabel)',
                      'প্রত্যাশিত লাভ ($_rangeLabel)'),
                  '+ ${_fmtRange(expMin, expMax)}',
                  valueColor: goldLight,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                      height: 0.8, color: Colors.white.withAlpha(40)),
                ),
                _breakdownRow(
                  LanguageService.tr('Total value', 'মোট মূল্য'),
                  _fmtRange(totMin, totMax),
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
                        LanguageService.tr(
                            'INVESTED ON', 'বিনিয়োগের তারিখ'),
                        _fmtDate(_parseDate(inv['createdAt'])),
                        isActiveLike && start != null
                            ? '${LanguageService.tr('Active', 'একটিভ')} ${_fmtDate(start)}'
                            : LanguageService.tr(
                            'Not active yet', 'এখনো একটিভ নয়'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _detailBox(
                        LanguageService.tr('MATURITY DATE', 'মেয়াদ শেষ'),
                        isActiveLike ? _fmtDate(maturity) : '—',
                        isActiveLike
                            ? LanguageService.tr('$daysLeft days left',
                            '$daysLeft দিন বাকি')
                            : LanguageService.tr('Starts after payment',
                            'পেমেন্টের পর শুরু'),
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
                        LanguageService.tr(
                            '$durationDays days', '$durationDays দিন'),
                        LanguageService.tr(
                            'Investment term', 'বিনিয়োগের মেয়াদ'),
                        accent: lapis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _detailBox(
                        LanguageService.tr('DISTRIBUTIONS', 'বিতরণ'),
                        received > 0 ? _fmtBdt(received) : '—',
                        received > 0
                            ? LanguageService.tr(
                            'Received so far', 'এ পর্যন্ত প্রাপ্ত')
                            : LanguageService.tr('None yet', 'এখনো নেই'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
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
                            LanguageService.tr(
                                'PROJECT FUNDED', 'প্রজেক্ট ফান্ডেড'),
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
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: emerald),
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
                          valueColor:
                          const AlwaysStoppedAnimation<Color>(emerald),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Payment submission status
          if (subStatus != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: rejected ? danger.withAlpha(18) : goldSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                  rejected ? danger.withAlpha(80) : gold.withAlpha(90),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        rejected
                            ? Icons.error_outline_rounded
                            : Icons.hourglass_top_rounded,
                        size: 16,
                        color: rejected ? danger : goldDeep,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        rejected
                            ? LanguageService.tr(
                            'Proof Rejected', 'প্রুফ বাতিল হয়েছে')
                            : LanguageService.tr(
                            'Under Review', 'পর্যালোচনায় আছে'),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: rejected ? danger : goldDeep,
                        ),
                      ),
                      const Spacer(),
                      if (subRef != null && subRef.isNotEmpty)
                        Text('Ref: $subRef',
                            style: const TextStyle(
                                fontSize: 10.5, color: muted)),
                    ],
                  ),
                  if (rejectionReason != null &&
                      rejectionReason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      rejectionReason,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: danger),
                    ),
                  ],
                ],
              ),
            ),

          // Footer actions
          const SizedBox(height: 12),
          const Divider(height: 1, color: line),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isAwaiting || rejected
                        ? LanguageService.tr(
                        'Submit payment proof to activate',
                        'একটিভ করতে পেমেন্ট প্রুফ দিন')
                        : LanguageService.tr(
                        'Investment certificate available',
                        'ইনভেস্টমেন্ট সার্টিফিকেট প্রস্তুত'),
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ),
                if ((isAwaiting && subStatus == null) || rejected)
                  FilledButton.icon(
                    onPressed: () => _showSubmitProofModal(inv),
                    icon: const Icon(Icons.upload_file_rounded, size: 15),
                    label: Text(
                      rejected
                          ? LanguageService.tr('Resubmit', 'পুনরায় পাঠান')
                          : LanguageService.tr('Submit Proof', 'প্রুফ দিন'),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: emerald,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  )
                else if (!isAwaiting)
                  OutlinedButton.icon(
                    onPressed: () => _openCertificateViewer(inv),
                    icon: const Icon(Icons.workspace_premium_outlined,
                        size: 15),
                    label: Text(
                      LanguageService.tr('Certificate', 'সার্টিফিকেট'),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: goldDeep,
                      side: BorderSide(color: gold.withAlpha(150)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
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

  Widget _detailBox(String label, String value, String sub,
      {Color accent = emerald}) {
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
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: accent),
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

  // ─── Empty ────────────────────────────────────────────────
  Widget _buildEmptyInvestmentsCard() {
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
            decoration: const BoxDecoration(
              color: goldSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.inventory_2_outlined,
                size: 28, color: goldDeep),
          ),
          const SizedBox(height: 14),
          Text(
            LanguageService.tr(
                'No investments found', 'কোনো বিনিয়োগ পাওয়া যায়নি'),
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: ink),
          ),
          const SizedBox(height: 4),
          Text(
            LanguageService.tr(
                'Browse open projects to make your first investment.',
                'আপনার প্রথম বিনিয়োগের জন্য প্রজেক্টসমূহ দেখুন।'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }
}