# Validation report

Generated: 2026-09-09

## Verified in this environment

- Source tree and local imports are complete.
- `pubspec.yaml` parses successfully and contains the required LLM/STT/TTS dependencies.
- Python platform configuration script passes `py_compile`.
- Bootstrap shell script passes `bash -n`.
- Platform patcher was executed against a representative generated Flutter Android/iOS host tree and verified to apply:
  - Android `RECORD_AUDIO` + `INTERNET`
  - Android min SDK 26
  - Android NDK r27
  - iOS 16.4 deployment target
  - iOS static frameworks
  - iOS microphone permission macro + Info.plist entry
- Ollama prompt renderer source contains the exact Gemma turn markers.
- Sampling constants are pinned to `temperature=1`, `top_k=64`, `top_p=0.95`, stop `<end_of_turn>`.
- Exact Ollama model-layer prefix is pinned to `7cd4618c1faf` and downloaded bytes are checked against the full SHA-256 supplied by the manifest.

## Not executable in this environment

The current runner has Java 21 and CMake but does not have Flutter, Dart, Gradle, Android SDK tooling, or Xcode. Therefore `flutter pub get`, `flutter analyze`, `flutter test`, APK build, and IPA build could not be executed here.

Use `./scripts/bootstrap_platforms.sh` on a Flutter 3.35+/Dart 3.9+ build machine. The script performs `pub get`, analyzer, and tests automatically after creating and patching current platform host files.
