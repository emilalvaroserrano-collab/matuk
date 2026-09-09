enum TranslationSide { a, b }

class TranslationLanguage {
  const TranslationLanguage({
    required this.code,
    required this.displayName,
    required this.ttsCode,
    required this.sttCode,
  });

  final String code;
  final String displayName;
  final String ttsCode;
  final String sttCode;
}

const translationLanguages = <TranslationLanguage>[
  TranslationLanguage(
    code: 'en',
    displayName: 'English (US)',
    ttsCode: 'en',
    sttCode: 'en-US',
  ),
  TranslationLanguage(
    code: 'tl',
    displayName: 'Tagalog (Filipino)',
    ttsCode: 'tl',
    sttCode: 'fil-PH',
  ),
  TranslationLanguage(
    code: 'nl-BE',
    displayName: 'Dutch (Flemish)',
    ttsCode: 'nl',
    sttCode: 'nl-BE',
  ),
  TranslationLanguage(
    code: 'fr',
    displayName: 'French',
    ttsCode: 'fr',
    sttCode: 'fr-FR',
  ),
  TranslationLanguage(
    code: 'de',
    displayName: 'German',
    ttsCode: 'de',
    sttCode: 'de-DE',
  ),
  TranslationLanguage(
    code: 'es',
    displayName: 'Spanish',
    ttsCode: 'es',
    sttCode: 'es-ES',
  ),
  TranslationLanguage(
    code: 'it',
    displayName: 'Italian',
    ttsCode: 'it',
    sttCode: 'it-IT',
  ),
  TranslationLanguage(
    code: 'pt',
    displayName: 'Portuguese',
    ttsCode: 'pt',
    sttCode: 'pt-PT',
  ),
];
