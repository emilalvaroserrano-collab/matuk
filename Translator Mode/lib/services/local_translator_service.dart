import 'dart:async';

import 'package:lib_llama_cpp/lib_llama_cpp.dart';

import '../core/model_constants.dart';
import '../core/translation_prompt_renderer.dart';
import '../models/model_artifact.dart';
import '../models/translation_language.dart';

/// Persistent, fully local Eb Translator runtime.
///
/// The earlier implementation loaded and disposed the GGUF for every sentence.
/// This service keeps llama.cpp loaded behind the package's loopback-only local
/// server for the lifetime of a voice session, removing repeated model-load
/// latency while preserving token streaming.
class LocalTranslatorService {
  static const _modelId = 'eb-translator';

  final _renderer = const TranslationPromptRenderer();
  ModelArtifact? _artifact;
  LlamaHttpServer? _server;
  LlamaServerClient? _client;
  bool _stopRequested = false;
  Future<void>? _loading;

  bool get isLoaded => _server != null && _client != null;

  Future<void> load(ModelArtifact artifact) async {
    if (isLoaded && _artifact?.path == artifact.path) {
      _stopRequested = false;
      return;
    }
    final inFlight = _loading;
    if (inFlight != null) {
      await inFlight;
      if (isLoaded && _artifact?.path == artifact.path) return;
    }

    final completer = Completer<void>();
    _loading = completer.future;
    try {
      await dispose();
      final server = LlamaHttpServer.open(
        config: LlamaServerConfig(
          model: _modelId,
          modelPath: artifact.path,
          port: 0,
        ),
      );
      final address = await server.start();
      _server = server;
      _client = LlamaServerClient(
        baseUri: Uri.parse('http://${address.host}:${address.port}/v1'),
      );
      _artifact = artifact;
      _stopRequested = false;
      completer.complete();
    } catch (e, st) {
      _server = null;
      _client = null;
      _artifact = null;
      completer.completeError(e, st);
      rethrow;
    } finally {
      _loading = null;
    }
  }

  Stream<String> translate({
    required TranslationLanguage source,
    required TranslationLanguage target,
    required String text,
    bool medicalMode = false,
  }) async* {
    final client = _client;
    if (!isLoaded || client == null || _artifact == null) {
      throw StateError('Eb Translator is not loaded.');
    }

    _stopRequested = false;
    final system = _renderer.systemInstructions(medicalMode: medicalMode);
    final user = _renderer.userContent(
      source: source,
      target: target,
      text: text,
    );

    await for (final event in client.streamChatCompletion(
      model: _modelId,
      messages: <Map<String, Object?>>[
        <String, Object?>{'role': 'system', 'content': system},
        <String, Object?>{'role': 'user', 'content': user},
      ],
      maxTokens: ModelConstants.maxOutputTokens,
      temperature: ModelConstants.temperature,
      topP: ModelConstants.topP,
      stop: const [ModelConstants.stopSequence],
    )) {
      if (_stopRequested) continue;
      final token = _extractDelta(event);
      if (token.isNotEmpty) yield token;
    }
  }

  String _extractDelta(Map<String, Object?> event) {
    final choices = event['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final first = choices.first;
    if (first is! Map) return '';
    final delta = first['delta'];
    if (delta is Map) {
      final content = delta['content'];
      if (content is String) return _cleanToken(content);
    }
    final text = first['text'];
    if (text is String) return _cleanToken(text);
    return '';
  }

  String _cleanToken(String token) {
    return token
        .replaceAll(ModelConstants.stopSequence, '')
        .replaceAll('<|im_start|>', '')
        .replaceAll('<|im_end|>', '');
  }

  Future<void> stop() async {
    _stopRequested = true;
  }

  Future<void> dispose() async {
    _stopRequested = true;
    final server = _server;
    _server = null;
    _client = null;
    _artifact = null;
    if (server != null) {
      await server.close();
    }
  }
}
