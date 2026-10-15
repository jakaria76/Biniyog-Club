import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../authentication/login_page.dart';
import '../../../services/auth_service.dart';
import '../../../services/bd_location_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';

class KycSubmitPage extends StatefulWidget {
  /// Age jama dewa (ba bad pora) KYC — thakle form age theke bhora thakbe
  final Map<String, dynamic>? existing;

  const KycSubmitPage({super.key, this.existing});

  @override
  State<KycSubmitPage> createState() => _KycSubmitPageState();
}

class _KycSubmitPageState extends State<KycSubmitPage> {
  // ─── Palette ───
  static const Color emerald = Color(0xFF0E4A37);
  static const Color emeraldSoft = Color(0xFFE3F0E9);
  static const Color gold = Color(0xFFB8935A);
  static const Color goldLight = Color(0xFFD9BE8C);
  static const Color goldDeep = Color(0xFF8A6A3A);
  static const Color goldSoft = Color(0xFFF6EEDF);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);
  static const Color danger = Color(0xFFB4413A);
  static const Color dangerSoft = Color(0xFFFBEAE8);

  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  // Personal
  final _fullNameController = TextEditingController();
  DateTime? _selectedDob;
  bool _dobError = false;

  // Present address
  final _presentAddressController = TextEditingController();
  String? _presentDivision;
  String? _presentDistrict;
  String? _presentUpazila;
  final _presentPostOfficeController = TextEditingController();
  final _presentPostalCodeController = TextEditingController();

  // Permanent address
  bool _sameAsPresent = true;
  final _permanentAddressController = TextEditingController();
  String? _permanentDivision;
  String? _permanentDistrict;
  String? _permanentUpazila;
  final _permanentPostOfficeController = TextEditingController();
  final _permanentPostalCodeController = TextEditingController();

  // Identity
  String _documentType = 'NATIONAL_ID';
  final _docNumberController = TextEditingController();

  // Nominee
  final _nomineeNidController = TextEditingController();
  String? _nomineeRelation;

  // Payout
  final _bankNameController = TextEditingController();
  final _bankAccountController = TextEditingController();
  String? _mobileProvider;
  final _mobileNumberController = TextEditingController();

  // Photos
  File? _yourFrontImage;
  File? _yourBackImage;
  File? _nomineeFrontImage;
  File? _nomineeBackImage;
  String? _yourFrontBase64;
  String? _yourBackBase64;
  String? _nomineeFrontBase64;
  String? _nomineeBackBase64;

  bool _ready = false; // prefill shesh hole form dekhai (dropdown thik value pay)
  bool _confirmed = false;
  bool _isSubmitting = false;
  String? _formError;

  static const List<String> mobileProviders = ['bKash', 'Nagad', 'Rocket', 'Upay'];

  // DB te English e jay (website er sathe mile), screen e bhasha onujayi
  static const List<(String, String)> relations = [
    ('Father', 'বাবা'),
    ('Mother', 'মা'),
    ('Spouse', 'স্বামী/স্ত্রী'),
    ('Son', 'ছেলে'),
    ('Daughter', 'মেয়ে'),
    ('Brother', 'ভাই'),
    ('Sister', 'বোন'),
    ('Other', 'অন্যান্য'),
  ];

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  /// Registration ar age jama dewa KYC theke — shudhu ja ashole ache
  Future<void> _prefill() async {
    final userData = await AuthService.getUserData();
    final k = widget.existing ?? {};
    final raw = (k['raw'] is Map) ? Map<String, dynamic>.from(k['raw'] as Map) : <String, dynamic>{};
    String v(String key) => k[key]?.toString().trim() ?? '';
    String r(String key) => raw[key]?.toString().trim() ?? '';

    if (!mounted) return;
    setState(() {
      _fullNameController.text = v('fullName').isNotEmpty ? v('fullName') : (userData?['name']?.toString() ?? '');
      if (v('documentType') == 'PASSPORT') _documentType = 'PASSPORT';
      _docNumberController.text = v('documentNumber');
      _presentAddressController.text = v('address');

      // Dropdown e shudhu list e thaka value boshai (na hole Flutter assert kore)
      final divs = BdLocationService.getDivisions();
      if (divs.contains(v('division'))) {
        _presentDivision = v('division');
        if (BdLocationService.getDistricts(_presentDivision).contains(v('district'))) {
          _presentDistrict = v('district');
          if (BdLocationService.getUpazilas(_presentDivision, _presentDistrict).contains(v('upazila'))) {
            _presentUpazila = v('upazila');
          }
        }
      }
      _presentPostOfficeController.text = r('presentPostOffice');
      _presentPostalCodeController.text = r('presentPostalCode');

      final pAddr = r('permanentAddress');
      if (pAddr.isNotEmpty && pAddr != v('address')) {
        _sameAsPresent = false;
        _permanentAddressController.text = pAddr;
        if (divs.contains(r('permanentDivision'))) {
          _permanentDivision = r('permanentDivision');
          if (BdLocationService.getDistricts(_permanentDivision).contains(r('permanentDistrict'))) {
            _permanentDistrict = r('permanentDistrict');
            if (BdLocationService.getUpazilas(_permanentDivision, _permanentDistrict)
                .contains(r('permanentUpazila'))) {
              _permanentUpazila = r('permanentUpazila');
            }
          }
        }
        _permanentPostOfficeController.text = r('permanentPostOffice');
        _permanentPostalCodeController.text = r('permanentPostalCode');
      }

      final dob = DateTime.tryParse(v('dateOfBirth'));
      if (dob != null) _selectedDob = DateTime(dob.year, dob.month, dob.day);

      _nomineeNidController.text = v('nomineeNid');
      final rel = v('nomineeRelation');
      if (relations.any((e) => e.$1 == rel)) _nomineeRelation = rel;

      _bankNameController.text = v('bankName');
      _bankAccountController.text = v('bankAccountNumber');
      if (mobileProviders.contains(v('mobileProvider'))) _mobileProvider = v('mobileProvider');
      _mobileNumberController.text =
      v('mobileNumber').isNotEmpty ? v('mobileNumber') : (userData?['phone']?.toString() ?? '');
      _ready = true;
    });
  }

  @override
  void dispose() {
    for (final c in [
      _fullNameController,
      _presentAddressController,
      _presentPostOfficeController,
      _presentPostalCodeController,
      _permanentAddressController,
      _permanentPostOfficeController,
      _permanentPostalCodeController,
      _docNumberController,
      _nomineeNidController,
      _bankNameController,
      _bankAccountController,
      _mobileNumberController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════
  // VALIDATION (Bangladesh er niyom)
  // ═════════════════════════════════════════════════════════
  String get _req => LanguageService.tr('Required', 'আবশ্যক');

  /// NID: 10, 13 ba 17 digit
  String? _nidValidator(String? v, {bool own = false}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return _req;
    if (!RegExp(r'^(\d{10}|\d{13}|\d{17})$').hasMatch(t)) {
      return LanguageService.tr('NID must be 10, 13 or 17 digits', 'এনআইডি ১০, ১৩ বা ১৭ সংখ্যার হতে হবে');
    }
    if (!own && t == _docNumberController.text.trim()) {
      return LanguageService.tr('Nominee NID cannot be your own NID', 'নমিনীর এনআইডি আপনার নিজের হতে পারবে না');
    }
    return null;
  }

  String? _docValidator(String? v) {
    if (_documentType == 'NATIONAL_ID') return _nidValidator(v, own: true);
    final t = (v ?? '').trim().toUpperCase();
    if (t.isEmpty) return _req;
    if (!RegExp(r'^[A-Z]{1,2}\d{7,8}$').hasMatch(t)) {
      return LanguageService.tr('Enter a valid passport number (e.g. A01234567)', 'সঠিক পাসপোর্ট নম্বর দিন (যেমন A01234567)');
    }
    return null;
  }

  bool _validMobile(String v) => RegExp(r'^01[3-9]\d{8}$').hasMatch(v.replaceAll(RegExp(r'[\s-]'), '').replaceFirst(RegExp(r'^\+?88'), ''));

  String _cleanMobile(String v) => v.replaceAll(RegExp(r'[\s-]'), '').replaceFirst(RegExp(r'^\+?88'), '');

  // ═════════════════════════════════════════════════════════
  // PHOTOS
  // ═════════════════════════════════════════════════════════
  String _mimeFromPath(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.heic')) return 'image/heic';
    return 'image/png';
  }

  Future<void> _pickImage(String type) async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        maxHeight: 1400,
        imageQuality: 82,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 4 * 1024 * 1024) {
        _toast(LanguageService.tr('Image is too large. Please choose a smaller one.',
            'ছবি অনেক বড়। ছোট একটি ছবি বাছাই করুন।'), error: true);
        return;
      }
      final mime = picked.mimeType ?? _mimeFromPath(picked.path);
      final dataUri = 'data:$mime;base64,${base64Encode(bytes)}';
      final file = File(picked.path);

      setState(() {
        _formError = null;
        switch (type) {
          case 'YOUR_FRONT':
            _yourFrontImage = file;
            _yourFrontBase64 = dataUri;
          case 'YOUR_BACK':
            _yourBackImage = file;
            _yourBackBase64 = dataUri;
          case 'NOMINEE_FRONT':
            _nomineeFrontImage = file;
            _nomineeFrontBase64 = dataUri;
          case 'NOMINEE_BACK':
            _nomineeBackImage = file;
            _nomineeBackBase64 = dataUri;
        }
      });
    } catch (e) {
      debugPrint('Error picking image: $e');
      _toast(LanguageService.tr('Could not open the image. Please try another one.',
          'ছবিটি খোলা যায়নি। অন্য একটি চেষ্টা করুন।'), error: true);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? danger : emerald),
    );
  }

  // ═════════════════════════════════════════════════════════
  // SUBMIT
  // ═════════════════════════════════════════════════════════
  String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _handleSubmitKyc() async {
    FocusScope.of(context).unfocus();
    final formOk = _formKey.currentState!.validate();

    String? problem;
    final now = DateTime.now();
    final adultLimit = DateTime(now.year - 18, now.month, now.day);
    setState(() => _dobError = _selectedDob == null || _selectedDob!.isAfter(adultLimit));

    final bankName = _bankNameController.text.trim();
    final bankAcc = _bankAccountController.text.trim();
    final mobile = _cleanMobile(_mobileNumberController.text.trim());
    final hasBank = bankName.isNotEmpty && bankAcc.isNotEmpty;
    final hasMobile = mobile.isNotEmpty && _mobileProvider != null;

    if (!formOk) {
      problem = LanguageService.tr('Please fix the highlighted fields.', 'লাল চিহ্নিত ঘরগুলো ঠিক করুন।');
    } else if (_dobError) {
      problem = _selectedDob == null
          ? LanguageService.tr('Please select your date of birth.', 'জন্ম তারিখ বাছাই করুন।')
          : LanguageService.tr('You must be at least 18 years old to invest.',
          'বিনিয়োগ করতে বয়স কমপক্ষে ১৮ বছর হতে হবে।');
    } else if (_yourFrontBase64 == null) {
      problem = _documentType == 'PASSPORT'
          ? LanguageService.tr('Please upload your passport photo page.', 'পাসপোর্টের ছবির পাতা আপলোড করুন।')
          : LanguageService.tr('Please upload the front of your NID.', 'এনআইডির সামনের ছবি আপলোড করুন।');
    } else if (_documentType == 'NATIONAL_ID' && _yourBackBase64 == null) {
      problem = LanguageService.tr('Please upload the back of your NID.', 'এনআইডির পেছনের ছবি আপলোড করুন।');
    } else if (!hasBank && !hasMobile) {
      problem = LanguageService.tr('Add a bank account or a mobile banking number to receive your returns.',
          'লাভ পেতে একটি ব্যাংক অ্যাকাউন্ট বা মোবাইল ব্যাংকিং নম্বর দিন।');
    } else if (mobile.isNotEmpty && !_validMobile(mobile)) {
      problem = LanguageService.tr('Enter a valid mobile number (01XXXXXXXXX).', 'সঠিক মোবাইল নম্বর দিন (01XXXXXXXXX)।');
    } else if (!_confirmed) {
      problem = LanguageService.tr('Please confirm that the information is correct.', 'তথ্য সঠিক বলে নিশ্চিত করুন।');
    }

    if (problem != null) {
      setState(() => _formError = problem);
      return;
    }

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';
    if (userId.isEmpty) {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _formError = null;
    });

    final same = _sameAsPresent;
    final result = await DatabaseService.submitKycData(
      userId: userId,
      fullName: _fullNameController.text.trim(),
      documentType: _documentType,
      documentNumber: _docNumberController.text.trim().toUpperCase(),
      division: _presentDivision!,
      district: _presentDistrict!,
      thana: _presentUpazila!,
      address: _presentAddressController.text.trim(),
      bankName: bankName,
      bankAccountNumber: bankAcc,
      // Number na thakle provider o na — age 'bKash' default chole jeto
      mobileProvider: mobile.isNotEmpty ? (_mobileProvider ?? '') : '',
      mobileNumber: mobile,
      nomineeNid: _nomineeNidController.text.trim(),
      nomineeRelation: _nomineeRelation ?? '',
      frontPhotoBase64: _yourFrontBase64,
      backPhotoBase64: _documentType == 'NATIONAL_ID' ? _yourBackBase64 : null,
      nomineeFrontBase64: _nomineeFrontBase64,
      nomineeBackBase64: _nomineeBackBase64,
      // Website er kyc table e column thakle save hobe (DOB, permanent address …)
      extraFields: {
        'dateOfBirth': _isoDate(_selectedDob!),
        'presentPostOffice': _presentPostOfficeController.text,
        'presentPostalCode': _presentPostalCodeController.text,
        'permanentAddress': same ? _presentAddressController.text : _permanentAddressController.text,
        'permanentDivision': same ? _presentDivision : _permanentDivision,
        'permanentDistrict': same ? _presentDistrict : _permanentDistrict,
        'permanentUpazila': same ? _presentUpazila : _permanentUpazila,
        'permanentPostOffice': same ? _presentPostOfficeController.text : _permanentPostOfficeController.text,
        'permanentPostalCode': same ? _presentPostalCodeController.text : _permanentPostalCodeController.text,
      },
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] == true) {
      _toast(LanguageService.tr('KYC submitted! We will review it soon.', 'কেওয়াইসি জমা হয়েছে! শীঘ্রই যাচাই করা হবে।'));
      Navigator.pop(context, true);
    } else {
      setState(() => _formError = result['message']?.toString() ??
          LanguageService.tr('KYC submission failed. Please try again.', 'কেওয়াইসি জমা হয়নি। আবার চেষ্টা করুন।'));
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
        final isPassport = _documentType == 'PASSPORT';

        return Scaffold(
          backgroundColor: ivory,
          appBar: AppBar(
            backgroundColor: ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: ink),
            title: Text(
              LanguageService.tr('Identity Verification', 'পরিচয় যাচাই (KYC)'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          body: !_ready
              ? const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(color: emerald, strokeWidth: 2.4),
            ),
          )
              : SafeArea(
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  _infoBanner(),
                  const SizedBox(height: 16),

                  // ─── 1. Personal ───
                  _section(
                    step: 1,
                    title: LanguageService.tr('Personal Information', 'ব্যক্তিগত তথ্য'),
                    subtitle: LanguageService.tr('Exactly as written on your ID', 'পরিচয়পত্রে যেমন লেখা ঠিক তেমন'),
                    children: [
                      TextFormField(
                        controller: _fullNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _dec(LanguageService.tr('Full legal name *', 'আইনগত পূর্ণ নাম *'), Icons.person_outline),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return _req;
                          if (t.length < 3) return LanguageService.tr('Name is too short', 'নাম খুব ছোট');
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDob ?? DateTime(now.year - 25, 1, 1),
                            firstDate: DateTime(1920),
                            lastDate: now,
                          );
                          if (picked != null) {
                            setState(() {
                              _selectedDob = picked;
                              _dobError = false;
                            });
                          }
                        },
                        child: InputDecorator(
                          decoration: _dec(LanguageService.tr('Date of birth *', 'জন্ম তারিখ *'), Icons.cake_outlined)
                              .copyWith(
                            errorText: _dobError
                                ? (_selectedDob == null
                                ? _req
                                : LanguageService.tr('Must be 18 or older', 'বয়স ১৮ বা তার বেশি হতে হবে'))
                                : null,
                          ),
                          child: Text(
                            _selectedDob != null
                                ? _isoDate(_selectedDob!)
                                : LanguageService.tr('Select date', 'তারিখ বাছাই করুন'),
                            style: TextStyle(fontSize: 14, color: _selectedDob != null ? ink : muted),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ─── 2. Address ───
                  _section(
                    step: 2,
                    title: LanguageService.tr('Address', 'ঠিকানা'),
                    subtitle: LanguageService.tr('Your address in Bangladesh', 'বাংলাদেশে আপনার ঠিকানা'),
                    children: [
                      _subTitle(LanguageService.tr('Present address', 'বর্তমান ঠিকানা')),
                      ..._addressFields(
                        prefix: 'present',
                        address: _presentAddressController,
                        division: _presentDivision,
                        district: _presentDistrict,
                        upazila: _presentUpazila,
                        postOffice: _presentPostOfficeController,
                        postalCode: _presentPostalCodeController,
                        onDivision: (v) => setState(() {
                          _presentDivision = v;
                          _presentDistrict = null;
                          _presentUpazila = null;
                        }),
                        onDistrict: (v) => setState(() {
                          _presentDistrict = v;
                          _presentUpazila = null;
                        }),
                        onUpazila: (v) => setState(() => _presentUpazila = v),
                      ),
                      const SizedBox(height: 4),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: emerald,
                        title: Text(
                          LanguageService.tr('Permanent address is the same', 'স্থায়ী ঠিকানা একই'),
                          style: const TextStyle(fontSize: 13, color: ink),
                        ),
                        value: _sameAsPresent,
                        onChanged: (v) => setState(() => _sameAsPresent = v ?? true),
                      ),
                      if (!_sameAsPresent) ...[
                        _subTitle(LanguageService.tr('Permanent address', 'স্থায়ী ঠিকানা')),
                        ..._addressFields(
                          prefix: 'permanent',
                          address: _permanentAddressController,
                          division: _permanentDivision,
                          district: _permanentDistrict,
                          upazila: _permanentUpazila,
                          postOffice: _permanentPostOfficeController,
                          postalCode: _permanentPostalCodeController,
                          onDivision: (v) => setState(() {
                            _permanentDivision = v;
                            _permanentDistrict = null;
                            _permanentUpazila = null;
                          }),
                          onDistrict: (v) => setState(() {
                            _permanentDistrict = v;
                            _permanentUpazila = null;
                          }),
                          onUpazila: (v) => setState(() => _permanentUpazila = v),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ─── 3. Identity ───
                  _section(
                    step: 3,
                    title: LanguageService.tr('Identity Document', 'পরিচয়পত্র'),
                    subtitle: LanguageService.tr('Clear photo — all four corners and text readable',
                        'পরিষ্কার ছবি — চার কোণা ও লেখা যেন পড়া যায়'),
                    children: [
                      Row(
                        children: [
                          _typeChip('NATIONAL_ID', LanguageService.tr('National ID', 'জাতীয় পরিচয়পত্র')),
                          const SizedBox(width: 8),
                          _typeChip('PASSPORT', LanguageService.tr('Passport', 'পাসপোর্ট')),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: ValueKey('doc-$_documentType'),
                        controller: _docNumberController,
                        keyboardType: isPassport ? TextInputType.text : TextInputType.number,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: isPassport
                            ? [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')), LengthLimitingTextInputFormatter(10)]
                            : [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(17)],
                        decoration: _dec(
                          isPassport
                              ? LanguageService.tr('Passport number *', 'পাসপোর্ট নম্বর *')
                              : LanguageService.tr('NID number *', 'এনআইডি নম্বর *'),
                          Icons.badge_outlined,
                        ),
                        validator: _docValidator,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _imageBox(
                              label: isPassport
                                  ? LanguageService.tr('Photo page *', 'ছবির পাতা *')
                                  : LanguageService.tr('NID front *', 'এনআইডি সামনে *'),
                              file: _yourFrontImage,
                              onTap: () => _pickImage('YOUR_FRONT'),
                            ),
                          ),
                          if (!isPassport) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: _imageBox(
                                label: LanguageService.tr('NID back *', 'এনআইডি পেছনে *'),
                                file: _yourBackImage,
                                onTap: () => _pickImage('YOUR_BACK'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ─── 4. Nominee ───
                  _section(
                    step: 4,
                    title: LanguageService.tr('Nominee', 'নমিনী'),
                    subtitle: LanguageService.tr('Who receives your investment if something happens to you',
                        'আপনার অবর্তমানে যিনি বিনিয়োগ পাবেন'),
                    children: [
                      TextFormField(
                        controller: _nomineeNidController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(17)],
                        decoration: _dec(LanguageService.tr('Nominee NID number *', 'নমিনীর এনআইডি নম্বর *'),
                            Icons.person_pin_outlined),
                        validator: (v) => _nidValidator(v),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: _nomineeRelation,
                        decoration: _dec(LanguageService.tr('Relationship *', 'সম্পর্ক *'), Icons.family_restroom_outlined),
                        items: relations
                            .map((r) => DropdownMenuItem(
                          value: r.$1,
                          child: Text(LanguageService.tr(r.$1, r.$2), style: const TextStyle(fontSize: 13.5)),
                        ))
                            .toList(),
                        onChanged: (v) => setState(() => _nomineeRelation = v),
                        validator: (v) => v == null ? _req : null,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        LanguageService.tr('Nominee NID photos (optional, speeds up review)',
                            'নমিনীর এনআইডির ছবি (ঐচ্ছিক, যাচাই দ্রুত হয়)'),
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _imageBox(
                              label: LanguageService.tr('Front', 'সামনে'),
                              file: _nomineeFrontImage,
                              onTap: () => _pickImage('NOMINEE_FRONT'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _imageBox(
                              label: LanguageService.tr('Back', 'পেছনে'),
                              file: _nomineeBackImage,
                              onTap: () => _pickImage('NOMINEE_BACK'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ─── 5. Payout ───
                  _section(
                    step: 5,
                    title: LanguageService.tr('Payout Account', 'পেআউট অ্যাকাউন্ট'),
                    subtitle: LanguageService.tr('Where your returns are sent — bank, mobile banking or both',
                        'যেখানে লাভ পাঠানো হবে — ব্যাংক, মোবাইল ব্যাংকিং বা দুটোই'),
                    children: [
                      _subTitle(LanguageService.tr('Bank account', 'ব্যাংক অ্যাকাউন্ট')),
                      TextFormField(
                        controller: _bankNameController,
                        decoration: _dec(LanguageService.tr('Bank name', 'ব্যাংকের নাম'), Icons.account_balance_outlined),
                        validator: (v) =>
                        (v ?? '').trim().isEmpty && _bankAccountController.text.trim().isNotEmpty ? _req : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _bankAccountController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(20)],
                        decoration: _dec(LanguageService.tr('Account number', 'অ্যাকাউন্ট নম্বর'), Icons.credit_card_outlined),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return _bankNameController.text.trim().isNotEmpty ? _req : null;
                          if (t.length < 8) return LanguageService.tr('Account number looks too short', 'অ্যাকাউন্ট নম্বর খুব ছোট');
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _subTitle(LanguageService.tr('Mobile banking', 'মোবাইল ব্যাংকিং')),
                      DropdownButtonFormField<String>(
                        initialValue: _mobileProvider,
                        decoration: _dec(LanguageService.tr('Provider', 'সেবা'), Icons.phone_android_outlined),
                        items: mobileProviders.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                        onChanged: (v) => setState(() => _mobileProvider = v),
                        validator: (v) => v == null && _mobileNumberController.text.trim().isNotEmpty ? _req : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _mobileNumberController,
                        keyboardType: TextInputType.phone,
                        decoration: _dec(LanguageService.tr('Mobile number', 'মোবাইল নম্বর'), Icons.phone_outlined)
                            .copyWith(hintText: '01XXXXXXXXX'),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return null;
                          return _validMobile(t)
                              ? null
                              : LanguageService.tr('Enter a valid number (01XXXXXXXXX)', 'সঠিক নম্বর দিন (01XXXXXXXXX)');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ─── Confirm ───
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: line),
                    ),
                    child: CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: emerald,
                      value: _confirmed,
                      onChanged: (v) => setState(() {
                        _confirmed = v ?? false;
                        _formError = null;
                      }),
                      title: Text(
                        LanguageService.tr(
                          'I confirm this information is true and the documents are mine.',
                          'আমি নিশ্চিত করছি এই তথ্য সত্য এবং কাগজপত্র আমার নিজের।',
                        ),
                        style: const TextStyle(fontSize: 12.5, color: ink, height: 1.4),
                      ),
                    ),
                  ),

                  if (_formError != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: dangerSoft, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 17, color: danger),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_formError!, style: const TextStyle(fontSize: 12.5, color: danger))),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _handleSubmitKyc,
                      style: FilledButton.styleFrom(
                        backgroundColor: emerald,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: emerald.withAlpha(120),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isSubmitting
                          ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Text(LanguageService.tr('Uploading…', 'আপলোড হচ্ছে…')),
                        ],
                      )
                          : Text(
                        LanguageService.tr('Submit for Verification', 'যাচাইয়ের জন্য জমা দিন'),
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Address fields (bortoman + sthayi duitar jonno ek-i) ─
  List<Widget> _addressFields({
    required String prefix,
    required TextEditingController address,
    required String? division,
    required String? district,
    required String? upazila,
    required TextEditingController postOffice,
    required TextEditingController postalCode,
    required ValueChanged<String?> onDivision,
    required ValueChanged<String?> onDistrict,
    required ValueChanged<String?> onUpazila,
  }) {
    final districts = BdLocationService.getDistricts(division);
    final upazilas = BdLocationService.getUpazilas(division, district);

    DropdownMenuItem<String> item(String v) =>
        DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)));

    return [
      TextFormField(
        controller: address,
        decoration: _dec(LanguageService.tr('House / road / village *', 'বাসা / রোড / গ্রাম *'), Icons.home_outlined),
        validator: (v) => (v ?? '').trim().length < 5
            ? ((v ?? '').trim().isEmpty ? _req : LanguageService.tr('Please write the full address', 'পূর্ণ ঠিকানা লিখুন'))
            : null,
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey('$prefix-div'),
        isExpanded: true,
        initialValue: division,
        decoration: _dec(LanguageService.tr('Division *', 'বিভাগ *'), null),
        items: BdLocationService.getDivisions().map(item).toList(),
        onChanged: onDivision,
        validator: (v) => v == null ? _req : null,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              // Bibhag bodlale jela reset — key bodle field notun kore toiri
              key: ValueKey('$prefix-dist-$division'),
              isExpanded: true,
              initialValue: district,
              decoration: _dec(LanguageService.tr('District *', 'জেলা *'), null),
              items: districts.map(item).toList(),
              onChanged: division == null ? null : onDistrict,
              validator: (v) => v == null ? _req : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('$prefix-upa-$division-$district'),
              isExpanded: true,
              initialValue: upazila,
              decoration: _dec(LanguageService.tr('Upazila / Thana *', 'উপজেলা / থানা *'), null),
              items: upazilas.map(item).toList(),
              onChanged: district == null ? null : onUpazila,
              validator: (v) => v == null ? _req : null,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: postOffice,
              decoration: _dec(LanguageService.tr('Post office', 'ডাকঘর'), null),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: postalCode,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              decoration: _dec(LanguageService.tr('Postal code', 'পোস্ট কোড'), null),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                return t.length == 4 ? null : LanguageService.tr('4 digits', '৪ সংখ্যা');
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ];
  }

  // ═════════════════════════════════════════════════════════
  // SMALL WIDGETS
  // ═════════════════════════════════════════════════════════
  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: goldSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gold.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, color: goldDeep, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              LanguageService.tr(
                'KYC is required before you can invest. Your documents are only used to verify your identity.',
                'বিনিয়োগের আগে কেওয়াইসি আবশ্যক। আপনার কাগজপত্র শুধু পরিচয় যাচাইয়ের জন্য ব্যবহার হয়।',
              ),
              style: const TextStyle(fontSize: 12.5, color: ink, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({required int step, required String title, required String subtitle, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [goldLight, gold]),
                  shape: BoxShape.circle,
                ),
                child: Text('$step',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: ink)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 36, top: 2),
            child: Text(subtitle, style: const TextStyle(fontSize: 11.5, color: muted)),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _subTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Transform.rotate(
          angle: math.pi / 4,
          child: Container(width: 6, height: 6, color: gold),
        ),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
      ],
    ),
  );

  Widget _typeChip(String value, String label) {
    final on = _documentType == value;
    return GestureDetector(
      onTap: () => setState(() {
        if (_documentType == value) return;
        _documentType = value;
        _docNumberController.clear();
        _yourFrontImage = null;
        _yourFrontBase64 = null;
        _yourBackImage = null;
        _yourBackBase64 = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? emerald : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? emerald : line),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? Colors.white : ink)),
      ),
    );
  }

  InputDecoration _dec(String label, IconData? icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: muted),
      prefixIcon: icon != null ? Icon(icon, color: goldDeep, size: 20) : null,
      filled: true,
      fillColor: ivory,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
      focusedBorder:
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: emerald, width: 1.4)),
      errorBorder:
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: danger)),
      focusedErrorBorder:
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: danger, width: 1.4)),
    );
  }

  Widget _imageBox({required String label, required File? file, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: _isSubmitting ? null : onTap,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: file != null ? emeraldSoft : ivory,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: file != null ? emerald : line, width: file != null ? 1.4 : 1),
        ),
        child: file != null
            ? Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.file(file, fit: BoxFit.cover),
              ),
            ),
            Positioned(
              left: 6,
              bottom: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black.withAlpha(150), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: goldLight, size: 13),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 10.5)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined, color: goldDeep, size: 26),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ink)),
            ),
          ],
        ),
      ),
    );
  }
}