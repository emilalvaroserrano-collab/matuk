import 'package:supertonic_flutter/supertonic_flutter.dart';

class SupertonicTtsService {
  final SupertonicTTS _tts = SupertonicTTS();
  final TTSAudioPlayer _player = TTSAudioPlayer();
  bool _initialized = false;

  Future<bool> modelsReady() => SupertonicTTS.modelsReady();

  Future<void> prepare({
    required void Function(int done, int total, String file, double progress)
        onProgress,
  }) async {
    if (!await SupertonicTTS.modelsReady()) {
      await SupertonicTTS.preDownloadModels(onProgress: onProgress);
    }
    await initialize();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    await _tts.initialize();
    _initialized = true;
  }

  Future<void> speak(
    String text, {
    required String language,
    String voiceStyle = 'M1',
  }) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;
    if (!_initialized) await initialize();
    await _player.stop();
    final result = await _tts.synthesize(
      cleaned,
      language: language,
      voiceStyle: voiceStyle,
      config: TTSConfig(
        speechSpeed: 1.03,
        denoisingSteps: 5,
      ),
    );
    await _player.play(result);
  }

  Future<void> stop() => _player.stop();

  void dispose() {
    _player.dispose();
    _tts.dispose();
  }
}
