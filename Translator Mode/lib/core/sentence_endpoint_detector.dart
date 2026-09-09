class SentenceEndpointDetector {
  static const Set<String> _abbreviations = {
    'mr.',
    'mrs.',
    'ms.',
    'dr.',
    'prof.',
    'sr.',
    'jr.',
    'st.',
    'vs.',
    'etc.',
    'e.g.',
    'i.e.',
  };

  static List<String> splitForShipping(String utterance) {
    final text = utterance.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return const [];

    final sentences = <String>[];
    var start = 0;
    var i = 0;

    while (i < text.length) {
      final char = text[i];
      final terminal = char == '.' || char == '!' || char == '?' || char == '…';
      if (!terminal || _isProtectedPeriod(text, i)) {
        i += 1;
        continue;
      }

      var end = i + 1;
      while (end < text.length && _isClosingPunctuation(text[end])) {
        end += 1;
      }

      final boundary = end >= text.length || _isWhitespace(text[end]);
      if (!boundary) {
        i += 1;
        continue;
      }

      final sentence = text.substring(start, end).trim();
      if (sentence.isNotEmpty) sentences.add(sentence);

      start = end;
      while (start < text.length && _isWhitespace(text[start])) {
        start += 1;
      }
      i = start;
    }

    final remainder = text.substring(start).trim();
    if (remainder.isNotEmpty) sentences.add(remainder);
    return sentences;
  }

  static bool endsWithTerminalPunctuation(String text) {
    var value = text.trimRight();
    while (value.isNotEmpty && _isClosingPunctuation(value[value.length - 1])) {
      value = value.substring(0, value.length - 1).trimRight();
    }
    if (value.isEmpty) return false;
    final char = value[value.length - 1];
    return char == '.' || char == '!' || char == '?' || char == '…';
  }

  static bool isSubstantial(String text) {
    final value = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value.length >= 2;
  }

  static bool _isProtectedPeriod(String text, int index) {
    if (text[index] != '.') return false;

    if (index > 0 &&
        index + 1 < text.length &&
        _isDigit(text[index - 1]) &&
        _isDigit(text[index + 1])) {
      return true;
    }

    final prefix = text.substring(0, index + 1).toLowerCase();
    for (final abbreviation in _abbreviations) {
      if (prefix.endsWith(abbreviation)) return true;
    }

    if (index > 0 &&
        _isAsciiLetter(text[index - 1]) &&
        (index == 1 || _isWhitespace(text[index - 2]))) {
      return true;
    }
    return false;
  }

  static bool _isClosingPunctuation(String char) =>
      char == '"' || char == "'" || char == '”' || char == '’' || char == ')' || char == ']';

  static bool _isWhitespace(String char) => RegExp(r'\s').hasMatch(char);

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  static bool _isAsciiLetter(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }
}
