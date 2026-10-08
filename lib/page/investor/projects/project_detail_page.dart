import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import '../portfolio/portfolio_page.dart';

class ProjectDetailPage extends StatefulWidget {
  final String projectIdOrSlug;

  const ProjectDetailPage({
    super.key,
    required this.projectIdOrSlug,
  });

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  bool _isLoading = true;
  Map<String, dynamic> _project = {};

  static const Color primaryTeal = Color(0xFF047857);
  static const Color primaryDarkTeal = Color(0xFF065F46);

  int _selectedBankIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadProjectDetail();
  }

  Future<void> _loadProjectDetail() async {
    setState(() => _isLoading = true);

    final data =
        await DatabaseService.getProjectDetail(widget.projectIdOrSlug);

    if (mounted) {
      setState(() {
        _project = data;
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
    return '৳${amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        )}';
  }

  // Direct Project Investment Action Modal (Without Wallet Balance)
  void _showInvestModal() {
    final minInv = _project['minInvestmentBdt'] as double? ?? 10000.0;
    final maxInv = _project['maxInvestmentBdt'] as double?;
    final amountController =
        TextEditingController(text: minInv.toStringAsFixed(0));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
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
                    LanguageService.tr('Invest in Project', 'প্রজেক্টে বিনিয়োগ করুন'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _project['title'] as String? ?? '',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: primaryTeal),
              ),
              const SizedBox(height: 16),

              // Amount Field
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: LanguageService.tr('Investment Amount (BDT)', 'বিনিয়োগের পরিমাণ (টাকা)'),
                  hintText: 'Enter amount',
                  prefixText: '৳ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Min: ${_formatBdtFull(minInv)}${maxInv != null && maxInv > 0 ? " · Max: ${_formatBdtFull(maxInv)}" : ""}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),

              Text(
                LanguageService.tr(
                    'Transfer funds to our project bank account and submit payment proof. Admin approval will add this directly to Total Invested.',
                    'আমাদের প্রজেক্ট ব্যাংক অ্যাকাউন্টে টাকা পাঠিয়ে পেমেন্ট প্রুফ জমা দিন। এডমিন এপ্রুভ করলে এটি সরাসরি মোট ইনভেস্টে যোগ হবে।'),
                style: TextStyle(fontSize: 11.5, color: Colors.grey[700]),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountController.text) ?? 0.0;
                  if (amount < minInv) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(LanguageService.tr(
                            'Minimum investment amount is ${_formatBdtFull(minInv)}',
                            'সর্বনিম্ন ইনভেস্টমেন্ট ${_formatBdtFull(minInv)}')),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                    return;
                  }

                  final userData = await AuthService.getUserData();
                  final userId = userData?['id']?.toString() ?? '';

                  final res = await DatabaseService.createInvestment(
                    userId: userId,
                    projectId: _project['id'].toString(),
                    amountBdt: amount,
                    useWalletBalance: false,
                  );

                  if (!context.mounted) return;
                  Navigator.pop(context);

                  if (res['success'] == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(LanguageService.tr(
                            'Investment created! Pending Admin approval.',
                            'বিনিয়োগ আবেদন তৈরি হয়েছে! এডমিন অনুমোদনের অপেক্ষায়।')),
                        backgroundColor: primaryTeal,
                      ),
                    );
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const PortfolioPage()),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(res['message'] ?? 'Failed to invest.'),
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
                  LanguageService.tr('Confirm & Create Investment', 'কনফার্ম করুন ও ইনভেস্ট করুন'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        if (_isLoading) {
          return Scaffold(
            appBar: AppBar(backgroundColor: Colors.white, elevation: 0.5),
            body: const Center(
                child: CircularProgressIndicator(color: primaryTeal)),
          );
        }

        if (_project.isEmpty) {
          return Scaffold(
            appBar: AppBar(
                backgroundColor: Colors.white,
                title: Text(LanguageService.tr('Project Details', 'প্রজেক্ট বিবরণ'))),
            body: Center(child: Text(LanguageService.tr('Project details not found.', 'প্রজেক্টের বিবরণ পাওয়া যায়নি।'))),
          );
        }

        final double goal = _project['fundingGoalBdt'] as double? ?? 1.0;
        final double minFunding = _project['fundingMinBdt'] as double? ?? 0.0;
        final double funded = _project['fundedAmountBdt'] as double? ?? 0.0;
        final double minInv = _project['minInvestmentBdt'] as double? ?? 10000.0;
        final double? maxInv = _project['maxInvestmentBdt'] as double?;
        final double remaining = _project['remainingBdt'] as double? ?? goal;
        final double progress = _project['progress'] as double? ?? 0.0;
        final int pctInt = (progress * 100).toInt();

        final returnPct = ((_project['expectedReturnPct'] as double? ?? 0.15) * 100)
            .toStringAsFixed(1);
        final daysLeft = _project['daysLeft'] as int? ?? 116;
        final durationDays = _project['durationDays'] as int? ?? 180;
        final investorsCount = _project['investorsCount'] as int? ?? 2;

        final List<String> images =
            _project['imageUrls'] as List<String>? ?? [_project['coverImageUrl']];

        final bankAccounts =
            _project['bankAccounts'] as List<Map<String, dynamic>>? ?? [];

        return Scaffold(
          backgroundColor: const Color(0xFFF4F7F6),
          appBar: AppBar(
            backgroundColor: primaryDarkTeal,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              _project['title'] as String? ?? 'Project',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Top Dark Header Banner
                _buildHeaderBanner(daysLeft),
                const SizedBox(height: 16),

                // 2. Image Gallery Carousel
                _buildImageCarousel(images),
                const SizedBox(height: 16),

                // 3. Description
                Text(
                  _project['description'] as String? ?? '',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey[800], height: 1.4),
                ),
                const SizedBox(height: 20),

                // 4. Primary Invest Widget Box
                _buildInvestNowCard(
                    funded, goal, pctInt, minInv, returnPct, durationDays, daysLeft),
                const SizedBox(height: 20),

                // 5. Financial Information
                _buildFinancialInfoBentoGrid(goal, minFunding, funded, pctInt,
                    remaining, minInv, maxInv, returnPct, durationDays, investorsCount),
                const SizedBox(height: 20),

                // 6. Timeline Card
                _buildTimelineCard(durationDays),
                const SizedBox(height: 20),

                // 7. Payment Bank Details
                if (bankAccounts.isNotEmpty) ...[
                  _buildPaymentBankDetails(bankAccounts),
                  const SizedBox(height: 20),
                ],

                // 9. FAQ Accordion
                _buildFaqSection(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  // Header Banner
  Widget _buildHeaderBanner(int daysLeft) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryDarkTeal,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Projects > ${_project['title']}',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 8),

          // Badges Row
          Wrap(
            spacing: 6,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.shade400,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  LanguageService.tr('Open for Investment', 'ইনভেস্টমেন্টের জন্য খোলা'),
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _project['category'] as String? ?? 'SME',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  LanguageService.tr('● Active', '● একটিভ'),
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Text(
            _project['title'] as String? ?? '',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),

          Row(
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 14, color: Colors.white70),
              const SizedBox(width: 4),
              Text(_project['location'] as String? ?? 'Narayanganj',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(width: 14),
              const Icon(Icons.access_time_rounded,
                  size: 14, color: Colors.amber),
              const SizedBox(width: 4),
              Text('$daysLeft ${LanguageService.tr("days left to invest", "দিন বাকি আছে")}',
                  style:
                      const TextStyle(color: Colors.amber, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  // Image Carousel
  Widget _buildImageCarousel(List<String> images) {
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        itemBuilder: (context, index) {
          return Container(
            width: 280,
            margin: const EdgeInsets.only(right: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                images[index],
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.teal.shade900,
                  child: const Center(
                    child: Icon(Icons.image_not_supported_outlined,
                        color: Colors.white54, size: 36),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Invest Now Primary Card
  Widget _buildInvestNowCard(double funded, double goal, int pctInt,
      double minInv, String returnPct, int durationDays, int daysLeft) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryTeal, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primaryTeal.withAlpha(20),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                LanguageService.tr('OPEN FOR INVESTMENT', 'বিনিয়োগের জন্য উন্মুক্ত'),
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: primaryTeal,
                    letterSpacing: 1.0),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(LanguageService.tr('Active', 'একটিভ'),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800)),
              ),
            ],
          ),
          const SizedBox(height: 6),

          Text(
            '${_formatBdt(funded)} ${LanguageService.tr("raised", "সংগৃহীত")}',
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: primaryTeal),
          ),
          const SizedBox(height: 6),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pctInt / 100,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(primaryTeal),
            ),
          ),
          const SizedBox(height: 4),
          Text('$pctInt% ${LanguageService.tr("of", "এর মধ্যে")} ${_formatBdt(goal)} ${LanguageService.tr("goal", "লক্ষ্য")}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 16),

          // 4 Grid KPIs
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 2.2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: [
              _buildMiniBox(LanguageService.tr('Min. Investment', 'সর্বনিম্ন ইনভেস্টমেন্ট'), _formatBdt(minInv)),
              _buildMiniBox(LanguageService.tr('Expected Return', 'প্রত্যাশিত লাভ'), '$returnPct%'),
              _buildMiniBox(LanguageService.tr('Duration', 'মেয়াদ'), '$durationDays ${LanguageService.tr("days", "দিন")}'),
              _buildMiniBox(LanguageService.tr('Return Type', 'রিটার্ন টাইপ'),
                  _project['returnType'] == 'PROFIT_SHARE' ? LanguageService.tr('Profit Share', 'মুনাফা শেয়ার') : LanguageService.tr('Fixed Return', 'নির্দিষ্ট রিটার্ন')),
            ],
          ),
          const SizedBox(height: 14),

          // Days Left Box
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time_rounded,
                    size: 16, color: Colors.amber.shade900),
                const SizedBox(width: 8),
                Text('$daysLeft ${LanguageService.tr("days left to invest", "দিন বাকি আছে")}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Action Button
          ElevatedButton(
            onPressed: _showInvestModal,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryTeal,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text('${LanguageService.tr("Invest Now", "এখনই ইনভেস্ট করুন")} →',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBox(String label, String val) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(val,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87)),
          Text(label,
              style: TextStyle(fontSize: 9.5, color: Colors.grey[600])),
        ],
      ),
    );
  }

  // Financial Information Bento Grid
  Widget _buildFinancialInfoBentoGrid(
      double goal,
      double minFunding,
      double funded,
      int pctInt,
      double remaining,
      double minInv,
      double? maxInv,
      String returnPct,
      int durationDays,
      int investorsCount) {
    final bentoItems = [
      {'label': LanguageService.tr('Funding Goal', 'অর্থায়নের লক্ষ্য'), 'val': _formatBdtFull(goal), 'sub': LanguageService.tr('Total target', 'মোট টার্গেট')},
      {'label': LanguageService.tr('Minimum Funding', 'সর্বনিম্ন অর্থায়ন'), 'val': _formatBdtFull(minFunding > 0 ? minFunding : goal * 0.6), 'sub': LanguageService.tr('To activate project', 'চালু করতে')},
      {'label': LanguageService.tr('Amount Raised', 'সংগৃহীত টাকা'), 'val': _formatBdtFull(funded), 'sub': '$pctInt% ${LanguageService.tr("of goal", "লক্ষ্যের")}'},
      {'label': LanguageService.tr('Remaining', 'অবশিষ্ট টাকা'), 'val': _formatBdtFull(remaining), 'sub': LanguageService.tr('Still needed', 'আরো প্রয়োজন')},
      {'label': LanguageService.tr('Min. Investment', 'সর্বনিম্ন ইনভেস্ট'), 'val': _formatBdtFull(minInv), 'sub': LanguageService.tr('Per investor', 'প্রতি জন')},
      {'label': LanguageService.tr('Max. Investment', 'সর্বোচ্চ ইনভেস্ট'), 'val': maxInv != null && maxInv > 0 ? _formatBdtFull(maxInv) : LanguageService.tr('Unlimited', 'সীমাহীন'), 'sub': LanguageService.tr('Per investor', 'প্রতি জন')},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LanguageService.tr('Financial Information', 'আর্থিক তথ্যসমূহ'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: bentoItems.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.8,
          ),
          itemBuilder: (context, index) {
            final item = bentoItems[index];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(item['label']!,
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey[600])),
                  const SizedBox(height: 2),
                  Text(item['val']!,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: primaryTeal)),
                  Text(item['sub']!,
                      style: TextStyle(
                          fontSize: 9.5, color: Colors.grey[500])),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // Timeline Card
  Widget _buildTimelineCard(int durationDays) {
    final timelineItems = [
      {'label': LanguageService.tr('Funding Deadline', 'অর্থায়নের শেষ সময়'), 'val': _project['fundingDeadline'] ?? 'January 30, 2027'},
      {'label': LanguageService.tr('Project Start Date', 'প্রজেক্ট শুরুর তারিখ'), 'val': _project['startDate'] ?? 'October 7, 2026'},
      {'label': LanguageService.tr('Expected Maturity', 'প্রত্যাশিত মেয়াদের শেষ'), 'val': _project['endDate'] ?? 'January 29, 2027'},
      {'label': LanguageService.tr('Duration', 'মোট সময়'), 'val': '$durationDays ${LanguageService.tr("days", "দিন")}'},
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
          Text(LanguageService.tr('Timeline', 'সময়সীমা'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Column(
            children: timelineItems.map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item['label']!,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                    Text(item['val']!,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }



  // Payment Bank Details
  Widget _buildPaymentBankDetails(List<Map<String, dynamic>> bankAccounts) {
    if (bankAccounts.isEmpty) return const SizedBox.shrink();

    final bank = bankAccounts[_selectedBankIndex % bankAccounts.length];

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
          Row(
            children: [
              const Icon(Icons.account_balance_rounded,
                  color: primaryTeal, size: 18),
              const SizedBox(width: 8),
              Text(
                LanguageService.tr('Payment Bank Details', 'টাকা পাঠনোর ব্যাংক তথ্য'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Details List
          _buildCopyDetailRow('Bank Name', bank['bankName'] as String),
          _buildCopyDetailRow('Account Name', bank['accountName'] as String),
          _buildCopyDetailRow(
              'Account Number', bank['accountNumber'] as String),
        ],
      ),
    );
  }

  Widget _buildCopyDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 9.5, color: Colors.grey[600])),
                Text(value,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.bold)),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.copy_rounded,
                  size: 16, color: primaryTeal),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copied $label to clipboard!'),
                    backgroundColor: primaryTeal,
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // FAQ Accordion Section
  Widget _buildFaqSection() {
    final faqs = [
      {
        'q': LanguageService.tr('When will I receive my returns?', 'আমি কখন লভ্যাংশ পাবো?'),
        'a': LanguageService.tr(
            'Returns are distributed after the project completes.',
            'প্রজেক্ট সফলভাবে মেয়াদ শেষে সম্পন্ন হলে লভ্যাংশ বণ্টন করা হয়।')
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(LanguageService.tr('Frequently Asked Questions', 'সাধারণ প্রশ্নাবলী (FAQ)'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Column(
          children: faqs.map((f) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: ExpansionTile(
                title: Text(f['q']!,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                        left: 16, right: 16, bottom: 14),
                    child: Text(f['a']!,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.4)),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
