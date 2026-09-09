import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/sentence_endpoint_detector.dart';
import '../models/model_artifact.dart';
import '../models/translation_language.dart';
import '../models/translation_turn.dart';
import '../services/eb_translator_model_installer.dart';
import '../services/local_language_router.dart';
import '../services/local_translator_service.dart';
import '../services/offline_stt_service.dart';
import '../services/supertonic_tts_service.dart';

class TranslatorController extends ChangeNotifier {
  TranslatorController({
    EbTranslatorModelInstaller? installer,
    LocalTranslatorService? translator,
    OfflineSttService? stt,
    SupertonicTtsService? tts,
    LocalLanguageRouter? languageRouter,
  })  : _installer = installer ?? EbTranslatorModelInstaller(),
        _translator = translator ?? LocalTranslatorService(),
        _stt = stt ?? OfflineSttService(),
        _tts = tts ?? SupertonicTtsService(),
        _languageRouter = languageRouter ?? LocalLanguageRouter();

  final EbTranslatorModelInstaller _installer;
  final LocalTranslatorService _translator;
  final OfflineSttService _stt;
  final SupertonicTtsService _tts;
  final LocalLanguageRouter _languageRouter;

  ModelArtifact? _artifact;

  /// Language A is always the fixed Staff language.
  TranslationLanguage languageA = translationLanguages[0];

  /// Language B is the latest paired non-Staff language.
  TranslationLanguage languageB = translationLanguages[1];
  TranslationSide? listeningSide;

  bool ready = false;
  bool generating = false;
  bool autoSpeak = true;
  bool medicalMode = true;
  bool autoDetectGuestLanguage = true;
  bool micMuted = false;
  bool speechSynthesysSpeaking = false;

  bool installingEbTranslator = false;
  bool installingSpeechRecognition = false;
  bool installingSpeechSynthesys = false;

  double setupProgress = 0;
  double ebTranslatorProgress = 0;
  double speechRecognitionProgress = 0;
  double speechSynthesysProgress = 0;

  String setupStatus = 'Checking local models…';
  String ebTranslatorStatus = 'Pending';
  String speechRecognitionStatus = 'Pending';
  String speechSynthesysStatus = 'Pending';
  String detectedLanguageStatus = '';

  String liveTranscript = '';
  String textA = '';
  String textB = '';
  String? error;

  bool _voiceSessionActive = false;
  TranslationSide _speakerHint = TranslationSide.a;
  bool _processingSentenceQueue = false;
  final Queue<_QueuedSentence> _sentenceQueue = Queue<_QueuedSentence>();

  final List<TranslationTurn> _history = [];
  List<TranslationTurn> get history => List.unmodifiable(_history);

  bool get preparing =>
      installingEbTranslator ||
      installingSpeechRecognition ||
      installingSpeechSynthesys;

  bool get allModelsReady =>
      ebTranslatorProgress >= 0.999 &&
      speechRecognitionProgress >= 0.999 &&
      speechSynthesysProgress >= 0.999 &&
      ebTranslatorStatus == 'Ready' &&
      speechRecognitionStatus == 'Ready' &&
      speechSynthesysStatus == 'Ready';

  bool get busy => preparing || generating || speechSynthesysSpeaking;
  bool get voiceSessionActive => _voiceSessionActive;
  TranslationSide get speakerHint => _speakerHint;

  TranslationSide? get lastOutputSide {
    if (_history.isEmpty) return null;
    return _history.first.sourceSide == TranslationSide.a
        ? TranslationSide.b
        : TranslationSide.a;
  }

  void _recalculateSetupProgress() {
    setupProgress = ((ebTranslatorProgress +
                speechRecognitionProgress +
                speechSynthesysProgress) /
            3)
        .clamp(0.0, 1.0);
  }

  void _syncReadyState() {
    _recalculateSetupProgress();
    ready = allModelsReady;
    if (ready) {
      setupProgress = 1;
      if (!_voiceSessionActive && !generating && !speechSynthesysSpeaking) {
        setupStatus = 'Offline models ready';
      }
    } else if (!preparing) {
      final missing = <String>[];
      if (ebTranslatorStatus != 'Ready') missing.add('Eb Translator');
      if (speechRecognitionStatus != 'Ready') {
        missing.add('Speech Recognition');
      }
      if (speechSynthesysStatus != 'Ready') missing.add('Speech Synthesys');
      setupStatus = missing.isEmpty
          ? 'Checking local models…'
          : 'Required: ${missing.join(', ')}';
    }
  }

  Future<void> initialize() async {
    try {
      setupStatus = 'Checking local models…';
      notifyListeners();

      final artifact = await _installer.cachedArtifact();
      final ttsReady = await _tts.modelsReady();
      final sttReady = await _stt.modelsReady();

      _artifact = artifact;
      ebTranslatorProgress = artifact == null ? 0 : 1;
      ebTranslatorStatus = artifact == null ? 'Not installed' : 'Ready';
      speechSynthesysProgress = ttsReady ? 1 : 0;
      speechSynthesysStatus = ttsReady ? 'Ready' : 'Not installed';
      speechRecognitionProgress = sttReady ? 1 : 0;
      speechRecognitionStatus = sttReady ? 'Ready' : 'Not installed';
      error = null;
      _syncReadyState();

      // Warm the tiny local language detector tables during app startup so
      // language routing does not add first-turn latency.
      try {
        await _languageRouter.initialize();
      } catch (_) {
        // Routing has a deterministic Staff/Guest fallback, so failure of the
        // lightweight detector must never prevent the app from starting.
      }
      notifyListeners();
    } catch (e) {
      error = e.toString();
      setupStatus = 'Model check failed';
      notifyListeners();
    }
  }

  Future<void> prepareOfflineModels() async {
    if (preparing) return;
    if (ebTranslatorStatus != 'Ready') {
      await installEbTranslator();
      return;
    }
    if (speechRecognitionStatus != 'Ready') {
      await installSpeechRecognition();
      return;
    }
    if (speechSynthesysStatus != 'Ready') {
      await installSpeechSynthesys();
      return;
    }
    _syncReadyState();
    notifyListeners();
  }

  Future<void> installEbTranslator() async {
    if (preparing || _voiceSessionActive || generating) return;
    installingEbTranslator = true;
    ready = false;
    error = null;
    ebTranslatorStatus = ebTranslatorProgress >= 0.999
        ? 'Verifying'
        : 'Downloading';
    setupStatus = 'Installing Eb Translator only';
    notifyListeners();

    try {
      await _releaseSessionRuntimes();
      final artifact = await _installer.install(onProgress: (progress, detail) {
        ebTranslatorProgress = progress.clamp(0.0, 1.0);
        ebTranslatorStatus = ebTranslatorProgress >= 0.999
            ? 'Verifying'
            : 'Downloading';
        setupStatus = detail;
        _recalculateSetupProgress();
        notifyListeners();
      });
      _artifact = artifact;
      ebTranslatorProgress = 1;
      ebTranslatorStatus = 'Ready';
    } catch (e) {
      error = 'Eb Translator installation failed: $e';
      ebTranslatorStatus = 'Error';
      setupStatus = 'Eb Translator interrupted — retry this model only';
    } finally {
      installingEbTranslator = false;
      _syncReadyState();
      notifyListeners();
    }
  }

  Future<void> installSpeechRecognition() async {
    if (preparing || _voiceSessionActive || generating) return;
    installingSpeechRecognition = true;
    ready = false;
    error = null;
    speechRecognitionStatus = speechRecognitionProgress >= 0.999
        ? 'Verifying'
        : 'Downloading';
    setupStatus = 'Installing Speech Recognition · Whisper Base';
    notifyListeners();

    try {
      await _releaseSessionRuntimes();
      await _stt.prepare(onProgress: (progress) {
        speechRecognitionProgress = progress.clamp(0.0, 1.0);
        speechRecognitionStatus = speechRecognitionProgress >= 0.999
            ? 'Verifying'
            : 'Downloading';
        setupStatus = 'Speech Recognition · Whisper Base multilingual';
        _recalculateSetupProgress();
        notifyListeners();
      });
      speechRecognitionProgress = 1;
      speechRecognitionStatus = 'Ready';
    } catch (e) {
      error = 'Speech Recognition installation failed: $e';
      speechRecognitionStatus = 'Error';
      setupStatus = 'Speech Recognition interrupted — retry this model only';
    } finally {
      installingSpeechRecognition = false;
      _syncReadyState();
      notifyListeners();
    }
  }

  Future<void> installSpeechSynthesys() async {
    if (preparing || _voiceSessionActive || generating) return;
    installingSpeechSynthesys = true;
    ready = false;
    error = null;
    speechSynthesysStatus = speechSynthesysProgress >= 0.999
        ? 'Verifying'
        : 'Downloading';
    setupStatus = 'Installing Speech Synthesys only';
    notifyListeners();

    try {
      await _releaseSessionRuntimes();
      await _tts.prepare(onProgress: (done, total, file, fileProgress) {
        final aggregate = total == 0 ? 0.0 : (done + fileProgress) / total;
        speechSynthesysProgress = aggregate.clamp(0.0, 1.0);
        speechSynthesysStatus = speechSynthesysProgress >= 0.999
            ? 'Verifying'
            : 'Downloading';
        setupStatus = 'Speech Synthesys: $file';
        _recalculateSetupProgress();
        notifyListeners();
      });
      speechSynthesysProgress = 1;
      speechSynthesysStatus = 'Ready';
    } catch (e) {
      error = 'Speech Synthesys installation failed: $e';
      speechSynthesysStatus = 'Error';
      setupStatus = 'Speech Synthesys interrupted — retry this model only';
    } finally {
      installingSpeechSynthesys = false;
      _syncReadyState();
      notifyListeners();
    }
  }

  Future<ModelArtifact> _requireArtifact() async {
    final cached = _artifact ?? await _installer.cachedArtifact();
    if (cached == null) {
      throw StateError('Eb Translator model is not installed.');
    }
    _artifact = cached;
    return cached;
  }

  void setLanguage(TranslationSide side, TranslationLanguage language) {
    if (_voiceSessionActive || generating || preparing) return;
    if (side == TranslationSide.a) {
      if (_sameLanguage(language, languageB)) languageB = languageA;
      languageA = language;
    } else {
      if (_sameLanguage(language, languageA)) languageA = languageB;
      languageB = language;
    }
    detectedLanguageStatus = '';
    notifyListeners();
  }

  void swapLanguages() {
    if (_voiceSessionActive || generating || preparing) return;
    final oldA = languageA;
    languageA = languageB;
    languageB = oldA;
    final oldTextA = textA;
    textA = textB;
    textB = oldTextA;
    _speakerHint = TranslationSide.a;
    notifyListeners();
  }

  void setAutoSpeak(bool value) {
    autoSpeak = value;
    notifyListeners();
  }

  void setMedicalMode(bool value) {
    if (_voiceSessionActive || generating) return;
    medicalMode = value;
    notifyListeners();
  }

  void setAutoDetectGuestLanguage(bool value) {
    if (_voiceSessionActive || generating) return;
    autoDetectGuestLanguage = value;
    detectedLanguageStatus = '';
    notifyListeners();
  }

  /// Play button behavior: one persistent local translation session.
  Future<void> toggleVoiceSession({TranslationSide hint = TranslationSide.a}) async {
    if (_voiceSessionActive) {
      await stopVoiceSession(flushTranscript: true);
    } else {
      await startVoiceSession(hint: hint);
    }
  }

  Future<void> startVoiceSession({TranslationSide hint = TranslationSide.a}) async {
    if (!ready || preparing || generating || _voiceSessionActive) return;
    error = null;
    _voiceSessionActive = true;
    micMuted = false;
    _speakerHint = hint;
    setupStatus = 'Starting local live session…';
    notifyListeners();

    try {
      // Warm long-lived STT + translator contexts once. This is the local
      // equivalent of opening one Gemini Live session, without any cloud call.
      final artifact = await _requireArtifact();
      await _stt.warmRuntime();
      setupStatus = 'Warming Eb Translator…';
      notifyListeners();
      await _translator.load(artifact);
      await _startListening();
    } catch (e) {
      _voiceSessionActive = false;
      micMuted = false;
      listeningSide = null;
      error = e.toString();
      setupStatus = 'Offline models ready';
      await _releaseSessionRuntimes();
      notifyListeners();
    }
  }

  /// Microphone behavior while a session is running: mute/unmute only.
  Future<void> toggleMicMute({TranslationSide? hint}) async {
    if (!ready || preparing) return;
    if (!_voiceSessionActive) {
      await startVoiceSession(hint: hint ?? _speakerHint);
      return;
    }
    if (speechSynthesysSpeaking || generating) return;

    if (micMuted) {
      micMuted = false;
      if (hint != null) _speakerHint = hint;
      await _startListening();
      return;
    }

    micMuted = true;
    final captured = await _pauseListeningCapture();
    setupStatus = 'Microphone muted · session remains active';
    notifyListeners();
    if (SentenceEndpointDetector.isSubstantial(captured)) {
      _enqueueSentenceUtterance(captured, hint: hint ?? _speakerHint);
    }
  }

  /// Backward-compatible mic entry point used by older UI code.
  Future<void> toggleListening(TranslationSide side) => toggleMicMute(hint: side);

  Future<void> stopVoiceSession({bool flushTranscript = true}) async {
    if (!_voiceSessionActive && listeningSide == null) return;
    final hint = _speakerHint;
    final captured = await _pauseListeningCapture();
    _voiceSessionActive = false;
    micMuted = false;
    _sentenceQueue.clear();
    setupStatus = 'Stopping local live session…';
    notifyListeners();

    if (flushTranscript && SentenceEndpointDetector.isSubstantial(captured)) {
      final pieces = SentenceEndpointDetector.splitForShipping(captured);
      for (final sentence in pieces) {
        await _routeAndTranslate(sentence, hint: hint);
      }
    }

    await _releaseSessionRuntimes();
    setupStatus = 'Offline models ready';
    notifyListeners();
  }

  Future<void> _startListening() async {
    if (!_voiceSessionActive || micMuted || generating || speechSynthesysSpeaking) {
      return;
    }

    liveTranscript = '';
    listeningSide = _speakerHint;
    setupStatus = autoDetectGuestLanguage
        ? 'Listening · automatic language routing'
        : 'Listening · ${_languageForHint().displayName}';
    notifyListeners();

    _stt.setLanguageTag(
      autoDetectGuestLanguage ? 'auto' : _languageForHint().sttCode,
    );
    await _stt.startListening(
      (text) {
        liveTranscript = text.trim();
        // The exact language is finalized at the sentence boundary. Use the
        // expected side only for provisional visual feedback.
        if (_speakerHint == TranslationSide.a) {
          textA = liveTranscript;
        } else {
          textB = liveTranscript;
        }
        notifyListeners();
      },
      onSentence: (utterance) {
        _enqueueSentenceUtterance(utterance, hint: _speakerHint);
      },
    );
    notifyListeners();
  }

  TranslationLanguage _languageForHint() =>
      _speakerHint == TranslationSide.a ? languageA : languageB;

  void _enqueueSentenceUtterance(
    String utterance, {
    required TranslationSide hint,
  }) {
    if (!_voiceSessionActive || micMuted) return;
    final sentences = SentenceEndpointDetector.splitForShipping(utterance);
    for (final sentence in sentences) {
      final value = sentence.trim();
      if (value.isNotEmpty) _sentenceQueue.add(_QueuedSentence(hint, value));
    }
    if (_sentenceQueue.isNotEmpty) unawaited(_processSentenceQueue());
  }

  Future<void> _processSentenceQueue() async {
    if (_processingSentenceQueue) return;
    _processingSentenceQueue = true;

    try {
      if (listeningSide != null) {
        await _pauseListeningCapture();
        setupStatus = 'Sentence finalized';
        notifyListeners();
      }

      while (_sentenceQueue.isNotEmpty) {
        final item = _sentenceQueue.removeFirst();
        await _routeAndTranslate(item.text, hint: item.hint);
      }
    } catch (e) {
      error = e.toString();
      setupStatus = _voiceSessionActive
          ? 'Live session paused after an error'
          : 'Offline models ready';
      notifyListeners();
    } finally {
      _processingSentenceQueue = false;
    }

    if (_voiceSessionActive &&
        !micMuted &&
        _sentenceQueue.isEmpty &&
        !generating &&
        !speechSynthesysSpeaking &&
        ready) {
      try {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await _startListening();
      } catch (e) {
        _voiceSessionActive = false;
        listeningSide = null;
        error = e.toString();
        setupStatus = 'Offline models ready';
        notifyListeners();
      }
    }
  }

  Future<String> _pauseListeningCapture() async {
    if (listeningSide == null) return liveTranscript.trim();
    final before = liveTranscript.trim();
    String finalText = before;
    try {
      final flushed = await _stt.pauseListening();
      if (flushed.trim().isNotEmpty) finalText = flushed.trim();
    } catch (e) {
      error = e.toString();
    }
    listeningSide = null;
    liveTranscript = '';
    notifyListeners();
    return finalText;
  }

  Future<void> stopListening({bool submitTranscript = false}) async {
    final hint = _speakerHint;
    final text = await _pauseListeningCapture();
    if (submitTranscript && SentenceEndpointDetector.isSubstantial(text)) {
      for (final sentence in SentenceEndpointDetector.splitForShipping(text)) {
        await _routeAndTranslate(sentence, hint: hint);
      }
    }
  }

  Future<void> _routeAndTranslate(
    String rawText, {
    required TranslationSide hint,
  }) async {
    final text = rawText.trim();
    if (text.isEmpty) return;

    final route = await _languageRouter.route(
      text: text,
      staffLanguage: languageA,
      guestLanguage: languageB,
      hintSide: hint,
      autoDetect: autoDetectGuestLanguage,
    );

    if (!_sameLanguage(route.guestLanguage, languageB) &&
        !_sameLanguage(route.guestLanguage, languageA)) {
      languageB = route.guestLanguage;
    }

    final sourceSide = _sameLanguage(route.source, languageA)
        ? TranslationSide.a
        : TranslationSide.b;
    detectedLanguageStatus = route.usedFallback
        ? '${route.source.displayName} · direction hint'
        : '${route.source.displayName} · detected locally';

    await _translateWithLanguages(
      sourceSide: sourceSide,
      source: route.source,
      target: route.target,
      text: text,
    );

    // Conversation partners normally alternate. This is only a low-confidence
    // hint for very short utterances; local language detection still overrides
    // it whenever it has a confident result.
    _speakerHint = sourceSide == TranslationSide.a
        ? TranslationSide.b
        : TranslationSide.a;
  }

  Future<void> translate(TranslationSide sourceSide, String rawText) async {
    final source = sourceSide == TranslationSide.a ? languageA : languageB;
    final target = sourceSide == TranslationSide.a ? languageB : languageA;
    await _translateWithLanguages(
      sourceSide: sourceSide,
      source: source,
      target: target,
      text: rawText.trim(),
    );
  }

  Future<void> _translateWithLanguages({
    required TranslationSide sourceSide,
    required TranslationLanguage source,
    required TranslationLanguage target,
    required String text,
  }) async {
    if (!ready || text.isEmpty || generating || preparing) return;
    if (listeningSide != null) await _pauseListeningCapture();

    error = null;
    generating = true;
    if (sourceSide == TranslationSide.a) {
      textA = text;
      textB = '';
    } else {
      textB = text;
      textA = '';
    }
    setupStatus = medicalMode ? 'Translating · Medical' : 'Translating';
    notifyListeners();

    var answer = '';
    try {
      final artifact = await _requireArtifact();
      if (!_translator.isLoaded) {
        setupStatus = 'Warming Eb Translator…';
        notifyListeners();
        await _translator.load(artifact);
      }

      setupStatus = medicalMode ? 'Translating · Medical' : 'Translating';
      notifyListeners();
      await for (final token in _translator.translate(
        source: source,
        target: target,
        text: text,
        medicalMode: medicalMode,
      )) {
        answer += token;
        if (sourceSide == TranslationSide.a) {
          textB = answer;
        } else {
          textA = answer;
        }
        notifyListeners();
      }

      answer = answer.trim();
      if (answer.isEmpty) {
        throw StateError('Eb Translator returned an empty translation.');
      }
      if (sourceSide == TranslationSide.a) {
        textB = answer;
      } else {
        textA = answer;
      }
      _history.insert(
        0,
        TranslationTurn(
          sourceSide: sourceSide,
          sourceLanguage: source,
          targetLanguage: target,
          sourceText: text,
          translatedText: answer,
        ),
      );
      notifyListeners();

      if (autoSpeak) {
        speechSynthesysSpeaking = true;
        setupStatus = 'Speaking · Speech Synthesys';
        notifyListeners();
        try {
          await _tts.speak(answer, language: target.ttsCode);
        } catch (ttsError) {
          // A speaker/playback issue must not kill the live translation
          // session or discard the successfully generated translation.
          error = 'Speech Synthesys playback failed: $ttsError';
        } finally {
          speechSynthesysSpeaking = false;
        }
      }
      setupStatus = _voiceSessionActive
          ? (micMuted ? 'Microphone muted · session active' : 'Live session active')
          : 'Offline models ready';
    } catch (e) {
      error = e.toString();
      setupStatus = _voiceSessionActive ? 'Live session active' : 'Offline models ready';
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  Future<void> replay(TranslationSide side) async {
    final text = side == TranslationSide.a ? textA : textB;
    final language = side == TranslationSide.a ? languageA : languageB;
    if (text.trim().isEmpty) return;

    final shouldResume = _voiceSessionActive && !micMuted;
    try {
      error = null;
      if (listeningSide != null) await _pauseListeningCapture();
      speechSynthesysSpeaking = true;
      setupStatus = 'Speaking · Speech Synthesys';
      notifyListeners();
      await _tts.speak(text, language: language.ttsCode);
    } catch (e) {
      error = 'Speech Synthesys playback failed: $e';
    } finally {
      speechSynthesysSpeaking = false;
      setupStatus = _voiceSessionActive ? 'Live session active' : 'Offline models ready';
      notifyListeners();
    }

    if (shouldResume && _voiceSessionActive && !micMuted) {
      await _startListening();
    }
  }

  Future<void> stopGeneration() async {
    _voiceSessionActive = false;
    micMuted = false;
    _sentenceQueue.clear();
    await _stt.pauseListening();
    listeningSide = null;
    await _translator.stop();
    await _tts.stop();
    generating = false;
    speechSynthesysSpeaking = false;
    await _releaseSessionRuntimes();
    setupStatus = 'Offline models ready';
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  /// Reset conversation state without disconnecting an active live session.
  void clearConversation() {
    _sentenceQueue.clear();
    textA = '';
    textB = '';
    liveTranscript = '';
    _history.clear();
    detectedLanguageStatus = '';
    error = null;
    notifyListeners();
  }

  Future<void> _releaseSessionRuntimes() async {
    try {
      await _stt.releaseRuntime();
    } catch (_) {}
    try {
      await _translator.dispose();
    } catch (_) {}
    try {
      await _tts.releaseRuntime();
    } catch (_) {}
  }

  bool _sameLanguage(TranslationLanguage a, TranslationLanguage b) {
    String base(String code) {
      final value = code.toLowerCase().replaceAll('_', '-');
      if (value.startsWith('fil') || value == 'tl') return 'tl';
      if (value.startsWith('nl')) return 'nl';
      return value.split('-').first;
    }
    return base(a.code) == base(b.code);
  }

  @override
  void dispose() {
    _voiceSessionActive = false;
    _sentenceQueue.clear();
    unawaited(_translator.dispose());
    unawaited(_stt.dispose());
    _tts.dispose();
    _installer.dispose();
    super.dispose();
  }
}

class _QueuedSentence {
  const _QueuedSentence(this.hint, this.text);

  final TranslationSide hint;
  final String text;
}
