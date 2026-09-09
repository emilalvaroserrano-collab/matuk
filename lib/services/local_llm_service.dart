import 'dart:async';
import 'dart:io';

import 'package:llama_cpp_flutter/llama_cpp_flutter.dart' as ios_llama;
import 'package:llama_flutter_android/llama_flutter_android.dart' as android_llama;

import '../core/model_constants.dart';
import '../core/ollama_prompt_renderer.dart';
import '../models/chat_message.dart';
import '../models/model_artifact.dart';

class LocalLlmService {
  final _renderer = const OllamaGemma3PromptRenderer();
  android_llama.LlamaController? _android;
  ios_llama.LlamaSession? _iosSession;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load(ModelArtifact artifact) async {
    if (_loaded) return;
    if (Platform.isAndroid) {
      final controller = android_llama.LlamaController();
      final gpu = await controller.detectGpu();
      await controller.loadModel(
        modelPath: artifact.path,
        threads: 4,
        contextSize: ModelConstants.contextSize,
        gpuLayers: gpu.recommendedGpuLayers,
      );
      _android = controller;
      _loaded = true;
      return;
    }

    if (Platform.isIOS) {
      final runtime = ios_llama.createLlamaRuntime();
      final format = ios_llama.resolveChatFormat('gemma');
      if (format == null) throw StateError('llama_cpp_flutter has no Gemma chat format.');

      ios_llama.ModelSpec buildSpec(int gpuLayers) => ios_llama.ModelSpec(
            id: 'ollama-gemma3-1b',
            displayName: 'Ollama Gemma 3 1B Q4_K_M',
            modelUrl: artifact.sourceUri,
            contextSize: ModelConstants.contextSize,
            gpuLayers: gpuLayers,
            format: format,
          );

      ios_llama.LlamaSession session;
      try {
        session = await runtime.loadModel(buildSpec(999), localPath: artifact.path);
      } catch (_) {
        // Simulator/older devices may not have usable Metal. CPU fallback is
        // slower but keeps the same model and sampling behavior.
        session = await runtime.loadModel(buildSpec(0), localPath: artifact.path);
      }
      _iosSession = session;
      _loaded = true;
      return;
    }

    throw UnsupportedError('Local Gemma inference is configured for Android and iOS only.');
  }

  Stream<String> generate(List<ChatMessage> history) async* {
    if (!_loaded) throw StateError('Gemma model is not loaded.');
    final prompt = _renderer.render(history);

    if (Platform.isAndroid) {
      await _android!.clearContext();
      final source = _android!.generate(
        prompt: prompt,
        maxTokens: ModelConstants.maxOutputTokens,
        temperature: ModelConstants.temperature,
        topP: ModelConstants.topP,
        topK: ModelConstants.topK,
        minP: 0.0,
      );
      yield* _stopFilteredAndroid(source);
      return;
    }

    if (Platform.isIOS) {
      await _iosSession!.clearSequence(0);
      yield* _iosSession!.generate(
        prompt,
        maxTokens: ModelConstants.maxOutputTokens,
        temperature: ModelConstants.temperature,
        topK: ModelConstants.topK,
        topP: ModelConstants.topP,
        stopSequences: const [ModelConstants.stopSequence],
      );
      return;
    }
  }

  Stream<String> _stopFilteredAndroid(Stream<String> source) async* {
    const stop = ModelConstants.stopSequence;
    var pending = '';
    await for (final token in source) {
      pending += token;
      final stopIndex = pending.indexOf(stop);
      if (stopIndex >= 0) {
        final visible = pending.substring(0, stopIndex);
        if (visible.isNotEmpty) yield visible;
        unawaited(_android?.stop());
        return;
      }

      // Keep enough trailing text to detect a stop marker split over tokens.
      final safeLength = pending.length - stop.length + 1;
      if (safeLength > 0) {
        yield pending.substring(0, safeLength);
        pending = pending.substring(safeLength);
      }
    }
    if (pending.isNotEmpty) yield pending;
  }

  Future<void> stop() async {
    if (Platform.isAndroid) await _android?.stop();
    if (Platform.isIOS) await _iosSession?.cancel();
  }

  Future<void> dispose() async {
    await stop();
    await _android?.dispose();
    await _iosSession?.dispose();
    _android = null;
    _iosSession = null;
    _loaded = false;
  }
}
