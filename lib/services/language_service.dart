import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageService {
  static const String _langKey = 'app_language';

  // ValueNotifier allowing instant UI updates across all screens on language change
  static final ValueNotifier<String> currentLanguage =
      ValueNotifier<String>('en');

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLang = prefs.getString(_langKey) ?? 'en';
      currentLanguage.value = savedLang;
    } catch (e) {
      debugPrint('Error initializing LanguageService: $e');
    }
  }

  static Future<void> setLanguage(String langCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_langKey, langCode);
      currentLanguage.value = langCode;
    } catch (e) {
      debugPrint('Error setting language: $e');
    }
  }

  static bool get isBangla => currentLanguage.value == 'bn';

  static String tr(String enText, String bnText) {
    return isBangla ? bnText : enText;
  }
}
