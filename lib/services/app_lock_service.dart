import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'language_service.dart';

// ═════════════════════════════════════════════════════════
// APP LOCK — fingerprint / face / phone er PIN diye app lock.
// Settings theke chalu korle, app khulle ba 30 second er beshi
// background e thakle abar unlock korte hobe.
// ═════════════════════════════════════════════════════════
class AppLockService {
  static const String _prefKey = 'app_lock_enabled';
  static final LocalAuthentication _auth = LocalAuthentication();

  static bool _authInProgress = false;
  static bool get authInProgress => _authInProgress;

  /// Phone e fingerprint / face / screen lock ache kina
  static Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }

  /// Fingerprint / face, na thakle phone er PIN / pattern
  static Future<bool> authenticate(String reason) async {
    _authInProgress = true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      debugPrint('App lock auth error: $e');
      return false;
    } finally {
      _authInProgress = false;
    }
  }
}

/// main.dart er MaterialApp e:
///   builder: (context, child) => AppLockGate(child: child!),
class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  // Gallery theke chobi nite gele protibar lock na hoy, tai 30 second chhar
  static const Duration _grace = Duration(seconds: 30);

  bool _locked = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockOnStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<bool> _shouldLock() async {
    if (!await AppLockService.isEnabled()) return false;
    final user = await AuthService.getUserData();
    return (user?['id']?.toString() ?? '').isNotEmpty;
  }

  Future<void> _lockOnStart() async {
    if (await _shouldLock() && mounted) {
      setState(() => _locked = true);
      _unlock();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    // Fingerprint dialog nijei app ke pause kore — tokhon kichu korbo na
    if (AppLockService.authInProgress) return;

    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _pausedAt != null) {
      final away = DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      if (away >= _grace && !_locked && await _shouldLock() && mounted) {
        setState(() => _locked = true);
        _unlock();
      }
    }
  }

  Future<void> _unlock() async {
    final ok = await AppLockService.authenticate(
      LanguageService.tr('Unlock Biniyog Club', 'বিনিয়োগ ক্লাব আনলক করুন'),
    );
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked) Positioned.fill(child: _LockScreen(onUnlock: _unlock)),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  final VoidCallback onUnlock;

  const _LockScreen({required this.onUnlock});

  static const Color emeraldDeep = Color(0xFF0A3327);
  static const Color gold = Color(0xFFB8935A);
  static const Color goldLight = Color(0xFFD9BE8C);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: emeraldDeep,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: gold, width: 1.4),
                    color: Colors.white.withAlpha(12),
                  ),
                  child: const Icon(Icons.lock_outline_rounded, color: goldLight, size: 32),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Biniyog Club',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  LanguageService.tr(
                      'Your app is locked', 'আপনার অ্যাপ লক করা আছে'),
                  style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 13),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: onUnlock,
                  icon: const Icon(Icons.fingerprint_rounded, size: 20),
                  label: Text(LanguageService.tr('Unlock', 'আনলক করুন')),
                  style: FilledButton.styleFrom(
                    backgroundColor: goldLight,
                    foregroundColor: emeraldDeep,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}