import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/splash_screen.dart';
import 'services/app_lock_service.dart';
import 'services/language_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Failed to load .env file: $e");
  }
  await LanguageService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Dashboard er Islamic palette
  static const Color emerald = Color(0xFF0E4A37);
  static const Color ivory = Color(0xFFF7F4EE);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, currentLang, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Biniyog Club',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: emerald),
            scaffoldBackgroundColor: ivory,
            useMaterial3: true,
          ),
          // App lock: shob page er upor lock screen boshe,
          // tai jekono page theke-i app lock kaj korbe
          builder: (context, child) => AppLockGate(
            child: child ?? const SizedBox.shrink(),
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}