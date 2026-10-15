import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import '../kyc/kyc_page.dart';
import '../portfolio/investments_page.dart';
import '../settings/legal_web_page.dart';

class ProjectDetailPage extends StatefulWidget {
  final String projectIdOrSlug;

  const ProjectDetailPage({
    super.key,
    required this.projectIdOrSlug,
  });

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  // ─── Palette ───
  static const Color emerald = Color(0xFF0E4A37);
  static const Color emeraldDeep = Color(0xFF0A3327);
  static const Color emeraldSoft = Color(0xFFE3F0E9);
  static const Color gold = Color(0xFFB8935A);
  static const Color goldLight = Color(0xFFD9BE8C);
  static const Color goldDeep = Color(0xFF8A6A3A);
  static const Color goldSoft = Color(0xFFF6EEDF);
  static const Color turquoise = Color(0xFF167A80);
  static const Color lapis = Color(0xFF26437A);
  static const Color lapisSoft = Color(0xFFE5EAF4);
  static const Color terracotta = Color(0xFFA5523A);
  static const Color terracottaSoft = Color(0xFFF7E6DF);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);
  static const Color danger = Color(0xFFB4413A);
  static const Color dangerSoft = Color(0xFFFBEAE8);

  static const Map<String, String> categoryLabels = {
    'REAL_ESTATE': 'Real Estate',
    'TRADE_FINANCE': 'Trade Finance',
    'SME': 'SME Business',
    'TECHNOLOGY': 'Technology',
    'INFRASTRUCTURE': 'Infrastructure',
    'CROP_FARMING': 'Crop Farming',
    'LIVESTOCK': 'Livestock',
    'AQUACULTURE': 'Aquaculture',
    'POULTRY': 'Poultry',
    'DAIRY': 'Dairy',
    'HORTICULTURE': 'Horticulture',
    'AGRO_PROCESSING': 'Agro Processing',
    'OTHER': 'Other',
  };

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  bool _isLoading = true;
  bool _loadFailed = false;
  Map<String, dynamic> _project = {};
  int _selectedBankIndex = 0;
  int _imageIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadProjectDetail();
  }

  Future<void> _loadProjectDetail() async {
    if (mounted) setState(() => _isLoading = true);

    final data = await DatabaseService.getProjectDetail(widget.projectIdOrSlug);

    if (!mounted) return;
    setState(() {
      _loadFailed = data['error'] == 'network';
      _project = _loadFailed ? {} : data;
      _isLoading = false;
    });
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  int _int(dynamic v) => (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  String _str(String key) => _project[key]?.toString() ?? '';

  String _trim(double v, int digits) {
    final s = v.toStringAsFixed(digits);
    return s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
  }

  String _fmtBdt(double amount) {
    if (amount >= 10000000) return '৳${_trim(amount / 10000000, 2)} Cr';
    if (amount >= 100000) return '৳${_trim(amount / 100000, 2)}L';
    if (amount >= 1000) return '৳${_trim(amount / 1000, 1)}K';
    return '৳${amount.toStringAsFixed(0)}';
  }

  String _fmtFull(double amount) {
    final s = amount.toStringAsFixed(0);
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '৳$b';
  }

  String _pctRange(double lo, double hi) {
    String p(double r) => _trim(r * 100, 1);
    if (lo <= 0 && hi <= 0) return '—';
    return lo == hi ? '${p(hi)}%' : '${p(lo)}–${p(hi)}%';
  }

  /// DB er tarikh (UTC, timezone chara) → "Oct 7, 2026"; na thakle ''
  String _fmtDate(dynamic s) {
    final raw = s?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    var t = raw.replaceFirst(' ', 'T');
    if (t.contains('T') && !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(t)) t = '${t}Z';
    final d = DateTime.tryParse(t)?.toLocal();
    if (d == null) return '';
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _statusText(String s) {
    switch (s) {
      case 'FUNDRAISING':
        return LanguageService.tr('Open for Investment', 'বিনিয়োগের জন্য খোলা');
      case 'FUNDED':
        return LanguageService.tr('Fully Funded', 'সম্পূর্ণ অর্থায়িত');
      case 'ACTIVE':
        return LanguageService.tr('Running', 'চলছে');
      case 'HARVESTING':
        return LanguageService.tr('Harvesting', 'ফসল সংগ্রহ');
      case 'COMPLETED':
        return LanguageService.tr('Completed', 'সম্পন্ন');
      default:
        return s;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'FUNDRAISING':
        return emerald;
      case 'FUNDED':
        return lapis;
      case 'ACTIVE':
        return turquoise;
      case 'HARVESTING':
        return goldDeep;
      default:
        return muted;
    }
  }

  String _returnTypeText(String t) {
    switch (t) {
      case 'PROFIT_SHARE':
        return LanguageService.tr('Profit Share', 'মুনাফা ভাগ');
      case 'FIXED_RETURN':
        return LanguageService.tr('Fixed Return', 'নির্দিষ্ট রিটার্ন');
      case '':
        return '—';
      default:
        final w = t.replaceAll('_', ' ').toLowerCase();
        return w[0].toUpperCase() + w.substring(1);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? danger : emerald),
    );
  }

  /// Ekhon invest kora jay kina — status + baki taka
  bool get _canInvest =>
      _str('status') == 'FUNDRAISING' && _num(_project['remainingBdt']) > 0;

  // ═════════════════════════════════════════════════════════
  // INVEST
  // ═════════════════════════════════════════════════════════
  Future<void> _startInvest() async {
    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    if (!mounted) return;

    if (userId.isEmpty) {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
      return;
    }
    _showInvestModal(userId);
  }

  void _showInvestModal(String userId) {
    final minInv = _num(_project['minInvestmentBdt']);
    final maxRaw = _project['maxInvestmentBdt'];
    final maxInv = maxRaw == null ? 0.0 : _num(maxRaw);
    final remaining = _num(_project['remainingBdt']);
    final lo = _num(_project['returnMin']);
    final hi = _num(_project['returnMax']);

    // Sobcheye boro joto invest kora jay
    double cap = remaining;
    if (maxInv > 0 && maxInv < cap) cap = maxInv;

    final amountController = TextEditingController(
        text: minInv > 0 && minInv <= cap ? minInv.toStringAsFixed(0) : '');
    bool submitting = false;
    String? error;
    bool kycNeeded = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final typed = double.tryParse(amountController.text.trim()) ?? 0;

            Future<void> submit() async {
              String? problem;
              if (typed <= 0) {
                problem = LanguageService.tr('Please enter the amount.', 'পরিমাণ লিখুন।');
              } else if (minInv > 0 && typed < minInv) {
                problem = LanguageService.tr('Minimum investment is ${_fmtFull(minInv)}.',
                    'সর্বনিম্ন বিনিয়োগ ${_fmtFull(minInv)}।');
              } else if (maxInv > 0 && typed > maxInv) {
                problem = LanguageService.tr('Maximum investment is ${_fmtFull(maxInv)}.',
                    'সর্বোচ্চ বিনিয়োগ ${_fmtFull(maxInv)}।');
              } else if (typed > remaining) {
                problem = LanguageService.tr('Only ${_fmtFull(remaining)} is left in this project.',
                    'এই প্রজেক্টে মাত্র ${_fmtFull(remaining)} বাকি আছে।');
              }
              if (problem != null) {
                setModalState(() => error = problem);
                return;
              }

              // Ek click e ekta-i investment — button ekhoni bondho
              setModalState(() {
                submitting = true;
                error = null;
                kycNeeded = false;
              });

              final res = await DatabaseService.createInvestment(
                userId: userId,
                projectId: _str('id'),
                amountBdt: typed,
                useWalletBalance: false,
              );

              if (res['success'] != true) {
                final msg = res['message']?.toString() ??
                    LanguageService.tr('Could not create the investment.', 'বিনিয়োগ তৈরি করা যায়নি।');
                setModalState(() {
                  submitting = false;
                  error = msg;
                  kycNeeded = msg.toLowerCase().contains('kyc');
                });
                return;
              }

              // Modal bondho, tarpor PAGE er context diye agai (modal er na)
              if (sheetContext.mounted) Navigator.pop(sheetContext);
              if (!mounted) return;
              _toast(LanguageService.tr(
                  'Investment created! Now send the money and submit your payment proof.',
                  'বিনিয়োগ তৈরি হয়েছে! এখন টাকা পাঠিয়ে পেমেন্ট প্রুফ জমা দিন।'));
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const InvestmentsPage(initialType: 'PROJECT')),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                top: 12,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            LanguageService.tr('Invest in Project', 'প্রজেক্টে বিনিয়োগ'),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ink),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: muted),
                          onPressed: submitting ? null : () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    Text(_str('title'), style: const TextStyle(fontSize: 13, color: muted)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      enabled: !submitting,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setModalState(() => error = null),
                      decoration: InputDecoration(
                        labelText: LanguageService.tr('Investment amount (BDT)', 'বিনিয়োগের পরিমাণ (টাকা)'),
                        labelStyle: const TextStyle(fontSize: 13, color: muted),
                        prefixText: '৳ ',
                        helperText: [
                          if (minInv > 0) LanguageService.tr('Min ${_fmtFull(minInv)}', 'সর্বনিম্ন ${_fmtFull(minInv)}'),
                          LanguageService.tr('Max ${_fmtFull(cap)}', 'সর্বোচ্চ ${_fmtFull(cap)}'),
                        ].join(' · '),
                        helperStyle: const TextStyle(fontSize: 11, color: muted),
                        filled: true,
                        fillColor: ivory,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: emerald, width: 1.4)),
                      ),
                    ),
                    if (typed > 0 && hi > 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: emeraldSoft, borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          LanguageService.tr(
                            'Expected return (${_pctRange(lo, hi)}): ${lo == hi ? _fmtFull(typed * hi) : '${_fmtFull(typed * lo)} – ${_fmtFull(typed * hi)}'}\nEstimate, not guaranteed.',
                            'প্রত্যাশিত লাভ (${_pctRange(lo, hi)}): ${lo == hi ? _fmtFull(typed * hi) : '${_fmtFull(typed * lo)} – ${_fmtFull(typed * hi)}'}\nআনুমানিক, নিশ্চিত নয়।',
                          ),
                          style: const TextStyle(fontSize: 12, color: emerald, fontWeight: FontWeight.w600, height: 1.4),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _stepsNote(),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      _errorBox(error!),
                      if (kycNeeded) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const KycPage()));
                          },
                          icon: const Icon(Icons.verified_user_outlined, size: 16),
                          label: Text(LanguageService.tr('Complete KYC', 'কেওয়াইসি সম্পন্ন করুন')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: emerald,
                            side: const BorderSide(color: emerald),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: submitting ? null : submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: emerald,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: emerald.withAlpha(120),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: submitting
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                        )
                            : Text(
                          LanguageService.tr('Confirm & Create Investment', 'নিশ্চিত করুন ও বিনিয়োগ করুন'),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _stepsNote() {
    final steps = [
      LanguageService.tr('Create the investment here', 'এখানে বিনিয়োগ তৈরি করুন'),
      LanguageService.tr('Send the money to the project bank account', 'প্রজেক্টের ব্যাংক অ্যাকাউন্টে টাকা পাঠান'),
      LanguageService.tr('Submit payment proof from Investments', 'Investments থেকে পেমেন্ট প্রুফ জমা দিন'),
      LanguageService.tr('Admin verifies — your investment becomes active', 'অ্যাডমিন যাচাই করলে বিনিয়োগ চালু হবে'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: goldSoft, shape: BoxShape.circle),
                  child: Text('${i + 1}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: goldDeep)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(steps[i], style: const TextStyle(fontSize: 11.5, color: muted, height: 1.4))),
              ],
            ),
          ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        if (_isLoading) {
          return Scaffold(
            backgroundColor: ivory,
            appBar: _plainAppBar(''),
            body: const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4),
              ),
            ),
          );
        }

        if (_loadFailed || _project.isEmpty) {
          return Scaffold(
            backgroundColor: ivory,
            appBar: _plainAppBar(LanguageService.tr('Project', 'প্রজেক্ট')),
            body: _buildMessage(
              _loadFailed ? Icons.wifi_off_rounded : Icons.search_off_rounded,
              _loadFailed
                  ? LanguageService.tr('Could not load the project', 'প্রজেক্ট লোড করা যায়নি')
                  : LanguageService.tr('Project not found', 'প্রজেক্ট পাওয়া যায়নি'),
              _loadFailed
                  ? LanguageService.tr('Please check your internet connection.', 'ইন্টারনেট সংযোগ চেক করুন।')
                  : LanguageService.tr('It may have been removed or is not public yet.',
                  'এটি সরানো হয়েছে অথবা এখনো প্রকাশিত হয়নি।'),
              _loadFailed,
            ),
          );
        }

        final bankAccounts = ((_project['bankAccounts'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final updates = ((_project['updates'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final risk = _str('riskInfo');
        final description = _str('description');

        return Scaffold(
          backgroundColor: ivory,
          appBar: _plainAppBar(_str('title')),
          bottomNavigationBar: _buildBottomBar(),
          body: RefreshIndicator(
            onRefresh: _loadProjectDetail,
            color: emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _buildGallery(),
                const SizedBox(height: 14),
                _buildHeader(),
                const SizedBox(height: 14),
                _buildFundingCard(),
                const SizedBox(height: 14),
                _buildTermsCard(),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _card(
                    title: LanguageService.tr('About this project', 'প্রজেক্ট সম্পর্কে'),
                    child: Text(description, style: const TextStyle(fontSize: 13, color: ink, height: 1.55)),
                  ),
                ],
                if (risk.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _buildRiskCard(risk),
                ],
                const SizedBox(height: 14),
                _buildTimelineCard(),
                if (updates.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _buildUpdatesCard(updates),
                ],
                if (bankAccounts.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _buildPaymentBankDetails(bankAccounts),
                ],
                const SizedBox(height: 14),
                _buildLearnMore(),
              ],
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _plainAppBar(String title) {
    return AppBar(
      backgroundColor: ivory,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: const IconThemeData(color: ink),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 16),
      ),
    );
  }

  // ─── Gallery ──────────────────────────────────────────────
  Widget _buildGallery() {
    final images = ((_project['imageUrls'] as List?) ?? []).map((e) => e.toString()).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 210,
        child: images.isEmpty
            ? _coverPlaceholder()
            : Stack(
          children: [
            PageView.builder(
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _imageIndex = i),
              itemBuilder: (_, i) => Image.network(
                images[i],
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => _coverPlaceholder(),
              ),
            ),
            if (images.length > 1)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(images.length, (i) {
                    final on = i == _imageIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: on ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: on ? goldLight : Colors.white.withAlpha(150),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder() {
    return Container(
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
            child: CustomPaint(painter: _IslamicPatternPainter(color: Colors.white.withAlpha(18), cell: 44)),
          ),
          const Center(child: Icon(Icons.eco_outlined, color: goldLight, size: 40)),
        ],
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────
  Widget _buildHeader() {
    final status = _str('status');
    final sc = _statusColor(status);
    final cat = _str('category');
    final catLabel = categoryLabels[cat] ?? cat;
    final location = _str('location');
    final group = _str('groupName');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _pill(_statusText(status), sc, sc.withAlpha(24)),
            if (catLabel.isNotEmpty) _pill(catLabel, goldDeep, goldSoft),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _str('title').isEmpty ? '—' : _str('title'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ink, height: 1.25),
        ),
        if (location.isNotEmpty || group.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              if (location.isNotEmpty) _iconText(Icons.location_on_outlined, location),
              if (group.isNotEmpty) _iconText(Icons.business_rounded, group),
            ],
          ),
        ],
      ],
    );
  }

  Widget _iconText(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: goldDeep),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, color: muted)),
      ],
    );
  }

  Widget _pill(String text, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  // ─── Funding ──────────────────────────────────────────────
  Widget _buildFundingCard() {
    final goal = _num(_project['fundingGoalBdt']);
    final funded = _num(_project['fundedAmountBdt']);
    final remaining = _num(_project['remainingBdt']);
    final progress = _num(_project['progress']).clamp(0.0, 1.0);
    final investors = _int(_project['investorsCount']);
    final daysLeft = _int(_project['daysLeft']);
    final showDeadline = _str('status') == 'FUNDRAISING' && _project['hasDeadline'] == true;

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
                  Text(
                    LanguageService.tr('RAISED SO FAR', 'এ পর্যন্ত সংগৃহীত'),
                    style: const TextStyle(
                        color: goldLight, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1.3),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _fmtFull(funded),
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7,
                      backgroundColor: Colors.white.withAlpha(40),
                      valueColor: const AlwaysStoppedAnimation<Color>(goldLight),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    LanguageService.tr(
                        '${(progress * 100).toStringAsFixed(0)}% of ${_fmtBdt(goal)} goal',
                        '${_fmtBdt(goal)} লক্ষ্যের ${(progress * 100).toStringAsFixed(0)}%'),
                    style: TextStyle(color: Colors.white.withAlpha(185), fontSize: 11.5),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _heroStat(LanguageService.tr('Remaining', 'বাকি'), _fmtBdt(remaining))),
                      Container(width: 0.8, height: 30, color: gold.withAlpha(90)),
                      const SizedBox(width: 12),
                      Expanded(child: _heroStat(LanguageService.tr('Investors', 'বিনিয়োগকারী'), '$investors')),
                      if (showDeadline) ...[
                        Container(width: 0.8, height: 30, color: gold.withAlpha(90)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _heroStat(
                            LanguageService.tr('Days left', 'দিন বাকি'),
                            daysLeft > 0 ? '$daysLeft' : LanguageService.tr('Last day', 'শেষ দিন'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }

  // ─── Terms ────────────────────────────────────────────────
  Widget _buildTermsCard() {
    final lo = _num(_project['returnMin']);
    final hi = _num(_project['returnMax']);
    final duration = _int(_project['durationDays']);
    final minInv = _num(_project['minInvestmentBdt']);
    final maxRaw = _project['maxInvestmentBdt'];
    final maxInv = maxRaw == null ? 0.0 : _num(maxRaw);
    final minFunding = _num(_project['fundingMinBdt']);

    final items = <(String, String, Color, Color)>[
      (LanguageService.tr('Expected return', 'প্রত্যাশিত লাভ'), _pctRange(lo, hi), emerald, emeraldSoft),
      (LanguageService.tr('Return type', 'রিটার্নের ধরন'), _returnTypeText(_str('returnType')), lapis, lapisSoft),
      (LanguageService.tr('Duration', 'মেয়াদ'),
      duration > 0 ? LanguageService.tr('$duration days', '$duration দিন') : '—', goldDeep, goldSoft),
      (LanguageService.tr('Min. investment', 'সর্বনিম্ন বিনিয়োগ'), minInv > 0 ? _fmtFull(minInv) : '—', ink, ivory),
      (LanguageService.tr('Max. investment', 'সর্বোচ্চ বিনিয়োগ'),
      maxInv > 0 ? _fmtFull(maxInv) : LanguageService.tr('No limit', 'সীমা নেই'), ink, ivory),
      // Website e set thakle tobei — age goal er 60% banaye dekhato
      if (minFunding > 0)
        (LanguageService.tr('Min. funding to start', 'চালু হতে ন্যূনতম'), _fmtFull(minFunding), ink, ivory),
    ];

    return _card(
      title: LanguageService.tr('Investment Terms', 'বিনিয়োগের শর্ত'),
      subtitle: LanguageService.tr('Expected return is an estimate, not guaranteed.',
          'প্রত্যাশিত লাভ আনুমানিক, নিশ্চিত নয়।'),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.2,
        ),
        itemBuilder: (_, i) {
          final (label, value, color, soft) = items[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
                ),
                const SizedBox(height: 2),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: muted)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Risk ─────────────────────────────────────────────────
  Widget _buildRiskCard(String risk) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: terracottaSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: terracotta.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: terracotta, size: 19),
              const SizedBox(width: 8),
              Text(
                LanguageService.tr('Risks to know', 'যে ঝুঁকিগুলো জানা দরকার'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: terracotta),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(risk, style: const TextStyle(fontSize: 12.5, color: ink, height: 1.5)),
        ],
      ),
    );
  }

  // ─── Timeline ─────────────────────────────────────────────
  Widget _buildTimelineCard() {
    final duration = _int(_project['durationDays']);
    // Shudhu je tarikh DB te ache — banano tarikh na
    final rows = <(String, String)>[
      (LanguageService.tr('Funding deadline', 'অর্থায়নের শেষ সময়'), _fmtDate(_project['fundingDeadline'])),
      (LanguageService.tr('Project start', 'প্রজেক্ট শুরু'), _fmtDate(_project['startDate'])),
      (LanguageService.tr('Expected maturity', 'প্রত্যাশিত মেয়াদ শেষ'), _fmtDate(_project['endDate'])),
      (LanguageService.tr('Duration', 'মোট সময়'),
      duration > 0 ? LanguageService.tr('$duration days', '$duration দিন') : ''),
    ].where((r) => r.$2.isNotEmpty).toList();

    return _card(
      title: LanguageService.tr('Timeline', 'সময়সূচি'),
      child: rows.isEmpty
          ? Text(
        LanguageService.tr('Dates have not been announced yet.', 'তারিখ এখনো ঘোষণা করা হয়নি।'),
        style: const TextStyle(fontSize: 12.5, color: muted),
      )
          : Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 18, color: line),
            Row(
              children: [
                Expanded(child: Text(rows[i].$1, style: const TextStyle(fontSize: 12.5, color: muted))),
                Text(rows[i].$2,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── Updates ──────────────────────────────────────────────
  Widget _buildUpdatesCard(List<Map<String, dynamic>> updates) {
    return _card(
      title: LanguageService.tr('Project Updates', 'প্রজেক্ট আপডেট'),
      subtitle: LanguageService.tr('${updates.length} published', '${updates.length} টি প্রকাশিত'),
      child: Column(
        children: [
          for (int i = 0; i < updates.length; i++) ...[
            if (i > 0) const Divider(height: 22, color: line),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: gold, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        updates[i]['title']?.toString() ?? '',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink),
                      ),
                      const SizedBox(height: 2),
                      Text(_fmtDate(updates[i]['createdAt']), style: const TextStyle(fontSize: 11, color: muted)),
                      if ((updates[i]['content']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          updates[i]['content'].toString(),
                          style: const TextStyle(fontSize: 12.5, color: ink, height: 1.45),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── Bank ─────────────────────────────────────────────────
  Widget _buildPaymentBankDetails(List<Map<String, dynamic>> bankAccounts) {
    final idx = _selectedBankIndex.clamp(0, bankAccounts.length - 1);
    final bank = bankAccounts[idx];
    String v(String k) => bank[k]?.toString() ?? '';

    final rows = <(String, String, bool)>[
      (LanguageService.tr('Bank', 'ব্যাংক'), v('bankName'), false),
      (LanguageService.tr('Account name', 'অ্যাকাউন্টের নাম'), v('accountName'), true),
      (LanguageService.tr('Account number', 'অ্যাকাউন্ট নম্বর'), v('accountNumber'), true),
      (LanguageService.tr('Branch', 'শাখা'), v('branchName'), false),
      (LanguageService.tr('Routing number', 'রাউটিং নম্বর'), v('routingNumber'), true),
      (LanguageService.tr('SWIFT code', 'সুইফট কোড'), v('swiftCode'), true),
      (LanguageService.tr('Mobile', 'মোবাইল'), v('mobileNumber'), true),
      (LanguageService.tr('Email', 'ইমেইল'), v('email'), true),
      (LanguageService.tr('Branch address', 'শাখার ঠিকানা'), v('branchAddress'), false),
    ].where((r) => r.$2.isNotEmpty).toList();

    return _card(
      title: LanguageService.tr('Payment Bank Details', 'টাকা পাঠানোর ব্যাংক তথ্য'),
      subtitle: LanguageService.tr('Only send money to these official accounts.',
          'শুধু এই অফিসিয়াল অ্যাকাউন্টে টাকা পাঠান।'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ekadhik account thakle bachar upay — age shudhu prothom ta dekhato
          if (bankAccounts.length > 1) ...[
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: bankAccounts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final on = i == idx;
                  final name = bankAccounts[i]['bankName']?.toString() ?? '';
                  return GestureDetector(
                    onTap: () => setState(() => _selectedBankIndex = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on ? emerald : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: on ? emerald : line),
                      ),
                      child: Text(
                        name.isEmpty ? LanguageService.tr('Account ${i + 1}', 'অ্যাকাউন্ট ${i + 1}') : name,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? Colors.white : ink),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final r in rows) _copyRow(r.$1, r.$2, r.$3),
        ],
      ),
    );
  }

  Widget _copyRow(String label, String value, bool copyable) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10.5, color: muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
              ],
            ),
          ),
          if (copyable)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: value));
                _toast(LanguageService.tr('$label copied', '$label কপি হয়েছে'));
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: goldSoft, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.copy_rounded, size: 16, color: goldDeep),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Learn more (website er ashol FAQ / risk page) ─────────
  Widget _buildLearnMore() {
    Widget tile(IconData icon, String title, String path) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LegalWebPage(title: title, url: 'https://www.biniyogclub.com$path'),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 19, color: emerald),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink))),
              const Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      );
    }

    return _card(
      title: LanguageService.tr('Questions?', 'প্রশ্ন আছে?'),
      child: Column(
        children: [
          tile(Icons.help_outline_rounded, LanguageService.tr('FAQ', 'সাধারণ প্রশ্নাবলী'), '/faq'),
          const Divider(height: 1, color: line),
          tile(Icons.shield_outlined, LanguageService.tr('About & Risk Disclosure', 'আমাদের সম্পর্কে ও ঝুঁকি'), '/about'),
          const Divider(height: 1, color: line),
          tile(Icons.gavel_rounded, LanguageService.tr('Terms', 'শর্তাবলী'), '/terms'),
        ],
      ),
    );
  }

  // ─── Bottom bar ───────────────────────────────────────────
  Widget _buildBottomBar() {
    final status = _str('status');
    final String? reason;
    if (_canInvest) {
      reason = null;
    } else if (status == 'FUNDRAISING') {
      reason = LanguageService.tr('This project is fully funded.', 'প্রজেক্টটি সম্পূর্ণ অর্থায়িত।');
    } else {
      reason = LanguageService.tr('Not open for investment — ${_statusText(status)}',
          'বিনিয়োগের জন্য খোলা নেই — ${_statusText(status)}');
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: line)),
        ),
        child: reason == null
            ? SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _startInvest,
            style: FilledButton.styleFrom(
              backgroundColor: emerald,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              LanguageService.tr('Invest Now', 'এখনই বিনিয়োগ করুন'),
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
          ),
        )
            : Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(14)),
          child: Text(
            reason,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: muted),
          ),
        ),
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

  Widget _errorBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: dangerSoft, borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: danger),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: danger))),
        ],
      ),
    );
  }

  Widget _buildMessage(IconData icon, String title, String subtitle, bool retry) {
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
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: muted)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: retry ? _loadProjectDetail : () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(retry
                  ? LanguageService.tr('Try again', 'আবার চেষ্টা করুন')
                  : LanguageService.tr('Go back', 'ফিরে যান')),
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