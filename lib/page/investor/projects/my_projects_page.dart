import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import 'project_detail_page.dart';
import 'project_labels.dart';
import '../../../theme/app_colors.dart';

/// Website er /projects (All Projects) page — search, sort, category ar
/// website er moto project card.
class MyProjectsPage extends StatefulWidget {
  /// Dashboard er tab hishebe khulle back chaple ki hobe (jemon Home tab e jawa).
  /// Alada page hishebe (push kore) khulle dorkar nei — tokhon pop hoy.
  final VoidCallback? onBack;

  const MyProjectsPage({super.key, this.onBack});

  @override
  State<MyProjectsPage> createState() => _MyProjectsPageState();
}

class _MyProjectsPageState extends State<MyProjectsPage> {
  // ─── Palette — website er rong (lib/theme/app_colors.dart) ───
  static const Color emerald = BC.primary;
  static const Color emeraldBright = BC.brand500; // home page er moto
  static const Color emeraldSoft = BC.secondary;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;

  /// Website er SORT_LABELS
  static const List<(String, String, String)> _sorts = [
    ('newest', 'Newest', 'নতুন'),
    ('deadline', 'Deadline Soon', 'শেষ সময় আগে'),
    ('funded_pct', 'Most Funded', 'সবচেয়ে বেশি সংগৃহীত'),
    ('goal_asc', 'Smallest Goal', 'ছোট লক্ষ্য'),
    ('goal_desc', 'Largest Goal', 'বড় লক্ষ্য'),
  ];

  bool _isLoading = true;
  bool _loadFailed = false;
  List<Map<String, dynamic>> _projects = [];

  String _sort = 'newest';
  String? _category; // null = All
  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProjectsData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProjectsData() async {
    if (mounted) setState(() => _isLoading = true);

    final res = await DatabaseService.getProjectsData();
    final list = ((res['projects'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    // Khali: "kono project nei" naki "net nei" — alada kori
    final failed = list.isEmpty && (res.isEmpty || DatabaseService.lastRequestFailed);

    if (!mounted) return;
    setState(() {
      _projects = list;
      _loadFailed = failed;
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

  DateTime _date(dynamic v) => ProjectLabels.parseDate(v) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// Website er search: title, description, location
  bool _matchesSearch(Map<String, dynamic> p) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [p['title'], p['description'], p['location']]
        .any((v) => (v?.toString() ?? '').toLowerCase().contains(q));
  }

  /// Search mile emon project — category chip er count er jonno
  List<Map<String, dynamic>> get _searched => _projects.where(_matchesSearch).toList();

  List<Map<String, dynamic>> get _visible {
    final list = _searched.where((p) => _category == null || p['category'] == _category).toList();
    // Website er buildOrderBy
    switch (_sort) {
      case 'deadline':
        list.sort((a, b) => _date(a['fundingDeadline']).compareTo(_date(b['fundingDeadline'])));
        break;
      case 'funded_pct':
        list.sort((a, b) => _num(b['fundedAmountBdt']).compareTo(_num(a['fundedAmountBdt'])));
        break;
      case 'goal_asc':
        list.sort((a, b) => _num(a['fundingGoalBdt']).compareTo(_num(b['fundingGoalBdt'])));
        break;
      case 'goal_desc':
        list.sort((a, b) => _num(b['fundingGoalBdt']).compareTo(_num(a['fundingGoalBdt'])));
        break;
      default:
        list.sort((a, b) => _date(b['createdAt']).compareTo(_date(a['createdAt'])));
    }
    return list;
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        final list = _visible;

        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 54,
            iconTheme: const IconThemeData(color: ink),
            automaticallyImplyLeading: false,
            // Onno page er moto back icon — shob shomoy dekhabe
            leading: IconButton(
              tooltip: LanguageService.tr('Back', 'পিছনে'),
              icon: const BackButtonIcon(),
              color: ink,
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else if (widget.onBack != null) {
                  // Dashboard er tab — Home tab e fire jay
                  widget.onBack!.call();
                } else {
                  Navigator.of(context).maybePop();
                }
              },
            ),
            title: Text(
              LanguageService.tr('All Projects', 'সব প্রজেক্ট'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 17.5),
            ),
          ),
          body: _isLoading
              ? const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4),
            ),
          )
              : _loadFailed
              ? _buildMessage()
              : RefreshIndicator(
            onRefresh: _loadProjectsData,
            color: emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              // Dashboard tab hole curved navbar er jonno niche jayga
              padding: EdgeInsets.fromLTRB(16, 2, 16, Navigator.of(context).canPop() ? 24 : 104),
              children: [
                _buildSummary(),
                const SizedBox(height: 12),
                _buildSearch(),
                const SizedBox(height: 10),
                _buildSortChips(),
                const SizedBox(height: 8),
                _buildCategoryChips(),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  _buildEmptyState()
                else
                  for (final p in list) ...[
                    _buildProjectCard(p),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Upore choto summary — website er "N verified projects" er moto, shob DB theke
  Widget _buildSummary() {
    final open = _projects.where((p) => p['acceptingInvestment'] == true);
    final seeking = open.fold<double>(
        0, (s, p) => s + math.max(0.0, _num(p['fundingGoalBdt']) - _num(p['fundedAmountBdt'])));

    Widget cell(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(165))),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
          ),
        ],
      ),
    );

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
                  Text(
                    LanguageService.tr('INVESTMENT PIPELINE', 'বিনিয়োগের সুযোগ'),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white.withAlpha(200), letterSpacing: 1.3),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    LanguageService.tr(
                        '${_projects.length} verified ${_projects.length == 1 ? 'project' : 'projects'} for co-investment',
                        '${_projects.length} টি যাচাইকৃত প্রজেক্ট'),
                    style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(200)),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      cell(LanguageService.tr('Open now', 'চলমান'), '${open.length}', Colors.white),
                      cell(LanguageService.tr('Still to raise', 'সংগ্রহ বাকি'),
                          seeking > 0 ? ProjectLabels.bdtCard(seeking) : '—', BC.brand200),
                      cell(LanguageService.tr('Projects', 'প্রজেক্ট'), '${_projects.length}', BC.brand300),
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

  Widget _buildSearch() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _search = v),
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14, color: ink),
      decoration: InputDecoration(
        hintText: LanguageService.tr('Search by title, sector, location...', 'নাম, খাত বা জায়গা দিয়ে খুঁজুন...'),
        hintStyle: const TextStyle(fontSize: 13.5, color: muted),
        prefixIcon: const Icon(Icons.search_rounded, size: 19, color: muted),
        suffixIcon: _search.isEmpty
            ? null
            : IconButton(
          icon: const Icon(Icons.close_rounded, size: 19, color: muted),
          onPressed: () {
            _searchCtrl.clear();
            setState(() => _search = '');
          },
        ),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: emerald, width: 1.4)),
      ),
    );
  }

  Widget _chip({required String label, required bool selected, required VoidCallback onTap, IconData? icon}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? emerald : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? emerald : line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: selected ? Colors.white : muted),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipRow(List<Widget> chips) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Center(child: chips[i]),
      ),
    );
  }

  Widget _buildSortChips() {
    return _chipRow([
      for (final s in _sorts)
        _chip(
          label: LanguageService.tr(s.$2, s.$3),
          icon: s.$1 == 'newest' ? Icons.tune_rounded : null,
          selected: _sort == s.$1,
          onTap: () => setState(() => _sort = s.$1),
        ),
    ]);
  }

  /// Website er moto: All (N) + je category te project ache shudhu sheigulo
  Widget _buildCategoryChips() {
    final searched = _searched;
    final counts = <String, int>{};
    for (final p in searched) {
      final c = p['category']?.toString() ?? '';
      counts[c] = (counts[c] ?? 0) + 1;
    }
    return _chipRow([
      _chip(
        label: LanguageService.tr('All (${searched.length})', 'সব (${searched.length})'),
        selected: _category == null,
        onTap: () => setState(() => _category = null),
      ),
      for (final cat in ProjectLabels.categoryLabels.keys)
        if ((counts[cat] ?? 0) > 0)
          _chip(
            label: '${ProjectLabels.category(cat)} (${counts[cat]})',
            selected: _category == cat,
            onTap: () => setState(() => _category = cat),
          ),
    ]);
  }

  // ─── Project card (website er components/shared/project-card.tsx) ───
  Widget _buildProjectCard(Map<String, dynamic> p) {
    final goal = _num(p['fundingGoalBdt']);
    final funded = _num(p['fundedAmountBdt']);
    final pct = ProjectLabels.fundingPct(funded, goal);
    final status = p['status']?.toString() ?? '';
    final cat = p['category']?.toString() ?? '';
    final catLabel = ProjectLabels.category(cat, p['customCategory']?.toString());
    final location = p['location']?.toString() ?? '';
    final groupName = p['groupName']?.toString() ?? '';
    final groupLogo = ProjectLabels.groupLogoUrl(p['groupSlug']?.toString());
    final cover = p['coverImageUrl']?.toString() ?? '';
    final images = ((p['imageUrls'] as List?) ?? []).map((e) => e.toString()).toList();
    final image = cover.isNotEmpty ? cover : (images.isNotEmpty ? images.first : '');
    final description = ProjectLabels.plainText(p['description']?.toString() ?? '');
    final returnLabel = ProjectLabels.returnLabel(_num(p['returnMin']), _num(p['returnMax']));
    final duration = (p['durationDays'] as num?)?.toInt() ?? 0;
    final minInv = _num(p['minInvestmentBdt']);
    final deadlineDays = (p['deadlineDays'] as num?)?.toInt();

    Future<void> openDetail() async {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProjectDetailPage(projectIdOrSlug: p['id'].toString())),
      );
      if (mounted) _loadProjectsData();
    }

    return GestureDetector(
      onTap: openDetail,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Chobi + badge
            SizedBox(
              height: 170,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  image.isEmpty ? _coverPlaceholder() : _blurredImage(image),
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _overlayPill(
                              text: catLabel.toUpperCase(),
                              icon: ProjectLabels.categoryIcon(cat),
                              bg: Colors.black.withAlpha(115),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _statusBadge(status),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Row(
                      children: [
                        if (groupName.isNotEmpty)
                          Flexible(child: _groupPill(groupName, groupLogo))
                        else if (location.isNotEmpty)
                          Flexible(
                            child: _overlayPill(
                              text: location,
                              icon: Icons.location_on_outlined,
                              bg: Colors.black.withAlpha(128),
                            ),
                          ),
                        const Spacer(),
                        if (returnLabel != '—')
                          _overlayPill(
                            text: LanguageService.tr('$returnLabel ROI', '$returnLabel লাভ'),
                            icon: Icons.trending_up_rounded,
                            bg: const Color(0xFF022C22).withAlpha(217),
                            fg: const Color(0xFF6EE7B7),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (p['title']?.toString() ?? '').isEmpty ? '—' : p['title'].toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink, height: 1.3),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: muted, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // ── Kotota uthlo
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: ProjectLabels.bdtCard(funded),
                                style: const TextStyle(fontWeight: FontWeight.w700, color: ink),
                              ),
                              TextSpan(
                                text: LanguageService.tr(
                                    ' raised of ${ProjectLabels.bdtCard(goal)}', ' উঠেছে, লক্ষ্য ${ProjectLabels.bdtCard(goal)}'),
                                style: const TextStyle(color: muted),
                              ),
                            ],
                          ),
                          style: const TextStyle(fontSize: 12.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: emeraldSoft, borderRadius: BorderRadius.circular(6)),
                        child: Text('$pct%',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: emerald)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 6,
                      color: line,
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: pct / 100,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(colors: [emerald, emeraldBright]),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ── 3 ta tottho (website er KPI bento)
                  Row(
                    children: [
                      Expanded(
                        child: _kpi(
                          returnLabel,
                          p['returnType'] == 'FIXED_RETURN'
                              ? LanguageService.tr('FIXED RETURN', 'নির্দিষ্ট রিটার্ন')
                              : LanguageService.tr('EST. RETURN', 'আনুমানিক লাভ'),
                          highlight: true,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: _kpi(ProjectLabels.term(duration), LanguageService.tr('TERM', 'মেয়াদ'))),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _kpi(minInv > 0 ? ProjectLabels.bdtCard(minInv) : '—',
                            LanguageService.tr('MIN. ENTRY', 'সর্বনিম্ন')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: line),
                  const SizedBox(height: 10),
                  // ── Footer
                  Row(
                    children: [
                      if (status == 'FUNDRAISING') ...[
                        Icon(Icons.access_time_rounded,
                            size: 16, color: (deadlineDays ?? 0) < 0 ? BC.destructive : emerald),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            ProjectLabels.countdown(deadlineDays),
                            style: TextStyle(
                                fontSize: 12.5, color: (deadlineDays ?? 0) < 0 ? BC.destructive : muted),
                          ),
                        ),
                      ] else
                        Expanded(
                          child: Text(ProjectLabels.cardFooterStatus(status),
                              style: const TextStyle(fontSize: 12.5, color: muted)),
                        ),
                      const SizedBox(width: 8),
                      // Shob shomoy ekdom dane — project er bistarito / invest page e jay
                      FilledButton(
                        onPressed: openDetail,
                        style: FilledButton.styleFrom(
                          backgroundColor: emerald,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              LanguageService.tr('Be an Investor', 'বিনিয়োগ করুন'),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 5),
                            const Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                      ),
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

  /// Website er status badge: Active (sobuj) · Funded / Matured (neel) · Completed (dhusor) · Inactive (lal)
  Widget _statusBadge(String status) {
    final Color dot;
    final Color fg;
    final Color bg;
    switch (status) {
      case 'FUNDRAISING':
        dot = const Color(0xFF10B981);
        fg = const Color(0xFF6EE7B7);
        bg = const Color(0xFF022C22).withAlpha(217);
        break;
      case 'FUNDED':
      case 'ACTIVE':
        dot = const Color(0xFF60A5FA);
        fg = const Color(0xFF93C5FD);
        bg = const Color(0xFF172554).withAlpha(204);
        break;
      case 'COMPLETED':
        dot = const Color(0xFF94A3B8);
        fg = const Color(0xFFCBD5E1);
        bg = const Color(0xFF0F172A).withAlpha(204);
        break;
      default:
        dot = const Color(0xFFEF4444);
        fg = const Color(0xFFFCA5A5);
        bg = const Color(0xFF450A0A).withAlpha(204);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(ProjectLabels.cardStatus(status),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }

  Widget _overlayPill({required String text, required Color bg, IconData? icon, Color fg = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withAlpha(45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg == Colors.white ? const Color(0xFF34D399) : fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg, letterSpacing: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupPill(String name, String? logoUrl) {
    return Container(
      padding: const EdgeInsets.fromLTRB(3, 3, 8, 3),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(128),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logoUrl != null) ...[
            Container(
              width: 18,
              height: 18,
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
              child: Image.network(
                logoUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.apartment_rounded, size: 14, color: emerald),
              ),
            ),
            const SizedBox(width: 5),
          ] else ...[
            const Icon(Icons.apartment_rounded, size: 14, color: Color(0xFF34D399)),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String value, String label, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: highlight ? emeraldSoft : ivory,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: highlight ? emerald.withAlpha(40) : line),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (highlight) ...[
                  const Icon(Icons.trending_up_rounded, size: 14, color: emerald),
                  const SizedBox(width: 2),
                ],
                Text(value,
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800, color: highlight ? emerald : ink)),
              ],
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.6,
                    color: highlight ? emerald.withAlpha(200) : muted)),
          ),
        ],
      ),
    );
  }

  /// Chobi pura dekhay (contain); faka jaygay oi chobir-i jhapsa (blur) boro
  /// copy — kalo ar dekha jay na
  Widget _blurredImage(String url) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: Transform.scale(
            // Blur er kinara jeno faka na dekhay
            scale: 1.25,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        // Halka kalo porda — samner chobi ar badge gulo fute uthe
        Container(color: Colors.black.withAlpha(45)),
        Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _coverPlaceholder(),
        ),
      ],
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

  Widget _buildEmptyState() {
    final filtered = _search.isNotEmpty || _category != null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(color: emeraldSoft, shape: BoxShape.circle),
            child: const Icon(Icons.search_rounded, color: emerald, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            LanguageService.tr('No projects found', 'কোনো প্রজেক্ট পাওয়া যায়নি'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: ink),
          ),
          const SizedBox(height: 3),
          Text(
            filtered
                ? LanguageService.tr('Try adjusting your filters.', 'ফিল্টার বদলে দেখুন।')
                : LanguageService.tr(
                'New verified projects are currently undergoing due diligence and will launch soon.',
                'নতুন প্রজেক্ট যাচাই চলছে, শীঘ্রই আসবে।'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: muted),
          ),
          if (filtered) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                _searchCtrl.clear();
                setState(() {
                  _search = '';
                  _category = null;
                });
              },
              style: TextButton.styleFrom(foregroundColor: emerald),
              child: Text(LanguageService.tr('View all projects', 'সব প্রজেক্ট দেখুন')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 34, color: emerald),
            const SizedBox(height: 10),
            Text(
              LanguageService.tr('Could not load projects', 'প্রজেক্ট লোড করা যায়নি'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
            ),
            const SizedBox(height: 3),
            Text(
              LanguageService.tr('Please check your internet connection.', 'ইন্টারনেট সংযোগ চেক করুন।'),
              style: const TextStyle(fontSize: 12.5, color: muted),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _loadProjectsData,
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