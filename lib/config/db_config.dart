import 'package:flutter_dotenv/flutter_dotenv.dart';

class DbConfig {
  static const String defaultDatabaseUrl =
      'postgresql://neondb_owner:npg_UaXCpI1M3YTJ@ep-withered-lake-b5bgohpl-pooler.c-7.us-east-2.aws.neon.tech/neondb?sslmode=require&channel_binding=require';

  static String get databaseUrl {
    final envUrl = dotenv.env['DATABASE_URL']?.trim() ?? '';
    return envUrl.isNotEmpty ? envUrl : defaultDatabaseUrl;
  }

  static String get cloudinaryCloudName {
    return dotenv.env['CLOUDINARY_CLOUD_NAME']?.trim().isNotEmpty == true
        ? dotenv.env['CLOUDINARY_CLOUD_NAME']!
        : 'bassbwni';
  }

  static String get cloudinaryApiKey {
    return dotenv.env['CLOUDINARY_API_KEY']?.trim().isNotEmpty == true
        ? dotenv.env['CLOUDINARY_API_KEY']!
        : '295818597755481';
  }

  static String get cloudinaryApiSecret {
    return dotenv.env['CLOUDINARY_API_SECRET']?.trim().isNotEmpty == true
        ? dotenv.env['CLOUDINARY_API_SECRET']!
        : 'gX_iko7rOLywogPLYzalt-S3GsQ';
  }

  static String get resendApiKey {
    return dotenv.env['RESEND_API_KEY']?.trim().isNotEmpty == true
        ? dotenv.env['RESEND_API_KEY']!
        : 're_iiFeq1qX_Hp8262ZGyu3Fix';
  }
}
