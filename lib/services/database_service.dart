import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import '../config/db_config.dart';

class DatabaseService {
  static final http.Client _httpClient = http.Client();
  static Connection? _connection;
  static String? _lastConnectionError;

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

  /// Deadline na thakle 0 — banano "116 days" r dekhabo na
  static int _daysLeft(String? deadline) {
    if (deadline == null || deadline.isEmpty) return 0;
    final d = DateTime.tryParse(deadline);
    if (d == null) return 0;
    return d.difference(DateTime.now()).inDays.clamp(0, 3650);
  }

  static String _mimeFromDataUri(String s) {
    final m = RegExp(r'^data:([^;,]+)[;,]').firstMatch(s);
    return m?.group(1) ?? 'image/png';
  }

  static String _connectionErrorMsg() =>
      _lastConnectionError != null
          ? 'Could not reach the server. Please check your internet connection.'
          : 'Something went wrong. Please try again.';

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
          _lastConnectionError = myError = "HTTP ${response.statusCode}: ${response.body}";
        }
      } catch (e) {
        debugPrint("Neon HTTP Query Exception (attempt $attempt): $e");
        _lastConnectionError = myError = e.toString();
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
          _lastConnectionError = "HTTP ${response.statusCode}: ${response.body}";
        }
      } catch (e) {
        debugPrint("Neon HTTP Execute Exception (attempt $attempt): $e");
        _lastConnectionError = e.toString();
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

  // Helper to ensure investorProfile and emailVerified exist in Neon DB for Website Compatibility
  static Future<void> _ensureInvestorProfileExists(String userId) async {
    if (userId.isEmpty) return;
    try {
      final nowStr = _nowIso();
      final profileId = _generateUuid();

      await executeNeonHttp('''
        INSERT INTO investor_profiles ("id", "userId", "country", "createdAt", "updatedAt")
        VALUES (\$1, \$2, 'BD', \$3, \$3)
        ON CONFLICT ("userId") DO NOTHING;
      ''', [profileId, userId, nowStr]);

      await executeNeonHttp('''
        UPDATE users
        SET "emailVerified" = true
        WHERE "id" = \$1 AND ("emailVerified" IS NOT TRUE OR "emailVerified" IS NULL);
      ''', [userId]);
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

  /// +8801… / 01… — duita-i 01… e ani
  static String normalizeBdPhone(String v) =>
      v.replaceAll(RegExp(r'[\s-]'), '').replaceFirst(RegExp(r'^\+?88(?=01)'), '');

  // Register User — website er users + investor_profiles + wallets e
  static Future<Map<String, dynamic>> registerUser({
    required String name,
    String? email,
    required String phone,
    required String password,
    // Nullable rakhi jate purono AuthService.register compile kore —
    // kintu khali hole register hobe na
    String? nidNumber,
    DateTime? dateOfBirth,
    String? address,
    String? city, // jela — website "city" column e
    String? nomineeNidNumber,
    String? nomineeRelation,
  }) async {
    try {
      final cleanEmail = (email ?? '').trim().toLowerCase();
      final cleanPhone = normalizeBdPhone(phone.trim());
      final cleanNid = (nidNumber ?? '').trim();
      final cleanAddress = (address ?? '').trim();
      final nomineeNid = (nomineeNidNumber ?? '').trim();
      final nomineeRel = (nomineeRelation ?? '').trim();
      if (cleanPhone.isEmpty || cleanNid.isEmpty || cleanAddress.isEmpty || dateOfBirth == null) {
        return {'success': false, 'message': 'Please fill in all required fields.'};
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
             OR "phone" = \$3::text
          LIMIT 1
        ),
        existing_check_nid AS (
          SELECT "nationalId" FROM investor_profiles WHERE "nationalId" = \$8::text LIMIT 1
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
        cleanNid, // 8
        nomineeNid.isEmpty ? null : nomineeNid, // 9
        nomineeRel.isEmpty ? null : nomineeRel, // 10
        walletId, // 11
        // Email na thakle "verified" bola jay na
        cleanEmail.isNotEmpty, // 12
        cleanAddress, // 13
        (city ?? '').trim().isEmpty ? null : city!.trim(), // 14
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
      if (existingPhone.isNotEmpty && existingPhone == cleanPhone) {
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
      final cleanInput = RegExp(r'^[+\d\s-]+$').hasMatch(raw) ? normalizeBdPhone(raw) : raw;

      final result = await queryNeonHttp('''
        SELECT "id", "name", "email", "phone", "passwordHash", "avatarUrl", "status"::text AS "status", "updatedAt"
        FROM users 
        WHERE LOWER("email") = LOWER(\$1) OR "phone" = \$1
      ''', [cleanInput]);

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
      if (newPassword.length < 8) {
        return {'success': false, 'message': 'Password must be at least 8 characters.'};
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
      // KYC ar lage na — account thakle-i invest kora jay
      String profileId;
      final profRes = await queryNeonHttp(
          'SELECT "id" FROM investor_profiles WHERE "userId" = \$1',
          [userId]);
      if (profRes.isNotEmpty) {
        profileId = profRes.first['id'].toString();
      } else {
        profileId = _generateUuid();
        final nowStr = _nowIso();
        await executeNeonHttp('''
          INSERT INTO investor_profiles ("id", "userId", "createdAt", "updatedAt")
          VALUES (\$1, \$2, \$3, \$3)
          ON CONFLICT ("userId") DO NOTHING
        ''', [profileId, userId, nowStr]);
        final again = await queryNeonHttp(
            'SELECT "id" FROM investor_profiles WHERE "userId" = \$1', [userId]);
        if (again.isEmpty) return {'success': false, 'message': _connectionErrorMsg()};
        profileId = again.first['id'].toString();
      }

      final projRes = await queryNeonHttp('''
        SELECT "id", "status"::text AS "status", "fundingGoalBdt", "fundedAmountBdt", "minInvestmentBdt",
               "maxInvestmentBdt", "expectedReturnPct", "returnPctMin", "returnPctMax",
               "returnType"::text AS "returnType"
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

      final goal = _toDouble(p['fundingGoalBdt'], 1.0);
      final funded = _toDouble(p['fundedAmountBdt']);
      final minInv = _toDouble(p['minInvestmentBdt']);
      final maxInv = _toDoubleOrNull(p['maxInvestmentBdt']);
      // 16 ba 0.16 — duitai 0.16. Project e nirdishto % na thakle range er
      // nicher ta (conservative) — banano 15% ar na
      final setPct = _normalizePct(p['expectedReturnPct']);
      final returnPct = setPct > 0 ? setPct : projectReturnRange(p)['returnMin']!;
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
      final certNo = 'BC-${investmentId.substring(0, min(12, investmentId.length)).toUpperCase()}';
      final nowStr = _nowIso();

      // ON CONFLICT: network retry hole duplicate row hobe na, r RETURNING diye
      // nishchit hoi je row asolei save hoyeche
      final ins = await queryNeonHttp('''
        INSERT INTO investments (
          "id", "investorProfileId", "projectId", "status", "amountBdt",
          "expectedReturnBdt", "returnType", "idempotencyKey", "receiptNumber", "createdAt", "updatedAt"
        ) VALUES (
          \$1, \$2, \$3, 'PENDING'::"InvestmentStatus", \$4,
          \$5, \$6::"ReturnType", \$7, \$8, \$9, \$9
        )
        ON CONFLICT ("id") DO UPDATE SET "updatedAt" = EXCLUDED."updatedAt"
        RETURNING "id"
      ''', [
        investmentId,
        profileId,
        projectId,
        amountBdt,
        amountBdt * returnPct,
        returnType,
        _generateUuid(),
        certNo,
        nowStr,
      ]);

      if (ins.isEmpty) return {'success': false, 'message': _connectionErrorMsg()};

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
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};

    try {
      // Investment ta ki ei user er, r ekhono payment er opekkhay ache?
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

      final ins = await queryNeonHttp('''
        INSERT INTO manual_payment_submissions (
          "id", "investmentId", "submittedBy", "status", "amountBdt",
          "bankAccountId", "paymentMethod", "transactionRef", "proofFileUrl",
          "proofMimeType", "notes", "createdAt", "updatedAt"
        ) VALUES (
          \$1, \$2, \$3, 'SUBMITTED'::"ManualPaymentStatus", \$4,
          \$5, 'BANK_TRANSFER', \$6, \$7,
          \$8, \$9, \$10, \$10
        )
        ON CONFLICT ("id") DO UPDATE SET "updatedAt" = EXCLUDED."updatedAt"
        RETURNING "id"
      ''', [
        submissionId,
        investmentId,
        userId,
        amountBdt,
        bankAccountId.isEmpty ? null : bankAccountId,
        transactionRef,
        fileUrl,
        _mimeFromDataUri(fileUrl),
        notes,
        nowStr,
      ]);

      if (ins.isEmpty) return {'success': false, 'message': _connectionErrorMsg()};

      await executeNeonHttp('''
        UPDATE investments
        SET "status" = 'PAYMENT_PENDING'::"InvestmentStatus", "paymentPendingAt" = \$1, "updatedAt" = \$1
        WHERE "id" = \$2
      ''', [nowStr, investmentId]);

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

  /// methods: 'BANK', 'CASH', 'CHEQUE' (ek ba ekadhik)
  static Future<Map<String, dynamic>> investWithPayment({
    required String userId,
    required String projectId,
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
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    final m = methods.toSet();
    if (m.isEmpty) return {'success': false, 'message': 'Please choose a payment method.'};

    // App er check server eo — kichu miss gele investment-i hobe na
    if (m.contains('BANK') &&
        ((bankTransactionId ?? '').trim().isEmpty || (bankReceiptUrl ?? '').isEmpty)) {
      return {'success': false, 'message': 'Bank payment needs the transaction number and receipt image.'};
    }
    if (m.contains('CASH') && (cashReceiver ?? '').trim().isEmpty) {
      return {'success': false, 'message': 'Please select who received the cash.'};
    }
    if (m.contains('CHEQUE') && (chequeImageUrl ?? '').isEmpty) {
      return {'success': false, 'message': 'Please upload the cheque image.'};
    }
    final parts = (m.contains('BANK') ? bankAmount : 0) +
        (m.contains('CASH') ? cashAmount : 0) +
        (m.contains('CHEQUE') ? chequeAmount : 0);
    if (m.length > 1 && (parts - amountBdt).abs() > 0.5) {
      return {'success': false, 'message': 'The split amounts must add up to the total.'};
    }

    // ধাপ ১: investment (min/max/baki/status — shob createInvestment e check hoy)
    final inv = await createInvestment(userId: userId, projectId: projectId, amountBdt: amountBdt);
    if (inv['success'] != true) return inv;
    final investmentId = inv['investmentId'].toString();

    Future<Map<String, dynamic>> undo(String msg) async {
      // Payment save na hole addha investment rakhbo na
      await executeNeonHttp('''
        DELETE FROM investments i USING investor_profiles p
        WHERE i."id" = \$1 AND i."investorProfileId" = p."id" AND p."userId" = \$2
          AND i."status"::text = 'PENDING'
      ''', [investmentId, userId]);
      return {'success': false, 'message': msg};
    }

    try {
      final metas = await Future.wait([
        _paymentMethodMeta(),
        _columnsOf('manual_payment_submissions'),
      ]);
      final pm = metas[0] as ({String cast, Set<String> labels});
      final cols = metas[1] as Map<String, bool>;

      // paymentMethod — DB je value nite pare tar moddhe theke
      String pick(List<String> candidates, String fallback) {
        if (pm.labels.isEmpty) return candidates.first;
        for (final c in candidates) {
          if (pm.labels.contains(c)) return c;
        }
        return pm.labels.contains(fallback) ? fallback : pm.labels.first;
      }

      final String method;
      if (m.length > 1) {
        method = pick(['MIXED', 'MULTIPLE', 'OTHER'], m.contains('BANK') ? 'BANK_TRANSFER' : 'CASH');
      } else if (m.contains('BANK')) {
        method = pick(['BANK_TRANSFER', 'BANK_DEPOSIT', 'BANK'], 'BANK_TRANSFER');
      } else if (m.contains('CASH')) {
        method = pick(['CASH', 'CASH_DEPOSIT', 'CASH_PAYMENT'], 'BANK_TRANSFER');
      } else {
        method = pick(['CHEQUE', 'CHECK', 'BANK_CHEQUE'], 'BANK_TRANSFER');
      }

      // Admin ek nojore shob dekhte pay — notes e pura bhag
      final lines = <String>[
        'Payment: ${[if (m.contains('BANK')) 'Bank', if (m.contains('CASH')) 'Cash', if (m.contains('CHEQUE')) 'Cheque'].join(' + ')}'
            ' — total ${_fmtTk(amountBdt)}',
        if (m.contains('BANK'))
          'Bank: ${_fmtTk(m.length > 1 ? bankAmount : amountBdt)}'
              '${(bankAccountLabel ?? '').isNotEmpty ? ' to $bankAccountLabel' : ''}'
              ', TRX ${bankTransactionId!.trim()}, receipt: $bankReceiptUrl',
        if (m.contains('CASH'))
          'Cash: ${_fmtTk(m.length > 1 ? cashAmount : amountBdt)} handed to ${cashReceiver!.trim()}',
        if (m.contains('CHEQUE'))
          'Cheque: ${_fmtTk(m.length > 1 ? chequeAmount : amountBdt)}, image: $chequeImageUrl',
      ];

      final proofUrl = m.contains('BANK') ? bankReceiptUrl! : (m.contains('CHEQUE') ? chequeImageUrl! : '');
      final ref = m.contains('BANK')
          ? bankTransactionId!.trim()
          : (m.contains('CASH') ? 'CASH - ${cashReceiver!.trim()}' : 'CHEQUE');
      final bankId = (m.contains('BANK') && (bankAccountId ?? '').isNotEmpty) ? bankAccountId : null;
      final nowStr = _nowIso();

      String? orEmpty(String? v, String col) =>
          (v == null || v.isEmpty) ? ((cols[col] ?? true) ? null : '') : v;

      final ins = await queryNeonHttp('''
        INSERT INTO manual_payment_submissions (
          "id", "investmentId", "submittedBy", "status", "amountBdt",
          "bankAccountId", "paymentMethod", "transactionRef", "proofFileUrl",
          "proofMimeType", "notes", "createdAt", "updatedAt"
        ) VALUES (
          \$1, \$2, \$3, 'SUBMITTED'::"ManualPaymentStatus", \$4,
          \$5, \$6${pm.cast}, \$7, \$8,
          \$9, \$10, \$11, \$11
        )
        RETURNING "id"
      ''', [
        _generateUuid(),
        investmentId,
        userId,
        amountBdt,
        bankId,
        method,
        ref,
        orEmpty(proofUrl, 'proofFileUrl'),
        orEmpty(proofUrl.isEmpty ? '' : 'image/jpeg', 'proofMimeType'),
        lines.join('\n'),
        nowStr,
      ]);

      if (ins.isEmpty) {
        return await undo('Could not save your payment details. (${_shortDbError()})');
      }

      await executeNeonHttp('''
        UPDATE investments
        SET "status" = 'PAYMENT_PENDING'::"InvestmentStatus", "paymentPendingAt" = \$1, "updatedAt" = \$1
        WHERE "id" = \$2
      ''', [nowStr, investmentId]);

      return {
        'success': true,
        'investmentId': investmentId,
        'message': 'Investment submitted! It will be active after admin approval.',
      };
    } catch (e) {
      return await undo('Could not save your payment details. Please try again.');
    }
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
  // platform er sadharon 16–22% (age app e shob jaygay eta hardcode chilo).
  // ═════════════════════════════════════════════════════════
  static const double platformReturnMin = 0.16;
  static const double platformReturnMax = 0.22;

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
      'title': r['title']?.toString() ?? '',
      'category': r['category']?.toString() ?? '',
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
      'investorsCount': _toInt(r['investorsCount']),
    };
  }

  // Fetch Full Single Project Detail
  static Future<Map<String, dynamic>> getProjectDetail(String projectIdOrSlug) async {
    try {
      final projRes = await queryNeonHttp('''
        SELECT p."id", p."title", p."slug", p."description", p."category"::text AS "category",
               p."status"::text AS "status", p."riskInfo", p."location", p."fundingGoalBdt",
               p."fundingMinBdt", p."fundedAmountBdt", p."minInvestmentBdt", p."maxInvestmentBdt",
               p."expectedReturnPct", p."returnPctMin", p."returnPctMax",
               p."returnType"::text AS "returnType", p."durationDays",
               p."fundingDeadline", p."startDate", p."endDate", p."coverImageUrl",
               p."imageUrls", bg."name" as "groupName",
               (SELECT COUNT(DISTINCT i."investorProfileId") FROM investments i WHERE i."projectId" = p."id") as "investorsCount"
        FROM projects p
        LEFT JOIN business_groups bg ON p."groupId" = bg."id"
        WHERE (p."id" = \$1 OR p."slug" = \$1)
          AND p."status"::text IN $_publicProjectStatuses
      ''', [projectIdOrSlug]);

      if (projRes.isEmpty) {
        return _lastConnectionError != null ? {'error': 'network'} : {};
      }

      final r = projRes.first;
      final projectId = r['id'].toString();

      final goal = _toDouble(r['fundingGoalBdt'], 1.0);
      final funded = _toDouble(r['fundedAmountBdt']);

      final coverUrl = _projectImage(r['coverImageUrl']);
      final List<String> imageUrls = [if (coverUrl.isNotEmpty) coverUrl];
      for (final img in _parseTextArray(r['imageUrls'])) {
        final formatted = _projectImage(img);
        if (formatted.isNotEmpty && !imageUrls.contains(formatted)) imageUrls.add(formatted);
      }

      final deadlineStr = r['fundingDeadline']?.toString() ?? '';
      final range = projectReturnRange(r);

      final extra = await Future.wait([
        queryNeonHttp('''
          SELECT "id", "bankName", "accountName", "accountNumber", "branchName",
                 "routingNumber", "swiftCode", "mobileNumber", "email", "branchAddress"
          FROM project_bank_accounts
          WHERE "projectId" = \$1 AND "isActive" = true
          ORDER BY "createdAt" ASC
        ''', [projectId]),
        // Ei project er prokashito update (website e admin je gulo dey)
        queryNeonHttp('''
          SELECT u."id", u."title", u."content", u."type"::text AS "type", u."createdAt"
          FROM project_updates u
          WHERE u."projectId" = \$1 AND u."isPublished" = true
          ORDER BY u."createdAt" DESC
          LIMIT 20
        ''', [projectId]),
      ]);
      final bankRes = extra[0];

      // Tarikh raw (ISO) pathai — page nijer bhashay sajabe; na thakle ''
      String dateOrEmpty(dynamic v) => v?.toString() ?? '';

      return {
        'id': projectId,
        'title': r['title']?.toString() ?? '',
        'slug': r['slug']?.toString() ?? '',
        'description': r['description']?.toString() ?? '',
        'category': r['category']?.toString() ?? '',
        'status': r['status']?.toString() ?? '',
        'riskInfo': r['riskInfo']?.toString() ?? '',
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
          'createdAt': u['createdAt']?.toString() ?? '',
        }).toList(),
        'coverImageUrl': coverUrl,
        'imageUrls': imageUrls,
        'groupName': r['groupName']?.toString() ?? '',
        'investorsCount': _toInt(r['investorsCount']),
        'remainingBdt': (goal - funded).clamp(0.0, double.infinity).toDouble(),
        'progress': goal > 0 ? (funded / goal).clamp(0.0, 1.0).toDouble() : 0.0,
        'daysLeft': _daysLeft(deadlineStr),
        'bankAccounts': bankRes.map(_mapProjectBank).toList(),
      };
    } catch (e) {
      debugPrint("Get Project Detail Error: $e");
      return {};
    }
  }

  // Fetch Projects Data
  static Future<Map<String, dynamic>> getProjectsData() async {
    try {
      final results = await Future.wait([
        queryNeonHttp('''
          SELECT p."id", p."title", p."category"::text AS "category", p."description", p."fundingGoalBdt",
                 p."fundedAmountBdt", p."minInvestmentBdt", p."expectedReturnPct",
                 p."returnPctMin", p."returnPctMax", p."durationDays",
                 p."coverImageUrl", p."status"::text AS "status", p."location", p."fundingDeadline",
                 (SELECT COUNT(DISTINCT i."investorProfileId") FROM investments i WHERE i."projectId" = p."id") as "investorsCount"
          FROM projects p
          WHERE p."status"::text IN $_publicProjectStatuses
          ORDER BY (p."status"::text = 'FUNDRAISING') DESC, p."createdAt" DESC
        '''),
        queryNeonHttp('''
          SELECT u."id", u."title", u."content", u."type"::text AS "type", u."createdAt", p."title" as "projectTitle"
          FROM project_updates u
          JOIN projects p ON u."projectId" = p."id"
          WHERE u."isPublished" = true
          ORDER BY u."createdAt" DESC
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
            (SELECT COUNT(*) FROM investments i JOIN investor_profiles p ON i."investorProfileId" = p."id"
             WHERE p."userId" = \$1 AND i."status"::text IN ('ACTIVE', 'MATURED', 'COMPLETED')) as active_inv_count,
            (SELECT COALESCE(SUM(i."amountBdt"), 0) FROM investments i JOIN investor_profiles p ON i."investorProfileId" = p."id"
             WHERE p."userId" = \$1 AND i."status"::text IN ('ACTIVE', 'MATURED', 'COMPLETED')) as total_invested_amt,
            (SELECT COUNT(*) FROM investments i JOIN investor_profiles p ON i."investorProfileId" = p."id"
             WHERE p."userId" = \$1 AND i."status"::text IN ('PENDING', 'PAYMENT_PENDING')
             AND NOT EXISTS (SELECT 1 FROM manual_payment_submissions m WHERE m."investmentId" = i."id" AND m."status"::text IN ('REJECTED', 'APPROVED'))) as pending_tx_count,
            (SELECT COALESCE(SUM(i."amountBdt"), 0) FROM investments i JOIN investor_profiles p ON i."investorProfileId" = p."id"
             WHERE p."userId" = \$1 AND i."status"::text IN ('PENDING', 'PAYMENT_PENDING')
             AND NOT EXISTS (SELECT 1 FROM manual_payment_submissions m WHERE m."investmentId" = i."id" AND m."status"::text IN ('REJECTED', 'APPROVED'))) as pending_inv_amt,
            (SELECT COALESCE(SUM(gi."amountBdt"), 0) FROM group_investments gi
             WHERE gi."investorUserId" = \$1 AND gi."status"::text IN ('ACTIVE', 'COMPLETED')) as group_invested_amt,
            (SELECT COUNT(*) FROM group_investments gi
             WHERE gi."investorUserId" = \$1 AND gi."status"::text IN ('ACTIVE', 'COMPLETED')) as active_group_count,
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
          ORDER BY p."createdAt" DESC
          LIMIT 5;
        '''),

        // 3. Recent investments
        queryNeonHttp('''
          SELECT i."id", pr."title", i."amountBdt", i."expectedReturnBdt", i."status"::text AS "status", i."createdAt"
          FROM investments i
          JOIN investor_profiles p ON i."investorProfileId" = p."id"
          JOIN projects pr ON i."projectId" = pr."id"
          WHERE p."userId" = \$1
          ORDER BY i."createdAt" DESC
          LIMIT 5;
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
      }

      final recentInvestments = results[2].map((row) {
        return {
          'id': row['id'].toString(),
          'title': row['title']?.toString() ?? 'Investment',
          'amountBdt': _toDouble(row['amountBdt']),
          'expectedReturnBdt': _toDouble(row['expectedReturnBdt']),
          'status': row['status']?.toString() ?? 'PENDING',
          'createdAt': row['createdAt']?.toString() ?? '',
        };
      }).toList();

      return {
        'avatarUrl': avatarUrl,
        'unreadNotificationCount': unreadNotifCount,
        'totalInvested': projectInvested + groupInvested,
        'projectInvested': projectInvested,
        'groupInvested': groupInvested,
        'activeInvestmentsCount': activeProjCount + activeGroupCount,
        'activeGroupCount': activeGroupCount,
        'pendingTransactionsCount': pendingProjTxCount + pendingGroupCount,
        'pendingInvestmentsAmount': pendingProjAmt + pendingGroupAmt,
        'totalReturns': totalReturns,
        'openProjects': results[1].map(_mapProjectCard).toList(),
        'recentInvestments': recentInvestments,
      };
    } catch (e) {
      debugPrint("Get Dashboard Summary Error: $e");
      return {};
    }
  }

  // ═════════════════════════════════════════════════════════
  // NOTIFICATIONS
  // ═════════════════════════════════════════════════════════
  /// Shesh request ta server e pouchate pareni kina (khali list mane
  /// "kichu nei" naki "net nei" — sheta alada korar jonno)
  static bool get lastRequestFailed => _lastConnectionError != null;

  /// Notun theke purono. [limit] — ekbare koyta anbo.
  /// Fail hole khali list dey; tokhon [lastRequestFailed] true thake.
  static Future<List<Map<String, dynamic>>> getNotificationsData(String userId, {int limit = 100}) async {
    if (userId.isEmpty) return [];
    try {
      final res = await queryNeonHttp('''
        SELECT n."id", n."title", n."body", n."type"::text AS "type", n."isRead", n."createdAt"
        FROM notifications n
        WHERE n."userId" = \$1
        ORDER BY n."createdAt" DESC
        LIMIT \$2
      ''', [userId, limit]);

      return res.map((r) {
        return <String, dynamic>{
          'id': r['id'].toString(),
          'title': r['title']?.toString() ?? '',
          'body': r['body']?.toString() ?? '',
          'type': r['type']?.toString() ?? 'SYSTEM',
          'isRead': (r['isRead'] as bool?) ?? false,
          'createdAt': r['createdAt']?.toString() ?? '',
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

        if (cat == 'PAYMENT_RECEIPT') {
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
                 sub."rejectionReason" AS "subReason", sub."createdAt" AS "subCreatedAt"
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
        final receiptNo = rawReceipt.isNotEmpty
            ? rawReceipt
            : 'GRP-${id.substring(0, min(8, id.length)).toUpperCase()}';
        final createdAt = r['createdAt']?.toString() ?? '';
        final groupName = r['groupName']?.toString() ?? 'Business Group';
        final tierName = r['tierName']?.toString() ?? 'Tier';
        final title = '$groupName — $tierName';

        return <String, dynamic>{
          'id': id,
          'name': 'Investment Receipt — $title',
          'category': 'GROUP_INVESTMENT_RECEIPT',
          'certificateNo': receiptNo,
          'issuedDate': createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt,
          'createdAt': createdAt,
          'status': 'CONFIRMED',
          'investmentStatus': r['status']?.toString() ?? 'ACTIVE',
          'amountInvested': _toDouble(r['amountBdt']),
          'groupName': groupName,
          'entityName': r['entityName']?.toString() ?? '',
          'tierName': tierName,
          'projectTitle': title,
          'expectedReturnPct': _normalizePct(r['expectedReturnPct'], 0.15),
          'durationMonths': _toInt(r['durationMonths'], 12),
          'userName': r['name']?.toString() ?? 'Investor',
          'userEmail': r['email']?.toString() ?? '',
          'userPhone': r['phone']?.toString(),
          'verifyUrl': '$websiteBaseUrl/verify/$receiptNo',
        };
      }).toList();
    } catch (e) {
      debugPrint("Get Group Website Certificates Error: $e");
      return [];
    }
  }

  static Future<void> _ensureReceiptNumbersExist() async {
    try {
      // 1. Auto-activate investments that have approved manual payment submissions
      await executeNeonHttp('''
        UPDATE investments
        SET "status" = 'ACTIVE'::"InvestmentStatus", "activatedAt" = COALESCE("activatedAt", NOW())
        WHERE "status"::text IN ('PENDING', 'PAYMENT_PENDING')
          AND "id" IN (
            SELECT "investmentId" FROM manual_payment_submissions WHERE "status"::text = 'APPROVED'
          )
      ''');

      // 2. Receipt number na thakle ek query te boshai (age protita row er jonno alada query hoto)
      await executeNeonHttp('''
        UPDATE investments
        SET "receiptNumber" = 'BC-' || UPPER(SUBSTRING("id" FROM 1 FOR 12))
        WHERE "receiptNumber" IS NULL OR "receiptNumber" = ''
      ''');

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
               sub."reason" AS "subReason"
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
          'groupName': r['groupName']?.toString() ?? 'Business Group',
          'entityName': r['entityName']?.toString() ?? 'Group Entity',
          'tierName': r['tierName']?.toString() ?? 'Tier',
          'amountBdt': _toDouble(r['amountBdt']),
          'plotNumber': r['plotNumber']?.toString() ?? '',
          'plotSizeSqft': _toDouble(r['plotSizeSqft']),
          'sharePercentage': _toDouble(r['sharePercentage']),
          'status': r['status']?.toString() ?? 'PENDING',
          'createdAt': r['createdAt']?.toString() ?? '',
          'expectedReturnPct': _normalizePct(r['expectedReturnPct']),
          'durationMonths': _toInt(r['durationMonths']),
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
        SELECT "id", "minAmountBdt", "maxAmountBdt", "isActive"
        FROM group_tiers
        WHERE "id" = \$1
      ''', [tierId]);

      if (tierRes.isEmpty) {
        return {
          'success': false,
          'message': _lastConnectionError != null ? _connectionErrorMsg() : 'Investment tier not found.',
        };
      }

      final t = tierRes.first;
      if (t['isActive'] == false) {
        return {'success': false, 'message': 'This tier is not open for investment right now.'};
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

      if (ins.isEmpty) return {'success': false, 'message': _connectionErrorMsg()};

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
  // GROUP INVEST + PAYMENT — Bank / Cash / Cheque (project er motoi)
  // group_investment_payments e SUBMITTED → group investment PAYMENT_PENDING.
  // Admin approve korle ACTIVE (website e).
  // ═════════════════════════════════════════════════════════

  /// App er check server eo — kichu miss gele kichui save hobe na
  static String? _checkPaymentParts({
    required Set<String> m,
    required double amountBdt,
    required double bankAmount,
    required double cashAmount,
    required double chequeAmount,
    String? bankTransactionId,
    String? bankReceiptUrl,
    String? cashReceiver,
    String? chequeImageUrl,
  }) {
    if (m.isEmpty) return 'Please choose a payment method.';
    if (amountBdt <= 0) return 'Please enter the amount.';
    if (m.contains('BANK') &&
        ((bankTransactionId ?? '').trim().isEmpty || (bankReceiptUrl ?? '').isEmpty)) {
      return 'Bank payment needs the transaction number and receipt image.';
    }
    if (m.contains('CASH') && (cashReceiver ?? '').trim().isEmpty) {
      return 'Please select who received the cash.';
    }
    if (m.contains('CHEQUE') && (chequeImageUrl ?? '').isEmpty) {
      return 'Please upload the cheque image.';
    }
    final parts = (m.contains('BANK') ? bankAmount : 0) +
        (m.contains('CASH') ? cashAmount : 0) +
        (m.contains('CHEQUE') ? chequeAmount : 0);
    if (m.length > 1 && (parts - amountBdt).abs() > 0.5) {
      return 'The split amounts must add up to the total.';
    }
    return null;
  }

  /// group_investment_payments e ekta SUBMITTED row (column/enum dekhe dekhe)
  static Future<Map<String, dynamic>> _insertGroupPayment({
    required String groupInvestmentId,
    required String userId,
    required double amountBdt,
    required Set<String> m,
    required double bankAmount,
    required double cashAmount,
    required double chequeAmount,
    String? bankAccountId,
    String? tierBankAccountId,
    String? bankAccountLabel,
    String? bankTransactionId,
    String? bankReceiptUrl,
    String? cashReceiver,
    String? chequeImageUrl,
  }) async {
    const table = 'group_investment_payments';
    final metas = await Future.wait([_paymentMethodMeta(table), _columnsOf(table)]);
    final pm = metas[0] as ({String cast, Set<String> labels});
    final cols = metas[1] as Map<String, bool>;
    if (cols.isEmpty) return {'success': false, 'message': _connectionErrorMsg()};

    String pick(List<String> candidates, String fallback) {
      if (pm.labels.isEmpty) return candidates.first;
      for (final c in candidates) {
        if (pm.labels.contains(c)) return c;
      }
      return pm.labels.contains(fallback) ? fallback : pm.labels.first;
    }

    final String method;
    if (m.length > 1) {
      method = pick(['MIXED', 'MULTIPLE', 'OTHER'], m.contains('BANK') ? 'BANK_TRANSFER' : 'CASH');
    } else if (m.contains('BANK')) {
      method = pick(['BANK_TRANSFER', 'BANK_DEPOSIT', 'BANK'], 'BANK_TRANSFER');
    } else if (m.contains('CASH')) {
      method = pick(['CASH', 'CASH_DEPOSIT', 'CASH_PAYMENT'], 'BANK_TRANSFER');
    } else {
      method = pick(['CHEQUE', 'CHECK', 'BANK_CHEQUE'], 'BANK_TRANSFER');
    }

    final lines = <String>[
      'Payment: ${[if (m.contains('BANK')) 'Bank', if (m.contains('CASH')) 'Cash', if (m.contains('CHEQUE')) 'Cheque'].join(' + ')}'
          ' — total ${_fmtTk(amountBdt)}',
      if (m.contains('BANK'))
        'Bank: ${_fmtTk(m.length > 1 ? bankAmount : amountBdt)}'
            '${(bankAccountLabel ?? '').isNotEmpty ? ' to $bankAccountLabel' : ''}'
            ', TRX ${bankTransactionId!.trim()}, receipt: $bankReceiptUrl',
      if (m.contains('CASH'))
        'Cash: ${_fmtTk(m.length > 1 ? cashAmount : amountBdt)} handed to ${cashReceiver!.trim()}',
      if (m.contains('CHEQUE'))
        'Cheque: ${_fmtTk(m.length > 1 ? chequeAmount : amountBdt)}, image: $chequeImageUrl',
    ];

    final proofUrl = m.contains('BANK') ? bankReceiptUrl! : (m.contains('CHEQUE') ? chequeImageUrl! : '');
    final ref = m.contains('BANK')
        ? bankTransactionId!.trim()
        : (m.contains('CASH') ? 'CASH - ${cashReceiver!.trim()}' : 'CHEQUE');

    // Bank na hole bankAccountId khali — kintu column NOT NULL hole tier er account
    String? bankId = (m.contains('BANK') && (bankAccountId ?? '').isNotEmpty) ? bankAccountId : null;
    if (bankId == null && cols.containsKey('bankAccountId') && cols['bankAccountId'] == false) {
      bankId = (tierBankAccountId ?? '').isNotEmpty ? tierBankAccountId : null;
      if (bankId == null) {
        return {'success': false, 'message': 'Payment account for this tier is not set yet. Please contact support.'};
      }
    }

    String? orEmpty(String? v, String col) =>
        (v == null || v.isEmpty) ? ((cols[col] ?? true) ? null : '') : v;

    final nowStr = _nowIso();
    final names = <String>[];
    final values = <String>[];
    final params = <dynamic>[];
    void add(String col, dynamic v, {String cast = '', String? raw}) {
      if (!cols.containsKey(col)) return;
      names.add('"$col"');
      if (raw != null) {
        values.add(raw);
      } else {
        params.add(v);
        values.add('\$${params.length}$cast');
      }
    }

    add('id', _generateUuid());
    add('groupInvestmentId', groupInvestmentId);
    add('submittedBy', userId);
    add('status', null, raw: "'SUBMITTED'::\"ManualPaymentStatus\"");
    add('amountBdt', amountBdt);
    add('bankAccountId', bankId);
    add('paymentMethod', method, cast: pm.cast);
    add('transactionRef', orEmpty(ref, 'transactionRef'));
    add('proofFileUrl', orEmpty(proofUrl, 'proofFileUrl'));
    add('proofMimeType', orEmpty(proofUrl.isEmpty ? '' : 'image/jpeg', 'proofMimeType'));
    add('notes', lines.join('\n'));
    add('createdAt', nowStr);
    add('updatedAt', nowStr);

    final ins = await queryNeonHttp('''
      INSERT INTO group_investment_payments (${names.join(', ')})
      VALUES (${values.join(', ')})
      RETURNING "id"
    ''', params);

    if (ins.isEmpty) {
      return {'success': false, 'message': 'Could not save your payment details. (${_shortDbError()})'};
    }

    await executeNeonHttp('''
      UPDATE group_investments
      SET "status" = 'PAYMENT_PENDING'::"GroupInvestmentStatus", "updatedAt" = \$1
      WHERE "id" = \$2
    ''', [nowStr, groupInvestmentId]);

    return {'success': true};
  }

  /// Notun group investment + payment ek shathe (Browse Groups theke)
  static Future<Map<String, dynamic>> groupInvestWithPayment({
    required String userId,
    required String tierId,
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
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    final m = methods.toSet();
    final problem = _checkPaymentParts(
      m: m,
      amountBdt: amountBdt,
      bankAmount: bankAmount,
      cashAmount: cashAmount,
      chequeAmount: chequeAmount,
      bankTransactionId: bankTransactionId,
      bankReceiptUrl: bankReceiptUrl,
      cashReceiver: cashReceiver,
      chequeImageUrl: chequeImageUrl,
    );
    if (problem != null) return {'success': false, 'message': problem};

    // Tier er nijer bank account (bankAccountId NOT NULL hole lagbe)
    final tier = await queryNeonHttp(
        'SELECT "bankAccountId" FROM group_tiers WHERE "id" = \$1', [tierId]);
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
      final res = await _insertGroupPayment(
        groupInvestmentId: gid,
        userId: userId,
        amountBdt: amountBdt,
        m: m,
        bankAmount: bankAmount,
        cashAmount: cashAmount,
        chequeAmount: chequeAmount,
        bankAccountId: bankAccountId,
        tierBankAccountId: tierBankId,
        bankAccountLabel: bankAccountLabel,
        bankTransactionId: bankTransactionId,
        bankReceiptUrl: bankReceiptUrl,
        cashReceiver: cashReceiver,
        chequeImageUrl: chequeImageUrl,
      );
      if (res['success'] != true) return await undo(res['message']?.toString() ?? 'Could not save your payment.');
      return {
        'success': true,
        'groupInvestmentId': gid,
        'message': 'Investment submitted! It will be active after admin approval.',
      };
    } catch (e) {
      return await undo('Could not save your payment details. Please try again.');
    }
  }

  /// Age theke thaka (PAYMENT_PENDING / proof bad pora) group investment er payment
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
  }) async {
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};
    final m = methods.toSet();
    final problem = _checkPaymentParts(
      m: m,
      amountBdt: amountBdt,
      bankAmount: bankAmount,
      cashAmount: cashAmount,
      chequeAmount: chequeAmount,
      bankTransactionId: bankTransactionId,
      bankReceiptUrl: bankReceiptUrl,
      cashReceiver: cashReceiver,
      chequeImageUrl: chequeImageUrl,
    );
    if (problem != null) return {'success': false, 'message': problem};

    try {
      final check = await queryNeonHttp('''
        SELECT gi."status"::text AS "status", gi."amountBdt", gt."bankAccountId" AS "tierBankId",
               EXISTS (
                 SELECT 1 FROM group_investment_payments x
                 WHERE x."groupInvestmentId" = gi."id" AND x."status"::text = 'SUBMITTED'
               ) AS "hasPending"
        FROM group_investments gi
        JOIN group_tiers gt ON gt."id" = gi."tierId"
        WHERE gi."id" = \$1 AND gi."investorUserId" = \$2
      ''', [groupInvestmentId, userId]);

      if (check.isEmpty) {
        return {
          'success': false,
          'message': _lastConnectionError != null ? _connectionErrorMsg() : 'Group investment not found.',
        };
      }
      final row = check.first;
      final st = row['status']?.toString() ?? '';
      if (st != 'PENDING' && st != 'PAYMENT_PENDING') {
        return {'success': false, 'message': 'This investment is not awaiting payment.'};
      }
      if (row['hasPending'] == true || row['hasPending']?.toString() == 'true') {
        return {'success': false, 'message': 'A payment is already under review.'};
      }
      // Taka investment er shoman-i hote hobe
      final invAmount = _toDouble(row['amountBdt']);
      if (invAmount > 0 && (invAmount - amountBdt).abs() > 0.5) {
        return {'success': false, 'message': 'Amount must be ${_fmtTk(invAmount)}.'};
      }

      final res = await _insertGroupPayment(
        groupInvestmentId: groupInvestmentId,
        userId: userId,
        amountBdt: amountBdt,
        m: m,
        bankAmount: bankAmount,
        cashAmount: cashAmount,
        chequeAmount: chequeAmount,
        bankAccountId: bankAccountId,
        tierBankAccountId: row['tierBankId']?.toString(),
        bankAccountLabel: bankAccountLabel,
        bankTransactionId: bankTransactionId,
        bankReceiptUrl: bankReceiptUrl,
        cashReceiver: cashReceiver,
        chequeImageUrl: chequeImageUrl,
      );
      if (res['success'] != true) return res;
      return <String, dynamic>{
        'success': true,
        'message': 'Payment submitted! It will be checked by admin.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Could not save your payment details. Please try again.'};
    }
  }

  /// Neon er error body theke shudhu "message" ta
  static String _shortDbError() {
    final e = _lastConnectionError ?? '';
    final m = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(e);
    final msg = m?.group(1) ?? e;
    if (msg.isEmpty) return 'unknown error';
    if (e.contains('HTTP 413') || msg.toLowerCase().contains('too large')) {
      return 'photo is too large';
    }
    return msg.length > 140 ? '${msg.substring(0, 140)}…' : msg;
  }



}