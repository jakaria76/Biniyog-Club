import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Certificate PDF er jonno data
class CertificateData {
  final String certNo;
  final String issuedDate;
  final String status;
  final double principal;
  final String investorName;
  final String investorEmail;
  final String investorPhone;
  final String projectTitle;
  final String location;
  final String returnType;
  final String verifyUrl;

  const CertificateData({
    required this.certNo,
    required this.issuedDate,
    required this.status,
    required this.principal,
    required this.investorName,
    required this.investorEmail,
    required this.investorPhone,
    required this.projectTitle,
    required this.location,
    required this.returnType,
    required this.verifyUrl,
  });
}

class PdfService {
  // Expected return range — onno page gular sathe same
  static const double minReturnRate = 0.16;
  static const double maxReturnRate = 0.22;

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  // ─── Formatting ───────────────────────────────────────────
  static String money(double v) {
    final s = v.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
    );
    return 'BDT $s';
  }

  static String formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    final l = d.toLocal();
    return '${_months[l.month - 1]} ${l.day}, ${l.year}';
  }

  static String rangeLabel() {
    String p(double r) {
      final v = r * 100;
      return v == v.roundToDouble()
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(1);
    }

    return '${p(minReturnRate)}-${p(maxReturnRate)}%';
  }

  static String safeFileName(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  // ─── Certificate PDF ──────────────────────────────────────
  static Future<Uint8List> buildCertificate(CertificateData d) async {
    final emerald = PdfColor.fromHex('#0E4A37');
    final deep = PdfColor.fromHex('#0A3327');
    final emeraldSoft = PdfColor.fromHex('#E3F0E9');
    final gold = PdfColor.fromHex('#B8935A');
    final goldLight = PdfColor.fromHex('#D9BE8C');
    final goldSoft = PdfColor.fromHex('#F6EEDF');
    final ivory = PdfColor.fromHex('#F7F4EE');
    final ink = PdfColor.fromHex('#1C2421');
    final muted = PdfColor.fromHex('#6E736F');

    final expMin = d.principal * minReturnRate;
    final expMax = d.principal * maxReturnRate;
    final totMin = d.principal + expMin;
    final totMax = d.principal + expMax;

    pw.Widget label(String t) => pw.Text(
      t,
      style: pw.TextStyle(
        fontSize: 7.5,
        color: muted,
        fontWeight: pw.FontWeight.bold,
        letterSpacing: 0.8,
      ),
    );

    pw.Widget sectionTitle(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(children: [
        pw.Container(width: 3, height: 11, color: gold),
        pw.SizedBox(width: 6),
        pw.Text(
          t,
          style: pw.TextStyle(
            fontSize: 9.5,
            fontWeight: pw.FontWeight.bold,
            color: deep,
            letterSpacing: 0.8,
          ),
        ),
      ]),
    );

    pw.Widget kv(String k, String v) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(k, style: pw.TextStyle(fontSize: 8.5, color: muted)),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              v,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );

    pw.Widget block(List<pw.Widget> rows) => pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: ivory,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(children: rows),
    );

    final doc = pw.Document(
      title: 'Investment Certificate ${d.certNo}',
      author: 'Biniyog Club',
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: gold, width: 1.2),
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(22, 20, 22, 20),
                decoration: pw.BoxDecoration(
                  color: emerald,
                  borderRadius: const pw.BorderRadius.only(
                    topLeft: pw.Radius.circular(9),
                    topRight: pw.Radius.circular(9),
                  ),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'BINIYOG CLUB',
                            style: pw.TextStyle(
                              fontSize: 9,
                              color: goldLight,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'INVESTMENT CERTIFICATE',
                            style: pw.TextStyle(
                              fontSize: 20,
                              color: PdfColors.white,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: pw.BoxDecoration(
                        color: goldLight,
                        borderRadius: pw.BorderRadius.circular(10),
                      ),
                      child: pw.Text(
                        d.status,
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          color: deep,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(22, 16, 22, 16),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Text(
                      'This document confirms a verified investment on the Biniyog Club platform.',
                      style: pw.TextStyle(fontSize: 9, color: muted),
                    ),
                    pw.SizedBox(height: 12),

                    // Meta
                    pw.Row(children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            label('CERTIFICATE NO.'),
                            pw.SizedBox(height: 2),
                            pw.Text(d.certNo,
                                style: pw.TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: ink)),
                          ],
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            label('ISSUED DATE'),
                            pw.SizedBox(height: 2),
                            pw.Text(d.issuedDate,
                                style: pw.TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: ink)),
                          ],
                        ),
                      ),
                    ]),
                    pw.SizedBox(height: 12),

                    // Amounts
                    pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: emeraldSoft,
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                label('AMOUNT INVESTED'),
                                pw.SizedBox(height: 3),
                                pw.Text(money(d.principal),
                                    style: pw.TextStyle(
                                        fontSize: 13,
                                        fontWeight: pw.FontWeight.bold,
                                        color: emerald)),
                                pw.Text('Principal',
                                    style: pw.TextStyle(
                                        fontSize: 7.5, color: muted)),
                              ],
                            ),
                          ),
                          pw.Container(
                              width: 0.8, height: 36, color: emerald),
                          pw.SizedBox(width: 12),
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                label('EXPECTED RETURN'),
                                pw.SizedBox(height: 3),
                                pw.Text(
                                    '${money(expMin)} - ${money(expMax)}',
                                    style: pw.TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: pw.FontWeight.bold,
                                        color: emerald)),
                                pw.Text('${rangeLabel()} of principal',
                                    style: pw.TextStyle(
                                        fontSize: 7.5, color: muted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 14),

                    // Investor + Project side by side
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                            children: [
                              sectionTitle('INVESTOR DETAILS'),
                              block([
                                kv('Full Name', d.investorName),
                                kv('Email', d.investorEmail),
                                kv('Phone', d.investorPhone),
                              ]),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 10),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                            children: [
                              sectionTitle('PROJECT DETAILS'),
                              block([
                                kv('Project', d.projectTitle),
                                kv('Location', d.location),
                                kv('Return Type', d.returnType),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 14),

                    sectionTitle('INVESTMENT TERMS'),
                    block([
                      kv('Investment Date', d.issuedDate),
                      kv('Principal Amount', money(d.principal)),
                      kv('Expected Return Rate', rangeLabel()),
                      kv('Expected Return',
                          '${money(expMin)} - ${money(expMax)}'),
                      kv('Total Expected Value',
                          '${money(totMin)} - ${money(totMax)}'),
                    ]),
                    pw.SizedBox(height: 14),

                    // Verify
                    pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: goldSoft,
                        border: pw.Border.all(color: gold, width: 0.6),
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('VERIFY THIS CERTIFICATE',
                                    style: pw.TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColor.fromHex('#8A6A3A'))),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  'Scan the QR code or visit the URL below. The verification page shows the original record from our database. Any altered PDF will not match.',
                                  style: pw.TextStyle(
                                      fontSize: 8, color: muted, lineSpacing: 1.5),
                                ),
                                pw.SizedBox(height: 6),
                                pw.Text(d.verifyUrl,
                                    style: pw.TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: pw.FontWeight.bold,
                                        color: emerald)),
                              ],
                            ),
                          ),
                          pw.SizedBox(width: 12),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(4),
                            color: PdfColors.white,
                            child: pw.BarcodeWidget(
                              barcode: pw.Barcode.qrCode(),
                              data: d.verifyUrl,
                              width: 70,
                              height: 70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Text(
                      'Expected return is an estimated range and is not guaranteed. Final returns depend on actual project performance.',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(fontSize: 7.5, color: muted),
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // Footer
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: deep,
                  borderRadius: const pw.BorderRadius.only(
                    bottomLeft: pw.Radius.circular(9),
                    bottomRight: pw.Radius.circular(9),
                  ),
                ),
                child: pw.Column(children: [
                  pw.Text('Biniyog Club',
                      style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                      'Investment Platform | Dhaka, Bangladesh | info@biniyogclub.com | www.biniyogclub.com',
                      style: pw.TextStyle(fontSize: 7.5, color: goldLight)),
                ]),
              ),
            ],
          ),
        ),
      ),
    );

    return doc.save();
  }

  // ═════════════════════════════════════════════════════════
  // WEBSITE CERTIFICATE — website er `investment-certificate.ts` er hubohu.
  // Data ashe database theke (DatabaseService.getWebsiteCertificates).
  // QR e website er ek-i link: https://biniyogclub.com/verify/<receiptNumber>
  // Verify puro ta website server e database theke hoy, tai scan korle
  // website er PDF er motoi "verified" dekhabe.
  // ═════════════════════════════════════════════════════════
  static const List<String> _monthsLong = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'
  ];

  static String _gbDate(DateTime d) {
    final u = d.toUtc();
    return '${u.day} ${_monthsLong[u.month - 1]} ${u.year}';
  }

  /// Bangladesh time (UTC+6) e date — website er sathe match korar jonno
  static DateTime _toDhaka(DateTime d) =>
      d.toUtc().add(const Duration(hours: 6));

  static String _bdDate(DateTime d) {
    final b = _toDhaka(d);
    return '${b.day} ${_monthsLong[b.month - 1]} ${b.year}';
  }

  /// Built-in Helvetica/Times font e em-dash (—), en-dash (–), bullet (•)
  /// nai, tai PDF e box (▯) dekhay. Egula safe character e replace kori.
  static String _safeText(String s) => s
      .replaceAll('\u2014', '-') // —
      .replaceAll('\u2013', '-') // –
      .replaceAll('\u2022', '\u00B7') // • -> ·
      .replaceAll('\u2018', "'")
      .replaceAll('\u2019', "'")
      .replaceAll('\u201C', '"')
      .replaceAll('\u201D', '"');

  /// Database e rate kokhono 15 (percent) ashe, kokhono 0.15 (fraction).
  /// Duita-kei fraction (0.15) e convert kori.
  static double _normalizeRate(double r) => r > 1 ? r / 100 : r;

  static String _bdt(double n) => money(n); // "BDT 1,234.00"

  static String _pct(double n) {
    final v = double.parse(n.toStringAsFixed(2));
    return v == v.roundToDouble() ? '${v.toInt()}%' : '$v%';
  }

  static const Map<String, String> _returnLabels = {
    'FIXED_RETURN': 'Fixed Return',
    'PROFIT_SHARE': 'Profit Share',
    'HYBRID': 'Hybrid',
  };

  /// [c] = DatabaseService.getWebsiteCertificates() er ekta item
  static Future<Uint8List> buildWebsiteCertificate(Map<String, dynamic> c) async {
    final brand = PdfColor.fromHex('#0d4a42');
    final brandDark = PdfColor.fromHex('#082f2a');
    final brandTint = PdfColor.fromHex('#eef6f4');
    final gold = PdfColor.fromHex('#b08d4a');
    final goldSoft = PdfColor.fromHex('#e9dcc0');
    final ink = PdfColor.fromHex('#111827');
    final body = PdfColor.fromHex('#374151');
    final muted = PdfColor.fromHex('#6b7280');
    final rule = PdfColor.fromHex('#e5e7eb');

    final helv = pw.Font.helvetica();
    final helvB = pw.Font.helveticaBold();
    final times = pw.Font.times();
    final timesB = pw.Font.timesBold();
    final timesI = pw.Font.timesItalic();
    final timesBI = pw.Font.timesBoldItalic();

    double d(String k) => (c[k] as num?)?.toDouble() ?? 0.0;
    double? dn(String k) => (c[k] as num?)?.toDouble();
    String s(String k, [String f = '']) {
      final v = c[k]?.toString() ?? '';
      return v.isEmpty ? f : v;
    }

    final receiptNumber = s('certificateNo');
    final investmentId = s('investmentId');
    final verifyUrl = s('verifyUrl');
    final title = s('projectTitle', 'Biniyog Project');
    final location = s('location');
    final name = s('userName', 'Investor');
    final email = s('userEmail');
    final phone = s('userPhone');
    final returnType = s('returnType', 'PROFIT_SHARE');
    final durationDays = (c['durationDays'] as num?)?.toInt() ?? 0;

    final amount = d('amountInvested');
    final minPct = dn('returnPctMin');
    final maxPct = dn('returnPctMax');
    final isRange = minPct != null && maxPct != null && minPct > 0 && maxPct > 0;
    final retMin = isRange ? (amount * minPct!).roundToDouble() / 100 : d('expectedReturnBdt');
    final double? retMax = isRange ? (amount * maxPct!).roundToDouble() / 100 : null;
    final rateLabel = isRange ? '${_pct(minPct!)} - ${_pct(maxPct!)}' : _pct(d('expectedReturnPct'));
    final returnLabel = retMax != null ? '${_bdt(retMin)} - ${_bdt(retMax)}' : _bdt(retMin);
    final totalLabel = retMax != null
        ? '${_bdt(amount + retMin)} - ${_bdt(amount + retMax)}'
        : _bdt(amount + retMin);

    final generatedAt = DateTime.tryParse(s('generatedAt')) ?? DateTime.now();
    final activatedAt = DateTime.tryParse(s('activatedAt')) ?? generatedAt;
    final maturity = activatedAt.toUtc().add(Duration(days: durationDays));

    pw.Widget hRule(PdfColor color, double w) =>
        pw.Container(height: w, color: color);

    pw.Widget metaRow(String label, String value) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(label,
            style: pw.TextStyle(font: helv, fontSize: 6.5, color: muted, letterSpacing: 0.8)),
        pw.SizedBox(height: 1),
        pw.Text(value, style: pw.TextStyle(font: helvB, fontSize: 8.5, color: ink)),
      ],
    );

    pw.Widget figure(String label, String value, String sub) => pw.Expanded(
      child: pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(8, 13, 8, 10),
        child: pw.Column(
          children: [
            pw.Text(label,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: helv, fontSize: 6.5, color: muted, letterSpacing: 1)),
            pw.Spacer(),
            pw.Text(value,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    font: helvB,
                    fontSize: value.contains('\n') ? 10 : 12.5,
                    color: brandDark,
                    lineSpacing: 1)),
            pw.Spacer(),
            pw.Text(sub,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: helv, fontSize: 7, color: muted)),
          ],
        ),
      ),
    );

    pw.Widget detailColumn(String heading, List<List<String>> rows, double labelW) =>
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(heading.toUpperCase(),
                  style: pw.TextStyle(font: helvB, fontSize: 7.5, color: brand, letterSpacing: 1.4)),
              pw.SizedBox(height: 5),
              hRule(brand, 0.8),
              pw.SizedBox(height: 6),
              for (final r in rows) ...[
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: labelW,
                      child: pw.Text(r[0],
                          style: pw.TextStyle(font: helv, fontSize: 8, color: muted)),
                    ),
                    pw.Expanded(
                      child: pw.Text(r[1],
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(font: helvB, fontSize: 8, color: ink)),
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                hRule(rule, 0.4),
                pw.SizedBox(height: 4),
              ],
            ],
          ),
        );

    final investorRows = <List<String>>[
      ['Name', name],
      ['Email', email],
      if (phone.isNotEmpty) ['Phone', phone],
      ['Investment ID', investmentId.substring(0, investmentId.length >= 8 ? 8 : investmentId.length).toUpperCase()],
    ];
    final investmentRows = <List<String>>[
      ['Project', title],
      if (location.isNotEmpty) ['Location', location],
      ['Return type', _returnLabels[returnType] ?? returnType],
      [isRange ? 'Return range' : 'Return rate', rateLabel],
      ['Effective date', _gbDate(activatedAt)],
      ['Maturity date', _gbDate(maturity)],
      ['Expected return', returnLabel],
      ['Total expected', totalLabel],
    ];

    final statement =
        'has invested ${_bdt(amount)} in "$title", a project administered through '
        'Biniyog Club, with effect from ${_gbDate(activatedAt)} for a term of $durationDays days.';

    final doc = pw.Document(
      title: 'Investment Certificate - $receiptNumber',
      author: 'Biniyog Club',
      subject: 'Investment Certificate',
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Stack(
          children: [
            // ── Frame ──
            pw.Positioned(
              left: 18, top: 18, right: 18, bottom: 18,
              child: pw.Container(
                decoration: pw.BoxDecoration(border: pw.Border.all(color: brand, width: 2)),
              ),
            ),
            pw.Positioned(
              left: 24, top: 24, right: 24, bottom: 24,
              child: pw.Container(
                decoration: pw.BoxDecoration(border: pw.Border.all(color: gold, width: 0.6)),
              ),
            ),
            for (final pos in const [
              [21.0, 21.0, null, null], [null, 21.0, 21.0, null],
              [21.0, null, null, 21.0], [null, null, 21.0, 21.0],
            ])
              pw.Positioned(
                left: pos[0], top: pos[1], right: pos[2], bottom: pos[3],
                child: pw.Container(width: 6, height: 6, color: gold),
              ),

            // ── Content ──
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(58, 50, 58, 0),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // Letterhead
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.SizedBox(height: 6),
                            pw.Text('BINIYOG CLUB',
                                style: pw.TextStyle(font: helvB, fontSize: 15, color: brand, letterSpacing: 1.6)),
                            pw.SizedBox(height: 4),
                            pw.Text('A Mariners Group Investment Platform',
                                style: pw.TextStyle(font: helv, fontSize: 7.5, color: muted, letterSpacing: 0.4)),
                          ],
                        ),
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          metaRow('CERTIFICATE NO.', receiptNumber),
                          pw.SizedBox(height: 4),
                          metaRow('DATE OF ISSUE', _gbDate(generatedAt)),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 12),
                  hRule(gold, 0.8),
                  pw.SizedBox(height: 1.7),
                  hRule(gold, 0.3),

                  // Title
                  pw.SizedBox(height: 24),
                  pw.Text('OFFICIAL RECORD',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: helvB, fontSize: 8, color: gold, letterSpacing: 3)),
                  pw.SizedBox(height: 8),
                  pw.Text('Certificate of Investment',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: timesB, fontSize: 30, color: brandDark)),
                  pw.SizedBox(height: 14),

                  // Statement
                  pw.Text('This is to certify that',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: timesI, fontSize: 12, color: body)),
                  pw.SizedBox(height: 8),
                  pw.Text(name,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: timesB, fontSize: 24, color: ink)),
                  pw.SizedBox(height: 6),
                  pw.Center(child: pw.Container(width: 220, height: 0.8, color: gold)),
                  pw.SizedBox(height: 14),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 24),
                    child: pw.Text(statement,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(font: times, fontSize: 11.5, color: body, lineSpacing: 3)),
                  ),
                  pw.SizedBox(height: 22),

                  // Key figures
                  pw.Container(
                    height: 74,
                    decoration: pw.BoxDecoration(
                      color: brandTint,
                      border: pw.Border(top: pw.BorderSide(color: brand, width: 2)),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        figure('PRINCIPAL', _bdt(amount), 'Amount invested'),
                        pw.Container(width: 0.8, margin: const pw.EdgeInsets.symmetric(vertical: 14), color: goldSoft),
                        figure(
                          'EXPECTED RETURN',
                          retMax != null ? '${_bdt(retMin)} -\n${_bdt(retMax)}' : _bdt(retMin),
                          '$rateLabel of principal',
                        ),
                        pw.Container(width: 0.8, margin: const pw.EdgeInsets.symmetric(vertical: 14), color: goldSoft),
                        figure('MATURITY DATE', _gbDate(maturity), '$durationDays-day term'),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 24),

                  // Details
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      detailColumn('Investor', investorRows, 70),
                      pw.SizedBox(width: 26),
                      detailColumn('Investment', investmentRows, 82),
                    ],
                  ),
                  pw.Spacer(),

                  // Verification + authorisation
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.all(5),
                        decoration: pw.BoxDecoration(border: pw.Border.all(color: rule, width: 0.6)),
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: verifyUrl,
                          width: 70,
                          height: 70,
                          color: brandDark,
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.SizedBox(height: 4),
                            pw.Text('VERIFY AUTHENTICITY',
                                style: pw.TextStyle(font: helvB, fontSize: 7.5, color: brand, letterSpacing: 1.2)),
                            pw.SizedBox(height: 5),
                            pw.Text(
                              'Scan the QR code or visit the address below. The verification page shows the original record held by Biniyog Club; an altered document will not match.',
                              style: pw.TextStyle(font: helv, fontSize: 7.5, color: body, lineSpacing: 1.5),
                            ),
                            pw.SizedBox(height: 6),
                            pw.Text(verifyUrl,
                                style: pw.TextStyle(font: helvB, fontSize: 7.5, color: brand)),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 20),
                      pw.SizedBox(
                        width: 150,
                        child: pw.Column(
                          children: [
                            pw.SizedBox(height: 30),
                            pw.Text('Biniyog Club',
                                style: pw.TextStyle(font: timesBI, fontSize: 14, color: brandDark)),
                            pw.SizedBox(height: 3),
                            hRule(ink, 0.6),
                            pw.SizedBox(height: 4),
                            pw.Text('Authorised on behalf of Biniyog Club',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(font: helv, fontSize: 7, color: muted)),
                            pw.Text('Electronically issued - no signature required',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(font: helv, fontSize: 7, color: muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 20),

                  // Footer
                  hRule(gold, 0.5),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    "Returns shown are projections based on the project's stated rate and are subject to project performance. "
                        'This certificate is system-generated and cryptographically signed; it is not a negotiable instrument.',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: helv, fontSize: 6.5, color: muted, lineSpacing: 1.5),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Biniyog Club  ·  Dhaka, Bangladesh  ·  info@biniyogclub.com  ·  www.biniyogclub.com',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: helvB, fontSize: 7, color: brand, letterSpacing: 0.3),
                  ),
                  pw.SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  // ─── Network download ─────────────────────────────────────
  static Future<Uint8List?> downloadBytes(String url) async {
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 60));
      if (res.statusCode == 200) return res.bodyBytes;
      debugPrint('Download failed ${res.statusCode}: $url');
    } catch (e) {
      debugPrint('Download error: $e');
    }
    return null;
  }

  static bool isPdf(Uint8List bytes) =>
      bytes.length > 4 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46; // %PDF

  static String extensionFor(Uint8List bytes, String url) {
    if (isPdf(bytes)) return 'pdf';
    if (bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50) return 'png';
    if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpg';
    final m = RegExp(r'\.([a-zA-Z0-9]{2,4})(?:\?|$)').firstMatch(url);
    return m?.group(1)?.toLowerCase() ?? 'bin';
  }

  // ─── Save to phone ────────────────────────────────────────
  /// Android: Download/Biniyog Club folder (na parle app folder)
  /// iOS: app Documents folder (Files app e dekha jabe)
  static Future<String> saveToDevice(Uint8List bytes, String fileName) async {
    final name = safeFileName(fileName);

    if (Platform.isAndroid) {
      try {
        final dir = Directory('/storage/emulated/0/Download/Biniyog Club');
        if (!await dir.exists()) await dir.create(recursive: true);
        final file = await _uniqueFile(dir, name);
        await file.writeAsBytes(bytes, flush: true);
        return file.path;
      } catch (e) {
        debugPrint('Public Download write failed, using app folder: $e');
      }
    }

    Directory base;
    if (Platform.isAndroid) {
      base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}/Biniyog Club');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = await _uniqueFile(dir, name);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<File> _uniqueFile(Directory dir, String name) async {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var file = File('${dir.path}/$name');
    var i = 1;
    while (await file.exists()) {
      file = File('${dir.path}/$stem ($i)$ext');
      i++;
    }
    return file;
  }

  static Future<void> openFile(String path) async {
    await OpenFilex.open(path);
  }

  /// Website er group certificate er motoi professional group certificate PDF banay
  static Future<Uint8List> buildGroupWebsiteCertificate(Map<String, dynamic> c) async {
    final brand = PdfColor.fromHex('#0d4a42');
    final brandDark = PdfColor.fromHex('#082f2a');
    final brandTint = PdfColor.fromHex('#eef6f4');
    final gold = PdfColor.fromHex('#b08d4a');
    final ink = PdfColor.fromHex('#111827');
    final muted = PdfColor.fromHex('#6b7280');
    final rule = PdfColor.fromHex('#e5e7eb');

    final helv = pw.Font.helvetica();
    final helvB = pw.Font.helveticaBold();

    double d(String k) => (c[k] as num?)?.toDouble() ?? 0.0;
    String s(String k, [String f = '']) {
      final v = c[k]?.toString() ?? '';
      return _safeText(v.isEmpty ? f : v);
    }

    final receiptNumber = s('certificateNo');
    final investmentId = s('id');
    final verifyUrl = s('verifyUrl', 'https://biniyogclub.com/verify/$receiptNumber');
    final groupName = s('groupName', 'Mariners Group');
    final title = s('projectTitle', 'Mariners Group - Investor Tier');
    final name = s('userName', 'Investor');
    final email = s('userEmail');
    final phone = s('userPhone');
    final durationMonths = (c['durationMonths'] as num?)?.toInt() ?? 12;

    final amount = d('amountInvested');
    // FIX: DB te 15 ashle 1500% hoye jacchilo. Ekhon 15 ba 0.15 — duitai 0.15.
    final retPct = _normalizeRate(d('expectedReturnPct'));
    final retPctLabel = _pct(retPct * 100); // "15%"
    final expReturn = (amount * retPct * 100).roundToDouble() / 100;
    final totalExpected = amount + expReturn;

    // Dates — Bangladesh time e, calendar month add kore (website er motoi)
    final issuedDateStr = s('issuedDate');
    final activatedAt = DateTime.tryParse(issuedDateStr) ?? DateTime.now();
    final start = _toDhaka(activatedAt);
    final startDay = DateTime.utc(start.year, start.month, start.day);
    final maturityDay = DateTime.utc(start.year, start.month + durationMonths, start.day);
    final durationDays = maturityDay.difference(startDay).inDays; // 12 mash = 365
    String dayLabel(DateTime u) => '${u.day} ${_monthsLong[u.month - 1]} ${u.year}';
    final effectiveLabel = _bdDate(activatedAt);
    final maturityLabel = dayLabel(maturityDay);

    pw.Widget hRule(PdfColor color, double w) =>
        pw.Container(height: w, color: color);

    pw.Widget figure(String label, String value, String sub) => pw.Expanded(
      child: pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(8, 10, 8, 10),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(label,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: helv, fontSize: 6.5, color: muted, letterSpacing: 1)),
            pw.SizedBox(height: 6),
            pw.Text(value,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: helvB, fontSize: 12.5, color: brandDark)),
            pw.SizedBox(height: 4),
            pw.Text(sub,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: helv, fontSize: 7, color: muted)),
          ],
        ),
      ),
    );

    pw.Widget detailColumn(String heading, List<List<String>> rows, double labelW) =>
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(heading.toUpperCase(),
                  style: pw.TextStyle(font: helvB, fontSize: 7.5, color: brand, letterSpacing: 1.4)),
              pw.SizedBox(height: 5),
              hRule(brand, 0.8),
              pw.SizedBox(height: 6),
              for (final r in rows) ...[
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: labelW,
                      child: pw.Text(r[0],
                          style: pw.TextStyle(font: helv, fontSize: 8, color: muted)),
                    ),
                    pw.Expanded(
                      child: pw.Text(r[1],
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(font: helvB, fontSize: 8, color: ink)),
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                hRule(rule, 0.4),
                pw.SizedBox(height: 4),
              ],
            ],
          ),
        );

    final investorRows = <List<String>>[
      ['Name', name],
      ['Email', email],
      if (phone.isNotEmpty) ['Phone', phone],
      ['Investment ID', investmentId.substring(0, investmentId.length >= 8 ? 8 : investmentId.length).toUpperCase()],
    ];

    final investmentRows = <List<String>>[
      ['Group / tier', title],
      ['Return type', 'Profit Share'],
      ['Return rate', retPctLabel],
      ['Effective date', effectiveLabel],
      ['Maturity date', maturityLabel],
      ['Expected return', _bdt(expReturn)],
      ['Total expected', _bdt(totalExpected)],
    ];

    final statement =
        'has invested ${_bdt(amount)} in "$title", a business group tier '
        'administered through Biniyog Club, with effect from $effectiveLabel for a term of $durationDays days.';

    final doc = pw.Document(
      title: 'Investment Certificate - $receiptNumber',
      author: 'Biniyog Club',
      subject: 'Investment Certificate',
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Stack(
          children: [
            pw.Positioned(
              left: 18, top: 18, right: 18, bottom: 18,
              child: pw.Container(
                decoration: pw.BoxDecoration(border: pw.Border.all(color: brand, width: 2)),
              ),
            ),
            pw.Positioned(
              left: 24, top: 24, right: 24, bottom: 24,
              child: pw.Container(
                decoration: pw.BoxDecoration(border: pw.Border.all(color: gold, width: 0.6)),
              ),
            ),
            for (final pos in const [
              [21.0, 21.0, null, null], [null, 21.0, 21.0, null],
              [21.0, null, null, 21.0], [null, null, 21.0, 21.0],
            ])
              pw.Positioned(
                left: pos[0], top: pos[1], right: pos[2], bottom: pos[3],
                child: pw.Container(width: 6, height: 6, color: gold),
              ),

            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(58, 50, 58, 0),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.SizedBox(height: 6),
                            pw.Text('BINIYOG CLUB',
                                style: pw.TextStyle(font: helvB, fontSize: 15, color: brand, letterSpacing: 1.6)),
                            pw.SizedBox(height: 4),
                            pw.Text('A $groupName Investment Platform',
                                style: pw.TextStyle(font: helv, fontSize: 7.5, color: muted, letterSpacing: 0.4)),
                          ],
                        ),
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('CERTIFICATE NO.',
                              style: pw.TextStyle(font: helv, fontSize: 6.5, color: muted, letterSpacing: 1)),
                          pw.SizedBox(height: 2),
                          pw.Text(receiptNumber,
                              style: pw.TextStyle(font: helvB, fontSize: 9.5, color: ink)),
                          pw.SizedBox(height: 6),
                          pw.Text('DATE OF ISSUE',
                              style: pw.TextStyle(font: helv, fontSize: 6.5, color: muted, letterSpacing: 1)),
                          pw.SizedBox(height: 2),
                          pw.Text(effectiveLabel,
                              style: pw.TextStyle(font: helvB, fontSize: 8.5, color: ink)),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 35),
                  pw.Center(
                    child: pw.Column(
                      children: [
                        pw.Text('OFFICIAL RECORD',
                            style: pw.TextStyle(font: helv, fontSize: 8, color: gold, letterSpacing: 2)),
                        pw.SizedBox(height: 8),
                        pw.Text('Certificate of Investment',
                            style: pw.TextStyle(font: pw.Font.timesBold(), fontSize: 28, color: brandDark)),
                        pw.SizedBox(height: 8),
                        pw.Text('This is to certify that',
                            style: pw.TextStyle(font: pw.Font.timesItalic(), fontSize: 11, color: muted)),
                        pw.SizedBox(height: 8),
                        pw.Text(name,
                            style: pw.TextStyle(font: pw.Font.timesBold(), fontSize: 18, color: ink)),
                        pw.SizedBox(height: 6),
                        pw.Container(width: 140, height: 0.8, color: gold),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 25),
                  pw.Text(
                    statement,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: pw.Font.times(), fontSize: 10, color: ink, lineSpacing: 1.4),
                  ),
                  pw.SizedBox(height: 25),

                  pw.Container(
                    decoration: pw.BoxDecoration(
                      color: brandTint,
                      border: pw.Border.all(color: brand, width: 0.8),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Row(
                      children: [
                        figure('PRINCIPAL', _bdt(amount), 'Amount invested'),
                        pw.Container(width: 0.8, height: 45, color: brand),
                        figure('EXPECTED RETURN', _bdt(expReturn), '$retPctLabel of principal'),
                        pw.Container(width: 0.8, height: 45, color: brand),
                        figure('MATURITY DATE', maturityLabel, '$durationDays-day term'),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),

                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      detailColumn('Investor', investorRows, 62),
                      pw.SizedBox(width: 16),
                      detailColumn('Investment', investmentRows, 75),
                    ],
                  ),
                  pw.Spacer(),

                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        width: 75,
                        height: 75,
                        padding: const pw.EdgeInsets.all(4),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: rule),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: verifyUrl,
                          color: ink,
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('VERIFY AUTHENTICITY',
                                style: pw.TextStyle(font: helvB, fontSize: 7.5, color: brand, letterSpacing: 0.8)),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              'Scan the QR code or visit the address below. The verification page shows the original record held by Biniyog Club; an altered document will not match.',
                              style: pw.TextStyle(font: helv, fontSize: 6.5, color: muted, lineSpacing: 1.2),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              verifyUrl,
                              style: pw.TextStyle(font: helvB, fontSize: 6.5, color: brand),
                            ),
                          ],
                        ),
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('Biniyog Club',
                              style: pw.TextStyle(font: pw.Font.timesBoldItalic(), fontSize: 13, color: brandDark)),
                          pw.SizedBox(height: 2),
                          hRule(rule, 0.8),
                          pw.SizedBox(height: 3),
                          pw.Text('Authorised on behalf of Biniyog Club',
                              style: pw.TextStyle(font: helv, fontSize: 6, color: muted)),
                          pw.Text('Electronically issued - no signature required',
                              style: pw.TextStyle(font: helv, fontSize: 6, color: muted)),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 15),
                  hRule(rule, 0.6),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Returns shown are projections based on the project\'s stated rate and are subject to project performance. This certificate is system-generated and cryptographically signed; it is not a negotiable instrument.',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: helv, fontSize: 5.5, color: muted, lineSpacing: 1.2),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text('Biniyog Club', style: pw.TextStyle(font: helvB, fontSize: 6, color: brand)),
                      pw.Text('  ·  ', style: pw.TextStyle(font: helv, fontSize: 6, color: muted)),
                      pw.Text('Dhaka, Bangladesh', style: pw.TextStyle(font: helv, fontSize: 6, color: muted)),
                      pw.Text('  ·  ', style: pw.TextStyle(font: helv, fontSize: 6, color: muted)),
                      pw.Text('info@biniyogclub.com', style: pw.TextStyle(font: helv, fontSize: 6, color: muted)),
                      pw.Text('  ·  ', style: pw.TextStyle(font: helv, fontSize: 6, color: muted)),
                      pw.Text('www.biniyogclub.com', style: pw.TextStyle(font: helv, fontSize: 6, color: muted)),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }
}