# Translator Mode validation status

## Source-level checks

- Translator Mode is a separate Flutter project under the Matuk repository root.
- **Eb Translator** now uses `HuggingFaceTB/SmolLM2-360M-Instruct` through Hugging Face's official `HuggingFaceTB/SmolLM2-360M-Instruct-GGUF` Q8_0 conversion.
- The GGUF download is pinned to SHA-256 `48ab3034d0dd401fbc721eb1df3217902fee7dab9078992d66431f09b7750201` before it is accepted.
- Android and iOS Eb Translator inference continue to use llama.cpp.
- SmolLM2's official ChatML turn tokens are used and generation stops on `<|im_end|>`.
- **Speech Recognition** remains the local Sherpa streaming STT layer.
- **Speech Synthesys** remains Supertonic 3, run through the shared sherpa-onnx native runtime.
- Heavy engines load lazily and are released between STT, translation, and TTS stages to lower peak mobile RAM.
- Translation is two-way: side A can translate to side B, and side B can translate to side A.
- Translation output streams token-by-token into the opposite language panel before optional Speech Synthesys read-aloud.
- The Eb Translator prompt explicitly forbids answering/explaining and requests translation-only output.

## Build verification

GitHub Actions generates the Android host, runs formatting/analyzer/tests, builds a release APK, verifies the packaged native ONNX runtime, and publishes the versioned APK under GitHub Releases.

The selected SmolLM2-360M-Instruct model card is labeled English, so multilingual translation quality must still be device-tested for all production language pairs.
