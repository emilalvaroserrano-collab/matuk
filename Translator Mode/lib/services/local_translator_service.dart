import 'dart:async';
import 'dart:io';

import 'package:llama_cpp_flutter/llama_cpp_flutter.dart' as ios_llama;
import 'package:llama_flutter_android/llama_flutter_android.dart' as android_llama;

import '../core/model_constants.dart';
import '../core/translation_prompt_renderer.dart';
import '../models/model_artifact.dart';
import '../models/translation_language.dart';

class LocalTranslatorService {
  final _renderer = const TranslationPromptRenderer();
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
      final format = ios_llama.resolveChatFormat('chatml') ??
          ios_llama.resolveChatFormat('gemma');
      if (format == null) {
        throw StateError('llama_cpp_flutter has no compatible chat format.');
      }

      ios_llama.ModelSpec buildSpec(int gpuLayers) => ios_llama.ModelSpec(
            id: 'eb-translator-smollm2-360m',
            displayName: 'Eb Translator',
            modelUrl: artifact.sourceUri,
            contextSize: ModelConstants.contextSize,
            gpuLayers: gpuLayers,
            format: format,
          );

      ios_llama.LlamaSession session;
      try {
        session = await runtime.loadModel(buildSpec(999), localPath: artifact.path);
      } catch (_) {
        session = await runtime.loadModel(buildSpec(0), localPath: artifact.path);
      }
      _iosSession = session;
      _loaded = true;
      return;
    }

    throw UnsupportedError(
      'Eb Translator local inference is configured for Android and iOS only.',
    );
  }

  Stream<String> translate({
    required TranslationLanguage source,
    required TranslationLanguage target,
    required String text,
    bool medicalMode = false,
  }) async* {
    if (!_loaded) throw StateError('Eb Translator is not loaded.');
    final prompt = _renderer.render(
      source: source,
      target: target,
      text: text,
      medicalMode: medicalMode,
    );

    if (Platform.isAndroid) {
      await _android!.clearContext();
      final stream = _android!.generate(
        prompt: prompt,
        maxTokens: ModelConstants.maxOutputTokens,
        temperature: ModelConstants.temperature,
        topP: ModelConstants.topP,
        topK: ModelConstants.topK,
        minP: 0.0,
      );
      yield* _stopFilteredAndroid(stream);
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
