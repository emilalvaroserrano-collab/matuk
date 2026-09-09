class ModelConstants {
  ModelConstants._();

  static const ollamaModel = 'gemma3';
  static const ollamaTag = '1b';
  static const manifestUri =
      'https://registry.ollama.ai/v2/library/gemma3/manifests/1b';
  static const blobBaseUri =
      'https://registry.ollama.ai/v2/library/gemma3/blobs';
  static const modelMediaType = 'application/vnd.ollama.image.model';
  static const modelDigestPrefix = '7cd4618c1faf';

  static const stopSequence = '<end_of_turn>';
  static const temperature = 1.0;
  static const topK = 64;
  static const topP = 0.95;

  // Translation turns are short, so a 2K context materially lowers mobile KV
  // cache RAM without changing the exact Ollama gemma3:1b model weights.
  static const contextSize = 2048;
  static const maxOutputTokens = 384;
}
