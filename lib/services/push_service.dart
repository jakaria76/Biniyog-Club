import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'database_service.dart';

/// App bondho / background e push ashle — Android nijei notification dekhay.
/// Ekhane shudhu Firebase chalu rakhi. (main.dart e register korte hobe)
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// ═══════════════════════════════════════════════════════════════════
/// Push notification (Firebase Cloud Messaging) — ekhon shudhu Android.
///
/// Kon ghotonay phone e notification ashe (mail er sathe mil rekhe):
///   Welcome            → app (notun account er prothom login e)
///   Investment Pending → app (Confirm chaplei)
///   Payment Submitted  → app (payment abar jomা dile)
///   Approved / Cancelled / Payment rejected → biniyog-mailer worker (FCM)
///
/// Dekhte: Biniyog Club logo (boro icon), emerald rong, app er nam upore,
/// lomba lekha puro dekhay.
/// ═══════════════════════════════════════════════════════════════════
class PushService {
  /// MaterialApp(navigatorKey: PushService.navigatorKey) — tap korle page kholar jonno
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Tap korle kon page — dashboard eta set kore (tai ekhane page import lage na)
  static Widget? Function(Map<String, dynamic> data)? pageFor;

  // ─── Look ───
  static const Color brandColor = Color(0xFF0E4A37); // emerald
  static const String _smallIcon = 'ic_notification'; // drawable — shada silhouette
  static const String _largeIcon = 'notification_logo'; // drawable — rongin logo

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'biniyog_default', // AndroidManifest r worker e ek-i id
    'Investment updates',
    description: 'Welcome, pending, approval, cancellation and payment updates from Biniyog Club',
    importance: Importance.high,
  );

  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _tableReady = false;
  static String? _currentUserId;
  static Map<String, dynamic>? _pendingOpen;
  static StreamSubscription<String>? _refreshSub;

  // ═════════════════════════════════════════════════════════
  // INIT — main.dart e Firebase.initializeApp() er por ekbar
  // ═════════════════════════════════════════════════════════
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (r) => _openFromPayload(r.payload),
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      // App khola thakle FCM nije dekhay na — amra dekhai, eki design e
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        _show(n.title ?? 'Biniyog Club', n.body ?? '', Map<String, dynamic>.from(m.data));
      });

      // Background e chilo, notification e tap
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data));

      // App puro bondho chilo, notification e tap kore khula —
      // login / dashboard ready hole tobe page khulbo
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _pendingOpen = Map<String, dynamic>.from(initial.data);
    } catch (e) {
      debugPrint('Push init error: $e');
    }
  }

  // ═════════════════════════════════════════════════════════
  // APP THEKE NOTIFICATION (pending, payment submitted, welcome)
  // ═════════════════════════════════════════════════════════
  static Future<void> showLocal({
    required String title,
    required String body,
    String kind = '',
    bool group = false,
  }) async {
    await init();
    await _show(title, body, {'kind': kind, 'group': group ? 'true' : 'false'});
  }

  static Future<void> _show(String title, String body, Map<String, dynamic> data) async {
    final id = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    final payload = jsonEncode(data);

    AndroidNotificationDetails details({required bool branded}) => AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.high,
      priority: Priority.high,
      icon: branded ? _smallIcon : '@mipmap/ic_launcher',
      largeIcon: branded ? const DrawableResourceAndroidBitmap(_largeIcon) : null,
      color: brandColor,
      colorized: false,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: '<b>$title</b>',
        htmlFormatContentTitle: true,
        summaryText: 'Biniyog Club',
      ),
      ticker: title,
    );

    try {
      await _local.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: details(branded: true)),
        payload: payload,
      );
    } catch (e) {
      // Logo / icon file na thakle — sadharon icon diye hoilew dekhai
      debugPrint('Branded notification failed ($e) — plain icon diye dekhacchi');
      try {
        await _local.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: NotificationDetails(android: details(branded: false)),
          payload: payload,
        );
      } catch (e2) {
        debugPrint('Notification show error: $e2');
      }
    }
  }

  // ═════════════════════════════════════════════════════════
  // LOGIN er por (dashboard theke dake)
  // ═════════════════════════════════════════════════════════
  static Future<void> registerForUser(String userId) async {
    if (userId.isEmpty) return;
    await init();
    _currentUserId = userId;

    try {
      // Android 13+ e "Allow notifications" dialog
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.denied) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) await _saveToken(userId, token);

        _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((t) {
          final u = _currentUserId;
          if (u != null && u.isNotEmpty) _saveToken(u, t);
        });

        await _maybeWelcome(userId);
      }
    } catch (e) {
      debugPrint('Push register error: $e');
    }

    // Bondho app notification tap kore khulechilo — ekhon page khuli
    final pending = _pendingOpen;
    if (pending != null) {
      _pendingOpen = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(pending));
    }
  }

  /// Notun account (3 diner moddhe khola) — prothom bar ekটা Welcome notification.
  /// email_log e 'PUSH_WELCOME' rakhi, tai kokhono duibar ashe na.
  static Future<void> _maybeWelcome(String userId) async {
    try {
      final rows = await DatabaseService.queryNeonHttp('''
        INSERT INTO email_log (kind, ref_id, status)
        SELECT 'PUSH_WELCOME', u."id", 'sent'
        FROM users u
        WHERE u."id" = \$1
          AND u."role"::text = 'INVESTOR'
          AND u."createdAt" > NOW() - INTERVAL '3 days'
        ON CONFLICT (kind, ref_id) DO NOTHING
        RETURNING (SELECT "name" FROM users WHERE "id" = \$1) AS name
      ''', [userId]);
      if (rows.isEmpty) return;
      final name = (rows.first['name']?.toString() ?? '').trim();
      await _show(
        '🎉 Welcome to Biniyog Club',
        'Assalamu Alaikum${name.isEmpty ? '' : ', $name'}! Your account is ready. '
            'Explore halal projects and business groups and start investing today.',
        {'kind': 'WELCOME', 'group': 'false'},
      );
    } catch (e) {
      debugPrint('Welcome push error: $e');
    }
  }

  // ═════════════════════════════════════════════════════════
  // LOGOUT / account delete er age
  // ═════════════════════════════════════════════════════════
  static Future<void> unregister() async {
    _currentUserId = null;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await DatabaseService.executeNeonHttp('DELETE FROM device_tokens WHERE token = \$1', [token]);
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('Push unregister error: $e');
    }
  }

  // ═════════════════════════════════════════════════════════
  // DB — device_tokens (website er Prisma schema te nei, app nijei banay)
  // ═════════════════════════════════════════════════════════
  static Future<bool> _ensureTable() async {
    if (_tableReady) return true;
    final a = await DatabaseService.executeNeonHttp('''
      CREATE TABLE IF NOT EXISTS device_tokens (
        token      TEXT PRIMARY KEY,
        user_id    TEXT NOT NULL,
        platform   TEXT NOT NULL DEFAULT 'android',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');
    final b = await DatabaseService.executeNeonHttp(
        'CREATE INDEX IF NOT EXISTS device_tokens_user_idx ON device_tokens (user_id)');
    _tableReady = a && b;
    return _tableReady;
  }

  /// Ek phone e onno user login korle token notun user er naame chole jay
  static Future<void> _saveToken(String userId, String token) async {
    if (!await _ensureTable()) return;
    await DatabaseService.executeNeonHttp('''
      INSERT INTO device_tokens (token, user_id, platform, updated_at)
      VALUES (\$1, \$2, 'android', NOW())
      ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, updated_at = NOW()
    ''', [token, userId]);
  }

  // ═════════════════════════════════════════════════════════
  // TAP → page
  // ═════════════════════════════════════════════════════════
  static void _openFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final d = jsonDecode(payload);
      if (d is Map) _open(Map<String, dynamic>.from(d));
    } catch (_) {}
  }

  static void _open(Map<String, dynamic> data) {
    final nav = navigatorKey.currentState;
    final builder = pageFor;
    if (nav == null || _currentUserId == null || builder == null) {
      // Ekhono login / dashboard hoyni — pore khulbo
      _pendingOpen = data;
      return;
    }
    final page = builder(data);
    if (page != null) nav.push(MaterialPageRoute(builder: (_) => page));
  }
}