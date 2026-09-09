import 'package:flutter_test/flutter_test.dart';
import 'package:matuk_translator_mode/core/sentence_endpoint_detector.dart';

void main() {
  test('splits an utterance into complete sentence payloads', () {
    expect(
      SentenceEndpointDetector.splitForShipping(
        'Hello there. How are you? I am fine!',
      ),
      ['Hello there.', 'How are you?', 'I am fine!'],
    );
  });

  test('does not split common abbreviations or decimals', () {
    expect(
      SentenceEndpointDetector.splitForShipping(
        'Dr. Smith prescribed 2.5 mg today. Take it tonight.',
      ),
      ['Dr. Smith prescribed 2.5 mg today.', 'Take it tonight.'],
    );
  });

  test('keeps an unpunctuated silence-finalized utterance as one payload', () {
    expect(
      SentenceEndpointDetector.splitForShipping('please open the window'),
      ['please open the window'],
    );
  });
}
