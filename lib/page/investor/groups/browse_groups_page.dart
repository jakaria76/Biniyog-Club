import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import 'group_invest_page.dart';
import '../../../theme/app_colors.dart';

class BrowseGroupsPage extends StatefulWidget {
  const BrowseGroupsPage({super.key});

  @override
  State<BrowseGroupsPage> createState() => _BrowseGroupsPageState();
}

class _BrowseGroupsPageState extends State<BrowseGroupsPage> {
  // Group list public data — cache rakha nirapod, kintu protibar background e refresh hoy
  static List<Map<String, dynamic>>? _cachedGroups;

  // ─── Palette — website er rong (lib/theme/app_colors.dart) ───
  static const Color emerald = BC.primary;
  static const Color emeraldBright = BC.brand500; // home page er moto
  static const Color emeraldSoft = BC.secondary;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color danger = BC.destructive;
  static const Color dangerSoft = BC.destructiveMuted;

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

  /// Unit er hishab thakle ar 0 hoye gele — bikri shesh
  bool _soldOut(Map<String, dynamic> tier) {
    final u = tier['availableUnits'];
    return u is num && u <= 0;
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
      // Landing page theke ashle pichoner page muche felbo na — login kore fire ashbe
      _toast(LanguageService.tr('Please sign in to invest.', 'বিনিয়োগ করতে সাইন ইন করুন।'));
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
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
    if (!mounted) return;
    // Dashboard er tab hole pop korbo na (tahole app-i bondho hoye jabe)
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context, true);
    } else {
      _loadGroups(background: true);
    }
  }

  Future<void> _showSuccessDialog(String groupName, String tierName) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(color: emeraldSoft, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: emerald, size: 24),
        ),
        title: Text(
          LanguageService.tr('Submitted for review', 'যাচাইয়ের জন্য জমা হয়েছে'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            toolbarHeight: 54,
            iconTheme: const IconThemeData(color: ink),
            // Back button — page push kore khulle pichone jay; dashboard er tab hole
            // dashboard er PopScope dhore Home tab e fire ashe
            leading: IconButton(
              tooltip: LanguageService.tr('Back', 'পিছনে'),
              icon: const Icon(Icons.arrow_back_rounded, color: ink, size: 22),
              onPressed: () => Navigator.maybePop(context),
            ),
            title: Text(
              LanguageService.tr('Business Groups', 'বিজনেস গ্রুপ'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 17.5),
            ),
          ),
          body: _isLoading
              ? const Center(
            child: SizedBox(
              width: 26,
              height: 26,
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
                const Icon(Icons.corporate_fare_rounded, size: 38, color: emerald),
                const SizedBox(height: 10),
                Text(
                  LanguageService.tr('No business groups open right now',
                      'এই মুহূর্তে কোনো বিজনেস গ্রুপ খোলা নেই'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: ink),
                ),
                const SizedBox(height: 4),
                Text(
                  LanguageService.tr('Pull down to refresh', 'রিফ্রেশ করতে নিচে টানুন'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: muted),
                ),
              ],
            )
                : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              // Dashboard tab hole curved navbar er jonno niche jayga
              padding: EdgeInsets.fromLTRB(16, 2, 16, Navigator.of(context).canPop() ? 24 : 104),
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
    final tierCount = entities.fold<int>(0, (n, e) => n + ((e['tiers'] as List?) ?? []).length);
    final hasTiers = tierCount > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header ───
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [emeraldBright, emerald],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(22),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: Colors.white.withAlpha(60)),
                            ),
                            child: const Icon(Icons.corporate_fare_rounded, size: 15, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty ? '—' : name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white),
                                ),
                                if (tagline.isNotEmpty)
                                  Text(tagline,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(200))),
                              ],
                            ),
                          ),
                          if (tierCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(22),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                LanguageService.tr('$tierCount tiers', '$tierCount টিয়ার'),
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(180), height: 1.4),
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
              padding: const EdgeInsets.all(12),
              child: Text(
                LanguageService.tr('No investment tiers open right now.',
                    'বর্তমানে কোনো ইনভেস্টমেন্ট টিয়ার খোলা নেই।'),
                style: const TextStyle(fontSize: 12.5, color: muted, fontStyle: FontStyle.italic),
              ),
            )
          else ...[
            ...entities
                .where((e) => ((e['tiers'] as List?) ?? []).isNotEmpty)
                .map((entity) => _buildEntityWidget(name, entity)),
            const SizedBox(height: 4),
          ],
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showName) ...[
            Row(
              children: [
                Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: emerald),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entityName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: emerald),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: ivory,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (tier['name']?.toString() ?? '').isEmpty ? '—' : tier['name'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
                ),
              ),
              if (pct > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: emeraldSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _pct(pct),
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: emerald),
                  ),
                ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: muted, height: 1.35)),
          ],
          if (benefits.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...benefits.take(4).map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle_rounded, size: 13, color: emerald),
                  ),
                  const SizedBox(width: 5),
                  Expanded(child: Text(b, style: const TextStyle(fontSize: 12, color: ink, height: 1.35))),
                ],
              ),
            )),
          ],
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: facts
                  .map((f) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.$1.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700, color: muted, letterSpacing: 0.6)),
                  const SizedBox(height: 1),
                  Text(f.$2,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ink)),
                ],
              ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: _hasBank(tier) && !_soldOut(tier)
                ? FilledButton(
              onPressed: () => _startInvest(tier, groupName, entityName),
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                LanguageService.tr('Invest Now', 'বিনিয়োগ করুন'),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            )
                : Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: BC.muted,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: line),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_soldOut(tier) ? Icons.block_rounded : Icons.schedule_rounded, size: 16, color: muted),
                  const SizedBox(width: 5),
                  Text(
                    _soldOut(tier)
                        ? LanguageService.tr('Sold Out', 'সব বিক্রি হয়ে গেছে')
                        : LanguageService.tr('Coming Soon', 'শীঘ্রই আসছে'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: muted),
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
            Icon(icon, size: 34, color: emerald),
            const SizedBox(height: 10),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
            const SizedBox(height: 3),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: muted)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _loadGroups,
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(LanguageService.tr('Try again', 'আবার চেষ্টা করুন')),
            ),
          ],
        ),
      ),
    );
  }
}