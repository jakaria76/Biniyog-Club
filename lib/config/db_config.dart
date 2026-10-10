import 'package:flutter_dotenv/flutter_dotenv.dart';

class DbConfig {
  static String get databaseUrl {
    return dotenv.env['DATABASE_URL'] ?? '';
  }

  static String get cloudinaryCloudName {
    return dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? '';
  }

  static String get cloudinaryApiKey {
    return dotenv.env['CLOUDINARY_API_KEY'] ?? '';
  }

  static String get cloudinaryApiSecret {
    return dotenv.env['CLOUDINARY_API_SECRET'] ?? '';
  }

  static String get resendApiKey {
    return dotenv.env['RESEND_API_KEY'] ?? '';
  }
}
