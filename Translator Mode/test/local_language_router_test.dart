import 'package:flutter_test/flutter_test.dart';
import 'package:matuk_translator_mode/models/translation_language.dart';
import 'package:matuk_translator_mode/services/local_language_router.dart';

void main() {
  final staff = translationLanguages.firstWhere((item) => item.code == 'en');
  final tagalog = translationLanguages.firstWhere((item) => item.code == 'tl');
  final french = translationLanguages.firstWhere((item) => item.code == 'fr');

  test('Staff speech routes to current Guest language', () async {
    final router = LocalLanguageRouter();
    final route = await router.route(
      text: 'Thank you very much for your help.',
      staffLanguage: staff,
      guestLanguage: tagalog,
      hintSide: TranslationSide.a,
      autoDetect: true,
    );

    expect(route.source.code, 'en');
    expect(route.target.code, 'tl');
    expect(route.guestLanguage.code, 'tl');
  });

  test('new non-Staff language becomes latest Guest', () async {
    final router = LocalLanguageRouter();
    final route = await router.route(
      text: 'Bonjour, merci beaucoup pour votre aide.',
      staffLanguage: staff,
      guestLanguage: tagalog,
      hintSide: TranslationSide.b,
      autoDetect: true,
    );

    expect(route.source.code, french.code);
    expect(route.target.code, staff.code);
    expect(route.guestLanguage.code, french.code);
  });

  test('manual mode follows the selected side without auto detection', () async {
    final router = LocalLanguageRouter();
    final route = await router.route(
      text: 'short ambiguous utterance',
      staffLanguage: staff,
      guestLanguage: tagalog,
      hintSide: TranslationSide.b,
      autoDetect: false,
    );

    expect(route.source.code, tagalog.code);
    expect(route.target.code, staff.code);
  });
}
