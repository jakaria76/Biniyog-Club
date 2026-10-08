import 'package:flutter_dotenv/flutter_dotenv.dart';

class DbConfig {
  static String get databaseUrl => dotenv.env['DATABASE_URL'] ?? '';
  static String get cloudinaryCloudName => dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? '';
  static String get cloudinaryApiKey => dotenv.env['CLOUDINARY_API_KEY'] ?? '';
  static String get cloudinaryApiSecret => dotenv.env['CLOUDINARY_API_SECRET'] ?? '';
  static String get resendApiKey => dotenv.env['RESEND_API_KEY'] ?? '';
}
