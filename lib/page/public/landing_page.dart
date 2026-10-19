// ============================================================================
//  LandingPage — website (biniyogclub.com) er home page er native Flutter rup.
//  WebView ar nai. Section order website er moto hubohu:
//    01 Hero (brand video + 2 button + headline)
//    02 About — Discover the Power of Collective Opportunities
//    03 Business Segments — One Platform. Six Business Segments.
//    04 Investment Opportunities — Explore Businesses You Can Be Part Of
//    05 How It Works — Your Investment Journey, Simplified
//    06 Our Portfolio — Explore the Businesses Behind the Opportunities
//    07 Transparency — Clarity, Accountability & Informed Decisions (dark)
//    08 Registration — Join the Biniyog Club Ecosystem (dark)
//    + Footer
//
//  Splash theke: logged in na thakle ei page (agher WebView er jaygay).
//
//  Niyom:
//   - Projects / groups er data DB theke asol data (DatabaseService) — kono
//     banano sonkha nai. Data na thakle oi jinish lukano thake.
//   - Shudhu dekha jay (scroll, filter). "How It Works" page er vitore scroll kore.
//   - Account khola button (Register, Create Free Investor Account, footer
//     "Create Account") → Registration page.
//   - Baki SHOB action (login, project/group tap, onno button, footer link…) → Login page.
//   - Marketing chobi/video website er public folder theke network e load hoy,
//     tai app size bare na. Load na hole Islamic pattern placeholder dekhay.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../screens/home_screen.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/language_service.dart';
import '../authentication/login_page.dart';
import '../authentication/registration_page.dart';

// ─── Palette (InvestorDashboardPage er Islamic palette er sathe mil) ─────────
class _C {
  static const emerald = Color(0xFF0E4A37);
  static const emeraldDeep = Color(0xFF0A3327);
  static const emeraldSoft = Color(0xFFE3F0E9);
  static const night = Color(0xFF06140F); // dark section er background
  static const nightBlue = Color(0xFF0B2A3A);
  static const gold = Color(0xFFB8935A);
  static const goldDeep = Color(0xFF8A6A3A);
  static const goldLight = Color(0xFFD9BE8C);
  static const goldSoft = Color(0xFFF6EEDF);
  static const turquoise = Color(0xFF167A80);
  static const lapis = Color(0xFF26437A);
  static const ivory = Color(0xFFF7F4EE);
  static const ink = Color(0xFF1C2421);
  static const muted = Color(0xFF6E736F);
  static const line = Color(0xFFE8E2D7);
}

const String _site = 'https://biniyogclub.com';
const double _radius = 4; // website er moto prai square corner

String _t(String en, String bn) => LanguageService.tr(en, bn);

String _asset(String path) => '$_site${Uri.encodeFull(path)}';

// ─── Choto helper — DB map theke nirapod vabe value pora ──────────────────
dynamic _pick(Map m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && v.toString().isNotEmpty) return v;
  }
  return null;
}

String _str(Map m, List<String> keys) => (_pick(m, keys) ?? '').toString();

double _num(Map m, List<String> keys) {
  final v = _pick(m, keys);
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

double? _numOrNull(Map m, List<String> keys) {
  final v = _pick(m, keys);
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

List<Map> _list(dynamic v) =>
    v is List ? v.whereType<Map>().toList() : const <Map>[];

/// 1234 → 1,234
String _count(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

/// 15 ba 0.15 — duitai 15% hisebe dhora hoy.
double _pct(double v) => v > 0 && v <= 1 ? v * 100 : v;

String _pctText(double v) {
  final p = _pct(v);
  return p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(1);
}

String _bdt(double n) {
  if (n >= 10000000) return '৳${(n / 10000000).toStringAsFixed(1)} Cr';
  if (n >= 100000) return '৳${(n / 100000).toStringAsFixed(1)}L';
  if (n >= 1000) return '৳${(n / 1000).toStringAsFixed(0)}K';
  return '৳${n.toStringAsFixed(0)}';
}

String? _imageUrl(dynamic raw) {
  final s = raw?.toString() ?? '';
  if (s.isEmpty) return null;
  if (s.startsWith('http')) return s;
  if (s.startsWith('/')) return _asset(s);
  return null;
}

/// Project er return label — website er moto: min–max, na thakle expected.
String? _returnLabel(Map p) {
  final min = _numOrNull(p, ['returnMin', 'returnPctMin']);
  final max = _numOrNull(p, ['returnMax', 'returnPctMax']);
  if (min != null && max != null && max > 0) {
    return '${_pctText(min)}–${_pctText(max)}%';
  }
  final exp = _numOrNull(p, ['expectedReturnPct', 'expectedReturn']);
  if (exp != null && exp > 0) return '${_pctText(exp)}%';
  return null;
}

String _categoryLabel(String c) {
  if (c.isEmpty) return '';
  return c
      .split('_')
      .map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase())
      .join(' ');
}

String _statusLabel(String s) {
  switch (s) {
    case 'FUNDRAISING':
      return _t('Fundraising', 'তহবিল সংগ্রহ চলছে');
    case 'FUNDED':
      return _t('Funded', 'তহবিল পূর্ণ');
    case 'ACTIVE':
      return _t('Active', 'চলমান');
    case 'HARVESTING':
      return _t('Harvesting', 'ফসল সংগ্রহ');
    case 'COMPLETED':
      return _t('Completed', 'সম্পন্ন');
    default:
      return _categoryLabel(s);
  }
}

Color _statusColor(String s) {
  switch (s) {
    case 'FUNDRAISING':
      return const Color(0xFF1F8A5B);
    case 'FUNDED':
      return _C.lapis;
    case 'ACTIVE':
      return _C.turquoise;
    case 'HARVESTING':
      return _C.goldDeep;
    default:
      return _C.muted;
  }
}

// ============================================================================
//  PAGE
// ============================================================================
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  // Onno page er moto static cache — abar khulle sathe sathe dekhay, pichone refresh.
  static List<Map>? _cachedProjects;
  static List<Map>? _cachedGroups;
  static int _cachedInvestors = 0;

  final _scroll = ScrollController();
  final _howItWorksKey = GlobalKey();

  List<Map> _projects = _cachedProjects ?? const [];
  List<Map> _groups = _cachedGroups ?? const [];
  bool _loading = _cachedProjects == null;
  int _totalInvestors = _cachedInvestors;
  bool _openingLogin = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        DatabaseService.getLandingData(),
        DatabaseService.getBusinessGroupsWithTiers(),
      ]);
      final landing = results[0] as Map<String, dynamic>;
      final projects = _list(landing['projects']);
      final groups = _list(results[1]);
      final investors = (landing['totalInvestors'] as int?) ?? 0;
      if (!mounted) return;
      setState(() {
        if (investors > 0) {
          _totalInvestors = investors;
          _cachedInvestors = investors;
        }
        // Network fail hole purono cache rakhi
        if (projects.isNotEmpty || _cachedProjects == null) {
          _projects = projects;
          _cachedProjects = projects;
        }
        if (groups.isNotEmpty || _cachedGroups == null) {
          _groups = groups;
          _cachedGroups = groups;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Landing er shob action → Login page. Login hoye fire ashle → Dashboard.
  Future<void> _goLogin() async {
    if (_openingLogin || !mounted) return;
    _openingLogin = true;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    _openingLogin = false;
    if (!mounted) return;

    bool isLoggedIn = false;
    try {
      isLoggedIn = await AuthService.isLoggedIn();
    } catch (e) {
      debugPrint('Auth check error: $e');
    }
    if (!mounted || !isLoggedIn) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
    );
  }

  /// Account khola button gulo → Registration page.
  /// Registration shofol hole page nijei Dashboard e niye jay.
  Future<void> _goRegister() async {
    if (_openingLogin || !mounted) return;
    _openingLogin = true;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegistrationPage()),
    );
    _openingLogin = false;
    if (!mounted) return;

    // Registration page theke "Sign in" diye login kore fire ashleo Dashboard e
    bool isLoggedIn = false;
    try {
      isLoggedIn = await AuthService.isLoggedIn();
    } catch (e) {
      debugPrint('Auth check error: $e');
    }
    if (!mounted || !isLoggedIn) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
    );
  }

  void _scrollToHowItWorks() {
    final ctx = _howItWorksKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
    }
  }

  /// Ekta project kon group er — groupId / groupSlug / groupName jeta pai.
  List<Map> _projectsOfGroup(Map group) {
    final id = _str(group, ['id']);
    final slug = _str(group, ['slug']).toUpperCase();
    final name = _str(group, ['name']).toLowerCase();
    return _projects.where((p) {
      final pid = _str(p, ['groupId']);
      if (pid.isNotEmpty) return pid == id;
      final ps = _str(p, ['groupSlug']).toUpperCase();
      if (ps.isNotEmpty) return ps == slug;
      final pn = _str(p, ['groupName']).toLowerCase();
      return pn.isNotEmpty && pn == name;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, _, __) {
        final featured = _projects
            .where((p) => const ['FUNDRAISING', 'FUNDED', 'ACTIVE']
            .contains(_str(p, ['status'])))
            .take(6)
            .toList();

        return Scaffold(
          backgroundColor: _C.ivory,
          appBar: _buildAppBar(),
          body: RefreshIndicator(
            color: _C.emerald,
            onRefresh: _load,
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeroSection(
                    onExplore: _goLogin,
                    onHowItWorks: _scrollToHowItWorks,
                  ),
                  _AboutSection(onAction: _goLogin),
                  _HierarchySection(
                    groups: _groups,
                    projectsOf: _projectsOfGroup,
                    loading: _loading,
                    onAction: _goLogin,
                  ),
                  _FeaturedProjectsSection(
                    projects: featured,
                    loading: _loading,
                    onAction: _goLogin,
                  ),
                  KeyedSubtree(
                    key: _howItWorksKey,
                    child: _HowItWorksSection(onAction: _goLogin),
                  ),
                  _PortfolioSection(
                    groups: _groups,
                    loading: _loading,
                    onAction: _goLogin,
                  ),
                  _SecuritySection(onAction: _goLogin),
                  _FinalCtaSection(
                      onAction: _goLogin,
                      onRegister: _goRegister,
                      totalInvestors: _totalInvestors),
                  _Footer(onAction: _goLogin, onRegister: _goRegister),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Colors.black12,
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      toolbarHeight: 64,
      title: Image.asset(
        'assets/images/logo_full.png',
        height: 38,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Text(
          'Biniyog Club',
          style: TextStyle(
              color: _C.emerald, fontWeight: FontWeight.w700, fontSize: 20),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _goLogin,
          style: TextButton.styleFrom(foregroundColor: _C.emerald),
          child: Text(_t('Login', 'লগইন'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12, left: 4),
          child: FilledButton(
            onPressed: _goRegister,
            style: FilledButton.styleFrom(
              backgroundColor: _C.emerald,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_radius)),
            ),
            child: Text(_t('Register', 'রেজিস্টার'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(2),
        child: Container(
          height: 2,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [_C.emerald, _C.gold, _C.turquoise]),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  SHARED WIDGETS
// ============================================================================

/// 8-point star grid (dashboard er pattern er moto).
class _StarPatternPainter extends CustomPainter {
  final Color color;
  final double cell;
  const _StarPatternPainter({required this.color, this.cell = 46});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    final r = cell * 0.26;
    final d = r * 1.4142;
    for (double y = 0; y <= size.height + cell; y += cell) {
      for (double x = 0; x <= size.width + cell; x += cell) {
        final c = Offset(x, y);
        canvas.drawRect(Rect.fromCenter(center: c, width: r * 2, height: r * 2),
            paint);
        final p = Path()
          ..moveTo(c.dx, c.dy - d)
          ..lineTo(c.dx + d, c.dy)
          ..lineTo(c.dx, c.dy + d)
          ..lineTo(c.dx - d, c.dy)
          ..close();
        canvas.drawPath(p, paint);
        canvas.drawCircle(c, r * 0.35, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StarPatternPainter old) =>
      old.color != color || old.cell != cell;
}

class _Pattern extends StatelessWidget {
  final Color color;
  final double cell;
  const _Pattern({required this.color, this.cell = 46});

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: CustomPaint(
          painter: _StarPatternPainter(color: color, cell: cell)),
    ),
  );
}

/// Chobi na thakle / load na hole ei placeholder.
class _PatternPlaceholder extends StatelessWidget {
  final IconData icon;
  const _PatternPlaceholder({this.icon = Icons.eco_outlined});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_C.emerald, _C.emeraldDeep, _C.nightBlue],
        ),
      ),
      child: Stack(children: [
        _Pattern(color: _C.gold.withValues(alpha: 0.22), cell: 34),
        Center(child: Icon(icon, color: _C.goldLight, size: 30)),
      ]),
    );
  }
}

class _NetImage extends StatelessWidget {
  final String? url;
  final IconData placeholderIcon;
  final int? cacheWidth;
  const _NetImage(this.url,
      {this.placeholderIcon = Icons.eco_outlined, this.cacheWidth = 900});

  @override
  Widget build(BuildContext context) {
    if (url == null) return _PatternPlaceholder(icon: placeholderIcon);
    return Image.network(
      url!,
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: frame != null
              ? child
              : Container(
                  color: _C.emeraldDeep,
                  child: const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _C.goldLight,
                      ),
                    ),
                  ),
                ),
        );
      },
      errorBuilder: (_, __, ___) => _PatternPlaceholder(icon: placeholderIcon),
    );
  }
}

/// Section er background: plain → tinted → … → dark (website er rhythm).
class _Section extends StatelessWidget {
  final Widget child;
  final Color color;
  final bool pattern;
  const _Section(
      {required this.child, this.color = _C.ivory, this.pattern = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      child: Stack(children: [
        if (pattern) _Pattern(color: _C.gold.withValues(alpha: 0.07), cell: 54),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 52, 16, 52),
          child: child,
        ),
      ]),
    );
  }
}

/// Website er SectionHeading: eyebrow — light title + semibold highlight — description.
class _SectionHeading extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? highlight;
  final String? description;
  final bool center;
  final bool dark;
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    this.highlight,
    this.description,
    this.center = false,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final eyebrowColor = dark ? _C.goldLight : _C.goldDeep;
    final lineW = Container(
        width: 22, height: 1, color: eyebrowColor.withValues(alpha: 0.7));
    return Column(
      crossAxisAlignment:
      center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            lineW,
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                eyebrow.toUpperCase(),
                style: TextStyle(
                  color: eyebrowColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ),
            if (center) ...[const SizedBox(width: 8), lineW],
          ],
        ),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: title,
              style: TextStyle(
                fontWeight: FontWeight.w300,
                color: dark ? Colors.white : _C.ink,
              ),
            ),
            if (highlight != null) ...[
              const TextSpan(text: ' '),
              TextSpan(
                text: highlight,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: dark ? _C.goldLight : _C.emerald,
                ),
              ),
            ],
          ]),
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: const TextStyle(fontSize: 28, height: 1.2, letterSpacing: -0.4),
        ),
        if (description != null) ...[
          const SizedBox(height: 14),
          Text(
            description!,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              fontSize: 15,
              height: 1.55,
              color: dark ? const Color(0xFFC9D3CE) : _C.muted,
            ),
          ),
        ],
      ],
    );
  }
}

enum _BtnStyle { primary, outline, ghostDark, gold }

class _Btn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final _BtnStyle style;
  final IconData? icon;
  const _Btn(this.label,
      {required this.onTap, this.style = _BtnStyle.primary, this.icon});

  @override
  Widget build(BuildContext context) {
    late Color bg, fg;
    Color? border;
    switch (style) {
      case _BtnStyle.primary:
        bg = _C.emerald;
        fg = Colors.white;
        break;
      case _BtnStyle.outline:
        bg = Colors.white;
        fg = _C.emerald;
        border = _C.line;
        break;
      case _BtnStyle.ghostDark:
        bg = Colors.white.withValues(alpha: 0.08);
        fg = Colors.white;
        border = Colors.white.withValues(alpha: 0.25);
        break;
      case _BtnStyle.gold:
        bg = _C.gold;
        fg = Colors.white;
        break;
    }
    final btn = Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
        side: border == null ? BorderSide.none : BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: fg,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600)),
              ),
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(icon, color: fg, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
    return SizedBox(width: double.infinity, child: btn);
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  final Color? border;
  final IconData? icon;
  final bool dot;
  const _Pill(this.text,
      {required this.fg,
        required this.bg,
        this.border,
        this.icon,
        this.dot = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(2),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 5),
        ],
        if (icon != null) ...[
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: fg,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3)),
        ),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Card({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
        side: const BorderSide(color: _C.line),
      ),
      child: InkWell(onTap: onTap, child: child),
    );
  }
}

class _LoadingBox extends StatelessWidget {
  const _LoadingBox();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 40),
    child: Center(
      child: SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: _C.emerald),
      ),
    ),
  );
}

class _EmptyBox extends StatelessWidget {
  final String text;
  const _EmptyBox(this.text);
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_radius),
      border: Border.all(color: _C.line),
    ),
    child: Text(text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _C.muted, fontSize: 13.5)),
  );
}

// ============================================================================
//  01 HERO
// ============================================================================
class _HeroSection extends StatelessWidget {
  final VoidCallback onExplore;
  final VoidCallback onHowItWorks;
  const _HeroSection({required this.onExplore, required this.onHowItWorks});

  @override
  Widget build(BuildContext context) {
    final h = (MediaQuery.of(context).size.height * 0.5).clamp(300.0, 480.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const _HeroVideo(),
              // Button gulo porishkar dekhate niche halka gradient
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.55, 1],
                    colors: [Colors.transparent, Color(0x99000000)],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Row(children: [
                  Expanded(
                    child: _Btn(_t('Explore Opportunities', 'সুযোগগুলো দেখুন'),
                        onTap: onExplore, icon: Icons.arrow_forward),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Btn(_t('How It Works', 'কীভাবে কাজ করে'),
                        onTap: onHowItWorks, style: _BtnStyle.outline),
                  ),
                ]),
              ),
            ],
          ),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 34, 20, 34),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: _t('Your Gateway to ', 'আপনার প্রবেশদ্বার — '),
                  style: const TextStyle(fontWeight: FontWeight.w300)),
              TextSpan(
                text: _t('Real Business Opportunities',
                    'বাস্তব ব্যবসায়িক সুযোগে'),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: _C.emerald),
              ),
            ]),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 28, height: 1.25, color: _C.ink, letterSpacing: -0.4),
          ),
        ),
        Container(height: 1, color: _C.line),
      ],
    );
  }
}

/// Website er brand video ("logo with money.mp4") — loop, mute.
/// Load na hole / internet na thakle pattern + logo dekhay.
class _HeroVideo extends StatefulWidget {
  const _HeroVideo();
  @override
  State<_HeroVideo> createState() => _HeroVideoState();
}

class _HeroVideoState extends State<_HeroVideo> {
  VideoPlayerController? _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(
      Uri.parse(_asset('/logo with money.mp4')),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _ctrl = c;
    try {
      await c.initialize().timeout(const Duration(seconds: 45));
      await c.setVolume(0);
      await c.setLooping(true);
      await c.play();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint("Hero video load_error on physical device: $e");
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    return Stack(fit: StackFit.expand, children: [
      // Poster (video load howar age / fail korle)
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_C.emerald, _C.emeraldDeep, _C.nightBlue],
          ),
        ),
        child: Stack(children: [
          _Pattern(color: _C.gold.withValues(alpha: 0.18)),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: Image.asset(
                'assets/images/logo_icon.png',
                height: 96,
                errorBuilder: (_, __, ___) => const Icon(Icons.mosque_outlined,
                    color: _C.goldLight, size: 64),
              ),
            ),
          ),
        ]),
      ),
      AnimatedOpacity(
        opacity: _ready && c != null ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 800),
        child: c != null
            ? FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
                ),
              )
            : const SizedBox.shrink(),
      ),
    ]);
  }
}

// ============================================================================
//  02 ABOUT
// ============================================================================
class _AboutSection extends StatelessWidget {
  final VoidCallback onAction;
  const _AboutSection({required this.onAction});

  @override
  Widget build(BuildContext context) {
    final pillars = [
      (
      _t('Secure Platform', 'নিরাপদ প্ল্যাটফর্ম'),
      _t(
          'Rigorous due diligence, multi-tier audits, and segregated escrow management for all allocations.',
          'কঠোর যাচাই-বাছাই, বহুস্তরের অডিট এবং প্রতিটি বিনিয়োগের জন্য আলাদা এসক্রো ব্যবস্থাপনা।'),
      '/icons/secure-platform.jpg',
      ),
      (
      _t('Transparent Process', 'স্বচ্ছ প্রক্রিয়া'),
      _t(
          'Full milestone transparency, audited yield formulas, and zero hidden deductions.',
          'প্রতিটি ধাপে পূর্ণ স্বচ্ছতা, অডিটকৃত মুনাফার হিসাব এবং কোনো লুকানো কর্তন নেই।'),
      '/icons/transparent-process.jpg',
      ),
      (
      _t('Modern Technology', 'আধুনিক প্রযুক্তি'),
      _t(
          'Double-entry cryptographic ledger architecture ensuring balance immutability and instant reconciliation.',
          'ডাবল-এন্ট্রি লেজার ব্যবস্থা, যাতে হিসাব অপরিবর্তনীয় থাকে এবং তাৎক্ষণিক মিলানো যায়।'),
      '/icons/modern-technology.jpg',
      ),
      (
      _t('User-Focused Experience', 'ব্যবহারকারী-কেন্দ্রিক অভিজ্ঞতা'),
      _t(
          'Seamless NID onboarding, real-time dashboard analytics, and direct payouts to bank or MFS accounts.',
          'সহজ NID দিয়ে যুক্ত হওয়া, রিয়েল-টাইম ড্যাশবোর্ড এবং সরাসরি ব্যাংক বা মোবাইল ব্যাংকিংয়ে মুনাফা।'),
      '/icons/user-experience.jpg',
      ),
    ];

    return _Section(
      color: _C.ivory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Due diligence image card ──
          ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 230,
                  child: Stack(fit: StackFit.expand, children: [
                    _NetImage(_asset('/images/about-due-diligence.jpg'),
                        placeholderIcon: Icons.fact_check_outlined),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xF006140F), Color(0x6606140F), Colors.transparent],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 14,
                      left: 14,
                      child: _Pill(
                        _t('On-Site Due Diligence Team', 'সরেজমিন যাচাই টিম'),
                        fg: Colors.white,
                        bg: Colors.black.withValues(alpha: 0.55),
                        border: Colors.white24,
                        icon: Icons.verified_user_outlined,
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 14,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_t('DHAKA HEADQUARTERS', 'ঢাকা প্রধান কার্যালয়'),
                              style: const TextStyle(
                                  color: _C.goldLight,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.4)),
                          const SizedBox(height: 3),
                          Text(
                              _t('Physical Site & Financial Audits',
                                  'সরেজমিন পরিদর্শন ও আর্থিক অডিট'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_C.emeraldDeep, _C.night, _C.nightBlue],
                    ),
                  ),
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                        child: _DarkFact(
                          label: _t('GOVERNANCE', 'পরিচালনা'),
                          value: _t('Bangladesh Law', 'বাংলাদেশের আইন'),
                          note: _t('Contract Act 1872', 'চুক্তি আইন ১৮৭২'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DarkFact(
                          label: _t('LEDGER AUDIT', 'লেজার অডিট'),
                          value: _t('Double-Entry', 'ডাবল-এন্ট্রি'),
                          note: _t('Zero Tampering', 'পরিবর্তন অসম্ভব'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    _DarkCheckBar(
                      text: _t('Multi-tier physical checks on every asset',
                          'প্রতিটি সম্পদে বহুস্তরের সরেজমিন যাচাই'),
                      trailing: _t('Verified', 'যাচাইকৃত'),
                    ),
                  ]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          _SectionHeading(
            eyebrow: _t('About Biniyog Club', 'বিনিয়োগ ক্লাব সম্পর্কে'),
            title: _t('Discover the Power of', 'আবিষ্কার করুন'),
            highlight: _t('Collective Opportunities', 'সম্মিলিত সুযোগের শক্তি'),
            description: _t(
                'Biniyog Club was established with a clear mandate: to bridge the gap between conscientious co-investors and high-potential, vetted commercial opportunities in Bangladesh.',
                'বিনিয়োগ ক্লাব প্রতিষ্ঠিত হয়েছে একটি স্পষ্ট লক্ষ্যে — সচেতন সহ-বিনিয়োগকারীদের সাথে বাংলাদেশের সম্ভাবনাময়, যাচাইকৃত ব্যবসায়িক সুযোগের সেতুবন্ধন তৈরি করা।'),
          ),
          const SizedBox(height: 12),
          Text(
            _t(
                'By combining institutional-grade financial analysis, direct legal enforceability, and an immutable double-entry ledger, we give everyday investors and institutions access to structured wealth creation previously reserved for private equity firms.',
                'প্রাতিষ্ঠানিক মানের আর্থিক বিশ্লেষণ, সরাসরি আইনি সুরক্ষা এবং অপরিবর্তনীয় ডাবল-এন্ট্রি লেজার একসাথে করে আমরা সাধারণ বিনিয়োগকারী ও প্রতিষ্ঠানকে এমন সুসংগঠিত সম্পদ গড়ার সুযোগ দিই, যা আগে শুধু প্রাইভেট ইকুইটি প্রতিষ্ঠানের জন্য ছিল।'),
            style: const TextStyle(fontSize: 14.5, height: 1.6, color: _C.muted),
          ),
          const SizedBox(height: 24),
          for (final p in pillars) ...[
            _Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        border: Border.all(color: _C.gold.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(_radius),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _NetImage(_asset(p.$3),
                          cacheWidth: 140,
                          placeholderIcon: Icons.star_border_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.$1,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: _C.ink)),
                          const SizedBox(height: 4),
                          Text(p.$2,
                              style: const TextStyle(
                                  fontSize: 12.5, height: 1.5, color: _C.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 14),
          _Btn(_t('Our Methodology & Team', 'আমাদের পদ্ধতি ও টিম'),
              onTap: onAction, icon: Icons.chevron_right),
          const SizedBox(height: 10),
          _Btn(_t('How The Platform Works', 'প্ল্যাটফর্ম কীভাবে কাজ করে'),
              onTap: onAction, style: _BtnStyle.outline),
        ],
      ),
    );
  }
}

class _DarkFact extends StatelessWidget {
  final String label, value, note;
  const _DarkFact(
      {required this.label, required this.value, required this.note});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      borderRadius: BorderRadius.circular(2),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              color: Color(0xFF9AA7A1),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8)),
      const SizedBox(height: 3),
      Text(value,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Text(note,
          style: const TextStyle(color: _C.goldLight, fontSize: 10.5)),
    ]),
  );
}

class _DarkCheckBar extends StatelessWidget {
  final String text, trailing;
  const _DarkCheckBar({required this.text, required this.trailing});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _C.emerald.withValues(alpha: 0.45),
      border: Border.all(color: _C.gold.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(2),
    ),
    child: Row(children: [
      const Icon(Icons.check_circle_outline, color: _C.goldLight, size: 18),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFFE2E8E5), fontSize: 12, height: 1.4)),
      ),
      const SizedBox(width: 8),
      Text(trailing,
          style: const TextStyle(
              color: _C.goldLight,
              fontSize: 12,
              fontWeight: FontWeight.w700)),
    ]),
  );
}

// ============================================================================
//  03 BUSINESS SEGMENTS (hierarchy)
// ============================================================================

class _GroupVisual {
  final String cover;
  final String sectorEn, sectorBn;
  final String code;
  final IconData icon;
  const _GroupVisual(
      this.cover, this.sectorEn, this.sectorBn, this.code, this.icon);
}

// Website er GROUP_VISUAL_MAP (hierarchy section)
const Map<String, _GroupVisual> _hierarchyVisual = {
  'MARINERS': _GroupVisual('/2.png', 'Maritime & Supply Chain',
      'সামুদ্রিক ও সাপ্লাই চেইন', 'GRP-01', Icons.account_balance_outlined),
  'MOHS': _GroupVisual('/3.png', 'Real Estate & Commercial Holdings',
      'রিয়েল এস্টেট ও বাণিজ্যিক সম্পদ', 'GRP-02', Icons.apartment_outlined),
  'MARINOZZ': _GroupVisual('/4.png', 'Hospitality & Agro Enterprise',
      'আতিথেয়তা ও কৃষি উদ্যোগ', 'GRP-03', Icons.auto_awesome_outlined),
  'CV': _GroupVisual('/images/investor-community.jpg',
      'Community & Impact Ventures', 'কমিউনিটি ও ইমপ্যাক্ট উদ্যোগ', 'GRP-04',
      Icons.groups_outlined),
  'VA': _GroupVisual('/images/about-due-diligence.jpg',
      'Strategic Cross-Sector Alliances', 'কৌশলগত বহুখাত জোট', 'GRP-05',
      Icons.work_outline),
};

class _HierarchySection extends StatefulWidget {
  final List<Map> groups;
  final List<Map> Function(Map group) projectsOf;
  final bool loading;
  final VoidCallback onAction;
  const _HierarchySection({
    required this.groups,
    required this.projectsOf,
    required this.loading,
    required this.onAction,
  });

  @override
  State<_HierarchySection> createState() => _HierarchySectionState();
}

class _HierarchySectionState extends State<_HierarchySection> {
  String _filter = 'ALL'; // ALL | ACTIVE | UPCOMING

  // Website er STATIC_GROUPS — ekhono DB te nei, "Incubating" dekhay.
  List<Map<String, dynamic>> get _staticGroups => [
    {
      'id': 'cv',
      'slug': null,
      'name': _t('Community Ventures', 'কমিউনিটি ভেঞ্চারস'),
      'tagline': _t('Community-driven co-investment initiatives',
          'কমিউনিটি-ভিত্তিক সহ-বিনিয়োগ উদ্যোগ'),
    },
    {
      'id': 'va',
      'slug': null,
      'name': _t('Venture Alliances', 'ভেঞ্চার অ্যালায়েন্স'),
      'tagline': _t('Strategic cross-sector consortium partnerships',
          'কৌশলগত বহুখাতের অংশীদারিত্ব'),
    },
  ];

  @override
  Widget build(BuildContext context) {
    final live = widget.groups;
    final statics = _staticGroups;
    final all = <Map>[...live, ...statics];
    final shown = _filter == 'ACTIVE'
        ? live
        : _filter == 'UPCOMING'
        ? statics
        : all;

    return _Section(
      color: _C.goldSoft,
      pattern: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(
            center: true,
            eyebrow: _t('Business segments', 'ব্যবসায়িক খাত'),
            title: _t('One Platform.', 'একটি প্ল্যাটফর্ম।'),
            highlight: _t('Six Business Segments.', 'ছয়টি ব্যবসায়িক খাত।'),
          ),
          const SizedBox(height: 28),
          // ── Master hub card ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(color: _C.emerald.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                    color: _C.emerald.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8)),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              Container(
                height: 3,
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [_C.emerald, _C.gold, _C.turquoise])),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    color: _C.emerald,
                    padding: const EdgeInsets.all(10),
                    child: Image.asset(
                      'assets/images/logo_icon.png',
                      color: Colors.white,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.account_balance,
                          color: Colors.white,
                          size: 24),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_t('Biniyog Club', 'বিনিয়োগ ক্লাব'),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _C.ink)),
                        const SizedBox(height: 2),
                        Text(
                            _t('Central investment platform',
                                'কেন্দ্রীয় বিনিয়োগ প্ল্যাটফর্ম'),
                            style: const TextStyle(
                                fontSize: 12.5, color: _C.muted)),
                      ],
                    ),
                  ),
                  _Pill(_t('Live', 'লাইভ'),
                      fg: const Color(0xFF1F8A5B),
                      bg: _C.emeraldSoft,
                      dot: true),
                ]),
              ),
            ]),
          ),
          // ── Stem connector ──
          Center(
            child: Column(children: [
              Container(width: 2, height: 22, color: _C.emerald.withValues(alpha: 0.6)),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: _C.emerald.withValues(alpha: 0.4)),
                ),
                alignment: Alignment.center,
                child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: _C.gold, shape: BoxShape.circle)),
              ),
              Container(width: 2, height: 18, color: _C.gold.withValues(alpha: 0.5)),
            ]),
          ),
          const SizedBox(height: 10),
          Text(_t('TIER-2 CORPORATE HOLDINGS', 'টিয়ার-২ কর্পোরেট হোল্ডিংস'),
              style: const TextStyle(
                  color: _C.goldDeep,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text(_t('Institutional Business Groups', 'প্রাতিষ্ঠানিক ব্যবসায়িক গ্রুপ'),
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w700, color: _C.ink)),
          const SizedBox(height: 14),
          // ── Filter tabs ──
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _C.line),
              borderRadius: BorderRadius.circular(_radius),
            ),
            child: Row(children: [
              _tab('ALL', '${_t('All', 'সব')} (${all.length})'),
              _tab('ACTIVE', '${_t('Active', 'সক্রিয়')} (${live.length})'),
              _tab('UPCOMING',
                  '${_t('Incubating', 'প্রস্তুতিতে')} (${statics.length})'),
            ]),
          ),
          const SizedBox(height: 18),
          if (widget.loading && live.isEmpty && _filter != 'UPCOMING')
            const _LoadingBox(),
          for (int i = 0; i < shown.length; i++) ...[
            _SegmentGroupCard(
              group: shown[i],
              projects:
              shown[i]['slug'] == null ? const [] : widget.projectsOf(shown[i]),
              onAction: widget.onAction,
            ),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 10),
          // ── Bottom CTA hub ──
          _Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      _t('Ready to co-invest in verified commercial projects?',
                          'যাচাইকৃত ব্যবসায়িক প্রকল্পে সহ-বিনিয়োগ করতে প্রস্তুত?'),
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _C.ink,
                          height: 1.3)),
                  const SizedBox(height: 6),
                  Text(
                      _t(
                          'Choose an individual project or co-invest directly at the parent holding group level to gain diversified profit allocations.',
                          'একটি নির্দিষ্ট প্রকল্প বেছে নিন, অথবা সরাসরি মূল গ্রুপ পর্যায়ে সহ-বিনিয়োগ করে বৈচিত্র্যময় মুনাফা পান।'),
                      style: const TextStyle(
                          fontSize: 13, height: 1.5, color: _C.muted)),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: _Btn(_t('Browse Projects', 'প্রকল্প দেখুন'),
                          onTap: widget.onAction, style: _BtnStyle.outline),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Btn(_t('Explore All Groups', 'সব গ্রুপ দেখুন'),
                          onTap: widget.onAction),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(String key, String label) {
    final on = _filter == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          color: on ? _C.emerald : Colors.transparent,
          alignment: Alignment.center,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: on ? Colors.white : _C.muted)),
        ),
      ),
    );
  }
}

class _SegmentGroupCard extends StatelessWidget {
  final Map group;
  final List<Map> projects;
  final VoidCallback onAction;
  const _SegmentGroupCard(
      {required this.group, required this.projects, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final slug = group['slug']?.toString();
    final isLive = slug != null && slug.isNotEmpty;
    final key = (slug ?? group['id']?.toString() ?? '').toUpperCase();
    final visual = _hierarchyVisual[key];
    final name = _str(group, ['name']);
    final cover = _imageUrl(_pick(group, ['coverUrl', 'coverImageUrl'])) ??
        (visual != null ? _asset(visual.cover) : null);
    final logo = _imageUrl(_pick(group, ['logoUrl']));
    final tagline = _str(group, ['tagline', 'description']);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Cover banner ──
          SizedBox(
            height: 150,
            child: Stack(fit: StackFit.expand, children: [
              Opacity(
                  opacity: 0.85,
                  child: _NetImage(cover,
                      placeholderIcon: visual?.icon ?? Icons.apartment_outlined)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xF006140F), Color(0x8806140F), Colors.transparent],
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (visual != null)
                      _Pill(visual.code,
                          fg: _C.goldLight,
                          bg: Colors.black.withValues(alpha: 0.55),
                          border: _C.gold.withValues(alpha: 0.4),
                          dot: true)
                    else
                      const SizedBox.shrink(),
                    isLive
                        ? _Pill(_t('Active Holding', 'সক্রিয় হোল্ডিং'),
                        fg: const Color(0xFF9FE0BF),
                        bg: _C.emeraldDeep.withValues(alpha: 0.85),
                        border: const Color(0x5534D399),
                        icon: Icons.check_circle_outline)
                        : _Pill(_t('Incubating', 'প্রস্তুতিতে'),
                        fg: _C.goldLight,
                        bg: const Color(0xD93A2A10),
                        border: _C.gold.withValues(alpha: 0.4),
                        icon: Icons.lock_outline),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      border: Border.all(color: _C.gold.withValues(alpha: 0.4)),
                    ),
                    padding: const EdgeInsets.all(7),
                    child: logo != null
                        ? Image.network(logo,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                            visual?.icon ?? Icons.apartment_outlined,
                            color: _C.emerald))
                        : Icon(visual?.icon ?? Icons.apartment_outlined,
                        color: _C.emerald),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            (visual == null
                                ? _t('Commercial Holdings', 'বাণিজ্যিক হোল্ডিংস')
                                : _t(visual.sectorEn, visual.sectorBn))
                                .toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Color(0xFFCBD5D1),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 2),
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          // ── Tagline + assets count ──
          Container(
            color: _C.ivory,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tagline.isNotEmpty)
                  Text(tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, height: 1.45, color: _C.muted)),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.layers_outlined, size: 15, color: _C.emerald),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                        _t(
                            '${projects.length} Asset${projects.length == 1 ? '' : 's'} Hosted',
                            '${projects.length}টি প্রকল্প'),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _C.muted)),
                  ),
                  if (isLive)
                    InkWell(
                      onTap: onAction,
                      child: Row(children: [
                        Text(_t('Details', 'বিস্তারিত'),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _C.emerald)),
                        const Icon(Icons.chevron_right,
                            size: 16, color: _C.emerald),
                      ]),
                    )
                  else
                    Text(_t('Audit in progress', 'অডিট চলছে'),
                        style:
                        const TextStyle(fontSize: 11, color: _C.muted)),
                ]),
              ],
            ),
          ),
          Container(height: 1, color: _C.line),
          // ── Nested projects ──
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                        _t('COMMERCIAL PROJECTS', 'বাণিজ্যিক প্রকল্প'),
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: _C.muted)),
                  ),
                  if (projects.isNotEmpty)
                    Text(_t('Live & Vetted', 'লাইভ ও যাচাইকৃত'),
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F8A5B))),
                ]),
                const SizedBox(height: 10),
                if (projects.isNotEmpty)
                  for (final p in projects) ...[
                    _ProjectMiniCard(project: p, onTap: onAction),
                    const SizedBox(height: 8),
                  ]
                else
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border.all(color: _C.line),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Column(children: [
                      const Icon(Icons.folder_open_outlined,
                          color: _C.muted, size: 26),
                      const SizedBox(height: 8),
                      Text(
                          _t('Upcoming Project Pipeline',
                              'আসন্ন প্রকল্পের তালিকা'),
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _C.ink)),
                      const SizedBox(height: 4),
                      Text(
                          _t(
                              'Compliance and risk underwriting currently in progress for co-investment listing.',
                              'সহ-বিনিয়োগ তালিকাভুক্তির জন্য কমপ্লায়েন্স ও ঝুঁকি যাচাই চলছে।'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 11.5, height: 1.45, color: _C.muted)),
                    ]),
                  ),
              ],
            ),
          ),
          // ── Footer action ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: isLive
                ? _Btn(
                _t('Explore $name Portfolio', '$name পোর্টফোলিও দেখুন'),
                onTap: onAction,
                style: _BtnStyle.outline,
                icon: Icons.arrow_forward)
                : Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: _C.ivory,
              alignment: Alignment.center,
              child: Text(
                  _t('Pipeline Coming Soon', 'শীঘ্রই তালিকাভুক্ত হবে'),
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: _C.muted)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectMiniCard extends StatelessWidget {
  final Map project;
  final VoidCallback onTap;
  const _ProjectMiniCard({required this.project, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = _str(project, ['status']);
    final category = _str(project, ['category']);
    final min = _num(project, ['minInvestmentBdt', 'minInvestment']);
    final days = _num(project, ['durationDays']);
    final ret = _returnLabel(project);
    final img = _imageUrl(_pick(project, ['coverImageUrl', 'coverImage', 'cover'])) ??
        _firstImage(project);

    return _Card(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          SizedBox(
            width: 66,
            height: 66,
            child: Stack(fit: StackFit.expand, children: [
              _NetImage(img, cacheWidth: 200),
              if (category.isNotEmpty)
                Positioned(
                  left: 3,
                  right: 3,
                  bottom: 3,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.6),
                    padding:
                    const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    child: Text(category.replaceAll('_', ' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(_str(project, ['title']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _C.ink)),
                  ),
                  const Icon(Icons.north_east, size: 14, color: _C.muted),
                ]),
                const SizedBox(height: 5),
                Row(children: [
                  if (status.isNotEmpty)
                    Flexible(
                      child: _Pill(_statusLabel(status),
                          fg: _statusColor(status),
                          bg: _statusColor(status).withValues(alpha: 0.1),
                          border: _statusColor(status).withValues(alpha: 0.3),
                          dot: true),
                    ),
                  if (min > 0) ...[
                    const SizedBox(width: 6),
                    Text('${_t('Min', 'সর্বনিম্ন')} ${_bdt(min)}',
                        style:
                        const TextStyle(fontSize: 10.5, color: _C.muted)),
                  ],
                ]),
                const SizedBox(height: 6),
                Container(height: 1, color: _C.line),
                const SizedBox(height: 5),
                Row(children: [
                  if (ret != null) ...[
                    const Icon(Icons.trending_up,
                        size: 13, color: Color(0xFF1F8A5B)),
                    const SizedBox(width: 3),
                    Text(ret,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F8A5B))),
                    const SizedBox(width: 3),
                    Text(_t('p.a.', 'বার্ষিক'),
                        style: const TextStyle(fontSize: 9.5, color: _C.muted)),
                  ],
                  const Spacer(),
                  if (days > 0) ...[
                    const Icon(Icons.schedule, size: 12, color: _C.muted),
                    const SizedBox(width: 3),
                    Text('${(days / 30).round()} ${_t('mo', 'মাস')}',
                        style:
                        const TextStyle(fontSize: 10.5, color: _C.muted)),
                  ],
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

String? _firstImage(Map p) {
  final imgs = _pick(p, ['imageUrls', 'images']);
  if (imgs is List && imgs.isNotEmpty) {
    final first = imgs.first;
    if (first is Map) return _imageUrl(_pick(first, ['url', 'src']));
    return _imageUrl(first);
  }
  return null;
}

// ============================================================================
//  04 INVESTMENT OPPORTUNITIES (featured projects)
// ============================================================================
class _FeaturedProjectsSection extends StatelessWidget {
  final List<Map> projects;
  final bool loading;
  final VoidCallback onAction;
  const _FeaturedProjectsSection(
      {required this.projects, required this.loading, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return _Section(
      color: _C.ivory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(
            eyebrow: _t('Investment opportunities', 'বিনিয়োগের সুযোগ'),
            title: _t('Explore Businesses', 'যেসব ব্যবসার'),
            highlight: _t('You Can Be Part Of', 'অংশ হতে পারেন'),
            description: _t(
                'Explore admin-vetted, asset-backed commercial ventures with legally binding contracts and transparent milestone distributions.',
                'যাচাইকৃত, সম্পদ-সমর্থিত ব্যবসায়িক উদ্যোগ দেখুন — আইনি চুক্তি এবং ধাপে ধাপে স্বচ্ছ মুনাফা বণ্টনসহ।'),
          ),
          const SizedBox(height: 26),
          if (loading && projects.isEmpty)
            const _LoadingBox()
          else if (projects.isEmpty)
            _EmptyBox(_t('New vetted project listings are currently being audited.',
                'নতুন যাচাইকৃত প্রকল্পগুলোর অডিট চলছে।'))
          else
            for (final p in projects) ...[
              _ProjectCard(project: p, onTap: onAction),
              const SizedBox(height: 18),
            ],
          const SizedBox(height: 8),
          _Btn(_t('View All Investment Projects', 'সব বিনিয়োগ প্রকল্প দেখুন'),
              onTap: onAction,
              style: _BtnStyle.outline,
              icon: Icons.chevron_right),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final Map project;
  final VoidCallback onTap;
  const _ProjectCard({required this.project, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = _str(project, ['status']);
    final category = _categoryLabel(_str(project, ['category']));
    final title = _str(project, ['title']);
    final location = _str(project, ['location']);
    final desc = _str(project, ['description']);
    final goal = _num(project, ['fundingGoalBdt', 'fundingGoal', 'goal']);
    final raised = _num(project, ['fundedAmountBdt', 'fundedAmount', 'raised']);
    final min = _num(project, ['minInvestmentBdt', 'minInvestment']);
    final days = _num(project, ['durationDays']);
    final investors = _num(project, ['investorCount', 'investors', 'investorsCount']);
    final daysLeft = _num(project, ['daysLeft']);
    final hasDeadline = project['hasDeadline'] == true;
    final ret = _returnLabel(project);
    final groupName = _str(project, ['groupName']);
    final img = _imageUrl(_pick(project, ['coverImageUrl', 'coverImage', 'cover'])) ??
        _firstImage(project);
    final pct = goal > 0 ? (raised / goal).clamp(0.0, 1.0).toDouble() : 0.0;

    return _Card(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 190,
            child: Stack(fit: StackFit.expand, children: [
              _NetImage(img),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [Color(0x9906140F), Colors.transparent],
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (category.isNotEmpty)
                      Flexible(
                        child: _Pill(category,
                            fg: _C.emerald, bg: Colors.white.withValues(alpha: 0.92)),
                      ),
                    if (status.isNotEmpty)
                      _Pill(
                        status == 'FUNDRAISING' && hasDeadline && daysLeft > 0
                            ? _t('${daysLeft.toInt()} days left',
                            '${daysLeft.toInt()} দিন বাকি')
                            : _statusLabel(status),
                        fg: Colors.white,
                        bg: _statusColor(status),
                        dot: true,
                      ),
                  ],
                ),
              ),
              if (groupName.isNotEmpty)
                Positioned(
                  left: 12,
                  bottom: 10,
                  right: 12,
                  child: Text(groupName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _C.goldLight,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _C.ink,
                        height: 1.3)),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Row(children: [
                    const Icon(Icons.place_outlined, size: 14, color: _C.muted),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, color: _C.muted)),
                    ),
                  ]),
                ],
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, height: 1.5, color: _C.muted)),
                ],
                if (goal > 0) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    Text('${(pct * 100).toStringAsFixed(0)}% ${_t('funded', 'সংগৃহীত')}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _C.emerald)),
                    const Spacer(),
                    Text('${_bdt(raised)} / ${_bdt(goal)}',
                        style: const TextStyle(
                            fontSize: 12, color: _C.muted)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: _C.emeraldSoft,
                      valueColor: const AlwaysStoppedAnimation(_C.gold),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  if (ret != null)
                    _MetricBox(
                        label: _t('Return', 'রিটার্ন'),
                        value: ret,
                        valueColor: const Color(0xFF1F8A5B)),
                  if (days > 0)
                    _MetricBox(
                        label: _t('Duration', 'মেয়াদ'),
                        value: '${(days / 30).round()} ${_t('mo', 'মাস')}'),
                  if (investors > 0)
                    _MetricBox(
                        label: _t('Investors', 'বিনিয়োগকারী'),
                        value: investors.toInt().toString()),
                ]),
                if (min > 0) ...[
                  const SizedBox(height: 12),
                  Container(height: 1, color: _C.line),
                  const SizedBox(height: 10),
                  Row(children: [
                    Text(_t('Minimum investment', 'সর্বনিম্ন বিনিয়োগ'),
                        style:
                        const TextStyle(fontSize: 12, color: _C.muted)),
                    const Spacer(),
                    Text(_bdt(min),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _C.ink)),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 18, color: _C.emerald),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  final String label, value;
  final Color valueColor;
  const _MetricBox(
      {required this.label, required this.value, this.valueColor = _C.ink});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      decoration: BoxDecoration(
        color: _C.ivory,
        border: Border.all(color: _C.line),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(children: [
        Text(label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: _C.muted)),
        const SizedBox(height: 3),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: valueColor)),
      ]),
    ),
  );
}

// ============================================================================
//  05 HOW IT WORKS
// ============================================================================
class _HowItWorksSection extends StatelessWidget {
  final VoidCallback onAction;
  const _HowItWorksSection({required this.onAction});

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
      '01',
      _t('Create Your Account', 'অ্যাকাউন্ট খুলুন'),
      _t('Register in under 2 minutes. Instant digital identity checks with NID/Passport verification.',
          '২ মিনিটেরও কম সময়ে রেজিস্টার করুন। NID/পাসপোর্ট দিয়ে তাৎক্ষণিক ডিজিটাল পরিচয় যাচাই।'),
      '/images/digital-kyc-verify.jpg',
      _t('Fast Onboarding', 'দ্রুত যুক্ত হওয়া'),
      ),
      (
      '02',
      _t('Explore Vetted Portfolios', 'যাচাইকৃত পোর্টফোলিও দেখুন'),
      _t('Compare reviewed agricultural and commercial ventures with audited returns and transparent disclosures.',
          'অডিটকৃত রিটার্ন ও স্বচ্ছ তথ্যসহ যাচাইকৃত কৃষি ও বাণিজ্যিক উদ্যোগ তুলনা করুন।'),
      '/images/smart-agro-farm.jpg',
      _t('Vetted Portfolios', 'যাচাইকৃত পোর্টফোলিও'),
      ),
      (
      '03',
      _t('Direct Legal Contract', 'সরাসরি আইনি চুক্তি'),
      _t('Fund seamlessly via Bank or MFS. Every investment is bound by an enforceable digital deed.',
          'ব্যাংক বা মোবাইল ব্যাংকিংয়ে সহজে টাকা দিন। প্রতিটি বিনিয়োগ কার্যকর ডিজিটাল দলিলে সুরক্ষিত।'),
      '/images/contract-security.jpg',
      _t('Legally Protected', 'আইনিভাবে সুরক্ষিত'),
      ),
      (
      '04',
      _t('Receive Return Payouts', 'মুনাফা গ্রহণ করুন'),
      _t('Track milestone progress in real time and receive scheduled return payouts directly to your wallet.',
          'রিয়েল টাইমে অগ্রগতি দেখুন এবং নির্ধারিত সময়ে সরাসরি মুনাফা গ্রহণ করুন।'),
      '/images/wallet-returns-payout.jpg',
      _t('Automated Returns', 'স্বয়ংক্রিয় রিটার্ন'),
      ),
    ];

    return _Section(
      color: _C.emeraldSoft,
      pattern: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(
            center: true,
            eyebrow: _t('Four simple steps', 'চারটি সহজ ধাপ'),
            title: _t('Your Investment Journey,', 'আপনার বিনিয়োগ যাত্রা,'),
            highlight: _t('Simplified', 'সহজ করে'),
            description: _t(
                'From registration to scheduled profit payouts directly into your bank or mobile wallet.',
                'রেজিস্ট্রেশন থেকে শুরু করে সরাসরি ব্যাংক বা মোবাইল ওয়ালেটে নির্ধারিত মুনাফা পর্যন্ত।'),
          ),
          const SizedBox(height: 28),
          for (int i = 0; i < steps.length; i++) ...[
            _Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 150,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Stack(fit: StackFit.expand, children: [
                          _NetImage(_asset(steps[i].$4)),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Color(0xB306140F), Colors.transparent],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: _Pill('STEP ${steps[i].$1}',
                                fg: Colors.white,
                                bg: Colors.black.withValues(alpha: 0.6),
                                border: Colors.white24),
                          ),
                          Positioned(
                            left: 10,
                            bottom: 10,
                            child: _Pill(steps[i].$5.toUpperCase(),
                                fg: _C.goldLight,
                                bg: _C.emeraldDeep.withValues(alpha: 0.85),
                                border: _C.gold.withValues(alpha: 0.35)),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(steps[i].$2,
                        style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w600,
                            color: _C.ink)),
                    const SizedBox(height: 6),
                    Text(steps[i].$3,
                        style: const TextStyle(
                            fontSize: 13, height: 1.5, color: _C.muted)),
                  ],
                ),
              ),
            ),
            if (i < steps.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Center(
                    child: Icon(Icons.keyboard_arrow_down,
                        color: _C.gold, size: 24)),
              ),
          ],
          const SizedBox(height: 22),
          _Btn(_t('Explore Detailed Investment Guide', 'বিস্তারিত বিনিয়োগ গাইড দেখুন'),
              onTap: onAction,
              style: _BtnStyle.outline,
              icon: Icons.arrow_forward),
        ],
      ),
    );
  }
}

// ============================================================================
//  06 OUR PORTFOLIO (business group cards)
// ============================================================================

// Website er BusinessGroupCard er cover / sector / ticker
const Map<String, String> _portfolioCover = {
  'MARINERS': '/4.png',
  'MOHS': '/2.png',
  'MARINOZZ': '/3.png',
};
const Map<String, List<String>> _portfolioMeta = {
  'MARINERS': ['Maritime Logistics & Cold Chain', 'সামুদ্রিক লজিস্টিকস ও কোল্ড চেইন', 'MARINERS-GRP'],
  'MOHS': ['Real Estate & Commercial Holdings', 'রিয়েল এস্টেট ও বাণিজ্যিক সম্পদ', 'MOHS-CORP'],
  'MARINOZZ': ['Hospitality & Public Enterprise', 'আতিথেয়তা ও জনসেবা উদ্যোগ', 'MARINOZZ-PLC'],
};

class _PortfolioSection extends StatelessWidget {
  final List<Map> groups;
  final bool loading;
  final VoidCallback onAction;
  const _PortfolioSection(
      {required this.groups, required this.loading, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return _Section(
      color: _C.ivory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(
            eyebrow: _t('Our portfolio', 'আমাদের পোর্টফোলিও'),
            title: _t('Explore the Businesses', 'সুযোগগুলোর পেছনের'),
            highlight: _t('Behind the Opportunities', 'ব্যবসাগুলো দেখুন'),
            description: _t(
                'Partner with vetted corporate enterprises and multi-sector conglomerates driving verified economic growth across Bangladesh.',
                'বাংলাদেশজুড়ে যাচাইকৃত অর্থনৈতিক প্রবৃদ্ধি চালিত করা কর্পোরেট প্রতিষ্ঠান ও বহুখাতের গ্রুপের অংশীদার হন।'),
          ),
          const SizedBox(height: 26),
          if (loading && groups.isEmpty)
            const _LoadingBox()
          else if (groups.isEmpty)
            _EmptyBox(_t('Corporate business groups will appear here.',
                'কর্পোরেট ব্যবসায়িক গ্রুপগুলো এখানে দেখা যাবে।'))
          else
            for (final g in groups) ...[
              _BusinessGroupCard(group: g, onTap: onAction),
              const SizedBox(height: 18),
            ],
          const SizedBox(height: 8),
          _Btn(_t('View All Business Groups', 'সব ব্যবসায়িক গ্রুপ দেখুন'),
              onTap: onAction,
              style: _BtnStyle.outline,
              icon: Icons.chevron_right),
        ],
      ),
    );
  }
}

class _BusinessGroupCard extends StatelessWidget {
  final Map group;
  final VoidCallback onTap;
  const _BusinessGroupCard({required this.group, required this.onTap});

  static const _tierLabels = {
    'INVESTOR': ['Investor', 'বিনিয়োগকারী'],
    'SHAREHOLDER': ['Shareholder', 'শেয়ারহোল্ডার'],
    'DIRECTORSHIP': ['Directorship', 'ডিরেক্টরশিপ'],
    'PLOT_BOOKING': ['Plot Booking', 'প্লট বুকিং'],
    'LAND_SHARE': ['Land Share', 'জমির শেয়ার'],
  };
  static const _tierColors = {
    'INVESTOR': Color(0xFF1F8A5B),
    'SHAREHOLDER': _C.lapis,
    'DIRECTORSHIP': _C.goldDeep,
    'PLOT_BOOKING': Color(0xFF6B4A8A),
    'LAND_SHARE': _C.turquoise,
  };

  @override
  Widget build(BuildContext context) {
    final slug = _str(group, ['slug']).toUpperCase();
    final name = _str(group, ['name']);
    final desc = _str(group, ['description', 'tagline']);
    final entities = _list(group['entities']);
    final tiers = <Map>[for (final e in entities) ..._list(e['tiers'])];
    final types = <String>{
      for (final t in tiers) _str(t, ['type'])
    }..remove('');

    // Est. Return = tier gulor moddhe sobcheye beshi expected return
    double maxRet = 0;
    double? minEntry;
    final durations = <double>[];
    for (final t in tiers) {
      final r = _pct(_num(t, ['expectedReturnPct', 'returnPct', 'expectedReturn']));
      if (r > maxRet) maxRet = r;
      final m = _num(t, ['minAmountBdt', 'minAmount']);
      if (m > 0 && (minEntry == null || m < minEntry)) minEntry = m;
      final d = _num(t, ['durationMonths']);
      if (d > 0) durations.add(d);
    }
    String tenure = _t('Flexible', 'নমনীয়');
    if (durations.isNotEmpty) {
      durations.sort();
      final a = durations.first.toInt(), b = durations.last.toInt();
      tenure = a == b
          ? '$a ${_t('Mo.', 'মাস')}'
          : '$a–$b ${_t('Mo.', 'মাস')}';
    }

    final meta = _portfolioMeta[slug];
    final cover = _imageUrl(_pick(group, ['coverUrl', 'coverImageUrl'])) ??
        _asset(_portfolioCover[slug] ?? '/2.png');

    return _Card(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            child: Stack(fit: StackFit.expand, children: [
              _NetImage(cover, placeholderIcon: Icons.apartment_outlined),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xF206140F), Color(0x8806140F), Color(0x55000000)],
                  ),
                ),
              ),
              Positioned(
                top: 14,
                left: 14,
                right: 14,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _Pill(meta?[2] ?? '$slug-GRP',
                        fg: Colors.white,
                        bg: Colors.black.withValues(alpha: 0.6),
                        border: Colors.white24,
                        dot: true),
                    _Pill(_t('Vetted Conglomerate', 'যাচাইকৃত গ্রুপ'),
                        fg: Colors.white,
                        bg: Colors.black.withValues(alpha: 0.6),
                        border: Colors.white24,
                        icon: Icons.verified_user_outlined),
                  ],
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _C.night.withValues(alpha: 0.9),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.trending_up, color: _C.goldLight),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            (meta == null
                                ? _t('Institutional Conglomerate', 'প্রাতিষ্ঠানিক গ্রুপ')
                                : _t(meta[0], meta[1]))
                                .toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _C.goldLight,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2)),
                        const SizedBox(height: 2),
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w400)),
                      ],
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (desc.isNotEmpty)
                  Text(desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, height: 1.5, color: _C.muted)),
                if (entities.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    const Icon(Icons.apartment_outlined,
                        size: 13, color: _C.emerald),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                          _t('OPERATING SUBSIDIARIES', 'পরিচালিত প্রতিষ্ঠান'),
                          style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: _C.muted)),
                    ),
                    Text('${entities.length} ${_t('Units', 'টি')}',
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _C.ink)),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in entities)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: _C.ivory,
                            border: Border.all(color: _C.line),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(_str(e, ['name']),
                              style: const TextStyle(
                                  fontSize: 11.5, color: _C.ink)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _C.ivory,
                    border: Border.all(color: _C.line),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: IntrinsicHeight(
                    child: Row(children: [
                      _kpi(_t('EST. RETURN', 'আনুমানিক রিটার্ন'),
                          maxRet > 0 ? '${_pctText(maxRet)}%' : '—',
                          const Color(0xFF1F8A5B)),
                      const VerticalDivider(width: 1, color: _C.line),
                      _kpi(_t('MIN. ENTRY', 'সর্বনিম্ন'),
                          minEntry != null ? _bdt(minEntry) : '—', _C.ink),
                      const VerticalDivider(width: 1, color: _C.line),
                      _kpi(_t('TENURE', 'মেয়াদ'), tenure, _C.ink),
                    ]),
                  ),
                ),
                if (types.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                      _t('AVAILABLE ALLOCATION TIERS (${tiers.length} options)',
                          'উপলব্ধ বিনিয়োগ স্তর (${tiers.length}টি)'),
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                          color: _C.muted)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final type in types)
                        _Pill(
                          _tierLabels[type] != null
                              ? _t(_tierLabels[type]![0], _tierLabels[type]![1])
                              : _categoryLabel(type),
                          fg: _tierColors[type] ?? _C.muted,
                          bg: (_tierColors[type] ?? _C.muted).withValues(alpha: 0.08),
                          border:
                          (_tierColors[type] ?? _C.muted).withValues(alpha: 0.3),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Container(height: 1, color: _C.line),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_t('Explore Group Portfolio', 'গ্রুপ পোর্টফোলিও দেখুন'),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _C.ink)),
                        const SizedBox(height: 2),
                        Text(
                            _t('Direct institutional contracts',
                                'সরাসরি প্রাতিষ্ঠানিক চুক্তি'),
                            style: const TextStyle(
                                fontSize: 11.5, color: _C.muted)),
                      ],
                    ),
                  ),
                  Container(
                    width: 38,
                    height: 38,
                    color: _C.emerald,
                    child: const Icon(Icons.arrow_forward,
                        color: Colors.white, size: 18),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, Color color) => Expanded(
    child: Column(children: [
      Text(label,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: _C.muted)),
      const SizedBox(height: 4),
      Text(value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 15.5, fontWeight: FontWeight.w700, color: color)),
    ]),
  );
}

// ============================================================================
//  07 TRANSPARENCY / SECURITY (dark)
// ============================================================================
class _SecuritySection extends StatelessWidget {
  final VoidCallback onAction;
  const _SecuritySection({required this.onAction});

  @override
  Widget build(BuildContext context) {
    final pillars = [
      (
      Icons.lock_outline,
      _t('Double-Entry Ledger Immutability', 'ডাবল-এন্ট্রি লেজারের অপরিবর্তনীয়তা'),
      _t('Every transaction is recorded with mathematical debit-credit balance checks, preventing unilateral modifications or phantom balances.',
          'প্রতিটি লেনদেন ডেবিট-ক্রেডিট মিলিয়ে রেকর্ড হয়, তাই একতরফা পরিবর্তন বা ভুয়া ব্যালান্স সম্ভব নয়।'),
      ),
      (
      Icons.task_outlined,
      _t('Legally Binding Digital Agreements', 'আইনত বাধ্যতামূলক ডিজিটাল চুক্তি'),
      _t('Every allocation generates a timestamped digital contract executed under the Contract Act of Bangladesh, establishing direct legal rights.',
          'প্রতিটি বিনিয়োগে বাংলাদেশের চুক্তি আইনের অধীনে সময়সহ ডিজিটাল চুক্তি তৈরি হয়, যা সরাসরি আইনি অধিকার দেয়।'),
      ),
      (
      Icons.shield_outlined,
      _t('Escrow Segregation Principle', 'এসক্রো পৃথকীকরণ নীতি'),
      _t("Capital contributed by co-investors is segregated by project and held strictly separated from Biniyog Club's corporate operations.",
          'সহ-বিনিয়োগকারীদের অর্থ প্রকল্প অনুযায়ী আলাদা রাখা হয় এবং বিনিয়োগ ক্লাবের নিজস্ব কার্যক্রম থেকে সম্পূর্ণ পৃথক থাকে।'),
      ),
      (
      Icons.check_circle_outline,
      _t('Finance Specialist Multi-Check', 'ফাইন্যান্স বিশেষজ্ঞের বহু-যাচাই'),
      _t('Incoming bank wires and mobile financial service payments are manually inspected and approved by finance officers before allocation.',
          'ব্যাংক ও মোবাইল ব্যাংকিংয়ের প্রতিটি পেমেন্ট বরাদ্দের আগে ফাইন্যান্স অফিসার নিজে যাচাই করে অনুমোদন দেন।'),
      ),
      (
      Icons.how_to_reg_outlined,
      _t('Mandatory KYC Identity Screening', 'বাধ্যতামূলক KYC পরিচয় যাচাই'),
      _t('All co-investors submit verified National Identity (NID) or Passport records, safeguarding the integrity of the collective ecosystem.',
          'সকল সহ-বিনিয়োগকারী যাচাইকৃত NID বা পাসপোর্ট তথ্য দেন, যা পুরো ব্যবস্থার নিরাপত্তা রক্ষা করে।'),
      ),
      (
      Icons.dns_outlined,
      _t('Data Confidentiality & Privacy', 'তথ্যের গোপনীয়তা'),
      _t('Sensitive identification records, bank statements, and tax data are encrypted and accessible only to authorized compliance personnel.',
          'পরিচয়পত্র, ব্যাংক স্টেটমেন্ট ও করের তথ্য এনক্রিপ্ট করা থাকে এবং শুধু অনুমোদিত কর্মীরাই দেখতে পারেন।'),
      ),
    ];

    final rows = [
      (
      _t('Ledger Immutability Guarantee', 'লেজার অপরিবর্তনীয়তার নিশ্চয়তা'),
      _t('Every deposit and payout is audited via double-entry accounting',
          'প্রতিটি জমা ও পরিশোধ ডাবল-এন্ট্রি হিসাবে অডিট হয়'),
      '100%',
      ),
      (
      _t('Contract Act 1872 Alignment', 'চুক্তি আইন ১৮৭২ অনুযায়ী'),
      _t('Legally recognized deeds enforceable in Bangladeshi courts',
          'বাংলাদেশের আদালতে কার্যকর স্বীকৃত দলিল'),
      _t('Legal', 'আইনি'),
      ),
      (
      _t('Segregated Escrow Allocation', 'পৃথক এসক্রো বরাদ্দ'),
      _t('Project capital isolated from operational accounts',
          'প্রকল্পের অর্থ পরিচালন হিসাব থেকে আলাদা'),
      _t('Isolated', 'পৃথক'),
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_C.emeraldDeep, _C.night, Color(0xFF071A22)],
        ),
      ),
      child: Stack(children: [
        _Pattern(color: _C.gold.withValues(alpha: 0.06), cell: 56),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 52, 16, 52),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionHeading(
                dark: true,
                eyebrow: _t('Transparency', 'স্বচ্ছতা'),
                title: _t('Clarity, Accountability', 'স্পষ্টতা, জবাবদিহিতা'),
                highlight: _t('& Informed Decisions', 'ও সচেতন সিদ্ধান্ত'),
                description: _t(
                    'Bangladeshi co-investors deserve uncompromising rigor. Biniyog Club pairs ledger precision with enforceable legal contracts to safeguard your capital at every step.',
                    'বাংলাদেশি সহ-বিনিয়োগকারীদের প্রাপ্য আপসহীন নির্ভুলতা। বিনিয়োগ ক্লাব নির্ভুল লেজার ও কার্যকর আইনি চুক্তি দিয়ে প্রতিটি ধাপে আপনার মূলধন সুরক্ষিত রাখে।'),
              ),
              const SizedBox(height: 26),
              for (final p in pillars) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                    borderRadius: BorderRadius.circular(_radius),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        color: _C.gold.withValues(alpha: 0.18),
                        child: Icon(p.$1, color: _C.goldLight, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.$2,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3)),
                            const SizedBox(height: 5),
                            Text(p.$3,
                                style: const TextStyle(
                                    color: Color(0xFFD5DDD9),
                                    fontSize: 12.5,
                                    height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 14),
              _Btn(_t('Our Due Diligence Approach', 'আমাদের যাচাই পদ্ধতি'),
                  onTap: onAction, style: _BtnStyle.gold, icon: Icons.chevron_right),
              const SizedBox(height: 10),
              _Btn(_t('Security & Compliance FAQ', 'নিরাপত্তা ও কমপ্লায়েন্স প্রশ্নোত্তর'),
                  onTap: onAction, style: _BtnStyle.ghostDark),
              const SizedBox(height: 30),
              // ── Trust & Security Framework card ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF13201B), _C.night, Color(0xFF06150F)],
                  ),
                  border: Border.all(color: _C.gold.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(_radius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _C.gold.withValues(alpha: 0.18),
                          border: Border.all(color: _C.gold.withValues(alpha: 0.35)),
                        ),
                        child: const Icon(Icons.shield_outlined,
                            color: _C.goldLight),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                _t('Trust & Security Framework',
                                    'আস্থা ও নিরাপত্তা কাঠামো'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Text(
                                _t('Multi-Layer Audit Active',
                                    'বহুস্তরের অডিট চালু'),
                                style: const TextStyle(
                                    color: _C.goldLight,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Container(height: 1, color: Colors.white12),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 170,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Stack(fit: StackFit.expand, children: [
                          _NetImage(_asset('/images/contract-security.jpg'),
                              placeholderIcon: Icons.description_outlined),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Color(0xF006140F), Colors.transparent],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 10,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: _Pill(
                                      _t('Stamped Legal Agreement',
                                          'স্ট্যাম্পকৃত আইনি চুক্তি'),
                                      fg: Colors.white,
                                      bg: Colors.black.withValues(alpha: 0.6),
                                      border: Colors.white24),
                                ),
                                const SizedBox(width: 6),
                                _Pill(_t('Contract Act 1872', 'চুক্তি আইন ১৮৭২'),
                                    fg: _C.goldLight,
                                    bg: _C.emeraldDeep.withValues(alpha: 0.85),
                                    border: _C.gold.withValues(alpha: 0.35)),
                              ],
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final r in rows) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          border:
                          Border.all(color: Colors.white.withValues(alpha: 0.10)),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.$1,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 3),
                                Text(r.$2,
                                    style: const TextStyle(
                                        color: Color(0xFFC3CDC8),
                                        fontSize: 11.5,
                                        height: 1.4)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          _Pill(r.$3,
                              fg: _C.goldLight,
                              bg: _C.emeraldDeep.withValues(alpha: 0.7),
                              border: _C.gold.withValues(alpha: 0.35)),
                        ]),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 4),
                    _DarkCheckBar(
                      text: _t(
                          'Multi-stage due diligence conducted prior to every project listing',
                          'প্রতিটি প্রকল্প তালিকাভুক্তির আগে বহুধাপের যাচাই সম্পন্ন হয়'),
                      trailing: _t('Compliant', 'অনুবর্তী'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ============================================================================
//  08 REGISTRATION / FINAL CTA (dark)
// ============================================================================
class _FinalCtaSection extends StatelessWidget {
  final VoidCallback onAction;
  final VoidCallback onRegister;
  final int totalInvestors;
  const _FinalCtaSection(
      {required this.onAction, required this.onRegister, this.totalInvestors = 0});

  @override
  Widget build(BuildContext context) {
    final assurances = [
      (Icons.check_circle_outline, _t('Start from ৳5,000', '৳৫,০০০ থেকে শুরু')),
      (Icons.verified_user_outlined,
      _t('Legally Enforceable Contracts', 'আইনত কার্যকর চুক্তি')),
      (Icons.check_circle_outline,
      _t('Direct Bank & MFS Payouts', 'সরাসরি ব্যাংক ও মোবাইল ব্যাংকিংয়ে মুনাফা')),
    ];

    return Container(
      color: const Color(0xFF030906),
      child: Stack(children: [
        Positioned.fill(
          child: Opacity(
            opacity: 0.25,
            child: _NetImage(_asset('/images/smart-agro-farm.jpg')),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xFF030906), Color(0xE6030906), Color(0xCC030906)],
              ),
            ),
          ),
        ),
        _Pattern(color: _C.gold.withValues(alpha: 0.06), cell: 56),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 56, 20, 56),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _C.emeraldDeep.withValues(alpha: 0.85),
                  border: Border.all(color: _C.gold.withValues(alpha: 0.35)),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          color: _C.goldLight, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                        totalInvestors > 0
                            ? _t('Join ${_count(totalInvestors)} verified investors earning scheduled returns',
                            '${_count(totalInvestors)} জন যাচাইকৃত বিনিয়োগকারীর সাথে যুক্ত হোন')
                            : _t('Now accepting verified investors',
                            'এখন যাচাইকৃত বিনিয়োগকারী নেওয়া হচ্ছে'),
                        style: const TextStyle(
                            color: _C.goldLight,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500)),
                  ),
                ]),
              ),
              const SizedBox(height: 22),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: _t('Join the Biniyog Club\n', 'যুক্ত হোন বিনিয়োগ ক্লাব\n'),
                      style: const TextStyle(fontWeight: FontWeight.w300)),
                  TextSpan(
                    text: _t('Ecosystem', 'ইকোসিস্টেমে'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: _C.goldLight),
                  ),
                ]),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    height: 1.2,
                    letterSpacing: -0.4),
              ),
              const SizedBox(height: 18),
              Text(
                _t(
                    'Create your investor account in under 2 minutes. Gain direct access to admin-vetted business groups, institutional transparency, and legally protected digital contracts.',
                    '২ মিনিটেরও কম সময়ে বিনিয়োগকারী অ্যাকাউন্ট খুলুন। যাচাইকৃত ব্যবসায়িক গ্রুপ, প্রাতিষ্ঠানিক স্বচ্ছতা ও আইনিভাবে সুরক্ষিত ডিজিটাল চুক্তিতে সরাসরি প্রবেশাধিকার পান।'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFFC9D3CE), fontSize: 15, height: 1.6),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 10,
                children: [
                  for (final a in assurances)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(a.$1, size: 16, color: _C.goldLight),
                      const SizedBox(width: 6),
                      Text(a.$2,
                          style: const TextStyle(
                              color: Color(0xFFD5DDD9), fontSize: 12.5)),
                    ]),
                ],
              ),
              const SizedBox(height: 30),
              _Btn(_t('Create Free Investor Account', 'বিনামূল্যে অ্যাকাউন্ট খুলুন'),
                  onTap: onRegister, style: _BtnStyle.gold, icon: Icons.chevron_right),
              const SizedBox(height: 12),
              _Btn(_t('Talk to Our Advisory Team', 'আমাদের পরামর্শক টিমের সাথে কথা বলুন'),
                  onTap: onAction, style: _BtnStyle.ghostDark),
            ],
          ),
        ),
      ]),
    );
  }
}

// ============================================================================
//  FOOTER
// ============================================================================
class _Footer extends StatelessWidget {
  final VoidCallback onAction;
  final VoidCallback onRegister;
  const _Footer({required this.onAction, required this.onRegister});

  void _copy(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_t('Copied: $value', 'কপি হয়েছে: $value')),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  static String get _createAccountLabel => _t('Create Account', 'অ্যাকাউন্ট খুলুন');

  @override
  Widget build(BuildContext context) {
    final columns = [
      (
      _t('Platform', 'প্ল্যাটফর্ম'),
      [
        _t('Business Groups', 'ব্যবসায়িক গ্রুপ'),
        _t('Browse Projects', 'প্রকল্প দেখুন'),
        _t('How It Works', 'কীভাবে কাজ করে'),
        _createAccountLabel,
      ],
      ),
      (
      _t('Company', 'প্রতিষ্ঠান'),
      [
        _t('Project Updates', 'প্রকল্পের আপডেট'),
        _t('About Us', 'আমাদের সম্পর্কে'),
        _t('Frequently Asked', 'সাধারণ প্রশ্ন'),
        _t('Investor Relations', 'বিনিয়োগকারী সম্পর্ক'),
      ],
      ),
      (
      _t('Legal', 'আইনি'),
      [
        _t('Privacy Policy', 'গোপনীয়তা নীতি'),
        _t('Terms of Service', 'সেবার শর্তাবলি'),
        _t('Risk Disclosures', 'ঝুঁকির তথ্য'),
        _t('Compliance & KYC', 'কমপ্লায়েন্স ও KYC'),
      ],
      ),
    ];

    const linkStyle = TextStyle(color: Color(0xFFB9C4BF), fontSize: 13);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF091511), Color(0xFF06100D), Color(0xFF030806)],
        ),
        border: Border(top: BorderSide(color: Color(0x6614532D))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Image.asset(
              'assets/images/logo_full.png',
              height: 34,
              errorBuilder: (_, __, ___) => const Text('Biniyog Club',
                  style: TextStyle(
                      color: _C.emerald,
                      fontWeight: FontWeight.w700,
                      fontSize: 18)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _t(
                'Empowering co-investors across Bangladesh to fund verified business groups and projects with complete legal security and radical transparency.',
                'সম্পূর্ণ আইনি নিরাপত্তা ও পূর্ণ স্বচ্ছতার সাথে যাচাইকৃত ব্যবসায়িক গ্রুপ ও প্রকল্পে বিনিয়োগে সারা বাংলাদেশের সহ-বিনিয়োগকারীদের পাশে।'),
            style: const TextStyle(
                color: Color(0xFF9AA7A1), fontSize: 13.5, height: 1.6),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _C.emeraldDeep.withValues(alpha: 0.7),
              border: Border.all(color: _C.gold.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.verified_user_outlined,
                  size: 14, color: _C.goldLight),
              const SizedBox(width: 6),
              Text(
                  _t('Immutable Ledger & Digital Contracts',
                      'অপরিবর্তনীয় লেজার ও ডিজিটাল চুক্তি'),
                  style: const TextStyle(color: _C.goldLight, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: [
              for (final col in columns)
                SizedBox(
                  width: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(col.$1.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6)),
                      const SizedBox(height: 12),
                      for (final link in col.$2)
                        InkWell(
                          onTap: link == _createAccountLabel ? onRegister : onAction,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(link, style: linkStyle),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
          Text(_t('CONTACT', 'যোগাযোগ'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6)),
          const SizedBox(height: 12),
          _contactRow(context, Icons.place_outlined,
              'MG SAM Center, 12 Mohakhali C/A, Dhaka-1212, Bangladesh'),
          _contactRow(context, Icons.phone_outlined, '+8801335149033'),
          _contactRow(context, Icons.mail_outline, 'info@biniyogclub.com'),
          const SizedBox(height: 26),
          Container(height: 1, color: Colors.white12),
          const SizedBox(height: 18),
          Text(
            _t(
                '© ${DateTime.now().year} Biniyog Club Ltd. All rights reserved. Registered in Bangladesh.',
                '© ${DateTime.now().year} বিনিয়োগ ক্লাব লিমিটেড। সর্বস্বত্ব সংরক্ষিত। বাংলাদেশে নিবন্ধিত।'),
            style: const TextStyle(color: Color(0xFF8A9690), fontSize: 11.5),
          ),
          const SizedBox(height: 6),
          Text(
            _t('Investment carries commercial risk. Past payouts do not guarantee future returns.',
                'বিনিয়োগে বাণিজ্যিক ঝুঁকি রয়েছে। অতীতের মুনাফা ভবিষ্যতের রিটার্নের নিশ্চয়তা দেয় না।'),
            style: const TextStyle(
                color: Color(0xFF8A9690), fontSize: 11.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _contactRow(BuildContext context, IconData icon, String value) =>
      InkWell(
        onTap: () => _copy(context, value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: _C.goldLight),
              const SizedBox(width: 10),
              Expanded(
                child: Text(value,
                    style: const TextStyle(
                        color: Color(0xFFCBD5D1), fontSize: 13, height: 1.4)),
              ),
            ],
          ),
        ),
      );
}