import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import '../../../services/membership_policy.dart';
import '../documents/documents_page.dart';
import '../portfolio/investments_page.dart';
import '../profit/profit_returns_page.dart';
import '../shares/my_shares_page.dart';
import '../../../theme/app_colors.dart';

/// Website er /dashboard/membership — Card & Points Policy v1.2.
/// Member ID, Investor / Shareholder ID, duto alada point, primary tier,
/// digital card (QR), ar Diamond / Star / Legacy. App shudhu dekhay;
/// approve / card issue website er Membership Administration kore.
class MembershipPage extends StatefulWidget {
  const MembershipPage({super.key});

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  static const Color emerald = BC.primary;
  static const Color emeraldSoft = BC.secondary;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color review = BC.chart4Deep;
  static const Color danger = BC.destructive;

  bool _loading = true;
  bool _needsLogin = false;
  bool _failed = false;
  String _sessionName = '';
  MyMembership? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final user = await AuthService.getUserData();
    final uid = user?['id']?.toString() ?? '';
    if (uid.isEmpty) {
      if (mounted) {
        setState(() {
          _needsLogin = true;
          _loading = false;
        });
      }
      return;
    }
    final d = await DatabaseService.getMyMembership(uid);
    if (!mounted) return;
    setState(() {
      _sessionName = user?['name']?.toString() ?? '';
      _needsLogin = false;
      _d = d ?? _d;
      _failed = d == null && _d == null;
      _loading = false;
    });
  }

  String _tierName(String? code) {
    final l = tierLabels[code];
    return l == null ? (code ?? '—') : LanguageService.tr(l.$1, l.$2);
  }

  void _open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) => Scaffold(
        backgroundColor: ivory,
        appBar: AppBar(
          backgroundColor: ivory,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 54,
          iconTheme: const IconThemeData(color: ink),
          title: Text(LanguageService.tr('Membership', 'মেম্বারশিপ'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 17.5)),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading && _d == null) {
      return const Center(
        child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4)),
      );
    }
    if (_needsLogin) {
      return _message(
        Icons.lock_outline_rounded,
        LanguageService.tr('Please log in to see your membership', 'মেম্বারশিপ দেখতে লগইন করুন'),
        LanguageService.tr('Log in', 'লগইন'),
            () => Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
        ),
      );
    }
    if (_failed || _d == null) {
      return _message(
        Icons.wifi_off_rounded,
        LanguageService.tr('Could not load your membership', 'মেম্বারশিপ লোড করা যায়নি'),
        LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
        _load,
      );
    }

    final d = _d!;
    return RefreshIndicator(
      onRefresh: _load,
      color: emerald,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
        children: [
          Text(
            LanguageService.tr('Your Biniyog Club membership, IDs, points and card',
                'আপনার বিনিয়োগ ক্লাব মেম্বারশিপ, আইডি, পয়েন্ট ও কার্ড'),
            style: const TextStyle(fontSize: 12.5, color: muted),
          ),
          const SizedBox(height: 12),
          if (!d.policyActive) _notStarted() else ..._content(d),
        ],
      ),
    );
  }

  Widget _notStarted() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          const Icon(Icons.badge_outlined, size: 32, color: muted),
          const SizedBox(height: 10),
          Text(
            LanguageService.tr(
              "The Biniyog Club membership programme hasn't started yet. Your investments and shareholdings are recorded and will count once it begins.",
              'বিনিয়োগ ক্লাব মেম্বারশিপ প্রোগ্রাম এখনো শুরু হয়নি। আপনার বিনিয়োগ ও শেয়ার রেকর্ড করা আছে, শুরু হলে গণনা হবে।',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: muted, height: 1.45),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(MyMembership d) {
    final tier = d.primaryTier;
    final card = d.digitalCard;
    final inv = d.investor;
    final sh = d.shareholder;
    final status = membershipStatusLabels[d.status];
    final showInvestor = d.investorId != null || inv.eligiblePaisa > 0 || d.boatClubException;
    final showShareholder = d.shareholderId != null || sh.shares > 0;

    return [
      // ── Digital card ba keno nei
      if (d.isMember && tier != null && card != null)
        DigitalMembershipCard(
          name: d.name ?? _sessionName,
          memberNumber: d.memberNumber!,
          investorId: d.investorId,
          shareholderId: d.shareholderId,
          tier: card.tierAtIssue.isNotEmpty ? card.tierAtIssue : tier,
          status: card.status,
          cardNumber: card.cardNumber,
          verifyUrl: card.verifyUrl,
          diamonds: d.diamonds.length,
          stars: d.activeStars,
          legacy: d.legacy,
        )
      else
        _infoBox(
          d.isMember
              ? LanguageService.tr(
              'Your digital card is issued once our Membership Administration has verified your membership.',
              'মেম্বারশিপ অ্যাডমিনিস্ট্রেশন আপনার মেম্বারশিপ যাচাই করলে ডিজিটাল কার্ড দেওয়া হবে।')
              : LanguageService.tr('You become a member once a qualifying investment or shareholding is verified.',
              'যোগ্য বিনিয়োগ বা শেয়ার যাচাই হলে আপনি মেম্বার হবেন।'),
        ),
      const SizedBox(height: 12),

      // ── Pori chay
      _section(
        title: LanguageService.tr('Member details', 'মেম্বার তথ্য'),
        icon: Icons.badge_outlined,
        children: [
          _grid([
            (LanguageService.tr('Member', 'মেম্বার'), (d.name ?? _sessionName).isEmpty ? '—' : (d.name ?? _sessionName), false),
            (
            LanguageService.tr('Permanent Member ID', 'স্থায়ী মেম্বার আইডি'),
            d.memberNumber ?? LanguageService.tr('Not yet assigned', 'এখনো দেওয়া হয়নি'),
            d.memberNumber != null
            ),
            (
            LanguageService.tr('Membership status', 'মেম্বারশিপ অবস্থা'),
            status != null
                ? LanguageService.tr(status.$1, status.$2)
                : (d.status ?? LanguageService.tr('Not yet a member', 'এখনো মেম্বার নন')),
            false
            ),
            (LanguageService.tr('Primary card tier', 'প্রধান কার্ড টিয়ার'), tier == null ? '—' : _tierName(tier), false),
            (LanguageService.tr('Investor ID', 'ইনভেস্টর আইডি'), d.investorId ?? '—', d.investorId != null),
            (LanguageService.tr('Shareholder ID', 'শেয়ারহোল্ডার আইডি'), d.shareholderId ?? '—', d.shareholderId != null),
          ]),
          if (d.physicalCard != null) ...[
            const SizedBox(height: 10),
            _physicalLine(d.physicalCard!),
          ],
        ],
      ),

      if (!d.isMember && tier == null) ...[
        const SizedBox(height: 10),
        Text(
          LanguageService.tr(
            "No verified qualifying investment or shareholding yet. Pending commitments and unverified payments don't count.",
            'এখনো কোনো যাচাইকৃত যোগ্য বিনিয়োগ বা শেয়ার নেই। বাকি থাকা বা যাচাই না হওয়া পেমেন্ট গণনা হয় না।',
          ),
          style: const TextStyle(fontSize: 12.5, color: muted, height: 1.4),
        ),
      ],

      // ── Investor track
      if (showInvestor) ...[
        const SizedBox(height: 12),
        _section(
          title: LanguageService.tr('Investor membership', 'ইনভেস্টর মেম্বারশিপ'),
          icon: Icons.trending_up_rounded,
          trailing: d.investorId,
          children: [
            Row(
              children: [
                _kv(
                  LanguageService.tr('Category', 'ক্যাটাগরি'),
                  inv.tier != null
                      ? _tierName(inv.tier)
                      : d.boatClubException
                      ? LanguageService.tr('Classic (Boat Club)', 'ক্লাসিক (বোট ক্লাব)')
                      : LanguageService.tr('Inactive', 'নিষ্ক্রিয়'),
                ),
                _kv(LanguageService.tr('Verified eligible', 'যাচাইকৃত যোগ্য'), fmtTaka(inv.eligiblePaisa / 100)),
                _kv(LanguageService.tr('Investor Points', 'ইনভেস্টর পয়েন্ট'), groupedNumber(inv.points)),
              ],
            ),
            ..._lines([
              for (final l in inv.lines.where((l) => l.eligiblePaisa > 0))
                (
                l.status == 'PAYMENT_PENDING'
                    ? '${l.projectTitle} · ${LanguageService.tr('installments (verified part)', 'কিস্তি (যাচাইকৃত অংশ)')}'
                    : l.projectTitle,
                fmtTaka(l.eligiblePaisa / 100)
                ),
            ]),
            const SizedBox(height: 8),
            _small(
              LanguageService.tr(
                '1 point per ${fmtTaka(d.rules.pointUnitBdt)} of verified active investment. Silver from ${fmtTaka(d.rules.silverFromBdt)}.'
                    '${d.boatClubException && inv.tier == null ? ' Classic by the Boat Club exception earns no points.' : ''}',
                'যাচাইকৃত সক্রিয় বিনিয়োগের প্রতি ${fmtTaka(d.rules.pointUnitBdt)} এ ১ পয়েন্ট। ${fmtTaka(d.rules.silverFromBdt)} থেকে সিলভার।'
                    '${d.boatClubException && inv.tier == null ? ' বোট ক্লাব ব্যতিক্রমে ক্লাসিক হলে পয়েন্ট নেই।' : ''}',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _link(LanguageService.tr('Investments & installments', 'বিনিয়োগ ও কিস্তি'),
                        () => _open(const InvestmentsPage())),
                _link(LanguageService.tr('Profit distributions', 'প্রফিট বিতরণ'), () => _open(const ProfitReturnsPage())),
                _link(LanguageService.tr('Investment documents', 'বিনিয়োগের ডকুমেন্ট'), () => _open(const DocumentsPage())),
              ],
            ),
          ],
        ),
      ],

      // ── Shareholder track
      if (showShareholder) ...[
        const SizedBox(height: 12),
        _section(
          title: LanguageService.tr('Shareholder membership', 'শেয়ারহোল্ডার মেম্বারশিপ'),
          icon: Icons.layers_outlined,
          trailing: d.shareholderId,
          children: [
            Row(
              children: [
                _kv(LanguageService.tr('Category', 'ক্যাটাগরি'),
                    sh.tier != null ? _tierName(sh.tier) : LanguageService.tr('Inactive', 'নিষ্ক্রিয়')),
                _kv(LanguageService.tr('Verified shares', 'যাচাইকৃত শেয়ার'), groupedNumber(sh.shares)),
                _kv(LanguageService.tr('Shareholder Points', 'শেয়ারহোল্ডার পয়েন্ট'), groupedNumber(sh.points)),
              ],
            ),
            ..._lines([
              for (final l in sh.lines.where((l) => l.eligibleShares > 0))
                (
                '${l.companyName} · ${l.projectTitle}',
                LanguageService.tr('${groupedNumber(l.eligibleShares)} shares', '${groupedNumber(l.eligibleShares)} শেয়ার')
                ),
            ]),
            const SizedBox(height: 8),
            _small(LanguageService.tr(
              "1 point per verified allotted share. Pending purchases and unverified allotments don't count. Points are recognition, not money or ownership percentage.",
              'প্রতিটি যাচাইকৃত বরাদ্দকৃত শেয়ারে ১ পয়েন্ট। বাকি থাকা কেনা বা যাচাই না হওয়া বরাদ্দ গণনা হয় না। পয়েন্ট শুধু স্বীকৃতি — টাকা বা মালিকানার শতাংশ নয়।',
            )),
            const SizedBox(height: 8),
            Wrap(
              children: [
                _link(LanguageService.tr('Share purchases, allotments & documents', 'শেয়ার কেনা, বরাদ্দ ও ডকুমেন্ট'),
                        () => _open(const MySharesPage())),
              ],
            ),
          ],
        ),
      ],

      // ── Recognition
      if (d.isMember) ...[
        const SizedBox(height: 12),
        _section(
          title: LanguageService.tr('Recognition', 'স্বীকৃতি'),
          icon: Icons.military_tech_outlined,
          children: [
            Row(
              children: [
                _kv(LanguageService.tr('Diamonds', 'ডায়মন্ড'), '${d.diamonds.length} / 6'),
                _kv(LanguageService.tr('Active Stars', 'সক্রিয় স্টার'), '${d.activeStars}'),
                _kv(LanguageService.tr('Lifetime Stars', 'আজীবন স্টার'), '${d.lifetimeStars}'),
                _kv(LanguageService.tr('Legacy', 'লেগেসি'), d.legacy ? LanguageService.tr('Awarded', 'প্রদত্ত') : '—'),
              ],
            ),
            if (d.diamonds.isNotEmpty) ...[
              const SizedBox(height: 8),
              _small(LanguageService.tr('Diamond segments: ${d.diamonds.join(', ')}', 'ডায়মন্ড সেগমেন্ট: ${d.diamonds.join(', ')}')),
            ],
            if (d.stars.isNotEmpty) ...[
              const SizedBox(height: 4),
              _small(LanguageService.tr(
                'Star projects: ${d.stars.map((s) => s.active ? s.projectTitle : '${s.projectTitle} (lifetime)').join(', ')}',
                'স্টার প্রজেক্ট: ${d.stars.map((s) => s.active ? s.projectTitle : '${s.projectTitle} (আজীবন)').join(', ')}',
              )),
            ],
            const SizedBox(height: 8),
            _small(LanguageService.tr(
              "Stars and Diamonds are recognition marks; they don't convert into points. Benefits are set out in a separate Privileges Schedule.",
              'স্টার ও ডায়মন্ড স্বীকৃতির চিহ্ন; এগুলো পয়েন্টে বদলায় না। সুবিধাসমূহ আলাদা প্রিভিলেজ শিডিউলে আছে।',
            )),
          ],
        ),
      ],

      if (d.policyVersion != null) ...[
        const SizedBox(height: 12),
        Text(
          LanguageService.tr('Membership policy v${d.policyVersion}', 'মেম্বারশিপ নীতিমালা v${d.policyVersion}'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: muted),
        ),
      ],
    ];
  }

  Widget _physicalLine(MemberCard c) {
    const steps = {
      'REQUESTED': ('Requested', 'অনুরোধ করা হয়েছে'),
      'IN_PRODUCTION': ('In production', 'তৈরি হচ্ছে'),
      'DISPATCHED': ('Dispatched', 'পাঠানো হয়েছে'),
      'DELIVERED': ('Delivered', 'পৌঁছেছে'),
    };
    final s = steps[c.fulfilmentStatus];
    return Row(
      children: [
        const Icon(Icons.credit_card_rounded, size: 15, color: emerald),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            LanguageService.tr('Physical card ${c.cardNumber}', 'ফিজিক্যাল কার্ড ${c.cardNumber}') +
                (s == null ? '' : ' · ${LanguageService.tr(s.$1, s.$2)}'),
            style: const TextStyle(fontSize: 12, color: ink, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════
  // SHARED
  // ═════════════════════════════════════════════════════════
  Widget _section({required String title, required IconData icon, String? trailing, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: emeraldSoft, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 15, color: emerald),
              ),
              const SizedBox(width: 9),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink))),
              if (trailing != null)
                SelectableText(trailing,
                    style: const TextStyle(fontSize: 11.5, color: muted, fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  /// 2 kolam er grid — (label, value, monospace)
  Widget _grid(List<(String, String, bool)> items) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final it in items.skip(i).take(2))
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.$1, style: const TextStyle(fontSize: 11, color: muted)),
                    const SizedBox(height: 1),
                    SelectableText(
                      it.$2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ink,
                        fontFamily: it.$3 ? 'monospace' : null,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  Widget _kv(String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            maxLines: 2,
            style: const TextStyle(fontSize: 10.5, color: muted, fontWeight: FontWeight.w600, height: 1.2)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: emerald)),
        ),
      ],
    ),
  );

  List<Widget> _lines(List<(String, String)> items) {
    if (items.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: line),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(items[i].$1, style: const TextStyle(fontSize: 12, color: ink))),
                    const SizedBox(width: 8),
                    Text(items[i].$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _small(String text) => Text(text, style: const TextStyle(fontSize: 11.5, color: muted, height: 1.4));

  Widget _link(String label, VoidCallback onTap) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: emeraldSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: emerald)),
          ),
          const SizedBox(width: 3),
          const Icon(Icons.arrow_forward_rounded, size: 13, color: emerald),
        ],
      ),
    ),
  );

  Widget _infoBox(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: review.withAlpha(18),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: review.withAlpha(50)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 16, color: review),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 12.5, color: ink, height: 1.4)),
        ),
      ],
    ),
  );

  Widget _message(IconData icon, String text, String buttonLabel, VoidCallback onTap) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: _failed ? danger : emerald),
            const SizedBox(height: 10),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════
// DIGITAL CARD — website er components/membership/digital-card.tsx
// Shudhu nam, ID, tier, status ar QR — kono taka / share na (Article 13)
// ═════════════════════════════════════════════════════════════

/// Tier er card rong (website er Tailwind gradient): (shuru, shesh, lekha)
const Map<String, (Color, Color, Color)> membershipTierColors = {
  'CLASSIC': (Color(0xFF475569), Color(0xFF1E293B), Colors.white),
  'SILVER': (Color(0xFFCBD5E1), Color(0xFF64748B), Color(0xFF0F172A)),
  'GOLD': (Color(0xFFFBBF24), Color(0xFFD97706), Color(0xFF451A03)),
  'PLATINUM': (Color(0xFFE4E4E7), Color(0xFFA1A1AA), Color(0xFF18181B)),
  'SIGNATURE': (Color(0xFF047857), Color(0xFF134E4A), Colors.white),
  'IMPERIAL': (Color(0xFF3730A3), Color(0xFF3B0764), Colors.white),
  'LEGACY': (Color(0xFF1C1917), Colors.black, Colors.white),
};

class DigitalMembershipCard extends StatelessWidget {
  final String name;
  final String memberNumber;
  final String? investorId;
  final String? shareholderId;
  final String tier;
  final String status;
  final String cardNumber;

  /// ACTIVE card hole QR er link, na hole null (tokhon status dekhay)
  final String? verifyUrl;
  final int diamonds;
  final int stars;
  final bool legacy;

  const DigitalMembershipCard({
    super.key,
    required this.name,
    required this.memberNumber,
    required this.investorId,
    required this.shareholderId,
    required this.tier,
    required this.status,
    required this.cardNumber,
    required this.verifyUrl,
    required this.diamonds,
    required this.stars,
    required this.legacy,
  });

  @override
  Widget build(BuildContext context) {
    final c = membershipTierColors[tier] ?? membershipTierColors['CLASSIC']!;
    final fg = c.$3;
    final label = tierLabels[tier];
    final marks = [
      if (legacy) 'Legacy',
      '$diamonds Diamond${diamonds == 1 ? '' : 's'}',
      '$stars Star${stars == 1 ? '' : 's'}',
    ].join(' · ');

    return AspectRatio(
      aspectRatio: 1.62,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c.$1, c.$2], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: c.$2.withAlpha(90), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Semantics(
          label: '${label?.$1 ?? tier} membership card for $name, member ID $memberNumber',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('BINIYOG CLUB',
                            style: TextStyle(
                                fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 2.2, color: fg.withAlpha(205))),
                        const SizedBox(height: 2),
                        Text(label?.$1 ?? tier,
                            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: fg)),
                      ],
                    ),
                  ),
                  if (verifyUrl != null)
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(7)),
                      child: QrImageView(
                        data: verifyUrl!,
                        version: QrVersions.auto,
                        size: 72,
                        padding: EdgeInsets.zero,
                        backgroundColor: Colors.white,
                        semanticsLabel: 'Card verification QR code',
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withAlpha(50), borderRadius: BorderRadius.circular(6)),
                      child: Text(status.toLowerCase(),
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
                    ),
                ],
              ),
              const Spacer(),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: fg, height: 1.2)),
              Text(memberNumber,
                  style: TextStyle(fontSize: 13, fontFamily: 'monospace', color: fg.withAlpha(230))),
              if (investorId != null || shareholderId != null) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    if (investorId != null)
                      Text('Investor $investorId',
                          style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: fg.withAlpha(225))),
                    if (shareholderId != null)
                      Text('Shareholder $shareholderId',
                          style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: fg.withAlpha(225))),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(marks,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: fg.withAlpha(205))),
                  ),
                  const SizedBox(width: 8),
                  Text(cardNumber, style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: fg.withAlpha(180))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════
// HOME STRIP — website er components/membership/membership-summary.tsx
// Tier, Member ID, duto ID ar duto point (kokhono mishe na). Chaple
// Membership page khule.
// ═════════════════════════════════════════════════════════════
class MembershipStrip extends StatelessWidget {
  final MyMembership data;

  const MembershipStrip({super.key, required this.data});

  /// Website er motoi: programme chalu, ar member ba kono tier ache tobei dekhay
  static bool shouldShow(MyMembership? d) => d != null && d.policyActive && (d.isMember || d.primaryTier != null);

  @override
  Widget build(BuildContext context) {
    final d = data;
    final tier = d.primaryTier;
    final colors = membershipTierColors[tier] ?? membershipTierColors['CLASSIC']!;
    final label = tierLabels[tier];
    final tierName = label == null ? LanguageService.tr('Member', 'মেম্বার') : LanguageService.tr(label.$1, label.$2);

    Widget idLine(String role, String id, int points) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(role, style: const TextStyle(fontSize: 11.5, color: BC.mutedForeground)),
          ),
          Expanded(
            child: Text(id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: BC.foreground)),
          ),
          Text(LanguageService.tr('${groupedNumber(points)} pts', '${groupedNumber(points)} পয়েন্ট'),
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: BC.primary)),
        ],
      ),
    );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MembershipPage())),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BC.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 24,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [colors.$1, colors.$2]),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Icon(Icons.badge_outlined, size: 14, color: colors.$3),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tierName,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: BC.foreground)),
                        if (d.memberNumber != null)
                          Text(d.memberNumber!,
                              style: const TextStyle(
                                  fontSize: 11.5, fontFamily: 'monospace', color: BC.mutedForeground)),
                      ],
                    ),
                  ),
                  Text(LanguageService.tr('Membership card', 'মেম্বারশিপ কার্ড'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BC.primary)),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: BC.primary),
                ],
              ),
              if (d.investorId != null || d.shareholderId != null) ...[
                const SizedBox(height: 6),
                const Divider(height: 1, color: BC.border),
                const SizedBox(height: 3),
                if (d.investorId != null)
                  idLine(LanguageService.tr('Investor', 'ইনভেস্টর'), d.investorId!, d.investor.points),
                if (d.shareholderId != null)
                  idLine(LanguageService.tr('Shareholder', 'শেয়ারহোল্ডার'), d.shareholderId!, d.shareholder.points),
              ],
              if (d.status == 'PENDING_REVIEW') ...[
                const SizedBox(height: 6),
                Text(LanguageService.tr('Verification in progress', 'যাচাই চলছে'),
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: BC.chart4Deep)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}