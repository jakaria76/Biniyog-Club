import 'package:flutter/material.dart';

class AuthCard extends StatelessWidget {
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
          boxShadow: [
            BoxShadow(
              color: Colors.teal.shade900.withAlpha(20),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Accent Bar
              Container(
                height: 5,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.teal, Colors.tealAccent],
                  ),
                ),
              ),

              // Quote Banner (if provided)
              if (quoteBanner != null) ...[quoteBanner!],

              Padding(
                padding: const EdgeInsets.all(28.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // App Brand / Logo Header
                    Center(
                      child: Image.asset(
                        'assets/images/logo_full.png',
                        height: 42,
                        errorBuilder: (context, error, stackTrace) => const Text(
                          'Biniyog Club',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Title
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Description
                    Text(
                      description,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Page Specific Form
                    child,

                    // Footer (if provided)
                    if (footer != null) ...[
                      const SizedBox(height: 24),
                      const Divider(height: 1, color: Color(0xFFEEEEEE)),
                      const SizedBox(height: 20),
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
