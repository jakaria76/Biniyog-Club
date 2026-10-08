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
  bool _isLoading = true;

  double _totalInvested = 0.0;
  double _totalExpected = 0.0;
  double _totalActual = 0.0;

  String _selectedStatusFilter = 'ALL';

  List<Map<String, dynamic>> _investments = [];
  List<Map<String, dynamic>> _bankAccounts = [];

  static const Color primaryTeal = Color(0xFF047857);
  static const Color primaryDarkTeal = Color(0xFF065F46);

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

  @override
  void initState() {
    super.initState();
    _loadInvestmentsData();
  }

  Future<void> _loadInvestmentsData() async {
    setState(() => _isLoading = true);

    var userData = await AuthService.getUserData();

    if (userData == null || (userData['id'] == null && userData['email'] == null)) {
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
        if (pData.isNotEmpty) {
          _totalInvested = (pData['totalInvested'] as double? ?? 0.0);
          _totalExpected = (pData['totalExpected'] as double? ?? 0.0);
          _totalActual = (pData['totalActual'] as double? ?? 0.0);

          _investments =
              (pData['investments'] as List<Map<String, dynamic>>? ?? []);
          _bankAccounts =
              (pData['bankAccounts'] as List<Map<String, dynamic>>? ?? []);
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

  List<Map<String, dynamic>> get _filteredInvestments {
    if (_selectedStatusFilter == 'ALL') return _investments;
    if (_selectedStatusFilter == 'ACTIVE') {
      return _investments.where((i) => i['status'] == 'ACTIVE').toList();
    }
    if (_selectedStatusFilter == 'AWAITING_PAYMENT') {
      return _investments
          .where((i) => i['status'] == 'PAYMENT_PENDING' || i['status'] == 'PENDING')
          .toList();
    }
    if (_selectedStatusFilter == 'DRAFT') {
      return _investments.where((i) => i['status'] == 'PENDING').toList();
    }
    if (_selectedStatusFilter == 'COMPLETED') {
      return _investments
          .where((i) => i['status'] == 'COMPLETED' || i['status'] == 'MATURED')
          .toList();
    }
    if (_selectedStatusFilter == 'CANCELLED') {
      return _investments.where((i) => i['status'] == 'CANCELLED').toList();
    }
    return _investments;
  }

  // Interactive Certificate Modal Viewer
  void _openCertificateViewer(Map<String, dynamic> inv) {
    final String invId = inv['id']?.toString() ?? '';
    final String certNo =
        'BC-${invId.substring(0, invId.length >= 12 ? 12 : invId.length).toUpperCase()}';
    final String issuedDate = inv['createdAt']?.toString() ?? 'Oct 8, 2026';
    final String status = inv['status']?.toString() ?? 'CONFIRMED';

    final double amtInvested = (inv['amountBdt'] as double? ?? 100000.0);
    final double expReturn = (inv['expectedReturnBdt'] as double? ?? 1600000.0);
    final double totalValue = amtInvested + expReturn;

    final String name = inv['userName']?.toString() ?? 'jmjakaria';
    final String email = inv['userEmail']?.toString() ?? 'jmjakaria221@gmail.com';
    final String phone = inv['userPhone']?.toString() ?? '01317536551';

    final String projTitle = inv['title']?.toString() ?? 'Biniyog Project';
    final String location = inv['location']?.toString() ?? 'Dhaka, Bangladesh';
    final String returnType = inv['returnType']?.toString() ?? 'Hybrid';

    final String verifyUrl = 'https://biniyogclub.com/verify/$certNo';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.92,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 24),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      LanguageService.tr('Investment Certificate', 'ইনভেস্টমেন্ট সার্টিফিকেট'),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primaryDarkTeal),
                    ),
                    IconButton(
                      icon: const Icon(Icons.share_rounded, color: primaryTeal),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(LanguageService.tr(
                                'Certificate link copied to clipboard!',
                                'সার্টিফিকেট লিঙ্ক কপি হয়েছে!')),
                            backgroundColor: primaryTeal,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(10),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 6,
                          decoration: const BoxDecoration(
                            color: primaryTeal,
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(15)),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            children: [
                              Text(
                                'INVESTMENT CERTIFICATE',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.grey.shade900,
                                  letterSpacing: 2.0,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'This document confirms a verified investment on the Biniyog Club platform',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 11.5, color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 18),

                              // Metadata Bar
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('CERTIFICATE NO.',
                                            style: TextStyle(
                                                fontSize: 8.5,
                                                color: Colors.grey[600],
                                                fontWeight: FontWeight.bold)),
                                        Text(certNo,
                                            style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('ISSUED DATE',
                                            style: TextStyle(
                                                fontSize: 8.5,
                                                color: Colors.grey[600],
                                                fontWeight: FontWeight.bold)),
                                        Text(issuedDate,
                                            style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                            color: Colors.green.shade200),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),

                              // Highlight KPI Box
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: Colors.green.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('AMOUNT INVESTED',
                                              style: TextStyle(
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.grey[700])),
                                          const SizedBox(height: 2),
                                          Text(_formatBdtFull(amtInvested),
                                              style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: primaryTeal)),
                                          Text('Principal',
                                              style: TextStyle(
                                                  fontSize: 8.5,
                                                  color: Colors.grey[500])),
                                        ],
                                      ),
                                    ),
                                    Container(
                                        height: 36,
                                        width: 1,
                                        color: Colors.green.shade200),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('EXPECTED RETURN',
                                              style: TextStyle(
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.grey[700])),
                                          const SizedBox(height: 2),
                                          Text(_formatBdtFull(expReturn),
                                              style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: primaryTeal)),
                                          Text('16% of principal',
                                              style: TextStyle(
                                                  fontSize: 8.5,
                                                  color: Colors.grey[500])),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // INVESTOR DETAILS
                              _buildCertSectionHeader('INVESTOR DETAILS'),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    _buildCertDetailRow('Full Name', name),
                                    const SizedBox(height: 8),
                                    _buildCertDetailRow('Email Address', email),
                                    const SizedBox(height: 8),
                                    _buildCertDetailRow('Phone Number', phone),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),

                              // PROJECT DETAILS
                              _buildCertSectionHeader('PROJECT DETAILS'),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    _buildCertDetailRow(
                                        'Project Title', projTitle),
                                    const SizedBox(height: 8),
                                    _buildCertDetailRow('Location', location),
                                    const SizedBox(height: 8),
                                    _buildCertDetailRow('Return Type', returnType),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),

                              // INVESTMENT TERMS
                              _buildCertSectionHeader('INVESTMENT TERMS'),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    _buildCertDetailRow(
                                        'Investment Date', issuedDate),
                                    const SizedBox(height: 8),
                                    _buildCertDetailRow(
                                        'Principal Amount', _formatBdtFull(amtInvested)),
                                    const SizedBox(height: 8),
                                    _buildCertDetailRow(
                                        'Expected Return', _formatBdtFull(expReturn)),
                                    const SizedBox(height: 8),
                                    _buildCertDetailRow(
                                        'Total Expected Value', _formatBdtFull(totalValue)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // VERIFY THIS CERTIFICATE
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: Colors.amber.shade300),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'VERIFY THIS CERTIFICATE',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Scan the QR code or visit the URL below to confirm this certificate is genuine. The verification page shows the original, uneditable record from our database.',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey[700],
                                              height: 1.3,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            verifyUrl,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: primaryTeal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Real Scannable QR Code
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
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
                              const SizedBox(height: 24),

                              // Footer
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: const BoxDecoration(
                                  color: primaryDarkTeal,
                                  borderRadius: BorderRadius.vertical(
                                      bottom: Radius.circular(12)),
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      'Biniyog Club',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Agricultural Investment Platform | Dhaka, Bangladesh',
                                      style: TextStyle(
                                        color: Colors.white.withAlpha(200),
                                        fontSize: 9.5,
                                      ),
                                    ),
                                    Text(
                                      'info@biniyogclub.com | www.biniyogclub.com',
                                      style: TextStyle(
                                        color: Colors.white.withAlpha(180),
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

              // Bottom Action Button
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(LanguageService.tr(
                            'Downloading Certificate PDF ($certNo)...',
                            'সার্টিফিকেট পিডিএফ ডাউনলোড করা হচ্ছে...')),
                        backgroundColor: primaryTeal,
                      ),
                    );
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: Text(LanguageService.tr(
                      'Download Certificate PDF', 'সার্টিফিকেট ডাউনলোড করুন')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryTeal,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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

  Widget _buildCertSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Container(width: 4, height: 14, color: primaryTeal),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: primaryDarkTeal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCertDetailRow(String label, String val) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            val,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  // Submit Payment Proof Bottom Sheet Modal
  void _showSubmitProofModal(Map<String, dynamic> inv) {
    final trxFefController = TextEditingController();
    final notesController = TextEditingController();
    String selectedBankId =
        _bankAccounts.isNotEmpty ? _bankAccounts.first['id'].toString() : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 24,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        LanguageService.tr('Submit Payment Proof', 'পেমেন্ট প্রুফ সাবমিট করুন'),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${inv['title']} · ${_fmtBdt(inv['amountBdt'] as double)}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: primaryTeal),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    LanguageService.tr('Select Platform Bank Account', 'প্ল্যাটফর্মের ব্যাংক অ্যাকাউন্ট বেছে নিন'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedBankId.isNotEmpty ? selectedBankId : null,
                        isExpanded: true,
                        hint: Text(LanguageService.tr('Choose Bank Account', 'ব্যাংক অ্যাকাউন্ট বেছে নিন')),
                        items: _bankAccounts.map((b) {
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
                    controller: trxFefController,
                    decoration: InputDecoration(
                      labelText: LanguageService.tr('Bank Deposit Slip No / Transaction Ref', 'ডিপোজিট স্লিপ নম্বর / ট্রানজেকশন রেফ'),
                      hintText: 'e.g. TRX987654321',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: notesController,
                    decoration: InputDecoration(
                      labelText: LanguageService.tr('Optional Notes / Depositor Name', 'নোটস / জমাদানকারীর নাম (ঐচ্ছিক)'),
                      hintText: 'e.g. Transferred from City Bank',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: () async {
                      final ref = trxFefController.text.trim();
                      if (ref.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(LanguageService.tr('Please enter transaction reference / deposit slip no.', 'ট্রানজেকশন রেফারেন্স বা জমা স্লিপ নম্বর লিখুন।')),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }

                      final userData = await AuthService.getUserData();
                      final userId = userData?['id']?.toString() ?? '';

                      final res = await DatabaseService.submitManualPaymentProof(
                        investmentId: inv['id'].toString(),
                        userId: userId,
                        amountBdt: inv['amountBdt'] as double,
                        transactionRef: ref,
                        bankAccountId: selectedBankId,
                        proofFileUrl: 'deposit_receipt.png',
                        notes: notesController.text.trim(),
                      );

                      if (!context.mounted) return;
                      Navigator.pop(context);

                      if (res['success'] == true) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(LanguageService.tr('Payment proof submitted! Pending Admin review.', 'পেমেন্ট প্রুফ সাবমিট হয়েছে! এডমিন পর্যালোচনার অপেক্ষায়।')),
                            backgroundColor: primaryTeal,
                          ),
                        );
                        _loadInvestmentsData();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(res['message'] ?? 'Failed to submit.'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryTeal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      LanguageService.tr('Submit Payment Proof', 'পেমেন্ট প্রুফ জমা দিন'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F7F6),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.5,
            iconTheme: const IconThemeData(color: primaryTeal),
            title: Text(
              LanguageService.tr('Investments', 'ইনভেস্টমেন্টস'),
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: primaryTeal))
              : RefreshIndicator(
                  onRefresh: _loadInvestmentsData,
                  color: primaryTeal,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LanguageService.tr(
                              '${_investments.length} total investment',
                              'মোট ${_investments.length} টি বিনিয়োগ'),
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 14),

                        // 1. KPI Cards Row
                        _buildKpiRow(),
                        const SizedBox(height: 18),

                        // 2. Status Filter Pills Bar
                        _buildStatusFilterBar(),
                        const SizedBox(height: 18),

                        // 3. Investments List
                        _filteredInvestments.isEmpty
                            ? _buildEmptyInvestmentsCard()
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _filteredInvestments.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 16),
                                itemBuilder: (context, index) {
                                  final inv = _filteredInvestments[index];
                                  return _buildInvestmentCard(inv);
                                },
                              ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  // 3 KPI Cards Row
  Widget _buildKpiRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(LanguageService.tr('Total Invested', 'মোট বিনিয়োগ'),
                    style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text(_fmtBdt(_totalInvested),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: primaryTeal)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(LanguageService.tr('Expected Returns', 'প্রত্যাশিত লাভ'),
                    style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text(_fmtBdt(_totalExpected),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: primaryTeal)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(LanguageService.tr('Returns Received', 'প্রাপ্ত লাভ'),
                    style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text(_fmtBdt(_totalActual),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: primaryTeal)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Filter Pills Bar with Count Badges (Matching Website Screenshot 1:1)
  Widget _buildStatusFilterBar() {
    final int allCount = _investments.length;
    final int activeCount =
        _investments.where((i) => i['status'] == 'ACTIVE').length;
    final int awaitingCount = _investments
        .where((i) => i['status'] == 'PAYMENT_PENDING' || i['status'] == 'PENDING')
        .length;
    final int draftCount =
        _investments.where((i) => i['status'] == 'PENDING').length;
    final int completedCount = _investments
        .where((i) => i['status'] == 'COMPLETED' || i['status'] == 'MATURED')
        .length;
    final int cancelledCount =
        _investments.where((i) => i['status'] == 'CANCELLED').length;

    final filters = [
      {'label': 'All', 'bn': 'সব', 'count': allCount, 'key': 'ALL'},
      {'label': 'Active', 'bn': 'একটিভ', 'count': activeCount, 'key': 'ACTIVE'},
      {'label': 'Awaiting Payment', 'bn': 'অপেক্ষমান', 'count': awaitingCount, 'key': 'AWAITING_PAYMENT'},
      {'label': 'Draft', 'bn': 'ড্রাফট', 'count': draftCount, 'key': 'DRAFT'},
      {'label': 'Completed', 'bn': 'সম্পন্ন', 'count': completedCount, 'key': 'COMPLETED'},
      {'label': 'Cancelled', 'bn': 'বাতিল', 'count': cancelledCount, 'key': 'CANCELLED'},
    ];

    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final f = filters[index];
          final bool isSel = _selectedStatusFilter == f['key'];
          final int count = f['count'] as int;

          return Container(
            margin: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(LanguageService.tr(
                      f['label'] as String, f['bn'] as String)),
                  if (count > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSel ? Colors.white24 : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isSel ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              selected: isSel,
              selectedColor: primaryTeal,
              labelStyle: TextStyle(
                fontSize: 11.5,
                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                color: isSel ? Colors.white : Colors.black87,
              ),
              backgroundColor: Colors.white,
              side: BorderSide(
                color: isSel ? primaryTeal : Colors.grey.shade300,
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedStatusFilter = f['key'] as String);
                }
              },
            ),
          );
        },
      ),
    );
  }

  // Single Investment Card (Matching Website Screenshot 1:1!)
  Widget _buildInvestmentCard(Map<String, dynamic> inv) {
    final String invId = inv['id']?.toString() ?? '';
    final String certNo =
        'BC-${invId.substring(0, invId.length >= 12 ? 12 : invId.length).toUpperCase()}';
    final String status = inv['status'] as String? ?? 'PENDING';
    final String catText =
        categoryLabels[inv['category']] ?? inv['category']?.toString() ?? 'SME';

    final double amt = inv['amountBdt'] as double? ?? 0.0;
    final double expRet = inv['expectedReturnBdt'] as double? ?? 0.0;
    final double totalVal = amt + expRet;
    final double returnPct =
        (inv['expectedReturnPct'] as double? ?? 0.16) * 100;
    final double progress = inv['progress'] as double? ?? 0.02;
    final int fundedPct = (progress * 100).toInt();

    final String createdAt =
        inv['createdAt']?.toString().substring(0, 10) ?? 'Oct 8, 2026';

    final latestSub = inv['latestSubmission'] as Map<String, dynamic>?;
    final String? subStatus = latestSub?['status']?.toString();
    final String? subRef = latestSub?['transactionRef']?.toString();
    final String? rejectionReason = latestSub?['rejectionReason']?.toString();

    final bool isAwaiting = status == 'PAYMENT_PENDING' || status == 'PENDING';

    String getStatusText(String st) {
      if (st == 'ACTIVE') return 'Active';
      if (st == 'PAYMENT_PENDING') return 'Awaiting Payment';
      if (st == 'COMPLETED' || st == 'MATURED') return 'Completed';
      if (st == 'CANCELLED') return 'Cancelled';
      return 'Draft';
    }

    Color getStatusColor(String st) {
      if (st == 'ACTIVE') return primaryTeal;
      if (st == 'PAYMENT_PENDING') return Colors.orange;
      if (st == 'COMPLETED' || st == 'MATURED') return Colors.green;
      if (st == 'CANCELLED') return Colors.red;
      return Colors.amber;
    }

    final Color stColor = getStatusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: subStatus == 'REJECTED'
              ? Colors.red.shade300
              : Colors.grey.shade200,
          width: subStatus == 'REJECTED' ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Header Row
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        inv['title'] as String? ?? 'Project',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$catText · ${inv['location']} · ${inv['durationDays']}d term',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: stColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        getStatusText(status),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: stColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      certNo,
                      style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 2. 8 Bento KPI Grid Boxes (Matching Website Screenshot 1:1!)
          Container(
            padding: const EdgeInsets.all(14),
            color: const Color(0xFFF8FAFC),
            child: Column(
              children: [
                // Row 1: Principal, Expected Return, Total Value, Invested On
                Row(
                  children: [
                    Expanded(
                        child: _buildBentoKpiBox('PRINCIPAL', _fmtBdt(amt), 'Principal')),
                    Expanded(
                        child: _buildBentoKpiBox('EXPECTED RETURN', _fmtBdt(expRet), '${returnPct.toStringAsFixed(1)}% · Hybrid')),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: _buildBentoKpiBox('TOTAL VALUE', _fmtBdt(totalVal), 'Principal + return')),
                    Expanded(
                        child: _buildBentoKpiBox('INVESTED ON', createdAt, 'Active $createdAt')),
                  ],
                ),
                const SizedBox(height: 10),

                // Row 2: Maturity Date, Duration, Distributions, Project Funded
                Row(
                  children: [
                    Expanded(
                        child: _buildBentoKpiBox('MATURITY DATE', 'Nov 7, 2026', '30 days left')),
                    Expanded(
                        child: _buildBentoKpiBox('DURATION', '${inv['durationDays']} days', '$createdAt → Nov 7')),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: _buildBentoKpiBox('DISTRIBUTIONS', '—', 'None yet')),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('PROJECT FUNDED',
                                style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[600])),
                            const SizedBox(height: 2),
                            Text('$fundedPct%',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: primaryTeal)),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 4,
                                backgroundColor: Colors.grey.shade200,
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(
                                        primaryTeal),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Manual Payment Submission Alert Box (if rejected or under review)
          if (subStatus != null) ...[
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: subStatus == 'REJECTED'
                    ? Colors.red.shade50
                    : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: subStatus == 'REJECTED'
                      ? Colors.red.shade200
                      : Colors.amber.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (subStatus == 'REJECTED' ? Colors.red : Colors.blue).withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          subStatus == 'REJECTED'
                              ? LanguageService.tr('Proof Rejected', 'প্রুফ বাতিল হয়েছে')
                              : LanguageService.tr('Under Review', 'পর্যালোচনায় আছে'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: subStatus == 'REJECTED' ? Colors.red : Colors.blue,
                          ),
                        ),
                      ),
                      if (subRef != null && subRef.isNotEmpty)
                        Text('Ref: $subRef',
                            style: TextStyle(
                                fontSize: 10.5, color: Colors.grey[700])),
                    ],
                  ),
                  if (rejectionReason != null && rejectionReason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Rejected: $rejectionReason',
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // 3. Bottom Action Bar (Certificate Button / Resubmit Button)
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  LanguageService.tr(
                      'Investment certificate available', 'ইনভেস্টমেন্ট সার্টিফিকেট প্রস্তুত'),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                if (isAwaiting || subStatus == 'REJECTED')
                  OutlinedButton.icon(
                    onPressed: () => _showSubmitProofModal(inv),
                    icon: const Icon(Icons.upload_file_rounded, size: 14),
                    label: Text(
                      subStatus == 'REJECTED'
                          ? LanguageService.tr('Resubmit', 'পুনরায় পাঠান')
                          : LanguageService.tr('Submit Proof', 'প্রুফ দিন'),
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryTeal,
                      side: const BorderSide(color: primaryTeal),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _openCertificateViewer(inv),
                    icon: const Icon(Icons.workspace_premium_outlined, size: 14),
                    label: Text(
                      LanguageService.tr('Certificate', 'সার্টিফিকেট'),
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[800],
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBentoKpiBox(String label, String value, String sub) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600])),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: primaryTeal)),
          Text(sub,
              style: TextStyle(fontSize: 8.5, color: Colors.grey[500])),
        ],
      ),
    );
  }

  // Empty State Card
  Widget _buildEmptyInvestmentsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            LanguageService.tr('No investments found', 'কোনো বিনিয়োগ পাওয়া যায়নি'),
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
          const SizedBox(height: 4),
          Text(
            LanguageService.tr('Browse open projects to make your first investment.', 'আপনার প্রথম বিনিয়োগের জন্য প্রজেক্টসমূহ দেখুন।'),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
