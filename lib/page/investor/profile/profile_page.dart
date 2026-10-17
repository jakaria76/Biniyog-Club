import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/cloudinary_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // ─── Palette (dashboard er moto) ───
  static const Color emerald = Color(0xFF0E4A37);
  static const Color emeraldDeep = Color(0xFF0A3327);
  static const Color emeraldSoft = Color(0xFFE3F0E9);
  static const Color gold = Color(0xFFB8935A);
  static const Color goldDeep = Color(0xFF8A6A3A);
  static const Color goldLight = Color(0xFFD9BE8C);
  static const Color goldSoft = Color(0xFFF6EEDF);
  static const Color turquoise = Color(0xFF167A80);
  static const Color turquoiseSoft = Color(0xFFE0F1F1);
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
    final parts = [_v('address'), _v('city')]
        .where((s) => s.isNotEmpty)
        .toList();
    // Address er bhitore district age theke thakle dui bar dekhabo na
    final unique = <String>[];
    for (final p in parts) {
      if (!unique.any((u) => u.toLowerCase().contains(p.toLowerCase()))) unique.add(p);
    }
    return unique.join(', ');
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? danger : emerald),
    );
  }

  // ═════════════════════════════════════════════════════════
  // PHOTO
  // ═════════════════════════════════════════════════════════
  void _showPhotoSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        Widget option(IconData icon, Color color, Color soft, String label, ImageSource source) {
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              Navigator.pop(sheetContext);
              _processImagePick(source);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: soft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 21),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink),
                  ),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LanguageService.tr('Profile Photo', 'প্রোফাইল ছবি'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: ink),
                ),
                const SizedBox(height: 8),
                option(Icons.camera_alt_outlined, emerald, emeraldSoft,
                    LanguageService.tr('Take a photo', 'ক্যামেরা দিয়ে ছবি তুলুন'), ImageSource.camera),
                option(Icons.photo_library_outlined, lapis, lapisSoft,
                    LanguageService.tr('Choose from gallery', 'গ্যালারি থেকে বেছে নিন'), ImageSource.gallery),
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
        _snack(LanguageService.tr('Profile photo updated.', 'প্রোফাইল ছবি আপডেট হয়েছে।'));
      } else {
        _snack(res['message']?.toString() ??
            LanguageService.tr('Could not save photo.', 'ছবি সেভ করা যায়নি।'),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          LanguageService.tr('Remove photo', 'ছবি সরান'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: ink),
        ),
        content: Text(
          LanguageService.tr('Are you sure you want to remove your profile photo?',
              'আপনি কি প্রোফাইল ছবি সরাতে চান?'),
          style: const TextStyle(fontSize: 13.5, color: muted, height: 1.45),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      _snack(LanguageService.tr('Profile photo removed.', 'প্রোফাইল ছবি সরানো হয়েছে।'));
    } else {
      _snack(res['message']?.toString() ??
          LanguageService.tr('Could not remove photo.', 'ছবি সরানো যায়নি।'),
          error: true);
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
        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              LanguageService.tr('Profile', 'প্রোফাইল'),
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
            LanguageService.tr('Please log in to see your profile',
                'প্রোফাইল দেখতে লগইন করুন'),
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
            LanguageService.tr('Could not load your profile',
                'প্রোফাইল লোড করা যায়নি'),
            LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
            _loadProfileData,
          )
              : RefreshIndicator(
            onRefresh: _loadProfileData,
            color: emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 40),
              children: [
                _buildHeroCard(),
                const SizedBox(height: 24),
                _sectionHeader(LanguageService.tr('Contact', 'যোগাযোগ')),
                const SizedBox(height: 12),
                _buildContactCard(),
                const SizedBox(height: 24),
                _sectionHeader(LanguageService.tr('Personal Information', 'ব্যক্তিগত তথ্য')),
                const SizedBox(height: 12),
                _buildPersonalCard(),
                const SizedBox(height: 24),
                _sectionHeader(
                    LanguageService.tr('Investor Profile', 'বিনিয়োগকারী প্রোফাইল')),
                const SizedBox(height: 12),
                _buildInvestorCard(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Shared pieces ────────────────────────────────────────
  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [goldLight, gold]),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ink,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  Widget _card(List<Widget> rows) {
    final children = <Widget>[];
    for (int i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i != rows.length - 1) {
        children.add(const Divider(height: 1, thickness: 1, color: line, indent: 66));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(children: children),
    );
  }

  Widget _infoRow(IconData icon, Color color, Color soft, String label, String value) {
    final empty = value.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: muted,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  empty ? _notProvided : value,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: empty ? FontWeight.w500 : FontWeight.w600,
                    color: empty ? muted : ink,
                    fontStyle: empty ? FontStyle.italic : FontStyle.normal,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Hero ─────────────────────────────────────────────────
  Widget _buildHeroCard() {
    final displayName = _name.isEmpty ? LanguageService.tr('Investor', 'বিনিয়োগকারী') : _name;
    final initial = displayName[0].toUpperCase();
    final hasPhoto = _avatarUrl != null && _avatarUrl!.isNotEmpty;
    final busy = _isUploadingPhoto || _isDeletingPhoto;

    Widget initialAvatar() => Container(
      color: emerald,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w600),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
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
              child: CustomPaint(
                painter: _IslamicPatternPainter(color: Colors.white.withAlpha(16), cell: 44),
              ),
            ),
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: gold.withAlpha(80), width: 0.8),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                children: [
                  // Avatar + camera badge
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: gold, width: 1.6),
                        ),
                        child: ClipOval(
                          child: SizedBox(
                            width: 88,
                            height: 88,
                            child: busy
                                ? Container(
                              color: emerald,
                              alignment: Alignment.center,
                              child: const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                    color: goldLight, strokeWidth: 2.4),
                              ),
                            )
                                : hasPhoto
                                ? Image.network(
                              _avatarUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => initialAvatar(),
                            )
                                : initialAvatar(),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: GestureDetector(
                          onTap: busy ? null : _showPhotoSourceSheet,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(colors: [goldLight, gold]),
                              border: Border.all(color: emeraldDeep, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt_rounded, size: 15, color: emeraldDeep),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_memberSince != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      LanguageService.tr('Member since ${_fmtDate(_memberSince)}',
                          'সদস্য হয়েছেন ${_fmtDate(_memberSince)}'),
                      style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _heroButton(
                        icon: Icons.add_a_photo_outlined,
                        label: hasPhoto
                            ? LanguageService.tr('Change Photo', 'ছবি বদলান')
                            : LanguageService.tr('Add Photo', 'ছবি যোগ করুন'),
                        onTap: busy ? null : _showPhotoSourceSheet,
                      ),
                      if (hasPhoto) ...[
                        const SizedBox(width: 10),
                        _heroButton(
                          icon: Icons.delete_outline_rounded,
                          label: LanguageService.tr('Remove', 'সরান'),
                          onTap: busy ? null : _confirmDeletePhoto,
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

  Widget _heroButton({required IconData icon, required String label, VoidCallback? onTap}) {
    return Material(
      color: Colors.white.withAlpha(22),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(40)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Contact ──────────────────────────────────────────────
  Widget _buildContactCard() {
    return _card([
      _infoRow(Icons.mail_outline_rounded, lapis, lapisSoft,
          LanguageService.tr('Email', 'ইমেইল'), _email),
      _infoRow(Icons.phone_outlined, emerald, emeraldSoft,
          LanguageService.tr('Phone', 'ফোন'), _phone),
    ]);
  }

  // ─── Personal info (registration e ja diyeche) ───────────
  String _fmtDob(String raw) {
    final d = DateTime.tryParse(raw.trim());
    if (d == null) return '';
    return _fmtDate(DateTime(d.year, d.month, d.day));
  }

  Widget _buildPersonalCard() {
    final nominee = _v('nomineeNationalId').isEmpty
        ? ''
        : '${_pretty(_v('nomineeRelation')).isEmpty ? '' : '${_pretty(_v('nomineeRelation'))} · '}'
        'NID ${_mask(_v('nomineeNationalId'))}';

    return _card([
      _infoRow(Icons.cake_outlined, goldDeep, goldSoft,
          LanguageService.tr('Date of Birth', 'জন্ম তারিখ'), _fmtDob(_v('dateOfBirth'))),
      _infoRow(Icons.badge_outlined, lapis, lapisSoft,
          LanguageService.tr('National ID', 'জাতীয় পরিচয়পত্র'), _mask(_v('nationalId'))),
      _infoRow(Icons.location_on_outlined, terracotta, terracottaSoft,
          LanguageService.tr('Address', 'ঠিকানা'), _fullAddress),
      _infoRow(Icons.supervisor_account_outlined, emerald, emeraldSoft,
          LanguageService.tr('Nominee', 'নমিনি'), nominee),
    ]);
  }

  // ─── Investor profile (DB te ja ache) ─────────────────────
  Widget _buildInvestorCard() {
    final rows = [
      (Icons.work_outline_rounded, terracotta, terracottaSoft,
      LanguageService.tr('Occupation', 'পেশা'), _pretty(_v('occupation'))),
      (Icons.location_city_rounded, emerald, emeraldSoft,
      LanguageService.tr('City / District', 'শহর / জেলা'), _v('city')),
      (Icons.public_rounded, lapis, lapisSoft,
      LanguageService.tr('Country', 'দেশ'), _pretty(_v('country'))),
      (Icons.account_balance_wallet_outlined, goldDeep, goldSoft,
      LanguageService.tr('Annual Income Range', 'বার্ষিক আয়ের সীমা'), _pretty(_v('annualIncomeRange'))),
      (Icons.trending_up_rounded, turquoise, turquoiseSoft,
      LanguageService.tr('Investment Experience', 'বিনিয়োগের অভিজ্ঞতা'), _pretty(_v('investmentExperience'))),
      (Icons.speed_rounded, terracotta, terracottaSoft,
      LanguageService.tr('Risk Tolerance', 'ঝুঁকি সহনশীলতা'), _pretty(_v('riskTolerance'))),
    ];

    final allEmpty = rows.every((r) => r.$5.isEmpty);

    if (allEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: line),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: muted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                LanguageService.tr('No investor profile details have been added yet.',
                    'এখনো কোনো বিনিয়োগকারী প্রোফাইল তথ্য যোগ করা হয়নি।'),
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
            Icon(icon, size: 40, color: goldDeep),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
            ),
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