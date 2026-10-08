import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/db_config.dart';

class CloudinaryService {
  // Upload Image Bytes directly to Cloudinary API and return HTTPS Secure URL string
  static Future<String?> uploadImage(Uint8List imageBytes, {String folder = 'avatars'}) async {
    try {
      final cloudName = DbConfig.cloudinaryCloudName.trim();
      final apiKey = DbConfig.cloudinaryApiKey.trim();
      final apiSecret = DbConfig.cloudinaryApiSecret.trim();

      if (cloudName.isEmpty || cloudName == 'your_cloud_name') {
        debugPrint('Cloudinary Error: CLOUDINARY_CLOUD_NAME is not configured in .env');
        return null;
      }

      final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

      // 1. Try Signed Upload with API Key & Secret if available
      if (apiKey.isNotEmpty && apiSecret.isNotEmpty) {
        final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
        final stringToSign = 'folder=$folder&timestamp=$timestamp$apiSecret';
        final signature = sha1.convert(utf8.encode(stringToSign)).toString();

        final request = http.MultipartRequest('POST', uri);
        request.fields['api_key'] = apiKey;
        request.fields['timestamp'] = timestamp;
        request.fields['folder'] = folder;
        request.fields['signature'] = signature;

        final multipartFile = http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'avatar_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        request.files.add(multipartFile);

        final response = await request.send();
        final responseBody = await response.stream.bytesToString();

        if (response.statusCode == 200 || response.statusCode == 201) {
          final json = jsonDecode(responseBody) as Map<String, dynamic>;
          final secureUrl = json['secure_url']?.toString();
          debugPrint('Signed Cloudinary Upload Success: $secureUrl');
          return secureUrl;
        } else {
          debugPrint('Signed Cloudinary Upload Failed (${response.statusCode}): $responseBody');
        }
      }

      // 2. Fallback to Unsigned Upload preset ml_default
      final request = http.MultipartRequest('POST', uri);
      request.fields['upload_preset'] = 'ml_default';
      request.fields['folder'] = folder;

      final multipartFile = http.MultipartFile.fromBytes(
        'file',
        imageBytes,
        filename: 'avatar_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      request.files.add(multipartFile);

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(responseBody) as Map<String, dynamic>;
        final secureUrl = json['secure_url']?.toString();
        debugPrint('Unsigned Cloudinary Upload Success: $secureUrl');
        return secureUrl;
      } else {
        debugPrint('Unsigned Cloudinary Upload Failed (${response.statusCode}): $responseBody');
        return null;
      }
    } catch (e) {
      debugPrint('Cloudinary Upload Exception: $e');
      return null;
    }
  }
}
