import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/splash_screen.dart';
import 'services/app_lock_service.dart';
import 'services/language_service.dart';
import 'services/push_service.dart'; // PushService import করা হলো

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Failed to load .env file: $e");
  }
  await LanguageService.init();

  // Firebase এবং Push Service ইনিশিয়ালাইজেশন[cite: 1]
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  await PushService.init();

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
          navigatorKey: PushService.navigatorKey, // Push navigation এর জন্য যুক্ত করা হলো[cite: 1]
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