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
  static const contextSize = 4096;
  static const maxOutputTokens = 512;
}
