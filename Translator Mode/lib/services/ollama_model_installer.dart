import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/model_constants.dart';
import '../models/model_artifact.dart';

class OllamaModelInstaller {
  OllamaModelInstaller({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Directory> _modelDirectory() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/models');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _metadataFile() async {
    final dir = await _modelDirectory();
    return File('${dir.path}/gemma3-1b.json');
  }

  Future<ModelArtifact?> cachedArtifact() async {
    try {
      final metadata = await _metadataFile();
      if (!await metadata.exists()) return null;
      final json = jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
      final path = json['path'] as String?;
      final digest = json['digest'] as String?;
      final size = json['size'] as int?;
      final source = json['source'] as String?;
      if (path == null || digest == null || size == null || source == null) {
        return null;
      }
      final file = File(path);
      if (!await file.exists() || await file.length() != size) return null;
      return ModelArtifact(
        path: path,
        digest: digest,
        size: size,
        sourceUri: Uri.parse(source),
      );
    } catch (_) {
      return null;
    }
  }

  Future<ModelArtifact> install({
    required void Function(double progress, String detail) onProgress,
  }) async {
    final cached = await cachedArtifact();
    if (cached != null) {
      onProgress(1, 'Exact Gemma 3 1B model already cached');
      return cached;
    }

    onProgress(0, 'Resolving Ollama gemma3:1b manifest');
    final manifestResponse = await _client.get(
      Uri.parse(ModelConstants.manifestUri),
      headers: const {
        'Accept': 'application/vnd.docker.distribution.manifest.v2+json',
      },
    );
    if (manifestResponse.statusCode != 200) {
      throw HttpException(
        'Ollama manifest request failed: ${manifestResponse.statusCode}',
        uri: Uri.parse(ModelConstants.manifestUri),
      );
    }

    final manifest = jsonDecode(manifestResponse.body) as Map<String, dynamic>;
    final layers = (manifest['layers'] as List<dynamic>?) ?? const [];
    final modelLayer = layers.cast<Map<String, dynamic>>().where(
          (layer) => layer['mediaType'] == ModelConstants.modelMediaType,
        );
    if (modelLayer.length != 1) {
      throw StateError('Expected one Ollama model layer, found ${modelLayer.length}.');
    }

    final layer = modelLayer.single;
    final digest = layer['digest'] as String;
    final expectedSize = layer['size'] as int;
    if (!digest.startsWith('sha256:')) {
      throw StateError('Unsupported Ollama digest: $digest');
    }
    final digestHex = digest.substring('sha256:'.length).toLowerCase();
    if (!digestHex.startsWith(ModelConstants.modelDigestPrefix)) {
      throw StateError(
        'Ollama gemma3:1b no longer resolves to the pinned model layer '
        '${ModelConstants.modelDigestPrefix}. Refusing silent model drift.',
      );
    }

    final blobUri = Uri.parse('${ModelConstants.blobBaseUri}/$digest');
    final dir = await _modelDirectory();
    final digestShort = digest.substring('sha256:'.length, 'sha256:'.length + 12);
    final target = File('${dir.path}/gemma3-1b-$digestShort.gguf');
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();

    onProgress(0, 'Downloading exact Ollama GGUF model');
    final request = http.Request('GET', blobUri);
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw HttpException(
        'Ollama model download failed: ${response.statusCode}',
        uri: blobUri,
      );
    }

    final sink = partial.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final denominator =
            expectedSize > 0 ? expectedSize : response.contentLength ?? 1;
        onProgress(
          (received / denominator).clamp(0, 1),
          'Downloading Gemma 3 1B ${(received / 1024 / 1024).toStringAsFixed(0)} MB',
        );
      }
    } finally {
      await sink.close();
    }

    final actualSize = await partial.length();
    if (actualSize != expectedSize) {
      await partial.delete();
      throw StateError(
        'Model size mismatch: expected $expectedSize, got $actualSize.',
      );
    }

    onProgress(0.99, 'Verifying SHA-256');
    final actualDigest = await sha256.bind(partial.openRead()).first;
    if (actualDigest.toString().toLowerCase() != digestHex) {
      await partial.delete();
      throw StateError('Gemma model SHA-256 verification failed.');
    }

    if (await target.exists()) await target.delete();
    await partial.rename(target.path);
    final artifact = ModelArtifact(
      path: target.path,
      digest: digest,
      size: expectedSize,
      sourceUri: blobUri,
    );

    final metadata = await _metadataFile();
    await metadata.writeAsString(jsonEncode({
      'model': '${ModelConstants.ollamaModel}:${ModelConstants.ollamaTag}',
      'path': artifact.path,
      'digest': artifact.digest,
      'size': artifact.size,
      'source': artifact.sourceUri.toString(),
    }));
    onProgress(1, 'Gemma 3 1B verified');
    return artifact;
  }

  void dispose() => _client.close();
}
