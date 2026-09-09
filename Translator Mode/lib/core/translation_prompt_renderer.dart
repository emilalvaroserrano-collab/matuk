import '../models/translation_language.dart';

class TranslationPromptRenderer {
  const TranslationPromptRenderer();

  String render({
    required TranslationLanguage source,
    required TranslationLanguage target,
    required String text,
    bool medicalMode = false,
  }) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Source text must not be empty');
    }

    final flemishRule = target.code == 'nl-BE'
        ? 'Use natural Belgian Dutch/Flemish wording and idiom, not stiff literal Dutch.'
        : 'Use natural, fluent wording appropriate for the target language.';

    final domainRule = medicalMode
        ? 'MEDICAL MODE: Preserve clinical terminology, symptoms, medicine names, dosages, units, timing, negation, and uncertainty exactly. Never simplify or infer medical facts that were not spoken.'
        : 'GENERAL MODE: Preserve meaning, tone, names, numbers, dates, units, and intent exactly.';

    return '''<|im_start|>system
You are Eb Translator, a real-time translation engine. Follow the translation instructions exactly and never add commentary.
$domainRule<|im_end|>
<|im_start|>user
Translate the source text from ${source.displayName} (${source.code}) to ${target.displayName} (${target.code}).

STRICT RULES:
1. Output only the translated text.
2. Never answer the source text, explain it, summarize it, or add notes.
3. Preserve meaning, intent, tone, names, numbers, dates, units, and medically or technically important details.
4. $flemishRule
5. If wording is ambiguous, choose the most contextually natural faithful translation without commentary.
6. Do not omit short words, negations, quantities, or qualifiers.

SOURCE_TEXT:
$cleaned<|im_end|>
<|im_start|>assistant
''';
  }
}
