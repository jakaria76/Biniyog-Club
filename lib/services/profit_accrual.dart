/// Website er src/lib/financial/profit-accrual.ts + profit-accrual.service er
/// je ongsho investor er dekhar jonno lage — hubohu ek-i hishab.
///
/// - Bochorer lav ÷ 12 = mashik lav; mash er bhetore din dhore (÷ oi mash er din).
/// - Prothom mash e effective date er por theke gona hoy.
/// - Choloman mash er lav "earned" kintu mash shesh na hole deya hoy na.
/// - Taka paisa (BigInt) e — kono doshomik er bhul nei.
library;

import 'installment_schedule.dart';

/// Ek mash er integer unit: 28, 29, 30, 31 er LCM — "din ÷ mash er din" thik thake
const int monthScale = 377580;

int daysInMonthOf(String day) => DateTime.utc(int.parse(day.substring(0, 4)), int.parse(day.substring(5, 7)) + 1, 0).day;

int _dayNumber(String day) =>
    DateTime.utc(int.parse(day.substring(0, 4)), int.parse(day.substring(5, 7)), int.parse(day.substring(8, 10)))
        .millisecondsSinceEpoch ~/
        86400000;

/// a theke b, duita din-i dhore
int daysBetweenDays(String a, String b) => _dayNumber(b) - _dayNumber(a) + 1;

String _monthStart(String day) => '${day.substring(0, 8)}01';
String _monthEnd(String day) => '${day.substring(0, 8)}${daysInMonthOf(day).toString().padLeft(2, '0')}';

BigInt _mulDivRound(BigInt a, BigInt b, BigInt c) => (a * b * BigInt.two + c) ~/ (BigInt.two * c);

BigInt paisaBig(dynamic v) => BigInt.from(toPaisa(v is num ? v : (double.tryParse(v?.toString() ?? '') ?? 0)));

class AccrualMonth {
  final String month; // "YYYY-MM-01"
  final String periodStart;
  final String periodEnd;
  final int eligibleDays;
  final int daysInMonth;
  final BigInt amountPaisa;

  /// Mash (ba investment er shesh din) periye geche — deya jay
  final bool closed;

  const AccrualMonth(
      this.month, this.periodStart, this.periodEnd, this.eligibleDays, this.daysInMonth, this.amountPaisa, this.closed);
}

/// Website er accrualSchedule: earnFrom theke (earnTo / through porjonto) mash e mash e
List<AccrualMonth> accrualSchedule(BigInt annualPaisa, String earnFrom, String? earnTo, String through) {
  final last = earnTo != null && earnTo.compareTo(through) < 0 ? earnTo : through;
  if (annualPaisa <= BigInt.zero || earnFrom.compareTo(last) > 0) return const [];
  final den = BigInt.from(12) * BigInt.from(monthScale);
  final months = <AccrualMonth>[];
  var units = BigInt.zero;
  var paidSoFar = BigInt.zero;
  for (var cursor = earnFrom; cursor.compareTo(last) <= 0; cursor = addDaysToDay(_monthEnd(cursor), 1)) {
    final dim = daysInMonthOf(cursor);
    final end = _monthEnd(cursor).compareTo(last) < 0 ? _monthEnd(cursor) : last;
    final days = daysBetweenDays(cursor, end);
    units += BigInt.from((days * monthScale) ~/ dim);
    final total = _mulDivRound(annualPaisa, units, den);
    final naturalEnd = earnTo != null && earnTo.compareTo(_monthEnd(cursor)) < 0 ? earnTo : _monthEnd(cursor);
    months.add(AccrualMonth(_monthStart(cursor), cursor, end, days, dim, total - paidSoFar, naturalEnd.compareTo(through) <= 0));
    paidSoFar = total;
  }
  return months;
}

/// Shesh lav er din: chukti-r meyad, ba age matured hole oi mash er shesh din — je ta age
String? lastEarningDay(String? maturityDay, String? maturedDay) {
  final early = maturedDay == null || maturedDay.isEmpty
      ? null
      : '${maturedDay.substring(0, 8)}${daysInMonthOf(maturedDay).toString().padLeft(2, '0')}';
  final contract = maturityDay == null || maturityDay.isEmpty ? null : maturityDay;
  if (contract != null && early != null) return contract.compareTo(early) < 0 ? contract : early;
  return contract ?? early;
}

/// Bangladesh er "gotokal": shesh puro din ja earned
String earnedThrough() => addDaysToDay(dhakaDay(), -1);

/// Website er payoutStatus — finance confirm korle tobei "Paid"
(String key, String en, String bn) payoutStatus(String lineStatus, String batchStatus) {
  if (lineStatus == 'PAID' || lineStatus == 'POSTED') return ('PAID', 'Paid', 'পরিশোধিত');
  if (lineStatus == 'FAILED') return ('FAILED', 'Failed', 'ব্যর্থ');
  if (lineStatus == 'REVERSED') return ('REVERSED', 'Reversed', 'ফেরত নেওয়া');
  if (batchStatus == 'PROCESSING') return ('AWAITING_PAYMENT', 'Awaiting payment', 'পেমেন্টের অপেক্ষায়');
  return ('IN_APPROVAL', 'Being approved', 'অনুমোদন চলছে');
}

const Map<String, String> payoutMethodLabels = {
  'BANK_TRANSFER': 'Bank transfer',
  'BKASH': 'bKash',
  'NAGAD': 'Nagad',
  'ROCKET': 'Rocket',
  'CHEQUE': 'Cheque',
  'CASH': 'Cash',
};

/// "৳1,234.50" — website er tk() (shob shomoy 2 ghor)
String tk2(num bdt) {
  final p = (bdt * 100).round();
  final whole = tkPaisa((p ~/ 100) * 100);
  return '$whole.${(p.abs() % 100).toString().padLeft(2, '0')}';
}