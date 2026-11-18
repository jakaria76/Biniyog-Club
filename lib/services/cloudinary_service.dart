import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/db_config.dart';

class CloudinaryService {
  /// Payment proof er folder — app er shob payment page eta pathay
  static const String paymentProofFolder = 'payment_proofs';

  // Upload Image Bytes directly to Cloudinary API and return HTTPS Secure URL string
  static Future<String?> uploadImage(Uint8List imageBytes, {String folder = 'avatars'}) async {
    // Payment proof (transfer screenshot, cheque, money receipt) website er motoi
    // PRIVATE ("authenticated") hishebe — link pele-o keu dekhte parbe na;
    // admin website er /api/payment-proofs diye dekhe
    if (folder == paymentProofFolder) {
      final private = await uploadPaymentProof(imageBytes);
      if (private != null) return private;
      // API key / secret na thakle purono (public) upload — website duitai pore
      if (DbConfig.cloudinaryApiKey.trim().isNotEmpty && DbConfig.cloudinaryApiSecret.trim().isNotEmpty) {
        return null;
      }
    }
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

  /// Website er uploadPaymentProof er hubohu: public_id "payments/proofs/…",
  /// type "authenticated" (private). Fire deya link theke signature (s--…--)
  /// muche fela hoy — eta shudhu chinho, kaj kora link na. null = upload hoyni.
  static Future<String?> uploadPaymentProof(Uint8List bytes) async {
    try {
      final cloudName = DbConfig.cloudinaryCloudName.trim();
      final apiKey = DbConfig.cloudinaryApiKey.trim();
      final apiSecret = DbConfig.cloudinaryApiSecret.trim();
      if (cloudName.isEmpty || apiKey.isEmpty || apiSecret.isEmpty) return null;

      final ms = DateTime.now().millisecondsSinceEpoch;
      final rnd = Random.secure().nextInt(1 << 30).toRadixString(36);
      final publicId = 'payments/proofs/${ms}_app_$rnd';
      final timestamp = (ms ~/ 1000).toString();
      // Cloudinary signature: parameter gulo a–z kromanushare
      final toSign = 'overwrite=true&public_id=$publicId&timestamp=$timestamp&type=authenticated$apiSecret';
      final signature = sha1.convert(utf8.encode(toSign)).toString();

      final request = http.MultipartRequest('POST', Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'))
        ..fields['api_key'] = apiKey
        ..fields['timestamp'] = timestamp
        ..fields['public_id'] = publicId
        ..fields['type'] = 'authenticated'
        ..fields['overwrite'] = 'true'
        ..fields['signature'] = signature
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'proof_$ms.jpg'));

      final response = await request.send().timeout(const Duration(seconds: 60));
      final body = await response.stream.bytesToString();
      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint('Private proof upload failed (${response.statusCode}): $body');
        return null;
      }
      final url = (jsonDecode(body) as Map<String, dynamic>)['secure_url']?.toString();
      if (url == null || url.isEmpty) return null;
      return url.replaceFirst(RegExp(r'/s--[^/]+--/'), '/');
    } catch (e) {
      debugPrint('Private proof upload exception: $e');
      return null;
    }
  }
}