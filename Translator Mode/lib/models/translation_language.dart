enum TranslationSide { a, b }

class TranslationLanguage {
  const TranslationLanguage({
    required this.code,
    required this.displayName,
    required this.ttsCode,
  });

  final String code;
  final String displayName;
  final String ttsCode;
}

const translationLanguages = <TranslationLanguage>[
  TranslationLanguage(code: 'en', displayName: 'English (US)', ttsCode: 'en'),
  TranslationLanguage(
    code: 'tl',
    displayName: 'Tagalog (Filipino)',
    ttsCode: 'tl',
  ),
  TranslationLanguage(
    code: 'nl-BE',
    displayName: 'Dutch (Flemish)',
    ttsCode: 'nl',
  ),
  TranslationLanguage(code: 'fr', displayName: 'French', ttsCode: 'fr'),
  TranslationLanguage(code: 'de', displayName: 'German', ttsCode: 'de'),
  TranslationLanguage(code: 'es', displayName: 'Spanish', ttsCode: 'es'),
  TranslationLanguage(code: 'it', displayName: 'Italian', ttsCode: 'it'),
  TranslationLanguage(code: 'pt', displayName: 'Portuguese', ttsCode: 'pt'),
];
