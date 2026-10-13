import 'package:flutter/material.dart';
import '../../../services/language_service.dart';

class TermsAndConditionsPage extends StatelessWidget {
  const TermsAndConditionsPage({super.key});

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
              LanguageService.tr('Terms & Conditions', 'ব্যবহারের শর্তাবলী'),
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
                    LanguageService.tr('Terms of Service', 'ব্যবহারের শর্তাবলী'),
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
                    '1. Acceptance of Terms',
                    '১. শর্তাবলী মেনে নেওয়া',
                    'By accessing or using the Biniyog Club platform ("Platform"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree, you may not use the Platform. These Terms constitute a legally binding agreement between you and Biniyog Club Ltd., a company registered in Bangladesh.',
                    'বিনিয়োগ ক্লাব প্ল্যাটফর্মটি ব্যবহারের মাধ্যমে আপনি আমাদের সকল শর্তাবলী মেনে নিতে সম্মত হচ্ছেন। আপনি সম্মত না হলে প্ল্যাটফর্মটি ব্যবহার করতে পারবেন না। এই শর্তাবলী আপনার এবং বিনিয়োগ ক্লাব লিমিটেডের মধ্যে একটি আইনগত চুক্তি।',
                  ),
                  _buildSection(
                    '2. Eligibility',
                    '২. যোগ্যতা',
                    'You must be at least 18 years of age and a Bangladeshi citizen or Non-Resident Bangladeshi (NRB) to use the Platform. By registering, you represent and warrant that you meet these requirements and that all information you provide is accurate and complete.',
                    'প্ল্যাটফর্মটি ব্যবহারের জন্য আপনার বয়স সর্বনিম্ন ১৮ বছর হতে হবে এবং আপনাকে বাংলাদেশের নাগরিক বা প্রবাসী বাংলাদেশী (NRB) হতে হবে। নিবন্ধন করার মাধ্যমে আপনি নিশ্চিত করছেন যে প্রদানকৃত সকল তথ্য সঠিক ও সত্য।',
                  ),
                  _buildSection(
                    '3. Account Registration & KYC',
                    '৩. অ্যাকাউন্ট নিবন্ধন ও কেওয়াইসি',
                    'You are responsible for maintaining the confidentiality of your account credentials. You must complete KYC verification before making any investment. Providing false information during KYC is grounds for immediate account termination.',
                    'আপনার অ্যাকাউন্টের গোপনীয়তা রক্ষার দায়িত্ব আপনার। যেকোনো প্রজেক্টে বিনিয়োগ করার পূর্বে আপনাকে কেওয়াইসি (KYC) ভেরিফিকেশন সম্পন্ন করতে হবে। ভুল তথ্য প্রদান করা হলে অ্যাকাউন্ট বাতিল বলে গণ্য হবে।',
                  ),
                  _buildSection(
                    '4. Investment Terms & Contracts',
                    '৪. বিনিয়োগ শর্ত ও চুক্তিপত্র',
                    'All investments are subject to the specific terms disclosed on each project page. Investment contracts are legally binding once signed digitally by both parties. Biniyog Club acts as a marketplace facilitator. Past performance of projects does not guarantee future results.',
                    'সকল বিনিয়োগ প্রতিটি প্রজেক্ট পেজে প্রদর্শিত শর্তাবলীর ওপর নির্ভরশীল। ডিজিটাল চুক্তি স্বাক্ষরের পর বিনিয়োগ চুক্তিটি আইনগতভাবে কার্যকরী হয়। বিনিয়োগ ক্লাব একটি ডিজিটাল প্ল্যাটফর্ম হিসেবে কাজ করে। পূর্বের লাভ ভবিষ্যতে কোনো নিশ্চয়তা দেয় না।',
                  ),
                  _buildSection(
                    '5. Platform Fees',
                    '৫. প্ল্যাটফর্ম ফি',
                    'Biniyog Club charges a transparent platform fee on investment returns. The applicable fee percentage is disclosed on each project page before investment. No fees are charged on your principal investment amount.',
                    'বিনিয়োগ ক্লাব প্রজেক্টের অর্জিত লভ্যাংশের ওপর একটি নির্দিষ্ট প্ল্যাটফর্ম ফি নিয়ে থাকে। আসল বিনিয়োগকৃত মূলধনের ওপর কোনো ফি প্রযোজ্য নয়। লভ্যাংশ বণ্টনের সময় স্বয়ংক্রিয়ভাবে ফি হিসাব করা হয়।',
                  ),
                  _buildSection(
                    '6. Payments & Admin Approvals',
                    '৬. লেনদেন ও এডমিন অনুমোদন',
                    'Direct bank transfers for investments require submitting payment proof. Upon verification and approval by the Biniyog Club Admin, your investment is activated and reflected in your Total Invested portfolio.',
                    'সরাসরি ব্যাংক ট্রান্সফারের মাধ্যমে বিনিয়োগ করার পর পেমেন্ট জমা স্লিপ বা রেফারেন্স সাবমিট করতে হবে। বিনিয়োগ ক্লাব এডমিন তথ্য যাচাই করে অনুমোদন দেওয়ার পর বিনিয়োগটি সক্রিয় হবে এবং আপনার মোট ইনভেস্টে যোগ হবে।',
                  ),
                  _buildSection(
                    '7. Prohibited Activities',
                    '৭. নিষিদ্ধ কর্মকাণ্ড',
                    'You may not use the Platform for money laundering, fraudulent activities, creating multiple accounts, or attempting to manipulate project funding without prior authorization.',
                    'অর্থ পাচার, জালিয়াতি, একাধিক ভুয়া অ্যাকাউন্ট খোলা বা প্রজেক্ট ফান্ডিং ম্যানিপুলেশন করার মতো কোনো অবৈধ কর্মকাণ্ডে প্ল্যাটফর্মটি ব্যবহার করা যাবে না।',
                  ),
                  _buildSection(
                    '8. Dispute Resolution & Governing Law',
                    '৮. বিরোধ নিষ্পত্তি ও আইন',
                    'These Terms are governed by the laws of the People\'s Republic of Bangladesh. Disputes shall be settled amicably or through binding arbitration in Dhaka, Bangladesh.',
                    'এই সকল শর্তাবলী গণপ্রজাতন্ত্রী বাংলাদেশের প্রচলিত আইন দ্বারা পরিচালিত হবে। যেকোনো বিরোধের ক্ষেত্রে ঢাকার এখতিয়ারভুক্ত আদালতে তা সুরাহা হবে।',
                  ),
                  _buildSection(
                    '9. Contact Information',
                    '৯. যোগাযোগ',
                    'For questions regarding these Terms, please contact us at:\n• Address: MG SAM Center, 12 Mohakhali C/A, Dhaka-1212, Bangladesh\n• Hotline: +880 1335-149033\n• Email: info@biniyogclub.com\n• Office Hours: Saturday – Thursday, 9:00 AM – 6:00 PM',
                    'শর্তাবলী সংক্রান্ত যেকোনো প্রশ্নের জন্য আমাদের সাথে যোগাযোগ করুন:\n• ঠিকানা: এমজি স্যাম সেন্টার, ১২ মহাখালী বা/এ, ঢাকা-১২১২, বাংলাদেশ\n• হটলাইন: +880 1335-149033\n• ইমেইল: info@biniyogclub.com\n• অফিস সময়: শনিবার – বৃহস্পতিবার, সকাল ৯:০০ টা – সন্ধ্যা ৬:০০ টা',
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
