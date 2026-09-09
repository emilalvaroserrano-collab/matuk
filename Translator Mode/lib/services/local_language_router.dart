import 'package:flutter_langdetect/flutter_langdetect.dart' as langdetect;

import '../models/translation_language.dart';

class LocalLanguageRoute {
  const LocalLanguageRoute({
    required this.source,
    required this.target,
    required this.guestLanguage,
    required this.confidence,
    required this.usedFallback,
  });

  final TranslationLanguage source;
  final TranslationLanguage target;
  final TranslationLanguage guestLanguage;
  final double confidence;
  final bool usedFallback;
}

/// Purely on-device language routing for the Dual Translate live session.
///
/// Language A is always the Staff language. The latest detected non-Staff
/// language becomes Language B (Guest). Staff speech is translated to the
/// current Guest language; every supported non-Staff language is translated
/// back to Staff and becomes the new Guest language.
class LocalLanguageRouter {
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await langdetect.initLangDetect();
    _initialized = true;
  }

  Future<LocalLanguageRoute> route({
    required String text,
    required TranslationLanguage staffLanguage,
    required TranslationLanguage guestLanguage,
    TranslationSide hintSide = TranslationSide.a,
    bool autoDetect = true,
  }) async {
    if (!autoDetect) {
      final source = hintSide == TranslationSide.a
          ? staffLanguage
          : guestLanguage;
      final target = hintSide == TranslationSide.a
          ? guestLanguage
          : staffLanguage;
      return LocalLanguageRoute(
        source: source,
        target: target,
        guestLanguage: guestLanguage,
        confidence: 1,
        usedFallback: false,
      );
    }

    await initialize();

    final fallback = hintSide == TranslationSide.a
        ? staffLanguage
        : guestLanguage;
    final detected = _detectSupported(text, fallback: fallback);
    final source = detected.language;
    final staffCode = _canonicalCode(staffLanguage.code);
    final sourceCode = _canonicalCode(source.code);

    if (sourceCode == staffCode) {
      return LocalLanguageRoute(
        source: staffLanguage,
        target: guestLanguage,
        guestLanguage: guestLanguage,
        confidence: detected.confidence,
        usedFallback: detected.usedFallback,
      );
    }

    return LocalLanguageRoute(
      source: source,
      target: staffLanguage,
      guestLanguage: source,
      confidence: detected.confidence,
      usedFallback: detected.usedFallback,
    );
  }

  _DetectedLanguage _detectSupported(
    String rawText, {
    required TranslationLanguage fallback,
  }) {
    final text = rawText.trim();
    if (text.isEmpty) {
      return _DetectedLanguage(fallback, 0, true);
    }

    final heuristic = _strongLexicalMatch(text);
    if (heuristic != null) {
      return _DetectedLanguage(heuristic, 0.99, false);
    }

    try {
      final results = langdetect.detectLangs(text);
      for (final result in results) {
        final match = _languageForCode(result.lang);
        if (match == null) continue;
        // Language detection becomes noisy on very short utterances. Prefer
        // the current speaker hint unless the detector has a meaningful lead.
        final threshold = _wordCount(text) <= 2 ? 0.72 : 0.42;
        if (result.prob >= threshold) {
          return _DetectedLanguage(match, result.prob, false);
        }
      }
    } catch (_) {
      // Fall back to the current staff/guest hint rather than stopping the
      // live translation session because of a language-ID failure.
    }

    return _DetectedLanguage(fallback, 0, true);
  }

  TranslationLanguage? _strongLexicalMatch(String rawText) {
    final normalized = rawText
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{M}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return null;

    final tokens = normalized.split(' ').toSet();
    String? bestCode;
    var bestScore = 0;

    for (final entry in _lexicalSignals.entries) {
      var score = 0;
      for (final signal in entry.value) {
        if (signal.contains(' ')) {
          if (normalized.contains(signal)) score += 2;
        } else if (tokens.contains(signal)) {
          score += 1;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestCode = entry.key;
      }
    }

    if (bestCode == null) return null;
    // One highly distinctive word is enough; common one-word signals are
    // intentionally omitted from the table to avoid false switches.
    return _languageForCode(bestCode);
  }

  TranslationLanguage? _languageForCode(String code) {
    final canonical = _canonicalCode(code);
    for (final language in translationLanguages) {
      if (_canonicalCode(language.code) == canonical) return language;
    }
    return null;
  }

  String _canonicalCode(String code) {
    final lower = code.toLowerCase().replaceAll('_', '-');
    if (lower == 'fil' || lower.startsWith('fil-') || lower == 'tl') {
      return 'tl';
    }
    if (lower.startsWith('nl')) return 'nl';
    return lower.split('-').first;
  }

  int _wordCount(String text) =>
      text.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).length;

  static const Map<String, Set<String>> _lexicalSignals = {
    'en': {
      'hello',
      'goodbye',
      'thanks',
      'thank you',
      'please help',
      'good morning',
      'good evening',
    },
    'tl': {
      'kumusta',
      'salamat',
      'magandang umaga',
      'magandang gabi',
      'opo',
      'hindi po',
      'masakit',
      'gamot',
      'doktor',
      'saan',
      'bakit',
      'paano',
    },
    'nl': {
      'goedemorgen',
      'goeiemorgen',
      'goedenavond',
      'dankjewel',
      'dank u',
      'alstublieft',
      'alsjeblieft',
      'medicijn',
      'waarom',
    },
    'fr': {
      'bonjour',
      'bonsoir',
      'merci',
      's il vous plaît',
      'au revoir',
      'pourquoi',
    },
    'de': {
      'guten morgen',
      'guten abend',
      'danke',
      'bitte helfen',
      'auf wiedersehen',
      'warum',
    },
    'es': {
      'hola',
      'gracias',
      'buenos días',
      'buenas noches',
      'por favor',
      'adiós',
      'dónde',
    },
    'it': {
      'buongiorno',
      'buonasera',
      'grazie',
      'per favore',
      'arrivederci',
      'perché',
    },
    'pt': {
      'olá',
      'obrigado',
      'obrigada',
      'bom dia',
      'boa noite',
      'por favor',
      'onde',
    },
  };
}

class _DetectedLanguage {
  const _DetectedLanguage(this.language, this.confidence, this.usedFallback);

  final TranslationLanguage language;
  final double confidence;
  final bool usedFallback;
}
