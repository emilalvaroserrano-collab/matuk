class ModelConstants {
  ModelConstants._();

  static const ollamaModel = 'gemma3';
  static const ollamaTag = '1b';
  static const manifestUri =
      'https://registry.ollama.ai/v2/library/gemma3/manifests/1b';
  static const blobBaseUri =
      'https://registry.ollama.ai/v2/library/gemma3/blobs';
  static const modelMediaType = 'application/vnd.ollama.image.model';

  // Current official Ollama model-layer ID shown for gemma3:1b. Refuse a
  // silently retagged model rather than changing weights behind the user's back.
  static const modelDigestPrefix = '7cd4618c1faf';

  // Ollama gemma3:1b parameters.
  static const stopSequence = '<end_of_turn>';
  static const temperature = 1.0;
  static const topK = 64;
  static const topP = 0.95;

  // Model supports 32,768 tokens. 4096 is deliberately conservative for
  // mobile memory/latency; raise toward 32768 on high-RAM devices.
  static const contextSize = 4096;
  static const maxOutputTokens = 512;
}
