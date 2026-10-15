import 'dart:math' as math;

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
  // ─── Palette ───
  static const Color emerald = Color(0xFF0E4A37);
  static const Color emeraldDeep = Color(0xFF0A3327);
  static const Color emeraldSoft = Color(0xFFE3F0E9);
  static const Color gold = Color(0xFFB8935A);
  static const Color goldLight = Color(0xFFD9BE8C);
  static const Color goldDeep = Color(0xFF8A6A3A);
  static const Color goldSoft = Color(0xFFF6EEDF);
  static const Color turquoise = Color(0xFF167A80);
  static const Color lapis = Color(0xFF26437A);
  static const Color terracotta = Color(0xFFA5523A);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);

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

  bool _isLoading = true;
  bool _loadFailed = false;
  List<Map<String, dynamic>> _projects = [];
  String _filter = 'OPEN'; // OPEN = shudhu FUNDRAISING, ALL = shob prokashito

  @override
  void initState() {
    super.initState();
    _loadProjectsData();
  }

  Future<void> _loadProjectsData() async {
    if (mounted) setState(() => _isLoading = true);

    final res = await DatabaseService.getProjectsData();
    final list = ((res['projects'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    // Khali: "kono project nei" naki "net nei" — alada kori
    final failed = list.isEmpty && (res.isEmpty || DatabaseService.lastRequestFailed);

    if (!mounted) return;
    setState(() {
      _projects = list;
      _loadFailed = failed;
      _isLoading = false;
    });
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  String _trim(double v, int digits) {
    final s = v.toStringAsFixed(digits);
    return s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
  }

  String _fmtBdt(double amount) {
    if (amount >= 10000000) return '৳${_trim(amount / 10000000, 2)} Cr';
    if (amount >= 100000) return '৳${_trim(amount / 100000, 2)}L';
    if (amount >= 1000) return '৳${_trim(amount / 1000, 1)}K';
    return '৳${amount.toStringAsFixed(0)}';
  }

  String _pctRange(double lo, double hi) {
    String p(double r) => _trim(r * 100, 1);
    if (lo <= 0 && hi <= 0) return '—';
    return lo == hi ? '${p(hi)}%' : '${p(lo)}–${p(hi)}%';
  }

  String _statusText(String s) {
    switch (s) {
      case 'FUNDRAISING':
        return LanguageService.tr('Open', 'চলমান');
      case 'FUNDED':
        return LanguageService.tr('Fully Funded', 'সম্পূর্ণ অর্থায়িত');
      case 'ACTIVE':
        return LanguageService.tr('Running', 'চলছে');
      case 'HARVESTING':
        return LanguageService.tr('Harvesting', 'ফসল সংগ্রহ');
      case 'COMPLETED':
        return LanguageService.tr('Completed', 'সম্পন্ন');
      default:
        return s;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'FUNDRAISING':
        return emerald;
      case 'FUNDED':
        return lapis;
      case 'ACTIVE':
        return turquoise;
      case 'HARVESTING':
        return goldDeep;
      case 'COMPLETED':
        return muted;
      default:
        return terracotta;
    }
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        final list = _filter == 'OPEN'
            ? _projects.where((p) => p['status'] == 'FUNDRAISING').toList()
            : _projects;
        final openCount = _projects.where((p) => p['status'] == 'FUNDRAISING').length;

        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              LanguageService.tr('Projects', 'প্রজেক্টসমূহ'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          body: _isLoading
              ? const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4),
            ),
          )
              : _loadFailed
              ? _buildMessage()
              : RefreshIndicator(
            onRefresh: _loadProjectsData,
            color: emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                Row(
                  children: [
                    _chip('OPEN', LanguageService.tr('Open ($openCount)', 'চলমান ($openCount)')),
                    const SizedBox(width: 8),
                    _chip('ALL', LanguageService.tr('All (${_projects.length})', 'সব (${_projects.length})')),
                  ],
                ),
                const SizedBox(height: 16),
                if (list.isEmpty)
                  _buildEmptyState()
                else
                  for (final p in list) ...[
                    _buildProjectCard(p),
                    const SizedBox(height: 16),
                  ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String value, String label) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? emerald : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? emerald : line),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : ink),
        ),
      ),
    );
  }

  Widget _buildProjectCard(Map<String, dynamic> p) {
    final goal = _num(p['fundingGoalBdt']);
    final progress = _num(p['progress']).clamp(0.0, 1.0);
    final status = p['status']?.toString() ?? '';
    final sc = _statusColor(status);
    final cat = p['category']?.toString() ?? '';
    final catLabel = categoryLabels[cat] ?? cat;
    final coverUrl = p['coverImageUrl']?.toString() ?? '';
    final location = p['location']?.toString() ?? '';
    final description = p['description']?.toString() ?? '';
    final daysLeft = (p['daysLeft'] as num?)?.toInt() ?? 0;
    final hasDeadline = p['hasDeadline'] == true;
    final duration = (p['durationDays'] as num?)?.toInt() ?? 0;
    final investors = (p['investorsCount'] as num?)?.toInt() ?? 0;
    final minInv = _num(p['minInvestmentBdt']);
    final returnText = _pctRange(_num(p['returnMin']), _num(p['returnMax']));

    // Badge e shudhu shotti tottho: deadline thakle din, na thakle status
    final String badge;
    if (status == 'FUNDRAISING' && hasDeadline) {
      badge = daysLeft > 0
          ? LanguageService.tr('$daysLeft days left', '$daysLeft দিন বাকি')
          : LanguageService.tr('Closing today', 'আজ শেষ দিন');
    } else {
      badge = _statusText(status);
    }

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProjectDetailPage(projectIdOrSlug: p['id'].toString())),
        );
        if (mounted) _loadProjectsData();
      },
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: coverUrl.isEmpty
                      ? _coverPlaceholder()
                      : Image.network(
                    coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _coverPlaceholder(),
                  ),
                ),
                if (catLabel.isNotEmpty)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _overlayPill(catLabel, Colors.black.withAlpha(150)),
                  ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: _overlayPill(badge, sc.withAlpha(225),
                      icon: status == 'FUNDRAISING' && hasDeadline ? Icons.access_time_rounded : null),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (p['title']?.toString() ?? '').isEmpty ? '—' : p['title'].toString(),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 13, color: goldDeep),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(location, style: const TextStyle(fontSize: 11.5, color: muted)),
                        ),
                      ],
                    ),
                  ],
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: muted, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        LanguageService.tr('${(progress * 100).toStringAsFixed(0)}% funded',
                            '${(progress * 100).toStringAsFixed(0)}% সংগৃহীত'),
                        style: const TextStyle(fontSize: 11.5, color: ink, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      if (goal > 0)
                        Text(
                          LanguageService.tr('Goal ${_fmtBdt(goal)}', 'লক্ষ্য ${_fmtBdt(goal)}'),
                          style: const TextStyle(fontSize: 11.5, color: muted),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: line,
                      valueColor: const AlwaysStoppedAnimation<Color>(emerald),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _stat(LanguageService.tr('Return', 'রিটার্ন'), returnText, emerald, emeraldSoft)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _stat(
                          LanguageService.tr('Duration', 'মেয়াদ'),
                          duration > 0 ? LanguageService.tr('$duration days', '$duration দিন') : '—',
                          goldDeep,
                          goldSoft,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _stat(LanguageService.tr('Investors', 'বিনিয়োগকারী'), '$investors', ink, ivory),
                      ),
                    ],
                  ),
                  if (minInv > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      LanguageService.tr('Minimum ${_fmtBdt(minInv)}', 'সর্বনিম্ন ${_fmtBdt(minInv)}'),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: ink),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF125A43), emeraldDeep, Color(0xFF0B2A3A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _IslamicPatternPainter(color: Colors.white.withAlpha(18), cell: 40)),
          ),
          const Center(child: Icon(Icons.eco_outlined, color: goldLight, size: 36)),
        ],
      ),
    );
  }

  Widget _overlayPill(String text, Color bg, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color, Color soft) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 9.5, color: muted)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: emeraldSoft, borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.eco_outlined, color: emerald, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            _filter == 'OPEN'
                ? LanguageService.tr('No projects open right now', 'এই মুহূর্তে কোনো প্রজেক্ট খোলা নেই')
                : LanguageService.tr('No projects yet', 'এখনো কোনো প্রজেক্ট নেই'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: ink),
          ),
          const SizedBox(height: 4),
          Text(
            LanguageService.tr('Check back later for new investment opportunities.',
                'নতুন বিনিয়োগের সুযোগের জন্য পরে আবার দেখুন।'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: muted),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 40, color: goldDeep),
            const SizedBox(height: 12),
            Text(
              LanguageService.tr('Could not load projects', 'প্রজেক্ট লোড করা যায়নি'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
            ),
            const SizedBox(height: 4),
            Text(
              LanguageService.tr('Please check your internet connection.', 'ইন্টারনেট সংযোগ চেক করুন।'),
              style: const TextStyle(fontSize: 12.5, color: muted),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadProjectsData,
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(LanguageService.tr('Try again', 'আবার চেষ্টা করুন')),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Islamic geometric pattern (dashboard er moto 8-point star)
// ═══════════════════════════════════════════════════════════
class _IslamicPatternPainter extends CustomPainter {
  final Color color;
  final double cell;

  _IslamicPatternPainter({required this.color, required this.cell});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    final r = cell * 0.34;

    for (double y = 0; y <= size.height + cell; y += cell) {
      final offsetRow = ((y / cell).round() % 2) * cell / 2;
      for (double x = -cell; x <= size.width + cell; x += cell) {
        final c = Offset(x + offsetRow, y);
        for (final start in [0.0, math.pi / 4]) {
          final path = Path();
          for (int i = 0; i < 4; i++) {
            final a = start + i * math.pi / 2;
            final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
            i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
          }
          path.close();
          canvas.drawPath(path, paint);
        }
        canvas.drawCircle(c, r * 0.32, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IslamicPatternPainter old) =>
      old.color != color || old.cell != cell;
}