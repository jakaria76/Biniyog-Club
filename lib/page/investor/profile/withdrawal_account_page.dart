import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import '../../../theme/app_colors.dart';

/// Website er profile "Withdrawal account" — lav ar withdrawal kon bank ba
/// mobile banking e jabe. Finance profit dewar shomoy eta dekhe.
///
/// Profile page e [WithdrawalAccountCard] dekhay; "Edit" chaple ei page.
class WithdrawalAccountPage extends StatefulWidget {
  final Map<String, String> account;

  const WithdrawalAccountPage({super.key, required this.account});

  @override
  State<WithdrawalAccountPage> createState() => _WithdrawalAccountPageState();
}

class _WithdrawalAccountPageState extends State<WithdrawalAccountPage> {
  static const Color emerald = BC.primary;
  static const Color emeraldSoft = BC.secondary;
  static const Color ivory = BC.background;
  static const Color ink = BC.foreground;
  static const Color muted = BC.mutedForeground;
  static const Color line = BC.border;
  static const Color danger = BC.destructive;

  late final Map<String, TextEditingController> _c = {
    for (final k in ['bankName', 'bankAccountName', 'bankAccountNumber', 'bankBranch', 'mobileNumber'])
      k: TextEditingController(text: widget.account[k] ?? ''),
  };
  late String _provider = widget.account['mobileProvider'] ?? '';
  Map<String, String> _errors = {};
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final user = await AuthService.getUserData();
    final uid = user?['id']?.toString() ?? '';
    setState(() {
      _saving = true;
      _error = null;
      _errors = {};
    });
    final res = await DatabaseService.saveWithdrawalAccount(
      userId: uid,
      bankName: _c['bankName']!.text,
      bankAccountName: _c['bankAccountName']!.text,
      bankAccountNumber: _c['bankAccountNumber']!.text,
      bankBranch: _c['bankBranch']!.text,
      mobileProvider: _provider,
      mobileNumber: _c['mobileNumber']!.text,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(LanguageService.tr('Withdrawal account saved.', 'উত্তোলনের অ্যাকাউন্ট সেভ হয়েছে।')),
        backgroundColor: emerald,
      ));
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _saving = false;
      _error = res['message']?.toString();
      _errors = Map<String, String>.from((res['fieldErrors'] as Map?) ?? const {});
    });
  }

  InputDecoration _dec(String label, IconData icon, String key) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 13, color: muted),
    prefixIcon: Icon(icon, color: emerald, size: 19),
    errorText: _errors[key],
    isDense: true,
    filled: true,
    fillColor: ivory,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line)),
    focusedBorder:
    OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: emerald, width: 1.4)),
  );

  Widget _section(String title, IconData icon, String sub, List<Widget> children) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: emeraldSoft, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 15, color: emerald),
            ),
            const SizedBox(width: 9),
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 35, top: 1, bottom: 10),
          child: Text(sub, style: const TextStyle(fontSize: 11.5, color: muted)),
        ),
        ...children,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) => Scaffold(
        backgroundColor: ivory,
        appBar: AppBar(
          backgroundColor: ivory,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 54,
          iconTheme: const IconThemeData(color: ink),
          title: Text(LanguageService.tr('Withdrawal Account', 'উত্তোলনের অ্যাকাউন্ট'),
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 17.5)),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: line))),
            child: SizedBox(
              height: 46,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: emerald,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: emerald.withAlpha(140),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(LanguageService.tr('Save', 'সেভ করুন'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
            children: [
              Text(
                LanguageService.tr(
                    'Where we send your profit and withdrawals. Add a bank account, a mobile banking number, or both. Leave a section empty to remove it.',
                    'আপনার লাভ ও উত্তোলনের টাকা কোথায় পাঠানো হবে। ব্যাংক, মোবাইল ব্যাংকিং বা দুটোই দিন। কোনো অংশ খালি রাখলে মুছে যাবে।'),
                style: const TextStyle(fontSize: 12.5, color: muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              _section(LanguageService.tr('Bank account', 'ব্যাংক অ্যাকাউন্ট'), Icons.account_balance_outlined,
                  LanguageService.tr('Optional', 'ঐচ্ছিক'), [
                    TextField(controller: _c['bankName'], decoration: _dec(LanguageService.tr('Bank name', 'ব্যাংকের নাম'), Icons.account_balance_outlined, 'bankName')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: _c['bankAccountName'],
                        decoration: _dec(LanguageService.tr('Account holder name', 'অ্যাকাউন্টধারীর নাম'), Icons.person_outline_rounded, 'bankAccountName')),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _c['bankAccountNumber'],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]'))],
                      decoration: _dec(LanguageService.tr('Account number', 'অ্যাকাউন্ট নম্বর'), Icons.numbers_rounded, 'bankAccountNumber'),
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: _c['bankBranch'], decoration: _dec(LanguageService.tr('Branch', 'শাখা'), Icons.location_on_outlined, 'bankBranch')),
                  ]),
              const SizedBox(height: 12),
              _section(LanguageService.tr('Mobile banking', 'মোবাইল ব্যাংকিং'), Icons.smartphone_rounded,
                  LanguageService.tr('Optional', 'ঐচ্ছিক'), [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final p in DatabaseService.mobileBankingProviders)
                          ChoiceChip(
                            label: Text(p),
                            selected: _provider == p,
                            showCheckmark: false,
                            selectedColor: emerald,
                            backgroundColor: ivory,
                            side: BorderSide(color: _provider == p ? emerald : line),
                            labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _provider == p ? Colors.white : ink),
                            onSelected: (_) => setState(() => _provider = _provider == p ? '' : p),
                          ),
                      ],
                    ),
                    if (_errors['mobileProvider'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_errors['mobileProvider']!, style: const TextStyle(fontSize: 12, color: danger)),
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _c['mobileNumber'],
                      keyboardType: TextInputType.phone,
                      decoration: _dec(LanguageService.tr('Mobile number (01XXXXXXXXX)', 'মোবাইল নম্বর (01XXXXXXXXX)'), Icons.phone_iphone_rounded,
                          'mobileNumber'),
                    ),
                  ]),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(fontSize: 12.5, color: danger)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Profile page er card — nije load kore, "Edit" chaple [WithdrawalAccountPage]
class WithdrawalAccountCard extends StatefulWidget {
  const WithdrawalAccountCard({super.key});

  @override
  State<WithdrawalAccountCard> createState() => _WithdrawalAccountCardState();
}

class _WithdrawalAccountCardState extends State<WithdrawalAccountCard> {
  Map<String, String>? _a;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = await AuthService.getUserData();
    final a = await DatabaseService.getWithdrawalAccount(user?['id']?.toString() ?? '');
    if (!mounted) return;
    setState(() {
      _a = a;
      _loading = false;
    });
  }

  Future<void> _edit() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => WithdrawalAccountPage(account: _a ?? const {})),
    );
    if (ok == true && mounted) _load();
  }

  Widget _row(String label, String? value, {bool mono = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, color: BC.mutedForeground))),
        Flexible(
          child: Text((value ?? '').isEmpty ? '—' : value!,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: BC.foreground, fontFamily: mono ? 'monospace' : null)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final hasBank = (a?['bankAccountNumber'] ?? '').isNotEmpty;
    final hasMobile = (a?['mobileNumber'] ?? '').isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: BC.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 18, color: BC.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(LanguageService.tr('Where your profit is paid', 'লাভ কোথায় পাবেন'),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: BC.foreground)),
              ),
              if (!_loading && a != null)
                TextButton.icon(
                  onPressed: _edit,
                  style: TextButton.styleFrom(foregroundColor: BC.primary, visualDensity: VisualDensity.compact),
                  icon: Icon(hasBank || hasMobile ? Icons.edit_outlined : Icons.add_rounded, size: 16),
                  label: Text(hasBank || hasMobile ? LanguageService.tr('Edit', 'এডিট') : LanguageService.tr('Add', 'যোগ করুন'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2, color: BC.primary, backgroundColor: Colors.transparent)
          else if (a == null)
            Text(LanguageService.tr('Could not load. Pull down to refresh.', 'লোড করা যায়নি। নিচে টেনে রিফ্রেশ করুন।'),
                style: const TextStyle(fontSize: 12, color: BC.mutedForeground))
          else if (!hasBank && !hasMobile)
              Text(
                LanguageService.tr('No withdrawal account yet. Add one so finance can pay your profit.',
                    'এখনো কোনো অ্যাকাউন্ট দেওয়া হয়নি। লাভ পেতে একটি যোগ করুন।'),
                style: const TextStyle(fontSize: 12, color: BC.mutedForeground, height: 1.4),
              )
            else ...[
                if (hasBank) ...[
                  _row(LanguageService.tr('Bank', 'ব্যাংক'), a['bankName']),
                  _row(LanguageService.tr('Account name', 'অ্যাকাউন্টের নাম'), a['bankAccountName']),
                  _row(LanguageService.tr('Account number', 'অ্যাকাউন্ট নম্বর'), a['bankAccountNumber'], mono: true),
                  if ((a['bankBranch'] ?? '').isNotEmpty) _row(LanguageService.tr('Branch', 'শাখা'), a['bankBranch']),
                ],
                if (hasBank && hasMobile) const Divider(height: 14, color: BC.border),
                if (hasMobile) _row(a['mobileProvider'] ?? LanguageService.tr('Mobile', 'মোবাইল'), a['mobileNumber'], mono: true),
              ],
        ],
      ),
    );
  }
}