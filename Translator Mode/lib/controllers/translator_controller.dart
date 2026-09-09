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
  double setupProgress = 0;
  String setupStatus = 'Checking local models…';
  String liveTranscript = '';
  String textA = '';
  String textB = '';
  String? error;

  final List<TranslationTurn> _history = [];
  List<TranslationTurn> get history => List.unmodifiable(_history);

  Future<void> initialize() async {
    try {
      setupStatus = 'Checking local models…';
      notifyListeners();

      final artifact = await _installer.cachedArtifact();
      if (artifact == null ||
          !await _tts.modelsReady() ||
          !await _stt.modelsReady()) {
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
      notifyListeners();
    }
  }

  Future<void> prepareOfflineModels() async {
    if (preparing) return;
    preparing = true;
    error = null;
    setupProgress = 0;
    notifyListeners();

    try {
      setupStatus = 'Installing Eb Translator';
      final artifact = await _installer.install(onProgress: (progress, detail) {
        setupStatus = detail;
        setupProgress = progress * 0.62;
        notifyListeners();
      });
      _artifact = artifact;

      setupStatus = 'Downloading Speech Synthesys';
      await _tts.prepare(onProgress: (done, total, file, fileProgress) {
        final aggregate = total == 0 ? 0.0 : (done + fileProgress) / total;
        setupProgress = 0.62 + aggregate.clamp(0, 1) * 0.32;
        setupStatus = 'Speech Synthesys: $file';
        notifyListeners();
      });

      setupStatus = 'Downloading Speech Recognition';
      await _stt.prepare(onProgress: (progress) {
        setupProgress = 0.94 + progress.clamp(0, 1) * 0.06;
        setupStatus = 'Speech Recognition';
        notifyListeners();
      });

      // Do not initialize any native engine here. The setup phase is strictly
      // download-only to avoid loading STT + TTS + Eb Translator at the same time.
      ready = true;
      setupProgress = 1;
      setupStatus = 'Offline models ready';
    } catch (e) {
      error = e.toString();
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

  Future<void> toggleListening(TranslationSide side) async {
    if (!ready || generating) return;
    error = null;

    try {
      if (listeningSide == side) {
        await stopListening(submitTranscript: true);
        return;
      }
      if (listeningSide != null) {
        await stopListening(submitTranscript: false);
      }

      // Memory-safe mode: release Eb Translator/Speech Synthesys before
      // bringing up Speech Recognition.
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

    // Fully release Speech Recognition before loading Eb Translator.
    await _stt.releaseRuntime();
    setupStatus = 'Offline models ready';
    notifyListeners();

    if (submitTranscript && text.isNotEmpty) {
      await translate(side, text);
    }
  }

  Future<void> translate(TranslationSide sourceSide, String rawText) async {
    final text = rawText.trim();
    if (!ready || text.isEmpty || generating) return;
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
      // Ensure only Eb Translator is resident while translating.
      await _stt.releaseRuntime();
      await _tts.releaseRuntime();
      final artifact = await _requireArtifact();
      if (!_translator.isLoaded) {
        await _translator.load(artifact);
      }

      setupStatus = 'Translating';
      notifyListeners();

      await for (final token in _translator.translate(
        source: source,
        target: target,
        text: text,
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

      if (autoSpeak && answer.isNotEmpty) {
        setupStatus = 'Preparing Speech Synthesys…';
        notifyListeners();

        // Free Eb Translator before initializing Speech Synthesys. This costs a
        // reload on the next turn but keeps peak RAM much lower on mobile.
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
      await _stt.releaseRuntime();
      await _translator.dispose();
      await _tts.speak(text, language: language.ttsCode);
    } catch (e) {
      error = e.toString();
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

  void clearConversation() {
    if (listeningSide != null || generating) return;
    textA = '';
    textB = '';
    liveTranscript = '';
    _history.clear();
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
