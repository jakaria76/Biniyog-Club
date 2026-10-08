import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';

class GroupInvestmentsPage extends StatefulWidget {
  const GroupInvestmentsPage({super.key});

  @override
  State<GroupInvestmentsPage> createState() => _GroupInvestmentsPageState();
}

class _GroupInvestmentsPageState extends State<GroupInvestmentsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _groupInvestments = [];

  static const Map<String, String> statusLabels = {
    'PENDING': 'Pending',
    'PAYMENT_PENDING': 'Awaiting Payment',
    'ACTIVE': 'Active',
    'CANCELLED': 'Cancelled',
    'COMPLETED': 'Completed',
  };

  static const Map<String, Color> statusColors = {
    'PENDING': Colors.grey,
    'PAYMENT_PENDING': Colors.amber,
    'ACTIVE': Colors.green,
    'CANCELLED': Colors.red,
    'COMPLETED': Colors.blue,
  };

  @override
  void initState() {
    super.initState();
    _loadGroupInvestments();
  }

  Future<void> _loadGroupInvestments() async {
    setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';

    final list = await DatabaseService.getGroupInvestmentsData(userId);

    if (mounted) {
      setState(() {
        _groupInvestments = list;
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
              LanguageService.tr('Group Investments', 'গ্রুপ ইনভেস্টমেন্টস'),
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.teal))
              : RefreshIndicator(
                  onRefresh: _loadGroupInvestments,
                  color: Colors.teal,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              LanguageService.tr(
                                  '${_groupInvestments.length} total group investments',
                                  'মোট ${_groupInvestments.length} টি গ্রুপ ইনভেস্টমেন্ট'),
                              style:
                                  TextStyle(fontSize: 13, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        _groupInvestments.isEmpty
                            ? _buildEmptyState()
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _groupInvestments.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 16),
                                itemBuilder: (context, index) {
                                  final inv = _groupInvestments[index];
                                  return _buildGroupCard(inv);
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

  Widget _buildGroupCard(Map<String, dynamic> inv) {
    final String status = inv['status'] as String? ?? 'PENDING';
    final String statusLabel = statusLabels[status] ?? status;
    final Color statusColor = statusColors[status] ?? Colors.grey;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🏢', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${inv['groupName']} — ${inv['entityName']}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${inv['tierName']} · Created ${inv['createdAt']}',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _fmtBdt(inv['amountBdt'] as double? ?? 0.0),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.all(14),
            color: Colors.grey.shade50,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(LanguageService.tr('PLOT NUMBER', 'প্লট নম্বর'),
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600])),
                      Text(inv['plotNumber'] as String? ?? 'N/A',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(LanguageService.tr('SHARE PERCENTAGE', 'শেয়ারের হার'),
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600])),
                      Text('${inv['sharePercentage']}%',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            const Text('🏢', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              LanguageService.tr('No group investments found', 'কোনো গ্রুপ বিনিয়োগ পাওয়া যায়নি'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              LanguageService.tr('Your group investments will appear here.', 'আপনার গ্রুপ ইনভেস্টমেন্ট এখানে দেখা যাবে।'),
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
