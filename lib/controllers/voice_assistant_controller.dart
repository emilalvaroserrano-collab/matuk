import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/model_artifact.dart';
import '../services/local_llm_service.dart';
import '../services/offline_stt_service.dart';
import '../services/ollama_model_installer.dart';
import '../services/supertonic_tts_service.dart';

class VoiceAssistantController extends ChangeNotifier {
  VoiceAssistantController({
    OllamaModelInstaller? installer,
    LocalLlmService? llm,
    OfflineSttService? stt,
    SupertonicTtsService? tts,
  })  : _installer = installer ?? OllamaModelInstaller(),
        _llm = llm ?? LocalLlmService(),
        _stt = stt ?? OfflineSttService(),
        _tts = tts ?? SupertonicTtsService();

  final OllamaModelInstaller _installer;
  final LocalLlmService _llm;
  final OfflineSttService _stt;
  final SupertonicTtsService _tts;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  bool ready = false;
  bool preparing = false;
  bool listening = false;
  bool generating = false;
  double setupProgress = 0;
  String setupStatus = 'Checking local models…';
  String transcript = '';
  String? error;

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

      setupStatus = 'Loading Gemma 3 1B';
      setupProgress = 0.99;
      notifyListeners();
      await _llm.load(artifact);
      ready = true;
      setupProgress = 1;
      setupStatus = '100% local voice assistant ready';
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
    // Initialize sequentially to avoid unnecessary peak memory pressure while
    // large ONNX and GGUF runtimes are being mapped on mobile devices.
    await _stt.initialize();
    await _tts.initialize();
    await _llm.load(artifact);
    ready = true;
    setupProgress = 1;
    setupStatus = '100% local voice assistant ready';
    notifyListeners();
  }

  Future<void> toggleListening() async {
    if (!ready || generating) return;
    error = null;
    try {
      if (listening) {
        await stopListening(sendTranscript: true);
      } else {
        await _tts.stop();
        transcript = '';
        listening = true;
        notifyListeners();
        await _stt.startListening((text) {
          transcript = text.trim();
          notifyListeners();
        });
      }
    } catch (e) {
      listening = false;
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> stopListening({bool sendTranscript = false}) async {
    if (!listening) return;
    await _stt.stopListening();
    listening = false;
    final text = transcript.trim();
    transcript = '';
    notifyListeners();
    if (sendTranscript && text.isNotEmpty) await send(text);
  }

  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (!ready || text.isEmpty || generating) return;
    if (listening) await stopListening();
    await _tts.stop();
    error = null;

    _messages.add(ChatMessage(role: ChatRole.user, content: text));
    _messages.add(const ChatMessage(
      role: ChatRole.assistant,
      content: '',
      isStreaming: true,
    ));
    generating = true;
    notifyListeners();

    final promptHistory = _messages.sublist(0, _messages.length - 1);
    var answer = '';
    try {
      await for (final token in _llm.generate(promptHistory)) {
        answer += token;
        _messages[_messages.length - 1] = ChatMessage(
          role: ChatRole.assistant,
          content: answer,
          isStreaming: true,
        );
        notifyListeners();
      }
      _messages[_messages.length - 1] = ChatMessage(
        role: ChatRole.assistant,
        content: answer.trim(),
      );
      if (answer.trim().isNotEmpty) {
        await _tts.speak(answer.trim());
      }
    } catch (e) {
      error = e.toString();
      if (answer.isEmpty) {
        _messages.removeLast();
      } else {
        _messages[_messages.length - 1] = ChatMessage(
          role: ChatRole.assistant,
          content: answer,
        );
      }
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  Future<void> stopGeneration() async {
    if (!generating) return;
    await _llm.stop();
    generating = false;
    if (_messages.isNotEmpty && _messages.last.role == ChatRole.assistant) {
      _messages[_messages.length - 1] = _messages.last.copyWith(isStreaming: false);
    }
    notifyListeners();
  }

  void clearChat() {
    if (generating || listening) return;
    _messages.clear();
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_llm.dispose());
    unawaited(_stt.dispose());
    _tts.dispose();
    _installer.dispose();
    super.dispose();
  }
}
