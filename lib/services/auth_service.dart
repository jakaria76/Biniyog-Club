import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';

  // Save authentication token
  static Future<void> saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    } catch (e) {
      debugPrint('Error saving token: $e');
    }
  }

  // Get saved authentication token
  static Future<String?> getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    } catch (e) {
      debugPrint('Error getting token: $e');
      return null;
    }
  }

  // Save user data
  static Future<void> saveUserData(Map<String, dynamic> userData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(userData));
    } catch (e) {
      debugPrint('Error saving user data: $e');
    }
  }

  // Get user data
  static Future<Map<String, dynamic>?> getUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_userKey);
      if (data != null) {
        return jsonDecode(data) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error getting user data: $e');
    }
    return null;
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    try {
      final token = await getToken();
      return token != null && token.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking isLoggedIn: $e');
      return false;
    }
  }

  // Logout
  static Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
    } catch (e) {
      debugPrint('Error during logout: $e');
    }
  }

  // Login via Neon Postgres Database directly
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final result = await DatabaseService.loginUser(
      email: email,
      password: password,
    );

    if (result['success'] == true && result['data'] != null) {
      final userData = result['data'] as Map<String, dynamic>;
      final mockToken = "token_${userData['id']}_${DateTime.now().millisecondsSinceEpoch}";
      await saveToken(mockToken);
      await saveUserData(userData);
    }

    return result;
  }

  // Register via Neon Postgres Database directly
  static Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final result = await DatabaseService.registerUser(
      name: fullName,
      email: email,
      phone: phone,
      password: password,
    );

    if (result['success'] == true && result['data'] != null) {
      final userData = result['data'] as Map<String, dynamic>;
      final mockToken = "token_${userData['id']}_${DateTime.now().millisecondsSinceEpoch}";
      await saveToken(mockToken);
      await saveUserData(userData);
    }

    return result;
  }

  // Forgot Password (Send OTP via Resend.com Email API & Neon Postgres)
  static Future<Map<String, dynamic>> forgotPassword({
    required String email,
  }) async {
    return DatabaseService.sendForgotPasswordOtp(email);
  }

  // Verify Reset OTP
  static Future<Map<String, dynamic>> verifyOtp({
    required String email,
    required String otp,
  }) async {
    return DatabaseService.verifyResetOtp(email, otp);
  }

  // Reset Password using OTP
  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    return DatabaseService.resetPasswordWithOtp(
      email: email,
      otp: otp,
      newPassword: newPassword,
    );
  }
}
