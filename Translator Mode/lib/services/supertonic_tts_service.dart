import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

class SupertonicTtsService {
  static const _modelName =
      'sherpa-onnx-supertonic-3-tts-int8-2026-05-11';
  static const _modelBase =
      'https://huggingface.co/csukuangfj2/$_modelName/resolve/main';
  static const _files = <String>[
    'duration_predictor.int8.onnx',
    'text_encoder.int8.onnx',
    'vector_estimator.int8.onnx',
    'vocoder.int8.onnx',
    'tts.json',
    'unicode_indexer.bin',
    'voice.bin',
  ];

  static const MethodChannel _androidAudio = MethodChannel(
    'ai.eburon.dual_translate/audio_output',
  );

  // Kept only as a non-Android fallback. Android uses AudioTrack directly so
  // generated Supertonic PCM never passes through MediaPlayer/setSource.
  final AudioPlayer _player = AudioPlayer();
  final http.Client _client = http.Client();
  sherpa_onnx.OfflineTts? _tts;
  bool _initialized = false;

  Future<Directory> _modelDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/models/$_modelName');
  }

  Future<bool> modelsReady() async {
    final dir = await _modelDirectory();
    for (final name in _files) {
      final file = File('${dir.path}/$name');
      if (!await file.exists() || await file.length() == 0) return false;
    }
    return true;
  }

  /// First-run setup is download-only. Native Speech Synthesys initialization
  /// is deferred until audio is actually requested.
  Future<void> prepare({
    required void Function(int done, int total, String file, double progress)
        onProgress,
  }) async {
    final dir = await _modelDirectory();
    await dir.create(recursive: true);

    var done = 0;
    for (final name in _files) {
      final target = File('${dir.path}/$name');
      if (await target.exists() && await target.length() > 0) {
        done += 1;
        onProgress(done, _files.length, name, 1);
        continue;
      }

      await _downloadFile(
        name,
        target,
        onProgress: (progress) =>
            onProgress(done, _files.length, name, progress),
      );
      done += 1;
      onProgress(done, _files.length, name, 1);
    }
  }

  Future<void> _downloadFile(
    String name,
    File target, {
    required void Function(double progress) onProgress,
  }) async {
    final part = File('${target.path}.part');
    if (await part.exists()) await part.delete();

    final request = http.Request(
      'GET',
      Uri.parse('$_modelBase/$name?download=true'),
    );
    final response = await _client.send(request);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Speech Synthesys model download failed for $name: HTTP ${response.statusCode}',
      );
    }

    final sink = part.openWrite();
    var received = 0;
    final total = response.contentLength ?? 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
      if (await part.length() == 0) {
        throw StateError('Downloaded Speech Synthesys model file is empty: $name');
      }
      await part.rename(target.path);
    } catch (_) {
      await sink.close();
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;
    if (!await modelsReady()) {
      throw StateError('Speech Synthesys model files are not ready.');
    }

    await sherpa_onnx.initBindingsAsync();
    final dir = await _modelDirectory();
    final base = dir.path;
    final supertonic = sherpa_onnx.OfflineTtsSupertonicModelConfig(
      durationPredictor: '$base/duration_predictor.int8.onnx',
      textEncoder: '$base/text_encoder.int8.onnx',
      vectorEstimator: '$base/vector_estimator.int8.onnx',
      vocoder: '$base/vocoder.int8.onnx',
      ttsJson: '$base/tts.json',
      unicodeIndexer: '$base/unicode_indexer.bin',
      voiceStyle: '$base/voice.bin',
    );
    final model = sherpa_onnx.OfflineTtsModelConfig(
      supertonic: supertonic,
      numThreads: 2,
      debug: false,
    );
    _tts = sherpa_onnx.OfflineTts(
      sherpa_onnx.OfflineTtsConfig(model: model),
    );
    _initialized = true;
  }

  Future<void> speak(
    String text, {
    required String language,
    String voiceStyle = 'M1',
  }) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;
    if (!_initialized) await initialize();

    await stop();
    final audio = _tts!.generateWithConfig(
      text: cleaned,
      config: sherpa_onnx.OfflineTtsGenerationConfig(
        sid: 6,
        speed: 1.03,
        extra: <String, Object>{
          'lang': language,
          'num_steps': 5,
        },
      ),
    );

    if (audio.samples.isEmpty || audio.sampleRate <= 0) {
      throw StateError('Speech Synthesys produced invalid audio.');
    }

    if (Platform.isAndroid) {
      final pcm16 = _encodePcm16(audio.samples);
      try {
        await _androidAudio.invokeMethod<void>('playPcm16', <String, Object>{
          'sampleRate': audio.sampleRate,
          'pcm': pcm16,
        });
      } on PlatformException catch (e) {
        throw StateError(
          'Speech Synthesys Android audio output failed: ${e.message ?? e.code}',
        );
      }
      return;
    }

    final temp = await getTemporaryDirectory();
    final wav = File('${temp.path}/matuk_speech_synthesys.wav');
    final ok = sherpa_onnx.writeWave(
      filename: wav.path,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
    if (!ok) throw StateError('Failed to write Speech Synthesys audio.');
    await _player.play(DeviceFileSource(wav.path));
  }

  Uint8List _encodePcm16(List<double> samples) {
    final bytes = Uint8List(samples.length * 2);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < samples.length; i++) {
      final normalized = samples[i].clamp(-1.0, 1.0).toDouble();
      final value = (normalized * 32767.0).round().clamp(-32768, 32767);
      data.setInt16(i * 2, value, Endian.little);
    }
    return bytes;
  }

  Future<void> stop() async {
    if (Platform.isAndroid) {
      try {
        await _androidAudio.invokeMethod<void>('stopPcm');
      } on PlatformException {
        // Playback may already have completed or the channel may be tearing down.
      }
    }
    await _player.stop();
  }

  /// Frees the native Speech Synthesys model while retaining downloaded files.
  Future<void> releaseRuntime() async {
    await stop();
    _tts?.free();
    _tts = null;
    _initialized = false;
  }

  void dispose() {
    if (Platform.isAndroid) {
      unawaited(_androidAudio.invokeMethod<void>('stopPcm'));
    }
    _tts?.free();
    _tts = null;
    _initialized = false;
    _player.dispose();
    _client.close();
  }
}
