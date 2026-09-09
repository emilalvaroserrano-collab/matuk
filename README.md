# Gemma Voice Assistant — Flutter / Fully Local

A mobile-first Flutter voice assistant for Android and iOS using:

- **LLM:** the exact Ollama `gemma3:1b` GGUF model layer (1B, Q4_K_M). The app resolves Ollama's registry manifest, downloads the model blob, validates its size, pins the official model-layer ID prefix `7cd4618c1faf`, and verifies the manifest's full SHA-256 before loading it.
- **Android LLM runtime:** `llama_flutter_android` (llama.cpp, token streaming, Vulkan with CPU fallback behavior chosen by its GPU detector).
- **iOS LLM runtime:** `llama_cpp_flutter` (llama.cpp + Metal; CPU retry if Metal model loading fails).
- **STT:** `sherpa_asr_sdk` / sherpa-onnx streaming speech recognition, fully offline after its first model download.
- **TTS:** `supertonic_flutter` backed by **Supertonic 3** ONNX assets from Hugging Face, fully local after first setup.

## Important model fidelity

The Ollama `gemma3:1b` model blob does not carry Ollama's separate template/parameter layers. The official Ollama page currently identifies the model layer as `7cd4618c1faf`; the installer refuses a silently retagged layer. This app intentionally uses raw-prompt generation and reproduces the Ollama template in `lib/core/ollama_prompt_renderer.dart`.

Sampling is also pinned to Ollama's model parameters:

- `temperature = 1.0`
- `top_k = 64`
- `top_p = 0.95`
- stop marker: `<end_of_turn>`

The original model supports a 32,768-token context. The mobile runtime defaults to **4,096** in `ModelConstants.contextSize` to reduce RAM and latency. Increase it on high-memory devices if needed; this does not change the model weights.

## First-run storage

Expect roughly **1.25 GB+** before caches/runtime overhead:

- Gemma 3 1B GGUF: ~815 MB
- Supertonic 3: ~400–415 MB
- default Sherpa streaming ASR model: ~30 MB

The first setup requires Internet only to fetch model assets. Chat inference, STT, and TTS are local afterward.

## Bootstrap Android + iOS host projects

This source bundle deliberately does not fake generated Flutter host files. On a machine with Flutter **3.35+** / Dart **3.9+**:

```bash
cd gemma_voice_assistant
./scripts/bootstrap_platforms.sh
```

The script:

1. Generates current Flutter Android/iOS host files without overwriting this app's Dart code.
2. Sets Android min SDK 26 and NDK r27 for the Android llama.cpp plugin.
3. Adds microphone/network permissions and ONNX/llama ProGuard rules.
4. Sets iOS deployment target 16.4, static frameworks, and microphone permission configuration.
5. Runs `flutter pub get`, formatting, `flutter analyze`, and `flutter test`.

Then run:

```bash
flutter run
```

Release examples:

```bash
flutter build apk --release
flutter build ipa --release
```

## App flow

```text
Microphone
  -> Sherpa-ONNX streaming STT
  -> final/current transcript
  -> exact Ollama Gemma 3 prompt renderer
  -> llama.cpp local inference
  -> streaming tokens rendered in chat
  -> Supertonic 3 ONNX synthesis
  -> speaker
```

The app explicitly stops TTS before opening the microphone, reducing self-listening/feedback in turn-based voice use.

## Supertonic expression tags

Supertonic 3 supports simple inline expression tags such as `<laugh>`, `<breath>`, and `<sigh>`. If Gemma emits or your app inserts supported tags, they can be passed directly into the TTS text path.

## STT language note

`sherpa_asr_sdk`'s packaged streaming bilingual model is documented as Chinese-English. The service boundary in `offline_stt_service.dart` is intentionally isolated so you can replace it with another sherpa-onnx streaming model/package for multilingual production coverage without changing the chat/LLM/TTS layers.

## Licenses

Review and comply with each dependency/model license before distribution. In particular, the Gemma weights are governed by the Gemma Terms of Use, and Supertonic 3 publishes its own model license. This repository does **not** bundle either model's weights.

## Validation status

The source bundle includes unit tests for the exact Ollama prompt framing and a deterministic platform-bootstrap script. The environment in which this bundle was generated did not contain Flutter/Dart/Xcode, so an APK/IPA build was **not** claimed as verified here. Run `./scripts/bootstrap_platforms.sh` on the target Flutter build machine to perform analyzer + unit-test verification before release.
