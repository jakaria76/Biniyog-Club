import 'package:flutter/material.dart';

import '../../../services/language_service.dart';

// ═══════════════════════════════════════════════════════════
// Project er lekha — website er hubohu (biniyogclub.com):
//   lib/project-categories.ts, components/shared/project-card.tsx,
//   app/(public)/projects/[slug]/page.tsx, lib/markdown-text.ts,
//   lib/financial/return-range.ts, lib/deadline.ts, lib/group-logos.ts
// Projects list ar Project details — dui page ei file theke nebe.
// ═══════════════════════════════════════════════════════════
class ProjectLabels {
  ProjectLabels._();

  static const String websiteBase = 'https://www.biniyogclub.com';

  /// Website er PROJECT_CATEGORY_LABELS — notun gulo age, purono gulo pore
  static const Map<String, String> categoryLabels = {
    'FMCG': 'FMCG',
    'FOOD_AGRO': 'Food & Agro',
    'FOOD_HOSPITALITY': 'Food & Hospitality',
    'FURNITURE_DECOR': 'Furniture & Decor',
    'PRINTING_PACKAGING': 'Printing & Packaging',
    'COMMUNITY': 'Community',
    'OTHER': 'Other',
    'REAL_ESTATE': 'Real Estate',
    'TRADE_FINANCE': 'Trade Finance',
    'SME': 'SME',
    'TECHNOLOGY': 'Technology',
    'INFRASTRUCTURE': 'Infrastructure',
  };

  static const Map<String, String> _categoryBn = {
    'FMCG': 'এফএমসিজি',
    'FOOD_AGRO': 'খাদ্য ও কৃষি',
    'FOOD_HOSPITALITY': 'খাদ্য ও আতিথেয়তা',
    'FURNITURE_DECOR': 'আসবাব ও সাজসজ্জা',
    'PRINTING_PACKAGING': 'প্রিন্টিং ও প্যাকেজিং',
    'COMMUNITY': 'কমিউনিটি',
    'OTHER': 'অন্যান্য',
    'REAL_ESTATE': 'রিয়েল এস্টেট',
    'TRADE_FINANCE': 'ট্রেড ফাইন্যান্স',
    'SME': 'এসএমই',
    'TECHNOLOGY': 'প্রযুক্তি',
    'INFRASTRUCTURE': 'অবকাঠামো',
  };

  /// Website er categoryLabel(): OTHER hole admin er likha nam
  static String category(String category, [String? customCategory]) {
    final custom = customCategory?.trim() ?? '';
    if (category == 'OTHER' && custom.isNotEmpty) return custom;
    final en = categoryLabels[category] ?? category;
    return LanguageService.tr(en, _categoryBn[category] ?? en);
  }

  /// Project card er category icon (website er CATEGORY_META er moto)
  static IconData categoryIcon(String category) {
    switch (category) {
      case 'REAL_ESTATE':
        return Icons.apartment_rounded;
      case 'TRADE_FINANCE':
        return Icons.paid_outlined;
      case 'SME':
        return Icons.work_outline_rounded;
      case 'TECHNOLOGY':
        return Icons.memory_rounded;
      case 'INFRASTRUCTURE':
        return Icons.account_balance_outlined;
      case 'FMCG':
        return Icons.shopping_basket_outlined;
      case 'FOOD_AGRO':
        return Icons.grass_rounded;
      case 'FOOD_HOSPITALITY':
        return Icons.restaurant_rounded;
      case 'FURNITURE_DECOR':
        return Icons.chair_outlined;
      case 'PRINTING_PACKAGING':
        return Icons.inventory_2_outlined;
      case 'COMMUNITY':
        return Icons.groups_outlined;
      default:
        return Icons.auto_awesome_outlined;
    }
  }

  /// Project card er status badge — website: Active / Funded / Matured / Completed / Inactive
  static String cardStatus(String status) {
    switch (status) {
      case 'FUNDRAISING':
        return LanguageService.tr('Active', 'চলমান');
      case 'FUNDED':
        return LanguageService.tr('Funded', 'অর্থায়িত');
      case 'ACTIVE':
        return LanguageService.tr('Matured', 'মেয়াদপূর্ণ');
      case 'COMPLETED':
        return LanguageService.tr('Completed', 'সম্পন্ন');
      default:
        return LanguageService.tr('Inactive', 'বন্ধ');
    }
  }

  /// Card er niche (FUNDRAISING na hole) — website er STATUS_LABELS
  static String cardFooterStatus(String status) {
    switch (status) {
      case 'FUNDRAISING':
        return LanguageService.tr('Open for Investment', 'বিনিয়োগের জন্য খোলা');
      case 'FUNDED':
        return LanguageService.tr('Fully Funded', 'সম্পূর্ণ অর্থায়িত');
      case 'ACTIVE':
        return LanguageService.tr('Matured, earning profit', 'মেয়াদপূর্ণ, লাভ আসছে');
      case 'COMPLETED':
        return LanguageService.tr('Completed', 'সম্পন্ন');
      case 'CANCELLED':
        return LanguageService.tr('Cancelled', 'বাতিল');
      default:
        return status;
    }
  }

  /// Details page er status — website: Open for Investment / Fully Funded / Matured ...
  static String detailStatus(String status) {
    switch (status) {
      case 'FUNDRAISING':
        return LanguageService.tr('Open for Investment', 'বিনিয়োগের জন্য খোলা');
      case 'FUNDED':
        return LanguageService.tr('Fully Funded', 'সম্পূর্ণ অর্থায়িত');
      case 'ACTIVE':
        return LanguageService.tr('Matured', 'মেয়াদপূর্ণ');
      case 'COMPLETED':
        return LanguageService.tr('Completed', 'সম্পন্ন');
      case 'CANCELLED':
        return LanguageService.tr('Cancelled', 'বাতিল');
      default:
        return status;
    }
  }

  static String returnType(String t) {
    switch (t) {
      case 'FIXED_RETURN':
        return LanguageService.tr('Fixed Return', 'নির্দিষ্ট রিটার্ন');
      case 'PROFIT_SHARE':
        return LanguageService.tr('Profit Share', 'মুনাফা ভাগ');
      case 'HYBRID':
        return LanguageService.tr('Hybrid', 'হাইব্রিড');
      case '':
        return '—';
      default:
        return t;
    }
  }

  static String riskLevel(String r) {
    switch (r) {
      case 'LOW':
        return LanguageService.tr('Low', 'কম');
      case 'MEDIUM':
        return LanguageService.tr('Medium', 'মাঝারি');
      case 'HIGH':
        return LanguageService.tr('High', 'বেশি');
      default:
        return r;
    }
  }

  /// Website er payoutPeriodLabel()
  static String payoutPeriod(int months) {
    if (months <= 0) return LanguageService.tr('At maturity', 'মেয়াদ শেষে');
    if (months == 1) return LanguageService.tr('Monthly', 'প্রতি মাসে');
    return LanguageService.tr('Every $months months', 'প্রতি $months মাসে');
  }

  static String updateType(String t) {
    switch (t) {
      case 'GENERAL':
        return LanguageService.tr('General', 'সাধারণ');
      case 'MILESTONE':
        return LanguageService.tr('Milestone', 'মাইলফলক');
      case 'ISSUE':
        return LanguageService.tr('Issue', 'সমস্যা');
      case 'FINANCIAL_REPORT':
        return LanguageService.tr('Financial Report', 'আর্থিক রিপোর্ট');
      default:
        return t;
    }
  }

  // ─── Taka ─────────────────────────────────────────────────

  static String _fixed(double v, int digits) => v.toStringAsFixed(digits);

  /// Project card er moto: ৳1.5 Cr · ৳12.5L · ৳50K
  static String bdtCard(double n) {
    if (n >= 10000000) return '৳${_fixed(n / 10000000, 1)} Cr';
    if (n >= 100000) return '৳${_fixed(n / 100000, 1)}L';
    if (n >= 1000) return '৳${_fixed(n / 1000, 0)}K';
    return '৳${grouped(n)}';
  }

  /// Details page er moto: ৳1.50 Cr · ৳12.50L · ৳50K
  static String bdtShort(double n) {
    if (n >= 10000000) return '৳${_fixed(n / 10000000, 2)} Cr';
    if (n >= 100000) return '৳${_fixed(n / 100000, 2)}L';
    if (n >= 1000) return '৳${_fixed(n / 1000, 0)}K';
    return '৳${grouped(n)}';
  }

  /// ৳12,50,000 — website er toLocaleString("en-BD") (lakh hishebe koma)
  static String bdtFull(double n) => '৳${grouped(n)}';

  static String grouped(double n) {
    final neg = n < 0;
    final s = n.abs().round().toString();
    if (s.length <= 3) return '${neg ? '-' : ''}$s';
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${neg ? '-' : ''}${parts.join(',')},$last3';
  }

  // ─── Return ───────────────────────────────────────────────

  /// returnMin / returnMax 0.16 hishebe ashe. Card e "16–20%", details e "16.0–20.0%"
  static String returnLabel(double min, double max, {int digits = 0}) {
    if (min <= 0 && max <= 0) return '—';
    String p(double r) => (r * 100).toStringAsFixed(digits);
    if (min > 0 && max > 0 && min != max) return '${p(min)}–${p(max)}%';
    return '${p(max > 0 ? max : min)}%';
  }

  /// Card er "Term": 30 diner beshi hole mash, na hole din
  static String term(int days) {
    if (days <= 0) return '—';
    if (days >= 30) {
      final m = (days / 30).round();
      return LanguageService.tr('$m Mo', '$m মাস');
    }
    return LanguageService.tr('${days}d', '$days দিন');
  }

  static int fundingPct(double funded, double goal) {
    if (goal <= 0) return 0;
    return ((funded / goal) * 100).round().clamp(0, 100);
  }

  // ─── Deadline (website er lib/deadline.ts) ───────────────

  /// Card er moto: "12 days left" · "Closes tomorrow" · "Closes today" · "Deadline passed"
  static String countdown(int? days) {
    if (days == null) return '';
    if (days > 1) return LanguageService.tr('$days days left', '$days দিন বাকি');
    if (days == 1) return LanguageService.tr('Closes tomorrow', 'কাল শেষ দিন');
    if (days == 0) return LanguageService.tr('Closes today', 'আজ শেষ দিন');
    return LanguageService.tr('Deadline passed', 'সময় শেষ');
  }

  /// Details er moto: "53 days left to invest · closes December 31, 2026"
  static String deadlineLong(int days, String date) {
    if (days > 1) {
      return LanguageService.tr('$days days left to invest · closes $date', 'বিনিয়োগের আর $days দিন বাকি · শেষ $date');
    }
    if (days == 1) return LanguageService.tr('Closes tomorrow, $date', 'কাল শেষ দিন, $date');
    if (days == 0) return LanguageService.tr('Closes today, $date', 'আজ শেষ দিন, $date');
    return LanguageService.tr('Funding deadline passed on $date', 'বিনিয়োগের শেষ সময় পেরিয়েছে $date');
  }

  static const List<String> _monthsLong = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  /// DB er tarikh (UTC, timezone chara hote pare). Website er moto UTC er
  /// tarikh-i dekhai (deadline DB te tarikh hishebe thake)
  static DateTime? parseDate(dynamic s) {
    final raw = s?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    var t = raw.replaceFirst(' ', 'T');
    if (t.contains('T') && !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(t)) t = '${t}Z';
    final d = DateTime.tryParse(t);
    if (d == null) return null;
    return d.toUtc();
  }

  /// "December 31, 2026" — website er fmtDate; na thakle ''
  static String dateLong(dynamic s) {
    final d = parseDate(s);
    if (d == null) return '';
    return '${_monthsLong[d.month - 1]} ${d.day}, ${d.year}';
  }

  // ─── Group logo (website er /public/Group logos) ─────────

  static const Map<String, String> _groupLogos = {
    'MARINERS': 'Mariners Group logo.png',
    'MOHS': 'MOHS Group logo.png',
    'MARINOZZ': 'Marinozz Group logo.png',
    'COMMUNITY_VENTURES': 'Community Ventures Logo.png',
    'VENTURE_ALLIANCES': 'Venture Alliance Logo.png',
  };

  static String? groupLogoUrl(String? slug) {
    final file = _groupLogos[(slug ?? '').toUpperCase()];
    if (file == null) return null;
    return Uri.encodeFull('$websiteBase/Group logos/$file');
  }

  // ─── Lekha ────────────────────────────────────────────────

  /// Website er markdownToPlainText — card e choto bornona
  static String plainText(String md) {
    return md
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1) ?? '')
        .replaceAll(RegExp(r'^\s{0,3}(#{1,6}|>|[-*+]|\d+\.)\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\|?[\s:|-]+\|[\s:|-]*$', multiLine: true), ' ')
        .replaceAll('|', ' ')
        .replaceAll(RegExp(r'(\*\*|__|\*|_|~~|`)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Website er stripLegacyCategory — risk er shuru te purono "Category: …" line bad
  static String stripLegacyCategory(String riskInfo) {
    return riskInfo.replaceFirst(RegExp(r'^(?:Category: [^\n]*(?:\r?\n|$))+'), '').trim();
  }
}