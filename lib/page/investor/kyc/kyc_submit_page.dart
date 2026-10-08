import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../services/auth_service.dart';
import '../../../services/bd_location_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';

class KycSubmitPage extends StatefulWidget {
  const KycSubmitPage({super.key});

  @override
  State<KycSubmitPage> createState() => _KycSubmitPageState();
}

class _KycSubmitPageState extends State<KycSubmitPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  // Personal Info
  final _fullNameController = TextEditingController();
  DateTime? _selectedDob;

  // Present Address
  final _presentAddressController = TextEditingController();
  final _presentDistrictController = TextEditingController();
  String? _presentDivision;
  String? _presentDistrict;
  String? _presentUpazila;
  final _presentPostOfficeController = TextEditingController();
  final _presentPostalCodeController = TextEditingController();

  // Permanent Address
  bool _sameAsPresent = true;
  final _permanentAddressController = TextEditingController();
  final _permanentDistrictController = TextEditingController();
  String? _permanentDivision;
  String? _permanentDistrict;
  String? _permanentUpazila;
  final _permanentPostOfficeController = TextEditingController();
  final _permanentPostalCodeController = TextEditingController();

  // Identity Document
  String _documentType = 'NATIONAL_ID';
  final _docNumberController = TextEditingController();

  // Nominee Info
  final _nomineeNidController = TextEditingController();
  final _nomineeRelationController = TextEditingController();

  // Payment Info
  final _bankNameController = TextEditingController();
  final _bankAccountController = TextEditingController();
  String? _mobileProvider = 'bKash';
  final _mobileNumberController = TextEditingController();

  // Photo Files & Base64
  File? _yourFrontImage;
  File? _yourBackImage;
  File? _nomineeFrontImage;
  File? _nomineeBackImage;

  String? _yourFrontBase64;
  String? _yourBackBase64;
  String? _nomineeFrontBase64;
  String? _nomineeBackBase64;

  bool _isSubmitting = false;

  static const List<String> mobileProviders = [
    'bKash',
    'Nagad',
    'Rocket',
    'Upay',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserDefaultData();
  }

  void _loadUserDefaultData() async {
    final userData = await AuthService.getUserData();
    if (userData != null && mounted) {
      setState(() {
        if (userData['name'] != null) {
          _fullNameController.text = userData['name'].toString();
        }
        if (userData['phone'] != null) {
          _mobileNumberController.text = userData['phone'].toString();
        }
      });
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _presentAddressController.dispose();
    _presentDistrictController.dispose();
    _presentPostOfficeController.dispose();
    _presentPostalCodeController.dispose();

    _permanentAddressController.dispose();
    _permanentDistrictController.dispose();
    _permanentPostOfficeController.dispose();
    _permanentPostalCodeController.dispose();

    _docNumberController.dispose();
    _nomineeNidController.dispose();
    _nomineeRelationController.dispose();

    _bankNameController.dispose();
    _bankAccountController.dispose();
    _mobileNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(String type) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (picked != null) {
        final file = File(picked.path);
        final bytes = await file.readAsBytes();
        final base64Str = 'data:image/png;base64,${base64Encode(bytes)}';

        setState(() {
          if (type == 'YOUR_FRONT') {
            _yourFrontImage = file;
            _yourFrontBase64 = base64Str;
          } else if (type == 'YOUR_BACK') {
            _yourBackImage = file;
            _yourBackBase64 = base64Str;
          } else if (type == 'NOMINEE_FRONT') {
            _nomineeFrontImage = file;
            _nomineeFrontBase64 = base64Str;
          } else if (type == 'NOMINEE_BACK') {
            _nomineeBackImage = file;
            _nomineeBackBase64 = base64Str;
          }
        });
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  void _handleSubmitKyc() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSubmitting = true);

      final userData = await AuthService.getUserData();
      final userId = userData?['id']?.toString() ?? '';

      final result = await DatabaseService.submitKycData(
        userId: userId,
        fullName: _fullNameController.text.trim(),
        documentType: _documentType,
        documentNumber: _docNumberController.text.trim(),
        division: _presentDivision ?? 'Dhaka',
        district: _presentDistrict ?? 'Dhaka',
        thana: _presentUpazila ?? 'Gazipur',
        address: _presentAddressController.text.trim(),
        bankName: _bankNameController.text.trim(),
        bankAccountNumber: _bankAccountController.text.trim(),
        mobileProvider: _mobileProvider ?? 'bKash',
        mobileNumber: _mobileNumberController.text.trim(),
        nomineeNid: _nomineeNidController.text.trim(),
        nomineeRelation: _nomineeRelationController.text.trim(),
        frontPhotoBase64: _yourFrontBase64,
        backPhotoBase64: _yourBackBase64,
        nomineeFrontBase64: _nomineeFrontBase64,
        nomineeBackBase64: _nomineeBackBase64,
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LanguageService.tr(
                'KYC Application saved & submitted for review!',
                'কেওয়াইসি আবেদন সফলভাবে জমা দেওয়া হয়েছে!')),
            backgroundColor: Colors.teal,
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'KYC submission failed.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        final availablePresentDistricts =
            BdLocationService.getDistricts(_presentDivision);
        final availablePresentUpazilas =
            BdLocationService.getUpazilas(_presentDivision, _presentDistrict);

        final availablePermanentDistricts =
            BdLocationService.getDistricts(_permanentDivision);
        final availablePermanentUpazilas =
            BdLocationService.getUpazilas(_permanentDivision, _permanentDistrict);

        return Scaffold(
          backgroundColor: const Color(0xFFF4F7F6),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.5,
            iconTheme: const IconThemeData(color: Colors.teal),
            title: Text(
              LanguageService.tr('Identity Verification', 'পরিচয় ভেরিফিকেশন (KYC)'),
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Warning Alert Banner
                    _buildTopAlertBanner(),
                    const SizedBox(height: 16),

                    Text(
                      LanguageService.tr('Identity Verification', 'পরিচয় ভেরিফিকেশন'),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      LanguageService.tr(
                          'Complete all sections and upload your identity document to get verified',
                          'ভেরিফিকেশনের জন্য নিচের সকল তথ্য পূরণ করুন এবং আপনার পরিচয়পত্র আপলোড করুন'),
                      style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 20),

                    // 1. Personal Information Section
                    _buildSectionCard(
                      title: LanguageService.tr('Personal Information', 'ব্যক্তিগত তথ্য'),
                      subtitle: LanguageService.tr(
                          'Pre-filled from your registration — edit if needed',
                          'রেজিস্ট্রেশনের তথ্য অনুযায়ী পূরণকৃত — প্রয়োজন হলে এডিট করুন'),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _fullNameController,
                            decoration: _buildInputDecoration(
                              label: LanguageService.tr('Full legal name *', 'আইনগত পূর্ণ নাম *'),
                              icon: Icons.person_outline,
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Required field' : null,
                          ),
                          const SizedBox(height: 14),
                          InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime(1995, 1, 1),
                                firstDate: DateTime(1940),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setState(() => _selectedDob = picked);
                              }
                            },
                            child: InputDecorator(
                              decoration: _buildInputDecoration(
                                label: LanguageService.tr('Date of birth *', 'জন্ম তারিখ *'),
                                icon: Icons.calendar_today_outlined,
                              ),
                              child: Text(
                                _selectedDob != null
                                    ? '${_selectedDob!.year}-${_selectedDob!.month.toString().padLeft(2, '0')}-${_selectedDob!.day.toString().padLeft(2, '0')}'
                                    : 'mm/dd/yyyy',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _selectedDob != null
                                      ? Colors.black87
                                      : Colors.grey[500],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 2. Address Section
                    _buildSectionCard(
                      title: LanguageService.tr('Address', 'ঠিকানা'),
                      subtitle: LanguageService.tr(
                          'Your present and permanent address in Bangladesh',
                          'বাংলাদেশে আপনার বর্তমান ও স্থায়ী ঠিকানা'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(LanguageService.tr('Present Address', 'বর্তমান ঠিকানা'),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _presentAddressController,
                            decoration: _buildInputDecoration(
                              label: LanguageService.tr('Address / House / Road *', 'ঠিকানা / বাসা / রোড *'),
                              icon: Icons.home_outlined,
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Required field' : null,
                          ),
                          const SizedBox(height: 14),

                          // Division & District Row
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _presentDivision,
                                  decoration: _buildInputDecoration(
                                      label: LanguageService.tr('Division *', 'বিভাগ *')),
                                  hint: Text(LanguageService.tr('Select Division', 'বিভাগ বেছে নিন'), style: const TextStyle(fontSize: 12)),
                                  items: BdLocationService.getDivisions().map((div) {
                                    return DropdownMenuItem<String>(
                                      value: div,
                                      child: Text(div,
                                          style: const TextStyle(fontSize: 13)),
                                    );
                                  }).toList(),
                                  onChanged: (v) {
                                    setState(() {
                                      _presentDivision = v;
                                      _presentDistrict = null;
                                      _presentUpazila = null;
                                    });
                                  },
                                  validator: (v) =>
                                      v == null ? 'Required field' : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _presentDistrict,
                                  decoration: _buildInputDecoration(
                                      label: LanguageService.tr('District *', 'জেলা *')),
                                  hint: Text(LanguageService.tr('Select District', 'জেলা বেছে নিন'), style: const TextStyle(fontSize: 12)),
                                  items: availablePresentDistricts.map((dist) {
                                    return DropdownMenuItem<String>(
                                      value: dist,
                                      child: Text(dist,
                                          style: const TextStyle(fontSize: 13)),
                                    );
                                  }).toList(),
                                  onChanged: (v) {
                                    setState(() {
                                      _presentDistrict = v;
                                      _presentUpazila = null;
                                    });
                                  },
                                  validator: (v) =>
                                      v == null ? 'Required field' : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Upazila & Post Office Row
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _presentUpazila,
                                  decoration: _buildInputDecoration(
                                      label: LanguageService.tr('Upazila / Thana *', 'উপজেলা / থানা *')),
                                  hint: Text(LanguageService.tr('Select Upazila', 'উপজেলা বেছে নিন'), style: const TextStyle(fontSize: 12)),
                                  items: availablePresentUpazilas.map((upa) {
                                    return DropdownMenuItem<String>(
                                      value: upa,
                                      child: Text(upa,
                                          style: const TextStyle(fontSize: 13)),
                                    );
                                  }).toList(),
                                  onChanged: (v) {
                                    setState(() => _presentUpazila = v);
                                  },
                                  validator: (v) =>
                                      v == null ? 'Required field' : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: _presentPostOfficeController,
                                  decoration: _buildInputDecoration(
                                      label: LanguageService.tr('Post Office', 'ডাকঘর')),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _presentPostalCodeController,
                            keyboardType: TextInputType.number,
                            decoration: _buildInputDecoration(
                                label: LanguageService.tr('Postal Code', 'পোস্টাল কোড')),
                          ),
                          const SizedBox(height: 16),
                          const Divider(),

                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              LanguageService.tr(
                                  'Permanent address is same as present address',
                                  'স্থায়ী ঠিকানা বর্তমান ঠিকানার মতোই'),
                              style: const TextStyle(fontSize: 13),
                            ),
                            value: _sameAsPresent,
                            activeColor: Colors.teal,
                            onChanged: (v) {
                              setState(() => _sameAsPresent = v ?? true);
                            },
                          ),

                          // Permanent Address Fields if not same
                          if (!_sameAsPresent) ...[
                            const SizedBox(height: 10),
                            Text(LanguageService.tr('Permanent Address', 'স্থায়ী ঠিকানা'),
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _permanentAddressController,
                              decoration: _buildInputDecoration(
                                label: LanguageService.tr('Address / House / Road *', 'ঠিকানা / বাসা / রোড *'),
                                icon: Icons.home_outlined,
                              ),
                              validator: (v) =>
                                  v == null || v.isEmpty ? 'Required field' : null,
                            ),
                            const SizedBox(height: 14),

                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _permanentDivision,
                                    decoration: _buildInputDecoration(
                                        label: LanguageService.tr('Division *', 'বিভাগ *')),
                                    hint: Text(LanguageService.tr('Select Division', 'বিভাগ বেছে নিন'),
                                        style: const TextStyle(fontSize: 12)),
                                    items:
                                        BdLocationService.getDivisions().map((div) {
                                      return DropdownMenuItem<String>(
                                        value: div,
                                        child: Text(div,
                                            style:
                                                const TextStyle(fontSize: 13)),
                                      );
                                    }).toList(),
                                    onChanged: (v) {
                                      setState(() {
                                        _permanentDivision = v;
                                        _permanentDistrict = null;
                                        _permanentUpazila = null;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _permanentDistrict,
                                    decoration: _buildInputDecoration(
                                        label: LanguageService.tr('District *', 'জেলা *')),
                                    hint: Text(LanguageService.tr('Select District', 'জেলা বেছে নিন'),
                                        style: const TextStyle(fontSize: 12)),
                                    items:
                                        availablePermanentDistricts.map((dist) {
                                      return DropdownMenuItem<String>(
                                        value: dist,
                                        child: Text(dist,
                                            style:
                                                const TextStyle(fontSize: 13)),
                                      );
                                    }).toList(),
                                    onChanged: (v) {
                                      setState(() {
                                        _permanentDistrict = v;
                                        _permanentUpazila = null;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 3. Identity Document Section
                    _buildSectionCard(
                      title: LanguageService.tr('Identity Document', 'পরিচয়পত্র'),
                      subtitle: LanguageService.tr(
                          'Upload valid government issued ID document',
                          'সরকারি গ্রহণযোগ্য আইডি ছবি আপলোড করুন'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ChoiceChip(
                                label: const Text('National ID (NID)'),
                                selected: _documentType == 'NATIONAL_ID',
                                selectedColor: Colors.teal,
                                labelStyle: TextStyle(
                                    color: _documentType == 'NATIONAL_ID'
                                        ? Colors.white
                                        : Colors.black87),
                                onSelected: (s) {
                                  if (s) {
                                    setState(() => _documentType = 'NATIONAL_ID');
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('Passport'),
                                selected: _documentType == 'PASSPORT',
                                selectedColor: Colors.teal,
                                labelStyle: TextStyle(
                                    color: _documentType == 'PASSPORT'
                                        ? Colors.white
                                        : Colors.black87),
                                onSelected: (s) {
                                  if (s) {
                                    setState(() => _documentType = 'PASSPORT');
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _docNumberController,
                            keyboardType: TextInputType.number,
                            decoration: _buildInputDecoration(
                              label: LanguageService.tr('Document ID Number *', 'পরিচয়পত্র নম্বর *'),
                              icon: Icons.badge_outlined,
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Required field' : null,
                          ),
                          const SizedBox(height: 16),

                          // Front & Back Image Upload Boxes
                          Row(
                            children: [
                              Expanded(
                                child: _buildImageUploadBox(
                                  label: LanguageService.tr('NID Front Side *', 'এনআইডি সামনের অংশ *'),
                                  file: _yourFrontImage,
                                  onTap: () => _pickImage('YOUR_FRONT'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildImageUploadBox(
                                  label: LanguageService.tr('NID Back Side *', 'এনআইডি পেছনের অংশ *'),
                                  file: _yourBackImage,
                                  onTap: () => _pickImage('YOUR_BACK'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 4. Nominee Information Section
                    _buildSectionCard(
                      title: LanguageService.tr('Nominee Information', 'নমিনীর তথ্য'),
                      subtitle: LanguageService.tr(
                          'Details of the person who will inherit investments',
                          'বিনিয়োগের উত্তরাধিকারীর তথ্য'),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nomineeNidController,
                            keyboardType: TextInputType.number,
                            decoration: _buildInputDecoration(
                              label: LanguageService.tr('Nominee NID Number *', 'নমিনীর এনআইডি নম্বর *'),
                              icon: Icons.person_pin_outlined,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _nomineeRelationController,
                            decoration: _buildInputDecoration(
                              label: LanguageService.tr('Relationship with Nominee *', 'নমিনীর সাথে সম্পর্ক *'),
                              icon: Icons.family_restroom_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 5. Payout Account Information Section
                    _buildSectionCard(
                      title: LanguageService.tr('Payout Account Information', 'পেআউট ব্যাংক অ্যাকাউন্ট'),
                      subtitle: LanguageService.tr(
                          'Account where investment returns will be transferred',
                          'যে অ্যাকাউন্টে আপনার লভ্যাংশ পাঠানো হবে'),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _bankNameController,
                            decoration: _buildInputDecoration(
                              label: LanguageService.tr('Bank Name *', 'ব্যাংকের নাম *'),
                              icon: Icons.account_balance_outlined,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _bankAccountController,
                            keyboardType: TextInputType.number,
                            decoration: _buildInputDecoration(
                              label: LanguageService.tr('Bank Account Number *', 'ব্যাংক অ্যাকাউন্ট নম্বর *'),
                              icon: Icons.credit_card_outlined,
                            ),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            value: _mobileProvider,
                            decoration: _buildInputDecoration(
                              label: LanguageService.tr('Mobile Provider', 'মোবাইল ব্যাংকিং সেবা'),
                              icon: Icons.phone_android_outlined,
                            ),
                            items: mobileProviders.map((p) {
                              return DropdownMenuItem<String>(
                                value: p,
                                child: Text(p),
                              );
                            }).toList(),
                            onChanged: (v) =>
                                setState(() => _mobileProvider = v),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _mobileNumberController,
                            keyboardType: TextInputType.phone,
                            decoration: _buildInputDecoration(
                              label: LanguageService.tr('Mobile Banking Number', 'মোবাইল ব্যাংকিং নম্বর'),
                              icon: Icons.phone_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Submit Button
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _handleSubmitKyc,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 1,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              LanguageService.tr('Submit KYC Verification', 'কেওয়াইসি ভেরিফিকেশন জমা দিন'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Top Alert Banner
  Widget _buildTopAlertBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded,
              color: Colors.red.shade700, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LanguageService.tr('You can\'t invest without doing the KYC verification.', 'কেওয়াইসি ভেরিফিকেশন ছাড়া আপনি বিনিয়োগ করতে পারবেন না।'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  LanguageService.tr('Complete your identity verification to unlock investing.', 'বিনিয়োগের সুবিধা পাওয়ার জন্য ভেরিফিকেশন সম্পন্ন করুন।'),
                  style: TextStyle(fontSize: 11.5, color: Colors.red.shade800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Section Card Container
  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  // Input Field Decoration
  InputDecoration _buildInputDecoration({
    required String label,
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13),
      prefixIcon: icon != null ? Icon(icon, color: Colors.teal, size: 20) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.teal, width: 2),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  // Image Upload Box Widget
  Widget _buildImageUploadBox({
    required String label,
    required File? file,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: file != null ? Colors.teal : Colors.grey.shade300,
              width: file != null ? 2 : 1),
        ),
        child: file != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(file, fit: BoxFit.cover, width: double.infinity),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_upload_outlined,
                      color: Colors.teal, size: 28),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal),
                  ),
                ],
              ),
      ),
    );
  }
}
