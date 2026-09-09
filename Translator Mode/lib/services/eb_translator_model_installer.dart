import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/model_constants.dart';
import '../models/model_artifact.dart';

class EbTranslatorModelInstaller {
  EbTranslatorModelInstaller({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Future<Directory> _modelDirectory() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/models');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _metadataFile() async {
    final dir = await _modelDirectory();
    return File('${dir.path}/eb-translator.json');
  }

  Future<File> _modelFile() async {
    final dir = await _modelDirectory();
    return File('${dir.path}/eb-translator-smollm2-360m-q8_0.gguf');
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

      if (digest.toLowerCase() != ModelConstants.modelSha256) return null;
      final file = File(path);
      if (!await file.exists() || await file.length() != size || size <= 0) {
        return null;
      }

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
      onProgress(1, 'Eb Translator already cached');
      return cached;
    }

    final target = await _modelFile();
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();

    final uri = Uri.parse(ModelConstants.modelUri);
    onProgress(0, 'Connecting to Eb Translator model source');
    final request = http.Request('GET', uri);
    final response = await _client.send(request);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Eb Translator download failed: HTTP ${response.statusCode}',
        uri: uri,
      );
    }

    final sink = partial.openWrite();
    var received = 0;
    final expectedSize = response.contentLength ?? 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final progress = expectedSize > 0
            ? (received / expectedSize).clamp(0.0, 0.98)
            : 0.5;
        onProgress(
          progress,
          'Downloading Eb Translator ${(received / 1024 / 1024).toStringAsFixed(0)} MB',
        );
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    final actualSize = await partial.length();
    if (actualSize <= 0) {
      await partial.delete();
      throw StateError('Eb Translator download produced an empty model file.');
    }
    if (expectedSize > 0 && actualSize != expectedSize) {
      await partial.delete();
      throw StateError(
        'Eb Translator size mismatch: expected $expectedSize, got $actualSize.',
      );
    }

    onProgress(0.99, 'Verifying Eb Translator');
    final actualDigest = (await sha256.bind(partial.openRead()).first)
        .toString()
        .toLowerCase();
    if (actualDigest != ModelConstants.modelSha256) {
      await partial.delete();
      throw StateError('Eb Translator SHA-256 verification failed.');
    }

    if (await target.exists()) await target.delete();
    await partial.rename(target.path);

    final artifact = ModelArtifact(
      path: target.path,
      digest: actualDigest,
      size: actualSize,
      sourceUri: uri,
    );

    final metadata = await _metadataFile();
    await metadata.writeAsString(jsonEncode({
      'alias': 'Eb Translator',
      'source_model': 'HuggingFaceTB/SmolLM2-360M-Instruct',
      'runtime_model': ModelConstants.modelRepository,
      'file': ModelConstants.modelFile,
      'path': artifact.path,
      'digest': artifact.digest,
      'size': artifact.size,
      'source': artifact.sourceUri.toString(),
    }));

    await _cleanupLegacyGemmaFiles();
    onProgress(1, 'Eb Translator verified');
    return artifact;
  }

  Future<void> _cleanupLegacyGemmaFiles() async {
    final dir = await _modelDirectory();
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name == 'gemma3-1b.json' ||
          (name.startsWith('gemma3-1b-') && name.endsWith('.gguf'))) {
        try {
          await entity.delete();
        } catch (_) {
          // Cleanup is opportunistic; never fail a verified Eb Translator install.
        }
      }
    }
  }

  void dispose() => _client.close();
}
