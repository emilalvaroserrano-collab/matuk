# Translator Mode validation status

## Source-level checks by construction

- Translator Mode is a separate Flutter project under the Matuk repository root.
- It uses the same dependency versions as Matuk for Gemma/llama.cpp, Sherpa STT, and Supertonic 3.
- The exact Ollama `gemma3:1b` manifest/blob installer and digest pin are copied from Matuk.
- Android and iOS inference use the same llama.cpp packages and sampling constants as Matuk.
- TTS is stopped before microphone capture to reduce feedback.
- Translation is two-way: side A can translate to side B, and side B can translate to side A.
- Translation output streams token-by-token into the opposite language panel before optional Supertonic read-aloud.
- The Gemma prompt explicitly forbids answering/explaining and requests translation-only output.

## Build verification

This repository edit was performed through the GitHub connector, which does not provide a Flutter/Android/iOS build runner. Therefore this commit is source-verified but not APK/IPA build-verified.

Run:

```bash
cd "Translator Mode"
./scripts/bootstrap_platforms.sh
```

on a Flutter 3.35+/Dart 3.9+ build machine. The script runs `flutter analyze` and `flutter test` after generating the Android/iOS hosts.
