import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../services/language_service.dart';
import '../../../theme/app_colors.dart';

// ═════════════════════════════════════════════════════════
// LEGAL PAGE — biniyogclub.com er Terms / Privacy / About / FAQ
// app er bhitorei dekhay. Lekha website theke ashe, tai website e
// update korlei app eo update hoye jay — app e alada copy nei.
//
// SHUDHU OI EKTA PAGE dekha jay:
//  - Website er upore menu (header) ar niche footer lukano.
//  - Page er bhitore onno kono page er link / button chaple kothao
//    jay na — oi page ei theke jay (choto ekta message dekhay).
//  - Ek page er bhitorer #section link (jemon FAQ category) kaj kore.
//  - Phone / email link phone er nijer app e khule.
// ═════════════════════════════════════════════════════════
class LegalWebPage extends StatefulWidget {
  final String title;
  final String url;

  const LegalWebPage({super.key, required this.title, required this.url});

  @override
  State<LegalWebPage> createState() => _LegalWebPageState();
}

class _LegalWebPageState extends State<LegalWebPage> {
  static const Color emerald = BC.primary;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;

  static const String _allowedHost = 'biniyogclub.com';

  late final WebViewController _controller;
  late final Uri _home;
  int _progress = 0;
  bool _failed = false;
  DateTime? _lastNotice;

  /// Website er header / footer lukai + onno page e jawa atkai.
  /// Page load howar por protibar chalano hoy.
  static const String _lockScript = r'''
(function () {
  // 1. Header (menu) ar footer lukano — shudhu page er lekha thakbe
  if (!document.getElementById('bc-app-style')) {
    var st = document.createElement('style');
    st.id = 'bc-app-style';
    st.textContent =
      'body > div > header, header.fixed, footer { display: none !important; }' +
      'main { padding-top: 12px !important; }';
    (document.head || document.documentElement).appendChild(st);
  }

  if (window.__bcLegalLock) return;
  window.__bcLegalLock = true;

  var home = location.pathname.replace(/\/+$/, '') || '/';
  function samePage(u) {
    try {
      var x = new URL(u, location.href);
      var p = x.pathname.replace(/\/+$/, '') || '/';
      return x.host === location.host && p === home;
    } catch (e) { return false; }
  }
  function notify() {
    try { LegalBridge.postMessage('blocked'); } catch (e) {}
  }

  // 2. Link click — same page (#section soho) chara shob atkai
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    var href = a.getAttribute('href') || '';
    if (href === '' || href.charAt(0) === '#') return;
    if (/^(tel|mailto):/i.test(href)) return; // app nije phone/email app e khulbe
    if (samePage(a.href)) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    notify();
  }, true);

  // 3. Form submit (newsletter, search ityadi)
  document.addEventListener('submit', function (e) {
    e.preventDefault();
    e.stopImmediatePropagation();
    notify();
  }, true);

  // 4. Next.js router.push / replace
  var ps = history.pushState, rs = history.replaceState;
  history.pushState = function (s, t, u) {
    if (u != null && !samePage(u)) { notify(); return; }
    return ps.apply(this, arguments);
  };
  history.replaceState = function (s, t, u) {
    if (u != null && !samePage(u)) { notify(); return; }
    return rs.apply(this, arguments);
  };

  // 5. Notun tab / window
  window.open = function () { notify(); return null; };
})();
''';

  @override
  void initState() {
    super.initState();
    _home = Uri.parse(widget.url);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ivory)
      ..addJavaScriptChannel('LegalBridge', onMessageReceived: (_) => _showOnlyThisPage())
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _failed = false);
          },
          onPageFinished: (_) => _controller.runJavaScript(_lockScript).catchError((_) {}),
          onWebResourceError: (error) {
            // Shudhu main page load fail holei error dekhai
            if (error.isForMainFrame == true && mounted) {
              setState(() => _failed = true);
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            // Phone / email — phone er nijer app e
            if (uri.scheme == 'tel' || uri.scheme == 'mailto') {
              launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            // Page er bhitorer iframe / resource — chalte dei
            if (!request.isMainFrame) return NavigationDecision.navigate;
            if (request.url == 'about:blank') return NavigationDecision.navigate;

            if (_isHomePage(uri)) return NavigationDecision.navigate;

            // Onno kono page / onno website — jabe na, ei page ei thakbe
            _showOnlyThisPage();
            return NavigationDecision.prevent;
          },
          // Next.js nijer moto URL bodlale (page reload chara) — abar ei page e
          onUrlChange: (change) {
            final url = change.url;
            if (url == null) return;
            final uri = Uri.tryParse(url);
            if (uri == null || _isHomePage(uri) || url == 'about:blank') return;
            _showOnlyThisPage();
            _controller.loadRequest(_home);
          },
        ),
      )
      ..loadRequest(_home);
  }

  String _cleanPath(String p) {
    final s = p.replaceAll(RegExp(r'/+$'), '');
    return s.isEmpty ? '/' : s;
  }

  /// Ek-i site (www soho ba chara) ar ek-i path — #section / ?query thakleo thik
  bool _isHomePage(Uri uri) {
    if (uri.scheme != 'https' && uri.scheme != 'http') return false;
    final host = uri.host.toLowerCase();
    final ourSite = host == _allowedHost || host.endsWith('.$_allowedHost');
    return ourSite && _cleanPath(uri.path) == _cleanPath(_home.path);
  }

  void _showOnlyThisPage() {
    if (!mounted) return;
    final now = DateTime.now();
    // Ek click e duibar message na dekhai
    if (_lastNotice != null && now.difference(_lastNotice!).inMilliseconds < 1500) return;
    _lastNotice = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(LanguageService.tr(
              'Only this page can be viewed here.', 'এখানে শুধু এই পেজটিই দেখা যাবে।')),
          backgroundColor: emerald,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _retry() {
    setState(() {
      _failed = false;
      _progress = 0;
    });
    _controller.loadRequest(_home);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 54,
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 16.5),
            ),
            actions: [
              IconButton(
                tooltip: LanguageService.tr('Reload', 'রিলোড'),
                icon: const Icon(Icons.refresh_rounded, color: ink, size: 20),
                onPressed: _retry,
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(2),
              child: _progress < 100 && !_failed
                  ? LinearProgressIndicator(
                value: _progress == 0 ? null : _progress / 100,
                minHeight: 2,
                color: emerald,
                backgroundColor: Colors.transparent,
              )
                  : const SizedBox(height: 2),
            ),
          ),
          body: _failed ? _buildError() : WebViewWidget(controller: _controller),
        );
      },
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 34, color: emerald),
            const SizedBox(height: 10),
            Text(
              LanguageService.tr('Could not load this page', 'পেজটি লোড করা যায়নি'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
            ),
            const SizedBox(height: 3),
            Text(
              LanguageService.tr('Please check your internet connection and try again.',
                  'ইন্টারনেট সংযোগ চেক করে আবার চেষ্টা করুন।'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: muted),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _retry,
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
    );
  }
}