import 'dart:convert';

/// Website er src/lib/membership/policy.ts (Card & Points Policy v1.2,
/// Phase 2 amendment shoho) — hubohu ek-i niyom. Database nei, shudhu hishab.
///
/// Duto alada track, kokhono mishe na:
///   Investor     point = floor(jachai kora active biniyog / ৳20,000)
///                tier  = ৳1,00,000 er niche CLASSIC, theke SILVER
///   Shareholder  point = jachai kora eligible share (1 share = 1 point)
///                tier  = GOLD / PLATINUM / SIGNATURE / IMPERIAL
/// Legacy shudhu shomman (High Authority approve kore).
/// Taka paisa (int) e, share puro shonkha.

// ─── Tier ─────────────────────────────────────────────────────────────────────

const Map<String, (String, String)> tierLabels = {
  'CLASSIC': ('Classic', 'ক্লাসিক'),
  'SILVER': ('Silver', 'সিলভার'),
  'GOLD': ('Gold', 'গোল্ড'),
  'PLATINUM': ('Platinum', 'প্লাটিনাম'),
  'SIGNATURE': ('Signature', 'সিগনেচার'),
  'IMPERIAL': ('Imperial', 'ইম্পেরিয়াল'),
  'LEGACY': ('Legacy', 'লেগেসি'),
};

/// Article 11 er choyta segment (Diamond)
const Map<String, String> recognitionSegments = {
  'MARINERS': 'Mariners Group',
  'MOHS': 'MOHS Group',
  'MARINOZZ': 'Marinozz Group',
  'COMMUNITY_VENTURES': 'Community Ventures',
  'VENTURE_ALLIANCES': 'Venture Alliance',
  'VENTURE_SYSTEMS': 'Venture Systems',
};

/// Membership.status
const Map<String, (String, String)> membershipStatusLabels = {
  'PENDING_REVIEW': ('Verification in progress', 'যাচাই চলছে'),
  'VERIFIED': ('Verified', 'যাচাইকৃত'),
  'SUSPENDED': ('Suspended', 'স্থগিত'),
};

// ─── Number format (website er formatShares — lakh grouping) ─────────────────

String groupedNumber(num n) {
  final s = n.abs().truncate().toString();
  final sign = n < 0 ? '-' : '';
  if (s.length <= 3) return '$sign$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '$sign${parts.join(',')},$last3';
}

/// "৳1,25,000" — poysha thakle "৳1,25,000.50"
String fmtTaka(num bdt) {
  final paisa = (bdt * 100).round();
  final whole = groupedNumber(paisa ~/ 100);
  final frac = paisa.abs() % 100;
  return frac == 0 ? '৳$whole' : '৳$whole.${frac.toString().padLeft(2, '0')}';
}

int paisaOf(dynamic v) {
  if (v is num) return (v * 100).round();
  final d = double.tryParse(v?.toString() ?? '');
  return d == null ? 0 : (d * 100).round();
}

// ─── Rules (ek policy version) ────────────────────────────────────────────────

class MembershipRules {
  final int pointUnitBdt;
  final int silverFromBdt;
  final List<String>? eligibleProjectIds;
  final List<String> excludedProjectIds;

  /// (GOLD, 1), (PLATINUM, 200001), …
  final List<(String, int)> shareTiers;
  final bool onlyMembershipEligibleOfferings;
  final List<String> excludedCompanyKeys;
  final bool autoStars;
  final List<String>? starProjectIds;
  final bool boatClub;

  const MembershipRules({
    this.pointUnitBdt = 20000,
    this.silverFromBdt = 100000,
    this.eligibleProjectIds,
    this.excludedProjectIds = const [],
    this.shareTiers = const [('GOLD', 1), ('PLATINUM', 200001), ('SIGNATURE', 500001), ('IMPERIAL', 1000001)],
    this.onlyMembershipEligibleOfferings = true,
    this.excludedCompanyKeys = const [],
    this.autoStars = true,
    this.starProjectIds,
    this.boatClub = true,
  });

  /// membership_policy_versions.rules (jsonb). Kono ghor na thakle website er DEFAULT_RULES.
  factory MembershipRules.fromJson(dynamic raw) {
    dynamic r = raw;
    if (r is String) {
      try {
        r = jsonDecode(r);
      } catch (_) {
        r = null;
      }
    }
    if (r is! Map) return const MembershipRules();
    Map m(dynamic v) => v is Map ? v : const {};
    List<String>? ids(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : null;
    int n(dynamic v, int fb) => v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? fb);
    bool b(dynamic v, bool fb) => v is bool ? v : fb;

    const def = MembershipRules();
    final inv = m(r['investor']);
    final sh = m(r['shareholder']);
    final rec = m(r['recognition']);
    final ex = m(r['exceptions']);
    final tiers = <(String, int)>[];
    if (sh['tiers'] is List) {
      for (final t in sh['tiers'] as List) {
        if (t is Map && t['code'] != null) tiers.add((t['code'].toString(), n(t['minShares'], 1)));
      }
    }
    return MembershipRules(
      pointUnitBdt: n(inv['pointUnitBdt'], def.pointUnitBdt),
      silverFromBdt: n(inv['silverFromBdt'], def.silverFromBdt),
      eligibleProjectIds: ids(inv['eligibleProjectIds']),
      excludedProjectIds: ids(inv['excludedProjectIds']) ?? const [],
      shareTiers: tiers.length == 4 ? tiers : def.shareTiers,
      onlyMembershipEligibleOfferings: b(sh['onlyMembershipEligibleOfferings'], true),
      excludedCompanyKeys: ids(sh['excludedCompanyKeys']) ?? const [],
      autoStars: b(rec['autoStars'], true),
      starProjectIds: ids(rec['starProjectIds']),
      boatClub: b(ex['boatClub'], true),
    );
  }
}

// ─── Investor track ───────────────────────────────────────────────────────────

class MemberInvestment {
  final String id;
  final String projectId;
  final String projectTitle;
  final String status;
  final String projectType;
  final int amountPaisa;

  /// Finance-approved payment (paisa)
  final int verifiedPaisa;
  final int refundedPaisa;
  final bool excluded;

  /// eligiblePrincipalPaisa er fol (track hishab korar por bose)
  int eligiblePaisa = 0;

  MemberInvestment({
    required this.id,
    required this.projectId,
    required this.projectTitle,
    required this.status,
    required this.projectType,
    required this.amountPaisa,
    required this.verifiedPaisa,
    this.refundedPaisa = 0,
    this.excluded = false,
  });
}

const Set<String> _activePrincipal = {'ACTIVE', 'MATURED'};

/// Article 5: ekta investment er jachai kora eligible mul taka.
/// Share kena (SHARE_BUYING project) ekhane kokhono gona hoy na.
int eligiblePrincipalPaisa(MemberInvestment inv, MembershipRules rules) {
  if (inv.projectType != 'REGULAR_INVESTMENT' || inv.excluded) return 0;
  if (rules.excludedProjectIds.contains(inv.projectId)) return 0;
  final only = rules.eligibleProjectIds;
  if (only != null && !only.contains(inv.projectId)) return 0;
  int base;
  if (_activePrincipal.contains(inv.status)) {
    // Active howa mane finance puro taka jachai koreche
    base = inv.amountPaisa;
  } else if (inv.status == 'PAYMENT_PENDING') {
    // Kisti cholche: shudhu joto jachai hoyeche
    base = inv.verifiedPaisa < inv.amountPaisa ? inv.verifiedPaisa : inv.amountPaisa;
  } else {
    return 0; // PENDING, CANCELLED, REFUNDED, COMPLETED (mul taka ferot)
  }
  final v = base - inv.refundedPaisa;
  return v > 0 ? v : 0;
}

class InvestorTrack {
  final int eligiblePaisa;
  final int points;
  final String? tier; // CLASSIC / SILVER / null
  final List<MemberInvestment> lines;
  const InvestorTrack(this.eligiblePaisa, this.points, this.tier, this.lines);
}

InvestorTrack investorTrack(List<MemberInvestment> list, MembershipRules rules) {
  var total = 0;
  for (final i in list) {
    i.eligiblePaisa = eligiblePrincipalPaisa(i, rules);
    total += i.eligiblePaisa;
  }
  final unit = rules.pointUnitBdt * 100;
  final points = unit > 0 ? total ~/ unit : 0;
  final tier = total <= 0 ? null : (total >= rules.silverFromBdt * 100 ? 'SILVER' : 'CLASSIC');
  return InvestorTrack(total, points, tier, list);
}

// ─── Shareholder track ────────────────────────────────────────────────────────

class MemberHolding {
  final String offeringId;
  final String? companyKey;
  final String companyName;
  final String projectTitle;
  final bool membershipEligible;

  /// Net ledger: verified allotment − cancel − transfer
  final int verifiedShares;
  final int disputedShares;
  int eligibleShares = 0;

  MemberHolding({
    required this.offeringId,
    required this.companyKey,
    required this.companyName,
    required this.projectTitle,
    required this.membershipEligible,
    required this.verifiedShares,
    this.disputedShares = 0,
  });
}

int eligibleShares(MemberHolding h, MembershipRules rules) {
  if (rules.onlyMembershipEligibleOfferings && !h.membershipEligible) return 0;
  if (h.companyKey != null && rules.excludedCompanyKeys.contains(h.companyKey)) return 0;
  final v = h.verifiedShares - h.disputedShares;
  return v > 0 ? v : 0;
}

class ShareholderTrack {
  final int shares;
  final int points;
  final String? tier;
  final List<MemberHolding> lines;
  const ShareholderTrack(this.shares, this.points, this.tier, this.lines);
}

ShareholderTrack shareholderTrack(List<MemberHolding> list, MembershipRules rules) {
  var total = 0;
  for (final h in list) {
    h.eligibleShares = eligibleShares(h, rules);
    total += h.eligibleShares;
  }
  String? tier;
  if (total > 0) {
    for (final t in rules.shareTiers.reversed) {
      if (total >= t.$2) {
        tier = t.$1;
        break;
      }
    }
  }
  return ShareholderTrack(total, total, tier, list);
}

/// "1 – 2,00,000" — protita shareholder tier er shima
List<(String, int, int?)> shareholderTierBands(MembershipRules rules) {
  final t = rules.shareTiers;
  return [
    for (var i = 0; i < t.length; i++) (t[i].$1, t[i].$2, i + 1 < t.length ? t[i + 1].$2 - 1 : null),
  ];
}

// ─── Primary card tier ────────────────────────────────────────────────────────

/// Article 2: Legacy > shareholder tier > investor tier > Boat Club (Classic)
String? primaryTier({String? investor, String? shareholder, required bool legacy, required bool boatClubException}) {
  if (legacy) return 'LEGACY';
  if (shareholder != null) return shareholder;
  if (investor != null) return investor;
  if (boatClubException) return 'CLASSIC';
  return null;
}

// ─── Fol: website er getMyMembership ──────────────────────────────────────────

class MemberStar {
  final String projectTitle;
  final bool active; // false = ENDED (lifetime)
  const MemberStar(this.projectTitle, this.active);
}

class MemberCard {
  final String kind; // DIGITAL / PHYSICAL
  final String status; // PENDING / ACTIVE / SUSPENDED
  final String cardNumber;
  final String tierAtIssue;
  final String? fulfilmentStatus;
  final bool complimentary;

  /// Shudhu ACTIVE digital card e — QR e eta thake
  final String? verifyUrl;

  const MemberCard({
    required this.kind,
    required this.status,
    required this.cardNumber,
    required this.tierAtIssue,
    this.fulfilmentStatus,
    this.complimentary = false,
    this.verifyUrl,
  });
}

class MyMembership {
  /// false = programme ekhono shuru hoyni (kono ACTIVE policy nei)
  final bool policyActive;
  final String? policyVersion;
  final MembershipRules rules;

  // Membership (null = ekhono member na)
  final String? memberNumber;
  final String? status;
  final String? name;
  final String? investorId;
  final String? shareholderId;

  final InvestorTrack investor;
  final ShareholderTrack shareholder;
  final bool legacy;
  final bool boatClubException;
  final String? primaryTier;

  final List<String> diamonds; // segment label
  final List<MemberStar> stars;
  final MemberCard? digitalCard;
  final MemberCard? physicalCard;

  const MyMembership({
    required this.policyActive,
    this.policyVersion,
    this.rules = const MembershipRules(),
    this.memberNumber,
    this.status,
    this.name,
    this.investorId,
    this.shareholderId,
    this.investor = const InvestorTrack(0, 0, null, []),
    this.shareholder = const ShareholderTrack(0, 0, null, []),
    this.legacy = false,
    this.boatClubException = false,
    this.primaryTier,
    this.diamonds = const [],
    this.stars = const [],
    this.digitalCard,
    this.physicalCard,
  });

  bool get isMember => memberNumber != null;
  int get activeStars => stars.where((s) => s.active).length;
  int get lifetimeStars => stars.length;
}