import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  double _totalInvested = 0.0;
  double _activeCapital = 0.0;
  double _totalReturns = 0.0;

  final Map<String, double> _byCategory = {};
  final Map<String, int> _byStatus = {};

  List<Map<String, dynamic>> _investmentHistory = [];
  List<Map<String, dynamic>> _transactions = [];
  final List<Map<String, dynamic>> _distributions = [];

  static const Color primaryTeal = Color(0xFF047857);

  // Expected return range (16% - 22%)
  static const double minReturnRate = 0.16;
  static const double maxReturnRate = 0.22;

  static const Map<String, String> categoryLabels = {
    'REAL_ESTATE': 'Real Estate',
    'TRADE_FINANCE': 'Trade Finance',
    'SME': 'SME',
    'TECHNOLOGY': 'Technology',
    'INFRASTRUCTURE': 'Infrastructure',
    'CROP_FARMING': 'Crop Farming',
    'LIVESTOCK': 'Livestock',
    'AQUACULTURE': 'Aquaculture',
    'OTHER': 'Other',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadReportsData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReportsData() async {
    setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    final userEmail = userData?['email']?.toString() ?? '';

    // Fetch Portfolio & Transaction Data from Neon DB
    final pData =
    await DatabaseService.getPortfolioData(userId, email: userEmail);
    final trxData = await DatabaseService.getTransactionsData(userId);

    if (mounted) {
      setState(() {
        if (pData.isNotEmpty) {
          _totalInvested = (pData['totalInvested'] as double? ?? 0.0);
          _totalReturns = (pData['totalActual'] as double? ?? 0.0);

          _investmentHistory =
          (pData['investments'] as List<Map<String, dynamic>>? ?? []);

          final Map<String, double> catMap = {};
          final Map<String, int> stMap = {};
          _activeCapital = 0.0;

          for (final inv in _investmentHistory) {
            final cat = inv['category']?.toString() ?? 'SME';
            final catName = categoryLabels[cat] ?? cat;
            final amt = inv['amountBdt'] as double? ?? 0.0;
            final st = inv['status']?.toString() ?? 'ACTIVE';

            catMap[catName] = (catMap[catName] ?? 0.0) + amt;
            stMap[st] = (stMap[st] ?? 0) + 1;

            if (st == 'ACTIVE') {
              _activeCapital += amt;
            }
          }

          _byCategory.clear();
          _byCategory.addAll(catMap);
          _byStatus.clear();
          _byStatus.addAll(stMap);
        }

        _transactions = trxData;
        _isLoading = false;
      });
    }
  }

  String _fmtBdt(double amount) {
    if (amount >= 10000000) {
      return '৳${(amount / 10000000).toStringAsFixed(2)} Cr';
    } else if (amount >= 100000) {
      return '৳${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      return '৳${(amount / 1000).toStringAsFixed(0)}K';
    }
    return '৳${amount.toStringAsFixed(0)}';
  }

  // Expected return range text (16% - 22% of amount)
  String _fmtExpectedReturnRange(double amount) {
    final double minR = amount * minReturnRate;
    final double maxR = amount * maxReturnRate;
    return '${_fmtBdt(minR)} - ${_fmtBdt(maxR)}';
  }

  // Export Action Dropdown Menu
  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LanguageService.tr('Export Report Statement', 'রিপোর্ট স্টেটমেন্ট এক্সপোর্ট'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.table_chart_outlined, color: primaryTeal),
                title: const Text('Export CSV'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(LanguageService.tr('Exporting Report as CSV...', 'সিএসভি ফাইল এক্সপোর্ট হচ্ছে...')),
                      backgroundColor: primaryTeal,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined, color: primaryTeal),
                title: const Text('Export Excel (.xlsx)'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(LanguageService.tr('Exporting Report as Excel (.xlsx)...', 'এক্সেল ফাইল এক্সপোর্ট হচ্ছে...')),
                      backgroundColor: primaryTeal,
                    ),
                  );
                },
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
        return Scaffold(
          backgroundColor: const Color(0xFFF4F7F6),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.5,
            iconTheme: const IconThemeData(color: primaryTeal),
            title: Text(
              LanguageService.tr('Reports', 'রিপোর্টস'),
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            actions: [
              OutlinedButton.icon(
                onPressed: _showExportOptions,
                icon: const Icon(Icons.download_rounded, size: 14),
                label: Text(LanguageService.tr('Export', 'এক্সপোর্ট')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryTeal,
                  side: const BorderSide(color: primaryTeal),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 12),
            ],
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: primaryTeal,
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: primaryTeal,
              indicatorWeight: 3,
              tabs: [
                Tab(
                    text: LanguageService.tr('Portfolio', 'পোর্টফোলিও'),
                    icon: const Icon(Icons.show_chart_rounded, size: 18)),
                Tab(
                    text: LanguageService.tr('Investment History', 'ইনভেস্টমেন্ট হিস্ট্রি'),
                    icon: const Icon(Icons.bar_chart_rounded, size: 18)),
                Tab(
                    text: LanguageService.tr('Transactions', 'লেনদেন'),
                    icon: const Icon(Icons.receipt_long_rounded, size: 18)),
                Tab(
                    text: LanguageService.tr('Distributions', 'বণ্টন'),
                    icon: const Icon(Icons.layers_outlined, size: 18)),
              ],
            ),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: primaryTeal))
              : TabBarView(
            controller: _tabController,
            children: [
              _buildPortfolioTab(),
              _buildInvestmentHistoryTab(),
              _buildTransactionsTab(),
              _buildDistributionsTab(),
            ],
          ),
        );
      },
    );
  }

  // 1. Portfolio Tab
  Widget _buildPortfolioTab() {
    final double roi = _totalInvested > 0
        ? ((_totalReturns / _totalInvested) * 100)
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top 4 KPI Grid Cards
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.6,
            children: [
              _buildKpiCard(LanguageService.tr('Total Invested', 'মোট বিনিয়োগ'), _fmtBdt(_totalInvested), LanguageService.tr('all time', 'সর্বমোট')),
              _buildKpiCard(LanguageService.tr('Active Capital', 'এক্টিভ ক্যাপিটাল'), _fmtBdt(_activeCapital), LanguageService.tr('currently deployed', 'চলতি প্রজেক্টে')),
              _buildKpiCard(LanguageService.tr('Total Returns', 'মোট রিটার্ন'), _fmtBdt(_totalReturns), LanguageService.tr('distributed', 'বণ্টনকৃত')),
              _buildKpiCard(LanguageService.tr('ROI', 'আর.ও.আই'), '${roi.toStringAsFixed(2)}%', LanguageService.tr('return on investment', 'বিনিয়োগের লাভ')),
            ],
          ),
          const SizedBox(height: 18),

          // 2 Progress / Status Side Cards
          _buildCategoryAllocationCard(),
          const SizedBox(height: 16),

          _buildStatusDistributionCard(),
        ],
      ),
    );
  }

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
          _byCategory.isEmpty
              ? const Text('No investments yet.',
              style: TextStyle(fontSize: 12, color: Colors.grey))
              : Column(
            children: _byCategory.entries.map((e) {
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
                        Text('${_fmtBdt(e.value)} (${pct.toStringAsFixed(1)}%)',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[700])),
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
            LanguageService.tr('Investments by Status', 'স্ট্যাটাস অনুসারে ইনভেস্টমেন্ট'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          _byStatus.isEmpty
              ? const Text('No investments yet.',
              style: TextStyle(fontSize: 12, color: Colors.grey))
              : Column(
            children: _byStatus.entries.map((e) {
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

  // 2. Investment History Tab
  Widget _buildInvestmentHistoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                LanguageService.tr(
                    '${_investmentHistory.length} investments',
                    'মোট ${_investmentHistory.length} টি ইনভেস্টমেন্ট'),
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: _investmentHistory.isEmpty
                ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No investments found.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            )
                : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _investmentHistory.length,
              separatorBuilder: (context, index) =>
              const Divider(height: 20),
              itemBuilder: (context, index) {
                final item = _investmentHistory[index];
                final cat = categoryLabels[item['category']] ??
                    item['category']?.toString() ??
                    'SME';
                final double amount =
                    item['amountBdt'] as double? ?? 0.0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item['title'] as String? ?? 'Project',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item['status'] as String? ?? 'ACTIVE',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal.shade800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(cat,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[600])),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('AMOUNT',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[600])),
                            Text(_fmtBdt(amount),
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: primaryTeal)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('EXPECTED RETURN',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[600])),
                            Text(_fmtExpectedReturnRange(amount),
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green)),
                          ],
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 3. Transactions Tab
  Widget _buildTransactionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 3 KPI Cards (Total In, Total Out, Transactions Count)
          GridView.count(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.2,
            children: [
              _buildKpiCard('Total In', _fmtBdt(0.0), 'inbound completed'),
              _buildKpiCard('Total Out', _fmtBdt(0.0), 'outbound completed'),
              _buildKpiCard('Transactions', '${_transactions.length}', 'all time'),
            ],
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: _transactions.isEmpty
                ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No transactions found.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            )
                : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _transactions.length,
              separatorBuilder: (context, index) =>
              const Divider(height: 16),
              itemBuilder: (context, index) {
                final t = _transactions[index];
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t['description'] as String? ?? 'Transaction',
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold)),
                        Text(t['createdAt'] as String? ?? '',
                            style: TextStyle(
                                fontSize: 10.5, color: Colors.grey[600])),
                      ],
                    ),
                    Text(_fmtBdt(t['amountBdt'] as double? ?? 0.0),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: primaryTeal)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 4. Distributions Tab
  Widget _buildDistributionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 3 KPI Cards (Gross Distributed, Platform Fees, Net Received)
          GridView.count(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.2,
            children: [
              _buildKpiCard('Gross Distributed', _fmtBdt(0.0), 'before fees'),
              _buildKpiCard('Platform Fees', _fmtBdt(0.0), 'deducted'),
              _buildKpiCard('Net Received', _fmtBdt(0.0), 'to your account'),
            ],
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: _distributions.isEmpty
                ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No distributions yet.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            )
                : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _distributions.length,
              separatorBuilder: (context, index) =>
              const Divider(height: 16),
              itemBuilder: (context, index) {
                final d = _distributions[index];
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d['project'] as String? ?? 'Project',
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold)),
                        Text(d['date'] as String? ?? '',
                            style: TextStyle(
                                fontSize: 10.5, color: Colors.grey[600])),
                      ],
                    ),
                    Text(_fmtBdt(d['net'] as double? ?? 0.0),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.green)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, String sub) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: primaryTeal)),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, color: Colors.grey[500])),
        ],
      ),
    );
  }
}