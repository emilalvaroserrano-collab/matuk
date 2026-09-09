import 'dart:async';
import 'dart:io';

import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

import '../core/sentence_endpoint_detector.dart';

class OfflineSttService {
  static const WhisperModelDescriptor _model = WhisperModelCatalog.base;

  // The reference live translator sends ~128 ms PCM chunks and keeps a
  // continuous session. Whisper needs a little more audio per decode, but a
  // 500 ms inference cadence keeps the UI responsive without translating
  // unstable partial words.
  static const WhisperStreamConfig _streamConfig = WhisperStreamConfig(
    updateInterval: Duration(milliseconds: 500),
    windowDuration: Duration(seconds: 12),
    confirmationLag: Duration(milliseconds: 1000),
  );
  static const Duration _punctuatedEndpointDelay = Duration(milliseconds: 450);
  static const Duration _silenceEndpointDelay = Duration(milliseconds: 1100);

  final WhisperModelManager _models = WhisperModelManager();

  WhisperEngine? _engine;
  WhisperStreamTask? _task;
  StreamSubscription<WhisperStreamUpdate>? _updates;
  Timer? _sentenceTimer;

  void Function(String text)? _onText;
  void Function(String sentence)? _onSentence;

  String _languageTag = 'auto';
  String _latestText = '';
  String? _lastError;
  bool _listening = false;
  bool _sentenceEmitted = false;
  bool _suppressSentenceCallbacks = false;

  bool get runtimeLoaded => _engine != null;
  bool get listening => _listening;

  void setLanguageTag(String languageTag) {
    _languageTag = languageTag;
  }

  Future<File?> _verifiedModel() async {
    try {
      return await _models.findCatalogModel(_model);
    } on FormatException {
      await _models.delete(_model.fileName);
      return null;
    }
  }

  Future<bool> modelsReady() async => await _verifiedModel() != null;

  Future<void> prepare({required void Function(double progress) onProgress}) async {
    final cached = await _verifiedModel();
    if (cached != null) {
      onProgress(1);
      return;
    }

    onProgress(0.01);
    await for (final progress in _models.downloadCatalogModel(_model)) {
      onProgress((progress.fraction ?? 0.0).clamp(0.0, 1.0));
    }

    final verified = await _verifiedModel();
    if (verified == null) {
      throw StateError('Speech Recognition model download did not verify.');
    }
    onProgress(1);
  }

  Future<void> initialize({void Function(double progress)? onProgress}) async {
    onProgress?.call(0.1);
    if (!await modelsReady()) {
      throw StateError('Speech Recognition model is not installed.');
    }
    onProgress?.call(1);
  }

  Future<void> warmRuntime() => _ensureEngineLoaded();

  Future<void> _ensureEngineLoaded() async {
    if (_engine != null) return;
    final modelFile = await _verifiedModel();
    if (modelFile == null) {
      throw StateError('Speech Recognition model is not installed.');
    }

    try {
      _engine = await WhisperEngine.load(
        modelFile.path,
        config: const WhisperConfig(
          useGpu: true,
          useFlashAttention: true,
        ),
      );
    } catch (_) {
      _engine = await WhisperEngine.load(
        modelFile.path,
        config: const WhisperConfig(
          useGpu: false,
          useFlashAttention: false,
        ),
      );
    }
  }

  Future<void> startListening(
    void Function(String text) onText, {
    required void Function(String sentence) onSentence,
  }) async {
    if (!await modelsReady()) {
      throw StateError('Speech Recognition model is not installed.');
    }

    // Stop only the active microphone stream. Keep the Whisper model loaded so
    // the next turn resumes without model startup latency.
    await _stopStream(suppressSentenceCallbacks: true);
    await _ensureEngineLoaded();

    _onText = onText;
    _onSentence = onSentence;
    _latestText = '';
    _lastError = null;
    _sentenceEmitted = false;
    _suppressSentenceCallbacks = false;

    final options = TranscribeOptions(
      language: _whisperLanguageCode(_languageTag),
      detectLanguage: _languageTag.trim().toLowerCase() == 'auto',
      tokenTimestamps: false,
      noTimestamps: true,
      suppressNonSpeechTokens: true,
    ).withPerformanceMode(WhisperPerformanceMode.responsive);

    final task = await _engine!.transcribeMicrophone(
      options: options,
      config: _streamConfig,
    );
    _task = task;
    _listening = true;

    _updates = task.updates.listen(
      _handleUpdate,
      onError: (Object error, StackTrace stackTrace) {
        _lastError = error.toString();
      },
    );
  }

  void _handleUpdate(WhisperStreamUpdate update) {
    final display = update.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (display.isNotEmpty) {
      _onText?.call(display);
    }

    if (_suppressSentenceCallbacks || _sentenceEmitted || !_listening) return;
    if (!SentenceEndpointDetector.isSubstantial(display)) return;

    if (display != _latestText) {
      _latestText = display;
      _sentenceTimer?.cancel();
      final stableText = update.confirmedText.trim().isNotEmpty
          ? update.confirmedText
          : display;
      final delay = SentenceEndpointDetector.endsWithTerminalPunctuation(
        stableText,
      )
          ? _punctuatedEndpointDelay
          : _silenceEndpointDelay;
      _sentenceTimer = Timer(delay, _emitLatestSentence);
    }

    if (update.isFinal) _emitLatestSentence();
  }

  void _emitLatestSentence() {
    if (_suppressSentenceCallbacks || _sentenceEmitted || !_listening) return;
    final sentence = _latestText.trim();
    if (!SentenceEndpointDetector.isSubstantial(sentence)) return;
    _sentenceEmitted = true;
    _sentenceTimer?.cancel();
    scheduleMicrotask(() => _onSentence?.call(sentence));
  }

  /// Pauses microphone capture while retaining the loaded Whisper model.
  Future<String> pauseListening() async {
    final before = _latestText.trim();
    await _stopStream(suppressSentenceCallbacks: true);
    final after = _latestText.trim();
    final failure = _lastError;
    _lastError = null;
    if (failure != null) throw StateError(failure);
    return after.isNotEmpty ? after : before;
  }

  Future<void> stopListening() async {
    await pauseListening();
  }

  Future<void> _stopStream({required bool suppressSentenceCallbacks}) async {
    _sentenceTimer?.cancel();
    _sentenceTimer = null;
    _suppressSentenceCallbacks = suppressSentenceCallbacks;

    final task = _task;
    if (task != null) {
      try {
        final finalUpdate = await task.stop();
        final finalText = finalUpdate.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (finalText.isNotEmpty) {
          _latestText = finalText;
          _onText?.call(finalText);
        }
      } catch (e) {
        _lastError ??= e.toString();
      }
    }

    _listening = false;
    await _updates?.cancel();
    _updates = null;
    _task = null;
    _onText = null;
    _onSentence = null;
    _sentenceEmitted = false;
    _suppressSentenceCallbacks = false;
  }

  Future<void> releaseRuntime() async {
    try {
      await _stopStream(suppressSentenceCallbacks: true);
    } finally {
      _engine?.dispose();
      _engine = null;
    }
  }

  Future<void> dispose() async {
    await releaseRuntime();
    _models.close();
  }

  String _whisperLanguageCode(String languageTag) {
    final normalized = languageTag.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'auto') return 'auto';
    if (normalized.startsWith('fil') || normalized.startsWith('tl')) {
      return 'tl';
    }
    if (normalized.startsWith('nl')) return 'nl';
    if (normalized.startsWith('en')) return 'en';
    if (normalized.startsWith('fr')) return 'fr';
    if (normalized.startsWith('de')) return 'de';
    if (normalized.startsWith('es')) return 'es';
    if (normalized.startsWith('it')) return 'it';
    if (normalized.startsWith('pt')) return 'pt';
    final language = normalized.split(RegExp('[-_]')).first;
    return language.isEmpty ? 'auto' : language;
  }
}
