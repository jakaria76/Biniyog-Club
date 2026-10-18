import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/auth_service.dart';
import '../../../services/bd_location_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';

/// Profile edit — nam, mobile, email, jonmo tarikh, NID, thikana (bibhag →
/// jela → upazila), nominee, pesha / ay / obhiggota / jhuki.
/// Kono field khali kore Save dile oi tottho muche jay.
/// Save hole `Navigator.pop(context, true)`.
class EditProfilePage extends StatefulWidget {
  /// getUserProfileFull er result
  final Map<String, dynamic> profile;

  const EditProfilePage({super.key, required this.profile});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  // ─── Palette ───
  static const Color emerald = Color(0xFF0E4A37);
  static const Color goldDeep = Color(0xFF8A6A3A);
  static const Color goldSoft = Color(0xFFF6EEDF);
  static const Color ivory = Color(0xFFF7F4EE);
  static const Color ink = Color(0xFF1C2421);
  static const Color muted = Color(0xFF6E736F);
  static const Color line = Color(0xFFE8E2D7);
  static const Color danger = Color(0xFFB4413A);

  static const String _otherKey = '__other__';

  /// DB te English (website er sathe mile), screen e bhasha onujayi
  static const List<(String, String)> _relations = [
    ('Father', 'বাবা'),
    ('Mother', 'মা'),
    ('Spouse', 'স্বামী/স্ত্রী'),
    ('Son', 'ছেলে'),
    ('Daughter', 'মেয়ে'),
    ('Brother', 'ভাই'),
    ('Sister', 'বোন'),
    ('Other', 'অন্যান্য'),
  ];
  static const List<(String, String)> _incomes = [
    ('Below 3 Lakh BDT', '৩ লাখ টাকার কম'),
    ('3–6 Lakh BDT', '৩–৬ লাখ টাকা'),
    ('6–12 Lakh BDT', '৬–১২ লাখ টাকা'),
    ('12–25 Lakh BDT', '১২–২৫ লাখ টাকা'),
    ('Above 25 Lakh BDT', '২৫ লাখ টাকার বেশি'),
  ];
  static const List<(String, String)> _experiences = [
    ('Beginner', 'নতুন'),
    ('Some experience', 'কিছু অভিজ্ঞতা আছে'),
    ('Experienced', 'অভিজ্ঞ'),
  ];
  static const List<(String, String)> _risks = [
    ('Low', 'কম'),
    ('Medium', 'মাঝারি'),
    ('High', 'বেশি'),
  ];

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _nid;
  late final TextEditingController _house;
  late final TextEditingController _otherArea;
  late final TextEditingController _postCode;
  late final TextEditingController _nomineeName;
  late final TextEditingController _nomineeNid;
  late final TextEditingController _occupation;

  DateTime? _dob;
  String? _division;
  String? _district;
  String? _upazila;
  String? _relation;
  String? _income;
  String? _experience;
  String? _risk;

  bool _saving = false;
  String? _error;

  Map<String, String> get _p {
    final raw = (widget.profile['investorProfile'] as Map?) ?? {};
    return raw.map((k, v) => MapEntry(k.toString(), v?.toString().trim() ?? ''));
  }

  @override
  void initState() {
    super.initState();
    final p = _p;
    _name = TextEditingController(text: widget.profile['name']?.toString() ?? '');
    _phone = TextEditingController(text: widget.profile['phone']?.toString() ?? '');
    _email = TextEditingController(text: widget.profile['email']?.toString() ?? '');
    _nid = TextEditingController(text: p['nationalId'] ?? '');
    _nomineeName = TextEditingController(text: p['nomineeName'] ?? '');
    _nomineeNid = TextEditingController(text: p['nomineeNationalId'] ?? '');
    _occupation = TextEditingController(text: p['occupation'] ?? '');
    _house = TextEditingController();
    _otherArea = TextEditingController();
    _postCode = TextEditingController();

    final dob = DateTime.tryParse(p['dateOfBirth'] ?? '');
    if (dob != null) _dob = DateTime(dob.year, dob.month, dob.day);

    _relation = _nonEmpty(p['nomineeRelation']);
    _income = _nonEmpty(p['annualIncomeRange']);
    _experience = _nonEmpty(p['investmentExperience']);
    _risk = _nonEmpty(p['riskTolerance']);

    _parseAddress(p['address'] ?? '', p['city'] ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _nid, _house, _otherArea, _postCode, _nomineeName, _nomineeNid, _occupation]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _nonEmpty(String? s) => (s ?? '').trim().isEmpty ? null : s!.trim();

  // ═════════════════════════════════════════════════════════
  // THIKANA — DB te ek line: "Basha 12, Mirpur, Dhaka, Dhaka Division - 1216"
  // ═════════════════════════════════════════════════════════
  void _parseAddress(String address, String city) {
    var rest = address.trim();
    if (rest.isEmpty) {
      if (city.isNotEmpty) _matchDistrictAnywhere(city);
      return;
    }
    final post = RegExp(r'\s*-\s*(\d{4})$').firstMatch(rest);
    if (post != null) {
      _postCode.text = post.group(1)!;
      rest = rest.substring(0, post.start);
    }
    final parts = rest.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    // Shesh theke: "<X> Division" → jela → upazila
    if (parts.isNotEmpty && parts.last.endsWith(' Division')) {
      final div = parts.last.substring(0, parts.last.length - ' Division'.length).trim();
      if (BdLocationService.divisionKeys().contains(div)) {
        _division = div;
        parts.removeLast();
        if (parts.isNotEmpty && BdLocationService.districtKeys(div).contains(parts.last)) {
          _district = parts.removeLast();
          if (parts.isNotEmpty) {
            final area = parts.last;
            if (BdLocationService.upazilaKeys(div, _district).contains(area)) {
              _upazila = parts.removeLast();
            } else if (parts.length >= 2) {
              // List e nei — "Other" hishebe
              _upazila = _otherKey;
              _otherArea.text = parts.removeLast();
            }
          }
        }
      }
    }
    _house.text = parts.join(', ');
    if (_district == null && city.isNotEmpty) _matchDistrictAnywhere(city);
  }

  void _matchDistrictAnywhere(String district) {
    for (final div in BdLocationService.divisionKeys()) {
      if (BdLocationService.districtKeys(div).contains(district)) {
        _division = div;
        _district = district;
        return;
      }
    }
  }

  String _composedAddress() {
    final area = _upazila == _otherKey ? _otherArea.text.trim() : (_upazila ?? '');
    final parts = <String>[
      _house.text.trim(),
      if (area.isNotEmpty) area,
      if (_district != null) _district!,
      if (_division != null) '${_division!} Division',
    ].where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    final post = _postCode.text.trim();
    return post.isEmpty ? parts.join(', ') : '${parts.join(', ')} - $post';
  }

  // ═════════════════════════════════════════════════════════
  // VALIDATION
  // ═════════════════════════════════════════════════════════
  String get _req => LanguageService.tr('Required', 'আবশ্যক');

  String? _nidValidator(String? v, {bool nominee = false}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    if (!RegExp(r'^(\d{10}|\d{13}|\d{17})$').hasMatch(t)) {
      return LanguageService.tr('NID must be 10, 13 or 17 digits', 'এনআইডি ১০, ১৩ বা ১৭ সংখ্যার হতে হবে');
    }
    if (nominee && t == _nid.text.trim()) {
      return LanguageService.tr('Nominee NID cannot be your own NID', 'নমিনীর এনআইডি আপনার নিজের হতে পারবে না');
    }
    return null;
  }

  bool _isAdult(DateTime d) {
    final now = DateTime.now();
    return !d.isAfter(DateTime(now.year - 18, now.month, now.day));
  }

  String _fmtDob(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDob() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: LanguageService.tr('Date of birth', 'জন্ম তারিখ'),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  // ═════════════════════════════════════════════════════════
  // SAVE
  // ═════════════════════════════════════════════════════════
  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) {
      setState(() => _error = LanguageService.tr('Please fix the highlighted fields.', 'লাল চিহ্নিত ঘরগুলো ঠিক করুন।'));
      return;
    }
    if (_dob != null && !_isAdult(_dob!)) {
      setState(() => _error = LanguageService.tr('You must be at least 18 years old.', 'বয়স কমপক্ষে ১৮ বছর হতে হবে।'));
      return;
    }
    final nomineeAny = _nomineeName.text.trim().isNotEmpty || _nomineeNid.text.trim().isNotEmpty;
    if (nomineeAny && _relation == null) {
      setState(() => _error = LanguageService.tr('Please select your relation with the nominee.', 'নমিনীর সাথে সম্পর্ক বেছে নিন।'));
      return;
    }

    setState(() => _saving = true);
    final userId = widget.profile['id']?.toString() ?? '';
    final res = await DatabaseService.updateUserProfile(
      userId: userId,
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      dateOfBirth: _dob,
      profile: {
        'nationalId': _nid.text.trim(),
        'address': _composedAddress(),
        'city': _district ?? '',
        'nomineeName': _nomineeName.text.trim(),
        'nomineeNationalId': _nomineeNid.text.trim(),
        'nomineeRelation': nomineeAny ? (_relation ?? '') : '',
        'occupation': _occupation.text.trim(),
        'annualIncomeRange': _income ?? '',
        'investmentExperience': _experience ?? '',
        'riskTolerance': _risk ?? '',
      },
    );
    if (!mounted) return;

    if (res['success'] == true) {
      // Login er session e nam / email / phone o notun
      final u = await AuthService.getUserData();
      final data = Map<String, dynamic>.from(res['data'] as Map);
      await AuthService.saveUserData({...?u, ...data});
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LanguageService.tr('Profile updated.', 'প্রোফাইল আপডেট হয়েছে।')),
          backgroundColor: emerald,
        ),
      );
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = res['message']?.toString() ??
            LanguageService.tr('Could not save. Please try again.', 'সেভ করা যায়নি। আবার চেষ্টা করুন।');
      });
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
              LanguageService.tr('Edit Profile', 'প্রোফাইল এডিট'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: line))),
              child: SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      : const Icon(Icons.check_rounded),
                  label: Text(LanguageService.tr('Save Changes', 'পরিবর্তন সেভ করুন'),
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    backgroundColor: emerald,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: emerald.withAlpha(140),
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ),
          body: AbsorbPointer(
            absorbing: _saving,
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: [
                  Text(
                    LanguageService.tr('Clear any field and save to remove that information.',
                        'কোনো তথ্য মুছতে ঘরটি খালি করে সেভ করুন।'),
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 14),

                  // ─── Basic ───
                  _section(Icons.person_outline_rounded, LanguageService.tr('Basic information', 'মৌলিক তথ্য'), [
                    _field(_name, LanguageService.tr('Full name *', 'পূর্ণ নাম *'), Icons.person_outline,
                        caps: TextCapitalization.words, clearable: false, validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return _req;
                          if (t.length < 3) return LanguageService.tr('Name is too short', 'নাম খুব ছোট');
                          return null;
                        }),
                    _field(_phone, LanguageService.tr('Mobile number *', 'মোবাইল নম্বর *'), Icons.phone_outlined,
                        keyboard: TextInputType.phone,
                        clearable: false,
                        formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')), LengthLimitingTextInputFormatter(16)],
                        validator: (v) {
                          final t = DatabaseService.normalizeBdPhone((v ?? '').trim());
                          if (t.isEmpty) return _req;
                          if (!RegExp(r'^01[3-9]\d{8}$').hasMatch(t)) {
                            return LanguageService.tr('Enter a valid number (01XXXXXXXXX)', 'সঠিক নম্বর দিন (01XXXXXXXXX)');
                          }
                          return null;
                        }),
                    _field(_email, LanguageService.tr('Email', 'ইমেইল'), Icons.mail_outline_rounded,
                        keyboard: TextInputType.emailAddress, validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return null;
                          if (!RegExp(r'^[\w.+-]+@([\w-]+\.)+[A-Za-z]{2,}$').hasMatch(t)) {
                            return LanguageService.tr('Enter a valid email address', 'সঠিক ইমেইল দিন');
                          }
                          return null;
                        }),
                    _dobField(),
                  ]),

                  // ─── NID ───
                  _section(Icons.badge_outlined, LanguageService.tr('National ID', 'জাতীয় পরিচয়পত্র'), [
                    _field(_nid, LanguageService.tr('Your NID number', 'আপনার এনআইডি নম্বর'), Icons.badge_outlined,
                        keyboard: TextInputType.number,
                        hint: LanguageService.tr('10, 13 or 17 digits', '১০, ১৩ বা ১৭ সংখ্যা'),
                        formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(17)],
                        validator: (v) => _nidValidator(v)),
                  ]),

                  // ─── Address ───
                  _section(Icons.home_outlined, LanguageService.tr('Present address', 'বর্তমান ঠিকানা'), _addressFields()),

                  // ─── Nominee ───
                  _section(Icons.family_restroom_outlined, LanguageService.tr('Nominee', 'নমিনী'), [
                    Text(
                      LanguageService.tr('The person who receives your investment if something happens to you.',
                          'আপনার অবর্তমানে যিনি আপনার বিনিয়োগ পাবেন।'),
                      style: const TextStyle(fontSize: 11.5, color: muted),
                    ),
                    _field(_nomineeName, LanguageService.tr('Nominee name', 'নমিনীর নাম'), Icons.person_pin_outlined,
                        caps: TextCapitalization.words, onChanged: (_) => setState(() {})),
                    _field(_nomineeNid, LanguageService.tr('Nominee NID number', 'নমিনীর এনআইডি নম্বর'), Icons.badge_outlined,
                        keyboard: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(17)],
                        onChanged: (_) => setState(() {}),
                        validator: (v) => _nidValidator(v, nominee: true)),
                    _dropdown(
                      label: LanguageService.tr('Relation with nominee', 'নমিনীর সাথে সম্পর্ক'),
                      icon: Icons.people_outline,
                      value: _relation,
                      options: _relations,
                      onChanged: (v) => setState(() => _relation = v),
                    ),
                  ]),

                  // ─── Investor info ───
                  _section(Icons.work_outline_rounded, LanguageService.tr('Other information', 'অন্যান্য তথ্য'), [
                    _field(_occupation, LanguageService.tr('Occupation', 'পেশা'), Icons.work_outline_rounded,
                        caps: TextCapitalization.words,
                        hint: LanguageService.tr('e.g. Businessman, Engineer', 'যেমন: ব্যবসায়ী, ইঞ্জিনিয়ার')),
                    _dropdown(
                      label: LanguageService.tr('Annual income', 'বার্ষিক আয়'),
                      icon: Icons.account_balance_wallet_outlined,
                      value: _income,
                      options: _incomes,
                      onChanged: (v) => setState(() => _income = v),
                    ),
                    _dropdown(
                      label: LanguageService.tr('Investment experience', 'বিনিয়োগের অভিজ্ঞতা'),
                      icon: Icons.trending_up_rounded,
                      value: _experience,
                      options: _experiences,
                      onChanged: (v) => setState(() => _experience = v),
                    ),
                    _dropdown(
                      label: LanguageService.tr('Risk tolerance', 'ঝুঁকি সহনশীলতা'),
                      icon: Icons.speed_rounded,
                      value: _risk,
                      options: _risks,
                      onChanged: (v) => setState(() => _risk = v),
                    ),
                  ]),

                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFFBEAE8), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 17, color: danger),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12.5, color: danger))),
                        ],
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

  // ─── Address fields ───────────────────────────────────────
  List<Widget> _addressFields() {
    DropdownMenuItem<String> item(String key) => DropdownMenuItem(
      value: key,
      child: Text(BdLocationService.localize(key), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
    );
    final districts = BdLocationService.districtKeys(_division);
    final upazilas = BdLocationService.upazilaKeys(_division, _district);

    return [
      _clearableDropdown(
        keyBase: 'ep-division',
        label: LanguageService.tr('Division', 'বিভাগ'),
        icon: Icons.map_outlined,
        value: _division,
        items: BdLocationService.divisionKeys().map(item).toList(),
        onChanged: (v) => setState(() {
          _division = v;
          _district = null;
          _upazila = null;
        }),
      ),
      _clearableDropdown(
        keyBase: 'ep-district-$_division',
        label: LanguageService.tr('District', 'জেলা'),
        icon: Icons.location_city_outlined,
        value: _district,
        items: districts.map(item).toList(),
        onChanged: _division == null
            ? null
            : (v) => setState(() {
          _district = v;
          _upazila = null;
        }),
      ),
      _clearableDropdown(
        keyBase: 'ep-upazila-$_division-$_district',
        label: LanguageService.tr('Upazila / Thana', 'উপজেলা / থানা'),
        icon: Icons.place_outlined,
        value: _upazila,
        items: [
          ...upazilas.map(item),
          DropdownMenuItem(
            value: _otherKey,
            child: Text(LanguageService.tr('Other (type it)', 'অন্যান্য (লিখে দিন)'),
                style: const TextStyle(fontSize: 13.5, color: goldDeep, fontWeight: FontWeight.w600)),
          ),
        ],
        onChanged: _district == null ? null : (v) => setState(() => _upazila = v),
      ),
      if (_upazila == _otherKey)
        _field(_otherArea, LanguageService.tr('Upazila / Thana name', 'উপজেলা / থানার নাম'), Icons.edit_location_alt_outlined,
            caps: TextCapitalization.words),
      _field(_house, LanguageService.tr('House / road / village', 'বাসা / রোড / গ্রাম'), Icons.signpost_outlined,
          caps: TextCapitalization.sentences,
          maxLines: 3,
          hint: LanguageService.tr('e.g. House 12, Road 5, Block C', 'যেমন: বাসা ১২, রোড ৫, ব্লক সি')),
      _field(_postCode, LanguageService.tr('Post code', 'পোস্ট কোড'), Icons.markunread_mailbox_outlined,
          keyboard: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          validator: (v) {
            final t = (v ?? '').trim();
            if (t.isEmpty) return null;
            return t.length == 4 ? null : LanguageService.tr('Post code is 4 digits', 'পোস্ট কোড ৪ সংখ্যার');
          }),
    ];
  }

  // ─── Building blocks ──────────────────────────────────────
  Widget _section(IconData icon, String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: goldSoft, borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 17, color: goldDeep),
              ),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
            ],
          ),
          for (final c in children) ...[const SizedBox(height: 12), c],
        ],
      ),
    );
  }

  Widget _field(
      TextEditingController c,
      String label,
      IconData icon, {
        TextInputType? keyboard,
        TextCapitalization caps = TextCapitalization.none,
        List<TextInputFormatter>? formatters,
        String? Function(String?)? validator,
        ValueChanged<String>? onChanged,
        String? hint,
        int maxLines = 1,
        bool clearable = true,
      }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: c,
      builder: (context, value, _) => TextFormField(
        controller: c,
        keyboardType: maxLines > 1 ? TextInputType.multiline : keyboard,
        textCapitalization: caps,
        inputFormatters: formatters,
        minLines: 1,
        maxLines: maxLines,
        onChanged: onChanged,
        validator: validator,
        decoration: _dec(label, icon).copyWith(
          hintText: hint,
          suffixIcon: clearable && value.text.isNotEmpty
              ? IconButton(
            tooltip: LanguageService.tr('Clear', 'মুছুন'),
            icon: const Icon(Icons.close_rounded, size: 18, color: muted),
            onPressed: () {
              c.clear();
              onChanged?.call('');
              setState(() {});
            },
          )
              : null,
        ),
      ),
    );
  }

  Widget _dobField() {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _pickDob,
      child: InputDecorator(
        decoration: _dec(LanguageService.tr('Date of birth', 'জন্ম তারিখ'), Icons.cake_outlined).copyWith(
          suffixIcon: _dob == null
              ? const Icon(Icons.calendar_month_outlined, color: muted, size: 20)
              : IconButton(
            tooltip: LanguageService.tr('Clear', 'মুছুন'),
            icon: const Icon(Icons.close_rounded, size: 18, color: muted),
            onPressed: () => setState(() => _dob = null),
          ),
        ),
        child: Text(
          _dob == null ? LanguageService.tr('Select date', 'তারিখ বাছাই করুন') : _fmtDob(_dob!),
          style: TextStyle(fontSize: 14, color: _dob == null ? muted : ink),
        ),
      ),
    );
  }

  /// English value DB te, label bhasha onujayi. Purono kono value list e na
  /// thakle sheta-o option hishebe rakhi (harabe na).
  Widget _dropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<(String, String)> options,
    required ValueChanged<String?> onChanged,
  }) {
    final items = <DropdownMenuItem<String>>[
      for (final o in options)
        DropdownMenuItem(value: o.$1, child: Text(LanguageService.tr(o.$1, o.$2), style: const TextStyle(fontSize: 13.5))),
      if (value != null && !options.any((o) => o.$1 == value))
        DropdownMenuItem(value: value, child: Text(value, style: const TextStyle(fontSize: 13.5))),
    ];
    return _clearableDropdown(label: label, icon: icon, value: value, items: items, onChanged: onChanged);
  }

  Widget _clearableDropdown({
    String? keyBase,
    required String label,
    required IconData icon,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
  }) {
    return DropdownButtonFormField<String>(
      // Value bodlale (clear soho) field notun kore dekhay
      key: ValueKey('${keyBase ?? 'dd-$label'}-$value'),
      isExpanded: true,
      initialValue: value,
      items: items,
      onChanged: onChanged,
      decoration: _dec(label, icon).copyWith(
        suffixIcon: value != null && onChanged != null
            ? IconButton(
          tooltip: LanguageService.tr('Clear', 'মুছুন'),
          icon: const Icon(Icons.close_rounded, size: 18, color: muted),
          onPressed: () => onChanged(null),
        )
            : null,
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: muted),
      prefixIcon: Icon(icon, color: goldDeep, size: 20),
      filled: true,
      fillColor: ivory,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
      disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line.withAlpha(120))),
      focusedBorder:
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: emerald, width: 1.4)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: danger)),
      focusedErrorBorder:
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: danger, width: 1.4)),
    );
  }
}
