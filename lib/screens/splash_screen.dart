import 'dart:async';
import 'package:flutter/material.dart';
import '../page/authentication/login_page.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  void _checkAuthAndNavigate() async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      bool isLoggedIn = false;
      try {
        isLoggedIn = await AuthService.isLoggedIn();
      } catch (e) {
        debugPrint('Auth check error: $e');
        isLoggedIn = false;
      }

      if (!mounted) return;

      if (isLoggedIn) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    } catch (e) {
      debugPrint('SplashScreen navigation error: $e');
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo_icon.png',
              height: 100,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.account_balance_wallet_rounded,
                size: 80,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 16),
            Image.asset(
              'assets/images/logo_full.png',
              height: 40,
              errorBuilder: (context, error, stackTrace) => const Text(
                'Biniyog Club',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
            ),
          ],
        ),
      ),
    );
  }
}
