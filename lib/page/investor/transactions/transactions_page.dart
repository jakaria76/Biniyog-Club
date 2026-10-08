import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  bool _isLoading = true;
  String _selectedFilter = 'ALL';

  List<Map<String, dynamic>> _allTransactions = [];

  static const Map<String, String> statusLabels = {
    'PENDING': 'Pending',
    'PROCESSING': 'Processing',
    'COMPLETED': 'Completed',
    'FAILED': 'Failed',
    'REFUNDED': 'Refunded',
    'CANCELLED': 'Cancelled',
  };

  static const Map<String, Color> statusColors = {
    'PENDING': Colors.amber,
    'PROCESSING': Colors.blue,
    'COMPLETED': Colors.green,
    'FAILED': Colors.red,
    'REFUNDED': Colors.grey,
    'CANCELLED': Colors.grey,
  };

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';

    final list = await DatabaseService.getTransactionsData(userId);

    if (mounted) {
      setState(() {
        _allTransactions = list;
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

  List<Map<String, dynamic>> get _filteredTransactions {
    if (_selectedFilter == 'INBOUND') {
      return _allTransactions
          .where((t) => t['direction'] == 'INBOUND')
          .toList();
    } else if (_selectedFilter == 'OUTBOUND') {
      return _allTransactions
          .where((t) => t['direction'] == 'OUTBOUND')
          .toList();
    }
    return _allTransactions;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTransactions;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.teal),
        title: const Text(
          'Transactions',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : RefreshIndicator(
              onRefresh: _loadTransactions,
              color: Colors.teal,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_allTransactions.length} total transactions',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 14),

                    // Filter Chips
                    Row(
                      children: [
                        _buildFilterChip('ALL', 'All'),
                        const SizedBox(width: 8),
                        _buildFilterChip('INBOUND', 'Deposits'),
                        const SizedBox(width: 8),
                        _buildFilterChip('OUTBOUND', 'Withdrawals'),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Transactions List
                    filtered.isEmpty
                        ? _buildEmptyState()
                        : Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 24),
                              itemBuilder: (context, index) {
                                final tx = filtered[index];
                                final bool isInbound = tx['direction'] == 'INBOUND';
                                final String status = tx['status'] as String? ?? 'COMPLETED';
                                final Color sColor =
                                    statusColors[status] ?? Colors.grey;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: isInbound
                                                    ? Colors.green.shade50
                                                    : Colors.red.shade50,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                isInbound
                                                    ? Icons.south_west_rounded
                                                    : Icons.north_east_rounded,
                                                color: isInbound
                                                    ? Colors.green.shade700
                                                    : Colors.red.shade700,
                                                size: 16,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  isInbound ? 'Deposit' : 'Withdrawal',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Text(
                                                  tx['method'] as String? ?? 'BANK',
                                                  style: TextStyle(
                                                      fontSize: 10.5,
                                                      color: Colors.grey[600]),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${isInbound ? "+" : "-"}${_fmtBdt(tx['amountBdt'] as double? ?? 0.0)}',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: isInbound
                                                    ? Colors.green.shade700
                                                    : Colors.red.shade700,
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: sColor.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                statusLabels[status] ?? status,
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: sColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            tx['description'] as String? ?? '',
                                            style: TextStyle(
                                                fontSize: 11, color: Colors.grey[700]),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if ((tx['feeBdt'] as double? ?? 0.0) > 0) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Fee: ${_fmtBdt(tx['feeBdt'] as double)}',
                                        style: TextStyle(
                                            fontSize: 10, color: Colors.grey[500]),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final bool isSelected = _selectedFilter == key;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: Colors.teal.shade100,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.teal.shade900 : Colors.grey[800],
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedFilter = key;
          });
        }
      },
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
            const Text('💳', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            const Text(
              'No transactions yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Your payment history will appear here.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
