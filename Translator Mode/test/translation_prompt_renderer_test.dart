import 'package:flutter_test/flutter_test.dart';
import 'package:matuk_translator_mode/core/translation_prompt_renderer.dart';
import 'package:matuk_translator_mode/models/translation_language.dart';

void main() {
  const renderer = TranslationPromptRenderer();

  test('renders strict Gemma translation turn', () {
    final prompt = renderer.render(
      source: translationLanguages[0],
      target: translationLanguages[1],
      text: 'Good morning, how are you today?',
    );

    expect(prompt, startsWith('<start_of_turn>user\n'));
    expect(prompt, contains('English (en)'));
    expect(prompt, contains('Dutch (Flemish) (nl-BE)'));
    expect(prompt, contains('Output only the translated text.'));
    expect(prompt, contains('natural Belgian Dutch/Flemish'));
    expect(prompt, contains('Good morning, how are you today?'));
    expect(prompt, endsWith('<start_of_turn>model\n'));
  });

  test('rejects empty source text', () {
    expect(
      () => renderer.render(
        source: translationLanguages[0],
        target: translationLanguages[1],
        text: '   ',
      ),
      throwsArgumentError,
    );
  });
}
