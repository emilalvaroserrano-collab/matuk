class ModelConstants {
  ModelConstants._();

  // User-facing alias: Eb Translator.
  // Source model: HuggingFaceTB/SmolLM2-360M-Instruct.
  // llama.cpp consumes Hugging Face's official GGUF conversion of the same model.
  static const modelRepository =
      'HuggingFaceTB/SmolLM2-360M-Instruct-GGUF';
  static const modelFile = 'smollm2-360m-instruct-q8_0.gguf';
  static const modelUri =
      'https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf?download=true';
  static const modelSha256 =
      '48ab3034d0dd401fbc721eb1df3217902fee7dab9078992d66431f09b7750201';

  static const stopSequence = '<|im_end|>';
  static const temperature = 0.2;
  static const topK = 40;
  static const topP = 0.9;

  // Translation turns are short. Keeping a 2K context lowers mobile KV-cache
  // RAM while remaining well inside SmolLM2's supported context window.
  static const contextSize = 2048;
  static const maxOutputTokens = 384;
}
