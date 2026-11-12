import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import '../config/db_config.dart';
import 'email_service.dart';
import 'push_service.dart';

class DatabaseService {
  static final http.Client _httpClient = http.Client();
  static Connection? _connection;
  static String? _lastConnectionError;

  /// Shesh je DB error hoyeche — onno query shuru hole MUCHE NA (shudhu
  /// invest/payment er shuru te muchi), tai ashol karon ta dekhano jay
  static String? _lastDbFailure;

  static const String websiteBaseUrl = 'https://biniyogclub.com';

  static const String _loginRequiredMsg = 'Please log in again to continue.';

  // ═════════════════════════════════════════════════════════
  // SMALL HELPERS
  // ═════════════════════════════════════════════════════════
  static double _toDouble(dynamic v, [double fallback = 0.0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  static double? _toDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  /// DB te kokhono 16 thake, kokhono 0.16 — shob 0.16 e ani
  static double _normalizePct(dynamic v, [double fallback = 0.0]) {
    final d = _toDouble(v, fallback);
    return d > 1.0 ? d / 100.0 : d;
  }

  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  /// Website er deadline.ts: Dhaka (UTC+6) er calendar din hishebe deadline
  /// er tarikh — aj theke koto din. 0 = aj shesh din, -1 = gotokal shesh hoyeche.
  /// Deadline na thakle null.
  static int? deadlineDaysDhaka(dynamic deadline) {
    final raw = deadline?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    DateTime dhakaDay(DateTime x) {
      final d = x.toUtc().add(const Duration(hours: 6));
      return DateTime.utc(d.year, d.month, d.day);
    }

    DateTime? day;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
      // Shudhu tarikh — sheta-i Dhaka er tarikh
      final p = raw.split('-').map(int.parse).toList();
      day = DateTime.utc(p[0], p[1], p[2]);
    } else {
      var t = raw.replaceFirst(' ', 'T');
      // DB er timestamp UTC te thake, timezone lekha thake na
      if (!RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(t)) t = '${t}Z';
      final d = DateTime.tryParse(t);
      if (d == null) return null;
      day = dhakaDay(d);
    }
    return day.difference(dhakaDay(DateTime.now())).inDays;
  }

  /// Deadline er din periye geche? (deadline er din porjonto invest kora jay)
  static bool deadlinePassed(dynamic deadline) {
    final d = deadlineDaysDhaka(deadline);
    return d != null && d < 0;
  }

  /// Deadline na thakle 0 — banano "116 days" r dekhabo na
  static int _daysLeft(String? deadline) {
    final d = deadlineDaysDhaka(deadline);
    return d == null ? 0 : d.clamp(0, 3650);
  }

  /// SQL: deadline nei, ba Dhaka er aj-er tarikh porjonto ache
  static const String _deadlineOpenSql =
  '''(p."fundingDeadline" IS NULL OR (p."fundingDeadline" AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Dhaka')::date >= (NOW() AT TIME ZONE 'Asia/Dhaka')::date)''';

  static String _mimeFromDataUri(String s) {
    final m = RegExp(r'^data:([^;,]+)[;,]').firstMatch(s);
    return m?.group(1) ?? 'image/png';
  }

  static String _connectionErrorMsg() =>
      _lastConnectionError != null
          ? 'Could not reach the server. Please check your internet connection.'
          : 'Something went wrong. Please try again.';

  /// Save fail hole ashol karon shoho message (net na thakle net er kotha)
  static String _saveFailMsg(String what) {
    final e = _lastDbFailure ?? _lastConnectionError ?? '';
    if (e.isEmpty) return '$what Please try again.';
    final low = e.toLowerCase();
    if (low.contains('socketexception') ||
        low.contains('timeoutexception') ||
        low.contains('failed host lookup') ||
        low.contains('clientexception') ||
        low.contains('connection refused') ||
        low.contains('connection reset') ||
        low.contains('connection closed')) {
      return 'Could not reach the server. Please check your internet connection.';
    }
    return '$what (${_shortDbError()})';
  }

  // Image URL Resolver for Cloudinary / Neon Postgres URLs
  static String formatImageUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return 'https://images.unsplash.com/photo-1595273670150-bd0c3c392e46?q=80&w=800&auto=format&fit=crop';
    }
    final url = rawUrl.trim();
    if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('data:image/')) {
      return url;
    }
    final cloudName = DbConfig.cloudinaryCloudName;
    if (cloudName.isNotEmpty && cloudName != 'your_cloud_name') {
      return 'https://res.cloudinary.com/$cloudName/image/upload/$url';
    }
    return 'https://res.cloudinary.com/demo/image/upload/$url';
  }

  // ═════════════════════════════════════════════════════════
  // NEON HTTP SQL
  // ═════════════════════════════════════════════════════════
  static Uri _getNeonHttpSqlUri() {
    try {
      final dbUrl = DbConfig.databaseUrl.trim();
      final uri = Uri.parse(dbUrl);
      final host = uri.host;
      if (host.isNotEmpty) {
        return Uri.parse('https://$host/sql');
      }
    } catch (_) {}
    return Uri.parse('https://ep-withered-lake-b5bgohpl-pooler.c-7.us-east-2.aws.neon.tech/sql');
  }

  static Future<List<Map<String, dynamic>>> queryNeonHttp(String querySql, [List<dynamic>? params]) async {
    final dbUrl = DbConfig.databaseUrl.trim();
    final endpoint = _getNeonHttpSqlUri();
    _lastConnectionError = null;
    String? myError;

    // 2 tries with 15s timeout each to quickly recover from cold starts
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final response = await _httpClient.post(
          endpoint,
          headers: {
            'Content-Type': 'application/json',
            'neon-connection-string': dbUrl,
          },
          body: jsonEncode({
            'query': querySql,
            if (params != null && params.isNotEmpty) 'params': params,
          }),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List rows = data['rows'] as List? ?? [];
          // 1st try fail, 2nd try pass hole shudhu NIJER purono error muchi
          // (parallel onno query er error muchbo na)
          if (myError != null && _lastConnectionError == myError) _lastConnectionError = null;
          return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
        } else {
          debugPrint("Neon HTTP Query Error (attempt $attempt) Status ${response.statusCode}: ${response.body}");
          _lastConnectionError = myError = _lastDbFailure = "HTTP ${response.statusCode}: ${response.body}";
        }
      } catch (e) {
        debugPrint("Neon HTTP Query Exception (attempt $attempt): $e");
        _lastConnectionError = myError = _lastDbFailure = e.toString();
        if (attempt == 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    return [];
  }

  // Execute Non-Query SQL Statement via Neon HTTP API
  static Future<bool> executeNeonHttp(String statementSql, [List<dynamic>? params]) async {
    final dbUrl = DbConfig.databaseUrl.trim();
    final endpoint = _getNeonHttpSqlUri();
    _lastConnectionError = null;

    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final response = await _httpClient.post(
          endpoint,
          headers: {
            'Content-Type': 'application/json',
            'neon-connection-string': dbUrl,
          },
          body: jsonEncode({
            'query': statementSql,
            if (params != null && params.isNotEmpty) 'params': params,
          }),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          return true;
        } else {
          debugPrint("Neon HTTP Execute Error (attempt $attempt) Status ${response.statusCode}: ${response.body}");
          _lastConnectionError = _lastDbFailure = "HTTP ${response.statusCode}: ${response.body}";
        }
      } catch (e) {
        debugPrint("Neon HTTP Execute Exception (attempt $attempt): $e");
        _lastConnectionError = _lastDbFailure = e.toString();
        if (attempt == 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    return false;
  }

  // Open & get active connection to Neon PostgreSQL with fallback
  static Future<Connection?> getConnection() async {
    try {
      if (_connection != null && _connection!.isOpen) {
        return _connection!;
      }
      _connection = null;

      final dbUrl = DbConfig.databaseUrl.trim();
      final uri = Uri.parse(dbUrl);

      final String neonUser = uri.userInfo.split(':')[0];
      final String neonPass = uri.userInfo.split(':').length > 1 ? uri.userInfo.split(':')[1] : '';
      final String neonDb = uri.path.replaceAll('/', '');
      final int neonPort = uri.port != 0 ? uri.port : 5432;

      try {
        final conn = await Connection.open(
          Endpoint(
            host: uri.host,
            database: neonDb,
            username: neonUser,
            password: neonPass,
            port: neonPort,
          ),
          settings: const ConnectionSettings(
            sslMode: SslMode.require,
          ),
        ).timeout(const Duration(seconds: 8));

        if (conn.isOpen) {
          _connection = conn;
          return _connection!;
        }
      } catch (e) {
        debugPrint("Failed TCP connection attempt ${uri.host}: $e");
      }

      return null;
    } catch (e) {
      _connection = null;
      return null;
    }
  }

  // ═════════════════════════════════════════════════════════
  // PASSWORD
  // ═════════════════════════════════════════════════════════
  static final RegExp _sha256Hex = RegExp(r'^[a-f0-9]{64}$');

  static bool _isBcrypt(String s) =>
      s.startsWith(r'$2a$') || s.startsWith(r'$2b$') || s.startsWith(r'$2y$');

  // Password Hash Helper (bcrypt matching Next.js / Node.js bcrypt)
  static String hashPassword(String password) {
    return BCrypt.hashpw(password, BCrypt.gensalt());
  }

  /// bcrypt → bcrypt diye check. Purono SHA-256 → SHA-256 diye check.
  /// Purono plaintext → shudhu tokhon-i, jokhon DB er value kono hash na.
  /// (Age hash string ta-i password hishebe dile login hoye jeto — eta bondho.)
  static bool verifyPassword(String enteredPassword, String dbPassword) {
    if (dbPassword.isEmpty) return false;

    if (_isBcrypt(dbPassword)) {
      try {
        return BCrypt.checkpw(enteredPassword, dbPassword);
      } catch (e) {
        debugPrint("BCrypt check error: $e");
        return false;
      }
    }

    if (_sha256Hex.hasMatch(dbPassword)) {
      return sha256.convert(utf8.encode(enteredPassword)).toString() == dbPassword;
    }

    return enteredPassword == dbPassword;
  }

  /// bcrypt na hole login er por bcrypt e upgrade kore dibo
  static bool _needsRehash(String dbPassword) => !_isBcrypt(dbPassword);

  /// Shotti random UUID v4 (Prisma @default(uuid()) er moto)
  static String _generateUuid() {
    final rnd = Random.secure();
    final b = List<int>.generate(16, (_) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20, 32)}';
  }

  /// Website er investor.data.ts resolveProfile: profile na thakle shudhu
  /// KYC VERIFIED hole KYC er tottho diye banay, sathe wallet.
  /// (Age eta shobar profile banato ar "emailVerified" = true kore dito —
  /// verify chara. Seta website er niyom na, tai bad.)
  static Future<void> _ensureInvestorProfileExists(String userId) async {
    if (userId.isEmpty) return;
    try {
      final nowStr = _nowIso();
      await executeNeonHttp('''
        WITH k AS (
          SELECT "documentNumber", "dateOfBirth", "addressLine", "city", "nationality"
          FROM kyc
          WHERE "userId" = \$2 AND "status"::text = 'VERIFIED'
            AND NOT EXISTS (SELECT 1 FROM investor_profiles WHERE "userId" = \$2)
        ),
        p AS (
          INSERT INTO investor_profiles ("id", "userId", "nationalId", "dateOfBirth", "address", "city", "country", "createdAt", "updatedAt")
          SELECT \$1, \$2, k."documentNumber", k."dateOfBirth", k."addressLine", k."city", COALESCE(k."nationality", 'BD'), \$3, \$3
          FROM k
          ON CONFLICT ("userId") DO NOTHING
          RETURNING "id"
        )
        INSERT INTO wallets ("id", "userId", "type", "cachedBalance", "currency", "isActive", "createdAt", "updatedAt")
        SELECT \$4, \$2, 'INVESTOR'::"WalletType", 0.00, 'BDT', true, \$3, \$3
        WHERE EXISTS (SELECT 1 FROM p)
        ON CONFLICT ("userId") DO NOTHING
      ''', [_generateUuid(), userId, nowStr, _generateUuid()]);
    } catch (e) {
      debugPrint("Ensure Investor Profile Error: $e");
    }
  }

  // ═════════════════════════════════════════════════════════
  // AUTH
  // ═════════════════════════════════════════════════════════

  // ═════════════════════════════════════════════════════════
  // TABLE SCHEMA (website er Prisma schema ja ache, sheta-i mani)
  // ═════════════════════════════════════════════════════════
  /// table → {column: nullable kina}. Ekbar jene rakhi.
  static final Map<String, Map<String, bool>> _tableCols = {};

  static Future<Map<String, bool>> _columnsOf(String table) async {
    final cached = _tableCols[table];
    if (cached != null) return cached;
    final res = await queryNeonHttp('''
      SELECT column_name AS "c", is_nullable AS "n"
      FROM information_schema.columns
      WHERE table_name = \$1
    ''', [table]);
    final cols = {for (final r in res) r['c'].toString(): r['n']?.toString() == 'YES'};
    if (cols.isNotEmpty) _tableCols[table] = cols;
    return cols;
  }

  /// Email chara account — users."email" NOT NULL hole ei nokol thikana boshe.
  /// Eta kothao dekhano hoy na (profile e "Not provided" dekhay).
  static const String _noEmailDomain = '@noemail.biniyogclub.com';

  static bool isPlaceholderEmail(String? e) => (e ?? '').toLowerCase().endsWith(_noEmailDomain);

  static String _publicEmail(dynamic e) {
    final s = e?.toString() ?? '';
    return isPlaceholderEmail(s) ? '' : s;
  }

  /// +8801… / 01… — duita-i 01… e ani (purono code er jonno rakha)
  static String normalizeBdPhone(String v) =>
      v.replaceAll(RegExp(r'[\s-]'), '').replaceFirst(RegExp(r'^\+?88(?=01)'), '');

  // ═════════════════════════════════════════════════════════
  // PHONE — je kono desh (website er "BD +880" input er motoi)
  // DB te ekhon international format e rakhi: +8801712345678, +447911123456
  // Purono '01…' bhabe save thaka account o khuje pay.
  // ═════════════════════════════════════════════════════════

  /// Desh er code + local number → +E.164 (shamner trunk '0' bad)
  static String toE164(String dialCode, String localNumber) {
    final dial = dialCode.replaceAll(RegExp(r'\D'), '');
    var local = localNumber.replaceAll(RegExp(r'\D'), '');
    // Keu pura number (code shoho) likhe dile abar code boshabo na
    if (local.startsWith(dial) && local.length > dial.length + 6) local = local.substring(dial.length);
    // Italy chara onno desh e local number er shuru te '0' thake na
    if (dial != '39') local = local.replaceFirst(RegExp(r'^0+'), '');
    return '+$dial$local';
  }

  /// Je kono lekha (01…, +880…, 00 44…, +1 (555)…) → +E.164
  static String canonicalPhone(String raw) {
    var v = raw.trim().replaceAll(RegExp(r'[\s\-().]'), '');
    if (v.startsWith('00')) v = '+${v.substring(2)}';
    if (v.startsWith('+')) return '+${v.substring(1).replaceAll(RegExp(r'\D'), '')}';
    if (RegExp(r'^01\d{9}$').hasMatch(v)) return '+880${v.substring(1)}'; // BD local
    if (RegExp(r'^8801\d{9}$').hasMatch(v)) return '+$v';
    return v;
  }

  /// Number ta ki thik? BD hole BD er niyom, onno desh hole 8–15 digit
  static bool isValidPhone(String e164) {
    if (e164.startsWith('+880')) return RegExp(r'^\+8801[3-9]\d{8}$').hasMatch(e164);
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(e164);
  }

  /// DB te je je bhabe save thakte pare (exactly 3 ta — SQL e \$a, \$b, \$c)
  static List<String> phoneVariants(String raw) {
    final e = canonicalPhone(raw);
    final set = <String>{e};
    if (e.startsWith('+8801')) {
      set.add('0${e.substring(4)}'); // 01712345678
      set.add(e.substring(1)); // 8801712345678
    } else if (e.startsWith('+')) {
      set.add(e.substring(1));
    }
    final list = set.toList();
    while (list.length < 3) {
      list.add(list.first);
    }
    return list.take(3).toList();
  }

  // Register User — website er users + investor_profiles + wallets e
  static Future<Map<String, dynamic>> registerUser({
    required String name,
    String? email,
    required String phone,
    required String password,
    // Website er motoi — NID, thikana, nominee pore Profile theke (optional)
    String? nidNumber,
    DateTime? dateOfBirth,
    String? address,
    String? city, // jela — website "city" column e
    String? nomineeNidNumber,
    String? nomineeRelation,
  }) async {
    try {
      final cleanEmail = (email ?? '').trim().toLowerCase();
      final cleanPhone = canonicalPhone(phone);
      final phoneVars = phoneVariants(cleanPhone);
      final cleanNid = (nidNumber ?? '').trim();
      final cleanAddress = (address ?? '').trim();
      final nomineeNid = (nomineeNidNumber ?? '').trim();
      final nomineeRel = (nomineeRelation ?? '').trim();
      // NID, thikana, nominee — pore profile theke deya jay (website er motoi)
      if (name.trim().length < 2 || cleanPhone.isEmpty || dateOfBirth == null) {
        return {'success': false, 'message': 'Please fill in all required fields.'};
      }
      // App er check server eo — website er form er niyom
      if (!isValidPhone(cleanPhone)) {
        return {'success': false, 'message': 'Please enter a valid phone number for the selected country.'};
      }
      if (cleanEmail.isNotEmpty && !RegExp(r'^[\w.+-]+@([\w-]+\.)+[A-Za-z]{2,}$').hasMatch(cleanEmail)) {
        return {'success': false, 'message': 'Please enter a valid email address.'};
      }
      if (password.length < 6) {
        return {'success': false, 'message': 'Password must be at least 6 characters.'};
      }
      final today = DateTime.now();
      if (dateOfBirth.isAfter(DateTime(today.year - 18, today.month, today.day))) {
        return {'success': false, 'message': 'You must be at least 18 years old.'};
      }

      final metas = await Future.wait([_columnsOf('users'), _columnsOf('investor_profiles')]);
      final userCols = metas[0];
      final profCols = metas[1];
      if (userCols.isEmpty || profCols.isEmpty) {
        return {'success': false, 'message': _connectionErrorMsg()};
      }

      // Email dile sheta; na dile column nullable hole NULL, na hole nokol thikana
      String? emailValue;
      if (cleanEmail.isNotEmpty) {
        emailValue = cleanEmail;
      } else if (userCols['email'] == true) {
        emailValue = null;
      } else {
        emailValue = 'u$cleanPhone$_noEmailDomain';
      }

      final userId = _generateUuid();
      final profileId = _generateUuid();
      final walletId = _generateUuid();
      final nowStr = _nowIso();

      // Ek query te: duplicate check + user + investor profile + wallet
      final res = await queryNeonHttp('''
        WITH existing_check_user AS (
          SELECT "id", "email", "phone" FROM users
          WHERE (\$2::text IS NOT NULL AND LOWER("email") = LOWER(\$2::text))
             -- +8801… / 01… / 8801… — je bhabe save thakuk dhora porbe
             OR "phone" IN (\$3::text, \$15::text, \$16::text)
          LIMIT 1
        ),
        existing_check_nid AS (
          SELECT "nationalId" FROM investor_profiles
          WHERE \$8::text IS NOT NULL AND "nationalId" = \$8::text LIMIT 1
        ),
        new_user AS (
          INSERT INTO users (
            "id", "email", "passwordHash", "name", "phone", "role", "status", "emailVerified", "createdAt", "updatedAt"
          )
          SELECT \$1, \$2::text, \$4, \$5, \$3::text, 'INVESTOR'::"UserRole", 'ACTIVE'::"UserStatus", \$12::boolean, \$6, \$6
          WHERE NOT EXISTS (SELECT 1 FROM existing_check_user) AND NOT EXISTS (SELECT 1 FROM existing_check_nid)
          RETURNING "id"
        ),
        new_profile AS (
          INSERT INTO investor_profiles (
            "id", "userId", "nationalId", "nomineeNationalId", "nomineeRelation", "address", "city", "country", "createdAt", "updatedAt"
          )
          SELECT \$7, \$1, \$8::text, \$9::text, \$10::text, \$13::text, \$14::text, 'BD', \$6, \$6
          WHERE EXISTS (SELECT 1 FROM new_user)
          ON CONFLICT ("userId") DO NOTHING
        ),
        new_wallet AS (
          INSERT INTO wallets ("id", "userId", "type", "cachedBalance", "currency", "isActive", "createdAt", "updatedAt")
          SELECT \$11, \$1, 'INVESTOR'::"WalletType", 0.00, 'BDT', true, \$6, \$6
          WHERE EXISTS (SELECT 1 FROM new_user)
          ON CONFLICT ("userId") DO NOTHING
        )
        SELECT
          (SELECT "email" FROM existing_check_user) as existing_email,
          (SELECT "phone" FROM existing_check_user) as existing_phone,
          (SELECT "nationalId" FROM existing_check_nid) as existing_nid,
          (SELECT COUNT(*) FROM new_user) as created_count;
      ''', [
        userId, // 1
        emailValue, // 2
        cleanPhone, // 3
        hashPassword(password), // 4
        name.trim(), // 5
        nowStr, // 6
        profileId, // 7
        cleanNid.isEmpty ? null : cleanNid, // 8
        nomineeNid.isEmpty ? null : nomineeNid, // 9
        nomineeRel.isEmpty ? null : nomineeRel, // 10
        walletId, // 11
        // Email na thakle "verified" bola jay na
        cleanEmail.isNotEmpty, // 12
        cleanAddress.isEmpty ? null : cleanAddress, // 13
        (city ?? '').trim().isEmpty ? null : city!.trim(), // 14
        phoneVars[1], // 15
        phoneVars[2], // 16
      ]);

      if (res.isEmpty) {
        debugPrint("Register failed: $_lastConnectionError");
        return {
          'success': false,
          'message': _lastConnectionError != null
              ? 'Could not create account. (${_shortDbError()})'
              : 'Could not create account. Please try again.',
        };
      }

      final row = res.first;
      final existingEmail = _publicEmail(row['existing_email']);
      final existingPhone = row['existing_phone']?.toString() ?? '';
      final existingNid = row['existing_nid']?.toString() ?? '';

      if (existingNid.isNotEmpty) {
        return {'success': false, 'message': 'An account with this NID number already exists.'};
      }
      if (existingPhone.isNotEmpty && canonicalPhone(existingPhone) == cleanPhone) {
        return {'success': false, 'message': 'An account with this phone number already exists. Please log in.'};
      }
      if (existingEmail.isNotEmpty) {
        return {'success': false, 'message': 'An account with this email already exists. Please log in.'};
      }
      if (_toInt(row['created_count']) == 0) {
        return {'success': false, 'message': 'Could not create account. Please try again.'};
      }

      final dobStr =
          '${dateOfBirth.year}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}';

      // Jonmo tarikh — website schema te je table e column ache sheikhane
      final dobTable = profCols.containsKey('dateOfBirth')
          ? 'investor_profiles'
          : (userCols.containsKey('dateOfBirth') ? 'users' : null);
      if (dobTable != null) {
        final key = dobTable == 'users' ? '"id"' : '"userId"';
        await executeNeonHttp(
          'UPDATE $dobTable SET "dateOfBirth" = \$1 WHERE $key = \$2',
          [dobStr, userId],
        );
      } else {
        debugPrint('dateOfBirth column nei — Prisma InvestorProfile e "dateOfBirth DateTime?" add korun');
      }

      // Welcome mail (forgot password er motoi Resend) — registration atkabe na
      if (cleanEmail.isNotEmpty) {
        unawaited(EmailService.sendWelcome(userId: userId, name: name.trim(), email: cleanEmail));
      }

      return {
        'success': true,
        'data': {
          'id': userId,
          'name': name.trim(),
          'email': cleanEmail,
          'phone': cleanPhone,
        },
        'message': 'Registration successful!',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }
  // Login User
  static Future<Map<String, dynamic>> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      final raw = email.trim();
      // Phone diye login: +8801… / 01… duita-i
      final isPhone = RegExp(r'^[+\d\s\-().]+$').hasMatch(raw);
      final vars = isPhone ? phoneVariants(raw) : [raw, raw, raw];

      final result = await queryNeonHttp('''
        SELECT "id", "name", "email", "phone", "passwordHash", "avatarUrl", "status"::text AS "status", "updatedAt"
        FROM users 
        WHERE LOWER("email") = LOWER(\$1) OR "phone" IN (\$1, \$2, \$3)
        LIMIT 1
      ''', vars);

      if (result.isEmpty) {
        return {
          'success': false,
          'message': _lastConnectionError != null
              ? _connectionErrorMsg()
              : 'User not found. Please check credentials or register first.',
        };
      }

      final row = result.first;
      final userId = row['id'].toString();
      final dbPassword = row['passwordHash']?.toString() ?? '';

      if (!verifyPassword(password, dbPassword)) {
        return {
          'success': false,
          'message': 'Incorrect password. Please try again.',
        };
      }

      // Purono SHA-256 / plaintext password thakle bcrypt e upgrade
      if (_needsRehash(dbPassword)) {
        await executeNeonHttp(
          'UPDATE users SET "passwordHash" = \$1 WHERE "id" = \$2',
          [hashPassword(password), userId],
        );
      }

      final st = row['status']?.toString() ?? 'ACTIVE';
      final updatedAtStr = row['updatedAt']?.toString();
      bool wasRestored = false;

      if (st == 'SUSPENDED') {
        final suspendedAt = updatedAtStr != null ? DateTime.tryParse(updatedAtStr) : null;
        final now = DateTime.now().toUtc();

        if (suspendedAt != null && now.difference(suspendedAt).inDays > 30) {
          return {
            'success': false,
            'message': 'This account has been permanently deleted after 30 days. Please register a new account.',
          };
        }

        await executeNeonHttp('''
          UPDATE users
          SET "status" = 'ACTIVE'::"UserStatus", "updatedAt" = \$1
          WHERE "id" = \$2
        ''', [now.toIso8601String(), userId]);
        wasRestored = true;
      }

      // Auto-backfill investor_profiles for website compatibility
      await _ensureInvestorProfileExists(userId);

      final rawAvatar = row['avatarUrl']?.toString();

      return {
        'success': true,
        'data': {
          'id': userId,
          'name': row['name']?.toString() ?? 'Investor',
          'email': _publicEmail(row['email']),
          'phone': row['phone']?.toString() ?? '',
          'avatarUrl': rawAvatar != null && rawAvatar.isNotEmpty ? formatImageUrl(rawAvatar) : null,
        },
        'message': wasRestored
            ? 'Welcome back! Your account deletion request has been canceled and your account is restored.'
            : 'Login successful!',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  // Change Password
  static Future<Map<String, dynamic>> changePassword({
    required String userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    try {
      final userRes = await queryNeonHttp(
          'SELECT "passwordHash" FROM users WHERE "id" = \$1', [userId]);

      if (userRes.isEmpty) {
        return {
          'success': false,
          'message': _lastConnectionError != null ? _connectionErrorMsg() : 'User not found.',
        };
      }

      final dbPasswordHash = userRes.first['passwordHash']?.toString() ?? '';

      if (!verifyPassword(oldPassword, dbPasswordHash)) {
        return {
          'success': false,
          'message': 'Incorrect current password. Please try again.',
        };
      }

      final ok = await executeNeonHttp('''
        UPDATE users
        SET "passwordHash" = \$1, "updatedAt" = \$2
        WHERE "id" = \$3
      ''', [hashPassword(newPassword), _nowIso(), userId]);

      if (!ok) return {'success': false, 'message': _connectionErrorMsg()};

      return {
        'success': true,
        'message': 'Password changed successfully!',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  /// Account delete er age: user er kono chalu ba pending investment ache kina.
  /// 'ok' false mane server e pouchano jayni — tokhon delete hote dibo na.
  static Future<Map<String, dynamic>> getOpenInvestmentSummary(String userId) async {
    if (userId.isEmpty) return {'ok': false};
    try {
      final res = await queryNeonHttp('''
        SELECT
          (SELECT COUNT(*) FROM investments i
             JOIN investor_profiles p ON i."investorProfileId" = p."id"
           WHERE p."userId" = \$1
             AND i."status"::text IN ('PENDING', 'PAYMENT_PENDING', 'ACTIVE', 'MATURED')) AS "projectOpen",
          (SELECT COUNT(*) FROM group_investments gi
           WHERE gi."investorUserId" = \$1
             AND gi."status"::text IN ('PENDING', 'PAYMENT_PENDING', 'ACTIVE')) AS "groupOpen"
      ''', [userId]);

      if (res.isEmpty) return {'ok': false};

      final projectOpen = _toInt(res.first['projectOpen']);
      final groupOpen = _toInt(res.first['groupOpen']);
      return {
        'ok': true,
        'projectOpen': projectOpen,
        'groupOpen': groupOpen,
        'totalOpen': projectOpen + groupOpen,
      };
    } catch (e) {
      debugPrint("Get Open Investment Summary Error: $e");
      return {'ok': false};
    }
  }

  // Request Account Deletion
  static Future<Map<String, dynamic>> requestAccountDeletion({
    required String userId,
    required String password,
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    try {
      final userRes = await queryNeonHttp(
          'SELECT "passwordHash" FROM users WHERE "id" = \$1', [userId]);

      if (userRes.isEmpty) {
        return {
          'success': false,
          'message': _lastConnectionError != null ? _connectionErrorMsg() : 'User not found.',
        };
      }

      final dbPasswordHash = userRes.first['passwordHash']?.toString() ?? '';

      if (!verifyPassword(password, dbPasswordHash)) {
        return {
          'success': false,
          'message': 'Incorrect password. Account deletion canceled.',
        };
      }

      // Chalu ba pending investment thakle account delete kora jabe na
      final open = await getOpenInvestmentSummary(userId);
      if (open['ok'] != true) {
        return {'success': false, 'message': _connectionErrorMsg()};
      }
      if ((open['totalOpen'] as int) > 0) {
        return {
          'success': false,
          'message': 'You have active or pending investments. Please contact support before deleting your account.',
        };
      }

      final ok = await executeNeonHttp('''
        UPDATE users
        SET "status" = 'SUSPENDED'::"UserStatus", "updatedAt" = \$1
        WHERE "id" = \$2
      ''', [_nowIso(), userId]);

      if (!ok) return {'success': false, 'message': _connectionErrorMsg()};

      return {
        'success': true,
        'message': 'Account deletion requested! Scheduled for deletion in 30 days.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  // ═════════════════════════════════════════════════════════
  // FORGOT PASSWORD (email OTP via Resend — biniyogclub.com domain)
  // ═════════════════════════════════════════════════════════

  /// Resend e verified domain theke mail jay — tai je kono real address e pouchay.
  static const String _mailFrom = 'Biniyog Club <noreply@biniyogclub.com>';
  static const String _mailReplyTo = 'support@biniyogclub.com';
  static const int _otpValidMinutes = 15;
  static const int _otpResendGapSeconds = 60;
  static const int _otpMaxAttempts = 5;

  static String _htmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  static Future<bool> _ensureResetTable() async {
    final a = await executeNeonHttp('''
      CREATE TABLE IF NOT EXISTS password_reset_tokens (
        "id" TEXT PRIMARY KEY,
        "email" TEXT NOT NULL,
        "token" TEXT NOT NULL,
        "expiresAt" TIMESTAMP WITH TIME ZONE NOT NULL,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL
      )
    ''');
    if (!a) return false;
    return executeNeonHttp(
        'ALTER TABLE password_reset_tokens ADD COLUMN IF NOT EXISTS "attempts" INTEGER NOT NULL DEFAULT 0');
  }

  // Send Forgot Password OTP — OTP app e ferot jay na, shudhu email e jay.
  static Future<Map<String, dynamic>> sendForgotPasswordOtp(String email) async {
    try {
      final cleanEmail = email.trim().toLowerCase();
      if (cleanEmail.isEmpty || isPlaceholderEmail(cleanEmail)) {
        return {'success': false, 'message': 'Please enter your registered email address.'};
      }

      final apiKey = DbConfig.resendApiKey.trim();
      if (apiKey.isEmpty || apiKey == 'your_resend_api_key') {
        return {
          'success': false,
          'message': 'Email service is not configured. Please contact support.',
        };
      }

      final userRes = await queryNeonHttp(
          'SELECT "id", "name" FROM users WHERE LOWER("email") = LOWER(\$1) LIMIT 1',
          [cleanEmail]);

      if (userRes.isEmpty) {
        return {
          'success': false,
          'message': _lastConnectionError != null
              ? _connectionErrorMsg()
              : 'No registered account found with this email address.',
        };
      }

      if (!await _ensureResetTable()) {
        return {'success': false, 'message': _connectionErrorMsg()};
      }

      // 60 second er moddhe abar pathano jabe na (spam / Resend limit)
      final recent = await queryNeonHttp('''
        SELECT EXTRACT(EPOCH FROM (NOW() - "createdAt"))::int AS "age"
        FROM password_reset_tokens
        WHERE LOWER("email") = LOWER(\$1)
        ORDER BY "createdAt" DESC LIMIT 1
      ''', [cleanEmail]);
      if (recent.isNotEmpty) {
        final age = int.tryParse(recent.first['age']?.toString() ?? '') ?? 9999;
        if (age < _otpResendGapSeconds) {
          return {
            'success': false,
            'message': 'Please wait ${_otpResendGapSeconds - age}s before requesting a new code.',
          };
        }
      }

      final userName = _htmlEscape(userRes.first['name']?.toString().trim().isNotEmpty == true
          ? userRes.first['name'].toString().trim()
          : 'Investor');
      final otp = (100000 + Random.secure().nextInt(900000)).toString();

      // Purono OTP gulo bad — shudhu shesh ta kaj korbe
      await executeNeonHttp(
          'DELETE FROM password_reset_tokens WHERE LOWER("email") = LOWER(\$1)',
          [cleanEmail]);

      final now = DateTime.now().toUtc();
      final tokenId = _generateUuid();
      final saved = await executeNeonHttp('''
        INSERT INTO password_reset_tokens ("id", "email", "token", "expiresAt", "createdAt", "attempts")
        VALUES (\$1, \$2, \$3, \$4, \$5, 0)
      ''', [
        tokenId,
        cleanEmail,
        otp,
        now.add(const Duration(minutes: _otpValidMinutes)).toIso8601String(),
        now.toIso8601String(),
      ]);

      if (!saved) return {'success': false, 'message': _connectionErrorMsg()};

      final mailRes = await _httpClient.post(
        Uri.parse('https://api.resend.com/emails'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'from': _mailFrom,
          'to': [cleanEmail],
          'reply_to': _mailReplyTo,
          'subject': 'Your Biniyog Club password reset code: $otp',
          'text': 'Assalamu Alaikum $userName,\n\n'
              'Your Biniyog Club password reset code is: $otp\n\n'
              'This code is valid for $_otpValidMinutes minutes. Never share it with anyone — '
              'Biniyog Club will never ask for this code.\n\n'
              'If you did not request a password reset, you can safely ignore this email.\n\n'
              '— Biniyog Club\nhttps://biniyogclub.com',
          'html': '''
<div style="font-family:Arial,Helvetica,sans-serif;background:#f6f1e7;padding:28px 12px;">
  <div style="max-width:480px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #e8dfc9;">
    <div style="background:#0f4d3a;padding:22px 24px;">
      <div style="color:#d4af61;font-size:12px;letter-spacing:2px;font-weight:bold;">BINIYOG CLUB</div>
      <div style="color:#ffffff;font-size:20px;font-weight:bold;margin-top:6px;">Password reset code</div>
    </div>
    <div style="padding:24px;">
      <p style="color:#1f2a24;font-size:14px;margin:0 0 12px;">Assalamu Alaikum <strong>$userName</strong>,</p>
      <p style="color:#3d4a43;font-size:14px;margin:0 0 18px;">Use this 6-digit code in the Biniyog Club app to reset your password:</p>
      <div style="background:#f3f8f5;border:1px solid #cfe3d8;border-radius:12px;padding:18px;text-align:center;">
        <span style="font-size:34px;font-weight:bold;letter-spacing:8px;color:#0f4d3a;">$otp</span>
      </div>
      <p style="color:#6b7570;font-size:12.5px;margin:18px 0 0;">This code is valid for <strong>$_otpValidMinutes minutes</strong>. Never share it with anyone — Biniyog Club will never ask for this code.</p>
      <p style="color:#6b7570;font-size:12.5px;margin:10px 0 0;">If you did not request a password reset, you can safely ignore this email. Your password will not change.</p>
    </div>
    <div style="border-top:1px solid #efe8d8;padding:14px 24px;color:#9a8f73;font-size:11.5px;">
      Biniyog Club · <a href="https://biniyogclub.com" style="color:#0f4d3a;">biniyogclub.com</a>
    </div>
  </div>
</div>
''',
        }),
      ).timeout(const Duration(seconds: 20));

      if (mailRes.statusCode < 200 || mailRes.statusCode >= 300) {
        debugPrint('Resend Error ${mailRes.statusCode}: ${mailRes.body}');
        // Mail na gele code-o rakha hobe na — jate abar sathe sathe try kora jay
        await executeNeonHttp('DELETE FROM password_reset_tokens WHERE "id" = \$1', [tokenId]);
        String reason = '';
        try {
          final m = jsonDecode(mailRes.body);
          if (m is Map && m['message'] != null) reason = ' (${m['message']})';
        } catch (_) {}
        return {
          'success': false,
          'message': 'Could not send the email. Please try again later.$reason',
        };
      }

      return {
        'success': true,
        'message': 'A 6-digit code has been sent to $cleanEmail. Check your inbox (and spam folder).',
      };
    } on TimeoutException {
      return {'success': false, 'message': 'Email server did not respond. Please try again.'};
    } catch (e) {
      return {'success': false, 'message': 'Something went wrong: ${e.toString()}'};
    }
  }

  // Verify Reset OTP Code — 5 bar vul dile code bad hoye jay
  static Future<Map<String, dynamic>> verifyResetOtp(String email, String otp) async {
    try {
      final cleanEmail = email.trim().toLowerCase();
      final cleanOtp = otp.trim();
      if (!RegExp(r'^\d{6}$').hasMatch(cleanOtp)) {
        return {'success': false, 'message': 'Please enter the 6-digit code.'};
      }

      final res = await queryNeonHttp('''
        SELECT "id", "token",
               ("expiresAt" < NOW()) AS "expired",
               COALESCE((to_jsonb(t) ->> 'attempts')::int, 0) AS "attempts"
        FROM password_reset_tokens t
        WHERE LOWER("email") = LOWER(\$1)
        ORDER BY "createdAt" DESC
        LIMIT 1
      ''', [cleanEmail]);

      if (res.isEmpty) {
        return {
          'success': false,
          'message': _lastConnectionError != null
              ? _connectionErrorMsg()
              : 'No active code found. Please request a new code.',
        };
      }

      final row = res.first;
      final id = row['id'].toString();
      final expired = row['expired'] == true || row['expired']?.toString() == 'true';
      final attempts = int.tryParse(row['attempts']?.toString() ?? '') ?? 0;

      if (expired) {
        await executeNeonHttp('DELETE FROM password_reset_tokens WHERE "id" = \$1', [id]);
        return {'success': false, 'message': 'This code has expired. Please request a new one.'};
      }

      if (attempts >= _otpMaxAttempts) {
        await executeNeonHttp('DELETE FROM password_reset_tokens WHERE "id" = \$1', [id]);
        return {'success': false, 'message': 'Too many wrong attempts. Please request a new code.'};
      }

      if (row['token']?.toString() != cleanOtp) {
        final used = attempts + 1;
        if (used >= _otpMaxAttempts) {
          await executeNeonHttp('DELETE FROM password_reset_tokens WHERE "id" = \$1', [id]);
          return {'success': false, 'message': 'Too many wrong attempts. Please request a new code.'};
        }
        await executeNeonHttp(
            'UPDATE password_reset_tokens SET "attempts" = \$2 WHERE "id" = \$1', [id, used]);
        final left = _otpMaxAttempts - used;
        return {
          'success': false,
          'message': 'Wrong code. $left attempt${left == 1 ? '' : 's'} left.',
        };
      }

      return {'success': true, 'message': 'Code verified!'};
    } catch (e) {
      return {'success': false, 'message': 'Something went wrong: ${e.toString()}'};
    }
  }

  // Reset Password using OTP — code abar check hoy, tarpor password badlay
  static Future<Map<String, dynamic>> resetPasswordWithOtp({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    try {
      if (newPassword.length < 6) {
        return {'success': false, 'message': 'Password must be at least 6 characters.'};
      }

      final verifyRes = await verifyResetOtp(email, otp);
      if (verifyRes['success'] != true) return verifyRes;

      final cleanEmail = email.trim().toLowerCase();

      final updated = await queryNeonHttp('''
        UPDATE users
        SET "passwordHash" = \$1, "updatedAt" = \$2
        WHERE LOWER("email") = LOWER(\$3)
        RETURNING "id"
      ''', [hashPassword(newPassword), _nowIso(), cleanEmail]);

      if (updated.isEmpty) {
        return {
          'success': false,
          'message': _lastConnectionError != null
              ? _connectionErrorMsg()
              : 'Account not found. Please try again.',
        };
      }

      // Code ekbar-i kaj kore
      await executeNeonHttp(
          'DELETE FROM password_reset_tokens WHERE LOWER("email") = LOWER(\$1)',
          [cleanEmail]);

      return {
        'success': true,
        'message': 'Password changed! Please sign in with your new password.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Something went wrong: ${e.toString()}'};
    }
  }

  // ═════════════════════════════════════════════════════════
  // PROFILE
  // ═════════════════════════════════════════════════════════

  // Update User Profile Avatar
  static Future<Map<String, dynamic>> updateUserAvatar({
    required String userId,
    required String avatarUrl,
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    try {
      final ok = await executeNeonHttp('''
        UPDATE users
        SET "avatarUrl" = \$1, "updatedAt" = \$2
        WHERE "id" = \$3
      ''', [avatarUrl, _nowIso(), userId]);

      if (!ok) return {'success': false, 'message': _connectionErrorMsg()};

      return {
        'success': true,
        'avatarUrl': formatImageUrl(avatarUrl),
        'message': 'Profile picture updated successfully!',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  // Delete User Profile Avatar
  static Future<Map<String, dynamic>> deleteUserAvatar(String userId) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    try {
      final ok = await executeNeonHttp('''
        UPDATE users
        SET "avatarUrl" = NULL, "updatedAt" = \$1
        WHERE "id" = \$2
      ''', [_nowIso(), userId]);

      if (!ok) return {'success': false, 'message': _connectionErrorMsg()};

      return {
        'success': true,
        'message': 'Profile picture removed successfully!',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  // ═════════════════════════════════════════════════════════
  // PROJECT INVESTMENT
  // ═════════════════════════════════════════════════════════

  // Create Investment
  static Future<Map<String, dynamic>> createInvestment({
    required String userId,
    required String projectId,
    required double amountBdt,
    bool useWalletBalance = false,
  }) async {
    // Login chara investment na — age "latest user" er naame toiri hoye jeto
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};

    try {
      // Website er resolveProfile: profile na thakle KYC VERIFIED hole KYC er
      // tottho diye banay (+ wallet); na hole invest kora jay na
      final profRes = await queryNeonHttp(
          'SELECT "id" FROM investor_profiles WHERE "userId" = \$1', [userId]);
      if (profRes.isEmpty && lastRequestFailed) return {'success': false, 'message': _connectionErrorMsg()};
      String profileId;
      if (profRes.isNotEmpty) {
        profileId = profRes.first['id'].toString();
      } else {
        final nowStr = _nowIso();
        final made = await queryNeonHttp('''
          WITH k AS (
            SELECT "documentNumber", "dateOfBirth", "addressLine", "city", "nationality"
            FROM kyc WHERE "userId" = \$2 AND "status"::text = 'VERIFIED'
          ),
          p AS (
            INSERT INTO investor_profiles ("id", "userId", "nationalId", "dateOfBirth", "address", "city", "country", "createdAt", "updatedAt")
            SELECT \$1, \$2, k."documentNumber", k."dateOfBirth", k."addressLine", k."city", COALESCE(k."nationality", 'BD'), \$3, \$3
            FROM k
            ON CONFLICT ("userId") DO UPDATE SET "updatedAt" = investor_profiles."updatedAt"
            RETURNING "id"
          ),
          w AS (
            INSERT INTO wallets ("id", "userId", "type", "cachedBalance", "currency", "isActive", "createdAt", "updatedAt")
            SELECT \$4, \$2, 'INVESTOR'::"WalletType", 0.00, 'BDT', true, \$3, \$3
            WHERE EXISTS (SELECT 1 FROM p)
            ON CONFLICT ("userId") DO NOTHING
          )
          SELECT "id" FROM p
        ''', [_generateUuid(), userId, nowStr, _generateUuid()]);
        if (made.isEmpty) {
          return {
            'success': false,
            'message': lastRequestFailed
                ? _connectionErrorMsg()
                : 'Investor profile not found. Please complete your profile setup.',
          };
        }
        profileId = made.first['id'].toString();
      }

      final projRes = await queryNeonHttp('''
        SELECT "id", "status"::text AS "status", "fundingGoalBdt", "fundedAmountBdt", "minInvestmentBdt",
               "maxInvestmentBdt", "expectedReturnPct", "returnPctMin", "returnPctMax",
               "returnType"::text AS "returnType", "fundingDeadline"
        FROM projects
        WHERE "id" = \$1
      ''', [projectId]);

      if (projRes.isEmpty) {
        return {
          'success': false,
          'message': _lastConnectionError != null ? _connectionErrorMsg() : 'Project not found.',
        };
      }

      final p = projRes.first;
      final status = p['status']?.toString() ?? 'DRAFT';
      if (status != 'FUNDRAISING') {
        return {
          'success': false,
          'message': 'Project is not currently open for fundraising (Status: $status).',
        };
      }
      // Website er motoi: deadline er din periye gele notun invest bondho
      if (deadlinePassed(p['fundingDeadline'])) {
        return {
          'success': false,
          'message': 'The funding deadline for this project has passed. New investments are closed.',
        };
      }

      final goal = _toDouble(p['fundingGoalBdt'], 1.0);
      final funded = _toDouble(p['fundedAmountBdt']);
      final minInv = _toDouble(p['minInvestmentBdt']);
      final maxInv = _toDoubleOrNull(p['maxInvestmentBdt']);
      // Website er calculateExpectedReturn: amount × expectedReturnPct ÷ 100,
      // 2 dosomik e round (16 ba 0.16 — duitai 0.16)
      final returnPct = _normalizePct(p['expectedReturnPct']);
      final returnType = p['returnType']?.toString() ?? 'FIXED_RETURN';

      if (minInv > 0 && amountBdt < minInv) {
        return {
          'success': false,
          'message': 'Minimum investment amount is ৳${minInv.toStringAsFixed(0)}.',
        };
      }

      if (maxInv != null && maxInv > 0 && amountBdt > maxInv) {
        return {
          'success': false,
          'message': 'Maximum investment amount is ৳${maxInv.toStringAsFixed(0)}.',
        };
      }

      final remaining = goal - funded;
      if (remaining <= 0) {
        return {'success': false, 'message': 'Project is already fully funded.'};
      }
      if (amountBdt > remaining) {
        return {
          'success': false,
          'message': 'Only ৳${remaining.toStringAsFixed(0)} capacity remaining in this project.',
        };
      }

      final investmentId = _generateUuid();
      final nowStr = _nowIso();
      final expectedReturn = (amountBdt * returnPct * 100).round() / 100;

      // ON CONFLICT: network retry hole duplicate row hobe na, r RETURNING diye
      // nishchit hoi je row asolei save hoyeche
      final ins = await queryNeonHttp('''
        INSERT INTO investments (
          "id", "investorProfileId", "projectId", "status", "amountBdt",
          "expectedReturnBdt", "returnType", "idempotencyKey", "createdAt", "updatedAt"
        ) VALUES (
          \$1, \$2, \$3, 'PENDING'::"InvestmentStatus", \$4,
          \$5, \$6::"ReturnType", \$7, \$8, \$8
        )
        ON CONFLICT ("id") DO UPDATE SET "updatedAt" = EXCLUDED."updatedAt"
        RETURNING "id"
      ''', [
        investmentId,
        profileId,
        projectId,
        amountBdt,
        expectedReturn,
        returnType,
        _generateUuid(),
        nowStr,
      ]);

      if (ins.isEmpty) {
        debugPrint('createInvestment failed: $_lastDbFailure');
        return {'success': false, 'message': _saveFailMsg('Could not create the investment.')};
      }

      return {
        'success': true,
        'investmentId': investmentId,
        'isDirectPayment': true,
        'message': 'Direct investment created! Please submit your payment proof for Admin approval.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  // Submit Manual Payment Proof
  static Future<Map<String, dynamic>> submitManualPaymentProof({
    required String investmentId,
    required String userId,
    required double amountBdt,
    required String transactionRef,
    required String bankAccountId,
    required String proofFileUrl,
    String? notes,
    String paymentMethod = 'BANK_TRANSFER',
    Map<String, dynamic>? paymentDetails,
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};

    try {
      final check = await queryNeonHttp('''
        SELECT i."status"::text AS "status",
               EXISTS (
                 SELECT 1 FROM manual_payment_submissions m
                 WHERE m."investmentId" = i."id" AND m."status"::text = 'SUBMITTED'
               ) AS "hasPending"
        FROM investments i
        JOIN investor_profiles p ON i."investorProfileId" = p."id"
        WHERE i."id" = \$1 AND p."userId" = \$2
      ''', [investmentId, userId]);

      if (check.isEmpty) {
        return {
          'success': false,
          'message': _lastConnectionError != null ? _connectionErrorMsg() : 'Investment not found.',
        };
      }

      final st = check.first['status']?.toString() ?? '';
      if (st != 'PENDING' && st != 'PAYMENT_PENDING') {
        return {'success': false, 'message': 'This investment is not awaiting payment.'};
      }
      if (check.first['hasPending'] == true) {
        return {'success': false, 'message': 'A payment proof is already under review.'};
      }

      final submissionId = _generateUuid();
      final nowStr = _nowIso();
      final fileUrl = proofFileUrl.isEmpty ? 'receipt.png' : proofFileUrl;
      final cleanBankId = (bankAccountId.isEmpty || bankAccountId == 'null') ? null : bankAccountId;

      final ins = await queryNeonHttp('''
        INSERT INTO manual_payment_submissions (
          "id", "investmentId", "submittedBy", "status", "amountBdt",
          "bankAccountId", "paymentMethod", "transactionRef", "proofFileUrl",
          "proofMimeType", "notes", "createdAt", "updatedAt"
        ) VALUES (
          \$1, \$2, \$3, 'SUBMITTED'::"ManualPaymentStatus", \$4,
          \$5, \$6, \$7, \$8,
          \$9, \$10, \$11, \$11
        )
        ON CONFLICT ("id") DO UPDATE SET "updatedAt" = EXCLUDED."updatedAt"
        RETURNING "id"
      ''', [
        submissionId,
        investmentId,
        userId,
        amountBdt,
        cleanBankId,
        paymentMethod,
        transactionRef,
        fileUrl,
        _mimeFromDataUri(fileUrl),
        notes,
        nowStr,
      ]);

      if (ins.isEmpty) return {'success': false, 'message': _lastConnectionError != null ? _connectionErrorMsg() : 'Failed to submit payment submission.'};

      await executeNeonHttp('''
        UPDATE investments
        SET "status" = 'PAYMENT_PENDING'::"InvestmentStatus", "paymentPendingAt" = \$1, "updatedAt" = \$1
        WHERE "id" = \$2
      ''', [nowStr, investmentId]);

      try {
        unawaited(EmailService.sendProjectPaymentSubmitted(submissionId));
        unawaited(PushService.showLocal(
          title: 'Payment Submitted',
          body: 'Your payment of ${_fmtTk(amountBdt)} has been submitted. It will become active after admin approval.',
          kind: 'PENDING',
          group: false,
        ));
      } catch (_) {}

      return {
        'success': true,
        'message': 'Payment proof submitted successfully for review!',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  // ═════════════════════════════════════════════════════════
  // PROJECT INVEST + PAYMENT (ek shathe) — Bank / Cash / Cheque
  // Investment toiri → payment er tottho admin er kache (manual_payment_submissions)
  // → status PAYMENT_PENDING. Admin approve korle ACTIVE (website e).
  // ═════════════════════════════════════════════════════════
  static final Map<String, ({String cast, Set<String> labels})> _payMethodMetaCache = {};

  /// paymentMethod column enum hole tar value gula (na hole text).
  /// Column-i na thakle cast/labels khali.
  static Future<({String cast, Set<String> labels})> _paymentMethodMeta(
      [String table = 'manual_payment_submissions']) async {
    final cached = _payMethodMetaCache[table];
    if (cached != null) return cached;
    final col = await queryNeonHttp('''
      SELECT data_type AS "t", udt_name AS "u" FROM information_schema.columns
      WHERE table_name = \$1 AND column_name = 'paymentMethod'
    ''', [table]);
    if (col.isEmpty) return (cast: '', labels: <String>{});
    final t = col.first['t']?.toString() ?? '';
    final u = col.first['u']?.toString() ?? '';
    if (t != 'USER-DEFINED') {
      return _payMethodMetaCache[table] = (cast: '', labels: <String>{});
    }
    final labels = await queryNeonHttp('''
      SELECT e.enumlabel AS "v" FROM pg_enum e JOIN pg_type ty ON e.enumtypid = ty.oid
      WHERE ty.typname = \$1
    ''', [u]);
    return _payMethodMetaCache[table] =
    (cast: '::"$u"', labels: labels.map((r) => r['v'].toString()).toSet());
  }

  static String _fmtTk(double v) {
    final s = v.toStringAsFixed(0);
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return 'BDT $b';
  }

  // ═════════════════════════════════════════════════════════
  // PAYMENT PARTS — website er motoi: protita madhyom (Bank / Cash / Cheque)
  // alada row, ek "batch" e. paymentMethod = BANK_TRANSFER / CASH / CHEQUE,
  // cash e cashReceivedBy. Admin protita part alada approve/reject kore,
  // approve hoye pura taka mille investment ACTIVE (website e).
  // Kisti (INSTALLMENT) hole ekbare puro taka lage na.
  // ═════════════════════════════════════════════════════════

  static String _mimeFromUrl(String url) {
    final u = url.toLowerCase().split('?').first;
    if (u.endsWith('.png')) return 'image/png';
    if (u.endsWith('.webp')) return 'image/webp';
    if (u.endsWith('.heic')) return 'image/heic';
    if (u.endsWith('.pdf')) return 'application/pdf';
    return 'image/jpeg';
  }

  /// Investment er payment er hishab: mot, jachai hoye geche, jachai cholche, baki
  static Future<Map<String, dynamic>?> getPaymentProgress({
    required bool group,
    required String id,
    required String userId,
  }) async {
    final rows = group
        ? await queryNeonHttp('''
            SELECT gi."status"::text AS "status", gi."amountBdt" AS "total",
                   COALESCE(to_jsonb(gi) ->> 'paymentPlan', 'FULL') AS "plan",
                   gt."bankAccountId" AS "fallbackBankId",
                   COALESCE((SELECT SUM(x."amountBdt") FROM group_investment_payments x
                             WHERE x."groupInvestmentId" = gi."id" AND x."status"::text = 'APPROVED'), 0) AS "approved",
                   COALESCE((SELECT SUM(x."amountBdt") FROM group_investment_payments x
                             WHERE x."groupInvestmentId" = gi."id"
                               AND x."status"::text IN ('SUBMITTED', 'UNDER_REVIEW')), 0) AS "pending"
            FROM group_investments gi
            JOIN group_tiers gt ON gt."id" = gi."tierId"
            WHERE gi."id" = \$1 AND gi."investorUserId" = \$2
          ''', [id, userId])
        : await queryNeonHttp('''
            SELECT i."status"::text AS "status", i."amountBdt" AS "total",
                   COALESCE(to_jsonb(i) ->> 'paymentPlan', 'FULL') AS "plan",
                   (SELECT b."id" FROM project_bank_accounts b
                    WHERE b."projectId" = i."projectId" AND b."isActive" = true
                    ORDER BY b."createdAt" ASC LIMIT 1) AS "fallbackBankId",
                   COALESCE((SELECT SUM(x."amountBdt") FROM manual_payment_submissions x
                             WHERE x."investmentId" = i."id" AND x."status"::text = 'APPROVED'), 0) AS "approved",
                   COALESCE((SELECT SUM(x."amountBdt") FROM manual_payment_submissions x
                             WHERE x."investmentId" = i."id"
                               AND x."status"::text IN ('SUBMITTED', 'UNDER_REVIEW')), 0) AS "pending"
            FROM investments i
            JOIN investor_profiles p ON p."id" = i."investorProfileId"
            WHERE i."id" = \$1 AND p."userId" = \$2
          ''', [id, userId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final total = _toDouble(r['total']);
    final approved = _toDouble(r['approved']);
    final pending = _toDouble(r['pending']);
    final outstanding = max(0.0, total - approved - pending);
    return {
      'status': r['status']?.toString() ?? '',
      'plan': (r['plan']?.toString() ?? 'FULL').toUpperCase(),
      'total': total,
      'approved': approved,
      'pending': pending,
      'outstanding': outstanding,
      'fallbackBankId': r['fallbackBankId']?.toString(),
    };
  }

  /// Protita madhyom er jonno alada row (ek INSERT e). Fire: prothom row er id.
  static Future<Map<String, dynamic>> _insertPaymentParts({
    required bool group,
    required String parentId,
    required String userId,
    required Set<String> m,
    required double payNowBdt,
    required double bankAmount,
    required double cashAmount,
    required double chequeAmount,
    String? bankAccountId,
    String? fallbackBankId,
    String? bankAccountLabel,
    String? bankTransactionId,
    List<String> bankProofUrls = const [],
    String? cashReceiver,
    List<String> chequeProofUrls = const [],
    List<String> cashProofUrls = const [],
    String? chequeNumber,
    String? cashReceiptNo,
    String? note,
  }) async {
    final table = group ? 'group_investment_payments' : 'manual_payment_submissions';
    final fk = group ? 'groupInvestmentId' : 'investmentId';
    final metas = await Future.wait([_paymentMethodMeta(table), _columnsOf(table)]);
    final pm = metas[0] as ({String cast, Set<String> labels});
    final cols = metas[1] as Map<String, bool>;
    if (cols.isEmpty) return {'success': false, 'message': _connectionErrorMsg()};

    // paymentMethod enum hole (purono schema) DB je value nay tar moddhe theke
    String method(String key) {
      final wanted = switch (key) {
        'BANK' => ['BANK_TRANSFER', 'BANK_DEPOSIT', 'BANK'],
        'CASH' => ['CASH', 'CASH_DEPOSIT', 'CASH_PAYMENT'],
        _ => ['CHECK', 'CHEQUE', 'BANK_CHEQUE'], // website: CHECK
      };
      if (pm.labels.isEmpty) return wanted.first;
      for (final w in wanted) {
        if (pm.labels.contains(w)) return w;
      }
      return pm.labels.contains('BANK_TRANSFER') ? 'BANK_TRANSFER' : pm.labels.first;
    }

    final single = m.length == 1;
    final parts = <({String key, double amount})>[
      if (m.contains('BANK')) (key: 'BANK', amount: single ? payNowBdt : bankAmount),
      if (m.contains('CASH')) (key: 'CASH', amount: single ? payNowBdt : cashAmount),
      if (m.contains('CHEQUE')) (key: 'CHEQUE', amount: single ? payNowBdt : chequeAmount),
    ];
    final label = [if (m.contains('BANK')) 'Bank', if (m.contains('CASH')) 'Cash', if (m.contains('CHEQUE')) 'Cheque']
        .join(' + ');
    final batchId = cols.containsKey('batchId') ? _generateUuid() : null;
    final hasExtra = cols.containsKey('extraProofs');
    final receiver = cashReceiverValue(cashReceiver);

    // Protita madhyom er reference: Bank = TxID, Cheque = cheque number, Cash = money receipt no
    String refOf(String key) => switch (key) {
      'BANK' => (bankTransactionId ?? '').trim(),
      'CHEQUE' => (chequeNumber ?? '').trim(),
      _ => (cashReceiptNo ?? '').trim(),
    };
    List<String> proofsOf(String key) => switch (key) {
      'BANK' => bankProofUrls,
      'CHEQUE' => chequeProofUrls,
      _ => cashProofUrls,
    };

    // Ek-i reference dui bar na (website er assertRefsUnused er motoi) — rejected gulo bade
    final refs = parts.map((x) => refOf(x.key)).where((r) => r.isNotEmpty && r.toUpperCase() != 'CASH').toList();
    if (refs.map((r) => r.toLowerCase()).toSet().length != refs.length) {
      return {'success': false, 'message': 'Each payment part needs its own reference number.'};
    }
    for (final r in refs) {
      final used = await queryNeonHttp('''
        SELECT 1 AS "x" FROM manual_payment_submissions WHERE LOWER("transactionRef") = LOWER(\$1) AND "status"::text <> 'REJECTED'
        UNION ALL
        SELECT 1 AS "x" FROM group_investment_payments WHERE LOWER("transactionRef") = LOWER(\$1) AND "status"::text <> 'REJECTED'
        LIMIT 1
      ''', [r]);
      if (used.isNotEmpty) {
        return {'success': false, 'message': 'Reference "$r" has already been used for another payment.'};
      }
    }
    // Website: BANK_TRANSFER e je account e taka pathiyechen seta bachai korte hobe
    if (m.contains('BANK') && (bankAccountId ?? '').isEmpty) {
      return {'success': false, 'message': 'Bank Transfer: select the bank account you paid into.'};
    }
    final nowStr = _nowIso();
    final bankNullable = cols['bankAccountId'] ?? true;

    final names = <String>[
      'id', fk, 'submittedBy', 'status', 'amountBdt', 'bankAccountId', 'paymentMethod',
      'transactionRef', 'proofFileUrl', 'proofMimeType', 'notes', 'createdAt', 'updatedAt',
      if (cols.containsKey('cashReceivedBy')) 'cashReceivedBy',
      if (batchId != null) 'batchId',
      if (hasExtra) 'extraProofs',
    ].where((c) => cols.containsKey(c)).toList();

    final params = <dynamic>[];
    String p(dynamic v, [String cast = '']) {
      params.add(v);
      return '\$${params.length}$cast';
    }

    final tuples = <String>[];
    final ids = <String>[];
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      final id = _generateUuid();
      ids.add(id);
      final files = proofsOf(part.key);
      final proof = files.isEmpty ? '' : files.first;
      final extra = files.length > 1
          ? jsonEncode(files.skip(1).map((u) => {'url': u, 'mimeType': _mimeFromUrl(u)}).toList())
          : null;
      String? bankId = part.key == 'BANK' && (bankAccountId ?? '').isNotEmpty ? bankAccountId : null;
      if (bankId == null && !bankNullable) bankId = (fallbackBankId ?? '').isNotEmpty ? fallbackBankId : null;
      if (bankId == null && !bankNullable) {
        return {'success': false, 'message': 'Payment account is not set yet. Please contact support.'};
      }
      // Website er partRowData: cash er reference na thakle "CASH"
      final ref = refOf(part.key).isNotEmpty ? refOf(part.key) : (part.key == 'CASH' ? 'CASH' : '');
      final noteLines = <String>[
        if ((note ?? '').trim().isNotEmpty) note!.trim(),
        if (part.key == 'BANK' && (bankAccountLabel ?? '').isNotEmpty) 'Paid into $bankAccountLabel',
        // cashReceivedBy column na thakle (purono DB) notes e
        if (part.key == 'CASH' && !cols.containsKey('cashReceivedBy')) 'Cash handed to ${receiver ?? cashReceiver}',
        if (!single) 'Part ${i + 1} of ${parts.length} · $label · ${_fmtTk(payNowBdt)} in total',
        'Submitted from the Biniyog Club app',
      ];

      // Shudhu je column ache tar value — parameter shonkha thik rakhte
      final raw = <String, dynamic>{
        'id': id,
        fk: parentId,
        'submittedBy': userId,
        'amountBdt': part.amount,
        'bankAccountId': bankId,
        'paymentMethod': method(part.key),
        'transactionRef': ref,
        'proofFileUrl': proof,
        'proofMimeType': proof.isEmpty ? '' : _mimeFromUrl(proof),
        'notes': noteLines.join('\n'),
        'createdAt': nowStr,
        'updatedAt': nowStr,
        'cashReceivedBy': part.key == 'CASH' ? receiver : null,
        'batchId': batchId,
        'extraProofs': extra,
      };
      final slots = names.map((n) {
        if (n == 'status') return "'SUBMITTED'::\"ManualPaymentStatus\"";
        if (n == 'extraProofs') return p(raw[n], '::jsonb');
        return p(raw[n], n == 'paymentMethod' ? pm.cast : '');
      }).join(', ');
      tuples.add('($slots)');
    }

    final ins = await queryNeonHttp('''
      INSERT INTO $table (${names.map((n) => '"$n"').join(', ')})
      VALUES ${tuples.join(', ')}
      RETURNING "id"
    ''', params);

    if (ins.isEmpty) {
      return {'success': false, 'message': 'Could not save your payment details. (${_shortDbError()})'};
    }

    await executeNeonHttp(
      group
          ? '''
            UPDATE group_investments
            SET "status" = 'PAYMENT_PENDING'::"GroupInvestmentStatus", "updatedAt" = \$1
            WHERE "id" = \$2
          '''
          : '''
            UPDATE investments
            SET "status" = 'PAYMENT_PENDING'::"InvestmentStatus",
                "paymentPendingAt" = COALESCE("paymentPendingAt", \$1::timestamp), "updatedAt" = \$1::timestamp
            WHERE "id" = \$2
          ''',
      [nowStr, parentId],
    );

    return {'success': true, 'submissionId': ids.first, 'submissionIds': ids};
  }

  /// Investment er paymentPlan (FULL / INSTALLMENT) — column thakle
  static Future<void> _setPaymentPlan({required bool group, required String id, required String plan}) async {
    final table = group ? 'group_investments' : 'investments';
    final cols = await _columnsOf(table);
    if (!cols.containsKey('paymentPlan')) return;
    await executeNeonHttp('UPDATE $table SET "paymentPlan" = \$1 WHERE "id" = \$2', [plan, id]);
  }

  /// Notun project investment + prothom payment.
  /// methods: 'BANK', 'CASH', 'CHEQUE' (ek ba ekadhik).
  /// paymentPlan 'INSTALLMENT' hole payNowBdt (ekhon joto) mot er cheye kom hote pare.
  static Future<Map<String, dynamic>> investWithPayment({
    required String userId,
    required String projectId,
    required double amountBdt,
    required List<String> methods,
    double? payNowBdt,
    String paymentPlan = 'FULL',
    double bankAmount = 0,
    double cashAmount = 0,
    double chequeAmount = 0,
    String? bankAccountId,
    String? bankAccountLabel,
    String? bankTransactionId,
    String? bankReceiptUrl,
    String? cashReceiver,
    String? chequeImageUrl,
    List<String> bankProofUrls = const [],
    List<String> chequeProofUrls = const [],
    List<String> cashProofUrls = const [],
    String? chequeNumber,
    String? cashReceiptNo,
    /// Cash/cheque hole-o bankAccountId column NOT NULL thakle project er account
    String? defaultBankAccountId,
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    final m = methods.toSet();
    final plan = paymentPlan == 'INSTALLMENT' ? 'INSTALLMENT' : 'FULL';
    final payNow = plan == 'FULL' ? amountBdt : (payNowBdt ?? amountBdt);
    _lastDbFailure = null;

    if (payNow <= 0 || (payNow * 100).round() > (amountBdt * 100).round()) {
      return {'success': false, 'message': 'The amount you pay now must be between 1 and ${_fmtTk(amountBdt)}.'};
    }
    final problem = _checkPaymentParts(
      m: m,
      amountBdt: payNow,
      bankAmount: bankAmount,
      cashAmount: cashAmount,
      chequeAmount: chequeAmount,
      bankTransactionId: bankTransactionId,
      bankProofUrls: [...bankProofUrls, if ((bankReceiptUrl ?? '').isNotEmpty) bankReceiptUrl!],
      cashReceiver: cashReceiver,
      chequeProofUrls: [...chequeProofUrls, if ((chequeImageUrl ?? '').isNotEmpty) chequeImageUrl!],
      cashProofUrls: cashProofUrls,
      chequeNumber: chequeNumber,
      cashReceiptNo: cashReceiptNo,
    );
    if (problem != null) return {'success': false, 'message': problem};

    // ধাপ ১: investment (min/max/baki/status — shob createInvestment e check hoy)
    final inv = await createInvestment(userId: userId, projectId: projectId, amountBdt: amountBdt);
    if (inv['success'] != true) return inv;
    final investmentId = inv['investmentId'].toString();

    Future<Map<String, dynamic>> undo(String msg) async {
      // Payment save na hole addha investment rakhbo na
      await executeNeonHttp('''
        DELETE FROM investments i USING investor_profiles p
        WHERE i."id" = \$1 AND i."investorProfileId" = p."id" AND p."userId" = \$2
          AND i."status"::text IN ('PENDING', 'PAYMENT_PENDING')
          AND NOT EXISTS (SELECT 1 FROM manual_payment_submissions x WHERE x."investmentId" = i."id")
      ''', [investmentId, userId]);
      return {'success': false, 'message': msg};
    }

    try {
      await _setPaymentPlan(group: false, id: investmentId, plan: plan);
      final res = await _insertPaymentParts(
        group: false,
        parentId: investmentId,
        userId: userId,
        m: m,
        payNowBdt: payNow,
        bankAmount: bankAmount,
        cashAmount: cashAmount,
        chequeAmount: chequeAmount,
        bankAccountId: bankAccountId,
        fallbackBankId: defaultBankAccountId,
        bankAccountLabel: bankAccountLabel,
        bankTransactionId: bankTransactionId,
        bankProofUrls: [...bankProofUrls, if ((bankReceiptUrl ?? '').isNotEmpty) bankReceiptUrl!],
        cashReceiver: cashReceiver,
        chequeProofUrls: [...chequeProofUrls, if ((chequeImageUrl ?? '').isNotEmpty) chequeImageUrl!],
        cashProofUrls: cashProofUrls,
        chequeNumber: chequeNumber,
        cashReceiptNo: cashReceiptNo,
        note: plan == 'INSTALLMENT' ? 'Installment 1 · commitment ${_fmtTk(amountBdt)}' : null,
      );
      if (res['success'] != true) {
        return await undo(res['message']?.toString() ?? 'Could not save your payment details.');
      }

      // User er notification page e "Pending" (mail worker pathabe)
      await _notifyProjectPending(userId: userId, investmentId: investmentId, amountBdt: amountBdt);
      unawaited(EmailService.sendProjectPending(investmentId));

      return {
        'success': true,
        'investmentId': investmentId,
        'message': 'Investment submitted! It will be active after admin approval.',
      };
    } catch (e) {
      debugPrint('investWithPayment error: $e');
      return await undo('Could not save your payment details. ($e)');
    }
  }

  /// Age theke thaka project investment e (baki taka / kisti / reject howa part) payment —
  /// website er "/dashboard/investments/[id]/pay" er motoi
  static Future<Map<String, dynamic>> submitProjectPaymentMulti({
    required String investmentId,
    required String userId,
    required double amountBdt,
    required List<String> methods,
    double bankAmount = 0,
    double cashAmount = 0,
    double chequeAmount = 0,
    String? bankAccountId,
    String? bankAccountLabel,
    String? bankTransactionId,
    String? bankReceiptUrl,
    String? cashReceiver,
    String? chequeImageUrl,
    List<String> bankProofUrls = const [],
    List<String> chequeProofUrls = const [],
    List<String> cashProofUrls = const [],
    String? chequeNumber,
    String? cashReceiptNo,
    String? defaultBankAccountId,
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    final m = methods.toSet();
    _lastDbFailure = null;
    final problem = _checkPaymentParts(
      m: m,
      amountBdt: amountBdt,
      bankAmount: bankAmount,
      cashAmount: cashAmount,
      chequeAmount: chequeAmount,
      bankTransactionId: bankTransactionId,
      bankProofUrls: [...bankProofUrls, if ((bankReceiptUrl ?? '').isNotEmpty) bankReceiptUrl!],
      cashReceiver: cashReceiver,
      chequeProofUrls: [...chequeProofUrls, if ((chequeImageUrl ?? '').isNotEmpty) chequeImageUrl!],
      cashProofUrls: cashProofUrls,
      chequeNumber: chequeNumber,
      cashReceiptNo: cashReceiptNo,
    );
    if (problem != null) return {'success': false, 'message': problem};

    try {
      final prog = await getPaymentProgress(group: false, id: investmentId, userId: userId);
      if (prog == null) {
        return {
          'success': false,
          'message': _lastConnectionError != null ? _connectionErrorMsg() : 'Investment not found.',
        };
      }
      final pay = _checkPayable(prog, amountBdt);
      if (pay != null) return {'success': false, 'message': pay};

      final res = await _insertPaymentParts(
        group: false,
        parentId: investmentId,
        userId: userId,
        m: m,
        payNowBdt: amountBdt,
        bankAmount: bankAmount,
        cashAmount: cashAmount,
        chequeAmount: chequeAmount,
        bankAccountId: bankAccountId,
        fallbackBankId: defaultBankAccountId ?? prog['fallbackBankId']?.toString(),
        bankAccountLabel: bankAccountLabel,
        bankTransactionId: bankTransactionId,
        bankProofUrls: [...bankProofUrls, if ((bankReceiptUrl ?? '').isNotEmpty) bankReceiptUrl!],
        cashReceiver: cashReceiver,
        chequeProofUrls: [...chequeProofUrls, if ((chequeImageUrl ?? '').isNotEmpty) chequeImageUrl!],
        cashProofUrls: cashProofUrls,
        chequeNumber: chequeNumber,
        cashReceiptNo: cashReceiptNo,
        note: prog['plan'] == 'INSTALLMENT' ? 'Installment · commitment ${_fmtTk(_toDouble(prog['total']))}' : null,
      );
      if (res['success'] != true) return res;

      try {
        unawaited(EmailService.sendProjectPaymentSubmitted(res['submissionId'].toString()));
        unawaited(PushService.showLocal(
          title: 'Payment Submitted',
          body: 'Your payment of ${_fmtTk(amountBdt)} has been submitted. It will be checked by admin.',
          kind: 'PENDING',
          group: false,
        ));
      } catch (_) {}

      return <String, dynamic>{
        'success': true,
        'message': 'Payment submitted! It will be checked by admin.',
      };
    } catch (e) {
      debugPrint('submitProjectPaymentMulti error: $e');
      return {'success': false, 'message': 'Could not save your payment details. Please try again.'};
    }
  }

  /// Ekhon koto deya jay — website er "Available to pay now" er niyom
  static String? _checkPayable(Map<String, dynamic> prog, double amount) {
    final st = prog['status']?.toString() ?? '';
    if (st != 'PENDING' && st != 'PAYMENT_PENDING') {
      return 'This investment is not awaiting payment.';
    }
    final outstanding = _toDouble(prog['outstanding']);
    final outP = (outstanding * 100).round();
    final amtP = (amount * 100).round();
    if (outP <= 0) {
      return 'Payments for the full amount are already under review.';
    }
    if (amtP > outP) {
      return 'Only ${_fmtTk(outstanding)} is left to pay (you entered ${_fmtTk(amount)}).';
    }
    // Ekbare (FULL) hole baki puro taka-i, paisa porjonto
    if (prog['plan'] != 'INSTALLMENT' && amtP != outP) {
      return 'The amounts must add up to ${_fmtTk(outstanding)} (you entered ${_fmtTk(amount)}).';
    }
    // Website: kisti kompokkhe ৳1,000 (baki er cheye kom hole puro baki)
    final minInst = outstanding < 1000 ? outstanding : 1000.0;
    if (amount + 0.5 < minInst) return 'An installment must be at least ${_fmtTk(minInst)}.';
    return null;
  }

  // ═════════════════════════════════════════════════════════
  // USER NOTIFICATIONS (app theke) — notification page e dekhay.
  // Type SYSTEM (enum e PENDING nei); data.kind diye page icon/link thik kore.
  // Mail app pathay na — biniyog-mailer worker DB dekhe pathay.
  // ═════════════════════════════════════════════════════════
  static Future<void> _notifyProjectPending({
    required String userId,
    required String investmentId,
    required double amountBdt,
  }) async {
    try {
      final rows = await queryNeonHttp('''
        INSERT INTO notifications ("id", "userId", "type", "title", "body", "data", "isRead", "createdAt")
        SELECT \$1, \$2, 'SYSTEM'::"NotificationType", 'Investment Pending',
               'Your investment of ' || \$3 || ' in "' || pr."title" ||
               '" has been submitted. It will become active after admin approval.',
               jsonb_build_object('kind', 'PENDING', 'investmentId', i."id", 'projectId', pr."id"),
               false, \$4
        FROM investments i
        JOIN projects pr ON pr."id" = i."projectId"
        WHERE i."id" = \$5
        RETURNING "title", "body"
      ''', [_generateUuid(), userId, _fmtTk(amountBdt), _nowIso(), investmentId]);
      _pushFromRow(rows, group: false);
    } catch (e) {
      debugPrint("Notify project pending error: $e");
    }
  }

  static Future<void> _notifyGroupPending({
    required String userId,
    required String groupInvestmentId,
    required double amountBdt,
    bool resubmitted = false,
  }) async {
    try {
      final rows = await queryNeonHttp('''
        INSERT INTO notifications ("id", "userId", "type", "title", "body", "data", "isRead", "createdAt")
        SELECT \$1, \$2, 'SYSTEM'::"NotificationType", \$3,
               \$4 || ' ' || \$5 || ' for ' || bg."name" || ' — ' || gt."name" ||
               ' has been submitted. It will become active after admin approval.',
               jsonb_build_object('kind', 'PENDING', 'groupInvestmentId', gi."id"),
               false, \$6
        FROM group_investments gi
        JOIN group_tiers gt     ON gt."id" = gi."tierId"
        JOIN group_entities ge  ON ge."id" = gt."entityId"
        JOIN business_groups bg ON bg."id" = ge."groupId"
        WHERE gi."id" = \$7
        RETURNING "title", "body"
      ''', [
        _generateUuid(),
        userId,
        resubmitted ? 'Payment Submitted' : 'Investment Pending',
        resubmitted ? 'Your payment of' : 'Your investment of',
        _fmtTk(amountBdt),
        _nowIso(),
        groupInvestmentId,
      ]);
      _pushFromRow(rows, group: true);
    } catch (e) {
      debugPrint("Notify group pending error: $e");
    }
  }

  /// Notification page e ja dhuklo, oi lekhai phone er notification e dekhai
  static void _pushFromRow(List<Map<String, dynamic>> rows, {required bool group}) {
    if (rows.isEmpty) return;
    final title = rows.first['title']?.toString() ?? '';
    final body = rows.first['body']?.toString() ?? '';
    if (title.isEmpty) return;
    unawaited(PushService.showLocal(
      title: title,
      body: body,
      kind: 'PENDING',
      group: group,
    ));
  }

  // ═════════════════════════════════════════════════════════
  // PROJECTS
  // ═════════════════════════════════════════════════════════

  static Map<String, dynamic> _mapProjectBank(Map<String, dynamic> b) {
    // Banano bank naam (Dutch-Bangla / Marinozz PLC) ar default dewa hoy na —
    // investor bhul account e taka pathate pare
    return {
      'id': b['id'].toString(),
      'bankName': b['bankName']?.toString() ?? '',
      'accountName': b['accountName']?.toString() ?? '',
      'accountNumber': b['accountNumber']?.toString() ?? '',
      'branchName': b['branchName']?.toString() ?? '',
      'routingNumber': b['routingNumber']?.toString() ?? '',
      'swiftCode': b['swiftCode']?.toString() ?? '',
      'mobileNumber': b['mobileNumber']?.toString() ?? '',
      'email': b['email']?.toString() ?? '',
      'branchAddress': b['branchAddress']?.toString() ?? '',
    };
  }

  // ═════════════════════════════════════════════════════════
  // PROJECT RETURN RANGE — website er motoi prottek project er nijer
  // returnPctMin–returnPctMax. Na thakle expectedReturnPct. Tao na thakle
  // 0 — tokhon app "—" dekhay (banano 16–22% ar na).
  // ═════════════════════════════════════════════════════════
  static const double platformReturnMin = 0;
  static const double platformReturnMax = 0;

  static Map<String, double> projectReturnRange(Map<String, dynamic> r) {
    final lo = _normalizePct(r['returnPctMin']);
    final hi = _normalizePct(r['returnPctMax']);
    final exp = _normalizePct(r['expectedReturnPct']);
    if (lo > 0 || hi > 0) {
      final a = lo > 0 ? lo : hi;
      final b = hi > 0 ? hi : lo;
      return {'returnMin': a <= b ? a : b, 'returnMax': a <= b ? b : a};
    }
    if (exp > 0) return {'returnMin': exp, 'returnMax': exp};
    return {'returnMin': platformReturnMin, 'returnMax': platformReturnMax};
  }

  /// Project er cover — na thakle '' (stock chobi boshabo na)
  static String _projectImage(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    return s.isEmpty ? '' : formatImageUrl(s);
  }

  /// Investor ra je status er project dekhte pare (DRAFT / review e thaka na)
  static const String _publicProjectStatuses =
      "('FUNDRAISING', 'FUNDED', 'ACTIVE', 'HARVESTING', 'COMPLETED')";

  static Map<String, dynamic> _mapProjectCard(Map<String, dynamic> r) {
    final goal = _toDouble(r['fundingGoalBdt'], 1.0);
    final funded = _toDouble(r['fundedAmountBdt']);
    final range = projectReturnRange(r);
    final deadline = r['fundingDeadline']?.toString() ?? '';

    // Banano default (৳10,000 / 180 din / 15% / "Bangladesh") ar na —
    // na thakle 0 ba '', page sheta lukabe
    return {
      'id': r['id'].toString(),
      'slug': r['slug']?.toString() ?? '',
      'title': r['title']?.toString() ?? '',
      'category': r['category']?.toString() ?? '',
      // Category OTHER hole admin je nam likheche
      'customCategory': r['customCategory']?.toString() ?? '',
      'returnType': r['returnType']?.toString() ?? '',
      'groupName': r['groupName']?.toString() ?? '',
      'groupSlug': r['groupSlug']?.toString() ?? '',
      'fundingDeadline': deadline,
      'createdAt': r['createdAt']?.toString() ?? '',
      'imageUrls': [
        for (final img in _parseTextArray(r['imageUrls']))
          if (_projectImage(img).isNotEmpty) _projectImage(img),
      ],
      'description': r['description']?.toString() ?? '',
      'fundingGoalBdt': goal,
      'fundedAmountBdt': funded,
      'progress': goal > 0 ? (funded / goal).clamp(0.0, 1.0).toDouble() : 0.0,
      'minInvestmentBdt': _toDouble(r['minInvestmentBdt']),
      'expectedReturnPct': range['returnMax'],
      'returnMin': range['returnMin'],
      'returnMax': range['returnMax'],
      'durationDays': _toInt(r['durationDays']),
      'coverImageUrl': _projectImage(r['coverImageUrl']),
      'status': r['status']?.toString() ?? '',
      'location': r['location']?.toString() ?? '',
      'hasDeadline': deadline.isNotEmpty,
      'daysLeft': _daysLeft(deadline),
      'deadlineDays': deadlineDaysDhaka(deadline),
      'deadlinePassed': deadlinePassed(deadline),
      // Ekhon invest kora jay: FUNDRAISING + deadline periye jayni + taka baki
      'acceptingInvestment': (r['status']?.toString() ?? '') == 'FUNDRAISING' &&
          !deadlinePassed(deadline) &&
          funded < goal,
      'investorsCount': _toInt(r['investorsCount']),
    };
  }

  // Fetch Full Single Project Detail
  /// Website er /projects/[slug] page er data. [userId] dile oi investor er
  /// ei project e age kora investment (website er "Investment status") o ane.
  static Future<Map<String, dynamic>> getProjectDetail(String projectIdOrSlug, {String? userId}) async {
    try {
      final projRes = await queryNeonHttp('''
        SELECT p."id", p."title", p."slug", p."description", p."category"::text AS "category",
               to_jsonb(p) ->> 'customCategory' AS "customCategory",
               p."status"::text AS "status", p."riskInfo", p."location", p."fundingGoalBdt",
               p."fundingMinBdt", p."fundedAmountBdt", p."minInvestmentBdt", p."maxInvestmentBdt",
               p."expectedReturnPct", p."returnPctMin", p."returnPctMax",
               p."returnType"::text AS "returnType", p."durationDays",
               p."fundingDeadline", p."startDate", p."endDate", p."coverImageUrl",
               p."imageUrls", bg."name" as "groupName", bg."slug"::text AS "groupSlug",
               -- Website er notun field (column na thakle null)
               to_jsonb(p) ->> 'riskLevel' AS "riskLevel",
               to_jsonb(p) ->> 'payoutPeriodMonths' AS "payoutPeriodMonths",
               -- Website er _count.investments ("Investors so far")
               (SELECT COUNT(*) FROM investments i WHERE i."projectId" = p."id") as "investorsCount"
        FROM projects p
        LEFT JOIN business_groups bg ON p."groupId" = bg."id"
        WHERE (p."id" = \$1 OR p."slug" = \$1)
          AND p."deletedAt" IS NULL
          AND p."status"::text IN $_publicProjectStatuses
      ''', [projectIdOrSlug]);

      if (projRes.isEmpty) {
        return _lastConnectionError != null ? {'error': 'network'} : {};
      }

      final r = projRes.first;
      final projectId = r['id'].toString();

      final goal = _toDouble(r['fundingGoalBdt'], 1.0);
      final funded = _toDouble(r['fundedAmountBdt']);

      // Website er motoi: cover + baki chobi, shorbochcho 5 ta
      final coverUrl = _projectImage(r['coverImageUrl']);
      final List<String> imageUrls = [if (coverUrl.isNotEmpty) coverUrl];
      for (final img in _parseTextArray(r['imageUrls'])) {
        final formatted = _projectImage(img);
        if (formatted.isNotEmpty && !imageUrls.contains(formatted)) imageUrls.add(formatted);
      }
      if (imageUrls.length > 5) imageUrls.removeRange(5, imageUrls.length);

      final deadlineStr = r['fundingDeadline']?.toString() ?? '';
      final range = projectReturnRange(r);
      final uid = userId?.trim() ?? '';

      final extra = await Future.wait([
        queryNeonHttp('''
          SELECT "id", "bankName", "accountName", "accountNumber", "branchName",
                 "routingNumber", "swiftCode", "mobileNumber", "email", "branchAddress"
          FROM project_bank_accounts
          WHERE "projectId" = \$1 AND "isActive" = true
          ORDER BY "createdAt" ASC
        ''', [projectId]),
        // Ei project er prokashito update — website er moto publishedAt diye
        queryNeonHttp('''
          SELECT u."id", u."title", u."content", u."type"::text AS "type",
                 u."publishedAt", u."createdAt"
          FROM project_updates u
          WHERE u."projectId" = \$1 AND u."isPublished" = true
          ORDER BY u."publishedAt" DESC NULLS LAST, u."createdAt" DESC
          LIMIT 20
        ''', [projectId]),
        // Brochure — website er brochure.data.ts: description = "Project brochure"
        // tag kora PROJECT_DOCUMENT, muche na fela notun ta
        queryNeonHttp('''
          SELECT d."id", d."name", d."fileUrl", d."mimeType", d."sizeBytes"
          FROM documents d
          WHERE d."entityType"::text = 'PROJECT'
            AND d."entityId" = \$1
            AND d."category"::text = 'PROJECT_DOCUMENT'
            AND d."description" = '$projectBrochureTag'
            AND d."deletedAt" IS NULL
          ORDER BY d."createdAt" DESC
          LIMIT 1
        ''', [projectId]),
        // "Project documents" — website e project er public document gulo
        queryNeonHttp('''
          SELECT d."id", d."name", d."fileUrl", d."mimeType", d."sizeBytes", d."createdAt"
          FROM documents d
          WHERE d."entityId" = \$1
            AND d."isPublic" = true
            AND d."deletedAt" IS NULL
            AND COALESCE(d."description", '') <> '$projectBrochureTag'
          ORDER BY d."createdAt" DESC
        ''', [projectId]),
        // Ei investor er ei project e shesh investment (CANCELLED / REFUNDED chara)
        if (uid.isNotEmpty)
          queryNeonHttp('''
            SELECT i."id", i."status"::text AS "status", i."amountBdt", i."expectedReturnBdt",
                   i."paymentPlan",
                   (SELECT COALESCE(SUM(m."amountBdt"), 0) FROM manual_payment_submissions m
                     WHERE m."investmentId" = i."id" AND m."submittedBy" = \$2
                       AND m."status"::text = 'APPROVED') AS "approvedBdt",
                   (SELECT COALESCE(SUM(m."amountBdt"), 0) FROM manual_payment_submissions m
                     WHERE m."investmentId" = i."id" AND m."submittedBy" = \$2
                       AND m."status"::text IN ('SUBMITTED', 'UNDER_REVIEW')) AS "pendingBdt",
                   ls."subStatus", ls."transactionRef", ls."rejectionReason"
            FROM investments i
            JOIN investor_profiles ip ON ip."id" = i."investorProfileId"
            LEFT JOIN LATERAL (
              SELECT m."status"::text AS "subStatus", m."transactionRef", m."rejectionReason"
              FROM manual_payment_submissions m
              WHERE m."investmentId" = i."id" AND m."submittedBy" = \$2
              ORDER BY m."createdAt" DESC
              LIMIT 1
            ) ls ON true
            WHERE i."projectId" = \$1
              AND ip."userId" = \$2
              AND i."status"::text NOT IN ('CANCELLED', 'REFUNDED')
            ORDER BY i."createdAt" DESC
            LIMIT 1
          ''', [projectId, uid])
        else
          Future.value(<Map<String, dynamic>>[]),
      ]);
      final bankRes = extra[0];
      final brochureRes = extra[2];
      final docsRes = extra[3];
      final myInvRes = extra[4];

      // Tarikh raw (ISO) pathai — page nijer bhashay sajabe; na thakle ''
      String dateOrEmpty(dynamic v) => v?.toString() ?? '';

      Map<String, dynamic> docMap(Map<String, dynamic> d) => <String, dynamic>{
        'id': d['id'].toString(),
        'name': d['name']?.toString() ?? '',
        'fileUrl': d['fileUrl']?.toString() ?? '',
        'mimeType': d['mimeType']?.toString() ?? '',
        'sizeBytes': _toInt(d['sizeBytes']),
      };

      Map<String, dynamic>? myInvestment;
      if (myInvRes.isNotEmpty) {
        final m = myInvRes.first;
        myInvestment = {
          'id': m['id'].toString(),
          'status': m['status']?.toString() ?? 'PENDING',
          'amountBdt': _toDouble(m['amountBdt']),
          'expectedReturnBdt': _toDouble(m['expectedReturnBdt']),
          'paymentPlan': m['paymentPlan']?.toString() ?? 'FULL',
          'approvedBdt': _toDouble(m['approvedBdt']),
          'pendingBdt': _toDouble(m['pendingBdt']),
          // Shesh payment proof — na thakle null
          'lastSubmissionStatus': m['subStatus']?.toString(),
          'lastTransactionRef': m['transactionRef']?.toString() ?? '',
          'lastRejectionReason': m['rejectionReason']?.toString() ?? '',
        };
      }

      return {
        'id': projectId,
        'title': r['title']?.toString() ?? '',
        'slug': r['slug']?.toString() ?? '',
        'description': r['description']?.toString() ?? '',
        'category': r['category']?.toString() ?? '',
        'customCategory': r['customCategory']?.toString() ?? '',
        'status': r['status']?.toString() ?? '',
        'riskInfo': r['riskInfo']?.toString() ?? '',
        'riskLevel': (r['riskLevel']?.toString() ?? '').toUpperCase(),
        // 1 / 3 / 6 / 9 mash por por lav; 0 = meyad sheshe ekbare
        'payoutPeriodMonths': _toInt(r['payoutPeriodMonths']),
        'location': r['location']?.toString() ?? '',
        'fundingGoalBdt': goal,
        'fundingMinBdt': _toDouble(r['fundingMinBdt']),
        'fundedAmountBdt': funded,
        'minInvestmentBdt': _toDouble(r['minInvestmentBdt']),
        'maxInvestmentBdt': _toDoubleOrNull(r['maxInvestmentBdt']),
        'expectedReturnPct': range['returnMax'],
        'returnMin': range['returnMin'],
        'returnMax': range['returnMax'],
        'returnType': r['returnType']?.toString() ?? '',
        'durationDays': _toInt(r['durationDays']),
        'fundingDeadline': dateOrEmpty(r['fundingDeadline']),
        'startDate': dateOrEmpty(r['startDate']),
        'endDate': dateOrEmpty(r['endDate']),
        'hasDeadline': deadlineStr.isNotEmpty,
        'updates': extra[1].map((u) => <String, dynamic>{
          'id': u['id'].toString(),
          'title': u['title']?.toString() ?? '',
          'content': u['content']?.toString() ?? '',
          'type': u['type']?.toString() ?? '',
          'publishedAt': u['publishedAt']?.toString() ?? '',
          'createdAt': u['createdAt']?.toString() ?? '',
        }).toList(),
        'coverImageUrl': coverUrl,
        'imageUrls': imageUrls,
        'groupName': r['groupName']?.toString() ?? '',
        'groupSlug': r['groupSlug']?.toString() ?? '',
        'investorsCount': _toInt(r['investorsCount']),
        'remainingBdt': (goal - funded).clamp(0.0, double.infinity).toDouble(),
        'progress': goal > 0 ? (funded / goal).clamp(0.0, 1.0).toDouble() : 0.0,
        'daysLeft': _daysLeft(deadlineStr),
        'deadlineDays': deadlineDaysDhaka(deadlineStr),
        'deadlinePassed': deadlinePassed(deadlineStr),
        // Website er investment.service: shudhu FUNDRAISING, deadline er din
        // shesh hoyni, ar taka baki
        'acceptingInvestment': (r['status']?.toString() ?? '') == 'FUNDRAISING' &&
            !deadlinePassed(deadlineStr) &&
            funded < goal,
        'bankAccounts': bankRes.map(_mapProjectBank).toList(),
        // Brochure na thakle null — page e card dekhabe na
        'brochure': brochureRes.isEmpty ? null : docMap(brochureRes.first),
        'documents': docsRes.map(docMap).toList(),
        // Investor er ei project e investment — na thakle null
        'myInvestment': myInvestment,
      };
    } catch (e) {
      debugPrint("Get Project Detail Error: $e");
      return {};
    }
  }

  // ═════════════════════════════════════════════════════════
  // WEBSITE DOCUMENT DOWNLOAD
  // Website document (brochure, deed ityadi) Cloudinary te "authenticated" —
  // fileUrl ashole storage key, sorasori link na. Website er
  // /api/documents/[id]/download login cookie (bc_session) chay, tai app
  // website er sessions table e nijer ekta session rakhe ar oi cookie pathay.
  // Website tokhon nijei permission check kore, signed link baniye file dey.
  // ═════════════════════════════════════════════════════════
  static const String projectBrochureTag = 'Project brochure';
  static const String _websiteApiBase = 'https://www.biniyogclub.com';
  static const String _appSessionAgent = 'BiniyogClub App';
  static String? _webSessionToken;
  static String? _webSessionUserId;

  static String _secureToken() {
    final rnd = Random.secure();
    return List<int>.generate(32, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Website er moto 64 hex token er session — ager ta (1 ghontar beshi
  /// meyad baki) thakle oita-i, na hole notun (7 din)
  static Future<String?> _websiteSession(String userId, {bool forceNew = false}) async {
    if (!forceNew && _webSessionToken != null && _webSessionUserId == userId) return _webSessionToken;
    if (!forceNew) {
      final rows = await queryNeonHttp('''
        SELECT "token" FROM sessions
        WHERE "userId" = \$1 AND "userAgent" = \$2
          AND "expiresAt" > NOW() + INTERVAL '1 hour'
        ORDER BY "expiresAt" DESC
        LIMIT 1
      ''', [userId, _appSessionAgent]);
      if (rows.isNotEmpty) {
        _webSessionToken = rows.first['token']?.toString();
        _webSessionUserId = userId;
        return _webSessionToken;
      }
    }
    final token = _secureToken();
    final ok = await executeNeonHttp('''
      INSERT INTO sessions ("id", "userId", "token", "userAgent", "expiresAt", "createdAt")
      VALUES (\$1, \$2, \$3, \$4, NOW() + INTERVAL '7 days', NOW())
    ''', [_generateUuid(), userId, token, _appSessionAgent]);
    if (!ok) return null;
    _webSessionToken = token;
    _webSessionUserId = userId;
    return token;
  }

  /// Logout er shomoy dakle app er website session muche jay (optional)
  static Future<void> clearWebsiteSession(String userId) async {
    _webSessionToken = null;
    _webSessionUserId = null;
    if (userId.isEmpty) return;
    await executeNeonHttp('''
      DELETE FROM sessions WHERE "userId" = \$1 AND "userAgent" = \$2
    ''', [userId, _appSessionAgent]);
  }

  /// Content-Disposition theke file er nam (UTF-8 nam age)
  static String? _fileNameFromDisposition(String? header) {
    if (header == null || header.isEmpty) return null;
    final star = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false).firstMatch(header);
    if (star != null) {
      try {
        return Uri.decodeComponent(star.group(1)!.trim());
      } catch (_) {}
    }
    final plain = RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(header);
    return plain?.group(1)?.trim();
  }

  /// Website theke document download — login thaka investor er jonno.
  /// Shofol hole bytes, file er nam ar mime; na hole null + [lastDownloadError]
  static String? lastDownloadError;

  static Future<({Uint8List bytes, String fileName, String mimeType})?> downloadWebsiteDocument({
    required String userId,
    required String documentId,
  }) async {
    lastDownloadError = null;
    if (userId.isEmpty) {
      lastDownloadError = _loginRequiredMsg;
      return null;
    }
    for (int attempt = 1; attempt <= 2; attempt++) {
      final token = await _websiteSession(userId, forceNew: attempt == 2);
      if (token == null) {
        lastDownloadError = 'Could not connect. Please check your internet.';
        return null;
      }
      try {
        final res = await _httpClient.get(
          Uri.parse('$_websiteApiBase/api/documents/$documentId/download'),
          headers: {'Cookie': 'bc_session=$token'},
        ).timeout(const Duration(seconds: 45));

        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          final mime = (res.headers['content-type'] ?? 'application/octet-stream').split(';').first.trim();
          final name = _fileNameFromDisposition(res.headers['content-disposition']) ?? 'document';
          return (bytes: res.bodyBytes, fileName: name, mimeType: mime);
        }
        // Session meyad shesh / muche gele ekbar notun session diye abar
        if (res.statusCode == 401 && attempt == 1) {
          _webSessionToken = null;
          continue;
        }
        debugPrint('Website document download ${res.statusCode}: ${res.body}');
        lastDownloadError = res.statusCode == 404
            ? 'This file is no longer available.'
            : res.statusCode == 403
            ? 'You do not have access to this file.'
            : 'Download failed. Please try again.';
        return null;
      } catch (e) {
        debugPrint('Website document download error: $e');
        lastDownloadError = 'Download failed. Check your internet.';
        return null;
      }
    }
    lastDownloadError = 'Download failed. Please try again.';
    return null;
  }

  // Fetch Projects Data
  /// Website er /projects page er moto: muche fela (deletedAt) project bad,
  /// notun project age (website er "Newest"). Sort / search / category page
  /// nije kore — website er moto.
  static Future<Map<String, dynamic>> getProjectsData() async {
    try {
      final results = await Future.wait([
        queryNeonHttp('''
          SELECT p."id", p."slug", p."title", p."category"::text AS "category",
                 to_jsonb(p) ->> 'customCategory' AS "customCategory",
                 p."description", p."fundingGoalBdt",
                 p."fundedAmountBdt", p."minInvestmentBdt", p."expectedReturnPct",
                 p."returnPctMin", p."returnPctMax", p."returnType"::text AS "returnType", p."durationDays",
                 p."coverImageUrl", p."imageUrls", p."status"::text AS "status", p."location", p."fundingDeadline",
                 p."createdAt", bg."name" AS "groupName", bg."slug"::text AS "groupSlug",
                 -- Website er _count.investments: oi project er shob investment
                 (SELECT COUNT(*) FROM investments i WHERE i."projectId" = p."id") AS "investorsCount"
          FROM projects p
          LEFT JOIN business_groups bg ON bg."id" = p."groupId"
          WHERE p."deletedAt" IS NULL
            AND p."status"::text IN $_publicProjectStatuses
          ORDER BY p."createdAt" DESC
        '''),
        queryNeonHttp('''
          SELECT u."id", u."title", u."content", u."type"::text AS "type", u."createdAt", p."title" as "projectTitle"
          FROM project_updates u
          JOIN projects p ON u."projectId" = p."id"
          WHERE u."isPublished" = true AND p."deletedAt" IS NULL
          ORDER BY COALESCE(u."publishedAt", u."createdAt") DESC
          LIMIT 10
        '''),
      ]);

      final updates = results[1].map((r) {
        return {
          'id': r['id'].toString(),
          'title': r['title']?.toString() ?? 'Project Update',
          'content': r['content']?.toString() ?? '',
          'type': r['type']?.toString() ?? 'GENERAL',
          'createdAt': r['createdAt']?.toString() ?? '',
          'projectTitle': r['projectTitle']?.toString() ?? 'Project',
        };
      }).toList();

      return {
        'projects': results[0].map(_mapProjectCard).toList(),
        'updates': updates,
      };
    } catch (e) {
      debugPrint("Get Projects Data Error: $e");
      return {};
    }
  }

  // ═════════════════════════════════════════════════════════
  // LANDING PAGE (login chara) — website er home page er data:
  // public project (kon group er, sheta soho) + mot investor sonkha
  // ═════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> getLandingData() async {
    try {
      final results = await Future.wait([
        queryNeonHttp('''
          SELECT p."id", p."title", p."category"::text AS "category", p."description", p."fundingGoalBdt",
                 p."fundedAmountBdt", p."minInvestmentBdt", p."expectedReturnPct",
                 p."returnPctMin", p."returnPctMax", p."durationDays",
                 p."coverImageUrl", p."status"::text AS "status", p."location", p."fundingDeadline",
                 p."groupId", bg."name" AS "groupName", bg."slug"::text AS "groupSlug",
                 (SELECT COUNT(DISTINCT i."investorProfileId") FROM investments i WHERE i."projectId" = p."id") AS "investorsCount"
          FROM projects p
          LEFT JOIN business_groups bg ON bg."id" = p."groupId"
          WHERE p."deletedAt" IS NULL
            AND p."status"::text IN $_publicProjectStatuses
          ORDER BY (p."status"::text = 'FUNDRAISING') DESC, p."createdAt" DESC
        '''),
        // Website er motoi: ACTIVE investor account
        queryNeonHttp('''
          SELECT COUNT(*) AS "n" FROM users
          WHERE "role"::text = 'INVESTOR' AND "deletedAt" IS NULL AND "status"::text = 'ACTIVE'
        '''),
        // Landing page er shotti hishab — kono banano shonkha na
        queryNeonHttp('''
          SELECT COUNT(*) AS "projects",
                 COUNT(*) FILTER (WHERE p."status"::text = 'COMPLETED') AS "completed",
                 COALESCE(SUM(p."fundedAmountBdt"), 0) AS "funded"
          FROM projects p
          WHERE p."deletedAt" IS NULL AND p."status"::text IN $_publicProjectStatuses
        '''),
        // Website er "Latest updates" — published project update (shesh 3 ta)
        queryNeonHttp('''
          SELECT u."id", u."title", u."content", u."type"::text AS "type",
                 COALESCE(u."publishedAt", u."createdAt") AS "publishedAt",
                 p."id" AS "projectId", p."title" AS "projectTitle", p."coverImageUrl"
          FROM project_updates u
          JOIN projects p ON p."id" = u."projectId"
          WHERE u."isPublished" = true AND p."deletedAt" IS NULL
            AND p."status"::text IN $_publicProjectStatuses
          ORDER BY COALESCE(u."publishedAt", u."createdAt") DESC
          LIMIT 3
        '''),
      ]);

      final projects = results[0].map((r) {
        return <String, dynamic>{
          ..._mapProjectCard(r),
          'groupId': r['groupId']?.toString() ?? '',
          'groupName': r['groupName']?.toString() ?? '',
          'groupSlug': r['groupSlug']?.toString() ?? '',
        };
      }).toList();

      final st = results[2].isEmpty ? <String, dynamic>{} : results[2].first;
      final updates = results[3]
          .map((r) => <String, dynamic>{
        'id': r['id'].toString(),
        'title': r['title']?.toString() ?? '',
        'content': r['content']?.toString() ?? '',
        'type': r['type']?.toString() ?? 'GENERAL',
        'publishedAt': r['publishedAt']?.toString() ?? '',
        'projectId': r['projectId']?.toString() ?? '',
        'projectTitle': r['projectTitle']?.toString() ?? '',
        'coverImageUrl': _projectImage(r['coverImageUrl']),
      })
          .toList();

      return {
        'ok': results[0].isNotEmpty || _lastConnectionError == null,
        'projects': projects,
        'totalInvestors': results[1].isEmpty ? 0 : _toInt(results[1].first['n']),
        'totalProjects': _toInt(st['projects']),
        'completedProjects': _toInt(st['completed']),
        'totalFundedBdt': _toDouble(st['funded']),
        'updates': updates,
      };
    } catch (e) {
      debugPrint("Get Landing Data Error: $e");
      return {
        'ok': false,
        'projects': <Map<String, dynamic>>[],
        'totalInvestors': 0,
        'totalProjects': 0,
        'completedProjects': 0,
        'totalFundedBdt': 0.0,
        'updates': <Map<String, dynamic>>[],
      };
    }
  }

  // ═════════════════════════════════════════════════════════
  // USER PROFILE + DASHBOARD
  // ═════════════════════════════════════════════════════════

  /// userId na thakle email diye khuji. Kichui na thakle '' —
  /// ar kokhono "latest registered user" er data ana hoy na.
  static Future<String> _resolveUserId(String userId, String? email) async {
    if (userId.isNotEmpty) return userId;
    final e = (email ?? '').trim();
    if (e.isEmpty) return '';
    final uRes = await queryNeonHttp(
        'SELECT "id" FROM users WHERE LOWER("email") = LOWER(\$1) LIMIT 1', [e]);
    return uRes.isNotEmpty ? uRes.first['id'].toString() : '';
  }

  // ═════════════════════════════════════════════════════════
  // PROFILE EDIT — nam, phone, email, jonmo tarikh, NID, thikana, nominee,
  // pesha ityadi. Khali ('') dile oi tottho muche jay (NULL).
  // Shudhu website er schema te je column ache, sheguloi bodlay.
  // ═════════════════════════════════════════════════════════
  static const List<String> editableProfileFields = [
    'nationalId',
    'address',
    'city',
    'nomineeName',
    'nomineeNationalId',
    'nomineeRelation',
    'occupation',
    'annualIncomeRange',
    'investmentExperience',
    'riskTolerance',
  ];

  static Future<Map<String, dynamic>> updateUserProfile({
    required String userId,
    required String name,
    required String phone,
    String? email,
    DateTime? dateOfBirth,
    Map<String, String> profile = const {},
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    try {
      final cleanName = name.trim();
      final cleanPhone = canonicalPhone(phone);
      final pv = phoneVariants(cleanPhone);
      final cleanEmail = (email ?? '').trim().toLowerCase();
      if (cleanName.length < 2) return {'success': false, 'message': 'Please enter your full name.'};
      if (!isValidPhone(cleanPhone)) {
        return {'success': false, 'message': 'Please enter a valid mobile number with country code.'};
      }

      final vals = <String, String?>{
        for (final k in editableProfileFields)
          if (profile.containsKey(k)) k: (profile[k] ?? '').trim().isEmpty ? null : profile[k]!.trim(),
      };
      final nid = vals['nationalId'];

      await _ensureInvestorProfileExists(userId);
      final metas = await Future.wait([_columnsOf('users'), _columnsOf('investor_profiles')]);
      final userCols = metas[0];
      final profCols = metas[1];
      if (userCols.isEmpty || profCols.isEmpty) return {'success': false, 'message': _connectionErrorMsg()};

      // Onno karo sathe mile jay kina
      final dup = await queryNeonHttp('''
        SELECT
          (SELECT 1 FROM users WHERE "id" <> \$1 AND "phone" IN (\$2, \$5, \$6) LIMIT 1) AS "phoneTaken",
          (SELECT 1 FROM users WHERE "id" <> \$1 AND \$3::text IS NOT NULL AND LOWER("email") = LOWER(\$3::text) LIMIT 1) AS "emailTaken",
          (SELECT 1 FROM investor_profiles WHERE "userId" <> \$1 AND \$4::text IS NOT NULL AND "nationalId" = \$4::text LIMIT 1) AS "nidTaken",
          (SELECT "email" FROM users WHERE "id" = \$1) AS "oldEmail"
      ''', [userId, cleanPhone, cleanEmail.isEmpty ? null : cleanEmail, nid, pv[1], pv[2]]);
      if (dup.isEmpty) return {'success': false, 'message': _connectionErrorMsg()};
      final d = dup.first;
      if (d['phoneTaken'] != null) {
        return {'success': false, 'message': 'This mobile number is already used by another account.'};
      }
      if (d['emailTaken'] != null) {
        return {'success': false, 'message': 'This email is already used by another account.'};
      }
      if (d['nidTaken'] != null) {
        return {'success': false, 'message': 'This NID number is already used by another account.'};
      }
      final nomineeNid = vals['nomineeNationalId'];
      if (nid != null && nomineeNid != null && nid == nomineeNid) {
        return {'success': false, 'message': 'Nominee NID cannot be your own NID.'};
      }

      // Email khali: column nullable hole NULL, na hole nokol thikana
      final String? emailValue = cleanEmail.isNotEmpty
          ? cleanEmail
          : (userCols['email'] == true ? null : 'u$cleanPhone$_noEmailDomain');
      final oldEmail = (d['oldEmail']?.toString() ?? '').toLowerCase();
      final emailChanged = (emailValue ?? '').toLowerCase() != oldEmail;
      final nowStr = _nowIso();

      final dobStr = dateOfBirth == null
          ? null
          : '${dateOfBirth.year}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}';

      // users
      final uSets = <String>['"name" = \$2', '"phone" = \$3', '"email" = \$4', '"updatedAt" = \$5'];
      final uParams = <dynamic>[userId, cleanName, cleanPhone, emailValue, nowStr];
      if (emailChanged && userCols.containsKey('emailVerified')) uSets.add('"emailVerified" = false');
      if (!profCols.containsKey('dateOfBirth') && userCols.containsKey('dateOfBirth')) {
        uParams.add(dobStr);
        uSets.add('"dateOfBirth" = \$${uParams.length}');
      }
      final okUser = await executeNeonHttp('UPDATE users SET ${uSets.join(', ')} WHERE "id" = \$1', uParams);
      if (!okUser) return {'success': false, 'message': _connectionErrorMsg()};

      // investor_profiles — shudhu ja column ache
      final pSets = <String>['"updatedAt" = \$2'];
      final pParams = <dynamic>[userId, nowStr];
      vals.forEach((k, v) {
        if (!profCols.containsKey(k)) return;
        pParams.add(v);
        pSets.add('"$k" = \$${pParams.length}');
      });
      if (profCols.containsKey('dateOfBirth')) {
        pParams.add(dobStr);
        pSets.add('"dateOfBirth" = \$${pParams.length}');
      }
      final okProf =
      await executeNeonHttp('UPDATE investor_profiles SET ${pSets.join(', ')} WHERE "userId" = \$1', pParams);
      if (!okProf) return {'success': false, 'message': _connectionErrorMsg()};

      return {
        'success': true,
        'message': 'Profile updated.',
        'data': {'id': userId, 'name': cleanName, 'email': cleanEmail, 'phone': cleanPhone},
      };
    } catch (e) {
      return {'success': false, 'message': 'Database error: ${e.toString()}'};
    }
  }

  // Fetch Full User Profile & Investor Profile
  static Future<Map<String, dynamic>> getUserProfileFull(String userId, {String? email}) async {
    try {
      final activeUserId = await _resolveUserId(userId, email);
      if (activeUserId.isEmpty) return {};

      await _ensureInvestorProfileExists(activeUserId);

      final results = await Future.wait([
        queryNeonHttp('''
          SELECT u."id", u."name", u."email", u."phone", u."emailVerified", u."phoneVerified",
                 u."createdAt", u."avatarUrl", to_jsonb(u) ->> 'dateOfBirth' AS "dob"
          FROM users u
          WHERE u."id" = \$1
        ''', [activeUserId]),
        queryNeonHttp('''
          SELECT to_jsonb(p) AS "raw"
          FROM investor_profiles p
          WHERE p."userId" = \$1
        ''', [activeUserId]),
      ]);

      final userRes = results[0];
      final profRes = results[1];

      if (userRes.isEmpty) return {};
      final uRow = userRes.first;

      Map<String, dynamic> p = {};
      if (profRes.isNotEmpty) {
        final r0 = profRes.first['raw'];
        if (r0 is Map) {
          p = Map<String, dynamic>.from(r0);
        } else if (r0 is String) {
          try {
            p = Map<String, dynamic>.from(jsonDecode(r0) as Map);
          } catch (_) {}
        }
      }

      // Kono banano default nei — user ja dey ni, ta khali ('') thake
      String prof(String key) => p[key]?.toString().trim() ?? '';

      // Jonmo tarikh: investor_profiles e na thakle users e
      String dob = prof('dateOfBirth');
      if (dob.isEmpty) dob = uRow['dob']?.toString() ?? '';

      final profMap = <String, String>{
        'nationalId': prof('nationalId'),
        'dateOfBirth': dob,
        'address': prof('address'),
        'city': prof('city'),
        'nomineeName': prof('nomineeName'),
        'nomineeNationalId': prof('nomineeNationalId'),
        'nomineeRelation': prof('nomineeRelation'),
        'country': prof('country'),
        'occupation': prof('occupation'),
        'annualIncomeRange': prof('annualIncomeRange'),
        'investmentExperience': prof('investmentExperience'),
        'riskTolerance': prof('riskTolerance'),
      };

      final rawAvatar = uRow['avatarUrl']?.toString();

      return {
        'id': uRow['id'].toString(),
        'name': uRow['name']?.toString() ?? '',
        'email': _publicEmail(uRow['email']),
        'phone': uRow['phone']?.toString() ?? '',
        'emailVerified': !isPlaceholderEmail(uRow['email']?.toString()) && ((uRow['emailVerified'] as bool?) ?? false),
        'phoneVerified': (uRow['phoneVerified'] as bool?) ?? false,
        'createdAt': uRow['createdAt']?.toString() ?? '',
        'avatarUrl': rawAvatar != null && rawAvatar.isNotEmpty ? formatImageUrl(rawAvatar) : null,
        'investorProfile': profMap,
      };
    } catch (e) {
      debugPrint("Get Full User Profile Error: $e");
      return {};
    }
  }

  // Fetch Dashboard Summary Data
  static Future<Map<String, dynamic>> getDashboardSummary(String userId, {String? email}) async {
    try {
      final activeUserId = await _resolveUserId(userId, email);
      if (activeUserId.isEmpty) return {};

      await _ensureInvestorProfileExists(activeUserId);

      final results = await Future.wait([
        // 1. Shob stats ek query te
        queryNeonHttp('''
          SELECT
            (SELECT "avatarUrl" FROM users WHERE "id" = \$1) as avatar_url,
            (SELECT COUNT(*) FROM notifications WHERE "userId" = \$1 AND "isRead" = false) as unread_notif_count,
            -- Website: activeCount = shudhu ACTIVE
            (SELECT COUNT(*) FROM investments i JOIN investor_profiles p ON i."investorProfileId" = p."id"
             WHERE p."userId" = \$1 AND i."status"::text = 'ACTIVE') as active_inv_count,
            (SELECT COUNT(*) FROM investments i JOIN investor_profiles p ON i."investorProfileId" = p."id"
             WHERE p."userId" = \$1 AND i."status"::text IN ('ACTIVE', 'MATURED', 'COMPLETED')) as live_inv_count,
            -- Website: kisti cholche (PAYMENT_PENDING) emon investment e finance je taka APPROVED korechhe
            (SELECT COALESCE(SUM(m."amountBdt"), 0) FROM manual_payment_submissions m
             JOIN investments i ON i."id" = m."investmentId"
             JOIN investor_profiles p ON i."investorProfileId" = p."id"
             WHERE p."userId" = \$1 AND i."status"::text = 'PAYMENT_PENDING' AND m."status"::text = 'APPROVED') as proj_verified_partial,
            (SELECT COALESCE(SUM(m."amountBdt"), 0) FROM manual_payment_submissions m
             JOIN investments i ON i."id" = m."investmentId"
             JOIN investor_profiles p ON i."investorProfileId" = p."id"
             WHERE p."userId" = \$1 AND i."status"::text = 'PAYMENT_PENDING' AND m."status"::text IN ('SUBMITTED', 'UNDER_REVIEW')) as proj_under_review,
            (SELECT COALESCE(SUM(i."amountBdt"), 0) FROM investments i JOIN investor_profiles p ON i."investorProfileId" = p."id"
             WHERE p."userId" = \$1 AND i."status"::text = 'PAYMENT_PENDING') as proj_unpaid_committed,
            (SELECT COALESCE(SUM(x."amountBdt"), 0) FROM group_investment_payments x
             JOIN group_investments gi ON gi."id" = x."groupInvestmentId"
             WHERE gi."investorUserId" = \$1 AND gi."status"::text = 'PAYMENT_PENDING' AND x."status"::text = 'APPROVED') as grp_verified_partial,
            (SELECT COALESCE(SUM(x."amountBdt"), 0) FROM group_investment_payments x
             JOIN group_investments gi ON gi."id" = x."groupInvestmentId"
             WHERE gi."investorUserId" = \$1 AND gi."status"::text = 'PAYMENT_PENDING' AND x."status"::text IN ('SUBMITTED', 'UNDER_REVIEW')) as grp_under_review,
            (SELECT COALESCE(SUM(gi."amountBdt"), 0) FROM group_investments gi
             WHERE gi."investorUserId" = \$1 AND gi."status"::text = 'PAYMENT_PENDING') as grp_unpaid_committed,
            (SELECT COALESCE(SUM(i."amountBdt"), 0) FROM investments i JOIN investor_profiles p ON i."investorProfileId" = p."id"
             WHERE p."userId" = \$1 AND i."status"::text IN ('ACTIVE', 'MATURED', 'COMPLETED')) as total_invested_amt,
            -- Payment baki / jachai cholche: PENDING ba PAYMENT_PENDING obosthay thaka sob investment
            (SELECT COUNT(*) FROM investments i JOIN investor_profiles p ON i."investorProfileId" = p."id"
             WHERE p."userId" = \$1 AND i."status"::text IN ('PENDING', 'PAYMENT_PENDING')) as pending_tx_count,
            (SELECT COALESCE(SUM(i."amountBdt"), 0) FROM investments i JOIN investor_profiles p ON i."investorProfileId" = p."id"
             WHERE p."userId" = \$1 AND i."status"::text IN ('PENDING', 'PAYMENT_PENDING')) as pending_inv_amt,
            (SELECT COALESCE(SUM(gi."amountBdt"), 0) FROM group_investments gi
             WHERE gi."investorUserId" = \$1 AND gi."status"::text IN ('ACTIVE', 'COMPLETED')) as group_invested_amt,
            (SELECT COUNT(*) FROM group_investments gi
             WHERE gi."investorUserId" = \$1 AND gi."status"::text = 'ACTIVE') as active_group_count,
            (SELECT COUNT(*) FROM group_investments gi
             WHERE gi."investorUserId" = \$1 AND gi."status"::text IN ('PENDING', 'PAYMENT_PENDING')) as pending_group_count,
            (SELECT COALESCE(SUM(gi."amountBdt"), 0) FROM group_investments gi
             WHERE gi."investorUserId" = \$1 AND gi."status"::text IN ('PENDING', 'PAYMENT_PENDING')) as pending_group_amt,
            (SELECT COALESCE(SUM(d."netAmountBdt"), 0) FROM profit_distributions d
             JOIN investments i ON d."investmentId" = i."id"
             JOIN investor_profiles p ON i."investorProfileId" = p."id"
             WHERE p."userId" = \$1) as total_returns_amt;
        ''', [activeUserId]),

        // 2. Shudhu je project e ekhon invest kora jay ("Open for Investment")
        queryNeonHttp('''
          SELECT p."id", p."title", p."category"::text AS "category", p."fundingGoalBdt", p."fundedAmountBdt",
                 p."minInvestmentBdt", p."expectedReturnPct", p."returnPctMin", p."returnPctMax",
                 p."durationDays", p."coverImageUrl",
                 p."status"::text AS "status", p."location", p."fundingDeadline",
                 (SELECT COUNT(DISTINCT i."investorProfileId") FROM investments i WHERE i."projectId" = p."id") as "investorsCount"
          FROM projects p
          WHERE p."status"::text = 'FUNDRAISING'
            AND p."deletedAt" IS NULL
            AND $_deadlineOpenSql
          ORDER BY p."createdAt" DESC
          LIMIT 6;
        '''),

        // 3. Recent investments — project ar group duitai, notun theke purono
        queryNeonHttp('''
          SELECT * FROM (
            SELECT i."id", pr."title" AS "title", NULL::text AS "subtitle", i."amountBdt",
                   i."status"::text AS "status", i."createdAt", 'PROJECT' AS "kind"
            FROM investments i
            JOIN investor_profiles p ON i."investorProfileId" = p."id"
            JOIN projects pr ON i."projectId" = pr."id"
            WHERE p."userId" = \$1
            UNION ALL
            SELECT gi."id", ge."name" AS "title", gt."name" AS "subtitle", gi."amountBdt",
                   gi."status"::text AS "status", gi."createdAt", 'GROUP' AS "kind"
            FROM group_investments gi
            JOIN group_tiers gt    ON gt."id" = gi."tierId"
            JOIN group_entities ge ON ge."id" = gt."entityId"
            WHERE gi."investorUserId" = \$1
          ) x
          ORDER BY x."createdAt" DESC
          LIMIT 8;
        ''', [activeUserId]),
      ]);

      final userStatsRes = results[0];

      String? avatarUrl;
      int unreadNotifCount = 0;
      double projectInvested = 0.0;
      double groupInvested = 0.0;
      int activeProjCount = 0;
      int activeGroupCount = 0;
      int pendingProjTxCount = 0;
      int pendingGroupCount = 0;
      double pendingProjAmt = 0.0;
      double pendingGroupAmt = 0.0;
      double totalReturns = 0.0;
      int liveProjCount = 0;
      double verifiedPartial = 0.0;
      double underReview = 0.0;
      double unpaidCommitted = 0.0;

      if (userStatsRes.isNotEmpty) {
        final row = userStatsRes.first;
        final rawAvatar = row['avatar_url']?.toString() ?? '';
        if (rawAvatar.isNotEmpty) avatarUrl = formatImageUrl(rawAvatar);
        unreadNotifCount = _toInt(row['unread_notif_count']);
        projectInvested = _toDouble(row['total_invested_amt']);
        groupInvested = _toDouble(row['group_invested_amt']);
        activeProjCount = _toInt(row['active_inv_count']);
        activeGroupCount = _toInt(row['active_group_count']);
        pendingProjTxCount = _toInt(row['pending_tx_count']);
        pendingGroupCount = _toInt(row['pending_group_count']);
        pendingProjAmt = _toDouble(row['pending_inv_amt']);
        pendingGroupAmt = _toDouble(row['pending_group_amt']);
        totalReturns = _toDouble(row['total_returns_amt']);
        liveProjCount = _toInt(row['live_inv_count']);
        verifiedPartial = _toDouble(row['proj_verified_partial']) + _toDouble(row['grp_verified_partial']);
        underReview = _toDouble(row['proj_under_review']) + _toDouble(row['grp_under_review']);
        unpaidCommitted = _toDouble(row['proj_unpaid_committed']) + _toDouble(row['grp_unpaid_committed']);
      }
      final fullyPaid = projectInvested + groupInvested;

      final recentInvestments = results[2].map((row) {
        return <String, dynamic>{
          'id': row['id'].toString(),
          'title': row['title']?.toString() ?? '',
          'subtitle': row['subtitle']?.toString() ?? '',
          'kind': row['kind']?.toString() ?? 'PROJECT',
          'amountBdt': _toDouble(row['amountBdt']),
          'status': row['status']?.toString() ?? '',
          'createdAt': row['createdAt']?.toString() ?? '',
        };
      }).toList();

      return {
        'avatarUrl': avatarUrl,
        'unreadNotificationCount': unreadNotifCount,
        // Website: totalInvested = puro taka verify howa + kistir APPROVED ongsho
        'totalInvested': fullyPaid + verifiedPartial,
        'fullyPaidInvested': fullyPaid,
        'verifiedPartial': verifiedPartial,
        'underReview': underReview,
        'outstanding': max(0.0, unpaidCommitted - verifiedPartial - underReview),
        'committedTotal': fullyPaid + unpaidCommitted,
        'investmentCount': liveProjCount,
        'projectInvested': projectInvested,
        'groupInvested': groupInvested,
        'activeInvestmentsCount': activeProjCount + activeGroupCount,
        'activeGroupCount': activeGroupCount,
        'pendingTransactionsCount': pendingProjTxCount + pendingGroupCount,
        'pendingInvestmentsAmount': pendingProjAmt + pendingGroupAmt,
        'totalReturns': totalReturns,
        'openProjects': results[1].map(_mapProjectCard).toList(),
        'recentInvestments': recentInvestments,
        'ok': true,
      };
    } catch (e) {
      debugPrint("Get Dashboard Summary Error: $e");
      return {};
    }
  }

  /// Ekta query fail korleo baki dashboard dekhabe — shudhu oi section khali thakbe
  static Future<List<Map<String, dynamic>>> _safeQuery(String sql, List<dynamic> params) async {
    try {
      return await queryNeonHttp(sql, params);
    } catch (e) {
      debugPrint('Dashboard extra query failed: $e');
      return [];
    }
  }

  /// Website dashboard er baki sob section er data:
  /// - investments: user er sob project + group investment (amount, status,
  ///   approved / under review payment, category, tarikh) — chart, payment
  ///   progress, fully paid, committed sob ekhan theke hishab hoy
  /// - distributions: shesh 13 masher profit (netAmountBdt, distributedAt)
  /// - groupRecent: group investment (group slug / nam / entity / tier)
  /// - updates: user je project e invest koreche tar published update
  /// - documents: confirmed investment er receipt / deed number
  static Future<Map<String, dynamic>> getDashboardExtras(String userId, {String? email}) async {
    try {
      final uid = await _resolveUserId(userId, email);
      if (uid.isEmpty) return {};

      final r = await Future.wait([
        _safeQuery('''
          SELECT 'PROJECT' AS "kind", i."id", i."amountBdt", i."status"::text AS "status",
                 i."createdAt", pr."category"::text AS "category",
                 COALESCE((SELECT SUM(m."amountBdt") FROM manual_payment_submissions m
                           WHERE m."investmentId" = i."id" AND m."status"::text = 'APPROVED'), 0) AS "approved",
                 COALESCE((SELECT SUM(m."amountBdt") FROM manual_payment_submissions m
                           WHERE m."investmentId" = i."id" AND m."status"::text IN ('SUBMITTED', 'UNDER_REVIEW')), 0) AS "review"
          FROM investments i
          JOIN investor_profiles p ON i."investorProfileId" = p."id"
          JOIN projects pr ON pr."id" = i."projectId"
          WHERE p."userId" = \$1
          UNION ALL
          SELECT 'GROUP' AS "kind", gi."id", gi."amountBdt", gi."status"::text AS "status",
                 gi."createdAt", NULL::text AS "category",
                 COALESCE((SELECT SUM(g."amountBdt") FROM group_investment_payments g
                           WHERE g."groupInvestmentId" = gi."id" AND g."status"::text = 'APPROVED'), 0) AS "approved",
                 COALESCE((SELECT SUM(g."amountBdt") FROM group_investment_payments g
                           WHERE g."groupInvestmentId" = gi."id" AND g."status"::text IN ('SUBMITTED', 'UNDER_REVIEW')), 0) AS "review"
          FROM group_investments gi
          WHERE gi."investorUserId" = \$1
        ''', [uid]),
        _safeQuery('''
          SELECT d."distributedAt", d."netAmountBdt"
          FROM profit_distributions d
          JOIN investments i ON d."investmentId" = i."id"
          JOIN investor_profiles p ON i."investorProfileId" = p."id"
          WHERE p."userId" = \$1 AND d."distributedAt" >= NOW() - INTERVAL '13 months'
        ''', [uid]),
        _safeQuery('''
          SELECT gi."id", bg."slug"::text AS "slug", bg."name" AS "groupName",
                 ge."name" AS "entityName", gt."name" AS "tierName",
                 gi."amountBdt", gi."status"::text AS "status", gi."createdAt"
          FROM group_investments gi
          JOIN group_tiers gt     ON gt."id" = gi."tierId"
          JOIN group_entities ge  ON ge."id" = gt."entityId"
          JOIN business_groups bg ON bg."id" = ge."groupId"
          WHERE gi."investorUserId" = \$1
          ORDER BY gi."createdAt" DESC
          LIMIT 5
        ''', [uid]),
        _safeQuery('''
          SELECT u."id", u."title", u."type"::text AS "type",
                 COALESCE(u."publishedAt", u."createdAt") AS "at",
                 pr."id" AS "projectId", pr."title" AS "projectTitle"
          FROM project_updates u
          JOIN projects pr ON pr."id" = u."projectId"
          WHERE u."isPublished" = true
            AND u."projectId" IN (
              SELECT i."projectId" FROM investments i
              JOIN investor_profiles p ON i."investorProfileId" = p."id"
              WHERE p."userId" = \$1)
          ORDER BY COALESCE(u."publishedAt", u."createdAt") DESC
          LIMIT 4
        ''', [uid]),
        _safeQuery('''
          SELECT i."id", pr."title", i."amountBdt", i."receiptNumber", c."deedNumber"
          FROM investments i
          JOIN investor_profiles p ON i."investorProfileId" = p."id"
          JOIN projects pr ON pr."id" = i."projectId"
          LEFT JOIN investment_contracts c ON c."investmentId" = i."id"
          WHERE p."userId" = \$1 AND i."status"::text IN ('ACTIVE', 'MATURED', 'COMPLETED')
          ORDER BY i."confirmedAt" DESC NULLS LAST, i."createdAt" DESC
          LIMIT 5
        ''', [uid]),
        // Prestige — website er prestige.data.ts er hubohu:
        // Star    = confirmed (ACTIVE/MATURED/COMPLETED) investment ache emon protiti project
        // Diamond = ACTIVE, directorship na emon group investment ache emon protiti business group (max 6)
        // Crown   = ACTIVE directorship ache emon protiti company (group entity)
        _safeQuery('''
          SELECT
            (SELECT COUNT(DISTINCT i."projectId") FROM investments i
             JOIN investor_profiles p ON i."investorProfileId" = p."id"
             WHERE p."userId" = \$1 AND i."status"::text IN ('ACTIVE', 'MATURED', 'COMPLETED')) AS "stars",
            (SELECT COUNT(DISTINCT ge."groupId") FROM group_investments gi
             JOIN group_tiers gt    ON gt."id" = gi."tierId"
             JOIN group_entities ge ON ge."id" = gt."entityId"
             WHERE gi."investorUserId" = \$1 AND gi."status"::text = 'ACTIVE'
               AND gt."type"::text <> 'DIRECTORSHIP') AS "diamonds",
            (SELECT COUNT(DISTINCT gt."entityId") FROM group_investments gi
             JOIN group_tiers gt ON gt."id" = gi."tierId"
             WHERE gi."investorUserId" = \$1 AND gi."status"::text = 'ACTIVE'
               AND gt."type"::text = 'DIRECTORSHIP') AS "crowns"
        ''', [uid]),
      ]);

      return {
        'investments': r[0].map((x) => <String, dynamic>{
          'kind': x['kind']?.toString() ?? 'PROJECT',
          'id': x['id'].toString(),
          'amount': _toDouble(x['amountBdt']),
          'status': x['status']?.toString() ?? '',
          'createdAt': x['createdAt']?.toString() ?? '',
          'category': x['category']?.toString() ?? '',
          'approved': _toDouble(x['approved']),
          'review': _toDouble(x['review']),
        }).toList(),
        'distributions': r[1].map((x) => <String, dynamic>{
          'at': x['distributedAt']?.toString() ?? '',
          'amount': _toDouble(x['netAmountBdt']),
        }).toList(),
        'groupRecent': r[2].map((x) => <String, dynamic>{
          'id': x['id'].toString(),
          'slug': x['slug']?.toString() ?? '',
          'groupName': x['groupName']?.toString() ?? '',
          'entityName': x['entityName']?.toString() ?? '',
          'tierName': x['tierName']?.toString() ?? '',
          'amount': _toDouble(x['amountBdt']),
          'status': x['status']?.toString() ?? '',
          'createdAt': x['createdAt']?.toString() ?? '',
        }).toList(),
        'updates': r[3].map((x) => <String, dynamic>{
          'id': x['id'].toString(),
          'title': x['title']?.toString() ?? '',
          'type': x['type']?.toString() ?? '',
          'at': x['at']?.toString() ?? '',
          'projectId': x['projectId']?.toString() ?? '',
          'projectTitle': x['projectTitle']?.toString() ?? '',
        }).toList(),
        'documents': r[4].map((x) => <String, dynamic>{
          'id': x['id'].toString(),
          'title': x['title']?.toString() ?? '',
          'amount': _toDouble(x['amountBdt']),
          'receiptNumber': x['receiptNumber']?.toString() ?? '',
          'deedNumber': x['deedNumber']?.toString() ?? '',
        }).toList(),
        'prestige': r[5].isEmpty
            ? null
            : <String, dynamic>{
          'stars': _toInt(r[5].first['stars']),
          'diamonds': _toInt(r[5].first['diamonds']),
          'crowns': _toInt(r[5].first['crowns']),
        },
        'ok': true,
      };
    } catch (e) {
      debugPrint('Get Dashboard Extras Error: $e');
      return {};
    }
  }

  // ═════════════════════════════════════════════════════════
  // NOTIFICATIONS
  // ═════════════════════════════════════════════════════════
  /// Shesh request ta server e pouchate pareni kina (khali list mane
  /// "kichu nei" naki "net nei" — sheta alada korar jonno)
  // ═════════════════════════════════════════════════════════
  // HELP CENTER — website er support_tickets / support_ticket_messages
  // Investor shudhu nijer ticket dekhe; internal note kokhono dekhe na.
  // Ticket kokhono financial record bodlay na.
  // ═════════════════════════════════════════════════════════

  /// Website er reference: HC-YYMMDD-XXXXXX (Dhaka er tarikh)
  static String _ticketReference() {
    final d = DateTime.now().toUtc().add(const Duration(hours: 6));
    String two(int v) => v.toString().padLeft(2, '0');
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final rnd = Random.secure();
    final tail = List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
    return 'HC-${two(d.year % 100)}${two(d.month)}${two(d.day)}-$tail';
  }

  /// Website er lib/support/tickets.ts
  static const List<String> profitIssueCategories = [
    'PROFIT_CALCULATION_DISCREPANCY',
    'INCORRECT_PROFIT_AMOUNT',
    'INCORRECT_CALCULATION_DATE',
    'MISSING_PROFIT_RECORD',
    'PAYMENT_STATUS_ISSUE',
    'MISSING_PROFIT_DISTRIBUTION',
    'OTHER_PROFIT_ISSUE',
  ];
  static const List<String> ticketCategories = [...profitIssueCategories, 'GENERAL'];
  static String get _profitCategorySql => profitIssueCategories.map((c) => "'$c'").join(', ');

  static Map<String, dynamic> _jsonMap(dynamic v) {
    if (v == null) return {};
    if (v is Map) return Map<String, dynamic>.from(v);
    try {
      final d = jsonDecode(v.toString());
      return d is Map ? Map<String, dynamic>.from(d) : {};
    } catch (_) {
      return {};
    }
  }

  /// Website er "My requests": status filter + page (20 ta kore).
  /// Protita ticket er shathe support er shesh reply (internal na).
  /// Server e pouchate na parle 'ok': false.
  static Future<Map<String, dynamic>> getInvestorTickets(String userId,
      {String? status, int page = 1, int pageSize = 20, bool profitOnly = false}) async {
    if (userId.isEmpty) return {'ok': false, 'items': <Map<String, dynamic>>[], 'total': 0, 'totalPages': 1};
    final p = page < 1 ? 1 : page;
    final params = <dynamic>[userId, pageSize, (p - 1) * pageSize];
    var where = 't."userId" = \$1';
    // Profit Returns page: website er motoi shudhu PROFIT_ISSUE_CATEGORIES
    if (profitOnly) where += ' AND t."category" IN ($_profitCategorySql)';
    if (status != null && status.isNotEmpty) {
      params.add(status);
      where += ' AND t."status" = \$4';
    }

    final rows = await queryNeonHttp('''
      SELECT t."id", t."reference", t."category", t."subject", t."status", t."channel",
             t."context", t."createdAt", t."lastActivityAt",
             (SELECT m."body" FROM support_ticket_messages m
               WHERE m."ticketId" = t."id" AND m."authorRole" = 'STAFF' AND m."internal" = false
               ORDER BY m."createdAt" DESC LIMIT 1) AS "latestReply",
             COUNT(*) OVER() AS "total"
      FROM support_tickets t
      WHERE $where
      ORDER BY t."lastActivityAt" DESC
      LIMIT \$2 OFFSET \$3
    ''', params);

    final failed = rows.isEmpty && lastRequestFailed;
    var total = rows.isEmpty ? 0 : _toInt(rows.first['total']);
    // Page er baire hole (jemon shesh page muche gele) total alada kore jani
    if (rows.isEmpty && !failed && p > 1) {
      final hasStatus = status != null && status.isNotEmpty;
      final c = await queryNeonHttp(
          'SELECT COUNT(*) AS n FROM support_tickets t WHERE t."userId" = \$1${profitOnly ? ' AND t."category" IN ($_profitCategorySql)' : ''}${hasStatus ? ' AND t."status" = \$2' : ''}',
          hasStatus ? [userId, status] : [userId]);
      total = c.isEmpty ? 0 : _toInt(c.first['n']);
    }
    return {
      'ok': !failed,
      'items': rows
          .map((r) => {
        'id': r['id']?.toString() ?? '',
        'reference': r['reference']?.toString() ?? '',
        'category': r['category']?.toString() ?? '',
        'subject': r['subject']?.toString() ?? '',
        'status': r['status']?.toString() ?? '',
        'channel': r['channel']?.toString() ?? 'WEB',
        'context': _jsonMap(r['context']),
        'createdAt': r['createdAt']?.toString(),
        'lastActivityAt': r['lastActivityAt']?.toString(),
        'latestReply': r['latestReply']?.toString(),
      })
          .toList(),
      'total': total,
      'totalPages': total <= 0 ? 1 : ((total + pageSize - 1) ~/ pageSize),
    };
  }

  /// Ekta ticket — shudhu oi investor er nijer. Na pele / onner hole null.
  /// Internal note bad; attachment er link website er protected route.
  static Future<Map<String, dynamic>?> getInvestorTicket(String userId, String ticketId) async {
    if (userId.isEmpty || !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(ticketId)) return null;
    final results = await Future.wait([
      queryNeonHttp('''
        SELECT "id", "reference", "category", "subject", "status", "channel", "context",
               "expectedAmountBdt", "profitRecordId", "resolution", "createdAt", "lastActivityAt"
        FROM support_tickets
        WHERE "id" = \$1 AND "userId" = \$2
        LIMIT 1
      ''', [ticketId, userId]),
      queryNeonHttp('''
        SELECT m."id", m."authorRole", m."body", m."attachmentUrl", m."attachmentName", m."createdAt"
        FROM support_ticket_messages m
        JOIN support_tickets t ON t."id" = m."ticketId"
        WHERE m."ticketId" = \$1 AND t."userId" = \$2 AND m."internal" = false
        ORDER BY m."createdAt" ASC
      ''', [ticketId, userId]),
    ]);
    if (results[0].isEmpty) return lastRequestFailed ? {'error': 'network'} : null;
    final t = results[0].first;
    return {
      'id': t['id']?.toString() ?? '',
      'reference': t['reference']?.toString() ?? '',
      'category': t['category']?.toString() ?? '',
      'subject': t['subject']?.toString() ?? '',
      'status': t['status']?.toString() ?? '',
      'channel': t['channel']?.toString() ?? 'WEB',
      'context': _jsonMap(t['context']),
      'expectedAmountBdt': t['expectedAmountBdt'] == null ? null : _toDouble(t['expectedAmountBdt']),
      'profitRecordId': t['profitRecordId']?.toString(),
      'resolution': t['resolution']?.toString(),
      'createdAt': t['createdAt']?.toString(),
      'lastActivityAt': t['lastActivityAt']?.toString(),
      'messages': results[1]
          .map((m) => {
        'id': m['id']?.toString() ?? '',
        'authorRole': m['authorRole']?.toString() ?? '',
        'body': m['body']?.toString() ?? '',
        'hasAttachment': (m['attachmentUrl']?.toString() ?? '').isNotEmpty,
        'attachmentName': m['attachmentName']?.toString(),
        // Website er protected route — website e login thakle khule
        'attachmentPath': '$websiteBaseUrl/api/payment-proofs/ticket/${m['id']}',
        'createdAt': m['createdAt']?.toString(),
      })
          .toList(),
    };
  }

  /// Ticket e jog korar jonno user er nijer project investment gulo
  static Future<List<Map<String, dynamic>>> getTicketInvestmentOptions(String userId) async {
    if (userId.isEmpty) return [];
    final rows = await queryNeonHttp('''
      SELECT i."id", i."receiptNumber", i."projectId", p."title"
      FROM investments i
      JOIN investor_profiles ip ON ip."id" = i."investorProfileId"
      JOIN projects p ON p."id" = i."projectId"
      WHERE ip."userId" = \$1
      ORDER BY i."createdAt" DESC
      LIMIT 50
    ''', [userId]);
    return rows
        .map((r) => {
      'investmentId': r['id']?.toString() ?? '',
      'projectId': r['projectId']?.toString() ?? '',
      'projectTitle': r['title']?.toString() ?? '',
      'receiptNumber': r['receiptNumber']?.toString(),
    })
        .toList();
  }

  /// Notun request: ticket + prothom message (investor er lekha) ek SQL e.
  /// Investment dile shudhu user er nijer hole-i jog hoy.
  static Future<Map<String, dynamic>> createSupportTicket({
    required String userId,
    required String category,
    required String subject,
    required String body,
    String? investmentId,
    double? expectedAmountBdt,
    String? profitRecordId,
    String? distributionLineId,
  }) async {
    final s = subject.trim();
    final b = body.trim();
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    if (s.length < 3) return {'success': false, 'message': 'Please write a short subject.'};
    if (b.length < 10) return {'success': false, 'message': 'Please describe the issue in a little more detail.'};
    if (s.length > 200 || b.length > 5000) return {'success': false, 'message': 'The text is too long.'};
    if (!ticketCategories.contains(category)) return {'success': false, 'message': 'Please choose what the request is about.'};

    // Investment er context (website er motoi projectTitle + receiptNumber)
    String? projectId;
    String? invId;
    final context = <String, dynamic>{};
    if (investmentId != null && investmentId.isNotEmpty) {
      final opts = await getTicketInvestmentOptions(userId);
      final m = opts.where((o) => o['investmentId'] == investmentId).toList();
      if (m.isNotEmpty) {
        invId = investmentId;
        projectId = m.first['projectId'] as String;
        context['projectTitle'] = m.first['projectTitle'];
        if (m.first['receiptNumber'] != null) context['receiptNumber'] = m.first['receiptNumber'];
      }
    }

    // Profit record (accrual) — shudhu nijer hole; tar tottho context e
    // (website er motoi: period, calculated, paid, status — jemon dekhechilen)
    String? recordId;
    if (profitRecordId != null && profitRecordId.isNotEmpty) {
      final rec = await getInvestorProfitRecord(userId, profitRecordId);
      if (rec != null && rec['error'] == null) {
        final r = rec['record'] as Map<String, dynamic>;
        recordId = profitRecordId;
        invId ??= r['investmentId'] as String?;
        projectId ??= r['projectId'] as String?;
        context['projectTitle'] = r['projectTitle'];
        if (r['receiptNumber'] != null) context['receiptNumber'] = r['receiptNumber'];
        context['periodStart'] = r['periodStart'];
        context['periodEnd'] = r['periodEnd'];
        context['calculatedBdt'] = r['calculatedBdt'];
        context['paidBdt'] = r['paidBdt'];
        context['status'] = r['status'];
      }
    }
    // Payout line — shudhu nijer hole
    String? lineId;
    if (distributionLineId != null && distributionLineId.isNotEmpty) {
      final l = await queryNeonHttp('''
        SELECT li."id", p."id" AS "projectId", p."title"
        FROM distribution_line_items li
        JOIN distribution_batches b ON b."id" = li."batchId"
        JOIN projects p ON p."id" = b."projectId"
        WHERE li."id" = \$1 AND li."investorUserId" = \$2
        LIMIT 1
      ''', [distributionLineId, userId]);
      if (l.isNotEmpty) {
        lineId = distributionLineId;
        projectId ??= l.first['projectId']?.toString();
        context['projectTitle'] ??= l.first['title']?.toString();
      }
    }

    final now = _nowIso();
    for (int attempt = 0; attempt < 3; attempt++) {
      final ticketId = _generateUuid();
      final reference = _ticketReference();
      final rows = await queryNeonHttp('''
        WITH t AS (
          INSERT INTO support_tickets
            ("id", "reference", "userId", "category", "subject", "status", "channel",
             "projectId", "investmentId", "profitRecordId", "distributionLineId", "context",
             "expectedAmountBdt", "createdBy", "lastActivityAt", "createdAt", "updatedAt")
          VALUES (\$1, \$2, \$3, \$4, \$5, 'OPEN', 'WEB', \$6, \$7, \$13, \$14, \$8::jsonb,
                  \$9, \$3, \$10, \$10, \$10)
          ON CONFLICT ("reference") DO NOTHING
          RETURNING "id"
        )
        INSERT INTO support_ticket_messages ("id", "ticketId", "authorId", "authorRole", "body", "internal", "createdAt")
        SELECT \$11, t."id", \$3, 'INVESTOR', \$12, false, \$10 FROM t
        RETURNING "ticketId"
      ''', [
        ticketId,
        reference,
        userId,
        category,
        s,
        projectId,
        invId,
        context.isEmpty ? null : jsonEncode(context),
        expectedAmountBdt == null ? null : expectedAmountBdt.toStringAsFixed(2),
        now,
        _generateUuid(),
        b,
        recordId,
        lineId,
      ]);
      if (rows.isNotEmpty) {
        return {'success': true, 'ticketId': ticketId, 'reference': reference};
      }
      if (lastRequestFailed) {
        return {'success': false, 'message': 'Could not reach the server. Please check your internet and try again.'};
      }
      // Reference mile gele (khub kom) notun reference diye abar
    }
    return {'success': false, 'message': 'Could not create the request. Please try again.'};
  }

  /// Investor er reply. CLOSED ticket e reply hoy na. Website er
  /// statusAfterInvestorReply: WAITING_FOR_INVESTOR ba RESOLVED → IN_REVIEW.
  static Future<Map<String, dynamic>> replySupportTicket({
    required String userId,
    required String ticketId,
    required String body,
  }) async {
    final b = body.trim();
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    if (b.length < 2) return {'success': false, 'message': 'Please write your reply.'};
    if (b.length > 5000) return {'success': false, 'message': 'The reply is too long.'};

    final now = _nowIso();
    final rows = await queryNeonHttp('''
      WITH t AS (
        UPDATE support_tickets
        SET "lastActivityAt" = \$4, "updatedAt" = \$4,
            "status" = CASE WHEN "status" IN ('WAITING_FOR_INVESTOR', 'RESOLVED') THEN 'IN_REVIEW' ELSE "status" END
        WHERE "id" = \$1 AND "userId" = \$2 AND "status" <> 'CLOSED'
        RETURNING "id"
      )
      INSERT INTO support_ticket_messages ("id", "ticketId", "authorId", "authorRole", "body", "internal", "createdAt")
      SELECT \$3, t."id", \$2, 'INVESTOR', \$5, false, \$4 FROM t
      RETURNING "id"
    ''', [ticketId, userId, _generateUuid(), now, b]);

    if (rows.isNotEmpty) return {'success': true};
    if (lastRequestFailed) {
      return {'success': false, 'message': 'Could not reach the server. Please check your internet and try again.'};
    }
    return {'success': false, 'message': 'This request is closed. Please open a new request.'};
  }

  // ═════════════════════════════════════════════════════════
  // PROFIT RETURNS — website er profit-returns.data.ts + profit-returns.ts
  // + payout-status.ts er hubohu app version (shudhu nijer row).
  //  • record = ekta accrual: fixed-rate er mash (top-up shoho), profit-share
  //    er period, ba cholti mash (ACCRUING, ekhono payable na)
  //  • taka shob paisa (int) te hishab, website er motoi
  //  • kichu recalculate / save hoy na — shudhu DB er row jog kora
  // ═════════════════════════════════════════════════════════

  /// Website er EARNING_STATUSES (profit hoy emon investment)
  static const List<String> _earningStatuses = ['ACTIVE', 'MATURED', 'COMPLETED'];

  static int _paisa(dynamic v) => (_toDouble(v) * 100).round();
  static double _taka(int p) => p / 100.0;

  /// @db.Date column → "YYYY-MM-DD"
  static String _dbDay(dynamic v) {
    final s = v?.toString() ?? '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  /// Timestamp → Bangladesh er din "YYYY-MM-DD" (website er dhakaDay)
  static String _dhakaDayOf(dynamic v) {
    final raw = v?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    var t = raw.replaceFirst(' ', 'T');
    if (!RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(t) && t.contains('T')) t = '${t}Z';
    final d = DateTime.tryParse(t);
    if (d == null) return _dbDay(raw);
    return d.toUtc().add(const Duration(hours: 6)).toIso8601String().substring(0, 10);
  }

  static DateTime _dayUtc(String day) =>
      DateTime.utc(int.parse(day.substring(0, 4)), int.parse(day.substring(5, 7)), int.parse(day.substring(8, 10)));
  static String _dayStr(DateTime d) => d.toIso8601String().substring(0, 10);
  static String _addDays(String day, int n) => _dayStr(_dayUtc(day).add(Duration(days: n)));
  static int _daysInMonthOf(String day) => DateTime.utc(_dayUtc(day).year, _dayUtc(day).month + 1, 0).day;
  static String _monthStartOf(String day) => '${day.substring(0, 8)}01';
  static String _monthEndOf(String day) => '${day.substring(0, 8)}${_daysInMonthOf(day).toString().padLeft(2, '0')}';
  static int _daysBetween(String a, String b) => _dayUtc(b).difference(_dayUtc(a)).inDays + 1;

  /// Fixed-rate mash payable hoy mash shesher porer din
  static String _monthMaturesOn(String periodEnd) => _addDays(_monthEndOf(periodEnd), 1);

  /// MONTHLY_ACTUAL_DAYS_V1: annual × din ÷ (12 × mash er din), paisa te round
  static int _periodProfitPaisa(int annualPaisa, int days, int dim) {
    final den = 12 * dim;
    return (annualPaisa * days * 2 + den) ~/ (2 * den);
  }

  /// Website er recordStatus
  static String _recordStatusOf({
    required bool running,
    required int calc,
    required int paid,
    required int reserved,
    required bool processing,
  }) {
    if (running) return 'ACCRUING';
    if (calc > 0 && paid >= calc) return 'PAID';
    if (reserved > 0) return processing ? 'AWAITING_PAYMENT' : 'IN_APPROVAL';
    if (paid > 0) return 'PARTLY_PAID';
    return 'MATURED';
  }

  /// Website er payoutStatus — finance nishchit korle-i "PAID"
  static String payoutStatusKey(String lineStatus, String batchStatus) {
    if (lineStatus == 'PAID' || lineStatus == 'POSTED') return 'PAID';
    if (lineStatus == 'FAILED') return 'FAILED';
    if (lineStatus == 'REVERSED') return 'REVERSED';
    if (batchStatus == 'PROCESSING') return 'AWAITING_PAYMENT';
    return 'IN_APPROVAL';
  }

  /// Investor er profit terms (je investment e profit hoy)
  static Future<List<Map<String, dynamic>>> _loadProfitTerms(String userId) => queryNeonHttp('''
        SELECT t."investmentId", t."projectId", t."principalBdt", t."annualRatePct", t."rateMaxPct",
               t."annualProfitBdt", t."policy", t."effectiveDate", t."maturityDate",
               i."status"::text AS "invStatus", i."receiptNumber", i."maturedAt",
               p."title" AS "projectTitle", p."returnType"::text AS "returnType"
        FROM investment_profit_terms t
        JOIN investments i ON i."id" = t."investmentId"
        JOIN projects p ON p."id" = i."projectId"
        WHERE t."investorUserId" = \$1
          AND i."status"::text IN ('ACTIVE', 'MATURED', 'COMPLETED')
        ORDER BY t."effectiveDate" ASC
      ''', [userId]);

  /// Shesh je din profit hoy: contract maturity / investment matured — je ta age
  static String? _lastEarningDay(Map<String, dynamic> t) {
    final days = <String>[
      if (t['maturityDate'] != null) _dbDay(t['maturityDate']),
      if (t['maturedAt'] != null) _dhakaDayOf(t['maturedAt']),
    ]..sort();
    return days.isEmpty ? null : days.first;
  }

  /// Website er getInvestorProfitRecords: shob record (notun period age),
  /// summary card ar ei mash er anuman.
  /// Note: website page khulle accrual "sync" kore; app shudhu DB te ja ache
  /// tai pore — tai shesh hoye jawa mash website sync na kora porjonto ashe na.
  static Future<Map<String, dynamic>> getInvestorProfitRecords(String userId, {DateTime? now}) async {
    if (userId.isEmpty) return {'ok': false};
    final results = await Future.wait([
      _loadProfitTerms(userId),
      queryNeonHttp('''
        SELECT a."id", a."investmentId", a."month", a."kind", a."periodStart", a."periodEnd",
               a."eligibleDays", a."daysInMonth", a."annualRatePct", a."amountBdt", a."createdAt",
               al."amountBdt" AS "alAmount", al."status" AS "alStatus",
               li."id" AS "lineId", li."status"::text AS "lineStatus", li."paidAt", li."postedAt",
               li."paymentMethod", li."paymentReference", (li."paymentProofUrl" IS NOT NULL) AS "hasProof",
               b."status"::text AS "batchStatus"
        FROM profit_accruals a
        LEFT JOIN profit_allocations al ON al."accrualId" = a."id" AND al."status" IN ('RESERVED', 'PAID')
        LEFT JOIN distribution_line_items li ON li."id" = al."lineItemId"
        LEFT JOIN distribution_batches b ON b."id" = li."batchId"
        WHERE a."investorUserId" = \$1 AND a."status" = 'ACCRUED'
        ORDER BY a."month" ASC, a."kind" ASC
      ''', [userId]),
    ]);
    final terms = results[0];
    final rows = results[1];
    if (terms.isEmpty) {
      return {
        'ok': !lastRequestFailed,
        'records': <Map<String, dynamic>>[],
        'summary': _summarize([], 0),
        'upcoming': <Map<String, dynamic>>[],
      };
    }
    final termsBy = {for (final t in terms) t['investmentId'].toString(): t};

    // Accrual + tar allocation gulo ek jaygay
    final accruals = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final id = r['id'].toString();
      if (!termsBy.containsKey(r['investmentId']?.toString())) continue;
      final a = accruals.putIfAbsent(id, () => {...r, 'allocs': <Map<String, dynamic>>[]});
      if (r['lineId'] != null) (a['allocs'] as List).add(r);
    }

    final records = <String, Map<String, dynamic>>{};
    final baseByMonth = <String, String>{};

    Map<String, dynamic> newRecord(Map<String, dynamic> a, String kind) {
      final t = termsBy[a['investmentId'].toString()]!;
      final periodEnd = _dbDay(a['periodEnd']);
      return {
        'id': a['id'].toString(),
        'kind': kind,
        'investmentId': a['investmentId'].toString(),
        'receiptNumber': t['receiptNumber']?.toString(),
        'projectId': t['projectId']?.toString(),
        'projectTitle': t['projectTitle']?.toString() ?? '',
        'profitModel': t['returnType'] == 'PROFIT_SHARE' ? 'PROFIT_SHARE' : 'FIXED_RATE',
        'principalBdt': _toDouble(t['principalBdt']),
        'annualRatePct': _toDouble(t['annualRatePct']),
        'rateMaxPct': t['rateMaxPct'] == null ? null : _toDouble(t['rateMaxPct']),
        'periodStart': _dbDay(a['periodStart']),
        'periodEnd': periodEnd,
        'eligibleDays': _toInt(a['eligibleDays']),
        'daysInMonth': kind == 'MONTH' ? _toInt(a['daysInMonth']) : null,
        'maturesOn': kind == 'MONTH' ? _monthMaturesOn(periodEnd) : _dhakaDayOf(a['createdAt']),
        'payments': <Map<String, dynamic>>[],
        'accrualIds': <String>[],
        '_base': 0,
        '_topup': 0,
        '_calc': 0,
        '_paid': 0,
        '_reserved': 0,
        '_processing': false,
      };
    }

    // Base / period row age, jate top-up tar mash khuje pay
    final ordered = accruals.values.toList()
      ..sort((x, y) {
        final tx = x['kind'].toString().startsWith('TOPUP:') ? 1 : 0;
        final ty = y['kind'].toString().startsWith('TOPUP:') ? 1 : 0;
        return tx.compareTo(ty);
      });
    for (final a in ordered) {
      final kind = a['kind'].toString();
      final monthKey = '${a['investmentId']}|${_dbDay(a['month'])}';
      final amount = _paisa(a['amountBdt']);
      Map<String, dynamic> rec;
      if (kind.startsWith('TOPUP:')) {
        final baseId = baseByMonth[monthKey];
        if (baseId != null) {
          rec = records[baseId]!;
        } else {
          rec = newRecord(a, 'MONTH');
          records[rec['id']] = rec;
          baseByMonth[monthKey] = rec['id'];
        }
        rec['_topup'] = (rec['_topup'] as int) + amount;
      } else {
        rec = newRecord(a, kind.startsWith('PROJECT:') ? 'PERIOD' : 'MONTH');
        records[rec['id']] = rec;
        if (rec['kind'] == 'MONTH') baseByMonth[monthKey] = rec['id'];
        rec['_base'] = amount;
      }
      (rec['accrualIds'] as List<String>).add(a['id'].toString());
      rec['_calc'] = (rec['_calc'] as int) + amount;

      for (final al in (a['allocs'] as List).cast<Map<String, dynamic>>()) {
        final amt = _paisa(al['alAmount']);
        final paid = al['alStatus'] == 'PAID';
        if (paid) {
          rec['_paid'] = (rec['_paid'] as int) + amt;
        } else {
          rec['_reserved'] = (rec['_reserved'] as int) + amt;
          if (al['batchStatus'] == 'PROCESSING') rec['_processing'] = true;
        }
        final pays = rec['payments'] as List<Map<String, dynamic>>;
        final existing = pays.where((p) => p['lineId'] == al['lineId'].toString()).toList();
        if (existing.isNotEmpty) {
          existing.first['_amt'] = (existing.first['_amt'] as int) + amt;
          continue;
        }
        pays.add({
          'lineId': al['lineId'].toString(),
          '_amt': amt,
          'allocationStatus': al['alStatus'],
          'status': payoutStatusKey(al['lineStatus']?.toString() ?? '', al['batchStatus']?.toString() ?? ''),
          'paidAt': paid ? (al['paidAt'] ?? al['postedAt'])?.toString() : null,
          'paymentMethod': paid ? al['paymentMethod']?.toString() : null,
          'paymentReference': paid ? al['paymentReference']?.toString() : null,
          'hasReceipt': al['lineStatus'] == 'PAID',
          'hasProof': al['lineStatus'] == 'PAID' && al['hasProof'] == true,
        });
      }
    }

    // Cholti fixed-rate mash (gotokal porjonto) + ei mash er anuman
    final today = _dhakaDayOf((now ?? DateTime.now()).toUtc().toIso8601String());
    final through = _addDays(today, -1);
    final upcoming = <Map<String, dynamic>>[];
    var upcomingPaisa = 0;
    for (final t in terms) {
      if (t['returnType'] == 'PROFIT_SHARE') continue;
      final effective = _dbDay(t['effectiveDate']);
      if (effective.length < 10) continue;
      final earningStart = _addDays(effective, 1);
      final last = _lastEarningDay(t);
      final annual = _paisa(t['annualProfitBdt']);
      final invId = t['investmentId'].toString();

      // Gotokal je mash e, sheta shesh na hole — cholti record
      if (through.compareTo(_monthEndOf(through)) < 0) {
        final start = [_monthStartOf(through), earningStart]..sort();
        final ends = [through, if (last != null) last]..sort();
        final s = start.last, e = ends.first;
        if (s.compareTo(e) <= 0) {
          final dim = _daysInMonthOf(through);
          final days = _daysBetween(s, e);
          final amt = _periodProfitPaisa(annual, days, dim);
          if (amt > 0) {
            final id = 'current-$invId';
            records[id] = {
              'id': id,
              'kind': 'RUNNING',
              'investmentId': invId,
              'receiptNumber': t['receiptNumber']?.toString(),
              'projectId': t['projectId']?.toString(),
              'projectTitle': t['projectTitle']?.toString() ?? '',
              'profitModel': 'FIXED_RATE',
              'principalBdt': _toDouble(t['principalBdt']),
              'annualRatePct': _toDouble(t['annualRatePct']),
              'rateMaxPct': t['rateMaxPct'] == null ? null : _toDouble(t['rateMaxPct']),
              'periodStart': s,
              'periodEnd': e,
              'eligibleDays': days,
              'daysInMonth': dim,
              'maturesOn': _monthMaturesOn(e),
              'payments': <Map<String, dynamic>>[],
              'accrualIds': <String>[],
              '_base': amt,
              '_topup': 0,
              '_calc': amt,
              '_paid': 0,
              '_reserved': 0,
              '_processing': false,
            };
          }
        }
      }

      // Ei calendar mash er anuman — investment mash shesh porjonto ACTIVE thakle
      if (t['invStatus'] != 'ACTIVE') continue;
      final pStart = ([_monthStartOf(today), earningStart]..sort()).last;
      final pEnd = ([_monthEndOf(today), if (last != null) last]..sort()).first;
      if (pStart.compareTo(pEnd) > 0) continue;
      final est = _periodProfitPaisa(annual, _daysBetween(pStart, pEnd), _daysInMonthOf(today));
      if (est > 0) {
        upcomingPaisa += est;
        upcoming.add({
          'investmentId': invId,
          'projectTitle': t['projectTitle']?.toString() ?? '',
          'month': _monthStartOf(today),
          'estimateBdt': _taka(est),
          'maturesOn': _monthMaturesOn(pEnd),
        });
      }
    }

    final list = records.values.map((r) {
      final calc = r['_calc'] as int, paid = r['_paid'] as int, reserved = r['_reserved'] as int;
      r['status'] = _recordStatusOf(
          running: r['kind'] == 'RUNNING', calc: calc, paid: paid, reserved: reserved, processing: r['_processing'] as bool);
      r['baseBdt'] = _taka(r['_base'] as int);
      r['topupBdt'] = _taka(r['_topup'] as int);
      r['calculatedBdt'] = _taka(calc);
      r['paidBdt'] = _taka(paid);
      r['reservedBdt'] = _taka(reserved);
      r['outstandingBdt'] = _taka(calc - (paid < calc ? paid : calc));
      for (final p in r['payments'] as List<Map<String, dynamic>>) {
        p['amountBdt'] = _taka(p.remove('_amt') as int);
      }
      return r;
    }).toList();

    final summary = _summarize(list, upcomingPaisa);
    list.sort((a, b) {
      final c = (b['periodStart'] as String).compareTo(a['periodStart'] as String);
      return c != 0 ? c : (a['projectTitle'] as String).compareTo(b['projectTitle'] as String);
    });
    for (final r in list) {
      r.removeWhere((k, _) => k.startsWith('_'));
    }
    return {'ok': true, 'records': list, 'summary': summary, 'upcoming': upcoming};
  }

  /// Website er summarizeRecords — protita taka ek bar:
  /// earned = matured + accruing · matured = paid + pending ·
  /// pending = awaiting + being approved + not yet in a disbursement
  static Map<String, double> _summarize(List<Map<String, dynamic>> records, int upcomingPaisa) {
    var matured = 0, accruing = 0, paid = 0, awaiting = 0, inApproval = 0;
    for (final r in records) {
      final calc = r['_calc'] as int;
      if (r['kind'] == 'RUNNING') {
        accruing += calc;
        continue;
      }
      matured += calc;
      final rp = r['_paid'] as int;
      final p = rp < calc ? rp : calc;
      paid += p;
      final left = calc - p;
      final rr = r['_reserved'] as int;
      final held = rr < left ? rr : left;
      if (r['_processing'] == true) {
        awaiting += held;
      } else {
        inApproval += held;
      }
    }
    final pending = matured - paid;
    return {
      'earnedBdt': _taka(matured + accruing),
      'maturedBdt': _taka(matured),
      'accruingBdt': _taka(accruing),
      'paidBdt': _taka(paid),
      'pendingBdt': _taka(pending),
      'awaitingPaymentBdt': _taka(awaiting),
      'inApprovalBdt': _taka(inApproval),
      'notScheduledBdt': _taka(pending - awaiting - inApproval),
      'upcomingEstimateBdt': _taka(upcomingPaisa),
    };
  }

  /// Website er getInvestorProfitPayments: finance er payout line, notun age.
  /// Filter app e hoy (website er motoi shob ane, tarpor chhake).
  static Future<Map<String, dynamic>> getInvestorProfitPayments(String userId) async {
    if (userId.isEmpty) return {'ok': false, 'items': <Map<String, dynamic>>[]};
    final rows = await queryNeonHttp('''
      SELECT li."id", li."status"::text AS "status", li."netAmountBdt", li."paidAt", li."postedAt", li."createdAt",
             li."paymentMethod", li."paymentReference", (li."paymentProofUrl" IS NOT NULL) AS "hasProof",
             i."receiptNumber",
             b."status"::text AS "batchStatus", b."periodStart", b."periodEnd",
             p."id" AS "projectId", p."title" AS "projectTitle",
             (SELECT al."accrualId" FROM profit_allocations al
               JOIN profit_accruals pa ON pa."id" = al."accrualId"
               WHERE al."lineItemId" = li."id"
               ORDER BY (pa."kind" LIKE 'TOPUP:%') ASC, pa."month" ASC LIMIT 1) AS "recordId"
      FROM distribution_line_items li
      JOIN distribution_batches b ON b."id" = li."batchId"
      JOIN projects p ON p."id" = b."projectId"
      LEFT JOIN investments i ON i."id" = li."investmentId"
      WHERE li."investorUserId" = \$1
        AND li."status"::text IN ('PENDING', 'PAID', 'POSTED', 'FAILED', 'REVERSED')
        AND b."status"::text NOT IN ('DRAFT', 'CANCELLED', 'REJECTED')
      ORDER BY li."createdAt" DESC
    ''', [userId]);
    final failed = rows.isEmpty && lastRequestFailed;
    return {
      'ok': !failed,
      'items': rows.map((l) {
        final key = payoutStatusKey(l['status']?.toString() ?? '', l['batchStatus']?.toString() ?? '');
        final paid = key == 'PAID';
        return {
          'id': l['id'].toString(),
          'date': (paid ? (l['paidAt'] ?? l['postedAt'] ?? l['createdAt']) : l['createdAt'])?.toString(),
          'projectId': l['projectId']?.toString(),
          'projectTitle': l['projectTitle']?.toString() ?? '',
          'receiptNumber': l['receiptNumber']?.toString(),
          'periodStart': l['periodStart'] == null ? null : _dbDay(l['periodStart']),
          'periodEnd': l['periodEnd'] == null ? null : _dbDay(l['periodEnd']),
          'amountBdt': _toDouble(l['netAmountBdt']),
          'status': key,
          'paymentMethod': paid ? l['paymentMethod']?.toString() : null,
          'paymentReference': paid ? l['paymentReference']?.toString() : null,
          'hasReceipt': l['status'] == 'PAID',
          'hasProof': l['status'] == 'PAID' && l['hasProof'] == true,
          'recordId': l['recordId']?.toString(),
        };
      }).toList(),
    };
  }

  /// Ekta record + investment er tottho + hishaber bhag (website er getInvestorProfitRecord).
  /// Onner record hole null.
  static Future<Map<String, dynamic>?> getInvestorProfitRecord(String userId, String recordId) async {
    if (userId.isEmpty || recordId.isEmpty || recordId.length > 80) return null;
    final all = await getInvestorProfitRecords(userId);
    if (all['ok'] != true) return {'error': 'network'};
    final list = (all['records'] as List).cast<Map<String, dynamic>>();
    final record = list.where((r) => r['id'] == recordId).toList();
    if (record.isEmpty) return null;
    final r = record.first;
    final invId = r['investmentId'] as String;

    final res = await Future.wait([
      queryNeonHttp('''
        SELECT t."principalBdt", t."annualRatePct", t."annualProfitBdt", t."policy", t."effectiveDate", t."maturityDate",
               i."amountBdt", i."createdAt", i."activatedAt", i."maturedAt", i."paymentPlan"
        FROM investment_profit_terms t
        JOIN investments i ON i."id" = t."investmentId"
        JOIN investor_profiles ip ON ip."id" = i."investorProfileId"
        WHERE t."investmentId" = \$1 AND ip."userId" = \$2
        LIMIT 1
      ''', [invId, userId]),
      queryNeonHttp('''
        SELECT * FROM (
          SELECT mp."id", mp."amountBdt", mp."paymentMethod" AS "method", COALESCE(mp."reviewedAt", mp."createdAt") AS "approvedAt"
          FROM manual_payment_submissions mp WHERE mp."investmentId" = \$1 AND mp."status"::text = 'APPROVED'
          UNION ALL
          SELECT gp."id", gp."amountBdt", gp."provider" AS "method", gp."createdAt" AS "approvedAt"
          FROM gateway_payments gp WHERE gp."investmentId" = \$1 AND gp."status"::text = 'SUCCESS'
        ) x ORDER BY "approvedAt" ASC
      ''', [invId]),
      (r['accrualIds'] as List).isEmpty
          ? Future.value(<Map<String, dynamic>>[])
          : queryNeonHttp('''
              SELECT "id", "kind", "annualRatePct", "eligibleDays", "daysInMonth", "amountBdt"
              FROM profit_accruals
              WHERE "investorUserId" = \$1 AND "id" IN (${List.generate((r['accrualIds'] as List).length, (i) => '\$${i + 2}').join(', ')})
            ''', [userId, ...(r['accrualIds'] as List)]),
    ]);
    if (res[0].isEmpty) return lastRequestFailed ? {'error': 'network'} : null;
    final t = res[0].first;
    final principal = _paisa(t['principalBdt']);
    final agreed = _toDouble(t['annualRatePct']);
    final effective = _dbDay(t['effectiveDate']);

    final info = {
      'investedAt': t['createdAt']?.toString(),
      'activatedAt': t['activatedAt']?.toString(),
      'effectiveDate': effective,
      'earningFrom': effective.length == 10 ? _addDays(effective, 1) : '',
      'earningTo': _lastEarningDay({'maturityDate': t['maturityDate'], 'maturedAt': t['maturedAt']}),
      'contractMaturity': t['maturityDate'] == null ? null : _dbDay(t['maturityDate']),
      'paymentPlan': t['paymentPlan']?.toString() ?? 'FULL',
      'annualProfitBdt': _toDouble(t['annualProfitBdt']),
      'policy': t['policy']?.toString(),
      'installments': res[1]
          .map((p) => {
        'amountBdt': _toDouble(p['amountBdt']),
        'method': p['method']?.toString(),
        'approvedAt': p['approvedAt']?.toString(),
      })
          .toList(),
    };

    Map<String, dynamic> fixedBreakdown(String label, double ratePct, int annual, int dim, int days, int amount) {
      final den = 12 * dim;
      final exactRounded = (annual * days * 2 + den) ~/ (2 * den);
      return {
        'label': label,
        'ratePct': ratePct,
        'principalBdt': _taka(principal),
        'annualProfitBdt': _taka(annual),
        'monthlyProfit': annual / 12 / 100,
        'dailyProfit': annual / den / 100,
        'daysInMonth': dim,
        'eligibleDays': days,
        'fullMonth': days == dim,
        'exactPeriodProfit': annual * days / den / 100,
        'amountBdt': _taka(amount),
        'roundingPaisa': amount - exactRounded,
      };
    }

    final fixed = <Map<String, dynamic>>[];
    Map<String, dynamic>? period;
    if (r['kind'] != 'PERIOD') {
      final accs = res[2];
      final base = accs.where((a) => a['kind'] == 'BASE').toList();
      fixed.add(fixedBreakdown(
        'AGREED',
        agreed,
        _paisa(t['annualProfitBdt']),
        (r['daysInMonth'] as int?) ?? 30,
        r['eligibleDays'] as int,
        base.isNotEmpty ? _paisa(base.first['amountBdt']) : _paisa(r['baseBdt']),
      ));
      for (final a in accs.where((a) => a['kind'].toString().startsWith('TOPUP:'))) {
        final extra = ((_toDouble(a['annualRatePct']) - agreed) * 10000).round() / 10000;
        fixed.add({
          ...fixedBreakdown('TOPUP', extra, (principal * extra / 100).round(), _toInt(a['daysInMonth']),
              _toInt(a['eligibleDays']), _paisa(a['amountBdt'])),
          'toRatePct': _toDouble(a['annualRatePct']),
        });
      }
    } else {
      // Profit share: shobar capital × din er mot (shudhu mot — onno karo tottho na)
      final acc = res[2].isNotEmpty ? res[2].first : null;
      final kind = acc?['kind']?.toString() ?? '';
      final calcId = kind.startsWith('PROJECT:') ? kind.substring(8) : '';
      if (acc != null && calcId.isNotEmpty) {
        final c = await Future.wait([
          queryNeonHttp('''
            SELECT "periodStart", "periodEnd", "revenueBdt", "expensesBdt", "netProfitBdt",
                   "investorSharePct", "investorPoolBdt", "notes"
            FROM project_profit_calculations WHERE "id" = \$1 LIMIT 1
          ''', [calcId]),
          queryNeonHttp('''
            SELECT COUNT(*) AS "investors",
                   COALESCE(SUM(ROUND(t."principalBdt" * 100) * a."eligibleDays"), 0) AS "totalWeight"
            FROM profit_accruals a
            LEFT JOIN investment_profit_terms t ON t."investmentId" = a."investmentId"
            WHERE a."kind" = \$1 AND a."status" = 'ACCRUED'
          ''', [kind]),
        ]);
        if (c[0].isNotEmpty) {
          final calc = c[0].first;
          final totalWeight = _toDouble(c[1].isEmpty ? 0 : c[1].first['totalWeight']);
          final weight = principal * _toInt(acc['eligibleDays']);
          final pool = _paisa(calc['investorPoolBdt']);
          final share = totalWeight > 0 ? (pool * weight / totalWeight).floor() : 0;
          final amount = _paisa(acc['amountBdt']);
          period = {
            'periodStart': _dbDay(calc['periodStart']),
            'periodEnd': _dbDay(calc['periodEnd']),
            'revenueBdt': _toDouble(calc['revenueBdt']),
            'expensesBdt': _toDouble(calc['expensesBdt']),
            'netProfitBdt': _toDouble(calc['netProfitBdt']),
            'investorSharePct': _toDouble(calc['investorSharePct']),
            'poolBdt': _taka(pool),
            'principalBdt': _taka(principal),
            'activeDays': _toInt(acc['eligibleDays']),
            'sharePct': totalWeight > 0 ? (weight * 1000000 / totalWeight).floor() / 10000 : 0.0,
            'computedShareBdt': _taka(share),
            'amountBdt': _taka(amount),
            'calculated': amount - share >= 0 && amount - share <= 1,
            'notes': calc['notes']?.toString(),
            'investorCount': _toInt(c[1].isEmpty ? 0 : c[1].first['investors']),
          };
        }
      }
    }

    return {'record': r, 'info': info, 'fixed': fixed, 'period': period};
  }

  static bool get lastRequestFailed => _lastConnectionError != null;

  /// Notun theke purono. [limit] — ekbare koyta anbo.
  /// Fail hole khali list dey; tokhon [lastRequestFailed] true thake.
  static Future<List<Map<String, dynamic>>> getNotificationsData(String userId, {int limit = 100}) async {
    if (userId.isEmpty) return [];
    try {
      final res = await queryNeonHttp('''
        SELECT n."id", n."title", n."body", n."type"::text AS "type", n."isRead", n."createdAt", n."data"
        FROM notifications n
        WHERE n."userId" = \$1
        ORDER BY n."createdAt" DESC
        LIMIT \$2
      ''', [userId, limit]);

      return res.map((r) {
        // data kokhono Map, kokhono JSON string hishebe ashe
        Map<String, dynamic> data = {};
        final raw = r['data'];
        if (raw is Map) {
          data = Map<String, dynamic>.from(raw);
        } else if (raw is String && raw.isNotEmpty) {
          try {
            final d = jsonDecode(raw);
            if (d is Map) data = Map<String, dynamic>.from(d);
          } catch (_) {}
        }
        return <String, dynamic>{
          'id': r['id'].toString(),
          'title': r['title']?.toString() ?? '',
          'body': r['body']?.toString() ?? '',
          'type': r['type']?.toString() ?? 'SYSTEM',
          'isRead': (r['isRead'] as bool?) ?? false,
          'createdAt': r['createdAt']?.toString() ?? '',
          'data': data,
        };
      }).toList();
    } catch (e) {
      debugPrint("Get Notifications Error: $e");
      _lastConnectionError ??= e.toString();
      return [];
    }
  }

  /// [userId] dile shudhu oi user er notification-i update hoy
  static Future<void> markNotificationAsRead(String notificationId, {String? userId}) async {
    if (userId != null && userId.isNotEmpty) {
      await executeNeonHttp(
          'UPDATE notifications SET "isRead" = true WHERE "id" = \$1 AND "userId" = \$2',
          [notificationId, userId]);
    } else {
      await executeNeonHttp(
          'UPDATE notifications SET "isRead" = true WHERE "id" = \$1',
          [notificationId]);
    }
  }

  static Future<void> markAllNotificationsAsRead(String userId) async {
    if (userId.isEmpty) return;
    await executeNeonHttp(
        'UPDATE notifications SET "isRead" = true WHERE "userId" = \$1 AND "isRead" = false',
        [userId]);
  }

  // ═════════════════════════════════════════════════════════
  // DOCUMENTS
  // ═════════════════════════════════════════════════════════
  /// User nije je category te upload korte pare (website er DocumentCategory enum)
  static const Set<String> userUploadCategories = {
    'PAYMENT_RECEIPT',
    'INVESTMENT_AGREEMENT',
    'PROJECT_DOCUMENT',
  };

  static Future<Map<String, dynamic>> uploadUserDocument({
    required String userId,
    required String name,
    required String category,
    required String fileUrl,
    String? description,
    int? sizeBytes,
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    // Age ojana category chupchap "Payment Receipt" hoye jeto — ekhon sorasori mana
    if (!userUploadCategories.contains(category)) {
      return {'success': false, 'message': 'Please choose a valid document category.'};
    }
    try {
      final nowStr = _nowIso();
      final desc = (description == null || description.trim().isEmpty) ? null : description.trim();
      final res = await queryNeonHttp('''
        INSERT INTO documents (
          "id", "name", "category", "fileUrl", "sizeBytes", "description",
          "uploadedBy", "ownerUserId", "isPublic", "createdAt", "updatedAt"
        ) VALUES (
          \$1, \$2, \$3::"DocumentCategory", \$4, \$5, \$6, \$7, \$7, false, \$8, \$8
        )
        RETURNING "id"
      ''', [
        _generateUuid(),
        name,
        category,
        fileUrl,
        sizeBytes ?? 0,
        desc,
        userId,
        nowStr,
      ]);

      if (res.isNotEmpty) {
        return {'success': true, 'message': 'Document uploaded successfully!'};
      }
      return {'success': false, 'message': _connectionErrorMsg()};
    } catch (e) {
      return {'success': false, 'message': 'Database error: ${e.toString()}'};
    }
  }

  /// Nijer upload kora document soft-delete (website er motoi "deletedAt").
  /// Certificate ba admin er document kokhono na.
  static Future<Map<String, dynamic>> deleteUserDocument({
    required String userId,
    required String documentId,
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    try {
      final res = await queryNeonHttp('''
        UPDATE documents
        SET "deletedAt" = \$3, "updatedAt" = \$3
        WHERE "id" = \$1
          AND "uploadedBy" = \$2
          AND "deletedAt" IS NULL
          AND "category"::text <> 'INVESTMENT_RECEIPT'
        RETURNING "id"
      ''', [documentId, userId, _nowIso()]);

      if (res.isNotEmpty) return {'success': true};
      return {
        'success': false,
        'message': _lastConnectionError != null
            ? _connectionErrorMsg()
            : 'This document cannot be deleted.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Database error: ${e.toString()}'};
    }
  }

  static Map<String, List<Map<String, dynamic>>> _emptyDocs() => {
    'contracts': [],
    'kycDocs': [],
    'paymentReceipts': [],
    'investmentReceipts': [],
    'groupInvestmentReceipts': [],
    'distributionStatements': [],
    'harvestReports': [],
    'projectDocs': [],
  };

  // Fetch Categorized Documents & Contracts
  static Future<Map<String, List<Map<String, dynamic>>>> getDocumentsCategorized(String userId) async {
    if (userId.isEmpty) return _emptyDocs();

    try {
      await _ensureReceiptNumbersExist();

      final results = await Future.wait([
        // [0] age contract er query chilo — page e kothao dekhay na, tai bad
        Future.value(<Map<String, dynamic>>[]),
        // [1] age KYC chilo — KYC ar nei
        Future.value(<Map<String, dynamic>>[]),
        // Investment certificate gulo alada section e, tai ekhane bad.
        // Website soft-delete kora document o bad.
        queryNeonHttp('''
          SELECT d."id", d."name", d."category"::text AS "category", d."fileUrl", d."sizeBytes", d."createdAt",
                 d."description", (d."uploadedBy" = \$1) AS "mine"
          FROM documents d
          WHERE (d."uploadedBy" = \$1 OR d."ownerUserId" = \$1 OR d."isPublic" = true)
            AND d."deletedAt" IS NULL
            AND d."category"::text <> 'INVESTMENT_RECEIPT'
          ORDER BY d."createdAt" DESC
        ''', [userId]),
        // Certificate = shudhu website je certificate baniyeche (admin approve er por)
        getWebsiteCertificates(userId),
        getGroupWebsiteCertificates(userId),
      ]);

      final docs = _emptyDocs();

      for (final r in results[2]) {
        final cat = r['category']?.toString() ?? 'PROJECT_DOCUMENT';
        final item = {
          'id': r['id'].toString(),
          'name': r['name']?.toString() ?? 'Document',
          'category': cat,
          'fileUrl': r['fileUrl']?.toString() ?? '',
          'sizeBytes': _toInt(r['sizeBytes']),
          'createdAt': r['createdAt']?.toString() ?? '',
          'description': r['description']?.toString() ?? '',
          // Nijer upload kora hole tobei delete kora jabe
          'mine': r['mine'] == true || r['mine']?.toString() == 'true',
        };

        if (cat == 'INVESTMENT_AGREEMENT') {
          // Website approve er por je deed (dolil) PDF banay — "Agreement #<receipt>"
          docs['contracts']!.add(item);
        } else if (cat == 'PAYMENT_RECEIPT') {
          docs['paymentReceipts']!.add(item);
        } else if (cat == 'DISTRIBUTION_STATEMENT') {
          docs['distributionStatements']!.add(item);
        } else if (cat == 'HARVEST_REPORT') {
          docs['harvestReports']!.add(item);
        } else {
          docs['projectDocs']!.add(item);
        }
      }

      docs['investmentReceipts']!.addAll(results[3]);
      docs['groupInvestmentReceipts']!.addAll(results[4]);

      return docs;
    } catch (e) {
      debugPrint("Get Documents Categorized Error: $e");
      return _emptyDocs();
    }
  }

  // ═════════════════════════════════════════════════════════
  // PORTFOLIO (project investments)
  // Age protita investment er jonno 2 ta alada query hoto (N+1) —
  // ekhon shob mile 4 ta query parallel e.
  // ═════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> getPortfolioData(String userId, {String? email}) async {
    try {
      final activeUserId = await _resolveUserId(userId, email);
      if (activeUserId.isEmpty) return {};

      await _ensureReceiptNumbersExist();

      final results = await Future.wait([
        queryNeonHttp('''
          SELECT i."id", i."receiptNumber", pr."id" AS "projectId", pr."title",
                 pr."category"::text AS "category", pr."slug", pr."durationDays", pr."location",
                 i."amountBdt", i."expectedReturnBdt", i."actualReturnBdt",
                 i."status"::text AS "status", i."createdAt", i."activatedAt",
                 pr."fundedAmountBdt", pr."fundingGoalBdt", pr."expectedReturnPct",
                 pr."returnPctMin", pr."returnPctMax",
                 sub."id" AS "subId", sub."status" AS "subStatus", sub."transactionRef" AS "subRef",
                 sub."rejectionReason" AS "subReason", sub."createdAt" AS "subCreatedAt",
                 COALESCE(to_jsonb(i) ->> 'paymentPlan', 'FULL') AS "paymentPlan",
                 i."cancellationReason",
                 COALESCE((SELECT SUM(x."amountBdt") FROM manual_payment_submissions x
                           WHERE x."investmentId" = i."id" AND x."status"::text = 'APPROVED'), 0) AS "paidApproved",
                 COALESCE((SELECT SUM(x."amountBdt") FROM manual_payment_submissions x
                           WHERE x."investmentId" = i."id"
                             AND x."status"::text IN ('SUBMITTED', 'UNDER_REVIEW')), 0) AS "paidPending"
          FROM investments i
          JOIN investor_profiles p ON i."investorProfileId" = p."id"
          JOIN projects pr ON i."projectId" = pr."id"
          LEFT JOIN LATERAL (
            SELECT m."id", m."status"::text AS "status", m."transactionRef", m."rejectionReason", m."createdAt"
            FROM manual_payment_submissions m
            WHERE m."investmentId" = i."id"
            ORDER BY m."createdAt" DESC
            LIMIT 1
          ) sub ON i."status"::text IN ('PENDING', 'PAYMENT_PENDING')
          WHERE p."userId" = \$1
          ORDER BY i."createdAt" DESC
        ''', [activeUserId]),
        queryNeonHttp('''
          SELECT b."id", b."projectId", b."bankName", b."accountName", b."accountNumber", b."branchName",
                 b."routingNumber", b."swiftCode", b."mobileNumber", b."email", b."branchAddress"
          FROM project_bank_accounts b
          WHERE b."isActive" = true
            AND b."projectId" IN (
              SELECT i."projectId"
              FROM investments i
              JOIN investor_profiles p ON i."investorProfileId" = p."id"
              WHERE p."userId" = \$1
            )
          ORDER BY b."createdAt" ASC
        ''', [activeUserId]),
        queryNeonHttp('''
          SELECT "id", "bankName", "accountName", "accountNumber", "branchName", "mobileNumber"
          FROM bank_accounts
          WHERE "isActive" = true
          ORDER BY "displayOrder" ASC
        '''),
        getWebsiteCertificates(activeUserId),
      ]);

      final invRes = results[0];

      final Map<String, List<Map<String, dynamic>>> banksByProject = {};
      for (final b in results[1]) {
        final pid = b['projectId'].toString();
        banksByProject.putIfAbsent(pid, () => []).add(_mapProjectBank(b));
      }

      // Website kon kon investment er certificate baniyeche
      final websiteCerts = {
        for (final c in results[3]) c['investmentId'].toString(): c,
      };

      double totalInvested = 0.0;
      double totalExpected = 0.0;
      double totalActual = 0.0;
      final List<Map<String, dynamic>> investmentsList = [];

      for (final r in invRes) {
        final invId = r['id'].toString();
        final projectId = r['projectId'].toString();
        final status = r['status']?.toString() ?? 'PENDING';
        final amt = _toDouble(r['amountBdt']);
        final expRet = _toDouble(r['expectedReturnBdt']);
        final actRet = _toDoubleOrNull(r['actualReturnBdt']);

        if (status == 'ACTIVE' || status == 'MATURED' || status == 'COMPLETED') {
          totalInvested += amt;
          totalExpected += expRet;
        }
        if (actRet != null && actRet > 0) totalActual += actRet;

        final latestSubmission = r['subId'] == null
            ? null
            : <String, dynamic>{
          'id': r['subId'].toString(),
          'status': r['subStatus']?.toString() ?? 'SUBMITTED',
          'transactionRef': r['subRef']?.toString() ?? '',
          'rejectionReason': r['subReason']?.toString(),
          'createdAt': r['subCreatedAt']?.toString() ?? '',
        };

        investmentsList.add({
          'id': invId,
          'projectId': projectId,
          'title': r['title']?.toString() ?? 'Biniyog Project',
          'category': r['category']?.toString() ?? 'SME',
          'slug': r['slug']?.toString() ?? '',
          'durationDays': _toInt(r['durationDays'], 180),
          'location': r['location']?.toString() ?? 'Bangladesh',
          'amountBdt': amt,
          'expectedReturnBdt': expRet,
          'actualReturnBdt': actRet,
          'status': status,
          'createdAt': r['createdAt']?.toString() ?? '',
          'activatedAt': r['activatedAt']?.toString(),
          'fundedAmountBdt': _toDouble(r['fundedAmountBdt']),
          'fundingGoalBdt': _toDouble(r['fundingGoalBdt'], 1.0),
          ...projectReturnRange(r),
          'expectedReturnPct': projectReturnRange(r)['returnMax'],
          'latestSubmission': latestSubmission,
          // Website er motoi payment er hishab (kisti / ekadhik part)
          'paymentPlan': (r['paymentPlan']?.toString() ?? 'FULL').toUpperCase(),
          'paidApproved': _toDouble(r['paidApproved']),
          'paidPending': _toDouble(r['paidPending']),
          'cancellationReason': r['cancellationReason']?.toString(),
          'bankAccounts': banksByProject[projectId] ?? <Map<String, dynamic>>[],
          'receiptNumber': r['receiptNumber']?.toString(),
          // Website er certificate data (na thakle null = ekhono toiri hoyni)
          'websiteCertificate': websiteCerts[invId],
        });
      }

      final bankAccounts = results[2].map((r) {
        return {
          'id': r['id'].toString(),
          'bankName': r['bankName']?.toString() ?? '',
          'accountName': r['accountName']?.toString() ?? '',
          'accountNumber': r['accountNumber']?.toString() ?? '',
          'branchName': r['branchName']?.toString() ?? '',
          'mobileNumber': r['mobileNumber']?.toString() ?? '',
        };
      }).toList();

      return {
        'totalInvested': totalInvested,
        'totalExpected': totalExpected,
        'totalActual': totalActual,
        'investments': investmentsList,
        'bankAccounts': bankAccounts,
      };
    } catch (e) {
      debugPrint("Get Portfolio Data Error: $e");
      return {};
    }
  }

  // ═════════════════════════════════════════════════════════
  // TRANSACTIONS
  // ═════════════════════════════════════════════════════════
  static Future<List<Map<String, dynamic>>> getTransactionsData(String userId) async {
    if (userId.isEmpty) return [];
    try {
      final results = await Future.wait([
        queryNeonHttp('''
          SELECT p."id", p."amountBdt", p."feeBdt", p."netAmountBdt", p."direction"::text AS "direction",
                 p."method"::text AS "method", p."status"::text AS "status", p."description", p."createdAt"
          FROM payments p
          JOIN wallets w ON p."walletId" = w."id"
          WHERE w."userId" = \$1
          ORDER BY p."createdAt" DESC
        ''', [userId]),
        queryNeonHttp('''
          SELECT w."id", w."amountBdt", w."feeBdt", w."netAmountBdt", w."method"::text AS "method",
                 w."status"::text AS "status", w."bankName", w."requestedAt"
          FROM withdrawals w
          JOIN wallets wa ON w."walletId" = wa."id"
          WHERE wa."userId" = \$1
          ORDER BY w."requestedAt" DESC
        ''', [userId]),
      ]);

      final List<Map<String, dynamic>> list = results[0].map((r) {
        return <String, dynamic>{
          'id': r['id'].toString(),
          'amountBdt': _toDouble(r['amountBdt']),
          'feeBdt': _toDouble(r['feeBdt']),
          'netAmountBdt': _toDouble(r['netAmountBdt']),
          'direction': r['direction']?.toString() ?? 'INBOUND',
          'method': r['method']?.toString() ?? 'BANK_TRANSFER',
          'status': r['status']?.toString() ?? 'COMPLETED',
          'description': r['description']?.toString() ?? 'Wallet Transaction',
          'createdAt': r['createdAt']?.toString() ?? '',
        };
      }).toList();

      for (final r in results[1]) {
        list.add({
          'id': r['id'].toString(),
          'amountBdt': _toDouble(r['amountBdt']),
          'feeBdt': _toDouble(r['feeBdt']),
          'netAmountBdt': _toDouble(r['netAmountBdt']),
          'direction': 'OUTBOUND',
          'method': r['method']?.toString() ?? 'BANK_TRANSFER',
          'status': r['status']?.toString() ?? 'PENDING',
          'description': 'Withdrawal to ${r['bankName']?.toString() ?? 'Bank'}',
          'createdAt': r['requestedAt']?.toString() ?? '',
        });
      }

      list.sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));
      return list;
    } catch (e) {
      debugPrint("Get Transactions Data Error: $e");
      return [];
    }
  }

  // ═════════════════════════════════════════════════════════
  // REPORTS — ek query te shob (project, group, payment, wallet, distribution)
  // Ek round-trip, tai "fail hoyeche kina" bhul hoy na.
  // Return: {'ok': bool, 'projects', 'groups', 'transactions', 'distributions'}
  // ═════════════════════════════════════════════════════════
  static List<Map<String, dynamic>> _jsonList(dynamic v) {
    dynamic x = v;
    if (x is String) {
      try {
        x = jsonDecode(x);
      } catch (_) {
        return [];
      }
    }
    if (x is! List) return [];
    return x.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Prothom je key te value ache sheta (column er naam schema bhede alada hote pare)
  static dynamic _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().isNotEmpty) return v;
    }
    return null;
  }

  static Future<Map<String, dynamic>> getReportsData(String userId) async {
    if (userId.isEmpty) return {'ok': false, 'message': _loginRequiredMsg};

    try {
      final res = await queryNeonHttp('''
        SELECT
          (SELECT COALESCE(json_agg(t ORDER BY t."createdAt" DESC), '[]'::json) FROM (
             SELECT i."id", pr."title", pr."category"::text AS "category",
                    pr."expectedReturnPct", pr."returnPctMin", pr."returnPctMax",
                    i."amountBdt", i."actualReturnBdt", i."status"::text AS "status",
                    i."createdAt", i."activatedAt"
             FROM investments i
             JOIN investor_profiles p ON i."investorProfileId" = p."id"
             JOIN projects pr ON i."projectId" = pr."id"
             WHERE p."userId" = \$1
          ) t) AS "projects",

          (SELECT COALESCE(json_agg(t ORDER BY t."createdAt" DESC), '[]'::json) FROM (
             SELECT gi."id", bg."name" AS "groupName", ge."name" AS "entityName",
                    gt."name" AS "tierName", gt."expectedReturnPct",
                    gi."amountBdt", gi."status"::text AS "status", gi."createdAt"
             FROM group_investments gi
             JOIN group_tiers gt     ON gi."tierId" = gt."id"
             JOIN group_entities ge  ON gt."entityId" = ge."id"
             JOIN business_groups bg ON ge."groupId" = bg."id"
             WHERE gi."investorUserId" = \$1
          ) t) AS "groups",

          (SELECT COALESCE(json_agg(t), '[]'::json) FROM (
             SELECT m."id", m."amountBdt", m."status"::text AS "status", m."transactionRef",
                    m."rejectionReason", m."createdAt", pr."title"
             FROM manual_payment_submissions m
             JOIN investments i ON m."investmentId" = i."id"
             JOIN investor_profiles p ON i."investorProfileId" = p."id"
             JOIN projects pr ON i."projectId" = pr."id"
             WHERE p."userId" = \$1
          ) t) AS "projectPayments",

          (SELECT COALESCE(json_agg(t), '[]'::json) FROM (
             SELECT x."id", x."amountBdt", x."status"::text AS "status", x."transactionRef",
                    x."createdAt", bg."name" AS "title"
             FROM group_investment_payments x
             JOIN group_investments gi ON x."groupInvestmentId" = gi."id"
             JOIN group_tiers gt     ON gi."tierId" = gt."id"
             JOIN group_entities ge  ON gt."entityId" = ge."id"
             JOIN business_groups bg ON ge."groupId" = bg."id"
             WHERE gi."investorUserId" = \$1
          ) t) AS "groupPayments",

          (SELECT COALESCE(json_agg(t), '[]'::json) FROM (
             SELECT p."id", p."amountBdt", p."feeBdt", p."netAmountBdt",
                    p."direction"::text AS "direction", p."status"::text AS "status",
                    p."description", p."createdAt"
             FROM payments p
             JOIN wallets w ON p."walletId" = w."id"
             WHERE w."userId" = \$1
          ) t) AS "walletPayments",

          (SELECT COALESCE(json_agg(t), '[]'::json) FROM (
             SELECT w."id", w."amountBdt", w."feeBdt", w."netAmountBdt",
                    w."status"::text AS "status", w."bankName", w."requestedAt" AS "createdAt"
             FROM withdrawals w
             JOIN wallets wa ON w."walletId" = wa."id"
             WHERE wa."userId" = \$1
          ) t) AS "withdrawals",

          (SELECT COALESCE(json_agg(t."dist"), '[]'::json) FROM (
             SELECT to_jsonb(d) || jsonb_build_object('projectTitle', pr."title") AS "dist"
             FROM profit_distributions d
             JOIN investments i ON d."investmentId" = i."id"
             JOIN investor_profiles p ON i."investorProfileId" = p."id"
             JOIN projects pr ON i."projectId" = pr."id"
             WHERE p."userId" = \$1
          ) t) AS "distributions"
      ''', [userId]);

      if (res.isEmpty) {
        return {'ok': false, 'message': _connectionErrorMsg()};
      }
      final row = res.first;

      // ─── Lenden (shob ek list e) ───
      final transactions = <Map<String, dynamic>>[];

      for (final r in _jsonList(row['projectPayments'])) {
        transactions.add({
          'id': r['id']?.toString() ?? '',
          'type': 'PROJECT_PAYMENT',
          'title': r['title']?.toString() ?? '',
          'amountBdt': _toDouble(r['amountBdt']),
          'feeBdt': 0.0,
          'status': r['status']?.toString() ?? '',
          'reference': r['transactionRef']?.toString() ?? '',
          'note': r['rejectionReason']?.toString(),
          'createdAt': r['createdAt']?.toString() ?? '',
        });
      }
      for (final r in _jsonList(row['groupPayments'])) {
        transactions.add({
          'id': r['id']?.toString() ?? '',
          'type': 'GROUP_PAYMENT',
          'title': r['title']?.toString() ?? '',
          'amountBdt': _toDouble(r['amountBdt']),
          'feeBdt': 0.0,
          'status': r['status']?.toString() ?? '',
          'reference': r['transactionRef']?.toString() ?? '',
          'note': null,
          'createdAt': r['createdAt']?.toString() ?? '',
        });
      }
      for (final r in _jsonList(row['walletPayments'])) {
        final dir = r['direction']?.toString() ?? '';
        transactions.add({
          'id': r['id']?.toString() ?? '',
          'type': dir == 'OUTBOUND' ? 'WALLET_OUT' : 'WALLET_IN',
          'title': r['description']?.toString() ?? '',
          'amountBdt': _toDouble(r['amountBdt']),
          'feeBdt': _toDouble(r['feeBdt']),
          'status': r['status']?.toString() ?? '',
          'reference': '',
          'note': null,
          'createdAt': r['createdAt']?.toString() ?? '',
        });
      }
      for (final r in _jsonList(row['withdrawals'])) {
        transactions.add({
          'id': r['id']?.toString() ?? '',
          'type': 'WITHDRAWAL',
          'title': r['bankName']?.toString() ?? '',
          'amountBdt': _toDouble(r['amountBdt']),
          'feeBdt': _toDouble(r['feeBdt']),
          'status': r['status']?.toString() ?? '',
          'reference': '',
          'note': null,
          'createdAt': r['createdAt']?.toString() ?? '',
        });
      }
      transactions.sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));

      // ─── Profit distribution ───
      // Column er naam schema te jai thakuk, ja ache shetai nibo — kichu banabo na
      final distributions = _jsonList(row['distributions']).map((d) {
        final net = _toDouble(d['netAmountBdt']);
        final feeRaw = _pick(d, ['platformFeeBdt', 'feeBdt', 'managementFeeBdt', 'serviceFeeBdt']);
        final grossRaw = _pick(d, ['grossAmountBdt', 'amountBdt', 'grossBdt']);
        final fee = feeRaw == null ? null : _toDouble(feeRaw);
        double? gross = grossRaw == null ? null : _toDouble(grossRaw);
        if (gross == null && fee != null) gross = net + fee;
        return <String, dynamic>{
          'id': d['id']?.toString() ?? '',
          'investmentId': d['investmentId']?.toString() ?? '',
          'projectTitle': d['projectTitle']?.toString() ?? '',
          'netAmountBdt': net,
          'grossAmountBdt': gross ?? net,
          'feeBdt': fee ?? ((gross ?? net) - net),
          'status': d['status']?.toString(),
          'date': (_pick(d, ['distributedAt', 'paidAt', 'distributionDate', 'createdAt']) ?? '').toString(),
        };
      }).toList()
        ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));

      return {
        'ok': true,
        'projects': _jsonList(row['projects']).map((p) => {...p, ...projectReturnRange(p)}).toList(),
        'groups': _jsonList(row['groups']).map((g) {
          return {...g, 'expectedReturnPct': _normalizePct(g['expectedReturnPct'])};
        }).toList(),
        'transactions': transactions,
        'distributions': distributions,
      };
    } catch (e) {
      debugPrint("Get Reports Data Error: $e");
      return {'ok': false, 'message': 'Could not load reports. Please try again.'};
    }
  }

  // ═════════════════════════════════════════════════════════
  // WEBSITE CERTIFICATES
  // Admin approve korle website `documents` table e INVESTMENT_RECEIPT row
  // banay (verificationHash shoho, description = "Receipt #<receiptNumber>").
  // Ekhane shei row + investment + project + user er data ana hoy — website
  // er certificate e hubohu ei data-i thake.
  // ═════════════════════════════════════════════════════════
  static Future<List<Map<String, dynamic>>> getWebsiteCertificates(String userId) async {
    if (userId.isEmpty) return [];
    try {
      final res = await queryNeonHttp('''
        SELECT d."id" AS "documentId", d."generatedAt", d."createdAt" AS "docCreatedAt",
               i."id" AS "investmentId", i."receiptNumber", i."amountBdt", i."expectedReturnBdt",
               i."returnType"::text AS "returnType", i."activatedAt", i."createdAt",
               i."status"::text AS "status",
               p."title", p."location", p."expectedReturnPct", p."returnPctMin", p."returnPctMax",
               p."durationDays",
               u."name", u."email", u."phone"
        FROM documents d
        JOIN investments i        ON d."description" = 'Receipt #' || i."receiptNumber"
        JOIN projects p           ON p."id" = i."projectId"
        JOIN investor_profiles ip ON ip."id" = i."investorProfileId"
        JOIN users u              ON u."id" = ip."userId"
        WHERE d."ownerUserId" = \$1
          AND u."id" = \$1
          AND d."category"::text = 'INVESTMENT_RECEIPT'
          AND d."verificationHash" IS NOT NULL
          AND d."deletedAt" IS NULL
        ORDER BY d."createdAt" DESC
      ''', [userId]);

      final seen = <String>{};
      final List<Map<String, dynamic>> out = [];
      for (final r in res) {
        final receiptNo = r['receiptNumber']?.toString() ?? '';
        if (receiptNo.isEmpty || !seen.add(receiptNo)) continue; // notun ta rakhi

        final createdAt = r['createdAt']?.toString() ?? '';
        final activatedAt = r['activatedAt']?.toString() ?? createdAt;
        final generatedAt = r['generatedAt']?.toString() ?? r['docCreatedAt']?.toString() ?? '';

        out.add({
          // Documents page er purono field gulo
          'id': r['investmentId'].toString(),
          'documentId': r['documentId'].toString(),
          'name': 'Investment Receipt — ${r['title'] ?? ''}',
          'category': 'INVESTMENT_RECEIPT',
          'certificateNo': receiptNo,
          'issuedDate': generatedAt,
          'createdAt': generatedAt,
          'status': 'CONFIRMED',
          'investmentStatus': r['status']?.toString() ?? 'ACTIVE',
          'amountInvested': _toDouble(r['amountBdt']),
          'projectTitle': r['title']?.toString() ?? 'Biniyog Project',
          'location': r['location']?.toString(),
          'userName': r['name']?.toString() ?? 'Investor',
          'userEmail': r['email']?.toString() ?? '',
          'userPhone': r['phone']?.toString(),
          // Website er certificate er hubohu hisab er jonno
          'investmentId': r['investmentId'].toString(),
          'generatedAt': generatedAt,
          'activatedAt': activatedAt,
          'expectedReturnBdt': _toDouble(r['expectedReturnBdt']),
          'returnType': r['returnType']?.toString() ?? 'PROFIT_SHARE',
          'expectedReturnPct': _toDouble(r['expectedReturnPct']),
          'returnPctMin': _toDoubleOrNull(r['returnPctMin']),
          'returnPctMax': _toDoubleOrNull(r['returnPctMax']),
          'durationDays': _toInt(r['durationDays']),
          // Website ek-i link QR e boshay: \${appUrl}/verify/\${receiptNumber}
          'verifyUrl': '$websiteBaseUrl/verify/$receiptNo',
        });
      }
      return out;
    } catch (e) {
      debugPrint("Get Website Certificates Error: $e");
      return [];
    }
  }

  /// Shudhu ACTIVE / COMPLETED group investment er certificate.
  /// (Age pending gulo o "CONFIRMED" certificate hishebe ashto,
  /// r email er jaygay userId pathano hocchilo.)
  static Future<List<Map<String, dynamic>>> getGroupWebsiteCertificates(String userId) async {
    if (userId.isEmpty) return [];
    try {
      final res = await queryNeonHttp('''
        SELECT gi."id", gi."receiptNumber", gi."amountBdt", gi."status"::text AS "status", gi."createdAt",
               bg."name" as "groupName", ge."name" as "entityName", gt."name" as "tierName",
               gt."expectedReturnPct", gt."durationMonths",
               u."name", u."email", u."phone"
        FROM group_investments gi
        JOIN group_tiers gt ON gi."tierId" = gt."id"
        JOIN group_entities ge ON gt."entityId" = ge."id"
        JOIN business_groups bg ON ge."groupId" = bg."id"
        JOIN users u ON gi."investorUserId" = u."id"
        WHERE gi."investorUserId" = \$1
          AND gi."status"::text IN ('ACTIVE', 'COMPLETED')
        ORDER BY gi."createdAt" DESC
      ''', [userId]);

      return res.map((r) {
        final id = r['id'].toString();
        final rawReceipt = r['receiptNumber']?.toString() ?? '';
        // Banano 'GRP-xxx' na — website receipt na dile certificate "pending" thake
        final receiptNo = rawReceipt;
        final createdAt = r['createdAt']?.toString() ?? '';
        final groupName = r['groupName']?.toString() ?? '';
        final tierName = r['tierName']?.toString() ?? '';
        final title = [groupName, tierName].where((s) => s.isNotEmpty).join(' — ');

        return <String, dynamic>{
          'id': id,
          'name': title.isEmpty ? 'Investment Receipt' : 'Investment Receipt — $title',
          'category': 'GROUP_INVESTMENT_RECEIPT',
          'certificateNo': receiptNo,
          'issuedDate': createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt,
          'createdAt': createdAt,
          'status': receiptNo.isEmpty ? 'RECEIPT_PENDING' : 'CONFIRMED',
          'investmentStatus': r['status']?.toString() ?? 'ACTIVE',
          'amountInvested': _toDouble(r['amountBdt']),
          'groupName': groupName,
          'entityName': r['entityName']?.toString() ?? '',
          'tierName': tierName,
          'projectTitle': title,
          'expectedReturnPct': _normalizePct(r['expectedReturnPct'], 0),
          'durationMonths': _toInt(r['durationMonths'], 0),
          'userName': r['name']?.toString() ?? '',
          'userEmail': r['email']?.toString() ?? '',
          'userPhone': r['phone']?.toString(),
          'verifyUrl': receiptNo.isEmpty ? '' : '$websiteBaseUrl/verify/$receiptNo',
        };
      }).toList();
    } catch (e) {
      debugPrint("Get Group Website Certificates Error: $e");
      return [];
    }
  }

  static Future<void> _ensureReceiptNumbersExist() async {
    try {
      // Age app nije ekta APPROVED kisti dekhlei investment ACTIVE kore dito ar
      // shobar (PENDING o) receipt number boshato — ledger, fundedAmount,
      // contract chara. Website eta approve er shomoy kore (puro taka verify
      // hole), tai app ar financial status bodlay na.
      // 3. Age app nijei bhuya "certificate" document row banato (asol file nei,
      //    signature nei, shobar jonno public). Egulo soft-delete — website er
      //    asol certificate e verificationHash thake, segulo chhoa hoy na.
      await executeNeonHttp('''
        UPDATE documents
        SET "deletedAt" = NOW()
        WHERE "category"::text = 'INVESTMENT_RECEIPT'
          AND "verificationHash" IS NULL
          AND "fileUrl" LIKE 'https://biniyogclub.com/verify/%'
          AND "deletedAt" IS NULL
      ''');
    } catch (e) {
      debugPrint("Ensure Receipt Numbers Error: $e");
    }
  }

  // ═════════════════════════════════════════════════════════
  // GROUP INVESTMENTS
  // ═════════════════════════════════════════════════════════
  /// Postgres text[] kokhono List, kokhono "{a,b}" string hishebe ashe
  static List<String> _parseTextArray(dynamic v) {
    if (v == null) return <String>[];
    if (v is List) {
      return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    var s = v.toString().trim();
    if (s.isEmpty || s == '{}') return <String>[];
    if (s.startsWith('[')) {
      try {
        final d = jsonDecode(s);
        if (d is List) return d.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      } catch (_) {}
    }
    if (s.startsWith('{') && s.endsWith('}')) s = s.substring(1, s.length - 1);
    final out = <String>[];
    for (final m in RegExp(r'"((?:[^"\\]|\\.)*)"|([^,]+)').allMatches(s)) {
      final item = (m.group(1) ?? m.group(2) ?? '').replaceAll(r'\"', '"').trim();
      if (item.isNotEmpty) out.add(item);
    }
    return out;
  }

  static Future<List<Map<String, dynamic>>> getBusinessGroupsWithTiers() async {
    try {
      final rows = await queryNeonHttp('''
        SELECT 
          bg.id as group_id, bg.slug as group_slug, bg.name as group_name, 
          bg.tagline as group_tagline, bg.description as group_description, 
          bg."logoUrl" as group_logo_url, bg."coverUrl" as group_cover_url,
          ge.id as entity_id, ge.name as entity_name, ge.slug as entity_slug, 
          ge.description as entity_description, ge."logoUrl" as entity_logo_url,
          gt.id as tier_id, gt.type::text as tier_type, gt.name as tier_name, 
          gt.description as tier_description, gt.benefits as tier_benefits,
          gt."minAmountBdt" as tier_min_amount, gt."maxAmountBdt" as tier_max_amount, 
          gt."expectedReturnPct" as tier_expected_return, gt."durationMonths" as tier_duration_months,
          to_jsonb(gt) ->> 'availableUnits' as tier_available_units,
          ba.id as bank_id, ba."bankName" as bank_name, ba."accountName" as bank_account_name, 
          ba."accountNumber" as bank_account_number, ba."branchName" as bank_branch_name
        FROM business_groups bg
        LEFT JOIN group_entities ge ON ge."groupId" = bg.id AND ge."isActive" = true
        LEFT JOIN group_tiers gt ON gt."entityId" = ge.id AND gt."isActive" = true
        LEFT JOIN bank_accounts ba ON gt."bankAccountId" = ba.id
        WHERE bg."isActive" = true
        ORDER BY bg.name ASC, ge.name ASC, gt."sortOrder" ASC NULLS LAST, gt."minAmountBdt" ASC NULLS LAST;
      ''');

      final Map<String, Map<String, dynamic>> groupsMap = {};

      for (final r in rows) {
        final groupId = r['group_id']?.toString();
        if (groupId == null) continue;

        groupsMap.putIfAbsent(groupId, () => {
          'id': groupId,
          'name': r['group_name']?.toString() ?? '',
          'slug': r['group_slug']?.toString() ?? '',
          'tagline': r['group_tagline']?.toString(),
          'description': r['group_description']?.toString() ?? '',
          'logoUrl': r['group_logo_url']?.toString(),
          'coverUrl': r['group_cover_url']?.toString(),
          'entitiesMap': <String, Map<String, dynamic>>{},
        });

        final entityId = r['entity_id']?.toString();
        if (entityId == null) continue;

        final entitiesMap = groupsMap[groupId]!['entitiesMap'] as Map<String, Map<String, dynamic>>;
        entitiesMap.putIfAbsent(entityId, () => {
          'id': entityId,
          'name': r['entity_name']?.toString() ?? '',
          'slug': r['entity_slug']?.toString() ?? '',
          'description': r['entity_description']?.toString() ?? '',
          'logoUrl': r['entity_logo_url']?.toString(),
          'tiers': <Map<String, dynamic>>[],
        });

        final tierId = r['tier_id']?.toString();
        if (tierId == null) continue;

        (entitiesMap[entityId]!['tiers'] as List<Map<String, dynamic>>).add({
          'id': tierId,
          'type': r['tier_type']?.toString() ?? 'INVESTOR',
          'name': r['tier_name']?.toString() ?? 'Tier',
          'description': r['tier_description']?.toString() ?? '',
          'benefits': _parseTextArray(r['tier_benefits']),
          // Na thakle 0 — banano default (10000 / 12 mash) dekhabo na
          'minAmountBdt': _toDouble(r['tier_min_amount']),
          'maxAmountBdt': _toDoubleOrNull(r['tier_max_amount']),
          'expectedReturnPct': _normalizePct(r['tier_expected_return']),
          'durationMonths': _toInt(r['tier_duration_months']),
          // null = unit er hishab nei; 0 = shob bikri hoye geche
          'availableUnits': r['tier_available_units'] == null ? null : _toInt(r['tier_available_units']),
          'bank': r['bank_id'] != null
              ? {
            'id': r['bank_id'].toString(),
            'bankName': r['bank_name']?.toString() ?? '',
            'accountName': r['bank_account_name']?.toString() ?? '',
            'accountNumber': r['bank_account_number']?.toString() ?? '',
            'branchName': r['bank_branch_name']?.toString() ?? '',
          }
              : null,
        });
      }

      return groupsMap.values.map((g) {
        final entitiesMap = g.remove('entitiesMap') as Map<String, Map<String, dynamic>>? ?? {};
        g['entities'] = entitiesMap.values.toList();
        return g;
      }).toList();
    } catch (e) {
      debugPrint("Get Business Groups Error: $e");
      return [];
    }
  }

  // Fetch Group Investments (Investments page + Group page dui jaygay use hoy)
  static Future<List<Map<String, dynamic>>> getGroupInvestmentsData(String userId, {String? email}) async {
    try {
      final activeUserId = await _resolveUserId(userId, email);
      if (activeUserId.isEmpty) return [];

      final res = await queryNeonHttp('''
        SELECT gi."id", gi."tierId", gi."receiptNumber", gi."amountBdt", gi."plotNumber",
               gi."plotSizeSqft", gi."sharePercentage", gi."status"::text AS "status", gi."createdAt",
               bg."name" AS "groupName", ge."name" AS "entityName", gt."name" AS "tierName",
               gt."expectedReturnPct", gt."durationMonths",
               ba."id" AS "bankId", ba."bankName", ba."accountName", ba."accountNumber",
               ba."branchName", ba."mobileNumber",
               sub."id" AS "subId", sub."status" AS "subStatus",
               sub."transactionRef" AS "subRef", sub."createdAt" AS "subCreatedAt",
               sub."reason" AS "subReason",
               COALESCE(to_jsonb(gi) ->> 'paymentPlan', 'FULL') AS "paymentPlan",
               COALESCE((SELECT SUM(x."amountBdt") FROM group_investment_payments x
                         WHERE x."groupInvestmentId" = gi."id" AND x."status"::text = 'APPROVED'), 0) AS "paidApproved",
               COALESCE((SELECT SUM(x."amountBdt") FROM group_investment_payments x
                         WHERE x."groupInvestmentId" = gi."id"
                           AND x."status"::text IN ('SUBMITTED', 'UNDER_REVIEW')), 0) AS "paidPending"
        FROM group_investments gi
        JOIN group_tiers gt     ON gi."tierId" = gt."id"
        JOIN group_entities ge  ON gt."entityId" = ge."id"
        JOIN business_groups bg ON ge."groupId" = bg."id"
        LEFT JOIN bank_accounts ba ON gt."bankAccountId" = ba."id"
        LEFT JOIN LATERAL (
          SELECT p."id", p."status"::text AS "status", p."transactionRef", p."createdAt",
                 to_jsonb(p) ->> 'rejectionReason' AS "reason"
          FROM group_investment_payments p
          WHERE p."groupInvestmentId" = gi."id"
          ORDER BY p."createdAt" DESC
          LIMIT 1
        ) sub ON true
        WHERE gi."investorUserId" = \$1
        ORDER BY gi."createdAt" DESC
      ''', [activeUserId]);

      return res.map((r) {
        final bankId = r['bankId']?.toString();

        return <String, dynamic>{
          'id': r['id'].toString(),
          'tierId': r['tierId']?.toString() ?? '',
          'receiptNumber': r['receiptNumber']?.toString(),
          'groupName': r['groupName']?.toString() ?? '',
          'entityName': r['entityName']?.toString() ?? '',
          'tierName': r['tierName']?.toString() ?? '',
          'amountBdt': _toDouble(r['amountBdt']),
          'plotNumber': r['plotNumber']?.toString() ?? '',
          'plotSizeSqft': _toDouble(r['plotSizeSqft']),
          'sharePercentage': _toDouble(r['sharePercentage']),
          'status': r['status']?.toString() ?? 'PENDING',
          'createdAt': r['createdAt']?.toString() ?? '',
          'expectedReturnPct': _normalizePct(r['expectedReturnPct']),
          'durationMonths': _toInt(r['durationMonths']),
          'paymentPlan': (r['paymentPlan']?.toString() ?? 'FULL').toUpperCase(),
          'paidApproved': _toDouble(r['paidApproved']),
          'paidPending': _toDouble(r['paidPending']),
          // GroupInvestmentsPage o ei field use kore — age eta khali jeto
          'bankAccountId': bankId ?? '',
          'bank': bankId == null
              ? null
              : <String, dynamic>{
            'id': bankId,
            'bankName': r['bankName']?.toString() ?? '',
            'accountName': r['accountName']?.toString() ?? '',
            'accountNumber': r['accountNumber']?.toString() ?? '',
            'branchName': r['branchName']?.toString() ?? '',
            'mobileNumber': r['mobileNumber']?.toString() ?? '',
          },
          'latestSubmission': r['subId'] == null
              ? null
              : <String, dynamic>{
            'id': r['subId'].toString(),
            'status': r['subStatus']?.toString() ?? 'SUBMITTED',
            'transactionRef': r['subRef']?.toString() ?? '',
            'rejectionReason': r['subReason']?.toString(),
            'createdAt': r['subCreatedAt']?.toString() ?? '',
          },
        };
      }).toList();
    } catch (e) {
      debugPrint("Get Group Investments Error: $e");
      return [];
    }
  }

  static Future<Map<String, dynamic>> createGroupInvestment({
    required String userId,
    required String tierId,
    required double amountBdt,
    String? notes,
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};

    try {
      // Tier ta ki chalu ache, r amount ki min/max er moddhe?
      final tierRes = await queryNeonHttp('''
        SELECT gt."id", gt."minAmountBdt", gt."maxAmountBdt", gt."isActive",
               ge."isActive" AS "entityActive", bg."isActive" AS "groupActive",
               to_jsonb(gt) ->> 'availableUnits' AS "availableUnits"
        FROM group_tiers gt
        JOIN group_entities ge ON ge."id" = gt."entityId"
        JOIN business_groups bg ON bg."id" = ge."groupId"
        WHERE gt."id" = \$1
      ''', [tierId]);

      if (tierRes.isEmpty) {
        return {
          'success': false,
          'message': _lastConnectionError != null ? _connectionErrorMsg() : 'Investment tier not found.',
        };
      }

      final t = tierRes.first;
      if (t['isActive'] == false || t['entityActive'] == false || t['groupActive'] == false) {
        return {'success': false, 'message': 'This tier is not open for investment right now.'};
      }
      // Unit er hishab thakle ar 0 hoye gele — bikri shesh
      if (t['availableUnits'] != null && _toInt(t['availableUnits']) <= 0) {
        return {'success': false, 'message': 'This tier is sold out. No units are available right now.'};
      }

      final minAmt = _toDouble(t['minAmountBdt']);
      final maxAmt = _toDoubleOrNull(t['maxAmountBdt']);
      if (minAmt > 0 && amountBdt < minAmt) {
        return {'success': false, 'message': 'Minimum investment amount is ৳${minAmt.toStringAsFixed(0)}.'};
      }
      if (maxAmt != null && maxAmt > 0 && amountBdt > maxAmt) {
        return {'success': false, 'message': 'Maximum investment amount is ৳${maxAmt.toStringAsFixed(0)}.'};
      }

      final invId = _generateUuid();
      final nowStr = _nowIso();
      final certNo = 'GRP-${invId.substring(0, min(12, invId.length)).toUpperCase()}';

      final ins = await queryNeonHttp('''
        INSERT INTO group_investments (
          "id", "tierId", "investorUserId", "status", "amountBdt", "notes", "receiptNumber", "createdAt", "updatedAt"
        ) VALUES (
          \$1, \$2, \$3, 'PAYMENT_PENDING'::"GroupInvestmentStatus", \$4, \$5, \$6, \$7, \$7
        )
        ON CONFLICT ("id") DO UPDATE SET "updatedAt" = EXCLUDED."updatedAt"
        RETURNING "id"
      ''', [
        invId,
        tierId,
        userId,
        amountBdt,
        (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
        certNo,
        nowStr,
      ]);

      if (ins.isEmpty) {
        debugPrint('createGroupInvestment failed: $_lastDbFailure');
        return {'success': false, 'message': _saveFailMsg('Could not create the investment.')};
      }

      return {
        'success': true,
        'groupInvestmentId': invId,
        'message': 'Group investment created! Please submit your payment proof.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  static Future<Map<String, dynamic>> submitGroupInvestmentPayment({
    required String groupInvestmentId,
    required String userId,
    required double amountBdt,
    required String bankAccountId,
    required String transactionRef,
    required String proofFileUrl,
    String? notes,
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    if (bankAccountId.isEmpty) {
      return {'success': false, 'message': 'Please select the bank account you paid into.'};
    }

    try {
      // Group investment ta ki ei user er, r payment er opekkhay ache?
      final check = await queryNeonHttp('''
        SELECT gi."status"::text AS "status",
               EXISTS (
                 SELECT 1 FROM group_investment_payments x
                 WHERE x."groupInvestmentId" = gi."id" AND x."status"::text = 'SUBMITTED'
               ) AS "hasPending"
        FROM group_investments gi
        WHERE gi."id" = \$1 AND gi."investorUserId" = \$2
      ''', [groupInvestmentId, userId]);

      if (check.isEmpty) {
        return {
          'success': false,
          'message': _lastConnectionError != null ? _connectionErrorMsg() : 'Group investment not found.',
        };
      }

      final st = check.first['status']?.toString() ?? '';
      if (st != 'PENDING' && st != 'PAYMENT_PENDING') {
        return {'success': false, 'message': 'This investment is not awaiting payment.'};
      }
      if (check.first['hasPending'] == true) {
        return {'success': false, 'message': 'A payment proof is already under review.'};
      }

      final nowStr = _nowIso();

      final ins = await queryNeonHttp('''
        INSERT INTO group_investment_payments (
          "id", "groupInvestmentId", "submittedBy", "status", "amountBdt",
          "bankAccountId", "transactionRef", "proofFileUrl", "proofMimeType", "notes", "createdAt", "updatedAt"
        ) VALUES (
          \$1, \$2, \$3, 'SUBMITTED'::"ManualPaymentStatus", \$4,
          \$5, \$6, \$7, \$8, \$9, \$10, \$10
        )
        ON CONFLICT ("id") DO UPDATE SET "updatedAt" = EXCLUDED."updatedAt"
        RETURNING "id"
      ''', [
        _generateUuid(),
        groupInvestmentId,
        userId,
        amountBdt,
        bankAccountId,
        transactionRef,
        proofFileUrl,
        _mimeFromDataUri(proofFileUrl),
        (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
        nowStr,
      ]);

      if (ins.isEmpty) return {'success': false, 'message': _connectionErrorMsg()};

      await executeNeonHttp('''
        UPDATE group_investments
        SET "status" = 'PAYMENT_PENDING'::"GroupInvestmentStatus", "updatedAt" = \$1
        WHERE "id" = \$2
      ''', [nowStr, groupInvestmentId]);

      await _notifyGroupPending(
        userId: userId,
        groupInvestmentId: groupInvestmentId,
        amountBdt: amountBdt,
        resubmitted: true,
      );
      unawaited(EmailService.sendGroupPaymentSubmitted(groupInvestmentId));

      return {
        'success': true,
        'message': 'Group investment payment proof submitted successfully!',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  // ═════════════════════════════════════════════════════════
  // GROUP INVEST + PAYMENT — Bank / Cash / Cheque (project er motoi, website er
  // niyome protita madhyom alada row). Admin approve korle ACTIVE (website e).
  // ═════════════════════════════════════════════════════════

  /// App er check server eo — kichu miss gele kichui save hobe na
  static String? _checkPaymentParts({
    required Set<String> m,
    required double amountBdt,
    required double bankAmount,
    required double cashAmount,
    required double chequeAmount,
    String? bankTransactionId,
    List<String> bankProofUrls = const [],
    String? cashReceiver,
    List<String> chequeProofUrls = const [],
    List<String> cashProofUrls = const [],
    String? chequeNumber,
    String? cashReceiptNo,
  }) {
    // Website split-payment.ts er niyom
    if (m.isEmpty) return 'Please choose a payment method.';
    if (m.length > 2) return 'You can combine at most two payment methods.';
    if (amountBdt <= 0) return 'Please enter the amount.';
    if (m.contains('BANK') && bankProofUrls.isEmpty) {
      return 'Bank Transfer: upload the transfer receipt or screenshot.';
    }
    if (m.contains('CASH') && cashReceiverValue(cashReceiver) == null) {
      return 'Cash: select who received the cash.';
    }
    if (m.contains('CHEQUE')) {
      if ((chequeNumber ?? '').trim().isEmpty) return 'Cheque: the cheque number is required.';
      if (chequeProofUrls.isEmpty) return 'Cheque: upload a photo of the cheque or deposit slip.';
    }
    if (bankProofUrls.length > 3 || chequeProofUrls.length > 3 || cashProofUrls.length > 3) {
      return 'Upload at most 3 proof files for each payment method.';
    }
    if (m.length > 1) {
      for (final (k, v) in [('BANK', bankAmount), ('CASH', cashAmount), ('CHEQUE', chequeAmount)]) {
        if (m.contains(k) && v <= 0) return 'Enter an amount for every payment method you chose.';
      }
      final parts = (m.contains('BANK') ? bankAmount : 0) +
          (m.contains('CASH') ? cashAmount : 0) +
          (m.contains('CHEQUE') ? chequeAmount : 0);
      if ((parts - amountBdt).abs() > 0.5) return 'The split amounts must add up to the total.';
    }
    return null;
  }

  /// Website er CASH_RECEIVERS value — purono app er lekha ("MD Sir") o bujhe
  static String? cashReceiverValue(String? raw) {
    final v = (raw ?? '').trim().toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (v.isEmpty) return null;
    if (v == 'CEO') return 'CEO';
    if (v == 'MD' || v.startsWith('MDSIR') || v.contains('MANAGINGDIRECTOR')) return 'MD';
    if (v.startsWith('CHAIRMAN')) return 'CHAIRMAN';
    if (v.startsWith('FINANCE')) return 'FINANCE_TEAM';
    return null;
  }

  /// Notun group investment + prothom payment (Browse Groups theke)
  static Future<Map<String, dynamic>> groupInvestWithPayment({
    required String userId,
    required String tierId,
    required double amountBdt,
    required List<String> methods,
    double? payNowBdt,
    String paymentPlan = 'FULL',
    double bankAmount = 0,
    double cashAmount = 0,
    double chequeAmount = 0,
    String? bankAccountId,
    String? bankAccountLabel,
    String? bankTransactionId,
    String? bankReceiptUrl,
    String? cashReceiver,
    String? chequeImageUrl,
    List<String> bankProofUrls = const [],
    List<String> chequeProofUrls = const [],
    List<String> cashProofUrls = const [],
    String? chequeNumber,
    String? cashReceiptNo,
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    final m = methods.toSet();
    final plan = paymentPlan == 'INSTALLMENT' ? 'INSTALLMENT' : 'FULL';
    final payNow = plan == 'FULL' ? amountBdt : (payNowBdt ?? amountBdt);
    _lastDbFailure = null;

    if (payNow <= 0 || (payNow * 100).round() > (amountBdt * 100).round()) {
      return {'success': false, 'message': 'The amount you pay now must be between 1 and ${_fmtTk(amountBdt)}.'};
    }
    final problem = _checkPaymentParts(
      m: m,
      amountBdt: payNow,
      bankAmount: bankAmount,
      cashAmount: cashAmount,
      chequeAmount: chequeAmount,
      bankTransactionId: bankTransactionId,
      bankProofUrls: [...bankProofUrls, if ((bankReceiptUrl ?? '').isNotEmpty) bankReceiptUrl!],
      cashReceiver: cashReceiver,
      chequeProofUrls: [...chequeProofUrls, if ((chequeImageUrl ?? '').isNotEmpty) chequeImageUrl!],
      cashProofUrls: cashProofUrls,
      chequeNumber: chequeNumber,
      cashReceiptNo: cashReceiptNo,
    );
    if (problem != null) return {'success': false, 'message': problem};

    // Tier er nijer bank account (bankAccountId NOT NULL hole lagbe)
    final tier = await queryNeonHttp('SELECT "bankAccountId" FROM group_tiers WHERE "id" = \$1', [tierId]);
    final tierBankId = tier.isEmpty ? null : tier.first['bankAccountId']?.toString();

    // ধাপ ১: investment (tier chalu? min/max? — createGroupInvestment e check)
    final inv = await createGroupInvestment(userId: userId, tierId: tierId, amountBdt: amountBdt);
    if (inv['success'] != true) return inv;
    final gid = inv['groupInvestmentId'].toString();

    Future<Map<String, dynamic>> undo(String msg) async {
      // Payment save na hole addha investment rakhbo na
      await executeNeonHttp('''
        DELETE FROM group_investments gi
        WHERE gi."id" = \$1 AND gi."investorUserId" = \$2
          AND NOT EXISTS (SELECT 1 FROM group_investment_payments p WHERE p."groupInvestmentId" = gi."id")
      ''', [gid, userId]);
      return {'success': false, 'message': msg};
    }

    try {
      await _setPaymentPlan(group: true, id: gid, plan: plan);
      final res = await _insertPaymentParts(
        group: true,
        parentId: gid,
        userId: userId,
        m: m,
        payNowBdt: payNow,
        bankAmount: bankAmount,
        cashAmount: cashAmount,
        chequeAmount: chequeAmount,
        bankAccountId: bankAccountId,
        fallbackBankId: tierBankId,
        bankAccountLabel: bankAccountLabel,
        bankTransactionId: bankTransactionId,
        bankProofUrls: [...bankProofUrls, if ((bankReceiptUrl ?? '').isNotEmpty) bankReceiptUrl!],
        cashReceiver: cashReceiver,
        chequeProofUrls: [...chequeProofUrls, if ((chequeImageUrl ?? '').isNotEmpty) chequeImageUrl!],
        cashProofUrls: cashProofUrls,
        chequeNumber: chequeNumber,
        cashReceiptNo: cashReceiptNo,
        note: plan == 'INSTALLMENT' ? 'Installment 1 · commitment ${_fmtTk(amountBdt)}' : null,
      );
      if (res['success'] != true) return await undo(res['message']?.toString() ?? 'Could not save your payment.');
      await _notifyGroupPending(userId: userId, groupInvestmentId: gid, amountBdt: amountBdt);
      unawaited(EmailService.sendGroupPending(gid));
      return {
        'success': true,
        'groupInvestmentId': gid,
        'message': 'Investment submitted! It will be active after admin approval.',
      };
    } catch (e) {
      debugPrint('groupInvestWithPayment error: $e');
      return await undo('Could not save your payment details. ($e)');
    }
  }

  /// Age theke thaka group investment e (baki taka / kisti / reject howa part) payment
  static Future<Map<String, dynamic>> submitGroupPaymentMulti({
    required String groupInvestmentId,
    required String userId,
    required double amountBdt,
    required List<String> methods,
    double bankAmount = 0,
    double cashAmount = 0,
    double chequeAmount = 0,
    String? bankAccountId,
    String? bankAccountLabel,
    String? bankTransactionId,
    String? bankReceiptUrl,
    String? cashReceiver,
    String? chequeImageUrl,
    List<String> bankProofUrls = const [],
    List<String> chequeProofUrls = const [],
    List<String> cashProofUrls = const [],
    String? chequeNumber,
    String? cashReceiptNo,
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    final m = methods.toSet();
    _lastDbFailure = null;
    final problem = _checkPaymentParts(
      m: m,
      amountBdt: amountBdt,
      bankAmount: bankAmount,
      cashAmount: cashAmount,
      chequeAmount: chequeAmount,
      bankTransactionId: bankTransactionId,
      bankProofUrls: [...bankProofUrls, if ((bankReceiptUrl ?? '').isNotEmpty) bankReceiptUrl!],
      cashReceiver: cashReceiver,
      chequeProofUrls: [...chequeProofUrls, if ((chequeImageUrl ?? '').isNotEmpty) chequeImageUrl!],
      cashProofUrls: cashProofUrls,
      chequeNumber: chequeNumber,
      cashReceiptNo: cashReceiptNo,
    );
    if (problem != null) return {'success': false, 'message': problem};

    try {
      final prog = await getPaymentProgress(group: true, id: groupInvestmentId, userId: userId);
      if (prog == null) {
        return {
          'success': false,
          'message': _lastConnectionError != null ? _connectionErrorMsg() : 'Group investment not found.',
        };
      }
      final pay = _checkPayable(prog, amountBdt);
      if (pay != null) return {'success': false, 'message': pay};

      final res = await _insertPaymentParts(
        group: true,
        parentId: groupInvestmentId,
        userId: userId,
        m: m,
        payNowBdt: amountBdt,
        bankAmount: bankAmount,
        cashAmount: cashAmount,
        chequeAmount: chequeAmount,
        bankAccountId: bankAccountId,
        fallbackBankId: prog['fallbackBankId']?.toString(),
        bankAccountLabel: bankAccountLabel,
        bankTransactionId: bankTransactionId,
        bankProofUrls: [...bankProofUrls, if ((bankReceiptUrl ?? '').isNotEmpty) bankReceiptUrl!],
        cashReceiver: cashReceiver,
        chequeProofUrls: [...chequeProofUrls, if ((chequeImageUrl ?? '').isNotEmpty) chequeImageUrl!],
        cashProofUrls: cashProofUrls,
        chequeNumber: chequeNumber,
        cashReceiptNo: cashReceiptNo,
        note: prog['plan'] == 'INSTALLMENT' ? 'Installment · commitment ${_fmtTk(_toDouble(prog['total']))}' : null,
      );
      if (res['success'] != true) return res;
      await _notifyGroupPending(
        userId: userId,
        groupInvestmentId: groupInvestmentId,
        amountBdt: amountBdt,
        resubmitted: true,
      );
      unawaited(EmailService.sendGroupPaymentSubmitted(groupInvestmentId));
      return <String, dynamic>{
        'success': true,
        'message': 'Payment submitted! It will be checked by admin.',
      };
    } catch (e) {
      debugPrint('submitGroupPaymentMulti error: $e');
      return {'success': false, 'message': 'Could not save your payment details. ($e)'};
    }
  }

  /// Neon er error body theke shudhu "message" ta
  static String _shortDbError() {
    final e = _lastDbFailure ?? _lastConnectionError ?? '';
    final m = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(e);
    final msg = m?.group(1) ?? e;
    if (msg.isEmpty) return 'unknown error';
    if (e.contains('HTTP 413') || msg.toLowerCase().contains('too large')) {
      return 'photo is too large';
    }
    return msg.length > 140 ? '${msg.substring(0, 140)}…' : msg;
  }



}