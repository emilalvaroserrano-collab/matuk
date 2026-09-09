# Translator Mode

A standalone dual-translator Flutter app stored inside the Matuk repository. It is intentionally separate from the existing Matuk voice-assistant application.

## Basis: Matuk local AI stack

Translator Mode copies the same local engines used by Matuk:

- **STT:** `sherpa_asr_sdk` / sherpa-onnx streaming speech recognition.
- **LLM:** the exact Ollama `gemma3:1b` GGUF layer, downloaded from the Ollama registry, pinned to model digest prefix `7cd4618c1faf`, size checked, and SHA-256 verified before loading.
- **Android LLM runtime:** `llama_flutter_android` / llama.cpp.
- **iOS LLM runtime:** `llama_cpp_flutter` / llama.cpp.
- **TTS:** `supertonic_flutter` / Supertonic 3 ONNX.

The existing Matuk assistant source at repository root is not imported or modified at runtime; this folder is a separate Flutter project with its own `pubspec.yaml`.

## Translation flow

```text
Person A mic
  -> local streaming STT
  -> finalized transcript
  -> strict Gemma translation prompt A -> B
  -> token-streamed translation in panel B
  -> Supertonic 3 reads B aloud

Person B mic
  -> local streaming STT
  -> finalized transcript
  -> strict Gemma translation prompt B -> A
  -> token-streamed translation in panel A
  -> Supertonic 3 reads A aloud
```

TTS is stopped before opening the microphone to reduce feedback/self-hearing.

## Default pair

- Side A: English
- Side B: Dutch (Flemish / `nl-BE`)

The Flemish target prompt explicitly asks Gemma for natural Belgian Dutch wording rather than stiff literal Dutch.

## Included language selectors

English, Dutch (Flemish), French, German, Spanish, Italian, and Portuguese are exposed in the first UI pass. The language catalog is isolated in `lib/models/translation_language.dart` so it can be expanded without changing the translator pipeline.

## Important STT limitation inherited from Matuk

The current `sherpa_asr_sdk` packaged streaming model used by Matuk is the package's bilingual streaming model. Translator Mode intentionally keeps that same STT stack as requested. For production multilingual speech input, replace the isolated `OfflineSttService` model/runtime with the chosen multilingual sherpa-onnx/Whisper backend while keeping the Gemma and Supertonic layers unchanged.

## Bootstrap

On a Flutter 3.35+ / Dart 3.9+ machine:

```bash
cd "Translator Mode"
./scripts/bootstrap_platforms.sh
```

The script generates Android/iOS host projects, applies the same local-inference platform configuration as Matuk, then runs `flutter pub get`, `dart format`, `flutter analyze`, and `flutter test`.

## Offline behavior

First setup needs Internet to download Gemma, Supertonic, and the packaged STT model. Translation, speech recognition, and speech synthesis run locally afterward.
