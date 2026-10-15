import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import 'kyc_submit_page.dart';

class KycPage extends StatefulWidget {
  const KycPage({super.key});

  @override
  State<KycPage> createState() => _KycPageState();
}

class _KycPageState extends State<KycPage> {
  // ─── Palette ───
  static const Color emerald = Color(0xFF0E4A37);
  static const Color emeraldDeep = Color(0xFF0A3327);
  static const Color emeraldSoft = Color(0xFFE3F0E9);
  static const Color gold = Color(0xFFB8935A);
  static const Color goldLight = Color(0xFFD9BE8C);
  static const Color goldDeep = Color(0xFF8A6A3A);
  static const Color goldSoft = Color(0xFFF6EEDF);
  static const Color lapis = Color(0xFF26437A);
  static const Color lapisSoft = Color(0xFFE5EAF4);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);
  static const Color danger = Color(0xFFB4413A);
  static const Color dangerSoft = Color(0xFFFBEAE8);

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  bool _isLoading = true;
  bool _needsLogin = false;
  bool _loadFailed = false;

  /// DB theke ja ashe — kono banano nam / NID / jayga na
  Map<String, dynamic> _kyc = {};
  String _status = 'NOT_STARTED';

  @override
  void initState() {
    super.initState();
    _loadKycData();
  }

  Future<void> _loadKycData() async {
    if (mounted) setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';

    if (userId.isEmpty) {
      if (mounted) {
        setState(() {
          _needsLogin = true;
          _isLoading = false;
        });
      }
      return;
    }

    final data = await DatabaseService.getKycStatus(userId);
    if (!mounted) return;

    setState(() {
      // Net na thakle "NOT_STARTED" dhore nibo na — tahole user bhule abar jama dito
      _loadFailed = data['error'] == 'network';
      _kyc = _loadFailed ? {} : data;
      _status = (data['status']?.toString() ?? 'NOT_STARTED').toUpperCase();
      _needsLogin = false;
      _isLoading = false;
    });
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  String _s(String k) => _kyc[k]?.toString() ?? '';

  bool get _isVerified => _status == 'VERIFIED' || _status == 'APPROVED';
  bool get _isReview => _status == 'SUBMITTED' || _status == 'UNDER_REVIEW' || _status == 'PENDING';
  bool get _isRejected => _status == 'REJECTED' || _status == 'RESUBMISSION_REQUIRED';
  bool get _canSubmit => _status == 'NOT_STARTED' || _isRejected;

  String _fmtDate(String raw) {
    if (raw.trim().isEmpty) return '';
    var t = raw.trim().replaceFirst(' ', 'T');
    if (t.contains('T') && !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(t)) t = '${t}Z';
    final d = DateTime.tryParse(t)?.toLocal();
    if (d == null) return '';
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// Shudhu shesh 4 ta — puro NID screen e dekhabo na
  String _mask(String v) {
    final t = v.replaceAll(' ', '');
    if (t.isEmpty) return '';
    if (t.length <= 4) return t;
    return '•••• ${t.substring(t.length - 4)}';
  }

  String _docTypeText(String t) {
    switch (t) {
      case 'NATIONAL_ID':
        return LanguageService.tr('National ID (NID)', 'জাতীয় পরিচয়পত্র (NID)');
      case 'PASSPORT':
        return LanguageService.tr('Passport', 'পাসপোর্ট');
      case 'DRIVING_LICENSE':
        return LanguageService.tr('Driving License', 'ড্রাইভিং লাইসেন্স');
      default:
        return t;
    }
  }

  String _docFileText(String t) {
    final passport = _s('documentType') == 'PASSPORT';
    switch (t) {
      case 'NATIONAL_ID_FRONT':
        return passport
            ? LanguageService.tr('Passport photo page', 'পাসপোর্টের ছবির পাতা')
            : LanguageService.tr('Your NID (front)', 'আপনার NID (সামনে)');
      case 'NATIONAL_ID_BACK':
        return LanguageService.tr('Your NID (back)', 'আপনার NID (পেছনে)');
      case 'NOMINEE_NID_FRONT':
        return LanguageService.tr('Nominee NID (front)', 'নমিনীর NID (সামনে)');
      case 'NOMINEE_NID_BACK':
        return LanguageService.tr('Nominee NID (back)', 'নমিনীর NID (পেছনে)');
      default:
        final w = t.replaceAll('_', ' ').toLowerCase();
        return w.isEmpty ? '—' : w[0].toUpperCase() + w.substring(1);
    }
  }

  Future<void> _openSubmit() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => KycSubmitPage(existing: _kyc)),
    );
    if (result == true && mounted) _loadKycData();
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
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
              LanguageService.tr('KYC Verification', 'কেওয়াইসি ভেরিফিকেশন'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          body: _isLoading
              ? const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4),
            ),
          )
              : _needsLogin
              ? _buildMessage(
            Icons.lock_outline_rounded,
            LanguageService.tr('Please log in to continue', 'চালিয়ে যেতে লগইন করুন'),
            null,
            LanguageService.tr('Log in', 'লগইন'),
                () async {
              await AuthService.logout();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginPage()),
                    (route) => false,
              );
            },
          )
              : _loadFailed
              ? _buildMessage(
            Icons.wifi_off_rounded,
            LanguageService.tr('Could not load your KYC status', 'কেওয়াইসি স্ট্যাটাস লোড করা যায়নি'),
            LanguageService.tr('Please check your internet connection.', 'ইন্টারনেট সংযোগ চেক করুন।'),
            LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
            _loadKycData,
          )
              : RefreshIndicator(
            onRefresh: _loadKycData,
            color: emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                _buildStatusHero(),
                if (_canSubmit) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _openSubmit,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: Text(
                        _status == 'NOT_STARTED'
                            ? LanguageService.tr('Start Verification', 'ভেরিফিকেশন শুরু করুন')
                            : LanguageService.tr('Fix & Resubmit', 'ঠিক করে আবার জমা দিন'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: emerald,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _buildProgressSteps(),
                if (_status != 'NOT_STARTED') ...[
                  const SizedBox(height: 16),
                  _buildSubmittedInfo(),
                  const SizedBox(height: 16),
                  _buildDocuments(),
                ] else ...[
                  const SizedBox(height: 16),
                  _buildWhatYouNeed(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Status hero ──────────────────────────────────────────
  Widget _buildStatusHero() {
    final IconData icon;
    final String title;
    final String desc;
    final Color accent;

    if (_isVerified) {
      icon = Icons.verified_rounded;
      accent = goldLight;
      title = LanguageService.tr('KYC Verified', 'কেওয়াইসি ভেরিফাইড');
      desc = LanguageService.tr('Your identity is verified. You can invest in any open project.',
          'আপনার পরিচয় ভেরিফাইড। আপনি যেকোনো খোলা প্রজেক্টে বিনিয়োগ করতে পারবেন।');
    } else if (_isReview) {
      icon = Icons.hourglass_top_rounded;
      accent = goldLight;
      title = LanguageService.tr('Under Review', 'পর্যালোচনা চলছে');
      desc = LanguageService.tr('We have your documents. Our team is checking them — you will be notified.',
          'আপনার কাগজপত্র পেয়েছি। আমাদের টিম যাচাই করছে — ফলাফল জানানো হবে।');
    } else if (_isRejected) {
      icon = Icons.error_outline_rounded;
      accent = const Color(0xFFF2B8A8);
      title = LanguageService.tr('Needs Correction', 'সংশোধন প্রয়োজন');
      desc = LanguageService.tr('Your submission could not be verified. See the reason below and resubmit.',
          'আপনার তথ্য যাচাই করা যায়নি। নিচের কারণ দেখে আবার জমা দিন।');
    } else {
      icon = Icons.shield_outlined;
      accent = goldLight;
      title = LanguageService.tr('Verification Required', 'ভেরিফিকেশন প্রয়োজন');
      desc = LanguageService.tr('Verify your identity once to start investing on Biniyog Club.',
          'বিনিয়োগ শুরু করতে একবার পরিচয় যাচাই করুন।');
    }

    final note = _kyc['reviewNote']?.toString() ?? '';
    final submitted = _fmtDate(_s('submittedAt'));
    final reviewed = _fmtDate(_s('reviewedAt'));

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF125A43), emeraldDeep, Color(0xFF0B2A3A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _IslamicPatternPainter(color: Colors.white.withAlpha(16), cell: 44)),
            ),
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: gold.withAlpha(80), width: 0.8),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(22),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: accent.withAlpha(120)),
                        ),
                        child: Icon(icon, color: accent, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(desc, style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 12.5, height: 1.45)),
                  if (submitted.isNotEmpty || reviewed.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      [
                        if (submitted.isNotEmpty) LanguageService.tr('Submitted $submitted', 'জমা $submitted'),
                        if (reviewed.isNotEmpty) LanguageService.tr('Reviewed $reviewed', 'যাচাই $reviewed'),
                      ].join(' · '),
                      style: const TextStyle(color: goldLight, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (_isRejected && note.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: dangerSoft, borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        LanguageService.tr('Reason: $note', 'কারণ: $note'),
                        style: const TextStyle(fontSize: 12.5, color: danger, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Steps ────────────────────────────────────────────────
  Widget _buildProgressSteps() {

    final steps = [
      (LanguageService.tr('Submit details & documents', 'তথ্য ও কাগজপত্র জমা'),
      LanguageService.tr('NID / passport, address, nominee, payout account', 'এনআইডি/পাসপোর্ট, ঠিকানা, নমিনী, পেআউট অ্যাকাউন্ট')),
      (LanguageService.tr('Team review', 'টিমের যাচাই'),
      LanguageService.tr('We check your documents', 'আমরা কাগজপত্র যাচাই করি')),
      (LanguageService.tr('Verified', 'ভেরিফাইড'),
      LanguageService.tr('Investing unlocked', 'বিনিয়োগ চালু')),
    ];

    return _card(
      title: LanguageService.tr('How it works', 'যেভাবে হয়'),
      child: Column(
        children: [
          for (int i = 0; i < steps.length; i++)
            Builder(builder: (_) {
              // Step 1: jama hoyeche kina · Step 2: review · Step 3: verified
              final submitted = _status != 'NOT_STARTED';
              final done = i == 0 ? submitted : _isVerified;
              final current = (i == 0 && !submitted) || (i == 1 && _isReview);
              final failed = i == 1 && _isRejected;
              final Color c = failed ? danger : (done ? emerald : (current ? goldDeep : muted));
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: done ? emerald : (failed ? dangerSoft : (current ? goldSoft : ivory)),
                        shape: BoxShape.circle,
                        border: Border.all(color: c.withAlpha(120)),
                      ),
                      child: Icon(
                        done
                            ? Icons.check_rounded
                            : failed
                            ? Icons.close_rounded
                            : current
                            ? Icons.more_horiz_rounded
                            : Icons.circle_outlined,
                        size: 15,
                        color: done ? Colors.white : c,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(steps[i].$1,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: done || current || failed ? ink : muted)),
                          Text(steps[i].$2, style: const TextStyle(fontSize: 11, color: muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ─── Submitted info (gopon tottho mask kora) ──────────────
  Widget _buildSubmittedInfo() {
    final location = [_s('upazila'), _s('district'), _s('division')].where((e) => e.isNotEmpty).join(', ');
    final bank = _s('bankName');
    final acc = _s('bankAccountNumber');
    final mobile = _s('mobileNumber');
    final provider = _s('mobileProvider');

    final rows = <(String, String)>[
      (LanguageService.tr('Full name', 'পূর্ণ নাম'), _s('fullName')),
      (LanguageService.tr('Document', 'পরিচয়পত্র'), _docTypeText(_s('documentType'))),
      (LanguageService.tr('Document no.', 'পরিচয়পত্র নম্বর'), _mask(_s('documentNumber'))),
      (LanguageService.tr('Location', 'অবস্থান'), location),
      (LanguageService.tr('Bank', 'ব্যাংক'), [bank, _mask(acc)].where((e) => e.isNotEmpty).join(' · ')),
      (LanguageService.tr('Mobile banking', 'মোবাইল ব্যাংকিং'),
      mobile.isEmpty ? '' : [provider, _mask(mobile)].where((e) => e.isNotEmpty).join(' · ')),
      (LanguageService.tr('Nominee', 'নমিনী'),
      [_s('nomineeRelation'), _mask(_s('nomineeNid'))].where((e) => e.isNotEmpty).join(' · ')),
    ];

    return _card(
      title: LanguageService.tr('Submitted Information', 'জমা দেওয়া তথ্য'),
      subtitle: LanguageService.tr('Sensitive numbers are partly hidden', 'গোপন নম্বর আংশিক লুকানো'),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 18, color: line),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(rows[i].$1, style: const TextStyle(fontSize: 12, color: muted)),
                ),
                Expanded(
                  child: Text(
                    rows[i].$2.isEmpty ? LanguageService.tr('Not provided', 'দেওয়া হয়নি') : rows[i].$2,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: rows[i].$2.isEmpty ? muted : ink,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── Documents ────────────────────────────────────────────
  Widget _buildDocuments() {
    final docs = ((_kyc['documents'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    final String stateText;
    final Color stateColor;
    if (_isVerified) {
      stateText = LanguageService.tr('Verified', 'ভেরিফাইড');
      stateColor = emerald;
    } else if (_isRejected) {
      stateText = LanguageService.tr('Rejected', 'বাতিল');
      stateColor = danger;
    } else {
      stateText = LanguageService.tr('Under review', 'যাচাই চলছে');
      stateColor = goldDeep;
    }

    return _card(
      title: LanguageService.tr('Uploaded Documents', 'আপলোড করা কাগজপত্র'),
      child: docs.isEmpty
          ? Text(
        LanguageService.tr('No document photos found. Please resubmit with photos.',
            'কোনো ছবি পাওয়া যায়নি। ছবিসহ আবার জমা দিন।'),
        style: const TextStyle(fontSize: 12.5, color: danger),
      )
          : Column(
        children: [
          for (final d in docs)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: lapisSoft, borderRadius: BorderRadius.circular(9)),
                    child: const Icon(Icons.badge_outlined, color: lapis, size: 17),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_docFileText(d['type']?.toString() ?? ''),
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink)),
                        if (_fmtDate(d['createdAt']?.toString() ?? '').isNotEmpty)
                          Text(_fmtDate(d['createdAt']?.toString() ?? ''),
                              style: const TextStyle(fontSize: 10.5, color: muted)),
                      ],
                    ),
                  ),
                  Text(stateText,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: stateColor)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWhatYouNeed() {
    final items = [
      (Icons.badge_outlined, LanguageService.tr('Your NID or passport (photo)', 'আপনার এনআইডি বা পাসপোর্ট (ছবি)')),
      (Icons.home_outlined, LanguageService.tr('Present address', 'বর্তমান ঠিকানা')),
      (Icons.family_restroom_outlined, LanguageService.tr('Nominee NID number & relation', 'নমিনীর এনআইডি নম্বর ও সম্পর্ক')),
      (Icons.account_balance_outlined, LanguageService.tr('Bank or mobile banking account for returns', 'লাভ পাওয়ার জন্য ব্যাংক বা মোবাইল ব্যাংকিং অ্যাকাউন্ট')),
    ];
    return _card(
      title: LanguageService.tr('Keep these ready', 'এগুলো হাতের কাছে রাখুন'),
      child: Column(
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(it.$1, size: 19, color: goldDeep),
                  const SizedBox(width: 12),
                  Expanded(child: Text(it.$2, style: const TextStyle(fontSize: 12.5, color: ink))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // SHARED
  // ═════════════════════════════════════════════════════════
  Widget _card({required String title, String? subtitle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [goldLight, gold])),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: ink)),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 17),
              child: Text(subtitle, style: const TextStyle(fontSize: 11, color: muted)),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildMessage(IconData icon, String title, String? subtitle, String buttonLabel, VoidCallback onTap) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: goldDeep),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: muted)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Islamic geometric pattern (dashboard er moto 8-point star)
// ═══════════════════════════════════════════════════════════
class _IslamicPatternPainter extends CustomPainter {
  final Color color;
  final double cell;

  _IslamicPatternPainter({required this.color, required this.cell});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    final r = cell * 0.34;

    for (double y = 0; y <= size.height + cell; y += cell) {
      final offsetRow = ((y / cell).round() % 2) * cell / 2;
      for (double x = -cell; x <= size.width + cell; x += cell) {
        final c = Offset(x + offsetRow, y);
        for (final start in [0.0, math.pi / 4]) {
          final path = Path();
          for (int i = 0; i < 4; i++) {
            final a = start + i * math.pi / 2;
            final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
            i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
          }
          path.close();
          canvas.drawPath(path, paint);
        }
        canvas.drawCircle(c, r * 0.32, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IslamicPatternPainter old) =>
      old.color != color || old.cell != cell;
}