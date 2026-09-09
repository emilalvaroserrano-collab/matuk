# Translator Mode

A standalone dual-translator Flutter app stored inside the Matuk repository. It is intentionally separate from the existing Matuk voice-assistant application.

## Local AI stack and aliases

Translator Mode uses these user-facing engine names:

- **Speech Recognition:** `sherpa_asr_sdk` / sherpa-onnx streaming speech recognition.
- **Eb Translator:** `HuggingFaceTB/SmolLM2-360M-Instruct`, executed through llama.cpp using Hugging Face's official `HuggingFaceTB/SmolLM2-360M-Instruct-GGUF` Q8_0 conversion (`smollm2-360m-instruct-q8_0.gguf`). The downloaded GGUF is pinned to SHA-256 `48ab3034d0dd401fbc721eb1df3217902fee7dab9078992d66431f09b7750201`.
- **Android Eb Translator runtime:** `llama_flutter_android` / llama.cpp.
- **iOS Eb Translator runtime:** `llama_cpp_flutter` / llama.cpp.
- **Speech Synthesys:** Supertonic 3 through the same sherpa-onnx native runtime used by Speech Recognition.

The existing Matuk assistant source at repository root is not imported or modified at runtime; this folder is a separate Flutter project with its own `pubspec.yaml`.

## Translation flow

```text
Person A mic
  -> Speech Recognition
  -> finalized transcript
  -> strict Eb Translator prompt A -> B
  -> token-streamed translation in panel B
  -> Speech Synthesys reads B aloud

Person B mic
  -> Speech Recognition
  -> finalized transcript
  -> strict Eb Translator prompt B -> A
  -> token-streamed translation in panel A
  -> Speech Synthesys reads A aloud
```

Speech Synthesys is stopped before opening Speech Recognition to reduce feedback/self-hearing. Heavy native engines are loaded lazily and released between stages to keep peak mobile RAM lower.

## Default pair

- Side A: English
- Side B: Dutch (Flemish / `nl-BE`)

The Flemish target prompt asks Eb Translator for natural Belgian Dutch wording rather than stiff literal Dutch.

## Included language selectors

English, Dutch (Flemish), French, German, Spanish, Italian, and Portuguese are exposed in the first UI pass. The language catalog is isolated in `lib/models/translation_language.dart` so it can be expanded without changing the translator pipeline.

## Model-language caveat

The selected SmolLM2-360M-Instruct model card labels the model as English. Translator Mode still instructs it to translate the configured language pairs, but multilingual translation quality should be validated carefully before production deployment, especially for Flemish and non-English-to-non-English pairs.

## Speech Recognition limitation

The current `sherpa_asr_sdk` packaged streaming model is the package's bilingual streaming model. For production multilingual speech input, replace the isolated `OfflineSttService` model/runtime with a multilingual sherpa-onnx or Whisper backend while keeping the surrounding translator flow unchanged.

## Bootstrap

On a current stable Flutter SDK:

```bash
cd "Translator Mode"
./scripts/bootstrap_platforms.sh
```

The script generates Android/iOS host projects, applies local-inference platform configuration, then runs `flutter pub get`, `dart format`, `flutter analyze`, and `flutter test`.

## Offline behavior

First setup needs Internet to download Eb Translator, Speech Recognition, and Speech Synthesys model files. Translation, speech recognition, and speech synthesis run locally afterward.
