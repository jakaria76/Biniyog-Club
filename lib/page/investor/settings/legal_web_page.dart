import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../services/language_service.dart';

// ═════════════════════════════════════════════════════════
// LEGAL PAGE — biniyogclub.com er Terms / Privacy / About / FAQ
// app er bhitorei dekhay. Lekha website theke ashe, tai website e
// update korlei app eo update hoye jay — app e alada copy nei.
// ═════════════════════════════════════════════════════════
class LegalWebPage extends StatefulWidget {
  final String title;
  final String url;

  const LegalWebPage({super.key, required this.title, required this.url});

  @override
  State<LegalWebPage> createState() => _LegalWebPageState();
}

class _LegalWebPageState extends State<LegalWebPage> {
  static const Color emerald = Color(0xFF0E4A37);
  static const Color goldDeep = Color(0xFF8A6A3A);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);

  static const String _allowedHost = 'biniyogclub.com';

  late final WebViewController _controller;
  int _progress = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ivory)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _failed = false);
          },
          onWebResourceError: (error) {
            // Shudhu main page load fail holei error dekhai
            if (error.isForMainFrame == true && mounted) {
              setState(() => _failed = true);
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            final host = uri?.host ?? '';
            final isOurSite = host == _allowedHost || host.endsWith('.$_allowedHost');
            if (isOurSite && (uri?.scheme == 'https' || uri?.scheme == 'http')) {
              return NavigationDecision.navigate;
            }
            // Onno site, tel:, mailto: — phone er nijer app e khule
            if (uri != null) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  void _retry() {
    setState(() {
      _failed = false;
      _progress = 0;
    });
    _controller.loadRequest(Uri.parse(widget.url));
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
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              widget.title,
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 17),
            ),
            actions: [
              IconButton(
                tooltip: LanguageService.tr('Reload', 'রিলোড'),
                icon: const Icon(Icons.refresh_rounded, color: ink),
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
            const Icon(Icons.wifi_off_rounded, size: 40, color: goldDeep),
            const SizedBox(height: 12),
            Text(
              LanguageService.tr('Could not load this page', 'পেজটি লোড করা যায়নি'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
            ),
            const SizedBox(height: 4),
            Text(
              LanguageService.tr('Please check your internet connection and try again.',
                  'ইন্টারনেট সংযোগ চেক করে আবার চেষ্টা করুন।'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: muted),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _retry,
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(LanguageService.tr('Try again', 'আবার চেষ্টা করুন')),
            ),
          ],
        ),
      ),
    );
  }
}