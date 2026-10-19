import 'package:flutter_dotenv/flutter_dotenv.dart';

class DbConfig {
  static String get databaseUrl {
    final envVal = dotenv.env['DATABASE_URL']?.trim() ?? '';
    if (envVal.isNotEmpty) return envVal;
    return const String.fromEnvironment('DATABASE_URL', defaultValue: '');
  }

  static String get cloudinaryCloudName {
    final envVal = dotenv.env['CLOUDINARY_CLOUD_NAME']?.trim() ?? '';
    if (envVal.isNotEmpty) return envVal;
    return const String.fromEnvironment('CLOUDINARY_CLOUD_NAME', defaultValue: '');
  }

  static String get cloudinaryApiKey {
    final envVal = dotenv.env['CLOUDINARY_API_KEY']?.trim() ?? '';
    if (envVal.isNotEmpty) return envVal;
    return const String.fromEnvironment('CLOUDINARY_API_KEY', defaultValue: '');
  }

  static String get cloudinaryApiSecret {
    final envVal = dotenv.env['CLOUDINARY_API_SECRET']?.trim() ?? '';
    if (envVal.isNotEmpty) return envVal;
    return const String.fromEnvironment('CLOUDINARY_API_SECRET', defaultValue: '');
  }

  static String get resendApiKey {
    final envVal = dotenv.env['RESEND_API_KEY']?.trim() ?? '';
    if (envVal.isNotEmpty) return envVal;
    return const String.fromEnvironment('RESEND_API_KEY', defaultValue: '');
  }
}
