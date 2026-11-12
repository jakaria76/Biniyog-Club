import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import '../../../services/pdf_service.dart';
import '../documents/documents_page.dart'; // PdfViewerScreen, ImageViewerScreen
import '../help/help_center_page.dart';
import '../portfolio/investments_page.dart';
import '../settings/legal_web_page.dart';
import 'project_invest_page.dart';
import 'project_labels.dart';
import '../../../theme/app_colors.dart';

/// Website er /projects/[slug] page — ek-i section, ek-i lekha, ek-i niyom.
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
  // ─── Palette — website er rong (lib/theme/app_colors.dart) ───
  static const Color emerald = BC.primary;
  static const Color emeraldBright = BC.brand500; // home page er moto
  static const Color emeraldSoft = BC.secondary;
  static const Color lapis = BC.finance600;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color danger = BC.destructive;
  static const Color dangerSoft = BC.destructiveMuted;
  // Gold er bodole website er chart-4 (teal) — "pending / notice" tone
  static const Color amber = BC.chart4Deep;
  static const Color amberSoft = BC.chart4Muted;

  /// Website er PROJECT_FAQS
  static const List<(String, String, String, String)> _faqs = [
    (
    'When will I receive my returns?',
    'Returns are paid according to the schedule in the project agreement and credited to your Biniyog Club wallet. You will be notified each time a payout is made.',
    'আমি কখন লাভ পাব?',
    'প্রজেক্ট চুক্তির সময়সূচি অনুযায়ী লাভ দেওয়া হয় এবং আপনার বিনিয়োগ ক্লাব ওয়ালেটে জমা হয়। প্রতিবার লাভ দেওয়ার সময় আপনাকে জানানো হবে।',
    ),
    (
    'Can I withdraw my investment early?',
    'Early exit depends on the project agreement. Contact our investor desk before committing if you may need your funds before maturity.',
    'আমি কি আগে বিনিয়োগ তুলে নিতে পারি?',
    'আগে বের হওয়া প্রজেক্ট চুক্তির উপর নির্ভর করে। মেয়াদের আগে টাকা লাগতে পারে মনে হলে বিনিয়োগের আগে আমাদের ইনভেস্টর ডেস্কে যোগাযোগ করুন।',
    ),
    (
    'What happens if the funding goal is not reached?',
    "If a project doesn't reach its funding goal by the deadline, investor funds are handled as set out in the project agreement, which you can review before investing.",
    'লক্ষ্যের টাকা না উঠলে কী হবে?',
    'শেষ সময়ের মধ্যে লক্ষ্যের টাকা না উঠলে বিনিয়োগকারীর টাকা প্রজেক্ট চুক্তি অনুযায়ী ব্যবস্থা করা হয়, যা বিনিয়োগের আগে দেখে নিতে পারেন।',
    ),
  ];

  bool _isLoading = true;
  bool _loadFailed = false;
  Map<String, dynamic> _project = {};
  String _userId = '';
  int _imageIndex = 0;

  /// Kon file ta download / khola cholche (document id)
  final Set<String> _busyDocs = {};

  @override
  void initState() {
    super.initState();
    _loadProjectDetail();
  }

  Future<void> _loadProjectDetail() async {
    if (mounted) setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    final data = await DatabaseService.getProjectDetail(widget.projectIdOrSlug, userId: userId);

    if (!mounted) return;
    setState(() {
      _userId = userId;
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

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? danger : emerald),
    );
  }

  int? get _deadlineDays => DatabaseService.deadlineDaysDhaka(_project['fundingDeadline']);

  /// Deadline er din periye geche? (Dhaka er tarikh, website er motoi)
  bool get _deadlinePassed => DatabaseService.deadlinePassed(_project['fundingDeadline']);

  /// Website er investment.service: FUNDRAISING + deadline baki + taka baki
  bool get _canInvest =>
      _str('status') == 'FUNDRAISING' && !_deadlinePassed && _num(_project['remainingBdt']) > 0;

  String get _returnLabel =>
      ProjectLabels.returnLabel(_num(_project['returnMin']), _num(_project['returnMax']), digits: 1);

  String _fileSize(int bytes) {
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes > 0) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '';
  }

  // ═════════════════════════════════════════════════════════
  // INVEST
  // ═════════════════════════════════════════════════════════
  Future<void> _goLogin() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
    if (mounted) _loadProjectDetail();
  }

  Future<void> _startInvest() async {
    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    if (!mounted) return;

    if (userId.isEmpty) {
      // Landing page theke ashle pichoner page muche felbo na — login kore fire ashbe
      _toast(LanguageService.tr('Please sign in to invest.', 'বিনিয়োগ করতে সাইন ইন করুন।'));
      await _goLogin();
      return;
    }
    if (!_canInvest) {
      _toast(LanguageService.tr('This project is no longer open for investment.',
          'এই প্রজেক্টে এখন আর বিনিয়োগ করা যাবে না।'), error: true);
      _loadProjectDetail();
      return;
    }
    // Alada page e: taka, payment er dhoron (bank/cash/cheque), bank tottho, proof
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProjectInvestPage(project: _project)),
    );
    // Fire ashle "baki taka" ar nijer investment notun kore dekhai
    if (mounted) _loadProjectDetail();
  }

  Future<void> _openMyInvestments() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InvestmentsPage(initialType: 'PROJECT')),
    );
    if (mounted) _loadProjectDetail();
  }

  // ═════════════════════════════════════════════════════════
  // FILE (brochure / project document)
  // Website er file Cloudinary te private — website er download API diye ani
  // ═════════════════════════════════════════════════════════
  Future<(Uint8List, String)?> _fetchFile(Map<String, dynamic> doc, String fallbackName) async {
    final id = doc['id']?.toString() ?? '';
    if (id.isEmpty || _busyDocs.contains(id)) return null;
    if (_userId.isEmpty) {
      _toast(LanguageService.tr('Please sign in to download.', 'ডাউনলোড করতে সাইন ইন করুন।'));
      await _goLogin();
      return null;
    }

    setState(() => _busyDocs.add(id));
    Uint8List? bytes;
    String fileName = '';
    final raw = doc['fileUrl']?.toString() ?? '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      // Purono document — sorasori link (website eo erokom)
      bytes = await PdfService.downloadBytes(raw);
      if (bytes != null) {
        fileName = '${PdfService.safeFileName(fallbackName)}.${PdfService.extensionFor(bytes, raw)}';
      }
    } else {
      final res = await DatabaseService.downloadWebsiteDocument(userId: _userId, documentId: id);
      if (res != null) {
        bytes = res.bytes;
        fileName = res.fileName;
      }
    }
    if (mounted) setState(() => _busyDocs.remove(id));

    if (bytes == null) {
      _toast(DatabaseService.lastDownloadError ??
          LanguageService.tr('Download failed. Check your internet.', 'ডাউনলোড হয়নি। ইন্টারনেট চেক করুন।'),
          error: true);
      return null;
    }
    if (fileName.isEmpty || !fileName.contains('.')) {
      fileName = '${PdfService.safeFileName(fallbackName)}.${PdfService.extensionFor(bytes, raw)}';
    }
    return (bytes, fileName);
  }

  /// Chaple — app er bhetore khule (PDF / chobi)
  Future<void> _viewFile(Map<String, dynamic> doc, String title) async {
    final res = await _fetchFile(doc, title);
    if (res == null || !mounted) return;
    final (bytes, fileName) = res;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfService.isPdf(bytes)
            ? PdfViewerScreen(title: title, bytes: bytes, fileName: fileName)
            : ImageViewerScreen(title: title, bytes: bytes, fileName: fileName),
      ),
    );
  }

  /// Download — phone e save kore, "Open" soho message
  Future<void> _downloadFile(Map<String, dynamic> doc, String title) async {
    final res = await _fetchFile(doc, title);
    if (res == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await PdfService.saveToDevice(res.$1, res.$2);
      final shown = path.contains('/Download/')
          ? 'Download/Biniyog Club'
          : LanguageService.tr('app files', 'অ্যাপ ফাইল');
      messenger.showSnackBar(
        SnackBar(
          content: Text(LanguageService.tr('Saved to $shown', '$shown এ সেভ হয়েছে')),
          backgroundColor: emerald,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: LanguageService.tr('Open', 'খুলুন'),
            textColor: BC.brand200,
            onPressed: () => PdfService.openFile(path),
          ),
        ),
      );
    } catch (e) {
      debugPrint('File save error: $e');
      _toast(
          LanguageService.tr('Could not save the file. Please check storage permission and try again.',
              'ফাইল সেভ করা যায়নি। স্টোরেজ পারমিশন চেক করে আবার চেষ্টা করুন।'),
          error: true);
    }
  }

  void _openWebsite(String title, String path) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LegalWebPage(title: title, url: '${ProjectLabels.websiteBase}$path')),
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
                width: 26,
                height: 26,
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

        final updates = ((_project['updates'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final documents = ((_project['documents'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final brochure = _project['brochure'] is Map
            ? Map<String, dynamic>.from(_project['brochure'] as Map)
            : null;
        final myInvestment = _project['myInvestment'] is Map
            ? Map<String, dynamic>.from(_project['myInvestment'] as Map)
            : null;
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
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
              children: [
                _buildGallery(),
                // Website er motoi chobir thik niche
                if (brochure != null) ...[
                  const SizedBox(height: 10),
                  _buildBrochureCard(brochure),
                ],
                const SizedBox(height: 12),
                _buildHeader(),
                const SizedBox(height: 12),
                _buildFundingCard(),
                if (myInvestment != null) ...[
                  const SizedBox(height: 10),
                  _buildMyInvestment(myInvestment),
                ],
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _card(
                    eyebrow: LanguageService.tr('OVERVIEW', 'সংক্ষেপে'),
                    title: LanguageService.tr('About this project', 'প্রজেক্ট সম্পর্কে'),
                    child: _DescriptionText(text: description, ink: ink, muted: muted),
                  ),
                ],
                const SizedBox(height: 10),
                _buildFinancialsCard(),
                const SizedBox(height: 10),
                _buildTimelineCard(),
                if (documents.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildDocumentsCard(documents),
                ],
                if (updates.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildUpdatesCard(updates),
                ],
                const SizedBox(height: 10),
                _buildRiskCard(),
                const SizedBox(height: 10),
                _buildInfoCard(),
                const SizedBox(height: 10),
                _buildFaqCard(),
                const SizedBox(height: 10),
                _buildContactCard(),
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
      toolbarHeight: 54,
      iconTheme: const IconThemeData(color: ink),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 16),
      ),
    );
  }

  // ─── Gallery (cover + shorbochcho 4 ta chobi) ─────────────
  Widget _buildGallery() {
    final images = ((_project['imageUrls'] as List?) ?? []).map((e) => e.toString()).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 190,
        child: images.isEmpty
            ? _coverPlaceholder()
            : Stack(
          children: [
            PageView.builder(
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _imageIndex = i),
              itemBuilder: (_, i) => Container(
                color: const Color(0xFF020617),
                child: Image.network(
                  images[i],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, __, ___) => _coverPlaceholder(),
                ),
              ),
            ),
            if (images.length > 1)
              Positioned(
                bottom: 8,
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
                        color: on ? Colors.white : Colors.white.withAlpha(130),
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
          colors: [emeraldBright, emerald],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: Icon(Icons.trending_up_rounded, color: Colors.white.withAlpha(110), size: 40)),
    );
  }

  // ─── Brochure (website: "Project brochure · PDF · 8.2 MB · Download") ───
  Widget _buildBrochureCard(Map<String, dynamic> b) {
    final id = b['id']?.toString() ?? '';
    final busy = _busyDocs.contains(id);
    final mime = (b['mimeType']?.toString() ?? '').toLowerCase();
    final title = LanguageService.tr('Project brochure', 'প্রজেক্ট ব্রোশিওর');
    final fileName = '${_str('title')} Brochure';
    final meta = [
      mime == 'application/pdf' ? 'PDF' : LanguageService.tr('Image', 'ছবি'),
      _fileSize(_int(b['sizeBytes'])),
      if (_userId.isEmpty) LanguageService.tr('Sign in to download', 'ডাউনলোড করতে সাইন ইন করুন'),
    ].where((s) => s.isNotEmpty).join(' · ');

    return Material(
      color: emeraldSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: busy ? null : () => _viewFile(b, title),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: emerald.withAlpha(60)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: emerald, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.description_outlined, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
                    const SizedBox(height: 1),
                    Text(meta, style: const TextStyle(fontSize: 12, color: muted)),
                  ],
                ),
              ),
              busy
                  ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: emerald, strokeWidth: 2),
                ),
              )
                  : TextButton.icon(
                onPressed: () => _downloadFile(b, fileName),
                style: TextButton.styleFrom(
                  foregroundColor: emerald,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                icon: const Icon(Icons.download_rounded, size: 19),
                label: Text(LanguageService.tr('Download', 'ডাউনলোড')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Header (status, category, group, nam, jayga, deadline, investor) ───
  Widget _buildHeader() {
    final status = _str('status');
    final groupName = _str('groupName');
    final groupLogo = ProjectLabels.groupLogoUrl(_str('groupSlug'));
    final location = _str('location');
    final investors = _int(_project['investorsCount']);
    final days = _deadlineDays;
    final deadlineDate = ProjectLabels.dateLong(_project['fundingDeadline']);

    // STATUS_DOT: FUNDRAISING white (gold nai), FUNDED/ACTIVE sobuj, COMPLETED neel
    final Color dot = status == 'FUNDRAISING'
        ? Colors.white
        : status == 'COMPLETED'
        ? const Color(0xFF38BDF8)
        : status == 'CANCELLED'
        ? const Color(0xFFF87171)
        : const Color(0xFF34D399);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _pill(
              ProjectLabels.detailStatus(status),
              emerald,
              emeraldSoft,
              leading: Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            ),
            _pill(ProjectLabels.category(_str('category'), _str('customCategory')), ink, Colors.white, border: line),
            if (groupName.isNotEmpty)
              _pill(
                groupName,
                ink,
                Colors.white,
                border: line,
                leading: groupLogo == null
                    ? const Icon(Icons.apartment_rounded, size: 14, color: emerald)
                    : SizedBox(
                  width: 14,
                  height: 14,
                  child: Image.network(
                    groupLogo,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.apartment_rounded, size: 14, color: emerald),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _str('title').isEmpty ? '—' : _str('title'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ink, height: 1.25),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            if (location.isNotEmpty) _iconText(Icons.location_on_outlined, location),
            if (status == 'FUNDRAISING' && days != null)
              _iconText(Icons.access_time_rounded, ProjectLabels.deadlineLong(days, deadlineDate),
                  color: days < 0 ? danger : null),
            _iconText(
              Icons.people_outline_rounded,
              LanguageService.tr('$investors investor${investors == 1 ? '' : 's'}', '$investors জন বিনিয়োগকারী'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _iconText(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color ?? emerald),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: TextStyle(fontSize: 12.5, color: color ?? muted))),
      ],
    );
  }

  Widget _pill(String text, Color color, Color bg, {Widget? leading, Color? border}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 5)],
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ),
        ],
      ),
    );
  }

  // ─── Funding panel (website: Raised · % of goal · Return / Minimum / Duration) ───
  Widget _buildFundingCard() {
    final goal = _num(_project['fundingGoalBdt']);
    final funded = _num(_project['fundedAmountBdt']);
    final pct = ProjectLabels.fundingPct(funded, goal);
    final duration = _int(_project['durationDays']);

    Widget stat(String label, String value, {Color color = Colors.white}) => Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 11.5)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(color: color, fontSize: 14.5, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    Widget divider() => Container(width: 1, height: 28, color: Colors.white.withAlpha(30));

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              LanguageService.tr('RAISED', 'সংগৃহীত'),
                              style: const TextStyle(
                                  color: Color(0xC8FFFFFF), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.3),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                ProjectLabels.bdtShort(funded),
                                style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('$pct%',
                              style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
                          Text(
                            LanguageService.tr('of ${ProjectLabels.bdtShort(goal)}', '${ProjectLabels.bdtShort(goal)} এর'),
                            style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct / 100,
                      minHeight: 6,
                      backgroundColor: Colors.white.withAlpha(40),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(height: 1, color: Colors.white.withAlpha(25)),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      stat(LanguageService.tr('Return', 'লাভ'), _returnLabel, color: BC.brand200),
                      divider(),
                      stat(LanguageService.tr('Minimum', 'সর্বনিম্ন'),
                          ProjectLabels.bdtShort(_num(_project['minInvestmentBdt']))),
                      divider(),
                      stat(LanguageService.tr('Duration', 'মেয়াদ'),
                          duration > 0 ? LanguageService.tr('$duration days', '$duration দিন') : '—'),
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

  // ─── Nijer investment (website er ProjectInvestmentStatus) ───
  Widget _buildMyInvestment(Map<String, dynamic> inv) {
    final status = inv['status']?.toString() ?? 'PENDING';
    final amount = _num(inv['amountBdt']);
    final expected = _num(inv['expectedReturnBdt']);
    final approved = _num(inv['approvedBdt']);
    final pending = _num(inv['pendingBdt']);
    final installment = inv['paymentPlan'] == 'INSTALLMENT';
    final subStatus = inv['lastSubmissionStatus']?.toString();
    final ref = inv['lastTransactionRef']?.toString() ?? '';
    final reason = inv['lastRejectionReason']?.toString() ?? '';
    final awaiting = status == 'PENDING' || status == 'PAYMENT_PENDING';
    final pendingSub = subStatus == 'SUBMITTED' || subStatus == 'UNDER_REVIEW';
    final owed = math.max(0.0, amount - approved - pending);
    final canPay = awaiting && (installment ? owed > 0 : (subStatus == null || subStatus == 'REJECTED'));

    final (String label, IconData icon, Color color) = switch (status) {
      'PAYMENT_PENDING' => (LanguageService.tr('Awaiting Payment', 'পেমেন্টের অপেক্ষায়'), Icons.schedule_rounded, BC.chart4Deep),
      'ACTIVE' => (LanguageService.tr('Investment Active', 'বিনিয়োগ চালু'), Icons.trending_up_rounded, emerald),
      'MATURED' => (LanguageService.tr('Investment Matured', 'বিনিয়োগ মেয়াদপূর্ণ'), Icons.check_circle_outline_rounded, emerald),
      'COMPLETED' => (LanguageService.tr('Investment Completed', 'বিনিয়োগ সম্পন্ন'), Icons.check_circle_outline_rounded, emerald),
      _ => (LanguageService.tr('Draft — Payment Pending', 'খসড়া — পেমেন্ট বাকি'), Icons.schedule_rounded, muted),
    };

    final (String subLabel, Color subColor, Color subBg) = switch (subStatus) {
      'APPROVED' => (LanguageService.tr('Proof Approved', 'প্রুফ অনুমোদিত'), emerald, emeraldSoft),
      'REJECTED' => (LanguageService.tr('Proof Rejected', 'প্রুফ বাতিল'), danger, dangerSoft),
      'UNDER_REVIEW' => (LanguageService.tr('Proof Under Review', 'প্রুফ যাচাই চলছে'), muted, ivory),
      _ => (LanguageService.tr('Proof Submitted — Under Review', 'প্রুফ জমা — যাচাই চলছে'), muted, ivory),
    };

    return _card(
      eyebrow: LanguageService.tr('YOUR INVESTMENT', 'আপনার বিনিয়োগ'),
      title: LanguageService.tr('Investment status', 'বিনিয়োগের অবস্থা'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              color: color.withAlpha(16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withAlpha(60)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
                      const SizedBox(height: 2),
                      Text(
                        LanguageService.tr(
                            '${ProjectLabels.bdtFull(amount)} invested · ${ProjectLabels.bdtFull(expected)} annual expected return',
                            '${ProjectLabels.bdtFull(amount)} বিনিয়োগ · ${ProjectLabels.bdtFull(expected)} বার্ষিক প্রত্যাশিত লাভ'),
                        style: const TextStyle(fontSize: 12, color: muted, height: 1.35),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _openMyInvestments,
                  style: TextButton.styleFrom(
                    foregroundColor: emerald,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  child: Text(LanguageService.tr('View →', 'দেখুন →')),
                ),
              ],
            ),
          ),
          // Kistite dicche — kotota jachai holo
          if (awaiting && installment) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 6,
                      child: LayoutBuilder(
                        builder: (_, c) {
                          double f(double v) => amount > 0 ? (v / amount).clamp(0.0, 1.0).toDouble() : 0.0;
                          return Stack(
                            children: [
                              Container(color: line),
                              Container(width: c.maxWidth * (f(approved) + f(pending)).clamp(0.0, 1.0), color: BC.chart4),
                              Container(width: c.maxWidth * f(approved), color: emerald),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    LanguageService.tr(
                        'Paying in installments · ${ProjectLabels.bdtFull(approved)} of ${ProjectLabels.bdtFull(amount)} verified'
                            '${pending > 0 ? ' · ${ProjectLabels.bdtFull(pending)} under review' : ''}',
                        'কিস্তিতে দিচ্ছেন · ${ProjectLabels.bdtFull(amount)} এর মধ্যে ${ProjectLabels.bdtFull(approved)} যাচাই হয়েছে'
                            '${pending > 0 ? ' · ${ProjectLabels.bdtFull(pending)} যাচাই চলছে' : ''}'),
                    style: const TextStyle(fontSize: 12, color: muted, height: 1.4),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    LanguageService.tr('Your deed is issued once the full amount is verified.',
                        'পুরো টাকা যাচাই হলে আপনার দলিল দেওয়া হবে।'),
                    style: const TextStyle(fontSize: 11.5, color: muted),
                  ),
                ],
              ),
            ),
          ],
          // Shesh payment proof er obostha (ekbare dile)
          if (subStatus != null && !installment) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: subBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: subColor.withAlpha(50)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        subStatus == 'REJECTED'
                            ? Icons.error_outline_rounded
                            : subStatus == 'APPROVED'
                            ? Icons.check_circle_outline_rounded
                            : Icons.schedule_rounded,
                        size: 16,
                        color: subColor,
                      ),
                      const SizedBox(width: 6),
                      Text(subLabel, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: subColor)),
                    ],
                  ),
                  if (ref.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text('Ref: $ref', style: const TextStyle(fontSize: 12, color: muted, fontFamily: 'monospace')),
                  ],
                  if (subStatus == 'REJECTED' && reason.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(LanguageService.tr('Reason: $reason', 'কারণ: $reason'),
                        style: const TextStyle(fontSize: 12, color: danger)),
                  ],
                ],
              ),
            ),
          ],
          if (pendingSub) ...[
            const SizedBox(height: 6),
            Text(
              LanguageService.tr('Our finance team will verify your payment within 1–2 business days.',
                  'আমাদের ফাইন্যান্স টিম ১–২ কর্মদিবসের মধ্যে আপনার পেমেন্ট যাচাই করবে।'),
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          ],
          if (canPay) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: FilledButton(
                onPressed: _openMyInvestments,
                style: FilledButton.styleFrom(
                  backgroundColor: emerald,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  installment && approved + pending > 0
                      ? LanguageService.tr('Pay Next Installment (${ProjectLabels.bdtFull(owed)} left)',
                      'পরের কিস্তি দিন (${ProjectLabels.bdtFull(owed)} বাকি)')
                      : LanguageService.tr('Complete Payment', 'পেমেন্ট সম্পন্ন করুন'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Financial details (website er 11 ta ghor) ─────────────
  Widget _buildFinancialsCard() {
    final goal = _num(_project['fundingGoalBdt']);
    final funded = _num(_project['fundedAmountBdt']);
    final remaining = math.max(0.0, goal - funded);
    final maxRaw = _project['maxInvestmentBdt'];
    final maxInv = maxRaw == null ? 0.0 : _num(maxRaw);
    final riskLevel = _str('riskLevel');
    final duration = _int(_project['durationDays']);

    final items = <(String, String)>[
      (LanguageService.tr('Funding goal', 'অর্থায়নের লক্ষ্য'), ProjectLabels.bdtFull(goal)),
      (LanguageService.tr('Minimum to activate', 'চালু হতে ন্যূনতম'), ProjectLabels.bdtFull(_num(_project['fundingMinBdt']))),
      (LanguageService.tr('Amount raised', 'সংগৃহীত'), ProjectLabels.bdtFull(funded)),
      (LanguageService.tr('Still needed', 'এখনো লাগবে'), ProjectLabels.bdtFull(remaining)),
      (LanguageService.tr('Minimum investment', 'সর্বনিম্ন বিনিয়োগ'), ProjectLabels.bdtFull(_num(_project['minInvestmentBdt']))),
      if (maxInv > 0) (LanguageService.tr('Maximum investment', 'সর্বোচ্চ বিনিয়োগ'), ProjectLabels.bdtFull(maxInv)),
      (
      LanguageService.tr('Annual expected return', 'বার্ষিক প্রত্যাশিত লাভ'),
      '$_returnLabel · ${ProjectLabels.returnType(_str('returnType'))}',
      ),
      (LanguageService.tr('Duration', 'মেয়াদ'), LanguageService.tr('$duration days', '$duration দিন')),
      (LanguageService.tr('Return payout', 'লাভ প্রদান'), ProjectLabels.payoutPeriod(_int(_project['payoutPeriodMonths']))),
      if (riskLevel.isNotEmpty) (LanguageService.tr('Risk level', 'ঝুঁকির মাত্রা'), ProjectLabels.riskLevel(riskLevel)),
      (LanguageService.tr('Investors so far', 'এ পর্যন্ত বিনিয়োগকারী'), '${_int(_project['investorsCount'])}'),
    ];

    return _card(
      eyebrow: LanguageService.tr('THE NUMBERS', 'হিসাব'),
      title: LanguageService.tr('Financial details', 'আর্থিক তথ্য'),
      subtitle: LanguageService.tr('Expected return is an estimate, not guaranteed.', 'প্রত্যাশিত লাভ আনুমানিক, নিশ্চিত নয়।'),
      child: LayoutBuilder(
        builder: (_, c) {
          final w = (c.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, value) in items)
                Container(
                  width: w,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: ivory,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontSize: 11.5, color: muted, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(value,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink, height: 1.3)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ─── Timeline (website: Funding deadline · Project start · Maturity) ───
  Widget _buildTimelineCard() {
    final now = DateTime.now().toUtc();
    final start = ProjectLabels.parseDate(_project['startDate']);
    final end = ProjectLabels.parseDate(_project['endDate']);
    final days = _deadlineDays;

    final milestones = <(String, String, IconData, bool)>[
      (
      LanguageService.tr('Funding deadline', 'অর্থায়নের শেষ সময়'),
      ProjectLabels.dateLong(_project['fundingDeadline']),
      Icons.event_outlined,
      // Deadline er pura din shesh holei "hoye geche"
      days != null && days < 0,
      ),
      (
      LanguageService.tr('Project start', 'প্রজেক্ট শুরু'),
      ProjectLabels.dateLong(_project['startDate']),
      Icons.trending_up_rounded,
      start != null && start.isBefore(now),
      ),
      (
      LanguageService.tr('Maturity', 'মেয়াদ শেষ'),
      ProjectLabels.dateLong(_project['endDate']),
      Icons.check_circle_outline_rounded,
      end != null && end.isBefore(now),
      ),
    ];

    return _card(
      eyebrow: LanguageService.tr('SCHEDULE', 'সময়সূচি'),
      title: LanguageService.tr('Timeline', 'টাইমলাইন'),
      child: Column(
        children: [
          for (int i = 0; i < milestones.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 34,
                    child: Column(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: milestones[i].$4 ? emerald : Colors.white,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: milestones[i].$4 ? emerald : line),
                          ),
                          child: Icon(milestones[i].$3, size: 17, color: milestones[i].$4 ? Colors.white : emerald),
                        ),
                        if (i < milestones.length - 1)
                          Expanded(child: Container(width: 1, color: line, margin: const EdgeInsets.symmetric(vertical: 3))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 1, bottom: i < milestones.length - 1 ? 14 : 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(milestones[i].$1,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink)),
                          const SizedBox(height: 1),
                          Text(
                            milestones[i].$2.isEmpty
                                ? LanguageService.tr('To be announced', 'পরে জানানো হবে')
                                : milestones[i].$2,
                            style: const TextStyle(fontSize: 12.5, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ─── Project documents (website er public document) ───────
  Widget _buildDocumentsCard(List<Map<String, dynamic>> docs) {
    return _card(
      eyebrow: LanguageService.tr('DUE DILIGENCE', 'যাচাইয়ের কাগজ'),
      title: LanguageService.tr('Project documents', 'প্রজেক্টের ডকুমেন্ট'),
      child: Column(
        children: [
          for (int i = 0; i < docs.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Builder(builder: (_) {
              final d = docs[i];
              final name = d['name']?.toString().isNotEmpty == true ? d['name'].toString() : 'Document';
              final busy = _busyDocs.contains(d['id']?.toString() ?? '');
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: busy ? null : () => _viewFile(d, name),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: line),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(color: emeraldSoft, borderRadius: BorderRadius.circular(9)),
                          child: const Icon(Icons.description_outlined, size: 19, color: emerald),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink)),
                              if (_fileSize(_int(d['sizeBytes'])).isNotEmpty)
                                Text(_fileSize(_int(d['sizeBytes'])),
                                    style: const TextStyle(fontSize: 12, color: muted)),
                            ],
                          ),
                        ),
                        busy
                            ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: emerald, strokeWidth: 2),
                          ),
                        )
                            : IconButton(
                          tooltip: LanguageService.tr('Download', 'ডাউনলোড'),
                          onPressed: () => _downloadFile(d, name),
                          icon: const Icon(Icons.download_rounded, size: 19, color: emerald),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ─── Updates (website: type badge + tarikh + lekha) ───────
  Widget _buildUpdatesCard(List<Map<String, dynamic>> updates) {
    (Color, Color) typeColors(String t) {
      switch (t) {
        case 'MILESTONE':
          return (emerald, emeraldSoft);
        case 'FINANCIAL_REPORT':
          return (lapis, BC.finance50);
        case 'ISSUE':
          return (danger, dangerSoft);
        default:
          return (muted, ivory);
      }
    }

    return _card(
      eyebrow: LanguageService.tr('PROGRESS', 'অগ্রগতি'),
      title: LanguageService.tr('Project updates', 'প্রজেক্ট আপডেট'),
      child: Column(
        children: [
          for (int i = 0; i < updates.length; i++) ...[
            if (i > 0) const Divider(height: 18, color: line),
            Builder(builder: (_) {
              final u = updates[i];
              final type = u['type']?.toString() ?? '';
              final (fg, bg) = typeColors(type);
              final date = ProjectLabels.dateLong(u['publishedAt']);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(color: emerald, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
                              child: Text(ProjectLabels.updateType(type),
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
                            ),
                            if (date.isNotEmpty) Text(date, style: const TextStyle(fontSize: 11.5, color: muted)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(u['title']?.toString() ?? '',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
                        if ((u['content']?.toString() ?? '').isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(u['content'].toString(),
                              style: const TextStyle(fontSize: 12.5, color: muted, height: 1.45)),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  // ─── Risk disclosure (website: shobar jonno lekha + project er nijer jhuNki) ───
  Widget _buildRiskCard() {
    final specific = ProjectLabels.stripLegacyCategory(_str('riskInfo'));
    final level = _str('riskLevel');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: amberSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: amber.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(LanguageService.tr('PLEASE READ', 'অবশ্যই পড়ুন'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: amber, letterSpacing: 1.3)),
          const SizedBox(height: 2),
          Text(LanguageService.tr('Risk disclosure', 'ঝুঁকির তথ্য'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, size: 19, color: amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  LanguageService.tr(
                      'All investments carry risk, including market fluctuations and operational challenges. Past performance does not guarantee future results, and you may receive less than you invest.',
                      'সব বিনিয়োগেই ঝুঁকি আছে — বাজারের ওঠানামা ও কাজের সমস্যা সহ। আগের ফলাফল ভবিষ্যতের নিশ্চয়তা দেয় না, এবং বিনিয়োগের চেয়ে কম ফেরত পেতে পারেন।'),
                  style: const TextStyle(fontSize: 12.5, color: muted, height: 1.5),
                ),
              ),
            ],
          ),
          if (specific.isNotEmpty || level.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: amber.withAlpha(40)),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: LanguageService.tr('PROJECT-SPECIFIC RISKS', 'এই প্রজেক্টের ঝুঁকি')),
                  if (level.isNotEmpty)
                    TextSpan(
                      text: LanguageService.tr(
                          '  · ${ProjectLabels.riskLevel(level)} risk', '  · ঝুঁকি ${ProjectLabels.riskLevel(level)}'),
                      style: const TextStyle(color: amber),
                    ),
                ],
              ),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: muted, letterSpacing: 0.9),
            ),
            if (specific.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(specific, style: const TextStyle(fontSize: 12.5, color: muted, height: 1.5)),
            ],
          ],
        ],
      ),
    );
  }

  // ─── Project info (website er sidebar: group, jayga, category, return type) ───
  Widget _buildInfoCard() {
    final rows = <(String, String)>[
      if (_str('groupName').isNotEmpty) (LanguageService.tr('Business group', 'বিজনেস গ্রুপ'), _str('groupName')),
      if (_str('location').isNotEmpty) (LanguageService.tr('Location', 'জায়গা'), _str('location')),
      (LanguageService.tr('Category', 'ক্যাটাগরি'), ProjectLabels.category(_str('category'), _str('customCategory'))),
      (LanguageService.tr('Return type', 'রিটার্নের ধরন'), ProjectLabels.returnType(_str('returnType'))),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: line),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rows[i].$1, style: const TextStyle(fontSize: 13, color: muted)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(rows[i].$2,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: ink)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── FAQ (website er 3 ta proshno) ────────────────────────
  Widget _buildFaqCard() {
    return _card(
      eyebrow: 'FAQ',
      title: LanguageService.tr('Common questions', 'সাধারণ প্রশ্ন'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < _faqs.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: line),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 10),
                iconColor: emerald,
                collapsedIconColor: muted,
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: Text(
                  LanguageService.tr(_faqs[i].$1, _faqs[i].$3),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink),
                ),
                children: [
                  Text(
                    LanguageService.tr(_faqs[i].$2, _faqs[i].$4),
                    style: const TextStyle(fontSize: 12.5, color: muted, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(LanguageService.tr('More questions? ', 'আরও প্রশ্ন? '),
                  style: const TextStyle(fontSize: 12.5, color: muted)),
              _link(LanguageService.tr('Read the full FAQ', 'পুরো FAQ পড়ুন'),
                      () => _openWebsite(LanguageService.tr('FAQ', 'সাধারণ প্রশ্নাবলী'), '/faq')),
              Text(LanguageService.tr(' or ', ' অথবা '), style: const TextStyle(fontSize: 12.5, color: muted)),
              _link(LanguageService.tr('contact support', 'সাপোর্টে যোগাযোগ'), _openHelpCenter),
            ],
          ),
        ],
      ),
    );
  }

  Widget _link(String text, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: emerald)),
  );

  void _openHelpCenter() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpCenterPage()));
  }

  // ─── "Questions about this project?" ──────────────────────
  Widget _buildContactCard() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openHelpCenter,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: line),
          ),
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline_rounded, size: 20, color: emerald),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(LanguageService.tr('Questions about this project?', 'এই প্রজেক্ট নিয়ে প্রশ্ন আছে?'),
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink)),
                    const SizedBox(height: 2),
                    Text(LanguageService.tr('Contact our investor desk', 'আমাদের ইনভেস্টর ডেস্কে যোগাযোগ করুন'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: emerald)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Bottom bar (website er "Invest in this project" box er moto) ───
  Widget _buildBottomBar() {
    final status = _str('status');
    final days = _deadlineDays;
    final deadlineDate = ProjectLabels.dateLong(_project['fundingDeadline']);

    final String? title;
    final String? reason;
    if (_canInvest) {
      title = null;
      reason = null;
    } else if (status == 'FUNDRAISING' && _deadlinePassed) {
      title = LanguageService.tr('Funding closed', 'বিনিয়োগ বন্ধ');
      reason = LanguageService.tr(
          'The funding deadline for this project has passed, so it is no longer accepting investments.',
          'এই প্রজেক্টের বিনিয়োগের শেষ সময় পেরিয়ে গেছে, তাই এখন আর বিনিয়োগ নেওয়া হচ্ছে না।');
    } else if (status == 'FUNDRAISING') {
      title = LanguageService.tr('Fully Funded', 'সম্পূর্ণ অর্থায়িত');
      reason = LanguageService.tr('This project has reached its funding goal.', 'প্রজেক্টটির লক্ষ্যের টাকা উঠে গেছে।');
    } else {
      title = ProjectLabels.detailStatus(status);
      reason = LanguageService.tr('This project is not currently accepting investments.',
          'এই প্রজেক্টে এখন বিনিয়োগ নেওয়া হচ্ছে না।');
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: line)),
        ),
        child: reason == null
            ? Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (days != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded, size: 15, color: amber),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        ProjectLabels.deadlineLong(days, deadlineDate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: amber),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: _returnLabel,
                              style: const TextStyle(fontWeight: FontWeight.w800, color: ink)),
                          TextSpan(
                              text: LanguageService.tr(' annual expected return', ' বার্ষিক প্রত্যাশিত লাভ'),
                              style: const TextStyle(color: muted)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text(
                        LanguageService.tr(
                            'From ${ProjectLabels.bdtShort(_num(_project['minInvestmentBdt']))} · ${ProjectLabels.fundingPct(_num(_project['fundedAmountBdt']), _num(_project['fundingGoalBdt']))}% funded',
                            '${ProjectLabels.bdtShort(_num(_project['minInvestmentBdt']))} থেকে · ${ProjectLabels.fundingPct(_num(_project['fundedAmountBdt']), _num(_project['fundingGoalBdt']))}% সংগৃহীত'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: _startInvest,
                    style: FilledButton.styleFrom(
                      backgroundColor: emerald,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                    label: Text(
                      LanguageService.tr('Invest Now', 'বিনিয়োগ করুন'),
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Center(
              child: Wrap(
                children: [
                  Text(LanguageService.tr('By investing you agree to our ', 'বিনিয়োগ করলে আপনি আমাদের '),
                      style: const TextStyle(fontSize: 11.5, color: muted)),
                  GestureDetector(
                    onTap: () => _openWebsite(LanguageService.tr('Terms of Service', 'ব্যবহারের শর্তাবলী'), '/terms'),
                    child: Text(LanguageService.tr('Terms of Service', 'শর্তাবলীতে রাজি'),
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: emerald)),
                  ),
                ],
              ),
            ),
          ],
        )
            : Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: ivory, borderRadius: BorderRadius.circular(12)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink)),
              const SizedBox(height: 2),
              Text(reason,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: muted, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // SHARED
  // ═════════════════════════════════════════════════════════
  /// Website er SectionTitle: choto sobuj "eyebrow" + boro title
  Widget _card({required String title, String? eyebrow, String? subtitle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null)
            Text(eyebrow,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: emerald, letterSpacing: 1.6)),
          if (eyebrow != null) const SizedBox(height: 2),
          Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: ink)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: muted)),
          ],
          const SizedBox(height: 10),
          child,
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
            Icon(icon, size: 34, color: emerald),
            const SizedBox(height: 10),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
            const SizedBox(height: 3),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: muted)),
            const SizedBox(height: 14),
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
// Project er bornona — website er autoFormatDescription er moto:
// choto alada line → heading, •/–/- → list, "Label: value" → bold label,
// **bold** → bold. Lekha je bhabe admin likheche sheta-i thake.
// ═══════════════════════════════════════════════════════════
class _DescriptionText extends StatelessWidget {
  final String text;
  final Color ink;
  final Color muted;

  const _DescriptionText({required this.text, required this.ink, required this.muted});

  static final RegExp _bullet = RegExp(r'^\s*([•●▪◦■□➤➢►▶✓✔☑✗–—]|[-*+](?=\s))\s*');
  static final RegExp _numbered = RegExp(r'^\s*([0-9০-৯]{1,2}[.)])\s+');
  static final RegExp _mdHeading = RegExp(r'^\s*#{1,6}\s+');
  static final RegExp _keyValue = RegExp(r'^([^:*#|>\n]{2,40}?):\s+(\S.*)$');
  static final RegExp _endPunct = RegExp(r'[.,;!।…]$');

  static int _words(String s) => s.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  bool _looksLikeHeading(String t, bool standalone) {
    if (t.isEmpty || t.length > 70 || t.contains('http') || t.contains('www.')) return false;
    if (_bullet.hasMatch(t)) return false;
    if (t.endsWith(':')) return _words(t) <= 5;
    if (_keyValue.hasMatch(t)) return false;
    if (_endPunct.hasMatch(t)) return false;
    final caps = RegExp(r'[A-Z]').hasMatch(t) && !RegExp(r'[a-z]').hasMatch(t);
    if (caps) return true;
    return standalone && _words(t) <= 10;
  }

  /// **bold** soho inline lekha
  List<InlineSpan> _inline(String s, TextStyle base) {
    final spans = <InlineSpan>[];
    final parts = s.split('**');
    // Bijor sonkhok ** hole (bondho hoyni) shob tara muche dei
    if (parts.length.isEven) return [TextSpan(text: s.replaceAll('**', ''), style: base)];
    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(TextSpan(
        text: parts[i].replaceAll('__', ''),
        style: i.isOdd ? base.copyWith(fontWeight: FontWeight.w700, color: ink) : base,
      ));
    }
    return spans;
  }

  Widget _rich(String s, TextStyle base) {
    final kv = _keyValue.firstMatch(s);
    if (kv != null && !s.contains('**') && _words(kv.group(1)!) <= 6 && !RegExp(r'^\d+$').hasMatch(kv.group(1)!.trim())) {
      return Text.rich(TextSpan(children: [
        TextSpan(text: '${kv.group(1)!.trim()}: ', style: base.copyWith(fontWeight: FontWeight.w700, color: ink)),
        ..._inline(kv.group(2)!, base),
      ]));
    }
    return Text.rich(TextSpan(children: _inline(s, base)));
  }

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(fontSize: 13.5, color: ink.withAlpha(220), height: 1.55);
    final heading = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: ink, height: 1.4);

    // Faka line diye block e bhag
    final blocks = <List<String>>[];
    var cur = <String>[];
    for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
      if (raw.trim().isEmpty) {
        if (cur.isNotEmpty) blocks.add(cur);
        cur = <String>[];
      } else {
        cur.add(raw.trimRight());
      }
    }
    if (cur.isNotEmpty) blocks.add(cur);

    final widgets = <Widget>[];
    for (int bi = 0; bi < blocks.length; bi++) {
      final block = blocks[bi];
      final isLast = bi == blocks.length - 1;
      if (bi > 0) widgets.add(const SizedBox(height: 10));

      for (int li = 0; li < block.length; li++) {
        final t = block[li].trim();
        final next = li + 1 < block.length ? block[li + 1].trim() : '';

        if (_mdHeading.hasMatch(t)) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(t.replaceFirst(_mdHeading, '').replaceAll('**', ''), style: heading),
          ));
          continue;
        }

        final standalone = block.length == 1 && !isLast;
        final labelAbove = li == 0 && block.length > 1 && _words(t) <= 3 && next.length > t.length;
        if (li == 0 && !t.contains('**') && _looksLikeHeading(t, standalone || labelAbove)) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(t.replaceFirst(RegExp(r':$'), ''), style: heading),
          ));
          continue;
        }

        final bullet = _bullet.firstMatch(t);
        final numbered = bullet == null ? _numbered.firstMatch(t) : null;
        if (bullet != null || numbered != null) {
          final marker = numbered != null ? numbered.group(1)! : '•';
          final rest = t.replaceFirst(bullet != null ? _bullet : _numbered, '');
          widgets.add(Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: numbered != null ? 20 : 14,
                  child: Text(marker, style: body.copyWith(fontWeight: FontWeight.w700, color: muted)),
                ),
                Expanded(child: _rich(rest, body)),
              ],
            ),
          ));
          continue;
        }

        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: _rich(t, body),
        ));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }
}