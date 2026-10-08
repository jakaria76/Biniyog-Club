import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import 'kyc_submit_page.dart';

class KycPage extends StatefulWidget {
  const KycPage({super.key});

  @override
  State<KycPage> createState() => _KycPageState();
}

class _KycPageState extends State<KycPage> {
  bool _isLoading = true;

  String _kycStatus = 'NOT_STARTED';
  String? _reviewNote;
  String _fullName = 'Mahmud Hassan';
  String _documentType = 'NATIONAL_ID';
  String _documentNumber = '19952691234567890';
  String _city = 'Gazipur';
  String _district = 'Dhaka';

  List<Map<String, String>> _uploadedDocs = [];

  static const Map<String, String> docLabels = {
    'NATIONAL_ID': 'National ID (NID)',
    'PASSPORT': 'Passport',
    'DRIVING_LICENSE': 'Driving License',
    'NID_FRONT': 'National ID (Front)',
    'NID_BACK': 'National ID (Back)',
    'NOMINEE_FRONT': 'Nominee NID (Front)',
    'NOMINEE_BACK': 'Nominee NID (Back)',
  };

  @override
  void initState() {
    super.initState();
    _loadKycData();
  }

  Future<void> _loadKycData() async {
    setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    final userEmail = userData?['email']?.toString() ?? '';

    final kycData =
        await DatabaseService.getKycStatus(userId, email: userEmail);

    if (mounted) {
      setState(() {
        if (kycData.isNotEmpty) {
          _kycStatus =
              (kycData['status']?.toString() ?? 'NOT_STARTED').toUpperCase();
          _reviewNote = kycData['reviewNote']?.toString();
          _fullName = kycData['fullName']?.toString() ?? _fullName;
          _documentType =
              kycData['documentType']?.toString() ?? _documentType;
          _documentNumber =
              kycData['documentNumber']?.toString() ?? _documentNumber;
          _city = kycData['division']?.toString() ?? _city;
          _district = kycData['district']?.toString() ?? _district;

          final rawDocs =
              kycData['documents'] as List<Map<String, dynamic>>? ?? [];
          if (rawDocs.isNotEmpty) {
            _uploadedDocs = rawDocs.map((d) {
              final type = d['type']?.toString() ?? 'NID_FRONT';
              return {
                'name': docLabels[type] ?? type,
                'status': _kycStatus == 'VERIFIED' ? 'Verified' : 'Submitted',
              };
            }).toList();
          }
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canSubmit = _kycStatus == 'NOT_STARTED' ||
        _kycStatus == 'REJECTED' ||
        _kycStatus == 'RESUBMISSION_REQUIRED';

    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F7F6),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.5,
            iconTheme: const IconThemeData(color: Colors.teal),
            title: Text(
              LanguageService.tr('KYC Verification', 'কেওয়াইসি ভেরিফিকেশন'),
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.teal))
              : RefreshIndicator(
                  onRefresh: _loadKycData,
                  color: Colors.teal,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LanguageService.tr(
                              'Identity verification is required to invest on Biniyog Club',
                              'বিনিয়োগ করার জন্য পরিচয় ভেরিফিকেশন সম্পন্ন করা আবশ্যক'),
                          style:
                              TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 16),

                        // 1. Status Card
                        _buildStatusCard(),
                        const SizedBox(height: 20),

                        // Action Button
                        if (canSubmit) ...[
                          ElevatedButton.icon(
                            onPressed: () async {
                              final result = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const KycSubmitPage(),
                                ),
                              );
                              if (result == true) {
                                _loadKycData();
                              }
                            },
                            icon: const Icon(Icons.arrow_forward_rounded,
                                size: 18),
                            label: Text(_kycStatus == 'NOT_STARTED'
                                ? LanguageService.tr(
                                    'Start Verification', 'ভেরিফিকেশন শুরু করুন')
                                : LanguageService.tr(
                                    'Resubmit Documents', 'পুনরায় কাগজ জমা দিন')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // 2. Verification Progress Steps
                        _buildProgressSteps(),
                        const SizedBox(height: 20),

                        // 3. Submitted Information Summary
                        if (_kycStatus != 'NOT_STARTED') ...[
                          _buildSubmittedInfoSummary(),
                          const SizedBox(height: 20),
                        ],

                        // 4. Uploaded Documents List
                        if (_uploadedDocs.isNotEmpty) ...[
                          _buildUploadedDocumentsList(),
                          const SizedBox(height: 20),
                        ],
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  // Status Badge Card
  Widget _buildStatusCard() {
    Color bg;
    Color border;
    IconData icon;
    String title;
    String desc;

    if (_kycStatus == 'VERIFIED' || _kycStatus == 'APPROVED') {
      bg = Colors.green.shade50;
      border = Colors.green.shade200;
      icon = Icons.check_circle_rounded;
      title = LanguageService.tr('KYC Verified', 'কেওয়াইসি ভেরিফাইড');
      desc = LanguageService.tr(
          'Your identity has been verified. You can now invest in any open project.',
          'আপনার পরিচয় সফলভাবে ভেরিফাই হয়েছে। আপনি সকল প্রজেক্টে ইনভেস্ট করতে পারবেন।');
    } else if (_kycStatus == 'SUBMITTED' || _kycStatus == 'UNDER_REVIEW') {
      bg = Colors.blue.shade50;
      border = Colors.blue.shade200;
      icon = Icons.access_time_filled_rounded;
      title = LanguageService.tr(
          'Verification Under Review', 'ভেরিফিকেশন পর্যালোচনায় আছে');
      desc = LanguageService.tr(
          'Your documents have been submitted and are under review by admin.',
          'আপনার জমা দেওয়া কাগজপত্র এডমিন প্যানেলে পর্যালোচনা করা হচ্ছে।');
    } else if (_kycStatus == 'REJECTED' ||
        _kycStatus == 'RESUBMISSION_REQUIRED') {
      bg = Colors.red.shade50;
      border = Colors.red.shade200;
      icon = Icons.error_rounded;
      title = LanguageService.tr(
          'Verification Rejected', 'ভেরিফিকেশন বাতিল হয়েছে');
      desc = _reviewNote ??
          LanguageService.tr(
              'Please resubmit valid documents for approval.',
              'অনুগ্রহ করে সঠিক কাগজপত্র পুনরায় সাবমিট করুন।');
    } else {
      bg = Colors.amber.shade50;
      border = Colors.amber.shade200;
      icon = Icons.shield_outlined;
      title = LanguageService.tr('Verification Required', 'ভেরিফিকেশন আবশ্যক');
      desc = LanguageService.tr(
          'Complete KYC verification to unlock investment features.',
          'বিনিয়োগের সুবিধা চালু করতে কেওয়াইসি ভেরিফিকেশন সম্পন্ন করুন।');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              color: _kycStatus == 'VERIFIED'
                  ? Colors.green
                  : (_kycStatus == 'REJECTED' ? Colors.red : Colors.teal),
              size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[800], height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Progress Steps
  Widget _buildProgressSteps() {
    final steps = [
      {
        'title': LanguageService.tr('1. Submit Documents', '১. কাগজপত্র জমা দিন'),
        'desc': LanguageService.tr('NID / Passport and Nominee details', 'এনআইডি ও নমিনির তথ্য'),
        'done': _kycStatus != 'NOT_STARTED',
      },
      {
        'title': LanguageService.tr('2. Admin Review', '২. এডমিন পর্যালোচনা'),
        'desc': LanguageService.tr('Admin verifies information', 'এডমিন ভেরিফাই করবে'),
        'done': _kycStatus == 'SUBMITTED' ||
            _kycStatus == 'UNDER_REVIEW' ||
            _kycStatus == 'VERIFIED',
      },
      {
        'title': LanguageService.tr('3. Verification Complete', '৩. ভেরিফিকেশন সম্পন্ন'),
        'desc': LanguageService.tr('Unlock all investment features', 'বিনিয়োগের সুবিধা চালু'),
        'done': _kycStatus == 'VERIFIED',
      },
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LanguageService.tr('Verification Process', 'ভেরিফিকেশন প্রক্রিয়া'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Column(
            children: steps.map((s) {
              final bool done = s['done'] as bool;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Icon(
                      done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: done ? Colors.green : Colors.grey[400],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s['title'] as String,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: done ? Colors.black87 : Colors.grey[600],
                            ),
                          ),
                          Text(
                            s['desc'] as String,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // Submitted Info Summary
  Widget _buildSubmittedInfoSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LanguageService.tr('Submitted Information', 'জমা দেওয়া তথ্যসমূহ'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          _buildInfoRow(LanguageService.tr('Full Name', 'পূরণকৃত নাম'), _fullName),
          _buildInfoRow(LanguageService.tr('Document Type', 'ডকুমেন্টের ধরন'), _documentType),
          _buildInfoRow(LanguageService.tr('Document ID', 'ডকুমেন্ট আইডি'), _documentNumber),
          _buildInfoRow(LanguageService.tr('Location', 'অবস্থান'), '$_city, $_district'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          Text(value,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // Uploaded Documents List
  Widget _buildUploadedDocumentsList() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LanguageService.tr('Uploaded Documents', 'আপলোড করা কাগজপত্র'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Column(
            children: _uploadedDocs.map((doc) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined,
                        color: Colors.teal, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        doc['name']!,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      doc['status']!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: doc['status'] == 'Verified'
                            ? Colors.green
                            : Colors.blue,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
