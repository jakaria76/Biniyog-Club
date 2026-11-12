import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../page/public/landing_page.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';

/// App khulle prothome — login thakle Dashboard, na thakle Landing page.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  // ─── Palette — website er rong (lib/theme/app_colors.dart) ───
  static const Color emerald = BC.primary;
  static const Color emeraldBright = BC.brand500; // dashboard er moto

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _go(Widget page) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  Future<void> _checkAuthAndNavigate() async {
    // Login check ar logo dekhano ek shathe — protibar puro 2 second boshe thakte hoy na
    final results = await Future.wait<dynamic>([
      Future.delayed(const Duration(milliseconds: 1200)),
      AuthService.isLoggedIn().catchError((Object e) {
        debugPrint('Auth check error: $e');
        return false;
      }),
    ]);
    if (!mounted) return;

    final isLoggedIn = results[1] == true;
    // Logged in → Dashboard, na hole → Landing page
    _go(isLoggedIn ? const HomeScreen() : const LandingPage());
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: emerald,
        body: Container(
          // Dashboard er card er moto sobuj — kono pattern / sonali nei
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [emeraldBright, emerald],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: FadeTransition(
                  opacity: fade,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1).animate(fade),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Logo shada card e — sobuj background e o porishkar dekha jay
                          Container(
                            width: 116,
                            height: 116,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withAlpha(45), blurRadius: 24, offset: const Offset(0, 10)),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/logo_icon.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.account_balance_rounded, size: 56, color: emerald),
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'Biniyog Club',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 22, height: 1, color: Colors.white.withAlpha(120)),
                              const SizedBox(width: 8),
                              Transform.rotate(
                                angle: math.pi / 4,
                                child: Container(width: 6, height: 6, color: Colors.white),
                              ),
                              const SizedBox(width: 8),
                              Container(width: 22, height: 1, color: Colors.white.withAlpha(120)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Invest in verified Bangladeshi businesses',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.white.withAlpha(200)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).padding.bottom + 40,
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}