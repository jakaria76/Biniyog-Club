import 'package:flutter/material.dart';
import '../../../services/language_service.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const Color primaryTeal = Color(0xFF047857);

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
              LanguageService.tr('Privacy Policy', 'প্রাইভেসী পলিসি'),
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(18.0),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(5),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LanguageService.tr('Privacy Policy', 'গোপনীয়তা নীতি'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: primaryTeal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    LanguageService.tr(
                        'Last updated: January 1, 2025 · Biniyog Club Ltd.',
                        'সর্বশেষ সংস্করণ: ১ জানুয়ারি, ২০২৫ · বিনিয়োগ ক্লাব লিমিটেড'),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 16),

                  _buildSection(
                    '1. Introduction',
                    '১. সূচনা',
                    'Biniyog Club Ltd. ("Biniyog Club", "we", "us", or "our") is committed to protecting your personal information. This Privacy Policy explains how we collect, use, disclose, and safeguard your data when you use our platform at biniyog.club and related mobile applications.',
                    'বিনিয়োগ ক্লাব লিমিটেড আপনার ব্যক্তিগত তথ্যের নিরাপত্তা সুরক্ষায় প্রতিশ্রুতিবদ্ধ। আপনি যখন আমাদের ওয়েবসাইট বা মোবাইল অ্যাপ ব্যবহার করেন, তখন আমরা কীভাবে আপনার তথ্য সংগ্রহ ও সুরক্ষা করি তা এখানে ব্যাখ্যা করা হলো।',
                  ),
                  _buildSection(
                    '2. Information We Collect',
                    '২. আমরা কী কী তথ্য সংগ্রহ করি',
                    '• Identity Data: Full legal name, NID / Passport number, photograph.\n• Contact Data: Email address, phone number, postal address.\n• Financial Data: Bank account details, mobile banking numbers (bKash/Nagad), investment history.\n• Device Data: Device IP, OS version, app usage statistics.',
                    '• পরিচয় তথ্য: আইনি পূর্ণ নাম, এনআইডি / পাসপোর্ট নম্বর ও ছবি।\n• যোগাযোগের তথ্য: ইমেইল ঠিকানা, মোবাইল নম্বর ও স্থায়ী ঠিকানা।\n• আর্থিক তথ্য: ব্যাংক অ্যাকাউন্ট ডিটেইলস, বিকাশ/নগদ নম্বর ও ইনভেস্টমেন্ট হিস্ট্রি।\n• ডিভাইস তথ্য: আইপি এড্রেস, অপারেটিং সিস্টেম ও অ্যাপ ব্যবহার ড্যাশবোর্ড।',
                  ),
                  _buildSection(
                    '3. How We Use Your Information',
                    '৩. তথ্যের ব্যবহার',
                    'We use your data to verify identity under KYC regulations, process investments & returns, send transaction receipts, detect fraud, and fulfill legal requirements under Bangladesh law.',
                    'আপনার কেওয়াইসি (KYC) ভেরিফিকেশন সম্পন্ন করতে, বিনিয়োগ ও লভ্যাংশ প্রক্রিয়াকরণ করতে, সিকিউরিটি নোটিফিকেশন পাঠাতে এবং আইনগত বাধ্যবাধকতা নিশ্চিত করতে তথ্যসমূহ ব্যবহার করা হয়।',
                  ),
                  _buildSection(
                    '4. Data Sharing & Cloud Security',
                    '৪. তথ্য শেয়ারিং ও ক্লাউড সিকিউরিটি',
                    'We do not sell your personal data. Data is encrypted using AES-256 at rest and TLS 1.3 in transit. Profile photos are securely uploaded to Cloudinary servers. Bank details are strictly processed for investment payouts.',
                    'আমরা কখনোই আপনার তথ্য কারও কাছে বিক্রি করি না। তথ্যের নিরাপত্তার জন্য AES-256 এনক্রিপশন ও TLS 1.3 প্রটোকল ব্যবহার করা হয়। প্রোফাইল ছবি নিরাপদ ক্লাউডিনারিতে সংরক্ষিত থাকে।',
                  ),
                  _buildSection(
                    '5. Your Rights & Data Retention',
                    '৫. আপনার অধিকার ও সংরক্ষণ',
                    'You have the right to access, update, or request deletion of your personal profile details. Financial transaction records are retained for a minimum of 7 years in accordance with financial regulations.',
                    'আপনার তথ্যের আপডেট বা সংশোধন করার সম্পূর্ণ অধিকার আপনার রয়েছে। ব্যাংকিং ও বিনিয়োগ সংক্রান্ত নথিপত্র আইন অনুযায়ী ৭ বছর সংরক্ষণ করা হয়।',
                  ),
                  _buildSection(
                    '6. Contact Privacy Team',
                    '৬. প্রাইভেসী টিমের সাথে যোগাযোগ',
                    'For privacy inquiries, please contact us at:\n• Address: MG SAM Center, 12 Mohakhali C/A, Dhaka-1212, Bangladesh\n• Hotline: +880 1335-149033\n• Email: info@biniyogclub.com\n• Office Hours: Saturday – Thursday, 9:00 AM – 6:00 PM',
                    'প্রাইভেসী নীতি সংক্রান্ত যেকোনো প্রয়োজনে আমাদের সাথে যোগাযোগ করুন:\n• ঠিকানা: এমজি স্যাম সেন্টার, ১২ মহাখালী বা/এ, ঢাকা-১২১২, বাংলাদেশ\n• হটলাইন: +880 1335-149033\n• ইমেইল: info@biniyogclub.com\n• অফিস সময়: শনিবার – বৃহস্পতিবার, সকাল ৯:০০ টা – সন্ধ্যা ৬:০০ টা',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSection(
      String enTitle, String bnTitle, String enDesc, String bnDesc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LanguageService.tr(enTitle, bnTitle),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: primaryTeal,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            LanguageService.tr(enDesc, bnDesc),
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey[800],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
