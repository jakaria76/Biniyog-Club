import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../page/authentication/login_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isRedirecting = false;

  static const String _websiteUrl = 'https://www.biniyogclub.com/';
  static const Set<String> _allowedHosts = {
    'www.biniyogclub.com',
    'biniyogclub.com',
  };

  // Website er bhitore inject kora JS: shob navigation dhore app ke janay
  static const String _guardScript = r'''
(function () {
  if (window.__bcGuard) return;
  window.__bcGuard = true;

  function isHome(u) {
    try {
      var x = new URL(u, location.href);
      return (x.hostname === 'www.biniyogclub.com' || x.hostname === 'biniyogclub.com')
        && (x.pathname === '' || x.pathname === '/');
    } catch (e) { return false; }
  }
  function block() {
    try { AppBridge.postMessage('login'); } catch (e) {}
  }

  // 1. Link click (Next.js <Link> soho)
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    var href = a.getAttribute('href') || '';
    if (href === '' || href.charAt(0) === '#') return; // same-page anchor allow
    if (isHome(a.href)) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    block();
  }, true);

  // 2. Form submit
  document.addEventListener('submit', function (e) {
    e.preventDefault();
    e.stopImmediatePropagation();
    block();
  }, true);

  // 3. Next.js router.push / replace (history API)
  var ps = history.pushState, rs = history.replaceState;
  history.pushState = function (s, t, u) {
    if (u != null && !isHome(u)) { block(); return; }
    return ps.apply(this, arguments);
  };
  history.replaceState = function (s, t, u) {
    if (u != null && !isHome(u)) { block(); return; }
    return rs.apply(this, arguments);
  };

  // 4. Notun tab / window
  window.open = function () { block(); return null; };
})();
''';

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'AppBridge',
        onMessageReceived: (_) => _navigateToAppLogin(),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) async {
            await _controller.runJavaScript(_guardScript);
            if (mounted) setState(() => _isLoading = false);
          },
          // Full page navigation block
          onNavigationRequest: (NavigationRequest request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            if (_isAllowed(request.url)) return NavigationDecision.navigate;
            _navigateToAppLogin();
            return NavigationDecision.prevent;
          },
          // SPA (Next.js) URL change er fallback
          onUrlChange: (UrlChange change) {
            final url = change.url;
            if (url == null || _isAllowed(url)) return;
            _controller.loadRequest(Uri.parse(_websiteUrl));
            _navigateToAppLogin();
          },
        ),
      );

    _init();
  }

  Future<void> _init() async {
    await WebViewCookieManager().clearCookies();
    await _controller.clearCache();
    await _controller.clearLocalStorage();
    await _controller.loadRequest(Uri.parse(_websiteUrl));
  }

  bool _isAllowed(String url) {
    if (url == 'about:blank') return true;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (!_allowedHosts.contains(uri.host.toLowerCase())) return false;
    // Shudhu home path allow; query (?utm=...) ar #anchor thik ache
    return uri.path.isEmpty || uri.path == '/';
  }

  Future<void> _navigateToAppLogin() async {
    if (_isRedirecting || !mounted) return;
    _isRedirecting = true;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
    _isRedirecting = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              Container(
                color: Colors.white,
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF047857)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}