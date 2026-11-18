import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import '../../../theme/app_colors.dart';

/// Website er ekta page app er bhetore — apnar login shoho (bc_session cookie).
///
/// Share kena (website er SharePurchaseForm) ekhane hoy: share er inventory
/// lock, coupon, order number ar audit shudhu website er server e nirapode
/// chole — app sorasori DB te likhle ek-i share dui jon kine felte pare.
class WebsiteWebPage extends StatefulWidget {
  final String title;

  /// Website er path, jemon "/projects/abc#invest"
  final String path;

  const WebsiteWebPage({super.key, required this.title, required this.path});

  @override
  State<WebsiteWebPage> createState() => _WebsiteWebPageState();
}

class _WebsiteWebPageState extends State<WebsiteWebPage> {
  static const Color emerald = BC.primary;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;

  WebViewController? _controller;
  int _progress = 0;
  bool _failed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _failed = false;
      _error = null;
      _progress = 0;
    });
    final user = await AuthService.getUserData();
    final uid = user?['id']?.toString() ?? '';
    // Login thakle website eo login (app er nijer session row)
    final token = uid.isEmpty ? null : await DatabaseService.websiteSessionToken(uid);
    if (!mounted) return;
    if (uid.isNotEmpty && token == null) {
      setState(() {
        _failed = true;
        _error = LanguageService.tr('Could not connect to the website. Check your internet and try again.',
            'ওয়েবসাইটে সংযোগ করা যায়নি। ইন্টারনেট চেক করে আবার চেষ্টা করুন।');
      });
      return;
    }

    final host = DatabaseService.websiteHost;
    if (token != null) {
      final cookies = WebViewCookieManager();
      for (final domain in {host, host.startsWith('www.') ? host.substring(4) : 'www.$host'}) {
        await cookies.setCookie(WebViewCookie(name: 'bc_session', value: token, domain: domain, path: '/'));
      }
    }

    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ivory)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onWebResourceError: (e) {
          // Shudhu mul page na khulle (chobi / font er bhul bad)
          if (e.isForMainFrame == true && mounted) {
            setState(() {
              _failed = true;
              _error = LanguageService.tr('The page could not be opened. Check your internet and try again.',
                  'পেজ খোলা যায়নি। ইন্টারনেট চেক করে আবার চেষ্টা করুন।');
            });
          }
        },
      ))
      ..loadRequest(Uri.parse('https://$host${widget.path.startsWith('/') ? '' : '/'}${widget.path}'));
    setState(() => _controller = c);
  }

  Future<void> _back() async {
    final c = _controller;
    if (c != null && await c.canGoBack()) {
      await c.goBack();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: ivory,
        appBar: AppBar(
          backgroundColor: ivory,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 54,
          iconTheme: const IconThemeData(color: ink),
          leading: IconButton(icon: const BackButtonIcon(), color: ink, onPressed: _back),
          title: Text(widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 16)),
          actions: [
            IconButton(
              tooltip: LanguageService.tr('Reload', 'আবার লোড'),
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _controller == null || _failed ? _open() : _controller!.reload(),
            ),
            IconButton(
              tooltip: LanguageService.tr('Close', 'বন্ধ'),
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: _progress > 0 && _progress < 100 && !_failed
                ? LinearProgressIndicator(
              value: _progress / 100,
              minHeight: 2,
              color: emerald,
              backgroundColor: emerald.withAlpha(30),
            )
                : const SizedBox(height: 2),
          ),
        ),
        body: _failed
            ? Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, size: 34, color: emerald),
                const SizedBox(height: 10),
                Text(_error ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: muted, height: 1.4)),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _open,
                  style: FilledButton.styleFrom(
                    backgroundColor: emerald,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(LanguageService.tr('Try again', 'আবার চেষ্টা করুন')),
                ),
              ],
            ),
          ),
        )
            : _controller == null
            ? const Center(
          child: SizedBox(
              width: 26, height: 26, child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4)),
        )
            : WebViewWidget(controller: _controller!),
      ),
    );
  }
}