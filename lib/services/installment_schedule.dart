/// Website er src/lib/payments/installments.ts + lib/financial/proration.ts
/// er je ongsho app e lage — hubohu ek-i niyom.
///
/// - Taka shob somoy paisa (int) e hishab, double e na.
/// - Din mane Bangladesh er calendar din, "YYYY-MM-DD" string.
/// - Jachai hoya (APPROVED) payment kisti 1, 2, 3… kromanushare dhore;
///   tarpor review e thaka (SUBMITTED / UNDER_REVIEW) taka.
/// - Kisti miss hole shudhu "Overdue" — kono jorimana nei.
library;

import 'dart:convert';

int toPaisa(num bdt) => (bdt * 100).round();

/// Ajker Bangladesh din (UTC+6, DST nei), jemon "2026-11-17"
String dhakaDay([DateTime? at]) {
  final d = (at ?? DateTime.now()).toUtc().add(const Duration(hours: 6));
  return _dayString(d.year, d.month, d.day);
}

String _dayString(int y, int m, int d) =>
    '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

/// DB er timestamp (Prisma UTC e rakhe, zone chara ashte pare) → UTC DateTime
DateTime? parseDbTime(dynamic v) {
  var t = v?.toString().trim() ?? '';
  if (t.isEmpty) return null;
  t = t.replaceFirst(' ', 'T');
  if (t.contains('T') && !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(t)) t = '${t}Z';
  return DateTime.tryParse(t)?.toUtc();
}

/// DB er @db.Date ba timestamp theke "YYYY-MM-DD" (website er dateToDay — UTC)
String dayOf(dynamic v) {
  final s = v?.toString().trim() ?? '';
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return s;
  final u = parseDbTime(s);
  if (u == null) return s.length >= 10 ? s.substring(0, 10) : s;
  return _dayString(u.year, u.month, u.day);
}

/// Timestamp → Bangladesh er din (website er dhakaDay), jemon order er tarikh
String dhakaDayOf(dynamic v) {
  final u = parseDbTime(v);
  return u == null ? '' : dhakaDay(u);
}

String addDaysToDay(String day, int n) {
  final d = DateTime.utc(int.parse(day.substring(0, 4)), int.parse(day.substring(5, 7)), int.parse(day.substring(8, 10)))
      .add(Duration(days: n));
  return _dayString(d.year, d.month, d.day);
}

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "1 Dec 2026" (website er fmtDay)
String fmtDay(String day) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(day)) return day.isEmpty ? '—' : day;
  final m = int.parse(day.substring(5, 7));
  return '${int.parse(day.substring(8, 10))} ${_months[m - 1]} ${day.substring(0, 4)}';
}

dynamic _json(dynamic raw) {
  if (raw is String && raw.trim().startsWith('{')) {
    try {
      return jsonDecode(raw);
    } catch (_) {}
  }
  return raw;
}

/// Investment.installmentTerms theke grace din (website er readTerms)
int readGraceDays(dynamic terms) {
  final raw = _json(terms);
  if (raw is Map) {
    final g = raw['graceDays'];
    if (g is int) return g;
    if (g is num && g == g.roundToDouble()) return g.toInt();
  }
  return 0;
}

/// Agiye deya jay kina (readTerms: allowEarly !== false)
bool readAllowEarly(dynamic terms) {
  final raw = _json(terms);
  return !(raw is Map && raw['allowEarly'] == false);
}

/// PAID, PARTIALLY_PAID, PENDING_VERIFICATION, OVERDUE, DUE, UPCOMING
class ScheduleInstallment {
  final int number;
  final String dueDate;
  final int amountPaisa;
  final int paidPaisa;
  final int pendingPaisa;
  final int openPaisa;
  final String status;

  const ScheduleInstallment({
    required this.number,
    required this.dueDate,
    required this.amountPaisa,
    required this.paidPaisa,
    required this.pendingPaisa,
    required this.openPaisa,
    required this.status,
  });
}

class ScheduleSummary {
  final List<ScheduleInstallment> installments;
  final int totalPaisa;
  final int approvedPaisa;
  final int pendingPaisa;
  final int remainingPaisa;
  final double progressPct;

  /// Prothom kisti jar kichu taka ekhono deya baki (review e thaka bad e)
  final ScheduleInstallment? next;
  final int overdueCount;
  final bool fullyPaid;

  const ScheduleSummary({
    required this.installments,
    required this.totalPaisa,
    required this.approvedPaisa,
    required this.pendingPaisa,
    required this.remainingPaisa,
    required this.progressPct,
    required this.next,
    required this.overdueCount,
    required this.fullyPaid,
  });
}

String _status(int amount, int paid, int open, String dueDate, String today, int graceDays) {
  if (paid >= amount) return 'PAID';
  if (open == 0) return 'PENDING_VERIFICATION';
  if (today.compareTo(addDaysToDay(dueDate, graceDays)) > 0) return 'OVERDUE';
  if (today.compareTo(dueDate) >= 0) return 'DUE';
  if (paid > 0) return 'PARTIALLY_PAID';
  return 'UPCOMING';
}

/// rows: (number, dueDate "YYYY-MM-DD", amountBdt)
ScheduleSummary summarizeSchedule(
    List<(int, String, double)> rows,
    double approvedBdt,
    double pendingBdt,
    String today,
    int graceDays,
    ) {
  final approvedPaisa = toPaisa(approvedBdt);
  final pendingPaisa = toPaisa(pendingBdt);
  var approved = approvedPaisa < 0 ? 0 : approvedPaisa;
  var pending = pendingPaisa < 0 ? 0 : pendingPaisa;

  final sorted = [...rows]..sort((a, b) => a.$1.compareTo(b.$1));
  final list = <ScheduleInstallment>[];
  for (final r in sorted) {
    final amount = toPaisa(r.$3);
    final paid = approved < amount ? approved : amount;
    approved -= paid;
    final room = amount - paid;
    final pend = pending < room ? pending : room;
    pending -= pend;
    final open = amount - paid - pend;
    list.add(ScheduleInstallment(
      number: r.$1,
      dueDate: r.$2,
      amountPaisa: amount,
      paidPaisa: paid,
      pendingPaisa: pend,
      openPaisa: open,
      status: _status(amount, paid, open, r.$2, today, graceDays),
    ));
  }

  final total = list.fold<int>(0, (s, a) => s + a.amountPaisa);
  final paid = approvedPaisa < total ? approvedPaisa : total;
  final pendLeft = total - paid;
  ScheduleInstallment? next;
  for (final a in list) {
    if (a.openPaisa > 0) {
      next = a;
      break;
    }
  }
  return ScheduleSummary(
    installments: list,
    totalPaisa: total,
    approvedPaisa: paid,
    pendingPaisa: pendingPaisa < pendLeft ? pendingPaisa : pendLeft,
    remainingPaisa: total - paid,
    progressPct: total > 0 ? (paid / total * 10000).floor() / 100 : 0,
    next: next,
    overdueCount: list.where((a) => a.status == 'OVERDUE').length,
    fullyPaid: total > 0 && paid >= total,
  );
}

/// Website er INSTALLMENT_STATUS_LABEL (+ Bangla)
const Map<String, (String, String)> installmentStatusLabel = {
  'PAID': ('Paid', 'পরিশোধিত'),
  'PARTIALLY_PAID': ('Partly paid', 'আংশিক পরিশোধ'),
  'PENDING_VERIFICATION': ('Under review', 'যাচাই চলছে'),
  'OVERDUE': ('Overdue', 'মেয়াদোত্তীর্ণ'),
  'DUE': ('Due', 'দেয়'),
  'UPCOMING': ('Upcoming', 'আসন্ন'),
};

// ═════════════════════════════════════════════════════════════
// PROJECT ER KISTI-R NIYOM — website er installmentSettingsSchema,
// checkSchedule, suggestSchedule, needsScheduleApproval, maxPayableNowPaisa.
// App ar website ek-i niyome schedule banay / jachai kore.
// ═════════════════════════════════════════════════════════════

const int installmentHardMax = 24;
const String earliestInstallmentDay = '1990-01-01';

/// Website MIN_INSTALLMENT_BDT — protita kisti-payment kompokkhe (baki er cheye kom hole puro baki)
const double minInstallmentBdt = 1000;

bool isDay(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return false;
  final d = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  return _dayString(d.year, d.month, d.day) == s;
}

/// Ek-i tarikh n mash pore, mash er shesh din e atkano (31 Jan + 1 → 28/29 Feb)
String addMonthsToDay(String day, int n) {
  final y = int.parse(day.substring(0, 4));
  final m = int.parse(day.substring(5, 7)) - 1 + n; // 0-based
  final d = int.parse(day.substring(8, 10));
  final last = DateTime.utc(y, m + 2, 0).day;
  final r = DateTime.utc(y, m + 1, d < last ? d : last);
  return _dayString(r.year, r.month, r.day);
}

List<String> monthlyDates(String firstDay, int count) =>
    [for (var i = 0; i < count; i++) addMonthsToDay(firstDay, i)];

/// "৳1,25,000" / "৳1,250.50" (website er toLocaleString("en-BD"))
String tkPaisa(int paisa) {
  final neg = paisa < 0;
  final p = paisa.abs();
  final s = (p ~/ 100).toString();
  String grouped;
  if (s.length <= 3) {
    grouped = s;
  } else {
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},${s.substring(s.length - 3)}';
  }
  final frac = p % 100;
  final f = frac == 0 ? '' : '.${frac.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}';
  return '${neg ? '-' : ''}৳$grouped$f';
}

/// Project.installmentSettings (jsonb). Bhul / khali hole website er DEFAULT.
class InstallmentSettings {
  final int minCount;
  final int maxCount;
  final double? minFirstBdt;
  final double? minFirstPct;
  final int? maxMonths;
  final List<int>? reminderDays;
  final int graceDays;
  final bool allowCustomDates;
  final bool allowEarly;

  /// Admin er thik kora tarikh — thakle kisti-r shonkha = eder shonkha
  final List<String>? fixedDates;

  const InstallmentSettings({
    this.minCount = 2,
    this.maxCount = 6,
    this.minFirstBdt,
    this.minFirstPct,
    this.maxMonths,
    this.reminderDays,
    this.graceDays = 0,
    this.allowCustomDates = true,
    this.allowEarly = true,
    this.fixedDates,
  });

  static const InstallmentSettings defaults = InstallmentSettings();

  factory InstallmentSettings.fromJson(dynamic raw) {
    final j = _json(raw);
    if (j is! Map) return defaults;
    num? n(dynamic v) => v is num ? v : (v is String && v.trim().isNotEmpty ? num.tryParse(v.trim()) : null);
    bool isInt(num? v) => v != null && v == v.roundToDouble();

    int intOr(String k, int fb, int lo, int hi) {
      if (!j.containsKey(k) || j[k] == null) return fb;
      final v = n(j[k]);
      if (!isInt(v) || v! < lo || v > hi) throw const FormatException();
      return v.toInt();
    }

    double? posOrNull(String k, {double? max}) {
      if (j[k] == null) return null;
      final v = n(j[k]);
      if (v == null || v <= 0 || (max != null && v > max)) throw const FormatException();
      return v.toDouble();
    }

    bool boolOr(String k, bool fb) {
      if (j[k] == null) return fb;
      if (j[k] is bool) return j[k] as bool;
      throw const FormatException();
    }

    try {
      var minCount = intOr('minCount', 2, 2, installmentHardMax);
      var maxCount = intOr('maxCount', 6, 2, installmentHardMax);
      final maxMonthsRaw = j['maxMonths'];
      final maxMonths = maxMonthsRaw == null ? null : intOr('maxMonths', 0, 1, 120);
      List<int>? reminder;
      if (j['reminderDays'] is List) {
        final l = j['reminderDays'] as List;
        if (l.length > 5) throw const FormatException();
        reminder = [
          for (final x in l)
            if (isInt(n(x)) && n(x)! >= 0 && n(x)! <= 60) n(x)!.toInt() else throw const FormatException(),
        ];
      } else if (j['reminderDays'] != null) {
        throw const FormatException();
      }
      List<String>? fixed;
      if (j['fixedDates'] is List) {
        final l = (j['fixedDates'] as List).map((e) => e.toString()).toList();
        if (l.length < 2 || l.length > installmentHardMax || l.any((d) => !isDay(d))) throw const FormatException();
        for (var i = 1; i < l.length; i++) {
          if (l[i].compareTo(l[i - 1]) <= 0) throw const FormatException();
        }
        fixed = l;
      } else if (j['fixedDates'] != null) {
        throw const FormatException();
      }
      if (maxCount < minCount) throw const FormatException();
      if (fixed != null) {
        minCount = fixed.length;
        maxCount = fixed.length;
      }
      return InstallmentSettings(
        minCount: minCount,
        maxCount: maxCount,
        minFirstBdt: posOrNull('minFirstBdt'),
        minFirstPct: posOrNull('minFirstPct', max: 100),
        maxMonths: maxMonths,
        reminderDays: reminder,
        graceDays: intOr('graceDays', 0, 0, 90),
        allowCustomDates: boolOr('allowCustomDates', true),
        allowEarly: boolOr('allowEarly', true),
        fixedDates: fixed,
      );
    } catch (_) {
      return defaults;
    }
  }

  /// Investment.installmentTerms e ja jama thake (website termsFromSettings)
  Map<String, dynamic> termsJson(DateTime now) => {
    'graceDays': graceDays,
    'reminderDays': reminderDays,
    'allowEarly': allowEarly,
    'agreedAt': now.toUtc().toIso8601String(),
  };

  /// Choto bornona: "2–6 installments · first at least 20% · …"
  String summary(String Function(String en, String bn) tr) {
    final parts = <String>[
      minCount == maxCount
          ? tr('$minCount installments', '$minCount কিস্তি')
          : tr('$minCount–$maxCount installments', '$minCount–$maxCount কিস্তি'),
      if (minFirstPct != null)
        tr('first at least ${_trimNum(minFirstPct!)}%', 'প্রথম কিস্তি কমপক্ষে ${_trimNum(minFirstPct!)}%'),
      if (minFirstBdt != null)
        tr('first at least ${tkPaisa(toPaisa(minFirstBdt!))}', 'প্রথম কিস্তি কমপক্ষে ${tkPaisa(toPaisa(minFirstBdt!))}'),
      if (maxMonths != null) tr('finish within $maxMonths months', '$maxMonths মাসের মধ্যে শেষ'),
      if (fixedDates != null)
        tr('dates set by the project', 'তারিখ প্রজেক্ট ঠিক করেছে')
      else if (!allowCustomDates)
        tr('monthly dates', 'মাসিক তারিখ'),
      if (!allowEarly) tr('no paying ahead of schedule', 'আগে পরিশোধ করা যাবে না'),
    ];
    return parts.join(' · ');
  }
}

String _trimNum(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Admin er tarikh thakle: 2nd tarikh ekhono samne thaklei notun kisti-plan khola
bool installmentPlanOpen(InstallmentSettings s, String today) =>
    s.fixedDates == null || s.fixedDates![1].compareTo(today) > 0;

/// Mot taka [count] bhage, puro takay shoman; shesh kisti baki ta nay
List<double> splitEvenly(double totalBdt, int count) {
  final total = toPaisa(totalBdt);
  if (count < 1) return [];
  final each = (total / count / 100).floor() * 100;
  final amounts = List<int>.filled(count, each);
  amounts[count - 1] = total - each * (count - 1);
  return amounts.map((p) => p / 100).toList();
}

/// Shuru-r schedule: shoman taka, aj theke mashik (ba project er thik kora tarikh)
List<(String, double)> suggestSchedule(double totalBdt, int count, String today, List<String>? fixedDates) {
  final dates = fixedDates ?? monthlyDates(today, count);
  final amounts = splitEvenly(totalBdt, dates.length);
  return [for (var i = 0; i < dates.length; i++) (dates[i], amounts[i])];
}

class ScheduleCheck {
  final int totalPaisa;
  final int scheduledPaisa;

  /// total − scheduled; beshi dile minus
  final int remainingPaisa;
  final List<String> errors;
  const ScheduleCheck(this.totalPaisa, this.scheduledPaisa, this.remainingPaisa, this.errors);
}

/// Notun schedule er shob niyom (website checkSchedule). rows: (dueDate, amountBdt)
ScheduleCheck checkSchedule(
    double totalBdt,
    List<(String, double)> rows,
    InstallmentSettings s,
    String today,
    String Function(String en, String bn) tr,
    ) {
  final errors = <String>[];
  final totalPaisa = toPaisa(totalBdt);
  final amounts = rows.map((r) => toPaisa(r.$2)).toList();
  final scheduled = amounts.fold<int>(0, (a, b) => a + b);
  final remaining = totalPaisa - scheduled;

  if (rows.length < s.minCount || rows.length > s.maxCount) {
    errors.add(tr('Choose between ${s.minCount} and ${s.maxCount} installments',
        '${s.minCount} থেকে ${s.maxCount} টি কিস্তি বেছে নিন'));
  }
  if (amounts.any((a) => a <= 0)) {
    errors.add(tr('Each installment must be more than ৳0', 'প্রতিটি কিস্তি ৳0 এর বেশি হতে হবে'));
  }
  if (rows.asMap().entries.any((e) => (e.value.$2 * 100 - amounts[e.key]).abs() > 1e-6)) {
    errors.add(tr('Amounts can have at most 2 decimal places', 'টাকায় দশমিকের পরে সর্বোচ্চ ২ ঘর'));
  }
  if (remaining != 0) {
    errors.add(tr('The total installment amount must equal your investment amount.',
        'কিস্তিগুলোর যোগফল আপনার বিনিয়োগের সমান হতে হবে।'));
  }

  final first = amounts.isEmpty ? 0 : amounts.first;
  if (s.minFirstBdt != null && first < toPaisa(s.minFirstBdt!)) {
    errors.add(tr('The first installment must be at least ${tkPaisa(toPaisa(s.minFirstBdt!))}',
        'প্রথম কিস্তি কমপক্ষে ${tkPaisa(toPaisa(s.minFirstBdt!))} হতে হবে'));
  }
  if (s.minFirstPct != null) {
    final need = (totalPaisa * s.minFirstPct! / 100).ceil();
    if (first < need) {
      errors.add(tr('The first installment must be at least ${_trimNum(s.minFirstPct!)}% of the total (${tkPaisa(need)})',
          'প্রথম কিস্তি মোটের কমপক্ষে ${_trimNum(s.minFirstPct!)}% হতে হবে (${tkPaisa(need)})'));
    }
  }

  final dates = rows.map((r) => r.$1).toList();
  if (dates.any((d) => !isDay(d))) {
    errors.add(tr('Enter a valid date for every installment', 'প্রতিটি কিস্তির সঠিক তারিখ দিন'));
  } else if (s.fixedDates != null) {
    final fixed = s.fixedDates!;
    if (dates.length != fixed.length || dates.asMap().entries.any((e) => e.value != fixed[e.key])) {
      errors.add(tr('This project uses fixed installment dates', 'এই প্রজেক্টের কিস্তির তারিখ নির্দিষ্ট'));
    }
    if (!installmentPlanOpen(s, today)) {
      errors.add(tr('The installment dates for this project have passed — please pay in full',
          'এই প্রজেক্টের কিস্তির তারিখ পেরিয়ে গেছে — একবারে পরিশোধ করুন'));
    }
  } else if (dates.isNotEmpty) {
    if (dates.first.compareTo(today) > 0) {
      errors.add(tr("The first installment date can't be in the future", 'প্রথম কিস্তির তারিখ ভবিষ্যতে হতে পারে না'));
    }
    if (dates.first.compareTo(earliestInstallmentDay) < 0) {
      errors.add(tr("The first installment date can't be before 1 January 1990", 'প্রথম কিস্তির তারিখ ১৯৯০ এর আগে হতে পারে না'));
    }
    for (var i = 1; i < dates.length; i++) {
      if (dates[i].compareTo(dates[i - 1]) <= 0) {
        errors.add(tr('Each installment date must be after the one before it', 'প্রতিটি কিস্তির তারিখ আগেরটির পরে হতে হবে'));
        break;
      }
    }
    if (s.maxMonths != null && dates.last.compareTo(addMonthsToDay(dates.first, s.maxMonths!)) > 0) {
      errors.add(tr('The last installment must be within ${s.maxMonths} month${s.maxMonths == 1 ? '' : 's'} of the first',
          'শেষ কিস্তি প্রথমটির ${s.maxMonths} মাসের মধ্যে হতে হবে'));
    }
    if (!s.allowCustomDates) {
      final expected = monthlyDates(dates.first, dates.length);
      if (dates.asMap().entries.any((e) => e.value != expected[e.key])) {
        errors.add(tr('This project uses monthly installment dates', 'এই প্রজেক্টে মাসিক তারিখে কিস্তি'));
      }
    }
  }
  return ScheduleCheck(totalPaisa, scheduled, remaining, errors.toSet().toList());
}

/// Admin ke age tarikh approve korte hobe kina (website needsScheduleApproval).
/// Website e 2026-12-01 porjonto approval bondho — shob auto-approved.
bool needsScheduleApproval(InstallmentSettings s, List<(String, double)> rows, String today) {
  if (today.compareTo('2026-12-01') < 0) return false;
  if (s.fixedDates != null || rows.isEmpty) return false;
  if (rows.first.$1.compareTo(today) < 0) return true;
  if (!s.allowCustomDates) return false;
  final monthly = monthlyDates(rows.first.$1, rows.length);
  return rows.asMap().entries.any((e) => e.value.$1 != monthly[e.key]);
}

/// Prothom kisti-r tarikh aj-er age (offline e age deya)
bool isBackdated(List<(String, double)> rows, String today) => rows.isNotEmpty && rows.first.$1.compareTo(today) < 0;

/// Approval er opekkhay ba bad — taka deya jay na
bool scheduleBlocksPayment(String? approval) => approval == 'PENDING' || approval == 'REJECTED';

/// Ekhon shorbochcho koto deya jay (website maxPayableNowPaisa)
int maxPayableNowPaisa(ScheduleSummary summary, String today, bool allowEarly) {
  final open = summary.installments.where((a) => a.openPaisa > 0).toList();
  if (allowEarly) return open.fold<int>(0, (s, a) => s + a.openPaisa);
  var total = 0;
  for (var i = 0; i < open.length; i++) {
    if (i == 0 || open[i].dueDate.compareTo(today) <= 0) {
      total += open[i].openPaisa;
    } else {
      break;
    }
  }
  return total;
}

/// "1st", "2nd", "3rd" …
String ordinal(int n) {
  final t = n % 100;
  if (t >= 11 && t <= 13) return '${n}th';
  return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
}