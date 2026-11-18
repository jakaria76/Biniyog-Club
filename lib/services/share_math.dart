// Website er lib/shares/share-math.ts ar coupon-math.ts er Dart rup.
//
// Taka shob somoy poysa (int) te — kono float hishab nei. Share purno shonkha;
// share er dam diye bhag na gele amount bad, gol kora hoy na.

import 'installment_schedule.dart' show tkPaisa;

typedef Tr = String Function(String en, String bn);

/// "300000", "3,00,000", "1500.50" → poysa; bhul hole null
int? parseBdtToPaisa(String? input) {
  if (input == null) return null;
  final clean = input.replaceAll(RegExp(r'[,\s৳]'), '').replaceFirst(RegExp(r'^BDT', caseSensitive: false), '');
  final m = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$').firstMatch(clean);
  if (m == null) return null;
  final whole = int.tryParse(m.group(1)!);
  if (whole == null) return null;
  final frac = int.parse((m.group(2) ?? '').padRight(2, '0'));
  return whole * 100 + frac;
}

/// DB er Decimal (num / "1234.50") → poysa
int decimalToPaisa(dynamic v) {
  if (v == null) return 0;
  if (v is num) return (v * 100).round();
  return parseBdtToPaisa(v.toString()) ?? ((double.tryParse(v.toString()) ?? 0) * 100).round();
}

/// "1234.50" — Decimal column e lekhar jonno
String paisaToDecimalString(int paisa) {
  final sign = paisa < 0 ? '-' : '';
  final a = paisa.abs();
  return '$sign${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
}

/// "1234" ba "1234.5" — input box e dekhanor jonno
String paisaToInput(int paisa) {
  final s = paisaToDecimalString(paisa);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s.replaceFirst(RegExp(r'0$'), '');
}

String formatBdtPaisa(int paisa) => tkPaisa(paisa);

/// 1,00,000 (lakh er moto)
String formatShares(int n) {
  final s = n.abs().toString();
  if (s.length <= 3) return '${n < 0 ? '-' : ''}$s';
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${n < 0 ? '-' : ''}${parts.join(',')},${s.substring(s.length - 3)}';
}

/// Offering er niyom (website OfferingRules)
class OfferingRules {
  final String status;
  final int pricePaisa;
  final int minInvestmentPaisa;
  final int? minSharesPerPurchase;
  final int? maxSharesPerInvestor;

  /// "YYYY-MM-DD" (Dhaka)
  final String purchaseStartDate;
  final String? purchaseEndDate;

  const OfferingRules({
    required this.status,
    required this.pricePaisa,
    required this.minInvestmentPaisa,
    this.minSharesPerPurchase,
    this.maxSharesPerInvestor,
    required this.purchaseStartDate,
    this.purchaseEndDate,
  });
}

/// Shob cheye kom koyta share kena jay (min amount ar min share theke)
int minSharesFor(OfferingRules o) {
  if (o.pricePaisa <= 0) return 1;
  final byAmount = (o.minInvestmentPaisa + o.pricePaisa - 1) ~/ o.pricePaisa;
  var m = 1;
  if (byAmount > m) m = byAmount;
  if ((o.minSharesPerPurchase ?? 0) > m) m = o.minSharesPerPurchase!;
  return m;
}

/// Aj kena jay na keno — null hole kena jay (website offeringClosedReason)
String? offeringClosedReason(OfferingRules o, String today, Tr tr) {
  if (o.status == 'DRAFT') return tr('This share offering is not open yet', 'এই শেয়ার অফার এখনো খোলেনি');
  if (o.status == 'PAUSED') return tr('This share offering is paused', 'এই শেয়ার অফার সাময়িক বন্ধ');
  if (o.status == 'CLOSED') return tr('This share offering is closed', 'এই শেয়ার অফার বন্ধ');
  if (o.status != 'ACTIVE') return tr('This share offering is not open', 'এই শেয়ার অফার খোলা নেই');
  if (today.compareTo(o.purchaseStartDate) < 0) {
    return tr('Share purchases open on ${o.purchaseStartDate}', 'শেয়ার কেনা শুরু হবে ${o.purchaseStartDate}');
  }
  if (o.purchaseEndDate != null && today.compareTo(o.purchaseEndDate!) > 0) {
    return tr('The share purchase period has ended', 'শেয়ার কেনার সময় শেষ');
  }
  return null;
}

class PurchaseCheck {
  final int shares;
  final int totalPaisa;
  final List<String> errors;
  const PurchaseCheck(this.shares, this.totalPaisa, this.errors);
}

/// Notun kenar shob niyom (website checkPurchase). amountPaisa ba shares — je ta user likheche.
PurchaseCheck checkPurchase(
    OfferingRules o, {
      required bool byAmount,
      int? amountPaisa,
      int? shares,
      required int available,
      required int heldByInvestor,
      required String today,
      required Tr tr,
    }) {
  final errors = <String>[];
  final closed = offeringClosedReason(o, today, tr);
  if (closed != null) errors.add(closed);

  var n = 0;
  var total = 0;
  if (byAmount) {
    if (amountPaisa == null || amountPaisa <= 0) {
      errors.add(tr('Enter a valid amount', 'সঠিক পরিমাণ লিখুন'));
    } else {
      n = o.pricePaisa > 0 ? amountPaisa ~/ o.pricePaisa : 0;
      total = amountPaisa;
      final exact = n * o.pricePaisa == amountPaisa;
      if (!exact) {
        final lower = n * o.pricePaisa;
        final upper = (n + 1) * o.pricePaisa;
        errors.add(n > 0
            ? tr(
            "${formatBdtPaisa(amountPaisa)} doesn't buy a whole number of shares at ${formatBdtPaisa(o.pricePaisa)} each — enter ${formatBdtPaisa(lower)} (${formatShares(n)} shares) or ${formatBdtPaisa(upper)} (${formatShares(n + 1)} shares)",
            '${formatBdtPaisa(amountPaisa)} দিয়ে পুরো সংখ্যার শেয়ার হয় না (প্রতিটি ${formatBdtPaisa(o.pricePaisa)}) — ${formatBdtPaisa(lower)} (${formatShares(n)} টি) বা ${formatBdtPaisa(upper)} (${formatShares(n + 1)} টি) লিখুন')
            : tr('One share costs ${formatBdtPaisa(o.pricePaisa)}', 'একটি শেয়ারের দাম ${formatBdtPaisa(o.pricePaisa)}'));
      }
    }
  } else {
    if (shares == null || shares <= 0) {
      errors.add(tr('Enter a whole number of shares', 'শেয়ারের সংখ্যা লিখুন'));
    } else {
      n = shares;
      total = shares * o.pricePaisa;
    }
  }

  if (n > 0 && errors.isEmpty) {
    if (total < o.minInvestmentPaisa) {
      errors.add(tr('The minimum investment is ${formatBdtPaisa(o.minInvestmentPaisa)}',
          'সর্বনিম্ন বিনিয়োগ ${formatBdtPaisa(o.minInvestmentPaisa)}'));
    }
    if (o.minSharesPerPurchase != null && n < o.minSharesPerPurchase!) {
      errors.add(tr('Buy at least ${formatShares(o.minSharesPerPurchase!)} shares',
          'কমপক্ষে ${formatShares(o.minSharesPerPurchase!)} টি শেয়ার কিনুন'));
    }
    final max = o.maxSharesPerInvestor;
    if (max != null && heldByInvestor + n > max) {
      final left = (max - heldByInvestor) < 0 ? 0 : max - heldByInvestor;
      errors.add(heldByInvestor > 0
          ? tr('Each investor may hold at most ${formatShares(max)} shares — you can buy ${formatShares(left)} more',
          'একজন সর্বোচ্চ ${formatShares(max)} টি শেয়ার রাখতে পারেন — আপনি আর ${formatShares(left)} টি কিনতে পারবেন')
          : tr('Each investor may buy at most ${formatShares(max)} shares',
          'একজন সর্বোচ্চ ${formatShares(max)} টি শেয়ার কিনতে পারেন'));
    }
    if (n > available) {
      errors.add(available > 0
          ? tr('Only ${formatShares(available)} shares are left', 'মাত্র ${formatShares(available)} টি শেয়ার বাকি')
          : tr('All shares in this offering have been taken', 'এই অফারের সব শেয়ার নেওয়া হয়ে গেছে'));
    }
  }
  return PurchaseCheck(n, total, errors.toSet().toList());
}

/// Order number, jemon SPO-ZCS-00012 (website orderNumber) — shudhu code er ongsho
String orderCodeOf(String? projectCode) {
  final c = (projectCode ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (c.isEmpty) return 'SHR';
  return c.length > 6 ? c.substring(0, 6) : c;
}

// ═══════════════════════════════════════════════════════════
// COUPON (website coupon-math.ts)
// ═══════════════════════════════════════════════════════════
class CouponTerms {
  final String code;

  /// FIXED ba PERCENT
  final String discountType;

  /// FIXED: poysa. PERCENT: shotangsher shotangsho (2857 = 28.57%)
  final int discountValue;
  final int? maxDiscountPaisa;
  final int? minShares;
  final int? maxShares;

  const CouponTerms({
    required this.code,
    required this.discountType,
    required this.discountValue,
    this.maxDiscountPaisa,
    this.minShares,
    this.maxShares,
  });
}

String normalizeCouponCode(String input) => input.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

String describeCoupon(CouponTerms c, Tr tr) {
  if (c.discountType == 'FIXED') return tr('${formatBdtPaisa(c.discountValue)} off', '${formatBdtPaisa(c.discountValue)} ছাড়');
  final v = c.discountValue / 100;
  final pct = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  return c.maxDiscountPaisa != null
      ? tr('$pct% off (up to ${formatBdtPaisa(c.maxDiscountPaisa!)})', '$pct% ছাড় (সর্বোচ্চ ${formatBdtPaisa(c.maxDiscountPaisa!)})')
      : tr('$pct% off', '$pct% ছাড়');
}

class CouponQuote {
  final int grossPaisa;
  final int discountPaisa;
  final int payablePaisa;
  final List<String> errors;
  const CouponQuote(this.grossPaisa, this.discountPaisa, this.payablePaisa, this.errors);
}

CouponQuote applyCoupon(CouponTerms c, int shares, int pricePaisa, Tr tr) {
  final gross = shares * pricePaisa;
  final errors = <String>[];
  if (c.minShares != null && shares < c.minShares!) {
    errors.add(tr('Coupon ${c.code} needs at least ${formatShares(c.minShares!)} shares',
        'কুপন ${c.code} এর জন্য কমপক্ষে ${formatShares(c.minShares!)} টি শেয়ার লাগবে'));
  }
  if (c.maxShares != null && shares > c.maxShares!) {
    errors.add(tr('Coupon ${c.code} applies to at most ${formatShares(c.maxShares!)} shares',
        'কুপন ${c.code} সর্বোচ্চ ${formatShares(c.maxShares!)} টি শেয়ারে চলে'));
  }
  var discount = c.discountType == 'FIXED' ? c.discountValue : (gross * c.discountValue) ~/ 10000;
  if (c.discountType == 'PERCENT' && c.maxDiscountPaisa != null && discount > c.maxDiscountPaisa!) {
    discount = c.maxDiscountPaisa!;
  }
  if (gross > 0 && discount >= gross) {
    errors.add(tr('Coupon ${c.code} is worth more than this order — buy more shares to use it',
        'কুপন ${c.code} এই অর্ডারের চেয়ে বেশি — ব্যবহার করতে আরও শেয়ার কিনুন'));
  }
  if (errors.isNotEmpty) return CouponQuote(gross, 0, gross, errors);
  return CouponQuote(gross, discount, gross - discount, errors);
}

/// Coupon ei investor ei offering e aj chalano jay kina (website couponUnusableReason).
/// Bhul code — shob khetre ek-i kotha, jate code anuman kora na jay.
String? couponUnusableReason({
  required String status,
  required String couponOfferingId,
  required String offeringId,
  required String? assignedUserId,
  required String userId,
  required int maxUses,
  required int usedCount,
  required String? validFrom,
  required String? validUntil,
  required String today,
  required Tr tr,
}) {
  final invalid = tr("This coupon code isn't valid for this purchase", 'এই কুপন কোডটি এই কেনায় চলবে না');
  if (status != 'ACTIVE') return invalid;
  if (couponOfferingId != offeringId) return invalid;
  if (assignedUserId != null && assignedUserId.isNotEmpty && assignedUserId != userId) return invalid;
  if (validFrom != null && today.compareTo(validFrom) < 0) return invalid;
  if (validUntil != null && today.compareTo(validUntil) > 0) return tr('This coupon has expired', 'এই কুপনের মেয়াদ শেষ');
  if (usedCount >= maxUses) return tr('This coupon has already been used', 'এই কুপন আগেই ব্যবহার হয়েছে');
  return null;
}