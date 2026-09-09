import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/sentence_endpoint_detector.dart';
import '../models/model_artifact.dart';
import '../models/translation_language.dart';
import '../models/translation_turn.dart';
import '../services/eb_translator_model_installer.dart';
import '../services/local_translator_service.dart';
import '../services/offline_stt_service.dart';
import '../services/supertonic_tts_service.dart';

class TranslatorController extends ChangeNotifier {
  TranslatorController({
    EbTranslatorModelInstaller? installer,
    LocalTranslatorService? translator,
    OfflineSttService? stt,
    SupertonicTtsService? tts,
  })  : _installer = installer ?? EbTranslatorModelInstaller(),
        _translator = translator ?? LocalTranslatorService(),
        _stt = stt ?? OfflineSttService(),
        _tts = tts ?? SupertonicTtsService();

  final EbTranslatorModelInstaller _installer;
  final LocalTranslatorService _translator;
  final OfflineSttService _stt;
  final SupertonicTtsService _tts;

  ModelArtifact? _artifact;

  TranslationLanguage languageA = translationLanguages[0];
  TranslationLanguage languageB = translationLanguages[1];
  TranslationSide? listeningSide;

  bool ready = false;
  bool generating = false;
  bool autoSpeak = true;
  bool medicalMode = true;

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

  String liveTranscript = '';
  String textA = '';
  String textB = '';
  String? error;

  bool _voiceSessionActive = false;
  TranslationSide? _sessionSide;
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

  bool get busy => preparing || generating || listeningSide != null;
  bool get voiceSessionActive => _voiceSessionActive;

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
      setupStatus = 'Offline models ready';
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
    if (preparing || generating || listeningSide != null) return;
    installingEbTranslator = true;
    ready = false;
    error = null;
    ebTranslatorStatus = ebTranslatorProgress >= 0.999
        ? 'Verifying'
        : 'Downloading';
    setupStatus = 'Installing Eb Translator only';
    notifyListeners();

    try {
      await _stt.releaseRuntime();
      await _tts.releaseRuntime();
      await _translator.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 120));

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
    if (preparing || generating || listeningSide != null) return;
    installingSpeechRecognition = true;
    ready = false;
    error = null;
    speechRecognitionStatus = speechRecognitionProgress >= 0.999
        ? 'Verifying'
        : 'Downloading';
    setupStatus = 'Installing Speech Recognition · Whisper Base';
    notifyListeners();

    try {
      await _tts.releaseRuntime();
      await _translator.dispose();
      await _stt.releaseRuntime();
      await Future<void>.delayed(const Duration(milliseconds: 120));

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
    if (preparing || generating || listeningSide != null) return;
    installingSpeechSynthesys = true;
    ready = false;
    error = null;
    speechSynthesysStatus = speechSynthesysProgress >= 0.999
        ? 'Verifying'
        : 'Downloading';
    setupStatus = 'Installing Speech Synthesys only';
    notifyListeners();

    try {
      await _stt.releaseRuntime();
      await _translator.dispose();
      await _tts.releaseRuntime();
      await Future<void>.delayed(const Duration(milliseconds: 120));

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
    if (listeningSide != null || generating) return;
    if (side == TranslationSide.a) {
      if (language.code == languageB.code) {
        languageB = languageA;
      }
      languageA = language;
    } else {
      if (language.code == languageA.code) {
        languageA = languageB;
      }
      languageB = language;
    }
    notifyListeners();
  }

  void swapLanguages() {
    if (listeningSide != null || generating) return;
    final oldA = languageA;
    languageA = languageB;
    languageB = oldA;
    final oldTextA = textA;
    textA = textB;
    textB = oldTextA;
    notifyListeners();
  }

  void setAutoSpeak(bool value) {
    autoSpeak = value;
    notifyListeners();
  }

  void setMedicalMode(bool value) {
    if (listeningSide != null || generating) return;
    medicalMode = value;
    notifyListeners();
  }

  Future<void> toggleListening(TranslationSide side) async {
    if (!ready || preparing) return;
    error = null;

    if (_voiceSessionActive || listeningSide != null) {
      _voiceSessionActive = false;
      _sessionSide = null;
      _sentenceQueue.clear();
      await stopListening(submitTranscript: true);
      return;
    }
    if (generating) return;

    _voiceSessionActive = true;
    _sessionSide = side;
    try {
      await _startListening(side);
    } catch (e) {
      _voiceSessionActive = false;
      _sessionSide = null;
      listeningSide = null;
      error = e.toString();
      setupStatus = 'Offline models ready';
      notifyListeners();
    }
  }

  Future<void> _startListening(TranslationSide side) async {
    if (!_voiceSessionActive || generating || preparing) return;

    await _translator.dispose();
    await _tts.releaseRuntime();

    liveTranscript = '';
    listeningSide = side;
    setupStatus = 'Loading Speech Recognition…';
    notifyListeners();

    final sourceLanguage = side == TranslationSide.a ? languageA : languageB;
    _stt.setLanguageTag(sourceLanguage.sttCode);
    await _stt.startListening(
      (text) {
        liveTranscript = text.trim();
        if (side == TranslationSide.a) {
          textA = liveTranscript;
        } else {
          textB = liveTranscript;
        }
        notifyListeners();
      },
      onSentence: (utterance) {
        _enqueueSentenceUtterance(side, utterance);
      },
    );
    setupStatus = 'Listening · sentence streaming';
    notifyListeners();
  }

  void _enqueueSentenceUtterance(TranslationSide side, String utterance) {
    if (!_voiceSessionActive || listeningSide != side) return;
    final sentences = SentenceEndpointDetector.splitForShipping(utterance);
    for (final sentence in sentences) {
      final value = sentence.trim();
      if (value.isNotEmpty) {
        _sentenceQueue.add(_QueuedSentence(side, value));
      }
    }
    if (_sentenceQueue.isNotEmpty) {
      unawaited(_processSentenceQueue());
    }
  }

  Future<void> _processSentenceQueue() async {
    if (_processingSentenceQueue) return;
    _processingSentenceQueue = true;

    try {
      if (listeningSide != null) {
        await _stt.stopListening();
        listeningSide = null;
        liveTranscript = '';
        await _stt.releaseRuntime();
        setupStatus = 'Sentence finalized';
        notifyListeners();
      }

      while (_sentenceQueue.isNotEmpty && _voiceSessionActive) {
        final item = _sentenceQueue.removeFirst();
        await translate(item.side, item.text);
      }
    } catch (e) {
      error = e.toString();
      setupStatus = 'Offline models ready';
      notifyListeners();
    } finally {
      _processingSentenceQueue = false;
    }

    if (_voiceSessionActive &&
        _sessionSide != null &&
        _sentenceQueue.isEmpty &&
        !generating &&
        ready) {
      try {
        await Future<void>.delayed(const Duration(milliseconds: 180));
        await _startListening(_sessionSide!);
      } catch (e) {
        _voiceSessionActive = false;
        _sessionSide = null;
        listeningSide = null;
        error = e.toString();
        setupStatus = 'Offline models ready';
        notifyListeners();
      }
    }
  }

  Future<void> stopListening({bool submitTranscript = false}) async {
    final side = listeningSide;
    if (side == null) return;

    final beforeStop = liveTranscript.trim();
    try {
      await _stt.stopListening();
    } catch (e) {
      error = e.toString();
    }

    listeningSide = null;
    final afterStop = liveTranscript.trim();
    final text = afterStop.isNotEmpty ? afterStop : beforeStop;
    liveTranscript = '';

    await _stt.releaseRuntime();
    setupStatus = 'Offline models ready';
    notifyListeners();

    if (submitTranscript && text.isNotEmpty) {
      final sentences = SentenceEndpointDetector.splitForShipping(text);
      for (final sentence in sentences) {
        await translate(side, sentence);
      }
    }
  }

  Future<void> translate(TranslationSide sourceSide, String rawText) async {
    final text = rawText.trim();
    if (!ready || text.isEmpty || generating || preparing) return;
    if (listeningSide != null) {
      await stopListening(submitTranscript: false);
    }

    error = null;
    generating = true;

    final source = sourceSide == TranslationSide.a ? languageA : languageB;
    final target = sourceSide == TranslationSide.a ? languageB : languageA;

    if (sourceSide == TranslationSide.a) {
      textA = text;
      textB = '';
    } else {
      textB = text;
      textA = '';
    }

    setupStatus = 'Loading Eb Translator…';
    notifyListeners();

    var answer = '';
    try {
      await _stt.releaseRuntime();
      await _tts.releaseRuntime();
      final artifact = await _requireArtifact();
      if (!_translator.isLoaded) {
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
        setupStatus = 'Preparing Speech Synthesys…';
        notifyListeners();
        await _translator.dispose();
        await _tts.speak(answer, language: target.ttsCode);
      }
      setupStatus = 'Offline models ready';
    } catch (e) {
      error = e.toString();
      setupStatus = 'Offline models ready';
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  Future<void> replay(TranslationSide side) async {
    final text = side == TranslationSide.a ? textA : textB;
    final language = side == TranslationSide.a ? languageA : languageB;
    if (text.trim().isEmpty) return;

    try {
      error = null;
      setupStatus = 'Preparing Speech Synthesys…';
      notifyListeners();
      await _stt.releaseRuntime();
      await _translator.dispose();
      await _tts.speak(text, language: language.ttsCode);
      setupStatus = 'Offline models ready';
    } catch (e) {
      error = e.toString();
      setupStatus = 'Offline models ready';
      notifyListeners();
    }
  }

  Future<void> stopGeneration() async {
    _voiceSessionActive = false;
    _sessionSide = null;
    _sentenceQueue.clear();
    await _translator.stop();
    await _translator.dispose();
    generating = false;
    setupStatus = 'Offline models ready';
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  void clearConversation() {
    if (listeningSide != null || generating) return;
    _voiceSessionActive = false;
    _sessionSide = null;
    _sentenceQueue.clear();
    textA = '';
    textB = '';
    liveTranscript = '';
    _history.clear();
    error = null;
    notifyListeners();
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
  const _QueuedSentence(this.side, this.text);

  final TranslationSide side;
  final String text;
}
