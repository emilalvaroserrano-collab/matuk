import 'dart:async';

import 'package:permission_handler/permission_handler.dart';
import 'package:sherpa_asr_sdk/sherpa_asr_sdk.dart';

class OfflineSttService {
  StreamSubscription<String>? _subscription;
  bool _initialized = false;

  Future<bool> modelsReady() =>
      SherpaModelsManager.instance.hasStreamingBilingualModel();

  Future<void> prepare({required void Function(double progress) onProgress}) async {
    final manager = SherpaModelsManager.instance;
    if (!await manager.hasStreamingBilingualModel()) {
      await manager.downloadStreamingBilingualModels(onProgress: onProgress);
    }
    await initialize(onProgress: onProgress);
  }

  Future<void> initialize({void Function(double progress)? onProgress}) async {
    if (_initialized && AsrSdk.isInitialized) return;
    AsrSdk.setLogger(DefaultAsrLogger());
    final ok = await AsrSdk.initialize(onProgress: onProgress);
    if (!ok) throw StateError('Sherpa ASR failed to initialize.');
    _initialized = true;
  }

  Future<void> startListening(void Function(String text) onText) async {
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      throw StateError('Microphone permission was denied.');
    }
    if (!_initialized) await initialize();
    if (!AsrSdk.isStarted) await AsrSdk.start();
    await _subscription?.cancel();
    _subscription = AsrSdk.recognize().listen(onText);
  }

  Future<void> stopListening() async {
    if (AsrSdk.isListening) await AsrSdk.stopRecognition();
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await stopListening();
    if (AsrSdk.isStarted) await AsrSdk.stop();
    if (AsrSdk.isInitialized) await AsrSdk.dispose();
    _initialized = false;
  }
}
