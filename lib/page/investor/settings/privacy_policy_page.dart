import 'package:flutter/material.dart';

import '../../../services/language_service.dart';
import 'legal_web_page.dart';

/// Privacy Policy — biniyogclub.com/privacy er asol lekha app er bhitorei.
/// Age ekhane hate lekha (banano) copy chilo; ekhon website theke ashe,
/// tai website update korlei app o update thake.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) => LegalWebPage(
        title: LanguageService.tr('Privacy Policy', 'গোপনীয়তা নীতি'),
        url: 'https://www.biniyogclub.com/privacy',
      ),
    );
  }
}