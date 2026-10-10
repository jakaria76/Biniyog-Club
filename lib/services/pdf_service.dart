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
}