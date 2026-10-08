import 'dart:convert';
import 'dart:math';
import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import '../config/db_config.dart';

class DatabaseService {
  static Connection? _connection;

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

  // Open & get active connection to Neon PostgreSQL
  static Future<Connection?> getConnection() async {
    try {
      if (_connection != null && _connection!.isOpen) {
        return _connection!;
      }

      final dbUrl = DbConfig.databaseUrl.trim();

      if (dbUrl.isEmpty) {
        debugPrint("Database Connection Error: DATABASE_URL is empty in .env file");
        return null;
      }

      if (dbUrl.startsWith("postgres://") || dbUrl.startsWith("postgresql://")) {
        // Parse database URL
        final uri = Uri.parse(dbUrl);
        final userInfo = uri.userInfo.split(':');
        final username = userInfo.isNotEmpty ? Uri.decodeComponent(userInfo[0]) : '';
        final password = userInfo.length > 1 ? Uri.decodeComponent(userInfo[1]) : '';
        final host = uri.host;
        final port = uri.port != 0 ? uri.port : 5432;
        final database = uri.path.replaceAll('/', '');

        _connection = await Connection.open(
          Endpoint(
            host: host,
            database: database,
            username: username,
            password: password,
            port: port,
          ),
          settings: const ConnectionSettings(
            sslMode: SslMode.require,
          ),
        );
      } else {
        debugPrint("Invalid DATABASE_URL format in .env file.");
        return null;
      }

      return _connection!;
    } catch (e) {
      debugPrint("Database Connection Error: $e");
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
  static Future<void> _ensureInvestorProfileExists(Connection conn, String userId) async {
    try {
      final now = DateTime.now().toUtc();
      final profileId = _generateUuid();

      await conn.execute(
        Sql.named('''
          INSERT INTO investor_profiles (
            "id", "userId", "country", "createdAt", "updatedAt"
          ) VALUES (
            @id, @userId, 'BD', @now, @now
          )
          ON CONFLICT ("userId") DO NOTHING;
        '''),
        parameters: {'id': profileId, 'userId': userId, 'now': now},
      );

      // Verify email if not verified for website compatibility
      await conn.execute(
        Sql.named('''
          UPDATE users
          SET "emailVerified" = true
          WHERE "id" = @userId AND ("emailVerified" IS NOT TRUE OR "emailVerified" IS NULL);
        '''),
        parameters: {'userId': userId},
      );
    } catch (e) {
      debugPrint("Ensure Investor Profile Error: $e");
    }
  }

  // Register User matching exact Prisma 'users' table
  static Future<Map<String, dynamic>> registerUser({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      final conn = await getConnection();
      if (conn == null) {
        return {
          'success': false,
          'message': 'Could not connect to Neon Postgres DB. Please check .env',
        };
      }

      final hashedPassword = hashPassword(password);
      final cleanEmail = email.trim().toLowerCase();
      final cleanPhone = phone.trim();

      // Pre-check if email OR phone already exists in users table
      final existing = await conn.execute(
        Sql.named('SELECT "id", "email", "phone" FROM users WHERE LOWER("email") = LOWER(@email) OR ("phone" = @phone AND @phone != \'\')'),
        parameters: {'email': cleanEmail, 'phone': cleanPhone},
      );

      if (existing.isNotEmpty) {
        final existingPhone = existing.first[2]?.toString();
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

      final userId = _generateUuid();
      final profileId = _generateUuid();
      final now = DateTime.now().toUtc();

      // 1. Insert user into users table with emailVerified = true for website compatibility
      await conn.execute(
        Sql.named('''
          INSERT INTO users (
            "id", "email", "passwordHash", "name", "phone", "role", "status", "emailVerified", "createdAt", "updatedAt"
          ) VALUES (
            @id, @email, @passwordHash, @name, @phone, 'INVESTOR'::"UserRole", 'ACTIVE'::"UserStatus", true, @createdAt, @updatedAt
          )
        '''),
        parameters: {
          'id': userId,
          'email': cleanEmail,
          'passwordHash': hashedPassword,
          'name': name.trim(),
          'phone': cleanPhone.isEmpty ? null : cleanPhone,
          'createdAt': now,
          'updatedAt': now,
        },
      );

      // 2. Create investor_profiles record for website compatibility
      await conn.execute(
        Sql.named('''
          INSERT INTO investor_profiles (
            "id", "userId", "country", "createdAt", "updatedAt"
          ) VALUES (
            @id, @userId, 'BD', @createdAt, @updatedAt
          )
          ON CONFLICT ("userId") DO NOTHING;
        '''),
        parameters: {
          'id': profileId,
          'userId': userId,
          'createdAt': now,
          'updatedAt': now,
        },
      );

      // 3. Create empty wallet for new user
      final walletId = _generateUuid();
      await conn.execute(
        Sql.named('''
          INSERT INTO wallets ("id", "userId", "type", "cachedBalance", "currency", "isActive", "createdAt", "updatedAt")
          VALUES (@id, @userId, 'INVESTOR'::"WalletType", 0.00, 'BDT', true, @createdAt, @updatedAt)
          ON CONFLICT ("userId") DO NOTHING;
        '''),
        parameters: {
          'id': walletId,
          'userId': userId,
          'createdAt': now,
          'updatedAt': now,
        },
      );

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
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  // Login User matching exact Prisma 'users' table (supports login by email or phone)
  static Future<Map<String, dynamic>> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      final conn = await getConnection();
      if (conn == null) {
        return {
          'success': false,
          'message': 'Could not connect to Neon Postgres DB. Please check .env',
        };
      }

      final cleanInput = email.trim();

      final result = await conn.execute(
        Sql.named('''
          SELECT "id", "name", "email", "phone", "passwordHash", "avatarUrl" 
          FROM users 
          WHERE LOWER("email") = LOWER(@input) OR "phone" = @input
        '''),
        parameters: {
          'input': cleanInput,
        },
      );

      if (result.isEmpty) {
        return {
          'success': false,
          'message': 'User not found. Please check credentials or register first.',
        };
      }

      final row = result.first;
      final dbPassword = row[4] != null ? row[4].toString() : '';

      if (!verifyPassword(password, dbPassword)) {
        return {
          'success': false,
          'message': 'Incorrect password. Please try again.',
        };
      }

      // Query User Status & Soft Deletion Status
      final userStatusRes = await conn.execute(
        Sql.named('SELECT "status"::text, "updatedAt" FROM users WHERE "id" = @id'),
        parameters: {'id': row[0].toString()},
      );

      bool wasRestored = false;
      if (userStatusRes.isNotEmpty) {
        final st = userStatusRes.first[0]?.toString() ?? 'ACTIVE';
        final updatedAtStr = userStatusRes.first[1]?.toString();

        if (st == 'SUSPENDED') {
          // Check if within 7 days deletion window
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

          // Restore account within 7 days
          await conn.execute(
            Sql.named('''
              UPDATE users
              SET "status" = 'ACTIVE'::"UserStatus", "updatedAt" = @now
              WHERE "id" = @id
            '''),
            parameters: {'id': row[0].toString(), 'now': now},
          );
          wasRestored = true;
        }
      }

      // Auto-backfill investor_profiles & emailVerified for website compatibility
      await _ensureInvestorProfileExists(conn, row[0].toString());

      final rawAvatar = row[5]?.toString();

      final userData = {
        'id': row[0].toString(),
        'name': row[1].toString(),
        'email': row[2].toString(),
        'phone': row[3]?.toString() ?? '',
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

  // Change Password directly in Neon PostgreSQL DB
  static Future<Map<String, dynamic>> changePassword({
    required String userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final conn = await getConnection();
      if (conn == null) {
        return {'success': false, 'message': 'Database connection failed.'};
      }

      // 1. Fetch current password hash
      final userRes = await conn.execute(
        Sql.named('SELECT "passwordHash" FROM users WHERE "id" = @userId'),
        parameters: {'userId': userId},
      );

      if (userRes.isEmpty) {
        return {'success': false, 'message': 'User not found.'};
      }

      final dbPasswordHash = userRes.first[0]?.toString() ?? '';

      // 2. Verify old password
      if (!verifyPassword(oldPassword, dbPasswordHash)) {
        return {
          'success': false,
          'message': 'Incorrect current password. Please try again.',
        };
      }

      // 3. Hash new password and update in users table
      final newHash = hashPassword(newPassword);
      final now = DateTime.now().toUtc();

      await conn.execute(
        Sql.named('''
          UPDATE users
          SET "passwordHash" = @newHash, "updatedAt" = @now
          WHERE "id" = @userId
        '''),
        parameters: {
          'newHash': newHash,
          'userId': userId,
          'now': now,
        },
      );

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

  // Request Account Deletion (Schedules Deletion in 7 Days Buffer)
  static Future<Map<String, dynamic>> requestAccountDeletion({
    required String userId,
    required String password,
  }) async {
    try {
      final conn = await getConnection();
      if (conn == null) {
        return {'success': false, 'message': 'Database connection failed.'};
      }

      // 1. Fetch current password hash
      final userRes = await conn.execute(
        Sql.named('SELECT "passwordHash" FROM users WHERE "id" = @userId'),
        parameters: {'userId': userId},
      );

      if (userRes.isEmpty) {
        return {'success': false, 'message': 'User not found.'};
      }

      final dbPasswordHash = userRes.first[0]?.toString() ?? '';

      // 2. Verify password
      if (!verifyPassword(password, dbPasswordHash)) {
        return {
          'success': false,
          'message': 'Incorrect password. Account deletion canceled.',
        };
      }

      // 3. Mark status = 'SUSPENDED' in Neon DB
      final now = DateTime.now().toUtc();
      await conn.execute(
        Sql.named('''
          UPDATE users
          SET "status" = 'SUSPENDED'::"UserStatus", "updatedAt" = @now
          WHERE "id" = @userId
        '''),
        parameters: {
          'userId': userId,
          'now': now,
        },
      );

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

  // Send Forgot Password OTP via Resend.com Email API
  static Future<Map<String, dynamic>> sendForgotPasswordOtp(String email) async {
    try {
      final conn = await getConnection();
      if (conn == null) {
        return {'success': false, 'message': 'Database connection failed.'};
      }

      final cleanEmail = email.trim().toLowerCase();

      // 1. Check if user exists in Neon DB
      final userRes = await conn.execute(
        Sql.named('SELECT "id", "name" FROM users WHERE LOWER("email") = LOWER(@email)'),
        parameters: {'email': cleanEmail},
      );

      if (userRes.isEmpty) {
        return {
          'success': false,
          'message': 'No registered account found with this email address.',
        };
      }

      final userName = userRes.first[1]?.toString() ?? 'Investor';

      // 2. Generate 6-digit OTP code
      final random = Random.secure();
      final otp = (100000 + random.nextInt(900000)).toString();

      // 3. Ensure password_reset_tokens table exists in Neon DB
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS password_reset_tokens (
          "id" TEXT PRIMARY KEY,
          "email" TEXT NOT NULL,
          "token" TEXT NOT NULL,
          "expiresAt" TIMESTAMP WITH TIME ZONE NOT NULL,
          "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL
        );
      ''');

      // Save OTP code valid for 15 minutes
      final tokenId = _generateUuid();
      final now = DateTime.now().toUtc();
      final expiresAt = now.add(const Duration(minutes: 15));

      await conn.execute(
        Sql.named('''
          INSERT INTO password_reset_tokens ("id", "email", "token", "expiresAt", "createdAt")
          VALUES (@id, @email, @token, @expiresAt, @createdAt)
        '''),
        parameters: {
          'id': tokenId,
          'email': cleanEmail,
          'token': otp,
          'expiresAt': expiresAt,
          'createdAt': now,
        },
      );

      // 4. Send Email via Resend.com API
      final apiKey = DbConfig.resendApiKey.trim();

      if (apiKey.isNotEmpty && apiKey != 'your_resend_api_key') {
        final resendUrl = Uri.parse('https://api.resend.com/emails');
        final response = await http.post(
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

        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint("Resend Email Sent Successfully to $cleanEmail!");
        } else {
          debugPrint("Resend Email API Warning: Status ${response.statusCode} - ${response.body}");
        }
      } else {
        debugPrint("RESEND_API_KEY is not configured in .env. Generated OTP for $cleanEmail is: $otp");
      }

      return {
        'success': true,
        'otp': otp,
        'message': 'OTP sent successfully to $cleanEmail!',
      };
    } catch (e) {
      debugPrint("Send Forgot Password OTP Error: $e");
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  // Verify Reset OTP Code
  static Future<Map<String, dynamic>> verifyResetOtp(String email, String otp) async {
    try {
      final conn = await getConnection();
      if (conn == null) {
        return {'success': false, 'message': 'Database connection failed.'};
      }

      final cleanEmail = email.trim().toLowerCase();
      final cleanOtp = otp.trim();

      final res = await conn.execute(
        Sql.named('''
          SELECT "id", "expiresAt" FROM password_reset_tokens
          WHERE LOWER("email") = LOWER(@email) AND "token" = @token
          ORDER BY "createdAt" DESC
          LIMIT 1
        '''),
        parameters: {'email': cleanEmail, 'token': cleanOtp},
      );

      if (res.isEmpty) {
        return {
          'success': false,
          'message': 'Invalid OTP code. Please check and try again.',
        };
      }

      final expiresAtStr = res.first[1]?.toString();
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
      final conn = await getConnection();
      if (conn == null) {
        return {'success': false, 'message': 'Database connection failed.'};
      }

      // 1. Verify OTP first
      final verifyRes = await verifyResetOtp(email, otp);
      if (verifyRes['success'] != true) {
        return verifyRes;
      }

      final cleanEmail = email.trim().toLowerCase();
      final hashedPassword = hashPassword(newPassword);
      final now = DateTime.now().toUtc();

      // 2. Update user's password in users table
      await conn.execute(
        Sql.named('''
          UPDATE users
          SET "passwordHash" = @hashedPassword, "updatedAt" = @now
          WHERE LOWER("email") = LOWER(@email)
        '''),
        parameters: {
          'hashedPassword': hashedPassword,
          'email': cleanEmail,
          'now': now,
        },
      );

      // 3. Delete used reset tokens
      await conn.execute(
        Sql.named('DELETE FROM password_reset_tokens WHERE LOWER("email") = LOWER(@email)'),
        parameters: {'email': cleanEmail},
      );

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

  // Update User Profile Avatar URL in Neon PostgreSQL DB
  static Future<Map<String, dynamic>> updateUserAvatar({
    required String userId,
    required String avatarUrl,
  }) async {
    try {
      final conn = await getConnection();
      if (conn == null) {
        return {'success': false, 'message': 'Database connection failed.'};
      }

      final now = DateTime.now().toUtc();

      await conn.execute(
        Sql.named('''
          UPDATE users
          SET "avatarUrl" = @avatarUrl, "updatedAt" = @now
          WHERE "id" = @userId
        '''),
        parameters: {
          'avatarUrl': avatarUrl,
          'userId': userId,
          'now': now,
        },
      );

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

  // Delete User Profile Avatar in Neon PostgreSQL DB
  static Future<Map<String, dynamic>> deleteUserAvatar(String userId) async {
    try {
      final conn = await getConnection();
      if (conn == null) {
        return {'success': false, 'message': 'Database connection failed.'};
      }

      final now = DateTime.now().toUtc();

      await conn.execute(
        Sql.named('''
          UPDATE users
          SET "avatarUrl" = NULL, "updatedAt" = @now
          WHERE "id" = @userId
        '''),
        parameters: {
          'userId': userId,
          'now': now,
        },
      );

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

  // Submit Real KYC Application matching Prisma 'kyc', 'kyc_documents' & 'investor_profiles'
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
      final conn = await getConnection();
      if (conn == null) {
        return {
          'success': false,
          'message': 'Database connection failed. Please check internet.',
        };
      }

      // Ensure valid userId exists in users table
      String activeUserId = userId;
      if (activeUserId.isEmpty) {
        final latestUser = await conn.execute('SELECT "id" FROM users ORDER BY "createdAt" DESC LIMIT 1');
        if (latestUser.isNotEmpty) {
          activeUserId = latestUser.first[0].toString();
        } else {
          return {
            'success': false,
            'message': 'No registered user found in database. Please log in first.',
          };
        }
      }

      final now = DateTime.now().toUtc();

      // Convert String documentType to valid KycDocumentType enum
      String docEnum = 'NATIONAL_ID';
      if (documentType.contains('PASSPORT')) {
        docEnum = 'PASSPORT';
      } else if (documentType.contains('DRIVING')) {
        docEnum = 'DRIVING_LICENSE';
      }

      // Check if existing KYC record for user
      final existingKyc = await conn.execute(
        Sql.named('SELECT "id" FROM kyc WHERE "userId" = @userId'),
        parameters: {'userId': activeUserId},
      );

      String kycId;

      if (existingKyc.isNotEmpty) {
        kycId = existingKyc.first[0].toString();

        await conn.execute(
          Sql.named('''
            UPDATE kyc SET 
              "status" = 'SUBMITTED'::"KycStatus",
              "fullName" = @fullName,
              "documentType" = @docEnum::"KycDocumentType",
              "documentNumber" = @documentNumber,
              "presentAddress" = @address,
              "presentDivision" = @division,
              "presentDistrict" = @district,
              "presentUpazila" = @thana,
              "bankName" = @bankName,
              "bankAccountNumber" = @bankAccountNumber,
              "mobileProvider" = @mobileProvider,
              "mobileNumber" = @mobileNumber,
              "submittedAt" = @submittedAt,
              "updatedAt" = @updatedAt
            WHERE "id" = @id
          '''),
          parameters: {
            'id': kycId,
            'fullName': fullName,
            'docEnum': docEnum,
            'documentNumber': documentNumber,
            'address': address,
            'division': division,
            'district': district,
            'thana': thana,
            'bankName': bankName,
            'bankAccountNumber': bankAccountNumber,
            'mobileProvider': mobileProvider,
            'mobileNumber': mobileNumber,
            'submittedAt': now,
            'updatedAt': now,
          },
        );
      } else {
        kycId = _generateUuid();

        await conn.execute(
          Sql.named('''
            INSERT INTO kyc (
              "id", "userId", "status", "fullName", "documentType", "documentNumber",
              "presentAddress", "presentDivision", "presentDistrict", "presentUpazila",
              "bankName", "bankAccountNumber", "mobileProvider", "mobileNumber",
              "submittedAt", "createdAt", "updatedAt"
            ) VALUES (
              @id, @userId, 'SUBMITTED'::"KycStatus", @fullName, @docEnum::"KycDocumentType", @documentNumber,
              @address, @division, @district, @thana,
              @bankName, @bankAccountNumber, @mobileProvider, @mobileNumber,
              @submittedAt, @createdAt, @updatedAt
            )
          '''),
          parameters: {
            'id': kycId,
            'userId': activeUserId,
            'fullName': fullName,
            'docEnum': docEnum,
            'documentNumber': documentNumber,
            'address': address,
            'division': division,
            'district': district,
            'thana': thana,
            'bankName': bankName,
            'bankAccountNumber': bankAccountNumber,
            'mobileProvider': mobileProvider,
            'mobileNumber': mobileNumber,
            'submittedAt': now,
            'createdAt': now,
            'updatedAt': now,
          },
        );
      }

      // Upsert InvestorProfile for nominee information
      final profileId = _generateUuid();
      await conn.execute(
        Sql.named('''
          INSERT INTO investor_profiles ("id", "userId", "nomineeNationalId", "nomineeRelation", "address", "city", "country", "createdAt", "updatedAt")
          VALUES (@id, @userId, @nomineeNid, @nomineeRelation, @address, @district, 'BD', @createdAt, @updatedAt)
          ON CONFLICT ("userId") DO UPDATE SET
            "nomineeNationalId" = EXCLUDED."nomineeNationalId",
            "nomineeRelation" = EXCLUDED."nomineeRelation",
            "updatedAt" = EXCLUDED."updatedAt";
        '''),
        parameters: {
          'id': profileId,
          'userId': activeUserId,
          'nomineeNid': nomineeNid,
          'nomineeRelation': nomineeRelation,
          'address': address,
          'district': district,
          'createdAt': now,
          'updatedAt': now,
        },
      );

      // Save NID documents into kyc_documents
      await _saveKycDocument(conn, kycId, 'NID_FRONT', frontPhotoBase64);
      await _saveKycDocument(conn, kycId, 'NID_BACK', backPhotoBase64);
      await _saveKycDocument(conn, kycId, 'NOMINEE_FRONT', nomineeFrontBase64);
      await _saveKycDocument(conn, kycId, 'NOMINEE_BACK', nomineeBackBase64);

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

  // Standard Create New Investment (Strictly follows Prisma & DB constraints)
  static Future<Map<String, dynamic>> createInvestment({
    required String userId,
    required String projectId,
    required double amountBdt,
    bool useWalletBalance = false,
  }) async {
    try {
      final conn = await getConnection();
      if (conn == null) {
        return {'success': false, 'message': 'Database connection failed.'};
      }

      String activeUserId = userId;
      if (activeUserId.isEmpty) {
        final latestUser = await conn.execute('SELECT "id" FROM users ORDER BY "createdAt" DESC LIMIT 1');
        if (latestUser.isNotEmpty) activeUserId = latestUser.first[0].toString();
      }

      // 1. Check KYC Status
      final kycRes = await conn.execute(
        Sql.named('SELECT "status"::text FROM kyc WHERE "userId" = @userId'),
        parameters: {'userId': activeUserId},
      );
      if (kycRes.isEmpty || kycRes.first[0]?.toString() != 'VERIFIED') {
        return {
          'success': false,
          'message': 'KYC verification required. Please complete and get your KYC approved before investing.',
        };
      }

      // 2. Fetch or Create InvestorProfile
      String profileId;
      final profRes = await conn.execute(
        Sql.named('SELECT "id" FROM investor_profiles WHERE "userId" = @userId'),
        parameters: {'userId': activeUserId},
      );
      if (profRes.isNotEmpty) {
        profileId = profRes.first[0].toString();
      } else {
        profileId = _generateUuid();
        final now = DateTime.now().toUtc();
        await conn.execute(
          Sql.named('''
            INSERT INTO investor_profiles ("id", "userId", "createdAt", "updatedAt")
            VALUES (@id, @userId, @now, @now)
          '''),
          parameters: {'id': profileId, 'userId': activeUserId, 'now': now},
        );
      }

      // 3. Fetch Project Details
      final projRes = await conn.execute(
        Sql.named('''
          SELECT "id", "status"::text, "fundingGoalBdt", "fundedAmountBdt", "minInvestmentBdt",
                 "maxInvestmentBdt", "expectedReturnPct", "returnType"::text
          FROM projects
          WHERE "id" = @projectId
        '''),
        parameters: {'projectId': projectId},
      );

      if (projRes.isEmpty) {
        return {'success': false, 'message': 'Project not found.'};
      }

      final p = projRes.first;
      final status = p[1]?.toString() ?? 'DRAFT';
      if (status != 'FUNDRAISING') {
        return {
          'success': false,
          'message': 'Project is not currently open for fundraising (Status: $status).',
        };
      }

      final goal = double.tryParse(p[2]?.toString() ?? '1') ?? 1.0;
      final funded = double.tryParse(p[3]?.toString() ?? '0') ?? 0.0;
      final minInv = double.tryParse(p[4]?.toString() ?? '10000') ?? 10000.0;
      final maxInv = double.tryParse(p[5]?.toString() ?? '0');
      final returnPct = double.tryParse(p[6]?.toString() ?? '0.15') ?? 0.15;
      final returnType = p[7]?.toString() ?? 'FIXED_RETURN';

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
      final now = DateTime.now().toUtc();

      // Direct Investment via Bank Transfer -> Creates PENDING investment record
      await conn.execute(
        Sql.named('''
          INSERT INTO investments (
            "id", "investorProfileId", "projectId", "status", "amountBdt",
            "expectedReturnBdt", "returnType", "idempotencyKey", "createdAt", "updatedAt"
          ) VALUES (
            @id, @profileId, @projectId, 'PENDING'::"InvestmentStatus", @amountBdt,
            @expectedReturnBdt, @returnType::"ReturnType", @idempotencyKey, @now, @now
          )
        '''),
        parameters: {
          'id': investmentId,
          'profileId': profileId,
          'projectId': projectId,
          'amountBdt': amountBdt,
          'expectedReturnBdt': expectedReturnBdt,
          'returnType': returnType,
          'idempotencyKey': idempotencyKey,
          'now': now,
        },
      );

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

  // Fetch Full Single Project Detail from Neon Postgres matching Next.js getProjectBySlug
  static Future<Map<String, dynamic>> getProjectDetail(String projectIdOrSlug) async {
    try {
      final conn = await getConnection();
      if (conn == null) return {};

      final projRes = await conn.execute(
        Sql.named('''
          SELECT p."id", p."title", p."slug", p."description", p."category"::text, p."status"::text,
                 p."riskInfo", p."location", p."fundingGoalBdt", p."fundingMinBdt", p."fundedAmountBdt",
                 p."minInvestmentBdt", p."maxInvestmentBdt", p."expectedReturnPct", p."returnType"::text,
                 p."durationDays", p."fundingDeadline", p."startDate", p."endDate", p."coverImageUrl",
                 p."imageUrls", bg."name" as groupName,
                 (SELECT COUNT(DISTINCT i."investorProfileId") FROM investments i WHERE i."projectId" = p."id") as investorsCount
          FROM projects p
          LEFT JOIN business_groups bg ON p."groupId" = bg."id"
          WHERE p."id" = @idOrSlug OR p."slug" = @idOrSlug
        '''),
        parameters: {'idOrSlug': projectIdOrSlug},
      );

      if (projRes.isEmpty) return {};

      final r = projRes.first;
      final projectId = r[0].toString();

      final goal = double.tryParse(r[8]?.toString() ?? '1') ?? 1.0;
      final minFunding = double.tryParse(r[9]?.toString() ?? '0') ?? 0.0;
      final funded = double.tryParse(r[10]?.toString() ?? '0') ?? 0.0;
      final minInv = double.tryParse(r[11]?.toString() ?? '10000') ?? 10000.0;
      final maxInv = double.tryParse(r[12]?.toString() ?? '0');
      final returnPct = double.tryParse(r[13]?.toString() ?? '0.15') ?? 0.15;
      final returnType = r[14]?.toString() ?? 'PROFIT_SHARE';
      final durationDays = int.tryParse(r[15]?.toString() ?? '180') ?? 180;

      final remaining = (goal - funded).clamp(0.0, double.infinity);
      final pct = goal > 0 ? (funded / goal).clamp(0.0, 1.0) : 0.0;

      final coverUrl = formatImageUrl(r[19]?.toString());
      final rawImageUrls = r[20] as List?;
      List<String> imageUrls = [coverUrl];
      if (rawImageUrls != null) {
        for (final img in rawImageUrls) {
          final formatted = formatImageUrl(img?.toString());
          if (!imageUrls.contains(formatted)) imageUrls.add(formatted);
        }
      }

      final deadlineStr = r[16]?.toString();
      int daysLeft = 116;
      if (deadlineStr != null) {
        try {
          final deadline = DateTime.parse(deadlineStr);
          daysLeft = deadline.difference(DateTime.now()).inDays.clamp(0, 365);
        } catch (_) {}
      }

      // Query Project Bank Accounts
      final bankRes = await conn.execute(
        Sql.named('''
          SELECT "id", "bankName", "accountName", "accountNumber", "branchName",
                 "routingNumber", "swiftCode", "mobileNumber", "email", "branchAddress"
          FROM project_bank_accounts
          WHERE "projectId" = @projectId AND "isActive" = true
          ORDER BY "createdAt" ASC
        '''),
        parameters: {'projectId': projectId},
      );

      final List<Map<String, dynamic>> bankAccounts = bankRes.map((b) {
        return {
          'id': b[0].toString(),
          'bankName': b[1]?.toString() ?? 'Dutch-Bangla Bank Limited',
          'accountName': b[2]?.toString() ?? 'Marinozz PLC',
          'accountNumber': b[3]?.toString() ?? '',
          'branchName': b[4]?.toString() ?? '',
          'routingNumber': b[5]?.toString() ?? '',
          'swiftCode': b[6]?.toString() ?? '',
          'mobileNumber': b[7]?.toString() ?? '',
          'email': b[8]?.toString() ?? '',
          'branchAddress': b[9]?.toString() ?? '',
        };
      }).toList();

      return {
        'id': projectId,
        'title': r[1]?.toString() ?? 'Biniyog Project',
        'slug': r[2]?.toString() ?? '',
        'description': r[3]?.toString() ?? '',
        'category': r[4]?.toString() ?? 'SME',
        'status': r[5]?.toString() ?? 'FUNDRAISING',
        'riskInfo': r[6]?.toString() ?? 'Agriculture faces risks from weather, disease, market prices, input costs, and supply chain disruptions.',
        'location': r[7]?.toString() ?? 'Narayanganj',
        'fundingGoalBdt': goal,
        'fundingMinBdt': minFunding,
        'fundedAmountBdt': funded,
        'minInvestmentBdt': minInv,
        'maxInvestmentBdt': maxInv,
        'expectedReturnPct': returnPct,
        'returnType': returnType,
        'durationDays': durationDays,
        'fundingDeadline': deadlineStr ?? '2027-01-30',
        'startDate': r[17]?.toString() ?? '2026-10-07',
        'endDate': r[18]?.toString() ?? '2027-01-29',
        'coverImageUrl': coverUrl,
        'imageUrls': imageUrls,
        'groupName': r[21]?.toString() ?? 'Mariners Group',
        'investorsCount': int.tryParse(r[22]?.toString() ?? '2') ?? 2,
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

  // Fetch Full User Profile & Investor Profile from Neon Postgres
  static Future<Map<String, dynamic>> getUserProfileFull(String userId, {String? email}) async {
    try {
      final conn = await getConnection();
      if (conn == null) return {};

      String activeUserId = userId;
      String activeEmail = email ?? '';

      if (activeUserId.isEmpty && activeEmail.isNotEmpty) {
        final uRes = await conn.execute(
          Sql.named('SELECT "id" FROM users WHERE LOWER("email") = LOWER(@email)'),
          parameters: {'email': activeEmail},
        );
        if (uRes.isNotEmpty) activeUserId = uRes.first[0].toString();
      }

      if (activeUserId.isEmpty) {
        final latestUser = await conn.execute('SELECT "id", "email" FROM users ORDER BY "createdAt" DESC LIMIT 1');
        if (latestUser.isNotEmpty) {
          activeUserId = latestUser.first[0].toString();
          activeEmail = latestUser.first[1].toString();
        }
      }

      // Auto-backfill investor_profiles for website compatibility
      if (activeUserId.isNotEmpty) {
        await _ensureInvestorProfileExists(conn, activeUserId);
      }

      // Query User Info including avatarUrl
      final userRes = await conn.execute(
        Sql.named('''
          SELECT "id", "name", "email", "phone", "emailVerified", "phoneVerified", "createdAt", "avatarUrl"
          FROM users
          WHERE "id" = @userId
        '''),
        parameters: {'userId': activeUserId},
      );

      if (userRes.isEmpty) return {};

      final uRow = userRes.first;

      // Query Investor Profile
      final profRes = await conn.execute(
        Sql.named('''
          SELECT "nationalId", "address", "city", "country", "occupation",
                 "annualIncomeRange", "investmentExperience", "riskTolerance"
          FROM investor_profiles
          WHERE "userId" = @userId
        '''),
        parameters: {'userId': activeUserId},
      );

      Map<String, dynamic> profMap = {};
      if (profRes.isNotEmpty) {
        final p = profRes.first;
        profMap = {
          'nationalId': p[0]?.toString() ?? 'N/A',
          'address': p[1]?.toString() ?? 'Bangladesh',
          'city': p[2]?.toString() ?? 'Dhaka',
          'country': p[3]?.toString() ?? 'BD',
          'occupation': p[4]?.toString() ?? 'Investor',
          'annualIncomeRange': p[5]?.toString() ?? 'Standard',
          'investmentExperience': p[6]?.toString() ?? 'Intermediate',
          'riskTolerance': p[7]?.toString() ?? 'Moderate',
        };
      }

      // Query KYC status
      String kycStatus = 'NOT_STARTED';
      final kycRes = await conn.execute(
        Sql.named('SELECT "status"::text FROM kyc WHERE "userId" = @userId'),
        parameters: {'userId': activeUserId},
      );
      if (kycRes.isNotEmpty) {
        kycStatus = kycRes.first[0]?.toString() ?? 'NOT_STARTED';
      }

      final rawAvatar = uRow[7]?.toString();

      return {
        'id': uRow[0].toString(),
        'name': uRow[1]?.toString() ?? 'Investor',
        'email': uRow[2]?.toString() ?? '',
        'phone': uRow[3]?.toString() ?? 'N/A',
        'emailVerified': (uRow[4] as bool?) ?? false,
        'phoneVerified': (uRow[5] as bool?) ?? false,
        'createdAt': uRow[6]?.toString() ?? '',
        'avatarUrl': rawAvatar != null && rawAvatar.isNotEmpty ? formatImageUrl(rawAvatar) : null,
        'kycStatus': kycStatus,
        'investorProfile': profMap,
      };
    } catch (e) {
      debugPrint("Get Full User Profile Error: $e");
      return {};
    }
  }

  // Fetch Specific User's Dashboard Summary Data from Neon Postgres
  // Excludes REJECTED and APPROVED submissions from pending count!
  static Future<Map<String, dynamic>> getDashboardSummary(String userId, {String? email}) async {
    try {
      final conn = await getConnection();
      if (conn == null) return {};

      String activeUserId = userId;
      String activeEmail = email ?? '';

      // Find user ID from email if userId is empty
      if (activeUserId.isEmpty && activeEmail.isNotEmpty) {
        final uRes = await conn.execute(
          Sql.named('SELECT "id" FROM users WHERE LOWER("email") = LOWER(@email)'),
          parameters: {'email': activeEmail},
        );
        if (uRes.isNotEmpty) {
          activeUserId = uRes.first[0].toString();
        }
      }

      // If still empty, get latest registered user
      if (activeUserId.isEmpty) {
        final latestUser = await conn.execute('SELECT "id", "email" FROM users ORDER BY "createdAt" DESC LIMIT 1');
        if (latestUser.isNotEmpty) {
          activeUserId = latestUser.first[0].toString();
          activeEmail = latestUser.first[1].toString();
        }
      }

      // Ensure investorProfile and emailVerified exist for Website Compatibility!
      if (activeUserId.isNotEmpty) {
        await _ensureInvestorProfileExists(conn, activeUserId);
      }

      // 1. Fetch User Avatar URL from users table
      String? avatarUrl;
      final avatarRes = await conn.execute(
        Sql.named('SELECT "avatarUrl" FROM users WHERE "id" = @userId OR (LOWER("email") = LOWER(@email) AND @email != \'\')'),
        parameters: {'userId': activeUserId, 'email': activeEmail},
      );
      if (avatarRes.isNotEmpty && avatarRes.first[0] != null) {
        final rawAvatar = avatarRes.first[0].toString();
        if (rawAvatar.isNotEmpty) avatarUrl = formatImageUrl(rawAvatar);
      }

      // 2. Fetch Unread Notifications Count
      int unreadNotifCount = 0;
      final unreadRes = await conn.execute(
        Sql.named('SELECT COUNT(*) FROM notifications WHERE "userId" = @userId AND "isRead" = false'),
        parameters: {'userId': activeUserId},
      );
      if (unreadRes.isNotEmpty) {
        unreadNotifCount = int.tryParse(unreadRes.first[0].toString()) ?? 0;
      }

      // 3. Fetch KYC Status
      String kycStatus = 'NOT_STARTED';
      final kycRes = await conn.execute(
        Sql.named('''
          SELECT k."status"::text FROM kyc k
          WHERE k."userId" = @userId 
             OR k."userId" IN (SELECT "id" FROM users WHERE LOWER("email") = LOWER(@email) AND @email != '')
        '''),
        parameters: {'userId': activeUserId, 'email': activeEmail},
      );

      if (kycRes.isNotEmpty && kycRes.first[0] != null) {
        kycStatus = kycRes.first[0].toString();
      }

      // 4. Fetch Active Approved Investments Sum & Count (ONLY ACTIVE, MATURED, COMPLETED)
      double totalInvested = 0.0;
      int activeInvestmentsCount = 0;
      final invRes = await conn.execute(
        Sql.named('''
          SELECT COUNT(*), COALESCE(SUM(i."amountBdt"), 0)
          FROM investments i
          JOIN investor_profiles p ON i."investorProfileId" = p.id
          JOIN users u ON p."userId" = u."id"
          WHERE (p."userId" = @userId OR (LOWER(u."email") = LOWER(@email) AND @email != ''))
            AND i."status"::text IN ('ACTIVE', 'MATURED', 'COMPLETED')
        '''),
        parameters: {'userId': activeUserId, 'email': activeEmail},
      );
      if (invRes.isNotEmpty) {
        activeInvestmentsCount = int.tryParse(invRes.first[0].toString()) ?? 0;
        totalInvested = double.tryParse(invRes.first[1].toString()) ?? 0.0;
      }

      // 4b. Fetch Pending Transactions Count & Pending Investments Sum (Excludes REJECTED submissions)
      int pendingTransactionsCount = 0;
      double pendingInvestmentsAmount = 0.0;
      final pendingRes = await conn.execute(
        Sql.named('''
          SELECT COUNT(*), COALESCE(SUM(i."amountBdt"), 0)
          FROM investments i
          JOIN investor_profiles p ON i."investorProfileId" = p.id
          JOIN users u ON p."userId" = u."id"
          WHERE (p."userId" = @userId OR (LOWER(u."email") = LOWER(@email) AND @email != ''))
            AND i."status"::text IN ('PENDING', 'PAYMENT_PENDING')
            AND NOT EXISTS (
              SELECT 1 FROM manual_payment_submissions m
              WHERE m."investmentId" = i."id"
                AND m."status"::text IN ('REJECTED', 'APPROVED')
            )
        '''),
        parameters: {'userId': activeUserId, 'email': activeEmail},
      );
      if (pendingRes.isNotEmpty) {
        pendingTransactionsCount = int.tryParse(pendingRes.first[0].toString()) ?? 0;
        pendingInvestmentsAmount = double.tryParse(pendingRes.first[1].toString()) ?? 0.0;
      }

      // 5. Fetch Total Profit Distributions Received
      double totalReturns = 0.0;
      final returnRes = await conn.execute(
        Sql.named('''
          SELECT COALESCE(SUM(d."netAmountBdt"), 0)
          FROM profit_distributions d
          JOIN investments i ON d."investmentId" = i.id
          JOIN investor_profiles p ON i."investorProfileId" = p.id
          JOIN users u ON p."userId" = u."id"
          WHERE p."userId" = @userId OR (LOWER(u."email") = LOWER(@email) AND @email != '')
        '''),
        parameters: {'userId': activeUserId, 'email': activeEmail},
      );
      if (returnRes.isNotEmpty) {
        totalReturns = double.tryParse(returnRes.first[0].toString()) ?? 0.0;
      }

      // 6. Fetch Open Fundraising Projects
      final projectsRes = await conn.execute('''
        SELECT p."id", p."title", p."category"::text, p."fundingGoalBdt", p."fundedAmountBdt",
               p."minInvestmentBdt", p."expectedReturnPct", p."durationDays", p."coverImageUrl",
               p."location", p."fundingDeadline",
               (SELECT COUNT(DISTINCT i."investorProfileId") FROM investments i WHERE i."projectId" = p."id") as investorsCount
        FROM projects p
        ORDER BY p."createdAt" DESC
        LIMIT 5
      ''');

      final List<Map<String, dynamic>> projects = projectsRes.map((row) {
        final goal = double.tryParse(row[3]?.toString() ?? '1') ?? 1.0;
        final funded = double.tryParse(row[4]?.toString() ?? '0') ?? 0.0;
        final pct = goal > 0 ? (funded / goal).clamp(0.0, 1.0) : 0.0;

        final rawCover = row[8]?.toString();
        final coverUrl = formatImageUrl(rawCover);

        final location = row[9]?.toString() ?? 'Narayanganj';
        final deadlineStr = row[10]?.toString();
        int daysLeft = 116;
        if (deadlineStr != null) {
          try {
            final deadline = DateTime.parse(deadlineStr);
            daysLeft = deadline.difference(DateTime.now()).inDays.clamp(0, 365);
          } catch (_) {}
        }

        final investorsCount = int.tryParse(row[11]?.toString() ?? '1') ?? 1;

        return {
          'id': row[0].toString(),
          'title': row[1]?.toString() ?? 'Biniyog Project',
          'category': row[2]?.toString() ?? 'SME',
          'fundingGoalBdt': goal,
          'fundedAmountBdt': funded,
          'progress': pct,
          'minInvestmentBdt': double.tryParse(row[5]?.toString() ?? '10000') ?? 10000.0,
          'expectedReturnPct': double.tryParse(row[6]?.toString() ?? '0.15') ?? 0.15,
          'durationDays': int.tryParse(row[7]?.toString() ?? '180') ?? 180,
          'coverImageUrl': coverUrl,
          'location': location.isEmpty ? 'Bangladesh' : location,
          'daysLeft': daysLeft,
          'investorsCount': investorsCount,
        };
      }).toList();

      // 7. Fetch User's Recent Investments
      final userInvRes = await conn.execute(
        Sql.named('''
          SELECT i."id", pr."title", i."amountBdt", i."expectedReturnBdt", i."status"::text, i."createdAt"
          FROM investments i
          JOIN investor_profiles p ON i."investorProfileId" = p.id
          JOIN projects pr ON i."projectId" = pr.id
          JOIN users u ON p."userId" = u."id"
          WHERE p."userId" = @userId OR (LOWER(u."email") = LOWER(@email) AND @email != '')
          ORDER BY i."createdAt" DESC
          LIMIT 5
        '''),
        parameters: {'userId': activeUserId, 'email': activeEmail},
      );

      final List<Map<String, dynamic>> recentInvestments = userInvRes.map((row) {
        return {
          'id': row[0].toString(),
          'title': row[1]?.toString() ?? 'Investment',
          'amountBdt': double.tryParse(row[2]?.toString() ?? '0') ?? 0.0,
          'expectedReturnBdt': double.tryParse(row[3]?.toString() ?? '0') ?? 0.0,
          'status': row[4]?.toString() ?? 'PENDING',
          'createdAt': row[5]?.toString() ?? '',
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

  // Fetch Real Notifications
  static Future<List<Map<String, dynamic>>> getNotificationsData(String userId) async {
    if (userId.isEmpty) return [];
    try {
      final conn = await getConnection();
      if (conn == null) return [];

      final res = await conn.execute(
        Sql.named('''
          SELECT n."id", n."title", n."body", n."type"::text, n."isRead", n."createdAt"
          FROM notifications n
          WHERE n."userId" = @userId
          ORDER BY n."createdAt" DESC
        '''),
        parameters: {'userId': userId},
      );

      return res.map((r) {
        return {
          'id': r[0].toString(),
          'title': r[1]?.toString() ?? 'Notification',
          'body': r[2]?.toString() ?? '',
          'type': r[3]?.toString() ?? 'SYSTEM',
          'isRead': (r[4] as bool?) ?? false,
          'createdAt': r[5]?.toString() ?? '',
        };
      }).toList();
    } catch (e) {
      debugPrint("Get Notifications Error: $e");
      return [];
    }
  }

  // Mark Single Notification as Read in Neon DB
  static Future<void> markNotificationAsRead(String notificationId) async {
    try {
      final conn = await getConnection();
      if (conn == null) return;
      await conn.execute(
        Sql.named('UPDATE notifications SET "isRead" = true WHERE "id" = @id'),
        parameters: {'id': notificationId},
      );
    } catch (e) {
      debugPrint("Mark Notification Read Error: $e");
    }
  }

  // Mark All Notifications as Read in Neon DB
  static Future<void> markAllNotificationsAsRead(String userId) async {
    try {
      final conn = await getConnection();
      if (conn == null) return;
      await conn.execute(
        Sql.named('UPDATE notifications SET "isRead" = true WHERE "userId" = @userId'),
        parameters: {'userId': userId},
      );
    } catch (e) {
      debugPrint("Mark All Notifications Read Error: $e");
    }
  }

  // Upload User Document to Cloudinary & insert record into Neon PostgreSQL 'documents' table
  static Future<Map<String, dynamic>> uploadUserDocument({
    required String userId,
    required String name,
    required String category,
    required String fileUrl,
    String? description,
    int? sizeBytes,
  }) async {
    try {
      final conn = await getConnection();
      if (conn == null) {
        return {'success': false, 'message': 'Database connection failed.'};
      }

      final docId = _generateUuid();
      final now = DateTime.now().toUtc();

      // Convert String category to valid enum e.g. PAYMENT_RECEIPT
      String catEnum = 'PAYMENT_RECEIPT';
      if (category.contains('KYC')) {
        catEnum = 'KYC';
      } else if (category.contains('INVESTMENT') || category.contains('AGREEMENT')) {
        catEnum = 'INVESTMENT_AGREEMENT';
      } else if (category.contains('PROJECT')) {
        catEnum = 'PROJECT_DOCUMENT';
      }

      await conn.execute(
        Sql.named('''
          INSERT INTO documents (
            "id", "name", "category", "fileUrl", "sizeBytes", "uploadedBy", "ownerUserId", "isPublic", "createdAt", "updatedAt"
          ) VALUES (
            @id, @name, @catEnum::"DocumentCategory", @fileUrl, @sizeBytes, @userId, @userId, false, @now, @now
          )
        '''),
        parameters: {
          'id': docId,
          'name': name,
          'catEnum': catEnum,
          'fileUrl': fileUrl,
          'sizeBytes': sizeBytes ?? 36800,
          'userId': userId,
          'now': now,
        },
      );

      return {
        'success': true,
        'message': 'Document uploaded successfully to database!',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Database error: ${e.toString()}',
      };
    }
  }

  // Fetch Categorized Documents & Contracts from Neon Postgres DB matching Website 1:1
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
      final conn = await getConnection();
      if (conn == null) {
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

      final List<Map<String, dynamic>> contracts = [];
      final List<Map<String, dynamic>> kycDocs = [];
      final List<Map<String, dynamic>> paymentReceipts = [];
      final List<Map<String, dynamic>> investmentReceipts = [];
      final List<Map<String, dynamic>> distributionStatements = [];
      final List<Map<String, dynamic>> harvestReports = [];
      final List<Map<String, dynamic>> projectDocs = [];

      // 1. Fetch Investment Contracts & Investment Receipts
      final invRes = await conn.execute(
        Sql.named('''
          SELECT i."id", pr."title", pr."location", pr."returnType"::text, pr."expectedReturnPct",
                 i."amountBdt", i."expectedReturnBdt", i."status"::text, i."createdAt",
                 u."name", u."email", u."phone"
          FROM investments i
          JOIN investor_profiles p ON i."investorProfileId" = p.id
          JOIN projects pr ON i."projectId" = pr.id
          JOIN users u ON p."userId" = u."id"
          WHERE p."userId" = @userId OR u."id" = @userId
          ORDER BY i."createdAt" DESC
        '''),
        parameters: {'userId': userId},
      );

      for (final r in invRes) {
        final invId = r[0].toString();
        final projTitle = r[1]?.toString() ?? 'Biniyog Project';
        final location = r[2]?.toString() ?? 'Dhaka, Bangladesh';
        final returnType = r[3]?.toString() ?? 'Hybrid';
        final returnPct = double.tryParse(r[4]?.toString() ?? '0.16') ?? 0.16;
        final amt = double.tryParse(r[5]?.toString() ?? '0') ?? 0.0;
        final expRet = double.tryParse(r[6]?.toString() ?? '0') ?? 0.0;
        final status = r[7]?.toString() ?? 'PENDING';
        final createdAt = r[8]?.toString() ?? '';
        final userName = r[9]?.toString() ?? 'Investor';
        final userEmail = r[10]?.toString() ?? '';
        final userPhone = r[11]?.toString() ?? 'N/A';

        final certNo = 'BC-${invId.substring(0, min(12, invId.length)).toUpperCase()}';
        final verifyUrl = 'https://biniyogclub.com/verify/$certNo';

        // Contract Card (Top Section)
        contracts.add({
          'id': invId,
          'title': projTitle,
          'amountBdt': amt,
          'status': status == 'PENDING' ? 'DRAFT' : status,
          'createdAt': createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt,
        });

        // Investment Receipt Card
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

      // 2. Fetch User's KYC Status Document
      final kycRes = await conn.execute(
        Sql.named('''
          SELECT k."id", k."status"::text, k."submittedAt", k."reviewedAt"
          FROM kyc k
          WHERE k."userId" = @userId
        '''),
        parameters: {'userId': userId},
      );

      if (kycRes.isNotEmpty) {
        final kRow = kycRes.first;
        final kStatus = kRow[1]?.toString() ?? 'SUBMITTED';
        final subAt = kRow[2]?.toString() ?? '';
        final revAt = kRow[3]?.toString() ?? '';

        String dateText = 'Submitted';
        if (subAt.length >= 10) dateText += ' ${subAt.substring(0, 10)}';
        if (revAt.length >= 10) dateText += ' · Reviewed ${revAt.substring(0, 10)}';

        kycDocs.add({
          'id': kRow[0].toString(),
          'title': 'KYC Verification',
          'subtitle': dateText,
          'status': kStatus == 'APPROVED' ? 'VERIFIED' : kStatus,
        });
      }

      // 3. Fetch Uploaded Documents from 'documents' table
      final docRes = await conn.execute(
        Sql.named('''
          SELECT d."id", d."name", d."category"::text, d."fileUrl", d."sizeBytes", d."createdAt"
          FROM documents d
          WHERE d."uploadedBy" = @userId OR d."ownerUserId" = @userId OR d."isPublic" = true
          ORDER BY d."createdAt" DESC
        '''),
        parameters: {'userId': userId},
      );

      for (final r in docRes) {
        final cat = r[2]?.toString() ?? 'PROJECT_DOCUMENT';
        final item = {
          'id': r[0].toString(),
          'name': r[1]?.toString() ?? 'Document',
          'category': cat,
          'fileUrl': r[3]?.toString() ?? '',
          'sizeBytes': int.tryParse(r[4]?.toString() ?? '0') ?? 36800,
          'createdAt': r[5]?.toString() ?? '',
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

  // Fetch Specific User's Real KYC Status and Submitted Documents
  static Future<Map<String, dynamic>> getKycStatus(String userId, {String? email}) async {
    try {
      final conn = await getConnection();
      if (conn == null) return {'status': 'NOT_STARTED'};

      String activeUserId = userId;
      String activeEmail = email ?? '';

      if (activeUserId.isEmpty && activeEmail.isEmpty) {
        final latestUser = await conn.execute('SELECT "id", "email" FROM users ORDER BY "createdAt" DESC LIMIT 1');
        if (latestUser.isNotEmpty) {
          activeUserId = latestUser.first[0].toString();
          activeEmail = latestUser.first[1].toString();
        }
      }

      final res = await conn.execute(
        Sql.named('''
          SELECT k."id", k."status"::text, k."fullName", k."documentType"::text, k."documentNumber",
                 k."presentDivision", k."presentDistrict", k."reviewNote", k."submittedAt", k."reviewedAt"
          FROM kyc k
          JOIN users u ON k."userId" = u."id"
          WHERE k."userId" = @userId OR (LOWER(u."email") = LOWER(@email) AND @email != '')
        '''),
        parameters: {
          'userId': activeUserId,
          'email': activeEmail,
        },
      );

      if (res.isEmpty) {
        return {'status': 'NOT_STARTED'};
      }

      final row = res.first;
      final kycId = row[0].toString();

      // Fetch uploaded documents for this specific KYC
      final docsRes = await conn.execute(
        Sql.named('SELECT "id", "documentType", "createdAt" FROM kyc_documents WHERE "kycId" = @kycId'),
        parameters: {'kycId': kycId},
      );

      final List<Map<String, dynamic>> documents = docsRes.map((d) {
        return {
          'id': d[0].toString(),
          'type': d[1]?.toString() ?? 'DOCUMENT',
          'createdAt': d[2]?.toString() ?? '',
        };
      }).toList();

      return {
        'id': kycId,
        'status': row[1]?.toString() ?? 'NOT_STARTED',
        'fullName': row[2]?.toString() ?? '',
        'documentType': row[3]?.toString() ?? '',
        'documentNumber': row[4]?.toString() ?? '',
        'division': row[5]?.toString() ?? '',
        'district': row[6]?.toString() ?? '',
        'reviewNote': row[7]?.toString(),
        'submittedAt': row[8]?.toString() ?? '',
        'reviewedAt': row[9]?.toString() ?? '',
        'documents': documents,
      };
    } catch (e) {
      debugPrint("Get KYC Status Error: $e");
      return {'status': 'NOT_STARTED'};
    }
  }

  // Fetch Specific User's Group Investments
  static Future<List<Map<String, dynamic>>> getGroupInvestmentsData(String userId) async {
    if (userId.isEmpty) return [];
    try {
      final conn = await getConnection();
      if (conn == null) return [];

      final res = await conn.execute(
        Sql.named('''
          SELECT gi."id", bg."name", ge."name", gt."name", gi."amountBdt", gi."plotNumber",
                 gi."plotSizeSqft", gi."sharePercentage", gi."status"::text, gi."createdAt"
          FROM group_investments gi
          JOIN group_tiers gt ON gi."tierId" = gt."id"
          JOIN group_entities ge ON gt."entityId" = ge."id"
          JOIN business_groups bg ON ge."groupId" = bg."id"
          WHERE gi."investorUserId" = @userId
          ORDER BY gi."createdAt" DESC
        '''),
        parameters: {'userId': userId},
      );

      return res.map((r) {
        return {
          'id': r[0].toString(),
          'groupName': r[1]?.toString() ?? 'Business Group',
          'entityName': r[2]?.toString() ?? 'Group Entity',
          'tierName': r[3]?.toString() ?? 'Tier',
          'amountBdt': double.tryParse(r[4]?.toString() ?? '0') ?? 0.0,
          'plotNumber': r[5]?.toString() ?? 'N/A',
          'plotSizeSqft': double.tryParse(r[6]?.toString() ?? '0') ?? 0.0,
          'sharePercentage': double.tryParse(r[7]?.toString() ?? '0') ?? 0.0,
          'status': r[8]?.toString() ?? 'PENDING',
          'createdAt': r[9]?.toString() ?? '',
        };
      }).toList();
    } catch (e) {
      debugPrint("Get Group Investments Error: $e");
      return [];
    }
  }

  // Fetch Real Investments Portfolio Data matching Next.js Investments Page
  static Future<Map<String, dynamic>> getPortfolioData(String userId, {String? email}) async {
    try {
      final conn = await getConnection();
      if (conn == null) return {};

      String activeUserId = userId;
      String activeEmail = email ?? '';

      if (activeUserId.isEmpty && activeEmail.isNotEmpty) {
        final uRes = await conn.execute(
          Sql.named('SELECT "id" FROM users WHERE LOWER("email") = LOWER(@email)'),
          parameters: {'email': activeEmail},
        );
        if (uRes.isNotEmpty) activeUserId = uRes.first[0].toString();
      }

      if (activeUserId.isEmpty) {
        final latestUser = await conn.execute('SELECT "id", "email" FROM users ORDER BY "createdAt" DESC LIMIT 1');
        if (latestUser.isNotEmpty) {
          activeUserId = latestUser.first[0].toString();
          activeEmail = latestUser.first[1].toString();
        }
      }

      // 1. Fetch User's Investor Profile ID
      String? profileId;
      final profRes = await conn.execute(
        Sql.named('SELECT "id" FROM investor_profiles WHERE "userId" = @userId'),
        parameters: {'userId': activeUserId},
      );
      if (profRes.isNotEmpty) {
        profileId = profRes.first[0].toString();
      }

      // 2. Query ALL Investments joined with Projects for this user
      final invRes = await conn.execute(
        Sql.named('''
          SELECT i."id", pr."id" as projectId, pr."title", pr."category"::text, pr."slug",
                 pr."durationDays", pr."location", i."amountBdt", i."expectedReturnBdt",
                 i."actualReturnBdt", i."status"::text, i."createdAt", i."activatedAt",
                 pr."fundedAmountBdt", pr."fundingGoalBdt", pr."expectedReturnPct"
          FROM investments i
          JOIN investor_profiles p ON i."investorProfileId" = p.id
          JOIN projects pr ON i."projectId" = pr.id
          JOIN users u ON p."userId" = u."id"
          WHERE p."userId" = @userId OR (LOWER(u."email") = LOWER(@email) AND @email != '') OR i."investorProfileId" = @profileId
          ORDER BY i."createdAt" DESC
        '''),
        parameters: {
          'userId': activeUserId,
          'email': activeEmail,
          'profileId': profileId ?? activeUserId,
        },
      );

      double totalInvested = 0.0;
      double totalExpected = 0.0;
      double totalActual = 0.0;

      final List<Map<String, dynamic>> investmentsList = [];

      for (final r in invRes) {
        final invId = r[0].toString();
        final projectId = r[1].toString();
        final title = r[2]?.toString() ?? 'Biniyog Project';
        final category = r[3]?.toString() ?? 'SME';
        final slug = r[4]?.toString() ?? '';
        final durationDays = int.tryParse(r[5]?.toString() ?? '180') ?? 180;
        final location = r[6]?.toString() ?? 'Bangladesh';
        final amt = double.tryParse(r[7]?.toString() ?? '0') ?? 0.0;
        final expRet = double.tryParse(r[8]?.toString() ?? '0') ?? 0.0;
        final actRet = double.tryParse(r[9]?.toString() ?? '0');
        final status = r[10]?.toString() ?? 'PENDING';
        final createdAt = r[11]?.toString() ?? '';
        final activatedAt = r[12]?.toString();
        final funded = double.tryParse(r[13]?.toString() ?? '0') ?? 0.0;
        final goal = double.tryParse(r[14]?.toString() ?? '1') ?? 1.0;
        final returnPct = double.tryParse(r[15]?.toString() ?? '0.15') ?? 0.15;

        // ONLY APPROVED ACTIVE/MATURED/COMPLETED INVESTMENTS ADD TO TOTAL INVESTED
        if (status == 'ACTIVE' || status == 'MATURED' || status == 'COMPLETED') {
          totalInvested += amt;
          totalExpected += expRet;
        }
        if (actRet != null && actRet > 0) {
          totalActual += actRet;
        }

        // Fetch latest manual payment submission for PAYMENT_PENDING
        Map<String, dynamic>? latestSubmission;
        if (status == 'PAYMENT_PENDING' || status == 'PENDING') {
          final subRes = await conn.execute(
            Sql.named('''
              SELECT "id", "status"::text, "transactionRef", "rejectionReason", "createdAt"
              FROM manual_payment_submissions
              WHERE "investmentId" = @invId
              ORDER BY "createdAt" DESC
              LIMIT 1
            '''),
            parameters: {'invId': invId},
          );
          if (subRes.isNotEmpty) {
            final s = subRes.first;
            latestSubmission = {
              'id': s[0].toString(),
              'status': s[1]?.toString() ?? 'SUBMITTED',
              'transactionRef': s[2]?.toString() ?? '',
              'rejectionReason': s[3]?.toString(),
              'createdAt': s[4]?.toString() ?? '',
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

      // Fetch Bank Accounts for Payment Submission
      final bankRes = await conn.execute('''
        SELECT "id", "bankName", "accountName", "accountNumber", "branchName", "mobileNumber"
        FROM bank_accounts
        WHERE "isActive" = true
        ORDER BY "displayOrder" ASC
      ''');

      final List<Map<String, dynamic>> bankAccounts = bankRes.map((r) {
        return {
          'id': r[0].toString(),
          'bankName': r[1]?.toString() ?? 'Bank',
          'accountName': r[2]?.toString() ?? 'Biniyog Club',
          'accountNumber': r[3]?.toString() ?? '',
          'branchName': r[4]?.toString() ?? '',
          'mobileNumber': r[5]?.toString() ?? '',
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

  // Submit Manual Payment Proof to Neon Postgres DB
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
      final conn = await getConnection();
      if (conn == null) {
        return {'success': false, 'message': 'Database connection failed.'};
      }

      final submissionId = _generateUuid();
      final now = DateTime.now().toUtc();

      // Insert into manual_payment_submissions table
      await conn.execute(
        Sql.named('''
          INSERT INTO manual_payment_submissions (
            "id", "investmentId", "submittedBy", "status", "amountBdt",
            "bankAccountId", "paymentMethod", "transactionRef", "proofFileUrl",
            "proofMimeType", "notes", "createdAt", "updatedAt"
          ) VALUES (
            @id, @investmentId, @submittedBy, 'SUBMITTED'::"ManualPaymentStatus", @amountBdt,
            @bankAccountId, 'BANK_TRANSFER', @transactionRef, @proofFileUrl,
            'image/png', @notes, @createdAt, @updatedAt
          )
        '''),
        parameters: {
          'id': submissionId,
          'investmentId': investmentId,
          'submittedBy': userId,
          'amountBdt': amountBdt,
          'bankAccountId': bankAccountId.isEmpty ? null : bankAccountId,
          'transactionRef': transactionRef,
          'proofFileUrl': proofFileUrl.isEmpty ? 'receipt.png' : proofFileUrl,
          'notes': notes,
          'createdAt': now,
          'updatedAt': now,
        },
      );

      // Update Investment status to PAYMENT_PENDING
      await conn.execute(
        Sql.named('''
          UPDATE investments
          SET "status" = 'PAYMENT_PENDING'::"InvestmentStatus", "paymentPendingAt" = @now, "updatedAt" = @now
          WHERE "id" = @investmentId
        '''),
        parameters: {
          'investmentId': investmentId,
          'now': now,
        },
      );

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

  // Fetch Open Projects & Updates with Cover Image & Location
  static Future<Map<String, dynamic>> getProjectsData() async {
    try {
      final conn = await getConnection();
      if (conn == null) return {};

      // Fetch Projects
      final projectsRes = await conn.execute('''
        SELECT p."id", p."title", p."category"::text, p."description", p."fundingGoalBdt", p."fundedAmountBdt",
               p."minInvestmentBdt", p."expectedReturnPct", p."durationDays", p."coverImageUrl", p."status"::text,
               p."location", p."fundingDeadline",
               (SELECT COUNT(DISTINCT i."investorProfileId") FROM investments i WHERE i."projectId" = p."id") as investorsCount
        FROM projects p
        ORDER BY p."createdAt" DESC
      ''');

      final List<Map<String, dynamic>> projects = projectsRes.map((r) {
        final goal = double.tryParse(r[4]?.toString() ?? '1') ?? 1.0;
        final funded = double.tryParse(r[5]?.toString() ?? '0') ?? 0.0;
        final pct = goal > 0 ? (funded / goal).clamp(0.0, 1.0) : 0.0;

        final rawCover = r[9]?.toString();
        final coverUrl = formatImageUrl(rawCover);

        final location = r[11]?.toString() ?? 'Narayanganj';
        final deadlineStr = r[12]?.toString();
        int daysLeft = 116;
        if (deadlineStr != null) {
          try {
            final deadline = DateTime.parse(deadlineStr);
            daysLeft = deadline.difference(DateTime.now()).inDays.clamp(0, 365);
          } catch (_) {}
        }

        final investorsCount = int.tryParse(r[13]?.toString() ?? '1') ?? 1;

        return {
          'id': r[0].toString(),
          'title': r[1]?.toString() ?? 'Biniyog Project',
          'category': r[2]?.toString() ?? 'SME',
          'description': r[3]?.toString() ?? '',
          'fundingGoalBdt': goal,
          'fundedAmountBdt': funded,
          'progress': pct,
          'minInvestmentBdt': double.tryParse(r[6]?.toString() ?? '10000') ?? 10000.0,
          'expectedReturnPct': double.tryParse(r[7]?.toString() ?? '0.15') ?? 0.15,
          'durationDays': int.tryParse(r[8]?.toString() ?? '180') ?? 180,
          'coverImageUrl': coverUrl,
          'status': r[10]?.toString() ?? 'FUNDRAISING',
          'location': location.isEmpty ? 'Bangladesh' : location,
          'daysLeft': daysLeft,
          'investorsCount': investorsCount,
        };
      }).toList();

      // Fetch Project Updates
      final updatesRes = await conn.execute('''
        SELECT u."id", u."title", u."content", u."type"::text, u."createdAt", p."title"
        FROM project_updates u
        JOIN projects p ON u."projectId" = p."id"
        WHERE u."isPublished" = true
        ORDER BY u."createdAt" DESC
        LIMIT 10
      ''');

      final List<Map<String, dynamic>> updates = updatesRes.map((r) {
        return {
          'id': r[0].toString(),
          'title': r[1]?.toString() ?? 'Project Update',
          'content': r[2]?.toString() ?? '',
          'type': r[3]?.toString() ?? 'GENERAL',
          'createdAt': r[4]?.toString() ?? '',
          'projectTitle': r[5]?.toString() ?? 'Project',
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

  // Fetch Specific User's Transactions Statement
  static Future<List<Map<String, dynamic>>> getTransactionsData(String userId) async {
    if (userId.isEmpty) return [];
    try {
      final conn = await getConnection();
      if (conn == null) return [];

      // Fetch Payments
      final payRes = await conn.execute(
        Sql.named('''
          SELECT p."id", p."amountBdt", p."feeBdt", p."netAmountBdt", p."direction"::text, p."method"::text, p."status"::text, p."description", p."createdAt"
          FROM payments p
          JOIN wallets w ON p."walletId" = w.id
          WHERE w."userId" = @userId
          ORDER BY p."createdAt" DESC
        '''),
        parameters: {'userId': userId},
      );

      final List<Map<String, dynamic>> list = payRes.map((r) {
        return {
          'id': r[0].toString(),
          'amountBdt': double.tryParse(r[1]?.toString() ?? '0') ?? 0.0,
          'feeBdt': double.tryParse(r[2]?.toString() ?? '0') ?? 0.0,
          'netAmountBdt': double.tryParse(r[3]?.toString() ?? '0') ?? 0.0,
          'direction': r[4]?.toString() ?? 'INBOUND',
          'method': r[5]?.toString() ?? 'BANK_TRANSFER',
          'status': r[6]?.toString() ?? 'COMPLETED',
          'description': r[7]?.toString() ?? 'Wallet Transaction',
          'createdAt': r[8]?.toString() ?? '',
        };
      }).toList();

      // Fetch Withdrawals
      final withRes = await conn.execute(
        Sql.named('''
          SELECT w."id", w."amountBdt", w."feeBdt", w."netAmountBdt", w."method"::text, w."status"::text, w."bankName", w."requestedAt"
          FROM withdrawals w
          JOIN wallets wa ON w."walletId" = wa.id
          WHERE wa."userId" = @userId
          ORDER BY w."requestedAt" DESC
        '''),
        parameters: {'userId': userId},
      );

      for (final r in withRes) {
        list.add({
          'id': r[0].toString(),
          'amountBdt': double.tryParse(r[1]?.toString() ?? '0') ?? 0.0,
          'feeBdt': double.tryParse(r[2]?.toString() ?? '0') ?? 0.0,
          'netAmountBdt': double.tryParse(r[3]?.toString() ?? '0') ?? 0.0,
          'direction': 'OUTBOUND',
          'method': r[4]?.toString() ?? 'BANK_TRANSFER',
          'status': r[5]?.toString() ?? 'PENDING',
          'description': 'Withdrawal to ${r[6]?.toString() ?? 'Bank'}',
          'createdAt': r[7]?.toString() ?? '',
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
      final now = DateTime.now().toUtc();

      await conn.execute(
        Sql.named('''
          INSERT INTO kyc_documents (
            "id", "kycId", "documentType", "storageKey", "mimeType", "sizeBytes", "createdAt"
          ) VALUES (
            @id, @kycId, @docType, @storageKey, 'image/png', @sizeBytes, @createdAt
          )
        '''),
        parameters: {
          'id': docId,
          'kycId': kycId,
          'docType': docType,
          'storageKey': fileData, // Base64 or Storage Key
          'sizeBytes': fileData.length,
          'createdAt': now,
        },
      );
    } catch (e) {
      debugPrint("Save KYC Document Warning: $e");
    }
  }
}
