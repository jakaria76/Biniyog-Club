import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import 'group_invest_page.dart';

class BrowseGroupsPage extends StatefulWidget {
  const BrowseGroupsPage({super.key});

  @override
  State<BrowseGroupsPage> createState() => _BrowseGroupsPageState();
}

class _BrowseGroupsPageState extends State<BrowseGroupsPage> {
  // Group list public data — cache rakha nirapod, kintu protibar background e refresh hoy
  static List<Map<String, dynamic>>? _cachedGroups;

  // ─── Palette ───
  static const Color emerald = Color(0xFF0E4A37);
  static const Color emeraldDeep = Color(0xFF0A3327);
  static const Color emeraldSoft = Color(0xFFE3F0E9);
  static const Color gold = Color(0xFFB8935A);
  static const Color goldLight = Color(0xFFD9BE8C);
  static const Color goldDeep = Color(0xFF8A6A3A);
  static const Color goldSoft = Color(0xFFF6EEDF);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);
  static const Color danger = Color(0xFFB4413A);
  static const Color dangerSoft = Color(0xFFFBEAE8);

  bool _isLoading = true;
  bool _loadFailed = false;
  List<Map<String, dynamic>> _groups = [];

  @override
  void initState() {
    super.initState();
    if (_cachedGroups != null && _cachedGroups!.isNotEmpty) {
      _groups = _cachedGroups!;
      _isLoading = false;
      _loadGroups(background: true);
    } else {
      _loadGroups();
    }
  }

  Future<void> _loadGroups({bool background = false}) async {
    if (!background && mounted) {
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
    }

    final groups = await DatabaseService.getBusinessGroupsWithTiers();
    final failed = groups.isEmpty && DatabaseService.lastRequestFailed;
    if (!mounted) return;

    if (failed) {
      // Cache theke dekhacchi hole oita-i thak; na hole error dekhai
      setState(() {
        _loadFailed = _groups.isEmpty;
        _isLoading = false;
      });
      if (_groups.isNotEmpty && !background) {
        _toast(LanguageService.tr('Could not refresh. Showing saved list.',
            'রিফ্রেশ করা যায়নি। আগের তালিকা দেখানো হচ্ছে।'), error: true);
      }
      return;
    }

    _cachedGroups = groups;
    setState(() {
      _groups = groups;
      _loadFailed = false;
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

  String _pct(double r) {
    final v = r * 100;
    return '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}%';
  }

  /// Admin tier e payment (bank) account add korle-i invest kora jabe
  bool _hasBank(Map<String, dynamic> tier) {
    final bank = tier['bank'];
    return bank is Map && (bank['accountNumber']?.toString() ?? '').trim().isNotEmpty;
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? danger : emerald),
    );
  }

  // ═════════════════════════════════════════════════════════
  // INVEST
  // ═════════════════════════════════════════════════════════
  Future<void> _startInvest(Map<String, dynamic> tier, String groupName, String entityName) async {
    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    if (!mounted) return;

    if (userId.isEmpty) {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
      return;
    }

    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupInvestPage(tier: tier, groupName: groupName, entityName: entityName),
      ),
    );
    if (ok != true || !mounted) return;
    await _showSuccessDialog(groupName, tier['name']?.toString() ?? '');
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _showSuccessDialog(String groupName, String tierName) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(color: emeraldSoft, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: emerald, size: 28),
        ),
        title: Text(
          LanguageService.tr('Submitted for review', 'যাচাইয়ের জন্য জমা হয়েছে'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: ink),
        ),
        content: Text(
          LanguageService.tr(
            '$groupName · $tierName\nYour investment is now pending. It becomes active after admin approves the payment.',
            '$groupName · $tierName\nবিনিয়োগ এখন পেন্ডিং। অ্যাডমিন পেমেন্ট অনুমোদন করলে চালু হবে।',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: muted, height: 1.4),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(LanguageService.tr('OK', 'ঠিক আছে')),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              LanguageService.tr('Business Groups', 'বিজনেস গ্রুপ'),
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
              ? _buildMessage(
            Icons.wifi_off_rounded,
            LanguageService.tr('Could not load business groups', 'বিজনেস গ্রুপ লোড করা যায়নি'),
            LanguageService.tr('Please check your internet connection.', 'ইন্টারনেট সংযোগ চেক করুন।'),
          )
              : RefreshIndicator(
            onRefresh: _loadGroups,
            color: emerald,
            child: _groups.isEmpty
                ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.22),
                const Icon(Icons.corporate_fare_rounded, size: 52, color: goldDeep),
                const SizedBox(height: 14),
                Text(
                  LanguageService.tr('No business groups open right now',
                      'এই মুহূর্তে কোনো বিজনেস গ্রুপ খোলা নেই'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
                ),
                const SizedBox(height: 6),
                Text(
                  LanguageService.tr('Pull down to refresh', 'রিফ্রেশ করতে নিচে টানুন'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: muted),
                ),
              ],
            )
                : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              itemCount: _groups.length,
              itemBuilder: (context, index) => _buildGroupCard(_groups[index]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> group) {
    final entities = ((group['entities'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final name = group['name']?.toString() ?? '';
    final tagline = group['tagline']?.toString() ?? '';
    final description = group['description']?.toString() ?? '';
    final hasTiers = entities.any((e) => ((e['tiers'] as List?) ?? []).isNotEmpty);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header ───
          Container(
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
                  child: CustomPaint(
                    painter: _IslamicPatternPainter(color: Colors.white.withAlpha(16), cell: 40),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      if (tagline.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(tagline, style: const TextStyle(fontSize: 12, color: goldLight)),
                      ],
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: Colors.white.withAlpha(185), height: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!hasTiers)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                LanguageService.tr('No investment tiers open right now.',
                    'বর্তমানে কোনো ইনভেস্টমেন্ট টিয়ার খোলা নেই।'),
                style: const TextStyle(fontSize: 12, color: muted, fontStyle: FontStyle.italic),
              ),
            )
          else
            ...entities
                .where((e) => ((e['tiers'] as List?) ?? []).isNotEmpty)
                .map((entity) => _buildEntityWidget(name, entity)),
        ],
      ),
    );
  }

  Widget _buildEntityWidget(String groupName, Map<String, dynamic> entity) {
    final tiers = ((entity['tiers'] as List?) ?? [])
        .map((t) => Map<String, dynamic>.from(t as Map))
        .toList();
    final entityName = entity['name']?.toString() ?? '';
    final showName = entityName.isNotEmpty && entityName.toLowerCase() != groupName.toLowerCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showName) ...[
            Row(
              children: [
                Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(gradient: LinearGradient(colors: [goldLight, gold])),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entityName,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: emerald),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          ...tiers.map((tier) => _buildTierCard(groupName, entityName, tier)),
        ],
      ),
    );
  }

  Widget _buildTierCard(String groupName, String entityName, Map<String, dynamic> tier) {
    final pct = _num(tier['expectedReturnPct']);
    final months = (tier['durationMonths'] as num?)?.toInt() ?? 0;
    final minAmount = _num(tier['minAmountBdt']);
    final maxRaw = tier['maxAmountBdt'];
    final maxAmount = maxRaw == null ? 0.0 : _num(maxRaw);
    final description = tier['description']?.toString() ?? '';
    final benefits = ((tier['benefits'] as List?) ?? []).map((b) => b.toString()).toList();

    String range;
    if (minAmount > 0 && maxAmount > 0) {
      range = '${_fmtBdt(minAmount)} – ${_fmtBdt(maxAmount)}';
    } else if (minAmount > 0) {
      range = LanguageService.tr('From ${_fmtBdt(minAmount)}', '${_fmtBdt(minAmount)} থেকে');
    } else if (maxAmount > 0) {
      range = LanguageService.tr('Up to ${_fmtBdt(maxAmount)}', 'সর্বোচ্চ ${_fmtBdt(maxAmount)}');
    } else {
      range = '';
    }

    final facts = <(String, String)>[
      if (pct > 0) (LanguageService.tr('Return', 'লাভ'), _pct(pct)),
      if (months > 0) (LanguageService.tr('Term', 'মেয়াদ'), LanguageService.tr('$months mo', '$months মাস')),
      if (range.isNotEmpty) (LanguageService.tr('Amount', 'পরিমাণ'), range),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ivory,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tier['name']?.toString() ?? '',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
                ),
              ),
              if (pct > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [goldLight, gold]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _pct(pct),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: emeraldDeep),
                  ),
                ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(description, style: const TextStyle(fontSize: 11.5, color: muted, height: 1.4)),
          ],
          if (benefits.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...benefits.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle_rounded, size: 13, color: emerald),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(b, style: const TextStyle(fontSize: 11.5, color: ink, height: 1.35))),
                ],
              ),
            )),
          ],
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: facts
                  .map((f) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.$1.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w700, color: muted, letterSpacing: 0.6)),
                  const SizedBox(height: 2),
                  Text(f.$2,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink)),
                ],
              ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _hasBank(tier)
                ? FilledButton(
              onPressed: () => _startInvest(tier, groupName, entityName),
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                LanguageService.tr('Invest Now', 'বিনিয়োগ করুন'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            )
                : Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: goldSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: gold.withAlpha(90)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.schedule_rounded, size: 16, color: goldDeep),
                  const SizedBox(width: 6),
                  Text(
                    LanguageService.tr('Coming Soon', 'শীঘ্রই আসছে'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: goldDeep),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═════════════════════════════════════════════════════════
  Widget _buildMessage(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: goldDeep),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: muted)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadGroups,
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