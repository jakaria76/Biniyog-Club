import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../kyc/kyc_page.dart';
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
  bool _isLoading = true;
  bool _isUploadingPhoto = false;
  bool _isDeletingPhoto = false;

  String _userId = '';
  String _name = 'Investor';
  String _email = '';
  String _phone = 'N/A';
  String? _avatarUrl;
  bool _isEmailVerified = false;
  bool _isPhoneVerified = false;
  String _memberSince = 'Recent';
  String _kycStatus = 'NOT_STARTED';

  Map<String, String> _investorProfile = {
    'City': 'Dhaka',
    'District': 'Dhaka',
    'Country': 'Bangladesh',
    'Occupation': 'Investor',
    'Annual Income Range': 'Standard',
    'Investment Experience': 'Intermediate',
    'Risk Tolerance': 'Moderate',
    'Address': 'Bangladesh',
  };

  final ImagePicker _picker = ImagePicker();

  static const Color primaryTeal = Color(0xFF047857);
  static const Color primaryDarkTeal = Color(0xFF064E3B);

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    final userEmail = userData?['email']?.toString() ?? '';

    final profileData =
        await DatabaseService.getUserProfileFull(userId, email: userEmail);

    if (mounted) {
      setState(() {
        if (profileData.isNotEmpty) {
          _userId = profileData['id']?.toString() ?? userId;
          _name = profileData['name']?.toString() ?? 'Investor';
          _email = profileData['email']?.toString() ?? '';
          _phone = profileData['phone']?.toString() ?? 'N/A';
          _avatarUrl = profileData['avatarUrl']?.toString();
          _isEmailVerified = (profileData['emailVerified'] as bool? ?? false);
          _isPhoneVerified = (profileData['phoneVerified'] as bool? ?? false);
          _kycStatus =
              (profileData['kycStatus']?.toString() ?? 'NOT_STARTED')
                  .toUpperCase();

          final rawCreated = profileData['createdAt']?.toString() ?? '';
          if (rawCreated.length >= 10) {
            _memberSince = rawCreated.substring(0, 10);
          }

          final profMap =
              profileData['investorProfile'] as Map<String, dynamic>? ?? {};
          if (profMap.isNotEmpty) {
            _investorProfile = {
              'City': profMap['city']?.toString() ?? 'Dhaka',
              'District': profMap['city']?.toString() ?? 'Dhaka',
              'Country': profMap['country']?.toString() ?? 'BD',
              'Occupation': profMap['occupation']?.toString() ?? 'Investor',
              'Annual Income Range':
                  profMap['annualIncomeRange']?.toString() ?? 'Standard',
              'Investment Experience':
                  profMap['investmentExperience']?.toString() ??
                      'Intermediate',
              'Risk Tolerance':
                  profMap['riskTolerance']?.toString() ?? 'Moderate',
              'Address': profMap['address']?.toString() ?? 'Bangladesh',
            };
          }
        }
        _isLoading = false;
      });
    }
  }

  // Pick Image & Upload to Cloudinary API and save in Neon DB
  Future<void> _pickAndUploadImage() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                LanguageService.tr(
                    'Choose Profile Photo Source', 'ছবি তোলার মাধ্যম বেছে নিন'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined,
                    color: primaryTeal),
                title: Text(LanguageService.tr(
                    'Take Photo with Camera', 'ক্যামেরা দিয়ে ছবি তুলুন')),
                onTap: () {
                  Navigator.pop(context);
                  _processImagePick(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined,
                    color: primaryTeal),
                title: Text(LanguageService.tr(
                    'Choose from Gallery', 'গ্যালারি থেকে ছবি সিলেক্ট করুন')),
                onTap: () {
                  Navigator.pop(context);
                  _processImagePick(ImageSource.gallery);
                },
              ),
            ],
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

      // Upload to Cloudinary
      final cloudinaryUrl =
          await CloudinaryService.uploadImage(bytes, folder: 'avatars');

      if (cloudinaryUrl == null || cloudinaryUrl.isEmpty) {
        if (mounted) {
          setState(() => _isUploadingPhoto = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cloudinary Upload Failed. Check internet.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      // Save in Neon PostgreSQL DB
      final res = await DatabaseService.updateUserAvatar(
        userId: _userId,
        avatarUrl: cloudinaryUrl,
      );

      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);

      if (res['success'] == true) {
        setState(() {
          _avatarUrl = res['avatarUrl']?.toString() ?? cloudinaryUrl;
        });

        final userData = await AuthService.getUserData();
        if (userData != null) {
          userData['avatarUrl'] = _avatarUrl;
          await AuthService.saveUserData(userData);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LanguageService.tr(
                  'Profile photo updated!', 'প্রোফাইল ছবি সফলভাবে সেভ হয়েছে!')),
              backgroundColor: primaryTeal,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(res['message'] ?? 'Failed to update photo in Neon DB.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // Delete Profile Avatar
  Future<void> _handleDeletePhoto() async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(LanguageService.tr('Remove Photo', 'ছবি রিমুভ করুন')),
          content: Text(LanguageService.tr(
              'Are you sure you want to remove your profile photo?',
              'আপনি কি নিশ্চিত যে আপনার প্রোফাইল পিকচার রিমুভ করতে চান?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(LanguageService.tr('Cancel', 'বাতিল'),
                  style: const TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                setState(() => _isDeletingPhoto = true);

                final res = await DatabaseService.deleteUserAvatar(_userId);

                if (!mounted) return;
                setState(() => _isDeletingPhoto = false);

                if (res['success'] == true) {
                  setState(() {
                    _avatarUrl = null;
                  });

                  final userData = await AuthService.getUserData();
                  if (userData != null) {
                    userData['avatarUrl'] = null;
                    await AuthService.saveUserData(userData);
                  }

                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(LanguageService.tr(
                          'Profile photo removed.', 'প্রোফাইল ছবি রিমুভ হয়েছে।')),
                      backgroundColor: primaryTeal,
                    ),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(res['message'] ?? 'Failed to remove.'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: Text(LanguageService.tr('Remove', 'রিমুভ করুন')),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String initial = _name.isNotEmpty ? _name[0].toUpperCase() : 'I';

    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F7F6),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.5,
            iconTheme: const IconThemeData(color: primaryTeal),
            title: Text(
              LanguageService.tr('Profile', 'প্রোফাইল'),
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: primaryTeal))
              : RefreshIndicator(
                  onRefresh: _loadProfileData,
                  color: primaryTeal,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Colorful Gradient Hero Avatar Banner Card
                        _buildColorfulHeroCard(initial),
                        const SizedBox(height: 18),

                        // 2. Email & Phone Colorful Contact Row
                        _buildColorfulContactRow(),
                        const SizedBox(height: 18),

                        // 3. Colorful KYC Status Banner
                        _buildColorfulKycBanner(),
                        const SizedBox(height: 18),

                        // 4. Colorful Bento Grid for Investor Details
                        _buildColorfulInvestorBentoGrid(),
                        const SizedBox(height: 18),

                        // 5. KYC Verified Information Card
                        _buildKycDetailsCard(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  // 1. Vibrant Gradient Hero Card
  Widget _buildColorfulHeroCard(String initial) {
    final bool isKycVerified =
        _kycStatus == 'VERIFIED' || _kycStatus == 'APPROVED';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF064E3B),
            Color(0xFF047857),
            Color(0xFF0D9488),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryDarkTeal.withAlpha(80),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              // Glowing Outer Avatar Ring
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isKycVerified
                        ? const [Color(0xFFF59E0B), Color(0xFF10B981)]
                        : [Colors.teal.shade300, Colors.teal.shade700],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isKycVerified ? Colors.amber : Colors.teal)
                          .withAlpha(100),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: ClipOval(
                    child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                        ? Image.network(
                            _avatarUrl!,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildInitialAvatar(initial),
                          )
                        : _buildInitialAvatar(initial),
                  ),
                ),
              ),

              // Camera Action Badge
              Positioned(
                bottom: 2,
                right: 2,
                child: GestureDetector(
                  onTap: _isUploadingPhoto ? null : _pickAndUploadImage,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        color: Colors.white, size: 15),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // User Name & Verified Icon Badge (ONLY if KYC is Verified!)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              if (isKycVerified) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified_rounded,
                    color: Colors.amberAccent, size: 20),
              ],
            ],
          ),
          const SizedBox(height: 4),

          // Member Since Translucent Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(35),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isKycVerified ? Icons.star_rounded : Icons.person_outline_rounded,
                  color: isKycVerified ? Colors.amberAccent : Colors.white70,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  isKycVerified
                      ? '${LanguageService.tr("Verified Investor", "ভেরিফাইড ইনভেস্টর")} · $_memberSince'
                      : '${LanguageService.tr("Investor", "ইনভেস্টর")} · $_memberSince',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Translucent Photo Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _isUploadingPhoto ? null : _pickAndUploadImage,
                icon: _isUploadingPhoto
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_a_photo_outlined, size: 14),
                label: Text(
                  _isUploadingPhoto
                      ? 'Uploading...'
                      : LanguageService.tr('Change Photo', 'ছবি পরিবর্তন'),
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withAlpha(45),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (_avatarUrl != null && _avatarUrl!.isNotEmpty) ...[
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _isDeletingPhoto ? null : _handleDeletePhoto,
                  icon: _isDeletingPhoto
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.delete_outline_rounded,
                          size: 14, color: Colors.redAccent),
                  label: Text(
                    _isDeletingPhoto
                        ? 'Removing...'
                        : LanguageService.tr('Remove', 'রিমুভ'),
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.redAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInitialAvatar(String initial) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF047857), Color(0xFF0D9488)],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // 2. Colorful Contact Row (Email & Phone)
  Widget _buildColorfulContactRow() {
    return Row(
      children: [
        // Email Card (Soft Purple/Indigo)
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDDD6FE)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF7C3AED),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.email_rounded, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(LanguageService.tr('Email', 'ইমেইল'),
                          style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF6B21A8),
                              fontWeight: FontWeight.bold)),
                      Text(
                        _email,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4C1D95)),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _isEmailVerified
                      ? Icons.check_circle_rounded
                      : Icons.check_circle_outline_rounded,
                  color: const Color(0xFF7C3AED),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Phone Card (Soft Blue/Cyan)
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0284C7),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.phone_rounded, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(LanguageService.tr('Phone', 'ফোন'),
                          style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF0369A1),
                              fontWeight: FontWeight.bold)),
                      Text(
                        _phone,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0C4A6E)),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _isPhoneVerified
                      ? Icons.check_circle_rounded
                      : Icons.check_circle_outline_rounded,
                  color: const Color(0xFF0284C7),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 3. Colorful KYC Banner Card
  Widget _buildColorfulKycBanner() {
    final bool isVerified =
        _kycStatus == 'VERIFIED' || _kycStatus == 'APPROVED';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isVerified ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color:
              isVerified ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isVerified
                      ? const Color(0xFF059669)
                      : const Color(0xFFD97706),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LanguageService.tr('KYC Verification Status',
                        'কেওয়াইসি ভেরিফিকেশন স্ট্যাটাস'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isVerified
                          ? const Color(0xFF065F46)
                          : const Color(0xFF92400E),
                    ),
                  ),
                  Text(
                    _kycStatus,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isVerified
                          ? const Color(0xFF047857)
                          : const Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
            ],
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const KycPage()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isVerified
                  ? const Color(0xFF047857)
                  : const Color(0xFFD97706),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              LanguageService.tr('Manage KYC →', 'কেওয়াইসি ম্যানেজ করুন →'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // 4. Colorful Bento Grid for Investor Details
  Widget _buildColorfulInvestorBentoGrid() {
    final bentoCards = [
      {
        'title': LanguageService.tr('Occupation', 'পেশা'),
        'val': _investorProfile['Occupation'] ?? 'Investor',
        'icon': Icons.work_outline_rounded,
        'bg': const Color(0xFFFFF7ED),
        'border': const Color(0xFFFFEDD5),
        'iconBg': const Color(0xFFEA580C),
        'textCol': const Color(0xFF9A3412),
      },
      {
        'title': LanguageService.tr('District / City', 'জেলা / শহর'),
        'val': _investorProfile['City'] ?? 'Dhaka',
        'icon': Icons.location_city_rounded,
        'bg': const Color(0xFFECFDF5),
        'border': const Color(0xFFA7F3D0),
        'iconBg': const Color(0xFF059669),
        'textCol': const Color(0xFF065F46),
      },
      {
        'title': LanguageService.tr('Country', 'দেশ'),
        'val': _investorProfile['Country'] ?? 'BD',
        'icon': Icons.public_rounded,
        'bg': const Color(0xFFFFF1F2),
        'border': const Color(0xFFFECDD3),
        'iconBg': const Color(0xFFE11D48),
        'textCol': const Color(0xFF9F1239),
      },
      {
        'title': LanguageService.tr('Annual Income', 'বার্ষিক আয়'),
        'val': _investorProfile['Annual Income Range'] ?? 'Standard',
        'icon': Icons.account_balance_wallet_outlined,
        'bg': const Color(0xFFEEF2FF),
        'border': const Color(0xFFC7D2FE),
        'iconBg': const Color(0xFF4F46E5),
        'textCol': const Color(0xFF3730A3),
      },
      {
        'title': LanguageService.tr('Experience', 'অভিজ্ঞতা'),
        'val': _investorProfile['Investment Experience'] ?? 'Intermediate',
        'icon': Icons.trending_up_rounded,
        'bg': const Color(0xFFF0F9FF),
        'border': const Color(0xFFBAE6FD),
        'iconBg': const Color(0xFF0284C7),
        'textCol': const Color(0xFF075985),
      },
      {
        'title': LanguageService.tr('Risk Tolerance', 'ঝুঁকি সহনশীলতা'),
        'val': _investorProfile['Risk Tolerance'] ?? 'Moderate',
        'icon': Icons.speed_rounded,
        'bg': const Color(0xFFF0FDF4),
        'border': const Color(0xFFBBF7D0),
        'iconBg': const Color(0xFF16A34A),
        'textCol': const Color(0xFF166534),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LanguageService.tr('Investor Profile Details', 'বিনিয়োগকারী প্রোফাইল বিবরণ'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),

        // Bento Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: bentoCards.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.1,
          ),
          itemBuilder: (context, index) {
            final card = bentoCards[index];
            final Color bg = card['bg'] as Color;
            final Color border = card['border'] as Color;
            final Color iconBg = card['iconBg'] as Color;
            final Color textCol = card['textCol'] as Color;

            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(card['icon'] as IconData,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          card['title'] as String,
                          style: TextStyle(
                              fontSize: 9.5,
                              color: textCol.withAlpha(200),
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          card['val'] as String,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: textCol),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),

        // Full Address Card (Soft Teal Gradient)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDFA),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF99F6E4)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D9488),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.map_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LanguageService.tr('Permanent Address', 'স্থায়ী ঠিকানা'),
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F766E)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _investorProfile['Address'] ?? 'Bangladesh',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF115E59)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKycDetailsCard() {
    final fullName = _investorProfile['fullName'] ?? '';
    final docType = _investorProfile['documentType'] ?? 'NATIONAL_ID';
    final docNo = _investorProfile['nationalId'] ?? 'N/A';
    final division = _investorProfile['division'] ?? '';
    final district = _investorProfile['district'] ?? '';
    final thana = _investorProfile['thana'] ?? '';
    final bankName = _investorProfile['bankName'] ?? '';
    final bankAcc = _investorProfile['bankAccountNumber'] ?? '';
    final nomineeNid = _investorProfile['nomineeNationalId'] ?? 'N/A';
    final nomineeRel = _investorProfile['nomineeRelation'] ?? 'N/A';

    if (fullName.isEmpty && docNo == 'N/A') return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LanguageService.tr('KYC Verified Information', 'কেওয়াইসি ভেরিফাইড তথ্য'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(5),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (fullName.isNotEmpty) ...[
                _buildKycRow(Icons.person_outline_rounded, LanguageService.tr('Full Name', 'পূর্ণ নাম'), fullName),
                const Divider(height: 16, color: Color(0xFFF1F5F9)),
              ],
              _buildKycRow(Icons.badge_outlined, docType, docNo),
              if (district.isNotEmpty || division.isNotEmpty) ...[
                const Divider(height: 16, color: Color(0xFFF1F5F9)),
                _buildKycRow(Icons.location_on_outlined, LanguageService.tr('Location', 'এলাকা'), '$thana, $district, $division'.replaceAll(RegExp(r'^,\s*|,\s*,\s*|,\s*$'), '')),
              ],
              if (bankName.isNotEmpty) ...[
                const Divider(height: 16, color: Color(0xFFF1F5F9)),
                _buildKycRow(Icons.account_balance_outlined, LanguageService.tr('Bank Account', 'ব্যাংক অ্যাকাউন্ট'), '$bankName ($bankAcc)'),
              ],
              if (nomineeNid != 'N/A' && nomineeNid.isNotEmpty) ...[
                const Divider(height: 16, color: Color(0xFFF1F5F9)),
                _buildKycRow(Icons.supervisor_account_outlined, LanguageService.tr('Nominee', 'নমিনি'), 'NID: $nomineeNid (${LanguageService.tr("Relation", "সম্পর্ক")}: $nomineeRel)'),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKycRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0D9488)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }
}
