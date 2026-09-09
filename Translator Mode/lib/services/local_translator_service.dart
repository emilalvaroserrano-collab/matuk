import 'dart:async';

import 'package:lib_llama_cpp/lib_llama_cpp.dart';

import '../core/model_constants.dart';
import '../core/translation_prompt_renderer.dart';
import '../models/model_artifact.dart';
import '../models/translation_language.dart';

class LocalTranslatorService {
  final _renderer = const TranslationPromptRenderer();
  ModelArtifact? _artifact;
  bool _loaded = false;
  bool _stopRequested = false;

  bool get isLoaded => _loaded;

  Future<void> load(ModelArtifact artifact) async {
    _artifact = artifact;
    _loaded = true;
    _stopRequested = false;
  }

  Stream<String> translate({
    required TranslationLanguage source,
    required TranslationLanguage target,
    required String text,
    bool medicalMode = false,
  }) async* {
    final artifact = _artifact;
    if (!_loaded || artifact == null) {
      throw StateError('Eb Translator is not loaded.');
    }

    final prompt = _renderer.render(
      source: source,
      target: target,
      text: text,
      medicalMode: medicalMode,
    );

    _stopRequested = false;
    final runtime = const LibLlamaCpp();
    final commands = Stream<LlamaCommand>.fromIterable([
      LlamaLoadModelCommand(
        modelPath: artifact.path,
        contextSize: ModelConstants.contextSize,
        gpuLayerCount: 0,
      ),
      LlamaGenerateCommand(
        prompt: prompt,
        maxTokens: ModelConstants.maxOutputTokens,
        temperature: ModelConstants.temperature,
        topP: ModelConstants.topP,
        stop: const [ModelConstants.stopSequence],
      ),
      const LlamaDisposeCommand(),
    ]);

    try {
      await for (final response in runtime.transform(commands)) {
        if (_stopRequested) {
          continue;
        }
        if (response is LlamaTokenResponse) {
          if (response.text.isNotEmpty) {
            yield response.text;
          }
        } else if (response is LlamaErrorResponse) {
          throw StateError('Eb Translator inference failed: ${response.message}');
        }
      }
    } finally {
      _loaded = false;
      _artifact = null;
      _stopRequested = false;
    }
  }

  Future<void> stop() async {
    _stopRequested = true;
  }

  Future<void> dispose() async {
    _stopRequested = true;
    _artifact = null;
    _loaded = false;
  }
}
