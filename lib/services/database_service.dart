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

  // Register User matching exact Prisma 'users' & 'investor_profiles' tables
  static Future<Map<String, dynamic>> registerUser({
    required String name,
    required String email,
    required String phone,
    required String password,
    String? nidNumber,
    String? nomineeNidNumber,
    String? nomineeRelation,
  }) async {
    try {
      final hashedPassword = hashPassword(password);
      final cleanEmail = email.trim().toLowerCase();
      final cleanPhone = phone.trim();

      final userId = _generateUuid();
      final profileId = _generateUuid();
      final walletId = _generateUuid();
      final nowStr = _nowIso();

      // Single Atomic SQL Statement inserting User, InvestorProfile & Wallet in 1 Round-Trip!
      final res = await queryNeonHttp('''
        WITH existing_check_user AS (
          SELECT "id", "email", "phone" FROM users WHERE LOWER("email") = LOWER(\$2) OR ("phone" = \$3 AND \$3 != '') LIMIT 1
        ),
        existing_check_nid AS (
          SELECT "nationalId" FROM investor_profiles WHERE "nationalId" = \$8 AND \$8 IS NOT NULL LIMIT 1
        ),
        new_user AS (
          INSERT INTO users (
            "id", "email", "passwordHash", "name", "phone", "role", "status", "emailVerified", "createdAt", "updatedAt"
          )
          SELECT \$1, \$2, \$4, \$5, \$3, 'INVESTOR'::"UserRole", 'ACTIVE'::"UserStatus", true, \$6, \$6
          WHERE NOT EXISTS (SELECT 1 FROM existing_check_user) AND NOT EXISTS (SELECT 1 FROM existing_check_nid)
          RETURNING "id"
        ),
        new_profile AS (
          INSERT INTO investor_profiles (
            "id", "userId", "nationalId", "nomineeNationalId", "nomineeRelation", "country", "createdAt", "updatedAt"
          )
          SELECT \$7, \$1, \$8, \$9, \$10, 'BD', \$6, \$6
          WHERE EXISTS (SELECT 1 FROM new_user)
          ON CONFLICT ("userId") DO UPDATE SET
            "nationalId" = COALESCE(EXCLUDED."nationalId", investor_profiles."nationalId"),
            "nomineeNationalId" = COALESCE(EXCLUDED."nomineeNationalId", investor_profiles."nomineeNationalId"),
            "nomineeRelation" = COALESCE(EXCLUDED."nomineeRelation", investor_profiles."nomineeRelation"),
            "updatedAt" = EXCLUDED."updatedAt"
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
        userId,
        cleanEmail,
        cleanPhone.isEmpty ? null : cleanPhone,
        hashedPassword,
        name.trim(),
        nowStr,
        profileId,
        (nidNumber?.trim().isEmpty ?? true) ? null : nidNumber?.trim(),
        (nomineeNidNumber?.trim().isEmpty ?? true) ? null : nomineeNidNumber?.trim(),
        (nomineeRelation?.trim().isEmpty ?? true) ? null : nomineeRelation?.trim(),
        walletId,
      ]);

      if (res.isNotEmpty) {
        final row = res.first;
        final existingEmail = row['existing_email']?.toString();
        final existingPhone = row['existing_phone']?.toString();
        final existingNid = row['existing_nid']?.toString();
        final createdCount = _toInt(row['created_count']);

        if (existingNid != null && existingNid.isNotEmpty) {
          return {
            'success': false,
            'message': 'An account with this NID number already exists.',
          };
        }

        if (existingEmail != null && existingEmail.isNotEmpty) {
          if (existingPhone == cleanPhone && cleanPhone.isNotEmpty) {
            return {
              'success': false,
              'message': 'An account with this phone number already exists. Please log in.',
            };
          }
          return {
            'success': false,
            'message': 'An account with this email already exists. Please log in.',
          };
        }

        if (createdCount > 0) {
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
        }
      }

      return {
        'success': false,
        'message': 'Could not create account. Please check internet connection.',
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
      final cleanInput = email.trim();

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
          'email': row['email']?.toString() ?? '',
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

  // Send Forgot Password OTP
  // OTP ar app e ferot pathano hoy na — shudhu email e jay.
  static Future<Map<String, dynamic>> sendForgotPasswordOtp(String email) async {
    try {
      final cleanEmail = email.trim().toLowerCase();

      final apiKey = DbConfig.resendApiKey.trim();
      if (apiKey.isEmpty || apiKey == 'your_resend_api_key') {
        return {
          'success': false,
          'message': 'Email service is not configured. Please contact support.',
        };
      }

      final userRes = await queryNeonHttp(
          'SELECT "id", "name" FROM users WHERE LOWER("email") = LOWER(\$1)',
          [cleanEmail]);

      if (userRes.isEmpty) {
        return {
          'success': false,
          'message': _lastConnectionError != null
              ? _connectionErrorMsg()
              : 'No registered account found with this email address.',
        };
      }

      final userName = userRes.first['name']?.toString() ?? 'Investor';
      final otp = (100000 + Random.secure().nextInt(900000)).toString();

      await executeNeonHttp('''
        CREATE TABLE IF NOT EXISTS password_reset_tokens (
          "id" TEXT PRIMARY KEY,
          "email" TEXT NOT NULL,
          "token" TEXT NOT NULL,
          "expiresAt" TIMESTAMP WITH TIME ZONE NOT NULL,
          "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL
        );
      ''');

      // Purono OTP gulo bad — shudhu shesh ta kaj korbe
      await executeNeonHttp(
          'DELETE FROM password_reset_tokens WHERE LOWER("email") = LOWER(\$1)',
          [cleanEmail]);

      final now = DateTime.now().toUtc();
      final saved = await executeNeonHttp('''
        INSERT INTO password_reset_tokens ("id", "email", "token", "expiresAt", "createdAt")
        VALUES (\$1, \$2, \$3, \$4, \$5)
      ''', [
        _generateUuid(),
        cleanEmail,
        otp,
        now.add(const Duration(minutes: 15)).toIso8601String(),
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
          'from': 'Biniyog Club <onboarding@resend.dev>',
          'to': [cleanEmail],
          'subject': 'Reset Your Biniyog Club Password',
          'html': '''
            <div style="font-family: Arial, sans-serif; padding: 24px; background-color: #f4f7f6;">
              <div style="max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; padding: 24px; border: 1px solid #e2e8f0;">
                <h2 style="color: #047857; margin-top: 0;">Biniyog Club</h2>
                <p style="color: #334155; font-size: 14px;">Hello <strong>$userName</strong>,</p>
                <p style="color: #334155; font-size: 14px;">You requested to reset your password. Here is your 6-digit OTP code:</p>
                <div style="background-color: #f0fdf4; border: 1px solid #bbf7d0; padding: 16px; text-align: center; border-radius: 12px; margin: 20px 0;">
                  <span style="font-size: 32px; font-weight: bold; letter-spacing: 6px; color: #047857;">$otp</span>
                </div>
                <p style="color: #64748b; font-size: 12px;">This OTP code is valid for 15 minutes. If you did not request a password reset, please ignore this email.</p>
              </div>
            </div>
          ''',
        }),
      ).timeout(const Duration(seconds: 15));

      if (mailRes.statusCode < 200 || mailRes.statusCode >= 300) {
        debugPrint("Resend Error ${mailRes.statusCode}: ${mailRes.body}");
        return {
          'success': false,
          'message': 'Could not send the OTP email. Please try again later.',
        };
      }

      return {
        'success': true,
        'message': 'OTP sent successfully to $cleanEmail!',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  // Verify Reset OTP Code
  static Future<Map<String, dynamic>> verifyResetOtp(String email, String otp) async {
    try {
      final cleanEmail = email.trim().toLowerCase();
      final cleanOtp = otp.trim();

      final res = await queryNeonHttp('''
        SELECT "id", "expiresAt" FROM password_reset_tokens
        WHERE LOWER("email") = LOWER(\$1) AND "token" = \$2
        ORDER BY "createdAt" DESC
        LIMIT 1
      ''', [cleanEmail, cleanOtp]);

      if (res.isEmpty) {
        return {
          'success': false,
          'message': _lastConnectionError != null
              ? _connectionErrorMsg()
              : 'Invalid OTP code. Please check and try again.',
        };
      }

      final expiresAt = DateTime.tryParse(res.first['expiresAt']?.toString() ?? '');
      if (expiresAt == null || DateTime.now().toUtc().isAfter(expiresAt)) {
        return {
          'success': false,
          'message': 'OTP code has expired. Please request a new one.',
        };
      }

      return {
        'success': true,
        'message': 'OTP verified successfully!',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  // Reset Password using OTP
  static Future<Map<String, dynamic>> resetPasswordWithOtp({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    try {
      final verifyRes = await verifyResetOtp(email, otp);
      if (verifyRes['success'] != true) {
        return verifyRes;
      }

      final cleanEmail = email.trim().toLowerCase();

      final ok = await executeNeonHttp('''
        UPDATE users
        SET "passwordHash" = \$1, "updatedAt" = \$2
        WHERE LOWER("email") = LOWER(\$3)
      ''', [hashPassword(newPassword), _nowIso(), cleanEmail]);

      if (!ok) return {'success': false, 'message': _connectionErrorMsg()};

      await executeNeonHttp(
          'DELETE FROM password_reset_tokens WHERE LOWER("email") = LOWER(\$1)',
          [cleanEmail]);

      return {
        'success': true,
        'message': 'Password reset successful! Please log in with your new password.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
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
  // KYC
  // ═════════════════════════════════════════════════════════

  /// Ei status e thakle notun kore KYC jama dewa jabe na
  static const Set<String> _kycLockedStatuses = {
    'SUBMITTED',
    'UNDER_REVIEW',
    'VERIFIED',
    'APPROVED',
  };

  /// kyc table e kon kon column ache (ekbar jene rakhi). Website er schema te
  /// date of birth, permanent address eshob thakle sheta-o save hobe — na
  /// thakle chupchap bad (age egula form e niye fele dewa hoto).
  static Set<String>? _kycColumns;

  static Future<Set<String>> _getKycColumns() async {
    if (_kycColumns != null) return _kycColumns!;
    final res = await queryNeonHttp('''
      SELECT column_name FROM information_schema.columns
      WHERE table_name = 'kyc'
    ''');
    final cols = res.map((r) => r['column_name'].toString()).toSet();
    if (cols.isNotEmpty) _kycColumns = cols;
    return cols;
  }

  // Submit Real KYC Application
  static Future<Map<String, dynamic>> submitKycData({
    required String userId,
    required String fullName,
    required String documentType,
    required String documentNumber,
    required String division,
    required String district,
    required String thana,
    required String address,
    required String bankName,
    required String bankAccountNumber,
    required String mobileProvider,
    required String mobileNumber,
    required String nomineeNid,
    required String nomineeRelation,
    String? frontPhotoBase64,
    String? backPhotoBase64,
    String? nomineeFrontBase64,
    String? nomineeBackBase64,
    // Website er schema te column thakle tobei save hoy
    Map<String, String?> extraFields = const {},
  }) async {
    // Login chara KYC na — age "latest user" er naame KYC jama hoye jeto
    if (userId.isEmpty) return {'success': false, 'message': _loginRequiredMsg};

    try {
      final nowStr = _nowIso();

      String docEnum = 'NATIONAL_ID';
      if (documentType.contains('PASSPORT')) {
        docEnum = 'PASSPORT';
      } else if (documentType.contains('DRIVING')) {
        docEnum = 'DRIVING_LICENSE';
      }

      final checks = await Future.wait([
        queryNeonHttp('SELECT "id", "status"::text AS "status" FROM kyc WHERE "userId" = \$1', [userId]),
        // Ek-i document number onno account e already ache kina
        queryNeonHttp('''
          SELECT 1 AS "taken" FROM kyc
          WHERE "documentNumber" = \$1 AND "userId" <> \$2
          LIMIT 1
        ''', [documentNumber, userId]),
      ]);
      if (_lastConnectionError != null) {
        return {'success': false, 'message': _connectionErrorMsg()};
      }

      final existingKyc = checks[0];
      if (checks[1].isNotEmpty) {
        return {
          'success': false,
          'message': 'This document number is already used by another account. Please contact support.',
        };
      }

      final prevStatus = existingKyc.isNotEmpty ? existingKyc.first['status']?.toString() ?? '' : '';
      if (_kycLockedStatuses.contains(prevStatus)) {
        return {
          'success': false,
          'message': prevStatus == 'VERIFIED' || prevStatus == 'APPROVED'
              ? 'Your KYC is already verified.'
              : 'Your KYC is already under review. Please wait for the result.',
        };
      }

      final isNew = existingKyc.isEmpty;
      final kycId = isNew ? _generateUuid() : existingKyc.first['id'].toString();

      // ধাপ ১: tottho save — status ekhono "SUBMITTED" na (notun hole matro row)
      bool ok;
      if (!isNew) {
        ok = await executeNeonHttp('''
          UPDATE kyc SET
            "fullName" = \$1,
            "documentType" = \$2::"KycDocumentType",
            "documentNumber" = \$3,
            "presentAddress" = \$4,
            "presentDivision" = \$5,
            "presentDistrict" = \$6,
            "presentUpazila" = \$7,
            "bankName" = \$8,
            "bankAccountNumber" = \$9,
            "mobileProvider" = \$10,
            "mobileNumber" = \$11,
            "updatedAt" = \$12
          WHERE "id" = \$13 AND "userId" = \$14
        ''', [
          fullName, docEnum, documentNumber, address, division, district, thana,
          bankName, bankAccountNumber, mobileProvider, mobileNumber, nowStr, kycId, userId,
        ]);
      } else {
        ok = await executeNeonHttp('''
          INSERT INTO kyc (
            "id", "userId", "status", "fullName", "documentType", "documentNumber",
            "presentAddress", "presentDivision", "presentDistrict", "presentUpazila",
            "bankName", "bankAccountNumber", "mobileProvider", "mobileNumber",
            "submittedAt", "createdAt", "updatedAt"
          ) VALUES (
            \$1, \$2, 'SUBMITTED'::"KycStatus", \$3, \$4::"KycDocumentType", \$5,
            \$6, \$7, \$8, \$9,
            \$10, \$11, \$12, \$13,
            \$14, \$14, \$14
          )
        ''', [
          kycId, userId, fullName, docEnum, documentNumber, address, division, district, thana,
          bankName, bankAccountNumber, mobileProvider, mobileNumber, nowStr,
        ]);
      }
      if (!ok) return {'success': false, 'message': _connectionErrorMsg()};

      // ধাপ ২: website schema te thaka baki column (DOB, permanent address …)
      final wanted = <String, String>{
        for (final e in extraFields.entries)
          if (e.value != null && e.value!.trim().isNotEmpty) e.key: e.value!.trim(),
      };
      if (wanted.isNotEmpty) {
        final cols = await _getKycColumns();
        final usable = wanted.entries.where((e) => cols.contains(e.key)).toList();
        if (usable.isNotEmpty) {
          final sets = <String>[];
          final params = <dynamic>[];
          for (final e in usable) {
            params.add(e.value);
            sets.add('"${e.key}" = \$${params.length}');
          }
          params.add(kycId);
          await executeNeonHttp(
            'UPDATE kyc SET ${sets.join(', ')} WHERE "id" = \$${params.length}',
            params,
          );
        }
      }

      // ধাপ ৩: chobi — ekta-o fail korle KYC "jama" dhora hobe na
      final docs = <(String, String?)>[
        ('NATIONAL_ID_FRONT', frontPhotoBase64),
        ('NATIONAL_ID_BACK', backPhotoBase64),
        ('NOMINEE_NID_FRONT', nomineeFrontBase64),
        ('NOMINEE_NID_BACK', nomineeBackBase64),
      ];
      for (final (type, data) in docs) {
        if (!await _saveKycDocument(kycId, type, data)) {
          if (isNew) {
            // Notun row muche dei, jate "jama hoyeche kintu chobi nei" obostha na thake
            await executeNeonHttp('DELETE FROM kyc_documents WHERE "kycId" = \$1', [kycId]);
            await executeNeonHttp('DELETE FROM kyc WHERE "id" = \$1', [kycId]);
          }
          return {
            'success': false,
            'message': 'Could not upload your document photos. Please check your internet and try again.',
          };
        }
      }

      // ধাপ ৪: shob thik — ekhon review er jonno pathai
      if (!isNew) {
        final sent = await executeNeonHttp('''
          UPDATE kyc SET "status" = 'SUBMITTED'::"KycStatus", "submittedAt" = \$1, "updatedAt" = \$1
          WHERE "id" = \$2
        ''', [nowStr, kycId]);
        if (!sent) return {'success': false, 'message': _connectionErrorMsg()};
      }

      // Nominee investor profile e (website eikhan thekei dekhay)
      await executeNeonHttp('''
        INSERT INTO investor_profiles ("id", "userId", "nomineeNationalId", "nomineeRelation", "address", "city", "country", "createdAt", "updatedAt")
        VALUES (\$1, \$2, \$3, \$4, \$5, \$6, 'BD', \$7, \$7)
        ON CONFLICT ("userId") DO UPDATE SET
          "nomineeNationalId" = EXCLUDED."nomineeNationalId",
          "nomineeRelation" = EXCLUDED."nomineeRelation",
          "address" = COALESCE(investor_profiles."address", EXCLUDED."address"),
          "city" = COALESCE(investor_profiles."city", EXCLUDED."city"),
          "updatedAt" = EXCLUDED."updatedAt";
      ''', [_generateUuid(), userId, nomineeNid, nomineeRelation, address, district, nowStr]);

      return {
        'success': true,
        'message': 'KYC submitted successfully!',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  // Fetch KYC Status
  // 'error': 'network' thakle server e pouchano jayni — tokhon "NOT_STARTED"
  // dhore niye abar jama dite dibo na.
  static Future<Map<String, dynamic>> getKycStatus(String userId, {String? email}) async {
    if (userId.isEmpty) return {'status': 'NOT_STARTED', 'error': 'login'};

    try {
      final results = await Future.wait([
        queryNeonHttp('''
          SELECT k."id", k."status"::text AS "status", k."documentType"::text AS "documentType",
                 to_jsonb(k) AS "raw"
          FROM kyc k
          WHERE k."userId" = \$1
          LIMIT 1
        ''', [userId]),
        queryNeonHttp('''
          SELECT "nomineeNationalId", "nomineeRelation"
          FROM investor_profiles WHERE "userId" = \$1
        ''', [userId]),
      ]);
      if (_lastConnectionError != null) return {'status': 'NOT_STARTED', 'error': 'network'};

      final prof = results[1].isNotEmpty ? results[1].first : <String, dynamic>{};

      if (results[0].isEmpty) {
        return {
          'status': 'NOT_STARTED',
          'nomineeNid': prof['nomineeNationalId']?.toString() ?? '',
          'nomineeRelation': prof['nomineeRelation']?.toString() ?? '',
        };
      }

      final row = results[0].first;
      final kycId = row['id'].toString();

      Map<String, dynamic> raw = {};
      final r0 = row['raw'];
      if (r0 is Map) {
        raw = Map<String, dynamic>.from(r0);
      } else if (r0 is String) {
        try {
          raw = Map<String, dynamic>.from(jsonDecode(r0) as Map);
        } catch (_) {}
      }
      String f(String k) => raw[k]?.toString() ?? '';

      final docsRes = await queryNeonHttp(
          'SELECT "id", "documentType"::text AS "documentType", "createdAt" FROM kyc_documents WHERE "kycId" = \$1',
          [kycId]);

      final List<Map<String, dynamic>> documents = docsRes.map((d) {
        return <String, dynamic>{
          'id': d['id'].toString(),
          'type': d['documentType']?.toString() ?? '',
          'createdAt': d['createdAt']?.toString() ?? '',
        };
      }).toList();

      final rawStatus = row['status']?.toString() ?? 'NOT_STARTED';

      return {
        'id': kycId,
        'status': rawStatus == 'APPROVED' ? 'VERIFIED' : rawStatus,
        'fullName': f('fullName'),
        'documentType': row['documentType']?.toString() ?? '',
        'documentNumber': f('documentNumber'),
        'address': f('presentAddress'),
        'division': f('presentDivision'),
        'district': f('presentDistrict'),
        'upazila': f('presentUpazila'),
        'bankName': f('bankName'),
        'bankAccountNumber': f('bankAccountNumber'),
        'mobileProvider': f('mobileProvider'),
        'mobileNumber': f('mobileNumber'),
        'dateOfBirth': f('dateOfBirth'),
        'reviewNote': raw['reviewNote']?.toString(),
        'submittedAt': f('submittedAt'),
        'reviewedAt': f('reviewedAt'),
        'nomineeNid': prof['nomineeNationalId']?.toString() ?? '',
        'nomineeRelation': prof['nomineeRelation']?.toString() ?? '',
        // Website schema te thaka baki field (thakle) — resubmit e age theke bhora
        'raw': raw,
        'documents': documents,
      };
    } catch (e) {
      debugPrint("Get KYC Status Error: $e");
      return {'status': 'NOT_STARTED', 'error': 'network'};
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
      final kycRes = await queryNeonHttp(
          'SELECT "status"::text AS "status" FROM kyc WHERE "userId" = \$1',
          [userId]);
      if (kycRes.isEmpty && _lastConnectionError != null) {
        return {'success': false, 'message': _connectionErrorMsg()};
      }
      final kycStatus = kycRes.isNotEmpty ? kycRes.first['status']?.toString() ?? '' : '';
      if (kycStatus != 'VERIFIED' && kycStatus != 'APPROVED') {
        return {
          'success': false,
          'message':
          'KYC verification required. Please complete and get your KYC approved before investing.',
        };
      }

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
          SELECT "id", "name", "email", "phone", "emailVerified", "phoneVerified", "createdAt", "avatarUrl"
          FROM users
          WHERE "id" = \$1
        ''', [activeUserId]),
        queryNeonHttp('''
          SELECT "status"::text AS "status", "fullName", "documentType"::text AS "documentType", "documentNumber",
                 "presentAddress", "presentDivision", "presentDistrict", "presentUpazila",
                 "bankName", "bankAccountNumber", "mobileProvider", "mobileNumber"
          FROM kyc
          WHERE "userId" = \$1
        ''', [activeUserId]),
        queryNeonHttp('''
          SELECT "nationalId", "address", "city", "country", "occupation",
                 "annualIncomeRange", "investmentExperience", "riskTolerance",
                 "nomineeNationalId", "nomineeRelation"
          FROM investor_profiles
          WHERE "userId" = \$1
        ''', [activeUserId]),
      ]);

      final userRes = results[0];
      final kycRes = results[1];
      final profRes = results[2];

      if (userRes.isEmpty) return {};
      final uRow = userRes.first;

      Map<String, dynamic> kycData = {};
      String kycStatus = 'NOT_STARTED';
      if (kycRes.isNotEmpty) {
        final k = kycRes.first;
        kycStatus = k['status']?.toString() ?? 'NOT_STARTED';
        if (kycStatus == 'APPROVED') kycStatus = 'VERIFIED';
        kycData = {
          'fullName': k['fullName']?.toString() ?? '',
          'documentType': k['documentType']?.toString() ?? '',
          'documentNumber': k['documentNumber']?.toString() ?? '',
          'presentAddress': k['presentAddress']?.toString() ?? '',
          'presentDivision': k['presentDivision']?.toString() ?? '',
          'presentDistrict': k['presentDistrict']?.toString() ?? '',
          'presentUpazila': k['presentUpazila']?.toString() ?? '',
          'bankName': k['bankName']?.toString() ?? '',
          'bankAccountNumber': k['bankAccountNumber']?.toString() ?? '',
          'mobileProvider': k['mobileProvider']?.toString() ?? '',
          'mobileNumber': k['mobileNumber']?.toString() ?? '',
        };
      }

      String kyc(String key) => kycData[key]?.toString() ?? '';
      final p = profRes.isNotEmpty ? profRes.first : <String, dynamic>{};

      // Kono banano default nei — user ja dey ni, ta khali ('') thake
      String prof(String key) => p[key]?.toString().trim() ?? '';

      final profMap = <String, String>{
        'nationalId': kyc('documentNumber').isNotEmpty ? kyc('documentNumber') : prof('nationalId'),
        'documentType': kyc('documentType'),
        'fullName': kyc('fullName'),
        'address': kyc('presentAddress').isNotEmpty ? kyc('presentAddress') : prof('address'),
        'city': kyc('presentDistrict').isNotEmpty ? kyc('presentDistrict') : prof('city'),
        'division': kyc('presentDivision'),
        'district': kyc('presentDistrict'),
        'thana': kyc('presentUpazila'),
        'bankName': kyc('bankName'),
        'bankAccountNumber': kyc('bankAccountNumber'),
        'mobileProvider': kyc('mobileProvider'),
        'mobileNumber': kyc('mobileNumber'),
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
        'email': uRow['email']?.toString() ?? '',
        'phone': uRow['phone']?.toString() ?? '',
        'emailVerified': (uRow['emailVerified'] as bool?) ?? false,
        'phoneVerified': (uRow['phoneVerified'] as bool?) ?? false,
        'createdAt': uRow['createdAt']?.toString() ?? '',
        'avatarUrl': rawAvatar != null && rawAvatar.isNotEmpty ? formatImageUrl(rawAvatar) : null,
        'kycStatus': kycStatus,
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
            (SELECT "status"::text FROM kyc WHERE "userId" = \$1 LIMIT 1) as kyc_status,
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
      String kycStatus = 'NOT_STARTED';
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
        kycStatus = row['kyc_status']?.toString() ?? 'NOT_STARTED';
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
        'kycStatus': kycStatus,
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
    'KYC',
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
        queryNeonHttp('''
          SELECT k."id", k."status"::text AS "status", k."submittedAt", k."reviewedAt"
          FROM kyc k
          WHERE k."userId" = \$1
        ''', [userId]),
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

      String day(String s) => s.length >= 10 ? s.substring(0, 10) : s;

      if (results[1].isNotEmpty) {
        final kRow = results[1].first;
        final kStatus = kRow['status']?.toString() ?? '';

        // Tarikh gulo raw pathai — page nijer bhashay sajabe
        docs['kycDocs']!.add({
          'id': kRow['id'].toString(),
          'title': 'KYC Verification',
          'submittedAt': day(kRow['submittedAt']?.toString() ?? ''),
          'reviewedAt': day(kRow['reviewedAt']?.toString() ?? ''),
          'status': kStatus == 'APPROVED' ? 'VERIFIED' : kStatus,
        });
      }

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

  /// true = save hoyeche (ba pathanor kichu chilo na)
  static Future<bool> _saveKycDocument(
      String kycId, String docType, String? fileData) async {
    if (fileData == null || fileData.isEmpty) return true;
    try {
      await executeNeonHttp(
          'DELETE FROM kyc_documents WHERE "kycId" = \$1 AND "documentType" = \$2::"KycDocumentType"',
          [kycId, docType]);

      return await executeNeonHttp('''
        INSERT INTO kyc_documents (
          "id", "kycId", "documentType", "storageKey", "mimeType", "sizeBytes", "createdAt"
        ) VALUES (
          \$1, \$2, \$3::"KycDocumentType", \$4, \$5, \$6, \$7
        )
      ''', [
        _generateUuid(),
        kycId,
        docType,
        fileData,
        _mimeFromDataUri(fileData),
        fileData.length,
        _nowIso(),
      ]);
    } catch (e) {
      debugPrint("Save KYC Document Warning: $e");
      return false;
    }
  }
}

