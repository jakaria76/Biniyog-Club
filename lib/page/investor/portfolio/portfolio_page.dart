import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  bool _isLoading = true;

  double _totalInvested = 0.0;
  double _totalExpected = 0.0;
  double _totalActual = 0.0;

  List<Map<String, dynamic>> _investments = [];
  final Map<String, double> _categoryAllocation = {};
  final Map<String, int> _statusDistribution = {};

  static const Color primaryTeal = Color(0xFF047857);

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
    _loadPortfolioData();
  }

  Future<void> _loadPortfolioData() async {
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

          // Calculate Category Allocations & Status Distribution
          final Map<String, double> catMap = {};
          final Map<String, int> stMap = {};

          for (final inv in _investments) {
            final cat = inv['category']?.toString() ?? 'SME';
            final amt = inv['amountBdt'] as double? ?? 0.0;
            final st = inv['status']?.toString() ?? 'PENDING';

            final catName = categoryLabels[cat] ?? cat;
            catMap[catName] = (catMap[catName] ?? 0.0) + amt;
            stMap[st] = (stMap[st] ?? 0) + 1;
          }

          _categoryAllocation.clear();
          _categoryAllocation.addAll(catMap);
          _statusDistribution.clear();
          _statusDistribution.addAll(stMap);
        }
        _isLoading = false;
      });
    }
  }

  String _fmtBdt(double amount) {
    if (amount >= 10000000) {
      return '৳${(amount / 10000000).toStringAsFixed(2)} Cr';
    } else if (amount >= 100000) {
      return '৳${(amount / 100000).toStringAsFixed(2)}L';
    } else if (amount >= 1000) {
      return '৳${(amount / 1000).toStringAsFixed(0)}K';
    }
    return '৳${amount.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final int categoriesCount = _categoryAllocation.length;

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
              LanguageService.tr('Portfolio', 'পোর্টফোলিও'),
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
                  onRefresh: _loadPortfolioData,
                  color: primaryTeal,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LanguageService.tr(
                              '${_investments.length} investments across $categoriesCount categories',
                              '$categoriesCount টি ক্যাটাগরিতে মোট ${_investments.length} টি বিনিয়োগ'),
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 14),

                        // 1. KPI Cards Row
                        _buildKpiRow(),
                        const SizedBox(height: 18),

                        // 2. Allocation by Category & Status Distribution
                        _buildCategoryAllocationCard(),
                        const SizedBox(height: 18),

                        _buildStatusDistributionCard(),
                        const SizedBox(height: 18),

                        // 3. Investment & Return History Chart
                        _buildHistoryTimelineChartCard(),
                        const SizedBox(height: 18),

                        // 4. Investment History Table Summary
                        _buildInvestmentHistorySummaryCard(),
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
                Text(LanguageService.tr('${_investments.length} investments', '${_investments.length} টি বিনিয়োগ'),
                    style: TextStyle(fontSize: 9.5, color: Colors.grey[500])),
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
                Text(LanguageService.tr('At maturity', 'মেয়াদপূর্তিতে'),
                    style: TextStyle(fontSize: 9.5, color: Colors.grey[500])),
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
                Text(LanguageService.tr('Distributed so far', 'প্রাপ্ত লভ্যাংশ'),
                    style: TextStyle(fontSize: 9.5, color: Colors.grey[500])),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Allocation by Category Card
  Widget _buildCategoryAllocationCard() {
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
          Text(
            LanguageService.tr('Allocation by Category', 'ক্যাটাগরি ভিত্তিক বণ্টন'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          _categoryAllocation.isEmpty
              ? Text(LanguageService.tr('No investments yet.', 'এখনো কোনো বিনিয়োগ নেই।'),
                  style: const TextStyle(fontSize: 12, color: Colors.grey))
              : Column(
                  children: _categoryAllocation.entries.map((e) {
                    final double pct = _totalInvested > 0
                        ? ((e.value / _totalInvested) * 100).clamp(0.0, 100.0)
                        : 0.0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.key,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                '${_fmtBdt(e.value)} (${pct.toStringAsFixed(1)}%)',
                                style: TextStyle(
                                    fontSize: 11.5, color: Colors.grey[700]),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct / 100,
                              minHeight: 6,
                              backgroundColor: Colors.grey.shade100,
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(primaryTeal),
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

  // Investment Status Distribution Card
  Widget _buildStatusDistributionCard() {
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
          Text(
            LanguageService.tr('Investment Status Distribution', 'ইনভেস্টমেন্ট স্ট্যাটাস বণ্টন'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          _statusDistribution.isEmpty
              ? Text(LanguageService.tr('No investments yet.', 'এখনো কোনো বিনিয়োগ নেই।'),
                  style: const TextStyle(fontSize: 12, color: Colors.grey))
              : Column(
                  children: _statusDistribution.entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key,
                              style: TextStyle(
                                  fontSize: 12.5, color: Colors.grey[800])),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${e.value}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTeal),
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

  // Investment & Return History 12-Month Line Timeline Chart
  Widget _buildHistoryTimelineChartCard() {
    final months = [
      'Nov 25',
      'Dec 25',
      'Jan 26',
      'Feb 26',
      'Mar 26',
      'Apr 26',
      'May 26',
      'Jun 26',
      'Jul 26',
      'Aug 26',
      'Sep 26',
      'Oct 26',
    ];

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
          Text(
            LanguageService.tr('Investment & Return History', 'ইনভেস্টমেন্ট ও রিটার্ন ইতিহাস'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          Text(
            LanguageService.tr('Last 12 months timeline', 'গত ১২ মাসের হিস্ট্রি চার্ট'),
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),

          // Legend
          Row(
            children: [
              Container(width: 10, height: 10, color: primaryTeal),
              const SizedBox(width: 4),
              Text(LanguageService.tr('Invested', 'বিনিয়োগ'), style: const TextStyle(fontSize: 10)),
              const SizedBox(width: 14),
              Container(width: 10, height: 10, color: Colors.amber),
              const SizedBox(width: 4),
              Text(LanguageService.tr('Returns', 'রিটার্ন'), style: const TextStyle(fontSize: 10)),
            ],
          ),
          const SizedBox(height: 16),

          // Visual Line Axis
          SizedBox(
            height: 50,
            child: Row(
              children: months.map((m) {
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        height: 2,
                        color: Colors.teal.shade300,
                      ),
                      const SizedBox(height: 6),
                      RotatedBox(
                        quarterTurns: 3,
                        child: Text(
                          m,
                          style: TextStyle(
                              fontSize: 8.5, color: Colors.grey[600]),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // Investment History Table Summary
  Widget _buildInvestmentHistorySummaryCard() {
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
          Text(
            LanguageService.tr('Investment History', 'বিনিয়োগের ইতিহাস'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _investments.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(LanguageService.tr('No investment history.', 'কোনো ইনভেস্টমেন্ট হিস্ট্রি নেই।'),
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _investments.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final inv = _investments[index];
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                inv['title'] as String? ?? 'Project',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                inv['createdAt'] as String? ?? '',
                                style: TextStyle(
                                    fontSize: 10.5, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _fmtBdt(inv['amountBdt'] as double? ?? 0.0),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: primaryTeal),
                        ),
                      ],
                    );
                  },
                ),
        ],
      ),
    );
  }
}
