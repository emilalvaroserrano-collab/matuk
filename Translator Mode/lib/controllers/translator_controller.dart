import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/model_artifact.dart';
import '../models/translation_language.dart';
import '../models/translation_turn.dart';
import '../services/local_translator_service.dart';
import '../services/offline_stt_service.dart';
import '../services/ollama_model_installer.dart';
import '../services/supertonic_tts_service.dart';

class TranslatorController extends ChangeNotifier {
  TranslatorController({
    OllamaModelInstaller? installer,
    LocalTranslatorService? translator,
    OfflineSttService? stt,
    SupertonicTtsService? tts,
  })  : _installer = installer ?? OllamaModelInstaller(),
        _translator = translator ?? LocalTranslatorService(),
        _stt = stt ?? OfflineSttService(),
        _tts = tts ?? SupertonicTtsService();

  final OllamaModelInstaller _installer;
  final LocalTranslatorService _translator;
  final OfflineSttService _stt;
  final SupertonicTtsService _tts;

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
      final ttsReady = await _tts.modelsReady();
      final sttReady = await _stt.modelsReady();
      if (artifact == null || !ttsReady || !sttReady) {
        setupStatus = 'Offline models need first-run setup';
        notifyListeners();
        return;
      }
      await _initializeRuntimes(artifact);
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
      setupStatus = 'Installing exact Ollama gemma3:1b';
      final artifact = await _installer.install(onProgress: (progress, detail) {
        setupStatus = detail;
        setupProgress = progress * 0.62;
        notifyListeners();
      });

      setupStatus = 'Preparing Supertonic 3';
      await _tts.prepare(onProgress: (done, total, file, fileProgress) {
        final aggregate = total == 0 ? 0.0 : (done + fileProgress) / total;
        setupProgress = 0.62 + aggregate.clamp(0, 1) * 0.32;
        setupStatus = 'Supertonic 3: $file';
        notifyListeners();
      });

      setupStatus = 'Preparing offline speech recognition';
      await _stt.prepare(onProgress: (progress) {
        setupProgress = 0.94 + progress.clamp(0, 1) * 0.05;
        notifyListeners();
      });

      setupStatus = 'Loading local translator';
      setupProgress = 0.99;
      notifyListeners();
      await _translator.load(artifact);
      ready = true;
      setupProgress = 1;
      setupStatus = '100% local dual translator ready';
    } catch (e) {
      error = e.toString();
    } finally {
      preparing = false;
      notifyListeners();
    }
  }

  Future<void> _initializeRuntimes(ModelArtifact artifact) async {
    setupStatus = 'Loading local runtimes…';
    notifyListeners();
    await _stt.initialize();
    await _tts.initialize();
    await _translator.load(artifact);
    ready = true;
    setupProgress = 1;
    setupStatus = '100% local dual translator ready';
    notifyListeners();
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

      await _tts.stop();
      liveTranscript = '';
      listeningSide = side;
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
    } catch (e) {
      listeningSide = null;
      error = e.toString();
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
    await _tts.stop();
    error = null;

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

    generating = true;
    notifyListeners();

    var answer = '';
    try {
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
        await _tts.speak(answer, language: target.ttsCode);
      }
    } catch (e) {
      error = e.toString();
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  Future<void> replay(TranslationSide side) async {
    final text = side == TranslationSide.a ? textA : textB;
    final language = side == TranslationSide.a ? languageA : languageB;
    if (text.trim().isEmpty) return;
    await _tts.speak(text, language: language.ttsCode);
  }

  Future<void> stopGeneration() async {
    await _translator.stop();
    generating = false;
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
