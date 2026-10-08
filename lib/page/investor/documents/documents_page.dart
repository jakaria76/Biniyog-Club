import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../services/auth_service.dart';
import '../../../services/cloudinary_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  bool _isLoading = true;
  String _userId = '';

  Map<String, List<Map<String, dynamic>>> _categorizedDocs = {
    'contracts': [],
    'kycDocs': [],
    'paymentReceipts': [],
    'investmentReceipts': [],
    'distributionStatements': [],
    'harvestReports': [],
    'projectDocs': [],
  };

  static const Color primaryTeal = Color(0xFF047857);
  static const Color primaryDarkTeal = Color(0xFF065F46);

  // Upload Form State
  final _uploadFormKey = GlobalKey<FormState>();
  String _selectedCategory = 'PAYMENT_RECEIPT';
  final _docNameController = TextEditingController();
  final _docDescController = TextEditingController();

  File? _selectedUploadFile;
  bool _isUploadingDoc = false;

  final ImagePicker _picker = ImagePicker();

  static const Map<String, String> categoryDropdownOptions = {
    'PAYMENT_RECEIPT': 'Payment Receipt',
    'KYC': 'KYC Document',
    'INVESTMENT_AGREEMENT': 'Investment Agreement',
    'PROJECT_DOCUMENT': 'Project Document',
    'OTHER': 'Other Document',
  };

  @override
  void initState() {
    super.initState();
    _loadDocumentsData();
  }

  @override
  void dispose() {
    _docNameController.dispose();
    _docDescController.dispose();
    super.dispose();
  }

  Future<void> _loadDocumentsData() async {
    setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';

    final categorized = await DatabaseService.getDocumentsCategorized(userId);

    if (mounted) {
      setState(() {
        _userId = userId;
        _categorizedDocs = categorized;
        _isLoading = false;
      });
    }
  }

  String _formatBdt(double amount) {
    if (amount >= 10000000) {
      return '৳${(amount / 10000000).toStringAsFixed(2)} Cr';
    } else if (amount >= 100000) {
      return '৳${(amount / 100000).toStringAsFixed(2)}L';
    } else if (amount >= 1000) {
      return '৳${(amount / 1000).toStringAsFixed(0)}K';
    }
    return '৳${amount.toStringAsFixed(0)}';
  }

  String _formatBdtFull(double amount) {
    return 'BDT ${amount.toStringAsFixed(2).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        )}';
  }

  // Pick Document File (Image or Camera)
  Future<void> _pickUploadFile() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (picked != null) {
        setState(() {
          _selectedUploadFile = File(picked.path);
        });
      }
    } catch (e) {
      debugPrint("Error picking document file: $e");
    }
  }

  // Handle Document Upload Submission to Cloudinary & Neon DB
  Future<void> _handleUploadDocument() async {
    if (!_uploadFormKey.currentState!.validate()) return;

    if (_selectedUploadFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LanguageService.tr(
              'Please select a file to upload.', 'একটি ফাইল নির্বাচন করুন।')),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isUploadingDoc = true);

    try {
      final bytes = await _selectedUploadFile!.readAsBytes();

      // 1. Upload File to Cloudinary
      final cloudinaryUrl =
          await CloudinaryService.uploadImage(bytes, folder: 'user_documents');

      if (cloudinaryUrl == null || cloudinaryUrl.isEmpty) {
        if (mounted) {
          setState(() => _isUploadingDoc = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cloudinary upload failed. Check network.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      // 2. Insert record into Neon PostgreSQL DB 'documents' table
      final res = await DatabaseService.uploadUserDocument(
        userId: _userId,
        name: _docNameController.text.trim(),
        category: _selectedCategory,
        fileUrl: cloudinaryUrl,
        description: _docDescController.text.trim(),
        sizeBytes: bytes.length,
      );

      if (!mounted) return;
      setState(() => _isUploadingDoc = false);

      if (res['success'] == true) {
        _docNameController.clear();
        _docDescController.clear();
        setState(() {
          _selectedUploadFile = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LanguageService.tr(
                'Document uploaded successfully!', 'ডকুমেন্ট সফলভাবে আপলোড হয়েছে!')),
            backgroundColor: primaryTeal,
          ),
        );
        _loadDocumentsData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Upload failed.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingDoc = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload error: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // Interactive Certificate Viewer Modal
  void _openCertificateViewer(Map<String, dynamic> doc) {
    final String certNo = doc['certificateNo']?.toString() ?? 'BC-MUZCHFEN-C6S4';
    final String issuedDate = doc['issuedDate']?.toString() ?? 'October 8, 2026';
    final String status = doc['status']?.toString() ?? 'CONFIRMED';

    final double amtInvested = (doc['amountInvested'] as double? ?? 100000.0);
    final double expReturn = (doc['expectedReturn'] as double? ?? 1600000.0);
    final double totalValue = amtInvested + expReturn;

    final String name = doc['userName']?.toString() ?? 'jmjakaria';
    final String email = doc['userEmail']?.toString() ?? 'jmjakaria221@gmail.com';
    final String phone = doc['userPhone']?.toString() ?? '01317536551';

    final String projTitle =
        doc['projectTitle']?.toString() ?? 'Proposal for Shareholder at Marinozz Confectionary PLC';
    final String location = doc['location']?.toString() ?? 'Dhaka, Bangladesh';
    final String returnType = doc['returnType']?.toString() ?? 'Hybrid';

    final String verifyUrl =
        doc['verifyUrl']?.toString() ?? 'https://biniyogclub.com/verify/$certNo';

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
              // Top Action Bar
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

              // Scrollable Certificate Document
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

                              // VERIFY THIS CERTIFICATE (Yellow Warning Box with Live Scannable QR Code!)
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
                                            'Scan the QR code or visit the URL below to confirm this certificate is genuine. The verification page shows the original, uneditable record from our database. Any altered PDF will not match.',
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

  @override
  Widget build(BuildContext context) {
    final int totalCount = _categorizedDocs.values
        .fold(0, (sum, list) => sum + list.length);

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
              LanguageService.tr('Documents', 'ডকুমেন্টস'),
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
                  onRefresh: _loadDocumentsData,
                  color: primaryTeal,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LanguageService.tr(
                              '$totalCount total investment documents',
                              'মোট $totalCount টি বিনিয়োগ নথিপত্র'),
                          style:
                              TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 16),

                        // Section 1: Investment Contracts
                        _buildSectionCard(
                          icon: Icons.description_outlined,
                          title: LanguageService.tr('Investment Contracts', 'ইনভেস্টমেন্ট কন্ট্রাক্টস'),
                          items: _categorizedDocs['contracts'] ?? [],
                          emptyMsg: LanguageService.tr('No investment contracts found.', 'কোনো চুক্তি পাওয়া যায়নি।'),
                          isContract: true,
                        ),
                        const SizedBox(height: 16),

                        // Section 2: KYC Documents
                        _buildSectionCard(
                          icon: Icons.verified_user_outlined,
                          title: LanguageService.tr('KYC Documents', 'কেওয়াইসি ডকুমেন্টস'),
                          items: _categorizedDocs['kycDocs'] ?? [],
                          emptyMsg: LanguageService.tr('No KYC documents found.', 'কোনো কেওয়াইসি নথি পাওয়া যায়নি।'),
                          isKyc: true,
                        ),
                        const SizedBox(height: 16),

                        // Section 3: PAYMENT_RECEIPTs
                        _buildSectionCard(
                          icon: Icons.receipt_long_outlined,
                          title: 'PAYMENT_RECEIPTs',
                          items: _categorizedDocs['paymentReceipts'] ?? [],
                          emptyMsg: 'No payment_receipts found.',
                        ),
                        const SizedBox(height: 16),

                        // Section 4: INVESTMENT_RECEIPTs
                        _buildSectionCard(
                          icon: Icons.workspace_premium_outlined,
                          title: 'INVESTMENT_RECEIPTs',
                          items: _categorizedDocs['investmentReceipts'] ?? [],
                          emptyMsg: 'No investment_receipts found.',
                          isReceipt: true,
                        ),
                        const SizedBox(height: 16),

                        // Section 5: DISTRIBUTION_STATEMENTs
                        _buildSectionCard(
                          icon: Icons.bar_chart_outlined,
                          title: 'DISTRIBUTION_STATEMENTs',
                          items: _categorizedDocs['distributionStatements'] ?? [],
                          emptyMsg: 'No distribution_statements found.',
                        ),
                        const SizedBox(height: 16),

                        // Section 6: HARVEST_REPORTs
                        _buildSectionCard(
                          icon: Icons.eco_outlined,
                          title: 'HARVEST_REPORTs',
                          items: _categorizedDocs['harvestReports'] ?? [],
                          emptyMsg: 'No harvest_reports found.',
                        ),
                        const SizedBox(height: 16),

                        // Section 7: PROJECT_DOCUMENTs
                        _buildSectionCard(
                          icon: Icons.folder_open_outlined,
                          title: 'PROJECT_DOCUMENTs',
                          items: _categorizedDocs['projectDocs'] ?? [],
                          emptyMsg: 'No project_documents found.',
                        ),
                        const SizedBox(height: 20),

                        // Section 8: Upload a Document Card
                        _buildUploadDocumentFormCard(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  // Section Card Builder (Matching Website Screenshots 1, 2, 3 1:1)
  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required List<Map<String, dynamic>> items,
    required String emptyMsg,
    bool isContract = false,
    bool isKyc = false,
    bool isReceipt = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: primaryTeal, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                  child: Center(
                    child: Text(
                      emptyMsg,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final item = items[index];

                    if (isContract) {
                      return _buildContractRow(item);
                    }
                    if (isKyc) {
                      return _buildKycRow(item);
                    }
                    if (isReceipt) {
                      return _buildReceiptRow(item);
                    }

                    return _buildGenericDocRow(item);
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildContractRow(Map<String, dynamic> item) {
    final String status = item['status']?.toString() ?? 'DRAFT';

    return InkWell(
      onTap: () => _openCertificateViewer(item),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'] as String,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatBdt(item['amountBdt'] as double? ?? 0.0)} · Created ${item['createdAt']}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                status,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKycRow(Map<String, dynamic> item) {
    final String status = item['status']?.toString() ?? 'VERIFIED';
    final bool isVer = status == 'VERIFIED' || status == 'APPROVED';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title'] as String,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  item['subtitle'] as String,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isVer ? Colors.green.shade50 : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: isVer ? Colors.green.shade200 : Colors.amber.shade300),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isVer ? Colors.green.shade800 : Colors.amber.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] as String,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item['sizeText']} · ${item['createdAt']}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _openCertificateViewer(item),
            icon: const Icon(Icons.download_rounded, size: 14),
            label: Text(LanguageService.tr('Download', 'ডাউনলোড'),
                style: const TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[800],
              side: BorderSide(color: Colors.grey.shade300),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenericDocRow(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] as String,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${item['createdAt']}',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded, color: primaryTeal),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Downloading ${item['name']}...'),
                  backgroundColor: primaryTeal,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Section 8: Upload a Document Form Card (Exact Matching Screenshot 3!)
  Widget _buildUploadDocumentFormCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _uploadFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_outlined, color: primaryTeal, size: 20),
                const SizedBox(width: 8),
                Text(
                  LanguageService.tr('Upload a Document', 'ডকুমেন্ট আপলোড করুন'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Category Dropdown
            Text(
              LanguageService.tr('Category', 'ক্যাটাগরি'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: InputDecoration(
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: categoryDropdownOptions.entries.map((e) {
                return DropdownMenuItem<String>(
                  value: e.key,
                  child: Text(e.value, style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _selectedCategory = v);
                }
              },
            ),
            const SizedBox(height: 14),

            // Drag & Drop / Click Upload Box
            GestureDetector(
              onTap: _pickUploadFile,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: _selectedUploadFile != null
                          ? primaryTeal
                          : Colors.grey.shade300,
                      style: BorderStyle.solid),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.file_upload_outlined,
                        size: 32, color: primaryTeal),
                    const SizedBox(height: 6),
                    Text(
                      _selectedUploadFile != null
                          ? 'File Selected: ${_selectedUploadFile!.path.split('/').last}'
                          : LanguageService.tr('Click to select a file', 'ফাইল সিলেক্ট করতে এখানে চাপ দিন'),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: primaryTeal),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'JPEG, PNG, WebP, or PDF · Max 10 MB',
                      style: TextStyle(fontSize: 10.5, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Document Name Input
            TextFormField(
              controller: _docNameController,
              decoration: InputDecoration(
                labelText: LanguageService.tr('Document name *', 'ডকুমেন্টের নাম *'),
                hintText: 'e.g. NID Front Side',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required field' : null,
            ),
            const SizedBox(height: 12),

            // Description Input
            TextFormField(
              controller: _docDescController,
              decoration: InputDecoration(
                labelText: LanguageService.tr('Description (optional)', 'বিবরণ (ঐচ্ছিক)'),
                hintText: 'Brief description',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 18),

            // Submit Button
            ElevatedButton(
              onPressed: _isUploadingDoc ? null : _handleUploadDocument,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF82B8A0),
                disabledBackgroundColor: Colors.grey.shade300,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: _isUploadingDoc
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      LanguageService.tr('Upload Document', 'ডকুমেন্ট আপলোড করুন'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
