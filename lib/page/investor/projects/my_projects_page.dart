import 'package:flutter/material.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import 'project_detail_page.dart';

class MyProjectsPage extends StatefulWidget {
  const MyProjectsPage({super.key});

  @override
  State<MyProjectsPage> createState() => _MyProjectsPageState();
}

class _MyProjectsPageState extends State<MyProjectsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _myProjects = [];

  static const Color primaryTeal = Color(0xFF047857);



  static const Map<String, Color> projectStatusColors = {
    'FUNDRAISING': Colors.amber,
    'FUNDED': Colors.blue,
    'ACTIVE': primaryTeal,
    'HARVESTING': Colors.orange,
    'COMPLETED': Colors.green,
    'CANCELLED': Colors.red,
  };

  static const Map<String, String> categoryLabels = {
    'REAL_ESTATE': 'Real Estate',
    'TRADE_FINANCE': 'Trade Finance',
    'SME': 'SME Business',
    'TECHNOLOGY': 'Technology',
    'INFRASTRUCTURE': 'Infrastructure',
    'CROP_FARMING': 'Crop Farming',
    'LIVESTOCK': 'Livestock',
    'OTHER': 'Other',
  };

  @override
  void initState() {
    super.initState();
    _loadProjectsData();
  }

  Future<void> _loadProjectsData() async {
    setState(() => _isLoading = true);

    final res = await DatabaseService.getProjectsData();

    if (mounted) {
      setState(() {
        if (res.isNotEmpty) {
          _myProjects = (res['projects'] as List<Map<String, dynamic>>? ?? []);
        }
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
              LanguageService.tr('Open Projects', 'উন্মুক্ত প্রজেক্টসমূহ'),
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
                  onRefresh: _loadProjectsData,
                  color: primaryTeal,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LanguageService.tr(
                              '${_myProjects.length} ${_myProjects.length == 1 ? "project" : "projects"} open for investment',
                              'মোট ${_myProjects.length} টি প্রজেক্ট বিনিয়োগের জন্য উন্মুক্ত'),
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 16),

                        _myProjects.isEmpty
                            ? _buildEmptyState()
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _myProjects.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 16),
                                itemBuilder: (context, index) {
                                  final p = _myProjects[index];
                                  return _buildProjectCard(p);
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

  Widget _buildProjectCard(Map<String, dynamic> p) {
    final double goal = p['fundingGoalBdt'] as double? ?? 1.0;
    final double progress = p['progress'] as double? ?? 0.0;
    final int fundedPct = (progress * 100).toInt();

    final String pStatus = p['status'] as String? ?? 'FUNDRAISING';
    final Color pStatusColor =
        projectStatusColors[pStatus] ?? Colors.grey;

    final String catLabel =
        categoryLabels[p['category']] ?? p['category'] as String? ?? 'SME';

    final String expReturn =
        '${((p['expectedReturnPct'] as double? ?? 0.15) * 100).toStringAsFixed(0)}%';

    final coverUrl = p['coverImageUrl']?.toString() ?? '';
    final location = p['location']?.toString() ?? 'Narayanganj';
    final daysLeft = p['daysLeft'] as int? ?? 116;
    final investorsCount = p['investorsCount'] as int? ?? 1;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProjectDetailPage(
              projectIdOrSlug: p['id'].toString(),
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Cover Image Header with Badges
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(18)),
                  child: Image.network(
                    coverUrl,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 160,
                        width: double.infinity,
                        color: Colors.teal.shade900,
                        child: const Center(
                          child: Icon(Icons.image_not_supported_outlined,
                              color: Colors.white54, size: 36),
                        ),
                      );
                    },
                  ),
                ),
                // Top-Left Category Badge
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(160),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      catLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                // Top-Right Status / Days Left Badge
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: pStatusColor.withAlpha(200),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_rounded,
                            size: 12, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          '$daysLeft ${LanguageService.tr("days left", "দিন বাকি")}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['title'] as String? ?? 'Project',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),

                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 13, color: primaryTeal),
                      const SizedBox(width: 4),
                      Text(
                        location,
                        style:
                            TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Text(
                    p['description'] as String? ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 14),

                  // Funding Progress Bar & Goal
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$fundedPct% ${LanguageService.tr("funded", "সংগৃহীত")}',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${LanguageService.tr("Goal:", "লক্ষ্য:")} ${_formatBdt(goal)}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: Colors.grey.shade200,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(primaryTeal),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 3 Bento Stat Boxes
                  Row(
                    children: [
                      Expanded(
                        child: _buildBentoBox(
                            LanguageService.tr('Return', 'রিটার্ন'),
                            expReturn,
                            primaryTeal),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildBentoBox(
                            LanguageService.tr('Duration', 'মেয়াদ'),
                            '${p['durationDays']}d',
                            Colors.black87),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildBentoBox(
                            LanguageService.tr('Investors', 'বিনিয়োগকারী'),
                            '$investorsCount',
                            Colors.black87),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Text(
                    '${LanguageService.tr("Min Entry:", "সর্বনিম্ন অংশগ্রহণ:")} ${_formatBdt(p['minInvestmentBdt'] as double? ?? 0.0)}',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBentoBox(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Text(
            val,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 9, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            const Text('🌾', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              LanguageService.tr('No projects found', 'কোনো প্রজেক্ট পাওয়া যায়নি'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              LanguageService.tr(
                  'Check back later for new investment opportunities.',
                  'নতুন ইনভেস্টমেন্টের জন্য পরবর্তীতে আবার চেক করুন।'),
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
