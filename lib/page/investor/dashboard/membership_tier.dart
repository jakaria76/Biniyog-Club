import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../services/language_service.dart';
import '../../../theme/app_colors.dart';

// ═══════════════════════════════════════════════════════════
// Biniyog Club Prestige — website er lib/prestige er niyom
//   Star    = 1 pt  (protiti project e onshogrohon)
//   Diamond = 2 pts (protiti business segment e malikana, max 6)
//   Crown   = 5 pts (protiti company te directorship)
//   Points  = Stars×1 + Diamonds×2 + Crowns×5
// ═══════════════════════════════════════════════════════════

class PrestigeHoldings {
  final int stars;
  final int diamonds;
  final int crowns;
  const PrestigeHoldings({this.stars = 0, this.diamonds = 0, this.crowns = 0});

  PrestigeHoldings copyWith({int? stars, int? diamonds, int? crowns}) => PrestigeHoldings(
    stars: stars ?? this.stars,
    diamonds: diamonds ?? this.diamonds,
    crowns: crowns ?? this.crowns,
  );
}

class PrestigeTier {
  final int level;
  final String name;
  final int min;
  final int? max;
  final int needDiamonds;
  final int needCrowns;
  const PrestigeTier(this.level, this.name, this.min, this.max,
      {this.needDiamonds = 0, this.needCrowns = 0});
}

const int kMaxDiamonds = 6;

const List<PrestigeTier> kPrestigeTiers = [
  PrestigeTier(1, 'Explorer', 1, 4),
  PrestigeTier(2, 'Bronze', 5, 9),
  PrestigeTier(3, 'Silver', 10, 19),
  PrestigeTier(4, 'Gold', 20, 29),
  PrestigeTier(5, 'Platinum', 30, 44),
  PrestigeTier(6, 'Diamond Elite', 45, 59, needDiamonds: 1),
  PrestigeTier(7, 'Crown Elite', 60, 79, needDiamonds: 1, needCrowns: 1),
  PrestigeTier(8, 'Legacy Circle', 80, null, needDiamonds: 1, needCrowns: 1),
];

class Prestige {
  final PrestigeHoldings holdings;
  final int points;
  final PrestigeTier? tier;
  final PrestigeTier? next;
  final int pointsToNext;
  final int missingDiamonds;
  final int missingCrowns;
  final double progress; // 0..1
  final List<String> recognitions;

  const Prestige({
    required this.holdings,
    required this.points,
    required this.tier,
    required this.next,
    required this.pointsToNext,
    required this.missingDiamonds,
    required this.missingCrowns,
    required this.progress,
    required this.recognitions,
  });

  /// "1 point + 1 Diamond" — porer tier e jete ki lagbe
  String get neededText {
    final parts = <String>[
      if (pointsToNext > 0) '$pointsToNext point${pointsToNext == 1 ? '' : 's'}',
      if (missingDiamonds > 0) '$missingDiamonds Diamond',
      if (missingCrowns > 0) '$missingCrowns Crown',
    ];
    return parts.join(' + ');
  }

  static Prestige compute(PrestigeHoldings h) {
    final points = h.stars + h.diamonds * 2 + h.crowns * 5;

    PrestigeTier? tier;
    for (final t in kPrestigeTiers) {
      if (points >= t.min && h.diamonds >= t.needDiamonds && h.crowns >= t.needCrowns) tier = t;
    }
    PrestigeTier? next;
    for (final t in kPrestigeTiers) {
      if (t.level > (tier?.level ?? 0)) {
        next = t;
        break;
      }
    }

    final toNext = next == null ? 0 : math.max(0, next.min - points);
    final missD = next == null ? 0 : math.max(0, next.needDiamonds - h.diamonds);
    final missC = next == null ? 0 : math.max(0, next.needCrowns - h.crowns);

    double progress;
    if (next == null) {
      progress = 1;
    } else if (toNext == 0) {
      // Point hoye geche, shudhu Diamond/Crown baki
      progress = 1;
    } else {
      final base = tier?.min ?? 0;
      final span = next.min - base;
      progress = span > 0 ? ((points - base) / span).clamp(0.0, 1.0) : 0;
    }

    final rec = <String>[
      if (h.diamonds >= 3) 'Multi-Segment Owner',
      if (h.crowns >= 1 && h.diamonds >= 2) 'Leadership Circle',
      if (h.stars >= 20 && h.diamonds >= 3 && h.crowns >= 1) 'Prestige Circle',
      // Founders' Circle shudhu amontron e — app nije dite pare na
    ];

    return Prestige(
      holdings: h,
      points: points,
      tier: tier,
      next: next,
      pointsToNext: toNext,
      missingDiamonds: missD,
      missingCrowns: missC,
      progress: progress,
      recognitions: rec,
    );
  }
}

// ─── Mark (Star / Diamond / Crown) er chehara ───────────────
enum MarkKind { star, diamond, crown }

class _Mark {
  final String label, plural, role, earnedBy;
  final int points;
  final Color color, soft;
  const _Mark(this.label, this.plural, this.role, this.earnedBy, this.points, this.color, this.soft);
}

const _marks = {
  // Proti ta mark er nijer rong — Star sobuj (gold nai), Diamond neel-sobuj, Crown beguni
  MarkKind.star: _Mark('Star', 'Stars', 'Project Investor', 'One per project you take part in', 1,
      BC.primary, BC.secondary),
  MarkKind.diamond: _Mark('Diamond', 'Diamonds', 'Company Shareholder',
      'One per business segment you hold an ownership stake in (max 6)', 2, Color(0xFF168A9A), Color(0xFFDDF2F4)),
  MarkKind.crown: _Mark('Crown', 'Crowns', 'Company Director', 'One per company where you hold a directorship', 5,
      Color(0xFF7A55B0), Color(0xFFEEE7F7)),
};

int _held(PrestigeHoldings h, MarkKind k) =>
    k == MarkKind.star ? h.stars : k == MarkKind.diamond ? h.diamonds : h.crowns;

class MarkIcon extends StatelessWidget {
  final MarkKind kind;
  final double size;
  const MarkIcon(this.kind, {super.key, this.size = 30});

  @override
  Widget build(BuildContext context) {
    final m = _marks[kind]!;
    final iconSize = size * 0.56;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: m.soft, borderRadius: BorderRadius.circular(size * 0.3)),
      alignment: Alignment.center,
      child: switch (kind) {
        MarkKind.star => Icon(Icons.star_rounded, size: iconSize, color: m.color),
        MarkKind.diamond => Icon(Icons.diamond_rounded, size: iconSize, color: m.color),
        MarkKind.crown => CustomPaint(size: Size(iconSize, iconSize), painter: _CrownPainter(m.color)),
      },
    );
  }
}

class _CrownPainter extends CustomPainter {
  final Color color;
  _CrownPainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final p = Path()
      ..moveTo(w * 0.08, h * 0.30)
      ..lineTo(w * 0.30, h * 0.55)
      ..lineTo(w * 0.50, h * 0.18)
      ..lineTo(w * 0.70, h * 0.55)
      ..lineTo(w * 0.92, h * 0.30)
      ..lineTo(w * 0.82, h * 0.78)
      ..lineTo(w * 0.18, h * 0.78)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.18, h * 0.84, w * 0.64, h * 0.10), const Radius.circular(2)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CrownPainter old) => old.color != color;
}

// ─── Rong ───────────────────────────────────────────────────
const _ink = BC.foreground;
const _muted = BC.mutedForeground;
const _line = BC.border;
const _ivory = BC.muted;
const _emerald = BC.primary;
const _emeraldSoft = BC.secondary;
// Home page er card gular moto sobuj
const _green = BC.primary;
const _greenBright = BC.brand500;
const _greenLight = BC.brand300;
const _greenSoft = BC.secondary;

// ═══════════════════════════════════════════════════════════
// Dashboard card — website er MembershipTierCard
// ═══════════════════════════════════════════════════════════
class MembershipTierCard extends StatelessWidget {
  final PrestigeHoldings holdings;
  const MembershipTierCard({super.key, required this.holdings});

  @override
  Widget build(BuildContext context) {
    final p = Prestige.compute(holdings);
    final tier = p.tier;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _greenLight.withAlpha(140)),
        boxShadow: [BoxShadow(color: _greenBright.withAlpha(30), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Matha — halka sobuj
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_greenSoft, Colors.white]),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_greenBright, _green],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: _greenBright.withAlpha(80), blurRadius: 6, offset: const Offset(0, 3))],
                  ),
                  child: const Icon(Icons.military_tech_rounded, color: Colors.white, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LanguageService.tr('MEMBERSHIP TIER', 'মেম্বারশিপ টিয়ার'),
                        style: const TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w800, color: _green, letterSpacing: 1.3),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              tier?.name ?? LanguageService.tr('Not yet ranked', 'এখনো র‍্যাঙ্ক হয়নি'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: _ink),
                            ),
                          ),
                          if (tier != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: _emeraldSoft, borderRadius: BorderRadius.circular(8)),
                              child: Text('Tier ${tier.level}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _emerald)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => showTierInfoSheet(context, holdings),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 14, color: _ink),
                        const SizedBox(width: 4),
                        Text(LanguageService.tr('Tier info', 'টিয়ার তথ্য'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _ink)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${p.points}',
                        style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: _ink, height: 1)),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(LanguageService.tr('prestige points', 'প্রেস্টিজ পয়েন্ট'),
                          style: const TextStyle(fontSize: 12.5, color: _muted, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 6,
                    color: BC.muted,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: p.progress <= 0 ? 0.015 : p.progress,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [_greenBright, _green]),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  p.next != null
                      ? LanguageService.tr('${p.neededText} to reach ${p.next!.name}',
                      '${p.next!.name} হতে আরও ${p.neededText} লাগবে')
                      : LanguageService.tr('You have reached the highest tier', 'আপনি সর্বোচ্চ টিয়ারে পৌঁছেছেন'),
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final k in MarkKind.values) ...[
                      if (k != MarkKind.star) const SizedBox(width: 8),
                      Expanded(child: _markBox(k, _held(holdings, k))),
                    ],
                  ],
                ),
                if (p.recognitions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final r in p.recognitions)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: _greenSoft,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _greenBright.withAlpha(90)),
                          ),
                          child: Text(r,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _green)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _markBox(MarkKind k, int value) {
    final m = _marks[k]!;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      decoration: BoxDecoration(
        color: m.soft.withAlpha(110),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: m.color.withAlpha(45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MarkIcon(k, size: 20),
              const SizedBox(width: 6),
              Flexible(
                child: Text(m.plural,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: _muted, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text('$value', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: m.color)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// "Tier Information" — website er dialog, app e bottom sheet
// ═══════════════════════════════════════════════════════════
Future<void> showTierInfoSheet(BuildContext context, PrestigeHoldings holdings) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => _TierInfoSheet(holdings: holdings, scroll: scroll),
    ),
  );
}

class _TierInfoSheet extends StatefulWidget {
  final PrestigeHoldings holdings;
  final ScrollController scroll;
  const _TierInfoSheet({required this.holdings, required this.scroll});

  @override
  State<_TierInfoSheet> createState() => _TierInfoSheetState();
}

class _TierInfoSheetState extends State<_TierInfoSheet> {
  late PrestigeHoldings _calc = widget.holdings;

  void _step(MarkKind k, int d) {
    setState(() {
      int clamp(int v, int max) => v < 0 ? 0 : (v > max ? max : v);
      switch (k) {
        case MarkKind.star:
          _calc = _calc.copyWith(stars: clamp(_calc.stars + d, 999));
        case MarkKind.diamond:
          _calc = _calc.copyWith(diamonds: clamp(_calc.diamonds + d, kMaxDiamonds));
        case MarkKind.crown:
          _calc = _calc.copyWith(crowns: clamp(_calc.crowns + d, 999));
      }
    });
  }

  static const _rules = [
    'One Star per qualifying project participation, not per additional investment amount.',
    'One Diamond per segment with verified qualifying ownership — maximum 6 segment Diamonds.',
    'One Crown per verified company directorship.',
    'Points are recognition values, not investment returns or ownership percentages.',
    'Tiers are recalculated when qualifying ownership or directorship ends.',
    'Diamond Elite requires at least 1 Diamond; Crown Elite and Legacy Circle require at least 1 Crown.',
  ];

  static const _recognitions = [
    ('Multi-Segment Owner', 'Diamonds in 3 or more of the 6 segments'),
    ('Leadership Circle', 'At least 1 Crown and 2 Diamonds'),
    ('Prestige Circle', 'At least 20 Stars, 3 Diamonds and 1 Crown'),
    ("Founders' Circle", 'Invitation-only, for exceptional long-term contributions'),
  ];

  Widget _title(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [_greenLight, _greenBright])),
          ),
        ),
        const SizedBox(width: 8),
        Text(t,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w800, color: _green, letterSpacing: 1.3)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final current = Prestige.compute(widget.holdings);
    final result = Prestige.compute(_calc);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: ListView(
        controller: widget.scroll,
        padding: EdgeInsets.zero,
        children: [
          // Matha — sobuj, white lekha
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 12, 18),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              gradient: LinearGradient(
                colors: [_greenBright, _green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white.withAlpha(70), borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Biniyog Club Prestige Tiers',
                              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
                          const SizedBox(height: 6),
                          Text(
                            'Stars, Diamonds and Crowns recognise investment, ownership and leadership. '
                                'Together they make up your Prestige Points and membership tier.',
                            style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(185), height: 1.45),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Recognition points
                _title('1. RECOGNITION POINTS'),
                for (final k in MarkKind.values)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _marks[k]!.soft.withAlpha(90),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _marks[k]!.color.withAlpha(40)),
                    ),
                    child: Row(
                      children: [
                        MarkIcon(k, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('1 ${_marks[k]!.label} · ${_marks[k]!.role}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
                              const SizedBox(height: 2),
                              Text('${_marks[k]!.earnedBy}.',
                                  style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.35)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${_marks[k]!.points} pt${_marks[k]!.points == 1 ? '' : 's'}',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _marks[k]!.color)),
                      ],
                    ),
                  ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                  decoration: BoxDecoration(color: _ivory, borderRadius: BorderRadius.circular(10)),
                  child: const Text(
                    'Prestige Points = (Stars × 1) + (Diamonds × 2) + (Crowns × 5)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: _ink),
                  ),
                ),

                // 2. Membership tiers
                const SizedBox(height: 24),
                _title('2. MEMBERSHIP TIERS'),
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _line),
                  ),
                  child: Column(
                    children: [
                      Container(
                        color: _ivory,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        child: const Row(
                          children: [
                            SizedBox(width: 40, child: Text('TIER', style: _thStyle)),
                            SizedBox(width: 72, child: Text('POINTS', style: _thStyle)),
                            Expanded(child: Text('STATUS', style: _thStyle)),
                          ],
                        ),
                      ),
                      for (final t in kPrestigeTiers) _tierRow(t, current.tier?.level == t.level),
                    ],
                  ),
                ),

                // 3. Tier calculator
                const SizedBox(height: 24),
                _title('3. TIER CALCULATOR'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (final k in MarkKind.values) ...[
                            if (k != MarkKind.star) const SizedBox(width: 8),
                            Expanded(child: _stepper(k)),
                          ],
                        ],
                      ),
                      const Divider(height: 26, color: _line),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('TOTAL PRESTIGE POINTS',
                                    style: TextStyle(
                                        fontSize: 11.5, fontWeight: FontWeight.w800, color: _muted, letterSpacing: 1)),
                                Text('${result.points}',
                                    style: const TextStyle(fontSize: 31, fontWeight: FontWeight.w800, color: _ink)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(result.tier?.name ?? 'Not yet ranked',
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _emerald)),
                              const SizedBox(height: 2),
                              Text(
                                result.next != null
                                    ? '${result.neededText} to ${result.next!.name}'
                                    : 'Highest tier reached',
                                style: const TextStyle(fontSize: 12.5, color: _muted),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: () => setState(() => _calc = const PrestigeHoldings()),
                        style: TextButton.styleFrom(foregroundColor: _muted, padding: EdgeInsets.zero),
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('Reset calculator', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),

                // 4. Special recognition
                const SizedBox(height: 24),
                _title('4. SPECIAL RECOGNITION'),
                for (final r in _recognitions)
                  Builder(builder: (context) {
                    final earned = current.recognitions.contains(r.$1);
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: earned ? _emeraldSoft : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: earned ? _emerald.withAlpha(90) : _line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(r.$1, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
                              if (earned) ...[
                                const SizedBox(width: 6),
                                const Text('EARNED',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _emerald)),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(r.$2, style: const TextStyle(fontSize: 12.5, color: _muted)),
                        ],
                      ),
                    );
                  }),
                const Text(
                  'Recognitions can determine priority seating, networking invitations, exclusive gatherings and '
                      'public acknowledgement. They carry no financial benefits.',
                  style: TextStyle(fontSize: 12.5, color: _muted, height: 1.45),
                ),

                // 5. Rules
                const SizedBox(height: 24),
                _title('5. RULES'),
                for (var i = 0; i < _rules.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 20,
                          child: Text('${i + 1}.',
                              style: const TextStyle(fontSize: 12.5, color: _green, fontWeight: FontWeight.w800)),
                        ),
                        Expanded(
                          child: Text(_rules[i], style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.45)),
                        ),
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

  static const _thStyle = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _muted, letterSpacing: 0.8);

  Widget _tierRow(PrestigeTier t, bool mine) {
    final req = [
      if (t.needDiamonds > 0) '${t.needDiamonds} Diamond',
      if (t.needCrowns > 0) '${t.needCrowns} Crown',
    ].join(' + ');
    return Container(
      decoration: BoxDecoration(
        color: mine ? _emeraldSoft : Colors.white,
        border: const Border(top: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text('${t.level}', style: const TextStyle(fontSize: 13.5, color: _muted))),
          SizedBox(
            width: 72,
            child: Text(t.max == null ? '${t.min}+' : '${t.min}–${t.max}',
                style: const TextStyle(fontSize: 13.5, color: _ink, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 2,
              children: [
                Text(t.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
                if (req.isNotEmpty)
                  Text('· needs $req', style: const TextStyle(fontSize: 12, color: _green)),
                if (mine)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: _emerald, borderRadius: BorderRadius.circular(8)),
                    child: const Text('You',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepper(MarkKind k) {
    final m = _marks[k]!;
    Widget btn(IconData icon, VoidCallback onTap) => InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _line),
        ),
        child: Icon(icon, size: 17, color: _ink),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(color: m.soft.withAlpha(110), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MarkIcon(k, size: 20),
              const SizedBox(width: 5),
              Text(m.plural, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              btn(Icons.remove_rounded, () => _step(k, -1)),
              SizedBox(
                width: 30,
                child: Text('${_held(_calc, k)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
              ),
              btn(Icons.add_rounded, () => _step(k, 1)),
            ],
          ),
        ],
      ),
    );
  }
}