import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Forgot / OTP / Reset password page er card — app er emerald + gold design e.
class AuthCard extends StatelessWidget {
  static const Color emerald = Color(0xFF0E4A37);
  static const Color emeraldDeep = Color(0xFF0A3327);
  static const Color gold = Color(0xFFB8935A);
  static const Color goldLight = Color(0xFFD9BE8C);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);

  final String title;
  final String description;
  final Widget child;
  final Widget? quoteBanner;
  final Widget? footer;

  const AuthCard({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.quoteBanner,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: line),
          boxShadow: [
            BoxShadow(
              color: emeraldDeep.withAlpha(22),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Upore emerald → gold dag
              Container(
                height: 5,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [emerald, gold, emerald]),
                ),
              ),

              if (quoteBanner != null) quoteBanner!,

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/images/logo_full.png',
                        height: 42,
                        errorBuilder: (context, error, stackTrace) => const Text(
                          'Biniyog Club',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: emerald,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Choto Islamic diamond divider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(width: 28, height: 1, color: goldLight),
                        const SizedBox(width: 8),
                        Transform.rotate(
                          angle: math.pi / 4,
                          child: Container(width: 7, height: 7, color: gold),
                        ),
                        const SizedBox(width: 8),
                        Container(width: 28, height: 1, color: goldLight),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: ink),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13.5, color: muted, height: 1.45),
                    ),
                    const SizedBox(height: 26),
                    child,
                    if (footer != null) ...[
                      const SizedBox(height: 22),
                      const Divider(height: 1, color: line),
                      const SizedBox(height: 18),
                      Center(child: footer!),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}