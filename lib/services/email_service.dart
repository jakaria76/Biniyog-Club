import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/db_config.dart';
import 'database_service.dart';
import 'pdf_service.dart';

/// ═══════════════════════════════════════════════════════════════════
/// Investor der email — forgot password OTP er motoi app theke Resend diye.
///
/// EKHON SHUDHU EKTA MAIL JAY:
///   APPROVED — admin website e project / group investment approve korle,
///              sathe Documents page er hubohu Investment Certificate PDF
///              attachment hishebe (Gmail theke download kora jay).
///
/// Welcome / Pending / Payment submitted / Cancelled / Rejected mail BONDHO
/// (egulor jonno phone e push notification ache).
///
/// checkStatusMails() — dashboard khulle r app khola thakle protি minute e.
/// email_log table e (kind, ref_id) rakhi → ek mail kokhono duibar jay na.
/// Mail fail korle log muche dei → porer bar abar chesta hoy.
/// ═══════════════════════════════════════════════════════════════════
class EmailService {
  static const String _from = 'Biniyog Club <noreply@biniyogclub.com>';
  static const String _replyTo = 'support@biniyogclub.com';
  static const String _site = 'https://biniyogclub.com';
  static const String _noEmailDomain = '@noemail.biniyogclub.com';

  static final http.Client _http = http.Client();
  static bool _tableReady = false;
  static bool _checking = false;
  static DateTime? _lastCheck;

  // ═════════════════════════════════════════════════════════
  // PUBLIC
  // ═════════════════════════════════════════════════════════

  // ─── Egulo ekhon BONDHO — shudhu approve mail jay. Function gulo rakha holo
  // jate database_service.dart e kichu bodlate na hoy. ───
  static Future<void> sendWelcome({
    required String userId,
    required String name,
    required String email,
  }) async {}

  static Future<void> sendProjectPending(String investmentId) async {}

  static Future<void> sendGroupPending(String groupInvestmentId) async {}

  static Future<void> sendProjectPaymentSubmitted(String submissionId) async {}

  static Future<void> sendGroupPaymentSubmitted(String groupInvestmentId) async {}

  /// Admin website e approve / cancel / reject korle — ei user er jonno check.
  /// Dashboard khulle r app khola thakle protি minute e dake.
  static Future<void> checkStatusMails(String userId) async {
    if (userId.isEmpty || _checking) return;
    final now = DateTime.now();
    if (_lastCheck != null && now.difference(_lastCheck!).inSeconds < 30) return;
    _checking = true;
    _lastCheck = now;
    try {
      if (!await _ensureTables()) return;
      await _seedUserOnce(userId);

      // Majhpothe atke thaka "sending" (app bondho hoye gechilo) — abar chesta
      await DatabaseService.executeNeonHttp('''
        DELETE FROM email_log WHERE status = 'sending' AND created_at < NOW() - INTERVAL '10 minutes'
      ''');

      // Shudhu APPROVED — project r group
      final rows = <Map<String, dynamic>>[
        ...await DatabaseService.queryNeonHttp(
            _projectQuery('APPROVED', 'p."userId" = \$1 AND i."status"::text IN (\'ACTIVE\', \'MATURED\', \'COMPLETED\')'),
            [userId]),
        ...await DatabaseService.queryNeonHttp(
            _groupQuery('APPROVED', 'gi."investorUserId" = \$1 AND gi."status"::text IN (\'ACTIVE\', \'COMPLETED\')'),
            [userId]),
      ];
      if (rows.isEmpty) return;

      // Documents page je data diye certificate banay, oi data-i
      final projectCerts = await DatabaseService.getWebsiteCertificates(userId);
      final groupCerts = await DatabaseService.getGroupWebsiteCertificates(userId);

      for (final ev in rows) {
        final d = _asMap(ev['d']);
        final isGroup = d['group'] == true || d['group']?.toString() == 'true';
        final ref = ev['ref_id']?.toString() ?? '';
        final certs = isGroup ? groupCerts : projectCerts;
        final cert = certs.cast<Map<String, dynamic>?>().firstWhere(
              (c) => c?['id']?.toString() == ref,
              orElse: () => null,
            );

        // Project er certificate website ektu pore banay — tokhon opekkha.
        // 2 ghonta por-o na hole certificate chara-i mail (app e pore pabe).
        if (cert == null && !_olderThan(d['at'], const Duration(hours: 2))) continue;

        (String, Uint8List)? attachment;
        if (cert != null) {
          try {
            final bytes = isGroup
                ? await PdfService.buildGroupWebsiteCertificate(cert)
                : await PdfService.buildWebsiteCertificate(cert);
            attachment = ('Certificate_${cert['certificateNo'] ?? ref}.pdf', bytes);
          } catch (e) {
            debugPrint('Certificate PDF error ($ref): $e');
            continue; // porer bar abar chesta
          }
        }

        await _deliver(ev, attachment: attachment);
        await Future.delayed(const Duration(milliseconds: 600)); // Resend rate limit
      }
    } catch (e) {
      debugPrint('Email status check error: $e');
    } finally {
      _checking = false;
    }
  }

  // ═════════════════════════════════════════════════════════
  // TABLES (website er Prisma schema te nei — app nijei banay,
  // password_reset_tokens er motoi)
  // ═════════════════════════════════════════════════════════
  static Future<bool> _ensureTables() async {
    if (_tableReady) return true;
    final a = await DatabaseService.executeNeonHttp('''
      CREATE TABLE IF NOT EXISTS email_log (
        kind       TEXT NOT NULL,
        ref_id     TEXT NOT NULL,
        email      TEXT,
        status     TEXT NOT NULL DEFAULT 'sent',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        sent_at    TIMESTAMPTZ,
        PRIMARY KEY (kind, ref_id)
      )
    ''');
    final b = await DatabaseService.executeNeonHttp('''
      CREATE TABLE IF NOT EXISTS email_worker_state (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    _tableReady = a && b;
    return _tableReady;
  }

  /// Ei user prothom bar check hole tar purono approve/cancel/reject
  /// "seeded" — purono ghotonar mail hothat jabe na, shudhu porer gulo.
  static Future<void> _seedUserOnce(String userId) async {
    final key = 'seeded_user:$userId';
    final done = await DatabaseService.queryNeonHttp(
        'SELECT 1 AS "x" FROM email_worker_state WHERE key = \$1', [key]);
    if (done.isNotEmpty) return;
    if (DatabaseService.lastRequestFailed) return; // net nei — porer bar

    final stmts = [
      '''INSERT INTO email_log (kind, ref_id, status)
         SELECT 'APPROVED', i."id", 'seeded' FROM investments i
         JOIN investor_profiles p ON p."id" = i."investorProfileId"
         WHERE p."userId" = \$1 AND i."status"::text IN ('ACTIVE', 'MATURED', 'COMPLETED')
         ON CONFLICT DO NOTHING''',
      '''INSERT INTO email_log (kind, ref_id, status)
         SELECT 'APPROVED', gi."id", 'seeded' FROM group_investments gi
         WHERE gi."investorUserId" = \$1 AND gi."status"::text IN ('ACTIVE', 'COMPLETED')
         ON CONFLICT DO NOTHING''',
      '''INSERT INTO email_log (kind, ref_id, status)
         SELECT 'CANCELLED', i."id", 'seeded' FROM investments i
         JOIN investor_profiles p ON p."id" = i."investorProfileId"
         WHERE p."userId" = \$1 AND i."status"::text = 'CANCELLED'
         ON CONFLICT DO NOTHING''',
      '''INSERT INTO email_log (kind, ref_id, status)
         SELECT 'CANCELLED', gi."id", 'seeded' FROM group_investments gi
         WHERE gi."investorUserId" = \$1 AND gi."status"::text = 'CANCELLED'
         ON CONFLICT DO NOTHING''',
      '''INSERT INTO email_log (kind, ref_id, status)
         SELECT 'REJECTED', m."id", 'seeded' FROM manual_payment_submissions m
         JOIN investments i ON i."id" = m."investmentId"
         JOIN investor_profiles p ON p."id" = i."investorProfileId"
         WHERE p."userId" = \$1 AND m."status"::text = 'REJECTED'
         ON CONFLICT DO NOTHING''',
      '''INSERT INTO email_log (kind, ref_id, status)
         SELECT 'REJECTED', x."id", 'seeded' FROM group_investment_payments x
         JOIN group_investments gi ON gi."id" = x."groupInvestmentId"
         WHERE gi."investorUserId" = \$1 AND x."status"::text = 'REJECTED'
         ON CONFLICT DO NOTHING''',
    ];
    for (final s in stmts) {
      if (!await DatabaseService.executeNeonHttp(s, [userId])) return; // abar porer bar
    }
    await DatabaseService.executeNeonHttp(
      'INSERT INTO email_worker_state (key, value) VALUES (\$1, NOW()::text) ON CONFLICT DO NOTHING',
      [key],
    );
  }

  // ═════════════════════════════════════════════════════════
  // QUERIES — protita row: kind, ref_id, email, name, d (details)
  // ═════════════════════════════════════════════════════════
  static String _userOk(String u) => '''
    $u."role"::text = 'INVESTOR'
    AND $u."email" IS NOT NULL AND $u."email" <> ''
    AND $u."email" NOT ILIKE '%$_noEmailDomain'
    AND $u."deletedAt" IS NULL''';

  static String _notLogged(String kind, String ref) =>
      "NOT EXISTS (SELECT 1 FROM email_log l WHERE l.kind = '$kind' AND l.ref_id = $ref)";

  static const String _groupTitle =
      '''bg."name" || CASE WHEN LOWER(ge."name") <> LOWER(bg."name") THEN ' — ' || ge."name" ELSE '' END || ' · ' || gt."name"''';

  static String _projectQuery(String kind, String where) => '''
    SELECT '$kind' AS "kind", i."id" AS "ref_id", u."email", u."name",
           jsonb_build_object('group', false, 'title', pr."title", 'amount', i."amountBdt",
                              'receipt', i."receiptNumber", 'reason', i."cancellationReason",
                              'at', COALESCE(i."activatedAt", i."updatedAt")) AS "d"
    FROM investments i
    JOIN investor_profiles p ON p."id" = i."investorProfileId"
    JOIN users u             ON u."id" = p."userId"
    JOIN projects pr         ON pr."id" = i."projectId"
    WHERE ${_userOk('u')} AND $where AND ${_notLogged(kind, 'i."id"')}
    LIMIT 20''';

  static String _groupQuery(String kind, String where) => '''
    SELECT '$kind' AS "kind", gi."id" AS "ref_id", u."email", u."name",
           jsonb_build_object('group', true, 'title', $_groupTitle, 'amount', gi."amountBdt",
                              'receipt', gi."receiptNumber", 'plot', gi."plotNumber",
                              'at', gi."updatedAt") AS "d"
    FROM group_investments gi
    JOIN users u            ON u."id" = gi."investorUserId"
    JOIN group_tiers gt     ON gt."id" = gi."tierId"
    JOIN group_entities ge  ON ge."id" = gt."entityId"
    JOIN business_groups bg ON bg."id" = ge."groupId"
    WHERE ${_userOk('u')} AND $where AND ${_notLogged(kind, 'gi."id"')}
    LIMIT 20''';

  // ═════════════════════════════════════════════════════════
  // DELIVER — claim → send → sent (fail hole claim muche dei)
  // ═════════════════════════════════════════════════════════
  static Future<void> _deliver(Map<String, dynamic> ev, {(String, Uint8List)? attachment}) async {
    final kind = ev['kind']?.toString() ?? '';
    final ref = ev['ref_id']?.toString() ?? '';
    final to = ev['email']?.toString().trim() ?? '';
    if (kind.isEmpty || ref.isEmpty || to.isEmpty) return;

    try {
      if (!await _ensureTables()) return;

      // Onno kotha theke (onno phone / ager chesta) already pathano hole kichu ferot ashbe na
      final claim = await DatabaseService.queryNeonHttp('''
        INSERT INTO email_log (kind, ref_id, email, status)
        VALUES (\$1, \$2, \$3, 'sending')
        ON CONFLICT (kind, ref_id) DO NOTHING
        RETURNING kind
      ''', [kind, ref, to]);
      if (claim.isEmpty) return;

      final mail = _render(kind, ev, hasPdf: attachment != null);
      final ok = await _send(to, mail.$1, mail.$2, mail.$3, attachment: attachment);

      if (ok) {
        await DatabaseService.executeNeonHttp(
            "UPDATE email_log SET status = 'sent', sent_at = NOW() WHERE kind = \$1 AND ref_id = \$2", [kind, ref]);
      } else {
        await DatabaseService.executeNeonHttp(
            'DELETE FROM email_log WHERE kind = \$1 AND ref_id = \$2', [kind, ref]);
      }
    } catch (e) {
      debugPrint('Email deliver error ($kind $ref): $e');
    }
  }

  // ═════════════════════════════════════════════════════════
  // RESEND (forgot password er moto)
  // ═════════════════════════════════════════════════════════
  static Future<bool> _send(String to, String subject, String html, String text,
      {(String, Uint8List)? attachment}) async {
    final apiKey = DbConfig.resendApiKey.trim();
    if (apiKey.isEmpty || apiKey == 'your_resend_api_key') {
      debugPrint('Resend key nei — mail gelo na');
      return false;
    }
    try {
      final res = await _http
          .post(
            Uri.parse('https://api.resend.com/emails'),
            headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
            body: jsonEncode({
              'from': _from,
              'to': [to],
              'reply_to': _replyTo,
              'subject': subject,
              'html': html,
              'text': text,
              if (attachment != null)
                'attachments': [
                  {'filename': attachment.$1, 'content': base64Encode(attachment.$2)},
                ],
            }),
          )
          .timeout(const Duration(seconds: 45));
      if (res.statusCode >= 200 && res.statusCode < 300) return true;
      debugPrint('Resend error ${res.statusCode}: ${res.body}');
      return false;
    } catch (e) {
      debugPrint('Resend exception: $e');
      return false;
    }
  }

  // ═════════════════════════════════════════════════════════
  // TEMPLATES — (subject, html, text)
  // ═════════════════════════════════════════════════════════
  static (String, String, String) _render(String kind, Map<String, dynamic> ev, {bool hasPdf = false}) {
    final d = _asMap(ev['d']);
    final name = _esc((ev['name']?.toString() ?? '').trim().isEmpty ? 'Investor' : ev['name'].toString().trim());
    final rawTitle = d['title']?.toString() ?? '';
    final title = _esc(rawTitle);
    final amount = _fmtTk(d['amount']);
    final receipt = _esc(d['receipt']?.toString() ?? '');
    final plot = _esc(d['plot']?.toString() ?? '');
    final reason = (d['reason']?.toString() ?? '').trim();
    final isGroup = d['group'] == true || d['group']?.toString() == 'true';
    final where = isGroup ? 'Group Investments' : 'Investments';
    final forTitle = rawTitle.isEmpty ? '' : ': $rawTitle';

    final rows = <(String, String)>[
      if (title.isNotEmpty) ('Investment', title),
      if (amount.isNotEmpty) ('Amount', amount),
      if (receipt.isNotEmpty) ('Receipt no.', receipt),
      if (plot.isNotEmpty) ('Plot no.', plot),
    ];

    switch (kind) {
      case 'WELCOME':
        return _mail(
          subject: 'Welcome to Biniyog Club',
          heading: 'Welcome to Biniyog Club',
          name: name,
          paras: [
            'Your account is ready. You can now browse open projects and business groups and invest right from the Biniyog Club app.',
            'Every payment you submit is reviewed by our team, and you will get an email at each step — when it is received, approved, or if anything needs your attention.',
          ],
        );

      case 'PENDING':
        return _mail(
          subject: 'Investment received — pending approval$forTitle',
          heading: 'Investment received',
          badge: ('PENDING REVIEW', '#8A6A3A', '#F6EEDF'),
          name: name,
          paras: [
            'We have received your investment and payment details. Our team will verify the payment shortly.',
            'You will get another email as soon as it is approved.',
          ],
          rows: rows,
        );

      case 'SUBMITTED':
        return _mail(
          subject: 'Payment received — under review$forTitle',
          heading: 'Payment received',
          badge: ('UNDER REVIEW', '#8A6A3A', '#F6EEDF'),
          name: name,
          paras: [
            'We have received your payment details. Our team will verify them shortly.',
            'You will get another email as soon as your investment is approved.',
          ],
          rows: rows,
        );

      case 'APPROVED':
        return _mail(
          subject: 'Your investment is approved$forTitle',
          heading: 'Investment approved',
          badge: ('ACTIVE', '#0E4A37', '#E3F0E9'),
          name: name,
          paras: [
            'Alhamdulillah — your payment has been verified and your investment is now active.',
            hasPdf
                ? 'Your <strong>Investment Certificate</strong> is attached to this email as a PDF. '
                    'Open the attachment to view it, or download and keep it for your records.'
                : 'Your investment certificate is being prepared — you will find it in the Documents section of the app.',
            isGroup
                ? 'You can also see this investment in the Group Investments section of the app.'
                : 'You can also see this investment in the Investments section of the app.',
          ],
          rows: rows,
        );

      case 'CANCELLED':
        return _mail(
          subject: 'Your investment has been cancelled$forTitle',
          heading: 'Investment cancelled',
          badge: ('CANCELLED', '#B4413A', '#FBEAE8'),
          name: name,
          paras: [
            'Your investment below has been cancelled.',
            if (reason.isNotEmpty) 'Reason: ${_esc(reason)}',
            'If you think this is a mistake, simply reply to this email or write to support@biniyogclub.com.',
          ],
          rows: rows,
        );

      case 'REJECTED':
        final ref = _esc(d['ref']?.toString() ?? '');
        return _mail(
          subject: 'Your payment proof needs attention$forTitle',
          heading: 'Payment proof not accepted',
          badge: ('ACTION NEEDED', '#A5523A', '#F7E6DF'),
          name: name,
          paras: [
            'Our team could not verify the payment you submitted for the investment below.',
            if (reason.isNotEmpty) 'Reason: ${_esc(reason)}',
            'Please open the app → $where, and tap "Submit Again" with the correct payment details.',
          ],
          rows: [...rows, if (ref.isNotEmpty) ('Your reference', ref)],
        );

      default:
        throw StateError('unknown email kind $kind');
    }
  }

  static (String, String, String) _mail({
    required String subject,
    required String heading,
    (String, String, String)? badge,
    required String name,
    required List<String> paras,
    List<(String, String)> rows = const [],
  }) {
    final badgeHtml = badge == null
        ? ''
        : '<span style="display:inline-block;margin-top:10px;padding:4px 10px;border-radius:20px;font-size:11px;'
            'font-weight:bold;letter-spacing:1px;color:${badge.$2};background:${badge.$3};">${badge.$1}</span>';

    final table = rows.isEmpty
        ? ''
        : '<table role="presentation" style="width:100%;border-collapse:collapse;margin:18px 0 4px;background:#F7F4EE;border-radius:12px;">'
            '${rows.map((r) => '<tr>'
                '<td style="padding:10px 14px;font-size:12.5px;color:#6E736F;">${r.$1}</td>'
                '<td style="padding:10px 14px;font-size:13.5px;color:#1C2421;font-weight:bold;text-align:right;">${r.$2}</td>'
                '</tr>').join()}'
            '</table>';

    final html = '''
<div style="font-family:Arial,Helvetica,sans-serif;background:#f6f1e7;padding:28px 12px;">
  <div style="max-width:500px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #e8dfc9;">
    <div style="background:#0f4d3a;padding:22px 24px;">
      <div style="color:#d4af61;font-size:12px;letter-spacing:2px;font-weight:bold;">BINIYOG CLUB</div>
      <div style="color:#ffffff;font-size:20px;font-weight:bold;margin-top:6px;">${_esc(heading)}</div>
      $badgeHtml
    </div>
    <div style="padding:24px;">
      <p style="color:#1f2a24;font-size:14px;margin:0 0 12px;">Assalamu Alaikum <strong>$name</strong>,</p>
      ${paras.map((p) => '<p style="color:#3d4a43;font-size:14px;line-height:1.55;margin:0 0 12px;">$p</p>').join()}
      $table
      <p style="color:#6b7570;font-size:12px;margin:18px 0 0;">Expected returns are estimates, not guaranteed. Only pay into the official accounts shown in the app.</p>
    </div>
    <div style="border-top:1px solid #efe8d8;padding:14px 24px;color:#9a8f73;font-size:11.5px;">
      Biniyog Club · <a href="$_site" style="color:#0f4d3a;">biniyogclub.com</a>
    </div>
  </div>
</div>''';

    final text = [
      'Assalamu Alaikum ${_unesc(name)},',
      '',
      ...paras.map(_unesc),
      '',
      ...rows.map((r) => '${r.$1}: ${_unesc(r.$2)}'),
      '',
      '— Biniyog Club',
      _site,
    ].join('\n');

    return (subject, html, text);
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  static bool _olderThan(dynamic raw, Duration age) {
    final s = raw?.toString() ?? '';
    if (s.isEmpty) return true;
    var t = s.replaceFirst(' ', 'T');
    if (!RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(t)) t = '${t}Z';
    final d = DateTime.tryParse(t);
    return d == null || DateTime.now().toUtc().difference(d.toUtc()) > age;
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String && v.isNotEmpty) {
      try {
        final d = jsonDecode(v);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return {};
  }

  static String _fmtTk(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    if (n == null) return '';
    final s = n.toStringAsFixed(0);
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return 'BDT $b';
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  static String _unesc(String s) => s
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
}
