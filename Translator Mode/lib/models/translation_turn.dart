import 'translation_language.dart';

class TranslationTurn {
  const TranslationTurn({
    required this.sourceSide,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.sourceText,
    required this.translatedText,
  });

  final TranslationSide sourceSide;
  final TranslationLanguage sourceLanguage;
  final TranslationLanguage targetLanguage;
  final String sourceText;
  final String translatedText;
}
