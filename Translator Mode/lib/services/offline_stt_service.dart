import 'dart:async';

import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

class OfflineSttService {
  static const WhisperModelDescriptor _speechModel = WhisperModelCatalog.base;

  final WhisperModelManager _models = WhisperModelManager();

  WhisperEngine? _engine;
  WhisperStreamTask? _task;
  StreamSubscription<WhisperStreamUpdate>? _updates;
  void Function(String text)? _onText;
  String _lastText = '';

  Future<bool> modelsReady() async {
    try {
      return await _models.findCatalogModel(_speechModel) != null;
    } on FormatException {
      return false;
    }
  }

  /// Installs only the Speech Recognition model.
  ///
  /// The whisper.cpp model manager uses a checksum-pinned catalog and
  /// resumable downloads, so an interrupted download can continue later
  /// without restarting the other local AI models.
  Future<void> prepare({required void Function(double progress) onProgress}) async {
    var cached = await _verifiedModelOrNull();
    if (cached != null) {
      onProgress(1);
      return;
    }

    await for (final progress in _models.downloadCatalogModel(_speechModel)) {
      onProgress((progress.fraction ?? 0.0).clamp(0.0, 1.0));
    }

    cached = await _verifiedModelOrNull();
    if (cached == null) {
      throw StateError('Speech Recognition model download did not verify.');
    }
    onProgress(1);
  }

  Future<void> initialize({void Function(double progress)? onProgress}) async {
    if (_engine != null) return;

    onProgress?.call(0);
    final model = await _verifiedModelOrNull();
    if (model == null) {
      throw StateError('Speech Recognition model is not installed.');
    }

    try {
      _engine = await WhisperEngine.load(
        model.path,
        config: const WhisperConfig(
          useGpu: true,
          useFlashAttention: true,
        ),
      );
    } catch (_) {
      _engine = await WhisperEngine.load(
        model.path,
        config: const WhisperConfig(
          useGpu: false,
          useFlashAttention: true,
        ),
      );
    }
    onProgress?.call(1);
  }

  Future<void> startListening(void Function(String text) onText) async {
    await stopListening();
    if (_engine == null) await initialize();

    _onText = onText;
    _lastText = '';

    final engine = _engine;
    if (engine == null) {
      throw StateError('Speech Recognition failed to initialize.');
    }

    final task = await engine.transcribeMicrophone(
      options: const TranscribeOptions(
        language: 'auto',
        detectLanguage: true,
        threads: 4,
        noContext: true,
        tokenTimestamps: false,
        noTimestamps: true,
        suppressBlank: true,
      ),
      config: const WhisperStreamConfig(
        updateInterval: Duration(milliseconds: 1200),
        windowDuration: Duration(seconds: 20),
        confirmationLag: Duration(milliseconds: 2500),
      ),
    );

    _task = task;
    _updates = task.updates.listen(
      (update) {
        final text = update.text.trim();
        if (text.isEmpty || text == _lastText) return;
        _lastText = text;
        _onText?.call(text);
      },
      onError: (Object error, StackTrace stackTrace) {},
    );
  }

  Future<void> stopListening() async {
    final task = _task;
    if (task == null) {
      await _updates?.cancel();
      _updates = null;
      return;
    }

    try {
      final finalUpdate = await task.stop();
      final finalText = finalUpdate.text.trim();
      if (finalText.isNotEmpty) {
        _lastText = finalText;
        _onText?.call(finalText);
      }
    } finally {
      await _updates?.cancel();
      _updates = null;
      _task = null;
      _onText = null;
    }
  }

  /// Releases whisper.cpp native memory while keeping the downloaded model
  /// file available for the next microphone turn.
  Future<void> releaseRuntime() async {
    await stopListening();
    _engine?.dispose();
    _engine = null;
    _lastText = '';
  }

  Future<void> dispose() async {
    await releaseRuntime();
    _models.close();
  }

  Future<dynamic> _verifiedModelOrNull() async {
    try {
      return await _models.findCatalogModel(_speechModel);
    } on FormatException {
      await _models.delete(_speechModel.fileName);
      return null;
    }
  }
}
