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

  // Universal Neon HTTP API SQL Executor (HTTPS Port 443 - 100% Reliable & Fast on All Devices/Emulators)
  static Future<List<Map<String, dynamic>>> queryNeonHttp(String querySql, [List<dynamic>? params]) async {
    try {
      final dbUrl = DbConfig.databaseUrl.trim();

      final response = await http.post(
        Uri.parse('https://ep-withered-lake-b5bgohpl.c-7.us-east-2.aws.neon.tech/sql'),
        headers: {
          'Content-Type': 'application/json',
          'neon-connection-string': dbUrl,
        },
        body: jsonEncode({
          'query': querySql,
          if (params != null && params.isNotEmpty) 'params': params,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List rows = data['rows'] as List? ?? [];
        return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      } else {
        debugPrint("Neon HTTP Query Error Status ${response.statusCode}: ${response.body}");
        _lastConnectionError = "HTTP ${response.statusCode}: ${response.body}";
      }
    } catch (e) {
      debugPrint("Neon HTTP Query Exception: $e");
      _lastConnectionError = e.toString();
    }
    return [];
  }

  // Execute Non-Query SQL Statement via Neon HTTP API
  static Future<bool> executeNeonHttp(String statementSql, [List<dynamic>? params]) async {
    try {
      final dbUrl = DbConfig.databaseUrl.trim();

      final response = await http.post(
        Uri.parse('https://ep-withered-lake-b5bgohpl.c-7.us-east-2.aws.neon.tech/sql'),
        headers: {
          'Content-Type': 'application/json',
          'neon-connection-string': dbUrl,
        },
        body: jsonEncode({
          'query': statementSql,
          if (params != null && params.isNotEmpty) 'params': params,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return true;
      } else {
        debugPrint("Neon HTTP Execute Error Status ${response.statusCode}: ${response.body}");
        _lastConnectionError = "HTTP ${response.statusCode}: ${response.body}";
      }
    } catch (e) {
      debugPrint("Neon HTTP Execute Exception: $e");
      _lastConnectionError = e.toString();
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

      final hostsToTry = [
        uri.host,
      ];

      for (final h in hostsToTry) {
        try {
          final conn = await Connection.open(
            Endpoint(
              host: h,
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
          debugPrint("Failed TCP connection attempt $h: $e");
        }
      }

      return null;
    } catch (e) {
      _connection = null;
      return null;
    }
  }

  // Password Hash Helper (bcrypt matching Next.js / Node.js bcrypt)
  static String hashPassword(String password) {
    return BCrypt.hashpw(password, BCrypt.gensalt());
  }

  // Verify password (matches BCrypt, SHA-256, or plaintext)
  static bool verifyPassword(String enteredPassword, String dbPassword) {
    if (dbPassword.startsWith(r'$2a$') ||
        dbPassword.startsWith(r'$2b$') ||
        dbPassword.startsWith(r'$2y$')) {
      try {
        return BCrypt.checkpw(enteredPassword, dbPassword);
      } catch (e) {
        debugPrint("BCrypt check error: $e");
      }
    }

    final sha256Hash = sha256.convert(utf8.encode(enteredPassword)).toString();
    return dbPassword == sha256Hash || dbPassword == enteredPassword;
  }

  // Generate UUID string ID matching Prisma @default(uuid())
  static String _generateUuid() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = Random.secure().nextInt(10000000);
    final hash =
        sha256.convert(utf8.encode('$timestamp-$random')).toString();
    return '${hash.substring(0, 8)}-${hash.substring(8, 12)}-4${hash.substring(13, 16)}-a${hash.substring(17, 20)}-${hash.substring(20, 32)}';
  }

  // Helper to ensure investorProfile and emailVerified exist in Neon DB for Website Compatibility
  static Future<void> _ensureInvestorProfileExists(String userId) async {
    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();
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
      final nowStr = DateTime.now().toUtc().toIso8601String();

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
        final createdCount = int.tryParse(row['created_count']?.toString() ?? '0') ?? 0;

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
          final userData = {
            'id': userId,
            'name': name.trim(),
            'email': cleanEmail,
            'phone': cleanPhone,
          };

          return {
            'success': true,
            'data': userData,
            'message': 'Registration successful!',
          };
        }
      }

      return {
        'success': false,
        'message': _lastConnectionError ?? 'Could not create account. Please check internet connection.',
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
        SELECT "id", "name", "email", "phone", "passwordHash", "avatarUrl", "status"::text, "updatedAt" 
        FROM users 
        WHERE LOWER("email") = LOWER(\$1) OR "phone" = \$1
      ''', [cleanInput]);

      if (result.isEmpty) {
        return {
          'success': false,
          'message': 'User not found. Please check credentials or register first.',
        };
      }

      final row = result.first;
      final userId = row['id'].toString();
      final dbPassword = row['passwordHash'] != null ? row['passwordHash'].toString() : '';

      if (!verifyPassword(password, dbPassword)) {
        return {
          'success': false,
          'message': 'Incorrect password. Please try again.',
        };
      }

      final st = row['status']?.toString() ?? 'ACTIVE';
      final updatedAtStr = row['updatedAt']?.toString();
      bool wasRestored = false;

      if (st == 'SUSPENDED') {
        DateTime? suspendedAt;
        if (updatedAtStr != null) {
          try {
            suspendedAt = DateTime.parse(updatedAtStr);
          } catch (_) {}
        }

        final now = DateTime.now().toUtc();
        if (suspendedAt != null && now.difference(suspendedAt).inDays > 7) {
          return {
            'success': false,
            'message': 'This account has been permanently deleted after 7 days. Please register a new account.',
          };
        }

        final nowStr = now.toIso8601String();
        await executeNeonHttp('''
          UPDATE users
          SET "status" = 'ACTIVE'::"UserStatus", "updatedAt" = \$1
          WHERE "id" = \$2
        ''', [nowStr, userId]);
        wasRestored = true;
      }

      // Auto-backfill investor_profiles for website compatibility
      await _ensureInvestorProfileExists(userId);

      final rawAvatar = row['avatarUrl']?.toString();

      final userData = {
        'id': userId,
        'name': row['name']?.toString() ?? 'Investor',
        'email': row['email']?.toString() ?? '',
        'phone': row['phone']?.toString() ?? '',
        'avatarUrl': rawAvatar != null && rawAvatar.isNotEmpty ? formatImageUrl(rawAvatar) : null,
      };

      return {
        'success': true,
        'data': userData,
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
    try {
      final userRes = await queryNeonHttp(
          'SELECT "passwordHash" FROM users WHERE "id" = \$1', [userId]);

      if (userRes.isEmpty) {
        return {'success': false, 'message': 'User not found.'};
      }

      final dbPasswordHash = userRes.first['passwordHash']?.toString() ?? '';

      if (!verifyPassword(oldPassword, dbPasswordHash)) {
        return {
          'success': false,
          'message': 'Incorrect current password. Please try again.',
        };
      }

      final newHash = hashPassword(newPassword);
      final nowStr = DateTime.now().toUtc().toIso8601String();

      await executeNeonHttp('''
        UPDATE users
        SET "passwordHash" = \$1, "updatedAt" = \$2
        WHERE "id" = \$3
      ''', [newHash, nowStr, userId]);

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

  // Request Account Deletion
  static Future<Map<String, dynamic>> requestAccountDeletion({
    required String userId,
    required String password,
  }) async {
    try {
      final userRes = await queryNeonHttp(
          'SELECT "passwordHash" FROM users WHERE "id" = \$1', [userId]);

      if (userRes.isEmpty) {
        return {'success': false, 'message': 'User not found.'};
      }

      final dbPasswordHash = userRes.first['passwordHash']?.toString() ?? '';

      if (!verifyPassword(password, dbPasswordHash)) {
        return {
          'success': false,
          'message': 'Incorrect password. Account deletion canceled.',
        };
      }

      final nowStr = DateTime.now().toUtc().toIso8601String();
      await executeNeonHttp('''
        UPDATE users
        SET "status" = 'SUSPENDED'::"UserStatus", "updatedAt" = \$1
        WHERE "id" = \$2
      ''', [nowStr, userId]);

      return {
        'success': true,
        'message': 'Account deletion requested! Scheduled for deletion in 7 days.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  // Send Forgot Password OTP
  static Future<Map<String, dynamic>> sendForgotPasswordOtp(String email) async {
    try {
      final cleanEmail = email.trim().toLowerCase();

      final userRes = await queryNeonHttp(
          'SELECT "id", "name" FROM users WHERE LOWER("email") = LOWER(\$1)',
          [cleanEmail]);

      if (userRes.isEmpty) {
        return {
          'success': false,
          'message': 'No registered account found with this email address.',
        };
      }

      final userName = userRes.first['name']?.toString() ?? 'Investor';

      final random = Random.secure();
      final otp = (100000 + random.nextInt(900000)).toString();

      await executeNeonHttp('''
        CREATE TABLE IF NOT EXISTS password_reset_tokens (
          "id" TEXT PRIMARY KEY,
          "email" TEXT NOT NULL,
          "token" TEXT NOT NULL,
          "expiresAt" TIMESTAMP WITH TIME ZONE NOT NULL,
          "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL
        );
      ''');

      final tokenId = _generateUuid();
      final now = DateTime.now().toUtc();
      final expiresAt = now.add(const Duration(minutes: 15));

      await executeNeonHttp('''
        INSERT INTO password_reset_tokens ("id", "email", "token", "expiresAt", "createdAt")
        VALUES (\$1, \$2, \$3, \$4, \$5)
      ''', [tokenId, cleanEmail, otp, expiresAt.toIso8601String(), now.toIso8601String()]);

      final apiKey = DbConfig.resendApiKey.trim();

      if (apiKey.isNotEmpty && apiKey != 'your_resend_api_key') {
        final resendUrl = Uri.parse('https://api.resend.com/emails');
        await http.post(
          resendUrl,
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
        );
      }

      return {
        'success': true,
        'otp': otp,
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
          'message': 'Invalid OTP code. Please check and try again.',
        };
      }

      final expiresAtStr = res.first['expiresAt']?.toString();
      if (expiresAtStr != null) {
        try {
          final expiresAt = DateTime.parse(expiresAtStr);
          if (DateTime.now().toUtc().isAfter(expiresAt)) {
            return {
              'success': false,
              'message': 'OTP code has expired. Please request a new one.',
            };
          }
        } catch (_) {}
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
      final hashedPassword = hashPassword(newPassword);
      final nowStr = DateTime.now().toUtc().toIso8601String();

      await executeNeonHttp('''
        UPDATE users
        SET "passwordHash" = \$1, "updatedAt" = \$2
        WHERE LOWER("email") = LOWER(\$3)
      ''', [hashedPassword, nowStr, cleanEmail]);

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

  // Update User Profile Avatar
  static Future<Map<String, dynamic>> updateUserAvatar({
    required String userId,
    required String avatarUrl,
  }) async {
    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();

      await executeNeonHttp('''
        UPDATE users
        SET "avatarUrl" = \$1, "updatedAt" = \$2
        WHERE "id" = \$3
      ''', [avatarUrl, nowStr, userId]);

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
    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();

      await executeNeonHttp('''
        UPDATE users
        SET "avatarUrl" = NULL, "updatedAt" = \$1
        WHERE "id" = \$2
      ''', [nowStr, userId]);

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
  }) async {
    try {
      String activeUserId = userId;
      if (activeUserId.isEmpty) {
        final latestUser = await queryNeonHttp(
            'SELECT "id" FROM users ORDER BY "createdAt" DESC LIMIT 1');
        if (latestUser.isNotEmpty) {
          activeUserId = latestUser.first['id'].toString();
        } else {
          return {
            'success': false,
            'message': 'No registered user found in database. Please log in first.',
          };
        }
      }

      final nowStr = DateTime.now().toUtc().toIso8601String();

      String docEnum = 'NATIONAL_ID';
      if (documentType.contains('PASSPORT')) {
        docEnum = 'PASSPORT';
      } else if (documentType.contains('DRIVING')) {
        docEnum = 'DRIVING_LICENSE';
      }

      final existingKyc = await queryNeonHttp(
          'SELECT "id" FROM kyc WHERE "userId" = \$1', [activeUserId]);

      String kycId;

      if (existingKyc.isNotEmpty) {
        kycId = existingKyc.first['id'].toString();

        await executeNeonHttp('''
          UPDATE kyc SET 
            "status" = 'SUBMITTED'::"KycStatus",
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
            "submittedAt" = \$12,
            "updatedAt" = \$12
          WHERE "id" = \$13
        ''', [
          fullName,
          docEnum,
          documentNumber,
          address,
          division,
          district,
          thana,
          bankName,
          bankAccountNumber,
          mobileProvider,
          mobileNumber,
          nowStr,
          kycId,
        ]);
      } else {
        kycId = _generateUuid();

        await executeNeonHttp('''
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
          kycId,
          activeUserId,
          fullName,
          docEnum,
          documentNumber,
          address,
          division,
          district,
          thana,
          bankName,
          bankAccountNumber,
          mobileProvider,
          mobileNumber,
          nowStr,
        ]);
      }

      // Upsert InvestorProfile
      final profileId = _generateUuid();
      await executeNeonHttp('''
        INSERT INTO investor_profiles ("id", "userId", "nomineeNationalId", "nomineeRelation", "address", "city", "country", "createdAt", "updatedAt")
        VALUES (\$1, \$2, \$3, \$4, \$5, \$6, 'BD', \$7, \$7)
        ON CONFLICT ("userId") DO UPDATE SET
          "nomineeNationalId" = EXCLUDED."nomineeNationalId",
          "nomineeRelation" = EXCLUDED."nomineeRelation",
          "updatedAt" = EXCLUDED."updatedAt";
      ''', [profileId, activeUserId, nomineeNid, nomineeRelation, address, district, nowStr]);

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

  // Create Investment
  static Future<Map<String, dynamic>> createInvestment({
    required String userId,
    required String projectId,
    required double amountBdt,
    bool useWalletBalance = false,
  }) async {
    try {
      String activeUserId = userId;
      if (activeUserId.isEmpty) {
        final latestUser = await queryNeonHttp(
            'SELECT "id" FROM users ORDER BY "createdAt" DESC LIMIT 1');
        if (latestUser.isNotEmpty) {
          activeUserId = latestUser.first['id'].toString();
        }
      }

      final kycRes = await queryNeonHttp(
          'SELECT "status"::text FROM kyc WHERE "userId" = \$1',
          [activeUserId]);
      if (kycRes.isEmpty || kycRes.first['status']?.toString() != 'VERIFIED') {
        return {
          'success': false,
          'message':
              'KYC verification required. Please complete and get your KYC approved before investing.',
        };
      }

      String profileId;
      final profRes = await queryNeonHttp(
          'SELECT "id" FROM investor_profiles WHERE "userId" = \$1',
          [activeUserId]);
      if (profRes.isNotEmpty) {
        profileId = profRes.first['id'].toString();
      } else {
        profileId = _generateUuid();
        final nowStr = DateTime.now().toUtc().toIso8601String();
        await executeNeonHttp('''
          INSERT INTO investor_profiles ("id", "userId", "createdAt", "updatedAt")
          VALUES (\$1, \$2, \$3, \$3)
        ''', [profileId, activeUserId, nowStr]);
      }

      final projRes = await queryNeonHttp('''
        SELECT "id", "status"::text, "fundingGoalBdt", "fundedAmountBdt", "minInvestmentBdt",
               "maxInvestmentBdt", "expectedReturnPct", "returnType"::text
        FROM projects
        WHERE "id" = \$1
      ''', [projectId]);

      if (projRes.isEmpty) {
        return {'success': false, 'message': 'Project not found.'};
      }

      final p = projRes.first;
      final status = p['status']?.toString() ?? 'DRAFT';
      if (status != 'FUNDRAISING') {
        return {
          'success': false,
          'message': 'Project is not currently open for fundraising (Status: $status).',
        };
      }

      final goal = double.tryParse(p['fundingGoalBdt']?.toString() ?? '1') ?? 1.0;
      final funded = double.tryParse(p['fundedAmountBdt']?.toString() ?? '0') ?? 0.0;
      final minInv = double.tryParse(p['minInvestmentBdt']?.toString() ?? '10000') ?? 10000.0;
      final maxInv = double.tryParse(p['maxInvestmentBdt']?.toString() ?? '0');
      final returnPct = double.tryParse(p['expectedReturnPct']?.toString() ?? '0.15') ?? 0.15;
      final returnType = p['returnType']?.toString() ?? 'FIXED_RETURN';

      if (amountBdt < minInv) {
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

      final expectedReturnBdt = amountBdt * returnPct;
      final investmentId = _generateUuid();
      final idempotencyKey = _generateUuid();
      final nowStr = DateTime.now().toUtc().toIso8601String();

      await executeNeonHttp('''
        INSERT INTO investments (
          "id", "investorProfileId", "projectId", "status", "amountBdt",
          "expectedReturnBdt", "returnType", "idempotencyKey", "createdAt", "updatedAt"
        ) VALUES (
          \$1, \$2, \$3, 'PENDING'::"InvestmentStatus", \$4,
          \$5, \$6::"ReturnType", \$7, \$8, \$8
        )
      ''', [
        investmentId,
        profileId,
        projectId,
        amountBdt,
        expectedReturnBdt,
        returnType,
        idempotencyKey,
        nowStr,
      ]);

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

  // Fetch Full Single Project Detail
  static Future<Map<String, dynamic>> getProjectDetail(String projectIdOrSlug) async {
    try {
      final projRes = await queryNeonHttp('''
        SELECT p."id", p."title", p."slug", p."description", p."category"::text, p."status"::text,
               p."riskInfo", p."location", p."fundingGoalBdt", p."fundingMinBdt", p."fundedAmountBdt",
               p."minInvestmentBdt", p."maxInvestmentBdt", p."expectedReturnPct", p."returnType"::text,
               p."durationDays", p."fundingDeadline", p."startDate", p."endDate", p."coverImageUrl",
               p."imageUrls", bg."name" as "groupName",
               (SELECT COUNT(DISTINCT i."investorProfileId") FROM investments i WHERE i."projectId" = p."id") as "investorsCount"
        FROM projects p
        LEFT JOIN business_groups bg ON p."groupId" = bg."id"
        WHERE p."id" = \$1 OR p."slug" = \$1
      ''', [projectIdOrSlug]);

      if (projRes.isEmpty) return {};

      final r = projRes.first;
      final projectId = r['id'].toString();

      final goal = double.tryParse(r['fundingGoalBdt']?.toString() ?? '1') ?? 1.0;
      final minFunding = double.tryParse(r['fundingMinBdt']?.toString() ?? '0') ?? 0.0;
      final funded = double.tryParse(r['fundedAmountBdt']?.toString() ?? '0') ?? 0.0;
      final minInv = double.tryParse(r['minInvestmentBdt']?.toString() ?? '10000') ?? 10000.0;
      final maxInv = double.tryParse(r['maxInvestmentBdt']?.toString() ?? '0');
      final returnPct = double.tryParse(r['expectedReturnPct']?.toString() ?? '0.15') ?? 0.15;
      final returnType = r['returnType']?.toString() ?? 'PROFIT_SHARE';
      final durationDays = int.tryParse(r['durationDays']?.toString() ?? '180') ?? 180;

      final remaining = (goal - funded).clamp(0.0, double.infinity);
      final pct = goal > 0 ? (funded / goal).clamp(0.0, 1.0) : 0.0;

      final coverUrl = formatImageUrl(r['coverImageUrl']?.toString());
      final rawImageUrls = r['imageUrls'] as List?;
      List<String> imageUrls = [coverUrl];
      if (rawImageUrls != null) {
        for (final img in rawImageUrls) {
          final formatted = formatImageUrl(img?.toString());
          if (!imageUrls.contains(formatted)) imageUrls.add(formatted);
        }
      }

      final deadlineStr = r['fundingDeadline']?.toString();
      int daysLeft = 116;
      if (deadlineStr != null) {
        try {
          final deadline = DateTime.parse(deadlineStr);
          daysLeft = deadline.difference(DateTime.now()).inDays.clamp(0, 365);
        } catch (_) {}
      }

      final bankRes = await queryNeonHttp('''
        SELECT "id", "bankName", "accountName", "accountNumber", "branchName",
               "routingNumber", "swiftCode", "mobileNumber", "email", "branchAddress"
        FROM project_bank_accounts
        WHERE "projectId" = \$1 AND "isActive" = true
        ORDER BY "createdAt" ASC
      ''', [projectId]);

      final List<Map<String, dynamic>> bankAccounts = bankRes.map((b) {
        return {
          'id': b['id'].toString(),
          'bankName': b['bankName']?.toString() ?? 'Dutch-Bangla Bank Limited',
          'accountName': b['accountName']?.toString() ?? 'Marinozz PLC',
          'accountNumber': b['accountNumber']?.toString() ?? '',
          'branchName': b['branchName']?.toString() ?? '',
          'routingNumber': b['routingNumber']?.toString() ?? '',
          'swiftCode': b['swiftCode']?.toString() ?? '',
          'mobileNumber': b['mobileNumber']?.toString() ?? '',
          'email': b['email']?.toString() ?? '',
          'branchAddress': b['branchAddress']?.toString() ?? '',
        };
      }).toList();

      return {
        'id': projectId,
        'title': r['title']?.toString() ?? 'Biniyog Project',
        'slug': r['slug']?.toString() ?? '',
        'description': r['description']?.toString() ?? '',
        'category': r['category']?.toString() ?? 'SME',
        'status': r['status']?.toString() ?? 'FUNDRAISING',
        'riskInfo': r['riskInfo']?.toString() ?? 'Agriculture faces risks from weather, disease, market prices, input costs, and supply chain disruptions.',
        'location': r['location']?.toString() ?? 'Narayanganj',
        'fundingGoalBdt': goal,
        'fundingMinBdt': minFunding,
        'fundedAmountBdt': funded,
        'minInvestmentBdt': minInv,
        'maxInvestmentBdt': maxInv,
        'expectedReturnPct': returnPct,
        'returnType': returnType,
        'durationDays': durationDays,
        'fundingDeadline': deadlineStr ?? '2027-01-30',
        'startDate': r['startDate']?.toString() ?? '2026-10-07',
        'endDate': r['endDate']?.toString() ?? '2027-01-29',
        'coverImageUrl': coverUrl,
        'imageUrls': imageUrls,
        'groupName': r['groupName']?.toString() ?? 'Mariners Group',
        'investorsCount': int.tryParse(r['investorsCount']?.toString() ?? '2') ?? 2,
        'remainingBdt': remaining,
        'progress': pct,
        'daysLeft': daysLeft,
        'bankAccounts': bankAccounts,
      };
    } catch (e) {
      debugPrint("Get Project Detail Error: $e");
      return {};
    }
  }

  // Fetch Full User Profile & Investor Profile
  static Future<Map<String, dynamic>> getUserProfileFull(String userId, {String? email}) async {
    try {
      String activeUserId = userId;
      String activeEmail = email ?? '';

      if (activeUserId.isEmpty && activeEmail.isNotEmpty) {
        final uRes = await queryNeonHttp(
            'SELECT "id" FROM users WHERE LOWER("email") = LOWER(\$1)',
            [activeEmail]);
        if (uRes.isNotEmpty) activeUserId = uRes.first['id'].toString();
      }

      if (activeUserId.isEmpty) {
        final latestUser = await queryNeonHttp(
            'SELECT "id", "email" FROM users ORDER BY "createdAt" DESC LIMIT 1');
        if (latestUser.isNotEmpty) {
          activeUserId = latestUser.first['id'].toString();
          activeEmail = latestUser.first['email'].toString();
        }
      }

      if (activeUserId.isNotEmpty) {
        await _ensureInvestorProfileExists(activeUserId);
      }

      final userRes = await queryNeonHttp('''
        SELECT "id", "name", "email", "phone", "emailVerified", "phoneVerified", "createdAt", "avatarUrl"
        FROM users
        WHERE "id" = \$1
      ''', [activeUserId]);

      if (userRes.isEmpty) return {};

      final uRow = userRes.first;

      final profRes = await queryNeonHttp('''
        SELECT "nationalId", "address", "city", "country", "occupation",
               "annualIncomeRange", "investmentExperience", "riskTolerance"
        FROM investor_profiles
        WHERE "userId" = \$1
      ''', [activeUserId]);

      Map<String, dynamic> profMap = {};
      if (profRes.isNotEmpty) {
        final p = profRes.first;
        profMap = {
          'nationalId': p['nationalId']?.toString() ?? 'N/A',
          'address': p['address']?.toString() ?? 'Bangladesh',
          'city': p['city']?.toString() ?? 'Dhaka',
          'country': p['country']?.toString() ?? 'BD',
          'occupation': p['occupation']?.toString() ?? 'Investor',
          'annualIncomeRange': p['annualIncomeRange']?.toString() ?? 'Standard',
          'investmentExperience': p['investmentExperience']?.toString() ?? 'Intermediate',
          'riskTolerance': p['riskTolerance']?.toString() ?? 'Moderate',
        };
      }

      String kycStatus = 'NOT_STARTED';
      final kycRes = await queryNeonHttp(
          'SELECT "status"::text FROM kyc WHERE "userId" = \$1',
          [activeUserId]);
      if (kycRes.isNotEmpty) {
        kycStatus = kycRes.first['status']?.toString() ?? 'NOT_STARTED';
      }

      final rawAvatar = uRow['avatarUrl']?.toString();

      return {
        'id': uRow['id'].toString(),
        'name': uRow['name']?.toString() ?? 'Investor',
        'email': uRow['email']?.toString() ?? '',
        'phone': uRow['phone']?.toString() ?? 'N/A',
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
      String activeUserId = userId;
      String activeEmail = email ?? '';

      if (activeUserId.isEmpty && activeEmail.isNotEmpty) {
        final uRes = await queryNeonHttp(
            'SELECT "id" FROM users WHERE LOWER("email") = LOWER(\$1)',
            [activeEmail]);
        if (uRes.isNotEmpty) {
          activeUserId = uRes.first['id'].toString();
        }
      }

      if (activeUserId.isEmpty) {
        final latestUser = await queryNeonHttp(
            'SELECT "id", "email" FROM users ORDER BY "createdAt" DESC LIMIT 1');
        if (latestUser.isNotEmpty) {
          activeUserId = latestUser.first['id'].toString();
          activeEmail = latestUser.first['email'].toString();
        }
      }

      if (activeUserId.isNotEmpty) {
        await _ensureInvestorProfileExists(activeUserId);
      }

      String? avatarUrl;
      final avatarRes = await queryNeonHttp(
          'SELECT "avatarUrl" FROM users WHERE "id" = \$1 OR (LOWER("email") = LOWER(\$2) AND \$2 != \'\')',
          [activeUserId, activeEmail]);
      if (avatarRes.isNotEmpty && avatarRes.first['avatarUrl'] != null) {
        final rawAvatar = avatarRes.first['avatarUrl'].toString();
        if (rawAvatar.isNotEmpty) avatarUrl = formatImageUrl(rawAvatar);
      }

      int unreadNotifCount = 0;
      final unreadRes = await queryNeonHttp(
          'SELECT COUNT(*) as cnt FROM notifications WHERE "userId" = \$1 AND "isRead" = false',
          [activeUserId]);
      if (unreadRes.isNotEmpty) {
        unreadNotifCount = int.tryParse(unreadRes.first['cnt']?.toString() ?? '0') ?? 0;
      }

      String kycStatus = 'NOT_STARTED';
      final kycRes = await queryNeonHttp('''
        SELECT k."status"::text FROM kyc k
        WHERE k."userId" = \$1 
           OR k."userId" IN (SELECT "id" FROM users WHERE LOWER("email") = LOWER(\$2) AND \$2 != '')
      ''', [activeUserId, activeEmail]);

      if (kycRes.isNotEmpty && kycRes.first['status'] != null) {
        kycStatus = kycRes.first['status'].toString();
      }

      double totalInvested = 0.0;
      int activeInvestmentsCount = 0;
      final invRes = await queryNeonHttp('''
        SELECT COUNT(*) as cnt, COALESCE(SUM(i."amountBdt"), 0) as total_amt
        FROM investments i
        JOIN investor_profiles p ON i."investorProfileId" = p.id
        JOIN users u ON p."userId" = u."id"
        WHERE (p."userId" = \$1 OR (LOWER(u."email") = LOWER(\$2) AND \$2 != ''))
          AND i."status"::text IN ('ACTIVE', 'MATURED', 'COMPLETED')
      ''', [activeUserId, activeEmail]);

      if (invRes.isNotEmpty) {
        activeInvestmentsCount = int.tryParse(invRes.first['cnt']?.toString() ?? '0') ?? 0;
        totalInvested = double.tryParse(invRes.first['total_amt']?.toString() ?? '0') ?? 0.0;
      }

      int pendingTransactionsCount = 0;
      double pendingInvestmentsAmount = 0.0;
      final pendingRes = await queryNeonHttp('''
        SELECT COUNT(*) as cnt, COALESCE(SUM(i."amountBdt"), 0) as pending_amt
        FROM investments i
        JOIN investor_profiles p ON i."investorProfileId" = p.id
        JOIN users u ON p."userId" = u."id"
        WHERE (p."userId" = \$1 OR (LOWER(u."email") = LOWER(\$2) AND \$2 != ''))
          AND i."status"::text IN ('PENDING', 'PAYMENT_PENDING')
          AND NOT EXISTS (
            SELECT 1 FROM manual_payment_submissions m
            WHERE m."investmentId" = i."id"
              AND m."status"::text IN ('REJECTED', 'APPROVED')
          )
      ''', [activeUserId, activeEmail]);

      if (pendingRes.isNotEmpty) {
        pendingTransactionsCount = int.tryParse(pendingRes.first['cnt']?.toString() ?? '0') ?? 0;
        pendingInvestmentsAmount = double.tryParse(pendingRes.first['pending_amt']?.toString() ?? '0') ?? 0.0;
      }

      double totalReturns = 0.0;
      final returnRes = await queryNeonHttp('''
        SELECT COALESCE(SUM(d."netAmountBdt"), 0) as total_ret
        FROM profit_distributions d
        JOIN investments i ON d."investmentId" = i.id
        JOIN investor_profiles p ON i."investorProfileId" = p.id
        JOIN users u ON p."userId" = u."id"
        WHERE p."userId" = \$1 OR (LOWER(u."email") = LOWER(\$2) AND \$2 != '')
      ''', [activeUserId, activeEmail]);

      if (returnRes.isNotEmpty) {
        totalReturns = double.tryParse(returnRes.first['total_ret']?.toString() ?? '0') ?? 0.0;
      }

      final projectsRes = await queryNeonHttp('''
        SELECT p."id", p."title", p."category"::text, p."fundingGoalBdt", p."fundedAmountBdt",
               p."minInvestmentBdt", p."expectedReturnPct", p."durationDays", p."coverImageUrl",
               p."location", p."fundingDeadline",
               (SELECT COUNT(DISTINCT i."investorProfileId") FROM investments i WHERE i."projectId" = p."id") as "investorsCount"
        FROM projects p
        ORDER BY p."createdAt" DESC
        LIMIT 5
      ''');

      final List<Map<String, dynamic>> projects = projectsRes.map((row) {
        final goal = double.tryParse(row['fundingGoalBdt']?.toString() ?? '1') ?? 1.0;
        final funded = double.tryParse(row['fundedAmountBdt']?.toString() ?? '0') ?? 0.0;
        final pct = goal > 0 ? (funded / goal).clamp(0.0, 1.0) : 0.0;

        final rawCover = row['coverImageUrl']?.toString();
        final coverUrl = formatImageUrl(rawCover);

        final location = row['location']?.toString() ?? 'Narayanganj';
        final deadlineStr = row['fundingDeadline']?.toString();
        int daysLeft = 116;
        if (deadlineStr != null) {
          try {
            final deadline = DateTime.parse(deadlineStr);
            daysLeft = deadline.difference(DateTime.now()).inDays.clamp(0, 365);
          } catch (_) {}
        }

        final investorsCount = int.tryParse(row['investorsCount']?.toString() ?? '1') ?? 1;

        return {
          'id': row['id'].toString(),
          'title': row['title']?.toString() ?? 'Biniyog Project',
          'category': row['category']?.toString() ?? 'SME',
          'fundingGoalBdt': goal,
          'fundedAmountBdt': funded,
          'progress': pct,
          'minInvestmentBdt': double.tryParse(row['minInvestmentBdt']?.toString() ?? '10000') ?? 10000.0,
          'expectedReturnPct': double.tryParse(row['expectedReturnPct']?.toString() ?? '0.15') ?? 0.15,
          'durationDays': int.tryParse(row['durationDays']?.toString() ?? '180') ?? 180,
          'coverImageUrl': coverUrl,
          'location': location.isEmpty ? 'Bangladesh' : location,
          'daysLeft': daysLeft,
          'investorsCount': investorsCount,
        };
      }).toList();

      final userInvRes = await queryNeonHttp('''
        SELECT i."id", pr."title", i."amountBdt", i."expectedReturnBdt", i."status"::text, i."createdAt"
        FROM investments i
        JOIN investor_profiles p ON i."investorProfileId" = p.id
        JOIN projects pr ON i."projectId" = pr.id
        JOIN users u ON p."userId" = u."id"
        WHERE p."userId" = \$1 OR (LOWER(u."email") = LOWER(\$2) AND \$2 != '')
        ORDER BY i."createdAt" DESC
        LIMIT 5
      ''', [activeUserId, activeEmail]);

      final List<Map<String, dynamic>> recentInvestments = userInvRes.map((row) {
        return {
          'id': row['id'].toString(),
          'title': row['title']?.toString() ?? 'Investment',
          'amountBdt': double.tryParse(row['amountBdt']?.toString() ?? '0') ?? 0.0,
          'expectedReturnBdt': double.tryParse(row['expectedReturnBdt']?.toString() ?? '0') ?? 0.0,
          'status': row['status']?.toString() ?? 'PENDING',
          'createdAt': row['createdAt']?.toString() ?? '',
        };
      }).toList();

      return {
        'avatarUrl': avatarUrl,
        'unreadNotificationCount': unreadNotifCount,
        'kycStatus': kycStatus,
        'totalInvested': totalInvested,
        'activeInvestmentsCount': activeInvestmentsCount,
        'pendingTransactionsCount': pendingTransactionsCount,
        'pendingInvestmentsAmount': pendingInvestmentsAmount,
        'totalReturns': totalReturns,
        'openProjects': projects,
        'recentInvestments': recentInvestments,
      };
    } catch (e) {
      debugPrint("Get Dashboard Summary Error: $e");
      return {};
    }
  }

  // Fetch Notifications
  static Future<List<Map<String, dynamic>>> getNotificationsData(String userId) async {
    if (userId.isEmpty) return [];
    try {
      final res = await queryNeonHttp('''
        SELECT n."id", n."title", n."body", n."type"::text, n."isRead", n."createdAt"
        FROM notifications n
        WHERE n."userId" = \$1
        ORDER BY n."createdAt" DESC
      ''', [userId]);

      return res.map((r) {
        return {
          'id': r['id'].toString(),
          'title': r['title']?.toString() ?? 'Notification',
          'body': r['body']?.toString() ?? '',
          'type': r['type']?.toString() ?? 'SYSTEM',
          'isRead': (r['isRead'] as bool?) ?? false,
          'createdAt': r['createdAt']?.toString() ?? '',
        };
      }).toList();
    } catch (e) {
      debugPrint("Get Notifications Error: $e");
      return [];
    }
  }

  // Mark Single Notification as Read
  static Future<void> markNotificationAsRead(String notificationId) async {
    await executeNeonHttp(
        'UPDATE notifications SET "isRead" = true WHERE "id" = \$1',
        [notificationId]);
  }

  // Mark All Notifications as Read
  static Future<void> markAllNotificationsAsRead(String userId) async {
    await executeNeonHttp(
        'UPDATE notifications SET "isRead" = true WHERE "userId" = \$1',
        [userId]);
  }

  // Upload User Document
  static Future<Map<String, dynamic>> uploadUserDocument({
    required String userId,
    required String name,
    required String category,
    required String fileUrl,
    String? description,
    int? sizeBytes,
  }) async {
    try {
      final docId = _generateUuid();
      final nowStr = DateTime.now().toUtc().toIso8601String();

      String catEnum = 'PAYMENT_RECEIPT';
      if (category.contains('KYC')) {
        catEnum = 'KYC';
      } else if (category.contains('INVESTMENT') || category.contains('AGREEMENT')) {
        catEnum = 'INVESTMENT_AGREEMENT';
      } else if (category.contains('PROJECT')) {
        catEnum = 'PROJECT_DOCUMENT';
      }

      final ok = await executeNeonHttp('''
        INSERT INTO documents (
          "id", "name", "category", "fileUrl", "sizeBytes", "uploadedBy", "ownerUserId", "isPublic", "createdAt", "updatedAt"
        ) VALUES (
          \$1, \$2, \$3::"DocumentCategory", \$4, \$5, \$6, \$6, false, \$7, \$7
        )
      ''', [
        docId,
        name,
        catEnum,
        fileUrl,
        sizeBytes ?? 36800,
        userId,
        nowStr,
      ]);

      if (ok) {
        return {
          'success': true,
          'message': 'Document uploaded successfully to database!',
        };
      }
      return {'success': false, 'message': 'Upload failed.'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  // Fetch Categorized Documents & Contracts
  static Future<Map<String, List<Map<String, dynamic>>>> getDocumentsCategorized(String userId) async {
    if (userId.isEmpty) {
      return {
        'contracts': [],
        'kycDocs': [],
        'paymentReceipts': [],
        'investmentReceipts': [],
        'distributionStatements': [],
        'harvestReports': [],
        'projectDocs': [],
      };
    }

    try {
      final List<Map<String, dynamic>> contracts = [];
      final List<Map<String, dynamic>> kycDocs = [];
      final List<Map<String, dynamic>> paymentReceipts = [];
      final List<Map<String, dynamic>> investmentReceipts = [];
      final List<Map<String, dynamic>> distributionStatements = [];
      final List<Map<String, dynamic>> harvestReports = [];
      final List<Map<String, dynamic>> projectDocs = [];

      final invRes = await queryNeonHttp('''
        SELECT i."id", pr."title", pr."location", pr."returnType"::text, pr."expectedReturnPct",
               i."amountBdt", i."expectedReturnBdt", i."status"::text, i."createdAt",
               u."name", u."email", u."phone"
        FROM investments i
        JOIN investor_profiles p ON i."investorProfileId" = p.id
        JOIN projects pr ON i."projectId" = pr.id
        JOIN users u ON p."userId" = u."id"
        WHERE p."userId" = \$1 OR u."id" = \$1
        ORDER BY i."createdAt" DESC
      ''', [userId]);

      for (final r in invRes) {
        final invId = r['id'].toString();
        final projTitle = r['title']?.toString() ?? 'Biniyog Project';
        final location = r['location']?.toString() ?? 'Dhaka, Bangladesh';
        final returnType = r['returnType']?.toString() ?? 'Hybrid';
        final returnPct = double.tryParse(r['expectedReturnPct']?.toString() ?? '0.16') ?? 0.16;
        final amt = double.tryParse(r['amountBdt']?.toString() ?? '0') ?? 0.0;
        final expRet = double.tryParse(r['expectedReturnBdt']?.toString() ?? '0') ?? 0.0;
        final status = r['status']?.toString() ?? 'PENDING';
        final createdAt = r['createdAt']?.toString() ?? '';
        final userName = r['name']?.toString() ?? 'Investor';
        final userEmail = r['email']?.toString() ?? '';
        final userPhone = r['phone']?.toString() ?? 'N/A';

        final certNo = 'BC-${invId.substring(0, min(12, invId.length)).toUpperCase()}';
        final verifyUrl = 'https://biniyogclub.com/verify/$certNo';

        contracts.add({
          'id': invId,
          'title': projTitle,
          'amountBdt': amt,
          'status': status == 'PENDING' ? 'DRAFT' : status,
          'createdAt': createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt,
        });

        investmentReceipts.add({
          'id': invId,
          'name': 'Investment Receipt — $projTitle',
          'category': 'INVESTMENT_RECEIPT',
          'certificateNo': certNo,
          'issuedDate': createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt,
          'status': status == 'ACTIVE' || status == 'COMPLETED' ? 'CONFIRMED' : status,
          'amountInvested': amt,
          'expectedReturn': expRet,
          'returnPct': returnPct,
          'userName': userName,
          'userEmail': userEmail,
          'userPhone': userPhone,
          'projectTitle': projTitle,
          'location': location,
          'returnType': returnType,
          'verifyUrl': verifyUrl,
          'createdAt': createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt,
          'sizeText': '36 KB',
        });
      }

      final kycRes = await queryNeonHttp('''
        SELECT k."id", k."status"::text, k."submittedAt", k."reviewedAt"
        FROM kyc k
        WHERE k."userId" = \$1
      ''', [userId]);

      if (kycRes.isNotEmpty) {
        final kRow = kycRes.first;
        final kStatus = kRow['status']?.toString() ?? 'SUBMITTED';
        final subAt = kRow['submittedAt']?.toString() ?? '';
        final revAt = kRow['reviewedAt']?.toString() ?? '';

        String dateText = 'Submitted';
        if (subAt.length >= 10) dateText += ' ${subAt.substring(0, 10)}';
        if (revAt.length >= 10) dateText += ' · Reviewed ${revAt.substring(0, 10)}';

        kycDocs.add({
          'id': kRow['id'].toString(),
          'title': 'KYC Verification',
          'subtitle': dateText,
          'status': kStatus == 'APPROVED' ? 'VERIFIED' : kStatus,
        });
      }

      final docRes = await queryNeonHttp('''
        SELECT d."id", d."name", d."category"::text, d."fileUrl", d."sizeBytes", d."createdAt"
        FROM documents d
        WHERE d."uploadedBy" = \$1 OR d."ownerUserId" = \$1 OR d."isPublic" = true
        ORDER BY d."createdAt" DESC
      ''', [userId]);

      for (final r in docRes) {
        final cat = r['category']?.toString() ?? 'PROJECT_DOCUMENT';
        final item = {
          'id': r['id'].toString(),
          'name': r['name']?.toString() ?? 'Document',
          'category': cat,
          'fileUrl': r['fileUrl']?.toString() ?? '',
          'sizeBytes': int.tryParse(r['sizeBytes']?.toString() ?? '0') ?? 36800,
          'createdAt': r['createdAt']?.toString() ?? '',
        };

        if (cat == 'PAYMENT_RECEIPT') {
          paymentReceipts.add(item);
        } else if (cat == 'DISTRIBUTION_STATEMENT') {
          distributionStatements.add(item);
        } else if (cat == 'HARVEST_REPORT') {
          harvestReports.add(item);
        } else {
          projectDocs.add(item);
        }
      }

      return {
        'contracts': contracts,
        'kycDocs': kycDocs,
        'paymentReceipts': paymentReceipts,
        'investmentReceipts': investmentReceipts,
        'distributionStatements': distributionStatements,
        'harvestReports': harvestReports,
        'projectDocs': projectDocs,
      };
    } catch (e) {
      debugPrint("Get Documents Categorized Error: $e");
      return {
        'contracts': [],
        'kycDocs': [],
        'paymentReceipts': [],
        'investmentReceipts': [],
        'distributionStatements': [],
        'harvestReports': [],
        'projectDocs': [],
      };
    }
  }

  // Fetch KYC Status
  static Future<Map<String, dynamic>> getKycStatus(String userId, {String? email}) async {
    try {
      String activeUserId = userId;
      String activeEmail = email ?? '';

      if (activeUserId.isEmpty && activeEmail.isEmpty) {
        final latestUser = await queryNeonHttp(
            'SELECT "id", "email" FROM users ORDER BY "createdAt" DESC LIMIT 1');
        if (latestUser.isNotEmpty) {
          activeUserId = latestUser.first['id'].toString();
          activeEmail = latestUser.first['email'].toString();
        }
      }

      final res = await queryNeonHttp('''
        SELECT k."id", k."status"::text, k."fullName", k."documentType"::text, k."documentNumber",
               k."presentDivision", k."presentDistrict", k."reviewNote", k."submittedAt", k."reviewedAt"
        FROM kyc k
        JOIN users u ON k."userId" = u."id"
        WHERE k."userId" = \$1 OR (LOWER(u."email") = LOWER(\$2) AND \$2 != '')
      ''', [activeUserId, activeEmail]);

      if (res.isEmpty) {
        return {'status': 'NOT_STARTED'};
      }

      final row = res.first;
      final kycId = row['id'].toString();

      final docsRes = await queryNeonHttp(
          'SELECT "id", "documentType", "createdAt" FROM kyc_documents WHERE "kycId" = \$1',
          [kycId]);

      final List<Map<String, dynamic>> documents = docsRes.map((d) {
        return {
          'id': d['id'].toString(),
          'type': d['documentType']?.toString() ?? 'DOCUMENT',
          'createdAt': d['createdAt']?.toString() ?? '',
        };
      }).toList();

      return {
        'id': kycId,
        'status': row['status']?.toString() ?? 'NOT_STARTED',
        'fullName': row['fullName']?.toString() ?? '',
        'documentType': row['documentType']?.toString() ?? '',
        'documentNumber': row['documentNumber']?.toString() ?? '',
        'division': row['presentDivision']?.toString() ?? '',
        'district': row['presentDistrict']?.toString() ?? '',
        'reviewNote': row['reviewNote']?.toString(),
        'submittedAt': row['submittedAt']?.toString() ?? '',
        'reviewedAt': row['reviewedAt']?.toString() ?? '',
        'documents': documents,
      };
    } catch (e) {
      debugPrint("Get KYC Status Error: $e");
      return {'status': 'NOT_STARTED'};
    }
  }

  // Fetch Group Investments
  static Future<List<Map<String, dynamic>>> getGroupInvestmentsData(String userId) async {
    if (userId.isEmpty) return [];
    try {
      final res = await queryNeonHttp('''
        SELECT gi."id", bg."name" as "groupName", ge."name" as "entityName", gt."name" as "tierName",
               gi."amountBdt", gi."plotNumber", gi."plotSizeSqft", gi."sharePercentage", gi."status"::text, gi."createdAt"
        FROM group_investments gi
        JOIN group_tiers gt ON gi."tierId" = gt."id"
        JOIN group_entities ge ON gt."entityId" = ge."id"
        JOIN business_groups bg ON ge."groupId" = bg."id"
        WHERE gi."investorUserId" = \$1
        ORDER BY gi."createdAt" DESC
      ''', [userId]);

      return res.map((r) {
        return {
          'id': r['id'].toString(),
          'groupName': r['groupName']?.toString() ?? 'Business Group',
          'entityName': r['entityName']?.toString() ?? 'Group Entity',
          'tierName': r['tierName']?.toString() ?? 'Tier',
          'amountBdt': double.tryParse(r['amountBdt']?.toString() ?? '0') ?? 0.0,
          'plotNumber': r['plotNumber']?.toString() ?? 'N/A',
          'plotSizeSqft': double.tryParse(r['plotSizeSqft']?.toString() ?? '0') ?? 0.0,
          'sharePercentage': double.tryParse(r['sharePercentage']?.toString() ?? '0') ?? 0.0,
          'status': r['status']?.toString() ?? 'PENDING',
          'createdAt': r['createdAt']?.toString() ?? '',
        };
      }).toList();
    } catch (e) {
      debugPrint("Get Group Investments Error: $e");
      return [];
    }
  }

  // Fetch Portfolio Data
  static Future<Map<String, dynamic>> getPortfolioData(String userId, {String? email}) async {
    try {
      String activeUserId = userId;
      String activeEmail = email ?? '';

      if (activeUserId.isEmpty && activeEmail.isNotEmpty) {
        final uRes = await queryNeonHttp(
            'SELECT "id" FROM users WHERE LOWER("email") = LOWER(\$1)',
            [activeEmail]);
        if (uRes.isNotEmpty) activeUserId = uRes.first['id'].toString();
      }

      if (activeUserId.isEmpty) {
        final latestUser = await queryNeonHttp(
            'SELECT "id", "email" FROM users ORDER BY "createdAt" DESC LIMIT 1');
        if (latestUser.isNotEmpty) {
          activeUserId = latestUser.first['id'].toString();
          activeEmail = latestUser.first['email'].toString();
        }
      }

      String? profileId;
      final profRes = await queryNeonHttp(
          'SELECT "id" FROM investor_profiles WHERE "userId" = \$1',
          [activeUserId]);
      if (profRes.isNotEmpty) {
        profileId = profRes.first['id'].toString();
      }

      final invRes = await queryNeonHttp('''
        SELECT i."id", pr."id" as "projectId", pr."title", pr."category"::text, pr."slug",
               pr."durationDays", pr."location", i."amountBdt", i."expectedReturnBdt",
               i."actualReturnBdt", i."status"::text, i."createdAt", i."activatedAt",
               pr."fundedAmountBdt", pr."fundingGoalBdt", pr."expectedReturnPct"
        FROM investments i
        JOIN investor_profiles p ON i."investorProfileId" = p.id
        JOIN projects pr ON i."projectId" = pr.id
        JOIN users u ON p."userId" = u."id"
        WHERE p."userId" = \$1 OR (LOWER(u."email") = LOWER(\$2) AND \$2 != '') OR i."investorProfileId" = \$3
        ORDER BY i."createdAt" DESC
      ''', [activeUserId, activeEmail, profileId ?? activeUserId]);

      double totalInvested = 0.0;
      double totalExpected = 0.0;
      double totalActual = 0.0;

      final List<Map<String, dynamic>> investmentsList = [];

      for (final r in invRes) {
        final invId = r['id'].toString();
        final projectId = r['projectId'].toString();
        final title = r['title']?.toString() ?? 'Biniyog Project';
        final category = r['category']?.toString() ?? 'SME';
        final slug = r['slug']?.toString() ?? '';
        final durationDays = int.tryParse(r['durationDays']?.toString() ?? '180') ?? 180;
        final location = r['location']?.toString() ?? 'Bangladesh';
        final amt = double.tryParse(r['amountBdt']?.toString() ?? '0') ?? 0.0;
        final expRet = double.tryParse(r['expectedReturnBdt']?.toString() ?? '0') ?? 0.0;
        final actRet = double.tryParse(r['actualReturnBdt']?.toString() ?? '0');
        final status = r['status']?.toString() ?? 'PENDING';
        final createdAt = r['createdAt']?.toString() ?? '';
        final activatedAt = r['activatedAt']?.toString();
        final funded = double.tryParse(r['fundedAmountBdt']?.toString() ?? '0') ?? 0.0;
        final goal = double.tryParse(r['fundingGoalBdt']?.toString() ?? '1') ?? 1.0;
        final returnPct = double.tryParse(r['expectedReturnPct']?.toString() ?? '0.15') ?? 0.15;

        if (status == 'ACTIVE' || status == 'MATURED' || status == 'COMPLETED') {
          totalInvested += amt;
          totalExpected += expRet;
        }
        if (actRet != null && actRet > 0) {
          totalActual += actRet;
        }

        Map<String, dynamic>? latestSubmission;
        if (status == 'PAYMENT_PENDING' || status == 'PENDING') {
          final subRes = await queryNeonHttp('''
            SELECT "id", "status"::text, "transactionRef", "rejectionReason", "createdAt"
            FROM manual_payment_submissions
            WHERE "investmentId" = \$1
            ORDER BY "createdAt" DESC
            LIMIT 1
          ''', [invId]);

          if (subRes.isNotEmpty) {
            final s = subRes.first;
            latestSubmission = {
              'id': s['id'].toString(),
              'status': s['status']?.toString() ?? 'SUBMITTED',
              'transactionRef': s['transactionRef']?.toString() ?? '',
              'rejectionReason': s['rejectionReason']?.toString(),
              'createdAt': s['createdAt']?.toString() ?? '',
            };
          }
        }

        investmentsList.add({
          'id': invId,
          'projectId': projectId,
          'title': title,
          'category': category,
          'slug': slug,
          'durationDays': durationDays,
          'location': location,
          'amountBdt': amt,
          'expectedReturnBdt': expRet,
          'actualReturnBdt': actRet,
          'status': status,
          'createdAt': createdAt,
          'activatedAt': activatedAt,
          'fundedAmountBdt': funded,
          'fundingGoalBdt': goal,
          'expectedReturnPct': returnPct,
          'latestSubmission': latestSubmission,
        });
      }

      final bankRes = await queryNeonHttp('''
        SELECT "id", "bankName", "accountName", "accountNumber", "branchName", "mobileNumber"
        FROM bank_accounts
        WHERE "isActive" = true
        ORDER BY "displayOrder" ASC
      ''');

      final List<Map<String, dynamic>> bankAccounts = bankRes.map((r) {
        return {
          'id': r['id'].toString(),
          'bankName': r['bankName']?.toString() ?? 'Bank',
          'accountName': r['accountName']?.toString() ?? 'Biniyog Club',
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
    try {
      final submissionId = _generateUuid();
      final nowStr = DateTime.now().toUtc().toIso8601String();

      await executeNeonHttp('''
        INSERT INTO manual_payment_submissions (
          "id", "investmentId", "submittedBy", "status", "amountBdt",
          "bankAccountId", "paymentMethod", "transactionRef", "proofFileUrl",
          "proofMimeType", "notes", "createdAt", "updatedAt"
        ) VALUES (
          \$1, \$2, \$3, 'SUBMITTED'::"ManualPaymentStatus", \$4,
          \$5, 'BANK_TRANSFER', \$6, \$7,
          'image/png', \$8, \$9, \$9
        )
      ''', [
        submissionId,
        investmentId,
        userId,
        amountBdt,
        bankAccountId.isEmpty ? null : bankAccountId,
        transactionRef,
        proofFileUrl.isEmpty ? 'receipt.png' : proofFileUrl,
        notes,
        nowStr,
      ]);

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

  // Fetch Projects Data
  static Future<Map<String, dynamic>> getProjectsData() async {
    try {
      final projectsRes = await queryNeonHttp('''
        SELECT p."id", p."title", p."category"::text, p."description", p."fundingGoalBdt", p."fundedAmountBdt",
               p."minInvestmentBdt", p."expectedReturnPct", p."durationDays", p."coverImageUrl", p."status"::text,
               p."location", p."fundingDeadline",
               (SELECT COUNT(DISTINCT i."investorProfileId") FROM investments i WHERE i."projectId" = p."id") as "investorsCount"
        FROM projects p
        ORDER BY p."createdAt" DESC
      ''');

      final List<Map<String, dynamic>> projects = projectsRes.map((r) {
        final goal = double.tryParse(r['fundingGoalBdt']?.toString() ?? '1') ?? 1.0;
        final funded = double.tryParse(r['fundedAmountBdt']?.toString() ?? '0') ?? 0.0;
        final pct = goal > 0 ? (funded / goal).clamp(0.0, 1.0) : 0.0;

        final rawCover = r['coverImageUrl']?.toString();
        final coverUrl = formatImageUrl(rawCover);

        final location = r['location']?.toString() ?? 'Narayanganj';
        final deadlineStr = r['fundingDeadline']?.toString();
        int daysLeft = 116;
        if (deadlineStr != null) {
          try {
            final deadline = DateTime.parse(deadlineStr);
            daysLeft = deadline.difference(DateTime.now()).inDays.clamp(0, 365);
          } catch (_) {}
        }

        final investorsCount = int.tryParse(r['investorsCount']?.toString() ?? '1') ?? 1;

        return {
          'id': r['id'].toString(),
          'title': r['title']?.toString() ?? 'Biniyog Project',
          'category': r['category']?.toString() ?? 'SME',
          'description': r['description']?.toString() ?? '',
          'fundingGoalBdt': goal,
          'fundedAmountBdt': funded,
          'progress': pct,
          'minInvestmentBdt': double.tryParse(r['minInvestmentBdt']?.toString() ?? '10000') ?? 10000.0,
          'expectedReturnPct': double.tryParse(r['expectedReturnPct']?.toString() ?? '0.15') ?? 0.15,
          'durationDays': int.tryParse(r['durationDays']?.toString() ?? '180') ?? 180,
          'coverImageUrl': coverUrl,
          'status': r['status']?.toString() ?? 'FUNDRAISING',
          'location': location.isEmpty ? 'Bangladesh' : location,
          'daysLeft': daysLeft,
          'investorsCount': investorsCount,
        };
      }).toList();

      final updatesRes = await queryNeonHttp('''
        SELECT u."id", u."title", u."content", u."type"::text, u."createdAt", p."title" as "projectTitle"
        FROM project_updates u
        JOIN projects p ON u."projectId" = p."id"
        WHERE u."isPublished" = true
        ORDER BY u."createdAt" DESC
        LIMIT 10
      ''');

      final List<Map<String, dynamic>> updates = updatesRes.map((r) {
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
        'projects': projects,
        'updates': updates,
      };
    } catch (e) {
      debugPrint("Get Projects Data Error: $e");
      return {};
    }
  }

  // Fetch Transactions
  static Future<List<Map<String, dynamic>>> getTransactionsData(String userId) async {
    if (userId.isEmpty) return [];
    try {
      final payRes = await queryNeonHttp('''
        SELECT p."id", p."amountBdt", p."feeBdt", p."netAmountBdt", p."direction"::text, p."method"::text, p."status"::text, p."description", p."createdAt"
        FROM payments p
        JOIN wallets w ON p."walletId" = w.id
        WHERE w."userId" = \$1
        ORDER BY p."createdAt" DESC
      ''', [userId]);

      final List<Map<String, dynamic>> list = payRes.map((r) {
        return {
          'id': r['id'].toString(),
          'amountBdt': double.tryParse(r['amountBdt']?.toString() ?? '0') ?? 0.0,
          'feeBdt': double.tryParse(r['feeBdt']?.toString() ?? '0') ?? 0.0,
          'netAmountBdt': double.tryParse(r['netAmountBdt']?.toString() ?? '0') ?? 0.0,
          'direction': r['direction']?.toString() ?? 'INBOUND',
          'method': r['method']?.toString() ?? 'BANK_TRANSFER',
          'status': r['status']?.toString() ?? 'COMPLETED',
          'description': r['description']?.toString() ?? 'Wallet Transaction',
          'createdAt': r['createdAt']?.toString() ?? '',
        };
      }).toList();

      final withRes = await queryNeonHttp('''
        SELECT w."id", w."amountBdt", w."feeBdt", w."netAmountBdt", w."method"::text, w."status"::text, w."bankName", w."requestedAt"
        FROM withdrawals w
        JOIN wallets wa ON w."walletId" = wa.id
        WHERE wa."userId" = \$1
        ORDER BY w."requestedAt" DESC
      ''', [userId]);

      for (final r in withRes) {
        list.add({
          'id': r['id'].toString(),
          'amountBdt': double.tryParse(r['amountBdt']?.toString() ?? '0') ?? 0.0,
          'feeBdt': double.tryParse(r['feeBdt']?.toString() ?? '0') ?? 0.0,
          'netAmountBdt': double.tryParse(r['netAmountBdt']?.toString() ?? '0') ?? 0.0,
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

  static Future<void> _saveKycDocument(
      Connection conn, String kycId, String docType, String? fileData) async {
    if (fileData == null || fileData.isEmpty) return;
    try {
      final docId = _generateUuid();
      final nowStr = DateTime.now().toUtc().toIso8601String();

      await executeNeonHttp('''
        INSERT INTO kyc_documents (
          "id", "kycId", "documentType", "storageKey", "mimeType", "sizeBytes", "createdAt"
        ) VALUES (
          \$1, \$2, \$3, \$4, 'image/png', \$5, \$6
        )
      ''', [docId, kycId, docType, fileData, fileData.length, nowStr]);
    } catch (e) {
      debugPrint("Save KYC Document Warning: $e");
    }
  }
}
