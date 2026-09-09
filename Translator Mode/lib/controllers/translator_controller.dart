import 'dart:async';

import 'package:flutter/foundation.dart';

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
  bool preparing = false;
  bool generating = false;
  bool autoSpeak = true;
  bool medicalMode = true;

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

  final List<TranslationTurn> _history = [];
  List<TranslationTurn> get history => List.unmodifiable(_history);

  bool get busy => preparing || generating || listeningSide != null;

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

  Future<void> initialize() async {
    try {
      setupStatus = 'Checking local models…';
      notifyListeners();

      final artifact = await _installer.cachedArtifact();
      final ttsReady = await _tts.modelsReady();
      final sttReady = await _stt.modelsReady();

      ebTranslatorProgress = artifact == null ? 0 : 1;
      ebTranslatorStatus = artifact == null ? 'Not installed' : 'Ready';
      speechSynthesysProgress = ttsReady ? 1 : 0;
      speechSynthesysStatus = ttsReady ? 'Ready' : 'Not installed';
      speechRecognitionProgress = sttReady ? 1 : 0;
      speechRecognitionStatus = sttReady ? 'Ready' : 'Not installed';
      _recalculateSetupProgress();

      if (artifact == null || !ttsReady || !sttReady) {
        ready = false;
        setupStatus = 'Offline models need first-run setup';
        notifyListeners();
        return;
      }

      _artifact = artifact;
      ready = true;
      setupProgress = 1;
      setupStatus = 'Offline models ready';
      notifyListeners();
    } catch (e) {
      error = e.toString();
      setupStatus = 'Model check failed';
      notifyListeners();
    }
  }

  Future<void> prepareOfflineModels() async {
    if (preparing) return;
    preparing = true;
    ready = false;
    error = null;
    setupStatus = 'Preparing model downloads';
    notifyListeners();

    var stage = 'Eb Translator';
    try {
      stage = 'Eb Translator';
      ebTranslatorStatus = ebTranslatorProgress >= 1 ? 'Verifying' : 'Downloading';
      notifyListeners();
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
      _recalculateSetupProgress();
      notifyListeners();

      stage = 'Speech Synthesys';
      speechSynthesysStatus =
          speechSynthesysProgress >= 1 ? 'Verifying' : 'Downloading';
      setupStatus = 'Downloading Speech Synthesys';
      notifyListeners();
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
      _recalculateSetupProgress();
      notifyListeners();

      stage = 'Speech Recognition';
      speechRecognitionStatus =
          speechRecognitionProgress >= 1 ? 'Verifying' : 'Downloading';
      setupStatus = 'Downloading Speech Recognition';
      notifyListeners();
      await _stt.prepare(onProgress: (progress) {
        speechRecognitionProgress = progress.clamp(0.0, 1.0);
        speechRecognitionStatus = speechRecognitionProgress >= 0.999
            ? 'Verifying'
            : 'Downloading';
        setupStatus = 'Speech Recognition';
        _recalculateSetupProgress();
        notifyListeners();
      });
      speechRecognitionProgress = 1;
      speechRecognitionStatus = 'Ready';
      _recalculateSetupProgress();

      // Download-only setup avoids a native-memory spike during first launch.
      ready = true;
      setupProgress = 1;
      setupStatus = 'Offline models ready';
    } catch (e) {
      error = e.toString();
      if (stage == 'Eb Translator') {
        ebTranslatorStatus = 'Error';
      } else if (stage == 'Speech Synthesys') {
        speechSynthesysStatus = 'Error';
      } else {
        speechRecognitionStatus = 'Error';
      }
      _recalculateSetupProgress();
      setupStatus = '$stage download interrupted — tap retry';
    } finally {
      preparing = false;
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
    if (!ready || generating || preparing) return;
    error = null;

    try {
      if (listeningSide == side) {
        await stopListening(submitTranscript: true);
        return;
      }
      if (listeningSide != null) {
        await stopListening(submitTranscript: false);
      }

      // Keep only one heavy native engine resident at a time.
      await _translator.dispose();
      await _tts.releaseRuntime();

      liveTranscript = '';
      listeningSide = side;
      setupStatus = 'Loading Speech Recognition…';
      notifyListeners();

      await _stt.startListening((text) {
        liveTranscript = text.trim();
        if (side == TranslationSide.a) {
          textA = liveTranscript;
        } else {
          textB = liveTranscript;
        }
        notifyListeners();
      });
      setupStatus = 'Listening';
      notifyListeners();
    } catch (e) {
      listeningSide = null;
      error = e.toString();
      setupStatus = 'Offline models ready';
      notifyListeners();
    }
  }

  Future<void> stopListening({bool submitTranscript = false}) async {
    final side = listeningSide;
    if (side == null) return;

    await _stt.stopListening();
    listeningSide = null;
    final text = liveTranscript.trim();
    liveTranscript = '';

    await _stt.releaseRuntime();
    setupStatus = 'Offline models ready';
    notifyListeners();

    if (submitTranscript && text.isNotEmpty) {
      await translate(side, text);
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

    final source =
        sourceSide == TranslationSide.a ? languageA : languageB;
    final target =
        sourceSide == TranslationSide.a ? languageB : languageA;

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
    textA = '';
    textB = '';
    liveTranscript = '';
    _history.clear();
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_translator.dispose());
    unawaited(_stt.dispose());
    _tts.dispose();
    _installer.dispose();
    super.dispose();
  }
}
