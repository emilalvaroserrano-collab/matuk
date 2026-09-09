import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class OfflineSttService {
  static const MethodChannel _methods = MethodChannel(
    'ai.eburon.dual_translate/on_device_stt',
  );
  static const EventChannel _events = EventChannel(
    'ai.eburon.dual_translate/on_device_stt_events',
  );

  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _finalCompleter;
  void Function(String text)? _onText;
  bool _listening = false;
  String _languageTag = 'en-US';
  String? _lastError;

  void setLanguageTag(String languageTag) {
    _languageTag = languageTag;
  }

  Future<bool> modelsReady() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _methods.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Android Speech Recognition is provided by the device itself.
  /// No separate STT model is downloaded by Dual Translate.
  Future<void> prepare({required void Function(double progress) onProgress}) async {
    onProgress(0.2);
    if (!await modelsReady()) {
      throw StateError(
        'Android on-device Speech Recognition is unavailable on this device. '
        'Install or enable the device offline speech recognition service/language pack.',
      );
    }
    onProgress(1);
  }

  Future<void> initialize({void Function(double progress)? onProgress}) async {
    onProgress?.call(0.2);
    if (!await modelsReady()) {
      throw StateError('Android on-device Speech Recognition is unavailable.');
    }
    onProgress?.call(1);
  }

  Future<void> startListening(void Function(String text) onText) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'This build uses Android on-device Speech Recognition.',
      );
    }

    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      throw StateError('Microphone permission was denied.');
    }

    if (!await modelsReady()) {
      throw StateError(
        'Android on-device Speech Recognition is not available. '
        'No cloud fallback is allowed in this build.',
      );
    }

    await stopListening();
    _onText = onText;
    _lastError = null;
    _finalCompleter = Completer<void>();

    _subscription = _events.receiveBroadcastStream().listen(
      (dynamic raw) {
        if (raw is! Map) return;
        final event = Map<Object?, Object?>.from(raw);
        final type = event['type']?.toString();
        if (type == 'result') {
          final text = event['text']?.toString().trim() ?? '';
          if (text.isNotEmpty) _onText?.call(text);
          final isFinal = event['final'] == true;
          if (isFinal && !(_finalCompleter?.isCompleted ?? true)) {
            _finalCompleter?.complete();
          }
        } else if (type == 'error') {
          final code = event['code'] as int? ?? -1;
          final message = event['message']?.toString() ?? 'Speech Recognition error';
          if (code != 6 && code != 7) {
            _lastError = message;
          }
          if (!(_finalCompleter?.isCompleted ?? true)) {
            _finalCompleter?.complete();
          }
        }
      },
      onError: (Object error) {
        _lastError = error.toString();
        if (!(_finalCompleter?.isCompleted ?? true)) {
          _finalCompleter?.complete();
        }
      },
    );

    try {
      await _methods.invokeMethod<void>('start', <String, Object>{
        'languageTag': _languageTag,
      });
      _listening = true;
    } catch (_) {
      await _subscription?.cancel();
      _subscription = null;
      _onText = null;
      rethrow;
    }
  }

  Future<void> stopListening() async {
    if (!_listening) {
      await _subscription?.cancel();
      _subscription = null;
      return;
    }

    try {
      await _methods.invokeMethod<void>('stop');
      final completer = _finalCompleter;
      if (completer != null && !completer.isCompleted) {
        try {
          await completer.future.timeout(const Duration(milliseconds: 1400));
        } on TimeoutException {
          // Some OEM recognizers do not emit an explicit final callback after
          // stopListening. The latest partial transcript is still preserved.
        }
      }
    } finally {
      _listening = false;
      await _subscription?.cancel();
      _subscription = null;
      _onText = null;
      _finalCompleter = null;
    }

    final failure = _lastError;
    _lastError = null;
    if (failure != null) throw StateError(failure);
  }

  Future<void> releaseRuntime() async {
    try {
      await stopListening();
    } finally {
      if (Platform.isAndroid) {
        try {
          await _methods.invokeMethod<void>('destroy');
        } on PlatformException {
          // The recognizer may already have been destroyed by Android.
        }
      }
    }
  }

  Future<void> dispose() => releaseRuntime();
}
