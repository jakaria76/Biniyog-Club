import 'package:flutter/material.dart';

import '../../../services/language_service.dart';
import 'legal_web_page.dart';

/// Terms of Service — biniyogclub.com/terms er asol lekha app er bhitorei.
/// Age ekhane hate lekha (banano) copy chilo; ekhon website theke ashe,
/// tai website update korlei app o update thake.
class TermsAndConditionsPage extends StatelessWidget {
  const TermsAndConditionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) => LegalWebPage(
        title: LanguageService.tr('Terms of Service', 'ব্যবহারের শর্তাবলী'),
        url: 'https://www.biniyogclub.com/terms',
      ),
    );
  }
}