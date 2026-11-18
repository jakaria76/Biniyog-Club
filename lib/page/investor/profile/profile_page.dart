import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/cloudinary_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import '../dashboard/investor_dashboard_page.dart';
import 'edit_profile_page.dart';
import '../../../theme/app_colors.dart';
import 'withdrawal_account_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // ─── Palette (dashboard er moto) ───
  static const Color emerald = BC.primary;
  static const Color emeraldBright = BC.brand500;
  static const Color emeraldSoft = BC.secondary;
  // Sonali nei — "baki" bojhate website er chart-4
  static const Color pendingTone = BC.chart4Deep;
  static const Color turquoise = BC.chart4;
  static const Color turquoiseSoft = BC.chart4Muted;
  static const Color lapis = BC.finance600;
  static const Color lapisSoft = BC.finance50;
  static const Color terracotta = BC.destructive;
  static const Color terracottaSoft = BC.destructiveMuted;
  static const Color amethyst = BC.info;
  static const Color amethystSoft = BC.infoMuted;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color danger = BC.destructive;
  static const Color dangerSoft = BC.destructiveMuted;

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  bool _isLoading = true;
  bool _needsLogin = false;
  bool _loadFailed = false;
  bool _isUploadingPhoto = false;
  bool _isDeletingPhoto = false;

  String _userId = '';
  String _name = '';
  String _email = '';
  String _phone = '';
  String? _avatarUrl;
  DateTime? _memberSince;

  /// DB te ja ache tai — khali hole ''
  Map<String, String> _p = {};

  /// Edit page e pathanor jonno getUserProfileFull er pura result
  Map<String, dynamic> _profile = {};

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  // ═════════════════════════════════════════════════════════
  // DATA
  // ═════════════════════════════════════════════════════════
  Future<void> _loadProfileData() async {
    if (mounted) setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    final userEmail = userData?['email']?.toString() ?? '';

    if (userId.isEmpty) {
      if (mounted) {
        setState(() {
          _needsLogin = true;
          _isLoading = false;
        });
      }
      return;
    }

    Map<String, dynamic> profile = {};
    try {
      profile = await DatabaseService.getUserProfileFull(userId, email: userEmail);
    } catch (e) {
      debugPrint('Profile load error: $e');
    }

    if (!mounted) return;
    setState(() {
      if (profile.isEmpty) {
        _loadFailed = true;
      } else {
        _loadFailed = false;
        _profile = profile;
        _userId = profile['id']?.toString() ?? userId;
        _name = profile['name']?.toString() ?? '';
        _email = profile['email']?.toString() ?? '';
        _phone = profile['phone']?.toString() ?? '';
        _avatarUrl = profile['avatarUrl']?.toString();
        _memberSince = DateTime.tryParse(profile['createdAt']?.toString() ?? '')?.toLocal();

        final raw = (profile['investorProfile'] as Map?) ?? {};
        _p = raw.map((k, v) => MapEntry(k.toString(), v?.toString().trim() ?? ''));
      }
      _needsLogin = false;
      _isLoading = false;
    });
  }

  // ═════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════
  String _v(String key) => _p[key] ?? '';

  String get _notProvided => LanguageService.tr('Not provided', 'দেওয়া হয়নি');

  /// Shudhu shesh 4 digit
  String _mask(String value) {
    final v = value.replaceAll(' ', '');
    if (v.isEmpty) return '';
    if (v.length <= 4) return v;
    return '•••• ${v.substring(v.length - 4)}';
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '';
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// DB te enum ba code thakle sundor kore dekhai: "BD" → Bangladesh, "SOME_VALUE" → Some Value
  String _pretty(String value) {
    if (value.isEmpty) return '';
    if (value.toUpperCase() == 'BD') return LanguageService.tr('Bangladesh', 'বাংলাদেশ');
    if (!value.contains('_') && value != value.toUpperCase()) return value;
    return value
        .toLowerCase()
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String get _fullAddress {
    final parts = [_v('address'), _v('city')].where((s) => s.isNotEmpty).toList();
    // Address er bhitore district age theke thakle dui bar dekhabo na
    final unique = <String>[];
    for (final p in parts) {
      if (!unique.any((u) => u.toLowerCase().contains(p.toLowerCase()))) unique.add(p);
    }
    return unique.join(', ');
  }

  String _fmtDob(String raw) {
    final d = DateTime.tryParse(raw.trim());
    if (d == null) return '';
    return _fmtDate(DateTime(d.year, d.month, d.day));
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? danger : emerald),
    );
  }

  /// Dorkari 5 ta tottho — kotogulo deya hoyeche (progress bar er jonno)
  List<(String, bool)> get _checklist => [
    (LanguageService.tr('Email', 'ইমেইল'), _email.isNotEmpty),
    (LanguageService.tr('Date of birth', 'জন্ম তারিখ'), _v('dateOfBirth').isNotEmpty),
    (LanguageService.tr('NID', 'এনআইডি'), _v('nationalId').isNotEmpty),
    (LanguageService.tr('Address', 'ঠিকানা'), _v('address').isNotEmpty),
    (LanguageService.tr('Nominee', 'নমিনী'), _v('nomineeNationalId').isNotEmpty),
  ];

  // ═════════════════════════════════════════════════════════
  // PHOTO
  // ═════════════════════════════════════════════════════════
  void _showPhotoSheet() {
    final hasPhoto = _avatarUrl != null && _avatarUrl!.isNotEmpty;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        Widget option(IconData icon, Color color, Color soft, String label, VoidCallback onTap) {
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.pop(sheetContext);
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, color: color, size: 17),
                  ),
                  const SizedBox(width: 12),
                  Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color == danger ? danger : ink)),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  LanguageService.tr('Profile photo', 'প্রোফাইল ছবি'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
                ),
                const SizedBox(height: 6),
                option(Icons.camera_alt_outlined, emerald, emeraldSoft,
                    LanguageService.tr('Take a photo', 'ক্যামেরা দিয়ে ছবি তুলুন'), () => _processImagePick(ImageSource.camera)),
                option(Icons.photo_library_outlined, emerald, emeraldSoft,
                    LanguageService.tr('Choose from gallery', 'গ্যালারি থেকে বেছে নিন'),
                        () => _processImagePick(ImageSource.gallery)),
                if (hasPhoto)
                  option(Icons.delete_outline_rounded, danger, dangerSoft,
                      LanguageService.tr('Remove photo', 'ছবি সরান'), _confirmDeletePhoto),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _processImagePick(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image == null) return;

      setState(() => _isUploadingPhoto = true);
      final bytes = await image.readAsBytes();
      final url = await CloudinaryService.uploadImage(bytes, folder: 'avatars');

      if (url == null || url.isEmpty) {
        if (mounted) setState(() => _isUploadingPhoto = false);
        _snack(
          LanguageService.tr('Photo upload failed. Please check your internet and try again.',
              'ছবি আপলোড হয়নি। ইন্টারনেট চেক করে আবার চেষ্টা করুন।'),
          error: true,
        );
        return;
      }

      final res = await DatabaseService.updateUserAvatar(userId: _userId, avatarUrl: url);
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);

      if (res['success'] == true) {
        setState(() => _avatarUrl = res['avatarUrl']?.toString() ?? url);
        final userData = await AuthService.getUserData();
        if (userData != null) {
          userData['avatarUrl'] = _avatarUrl;
          await AuthService.saveUserData(userData);
        }
        InvestorDashboardPage.clearCache(); // dashboard er chobi o notun
        _snack(LanguageService.tr('Profile photo updated.', 'প্রোফাইল ছবি আপডেট হয়েছে।'));
      } else {
        _snack(res['message']?.toString() ?? LanguageService.tr('Could not save photo.', 'ছবি সেভ করা যায়নি।'),
            error: true);
      }
    } catch (e) {
      debugPrint('Photo pick error: $e');
      if (mounted) setState(() => _isUploadingPhoto = false);
      _snack(
        source == ImageSource.camera
            ? LanguageService.tr('Could not open the camera.', 'ক্যামেরা খোলা যায়নি।')
            : LanguageService.tr('Could not open the gallery.', 'গ্যালারি খোলা যায়নি।'),
        error: true,
      );
    }
  }

  void _confirmDeletePhoto() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          LanguageService.tr('Remove photo', 'ছবি সরান'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: ink),
        ),
        content: Text(
          LanguageService.tr('Are you sure you want to remove your profile photo?', 'আপনি কি প্রোফাইল ছবি সরাতে চান?'),
          style: const TextStyle(fontSize: 14, color: muted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(LanguageService.tr('Cancel', 'বাতিল'),
                style: const TextStyle(color: muted, fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deletePhoto();
            },
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(LanguageService.tr('Remove', 'সরান')),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePhoto() async {
    setState(() => _isDeletingPhoto = true);
    final res = await DatabaseService.deleteUserAvatar(_userId);
    if (!mounted) return;
    setState(() => _isDeletingPhoto = false);

    if (res['success'] == true) {
      setState(() => _avatarUrl = null);
      final userData = await AuthService.getUserData();
      if (userData != null) {
        userData['avatarUrl'] = null;
        await AuthService.saveUserData(userData);
      }
      InvestorDashboardPage.clearCache();
      _snack(LanguageService.tr('Profile photo removed.', 'প্রোফাইল ছবি সরানো হয়েছে।'));
    } else {
      _snack(res['message']?.toString() ?? LanguageService.tr('Could not remove photo.', 'ছবি সরানো যায়নি।'),
          error: true);
    }
  }

  // ═════════════════════════════════════════════════════════
  // EDIT — page e ekta-i edit button (app bar e)
  // ═════════════════════════════════════════════════════════
  Future<void> _openEdit() async {
    if (_profile.isEmpty) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditProfilePage(profile: _profile)),
    );
    if (saved == true && mounted) {
      InvestorDashboardPage.clearCache(); // dashboard e notun nam
      _loadProfileData();
    }
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        final ready = !_isLoading && !_needsLogin && !_loadFailed;
        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 54,
            iconTheme: const IconThemeData(color: ink),
            // Back button — page push kore khulle pichone jay; dashboard er tab hole
            // dashboard er PopScope dhore Home tab e fire ashe
            leading: IconButton(
              tooltip: LanguageService.tr('Back', 'পিছনে'),
              icon: const Icon(Icons.arrow_back_rounded, color: ink, size: 22),
              onPressed: () => Navigator.maybePop(context),
            ),
            title: Text(
              LanguageService.tr('My Profile', 'আমার প্রোফাইল'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 17.5),
            ),
            actions: [
              if (ready)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                      side: const BorderSide(color: line),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: _openEdit,
                      child: const SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(Icons.edit_outlined, size: 17, color: emerald),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: _isLoading
              ? const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4),
            ),
          )
              : _needsLogin
              ? _buildMessage(
            Icons.lock_outline_rounded,
            LanguageService.tr('Please log in to see your profile', 'প্রোফাইল দেখতে লগইন করুন'),
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
            LanguageService.tr('Could not load your profile', 'প্রোফাইল লোড করা যায়নি'),
            LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
            _loadProfileData,
          )
              : RefreshIndicator(
            onRefresh: _loadProfileData,
            color: emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              // dashboard er curved navbar er jonno niche jayga
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 104),
              children: [
                _buildHeroCard(),
                const SizedBox(height: 12),
                _buildCompletionCard(),
                const SizedBox(height: 18),
                _sectionLabel(LanguageService.tr('CONTACT', 'যোগাযোগ')),
                _buildContactCard(),
                const SizedBox(height: 16),
                _sectionLabel(LanguageService.tr('PERSONAL INFORMATION', 'ব্যক্তিগত তথ্য')),
                _buildPersonalCard(),
                const SizedBox(height: 16),
                _sectionLabel(LanguageService.tr('INVESTOR PROFILE', 'বিনিয়োগকারী প্রোফাইল')),
                _buildInvestorCard(),
                const SizedBox(height: 16),
                // Website er profile "Withdrawal account"
                _sectionLabel(LanguageService.tr('WITHDRAWAL ACCOUNT', 'উত্তোলনের অ্যাকাউন্ট')),
                const WithdrawalAccountCard(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Hero: chobi + nam + member since ─────────────────────
  Widget _buildHeroCard() {
    final displayName = _name.isEmpty ? LanguageService.tr('Investor', 'বিনিয়োগকারী') : _name;
    final initial = displayName[0].toUpperCase();
    final hasPhoto = _avatarUrl != null && _avatarUrl!.isNotEmpty;
    final busy = _isUploadingPhoto || _isDeletingPhoto;

    Widget initialAvatar() => Container(
      color: emerald,
      alignment: Alignment.center,
      child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w700)),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: emerald.withAlpha(55), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
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
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(
                  children: [
                    // Avatar — chaple chobi bodlano / sorano
                    GestureDetector(
                      onTap: busy ? null : _showPhotoSheet,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withAlpha(200), width: 1.4),
                            ),
                            child: ClipOval(
                              child: SizedBox(
                                width: 58,
                                height: 58,
                                child: busy
                                    ? Container(
                                  color: emerald,
                                  alignment: Alignment.center,
                                  child: const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  ),
                                )
                                    : hasPhoto
                                    ? Image.network(_avatarUrl!,
                                    fit: BoxFit.cover, errorBuilder: (_, __, ___) => initialAvatar())
                                    : initialAvatar(),
                              ),
                            ),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(color: emerald, width: 1.6),
                              ),
                              child: const Icon(Icons.camera_alt_rounded, size: 12, color: emerald),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          if (_phone.isNotEmpty || _email.isNotEmpty)
                            Text(
                              _phone.isNotEmpty ? _phone : _email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white.withAlpha(190), fontSize: 12.5),
                            ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _heroChip(Icons.verified_user_outlined, LanguageService.tr('Investor', 'বিনিয়োগকারী')),
                              if (_memberSince != null)
                                _heroChip(
                                  Icons.event_available_outlined,
                                  LanguageService.tr('Since ${_months[_memberSince!.month - 1]} ${_memberSince!.year}',
                                      '${_months[_memberSince!.month - 1]} ${_memberSince!.year} থেকে'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }

  // ─── Profile completion — ki baki ache, ek nojore ─────────
  Widget _buildCompletionCard() {
    final items = _checklist;
    final done = items.where((e) => e.$2).length;
    final total = items.length;
    final complete = done == total;
    final color = complete ? emeraldBright : pendingTone;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: complete ? null : _openEdit,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: complete ? emeraldBright.withAlpha(70) : pendingTone.withAlpha(90)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(complete ? Icons.verified_rounded : Icons.assignment_ind_outlined, size: 16, color: color),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      complete
                          ? LanguageService.tr('Profile complete', 'প্রোফাইল সম্পূর্ণ')
                          : LanguageService.tr('Complete your profile', 'প্রোফাইল সম্পূর্ণ করুন'),
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink),
                    ),
                  ),
                  Text('$done/$total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total,
                  minHeight: 5,
                  backgroundColor: BC.muted,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final it in items)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: it.$2 ? emeraldSoft : ivory,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: it.$2 ? Colors.transparent : line),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(it.$2 ? Icons.check_rounded : Icons.add_rounded, size: 13, color: it.$2 ? emerald : muted),
                          const SizedBox(width: 3),
                          Text(it.$1,
                              style: TextStyle(
                                  fontSize: 11.5, fontWeight: FontWeight.w600, color: it.$2 ? emerald : muted)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Shared pieces ────────────────────────────────────────
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
      child: Row(
        children: [
          Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(color: emerald),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: emerald, letterSpacing: 1.1),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> rows) {
    final children = <Widget>[];
    for (int i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i != rows.length - 1) {
        children.add(const Divider(height: 1, thickness: 1, color: line, indent: 56));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line),
      ),
      child: Column(children: children),
    );
  }

  Widget _infoRow(IconData icon, Color color, Color soft, String label, String value) {
    final empty = value.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: muted),
                ),
                const SizedBox(height: 1),
                Text(
                  empty ? _notProvided : value,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: empty ? FontWeight.w500 : FontWeight.w600,
                    color: empty ? muted.withAlpha(170) : ink,
                    fontStyle: empty ? FontStyle.italic : FontStyle.normal,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Contact ──────────────────────────────────────────────
  Widget _buildContactCard() {
    return _card([
      _infoRow(Icons.phone_outlined, emerald, emeraldSoft, LanguageService.tr('Phone', 'ফোন'), _phone),
      _infoRow(Icons.mail_outline_rounded, emerald, emeraldSoft, LanguageService.tr('Email', 'ইমেইল'), _email),
    ]);
  }

  // ─── Personal info ────────────────────────────────────────
  Widget _buildPersonalCard() {
    final nominee = [
      _v('nomineeName'),
      _pretty(_v('nomineeRelation')),
      if (_v('nomineeNationalId').isNotEmpty) 'NID ${_mask(_v('nomineeNationalId'))}',
    ].where((s) => s.isNotEmpty).join(' · ');

    return _card([
      _infoRow(Icons.cake_outlined, emerald, emeraldSoft, LanguageService.tr('Date of birth', 'জন্ম তারিখ'),
          _fmtDob(_v('dateOfBirth'))),
      _infoRow(Icons.badge_outlined, emerald, emeraldSoft, LanguageService.tr('National ID', 'জাতীয় পরিচয়পত্র'),
          _mask(_v('nationalId'))),
      _infoRow(Icons.location_on_outlined, emerald, emeraldSoft, LanguageService.tr('Address', 'ঠিকানা'),
          _fullAddress),
      _infoRow(Icons.family_restroom_outlined, emerald, emeraldSoft, LanguageService.tr('Nominee', 'নমিনী'), nominee),
    ]);
  }

  // ─── Investor profile ─────────────────────────────────────
  Widget _buildInvestorCard() {
    final rows = [
      (Icons.work_outline_rounded, emerald, emeraldSoft, LanguageService.tr('Occupation', 'পেশা'),
      _pretty(_v('occupation'))),
      (Icons.public_rounded, emerald, emeraldSoft, LanguageService.tr('Country', 'দেশ'), _pretty(_v('country'))),
      (Icons.account_balance_wallet_outlined, emerald, emeraldSoft,
      LanguageService.tr('Annual income', 'বার্ষিক আয়'), _pretty(_v('annualIncomeRange'))),
      (Icons.trending_up_rounded, emerald, emeraldSoft,
      LanguageService.tr('Investment experience', 'বিনিয়োগের অভিজ্ঞতা'), _pretty(_v('investmentExperience'))),
      (Icons.speed_rounded, emerald, emeraldSoft, LanguageService.tr('Risk tolerance', 'ঝুঁকি সহনশীলতা'),
      _pretty(_v('riskTolerance'))),
    ];

    if (rows.every((r) => r.$5.isEmpty)) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: line),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: muted, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                LanguageService.tr('No investor profile details yet. Tap the edit icon to add them.',
                    'এখনো কোনো তথ্য যোগ করা হয়নি। যোগ করতে উপরের এডিট আইকনে চাপুন।'),
                style: const TextStyle(fontSize: 12.5, color: muted, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    // Khali value hole _infoRow nijei "Not provided" dekhay
    return _card(rows.map((r) => _infoRow(r.$1, r.$2, r.$3, r.$4, r.$5)).toList());
  }

  Widget _buildMessage(IconData icon, String text, String buttonLabel, VoidCallback onTap) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: emerald),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}