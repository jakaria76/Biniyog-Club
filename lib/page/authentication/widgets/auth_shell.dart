import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';

/// Login / Registration er common design:
/// upore dashboard er moto sobuj header (kono pattern / sonali nei), niche shada card e form.
class AuthShell extends StatelessWidget {
  // ─── Palette — website er rong (lib/theme/app_colors.dart), dashboard er moto ───
  static const Color emerald = BC.primary;
  static const Color emeraldBright = BC.brand500;
  static const Color emeraldDeep = BC.brand800;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color danger = BC.destructive;
  static const Color dangerSoft = BC.destructiveMuted;

  final String eyebrow;
  final String title;
  final String subtitle;
  final List<(IconData, String)> highlights;
  final Widget child;
  final Widget? footer;

  const AuthShell({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.child,
    this.highlights = const [],
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final topPad = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Dark header er upor status bar er icon shada
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: ivory,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              children: [
                // ─── Header ───
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [emeraldBright, emerald],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(22, topPad + (canPop ? 4 : 28), 22, 64),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (canPop)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Material(
                                    color: Colors.white.withAlpha(22),
                                    shape: const CircleBorder(),
                                    child: IconButton(
                                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                                      onPressed: () => Navigator.of(context).maybePop(),
                                    ),
                                  ),
                                ),
                              Row(
                                children: [
                                  Transform.rotate(
                                    angle: math.pi / 4,
                                    child: Container(width: 8, height: 8, color: Colors.white),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    eyebrow.toUpperCase(),
                                    style: TextStyle(
                                      color: Colors.white.withAlpha(215),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.6,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                subtitle,
                                style: TextStyle(color: Colors.white.withAlpha(195), fontSize: 15, height: 1.45),
                              ),
                              if (highlights.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final h in highlights)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withAlpha(20),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.white.withAlpha(60)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(h.$1, size: 15, color: Colors.white),
                                            const SizedBox(width: 6),
                                            Text(
                                              h.$2,
                                              style: const TextStyle(
                                                  color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ─── Form card (header er upor uthe ase) ───
                Transform.translate(
                  offset: const Offset(0, -40),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
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
                      child: child,
                    ),
                  ),
                ),
                if (footer != null)
                  Transform.translate(
                    offset: const Offset(0, -24),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 8),
                      child: footer,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Shared form pieces ───────────────────────────────────
  static Widget label(String text, {bool isRequired = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7, left: 2),
      child: Text.rich(
        TextSpan(
          text: text,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ink, letterSpacing: 0.9),
          children: [
            if (isRequired) const TextSpan(text: ' *', style: TextStyle(color: danger)),
          ],
        ),
      ),
    );
  }

  static InputDecoration dec(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint.isEmpty ? null : hint,
      hintStyle: TextStyle(fontSize: 15, color: muted.withAlpha(150)),
      prefixIcon: Icon(icon, color: muted, size: 20),
      filled: true,
      fillColor: ivory,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
      enabledBorder:
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: emerald, width: 1.5)),
      errorBorder:
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: danger)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: danger, width: 1.5)),
    );
  }

  static Widget errorBox(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: dangerSoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 17, color: danger),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, color: danger, height: 1.4))),
        ],
      ),
    );
  }

  static Widget primaryButton({
    required String text,
    required bool loading,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: emerald,
          foregroundColor: Colors.white,
          disabledBackgroundColor: emerald.withAlpha(140),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: loading
            ? const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
        )
            : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded, size: 19),
          ],
        ),
      ),
    );
  }

  /// "Already have an account? Sign in" dhoroner nicher link
  static Widget switchLink({
    required String question,
    required String action,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(question, style: const TextStyle(color: muted, fontSize: 14.5)),
          ),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                action,
                style: const TextStyle(color: emerald, fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}