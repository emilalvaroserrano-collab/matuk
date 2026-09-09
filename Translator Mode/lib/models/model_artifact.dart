class ModelArtifact {
  const ModelArtifact({
    required this.path,
    required this.digest,
    required this.size,
    required this.sourceUri,
  });

  final String path;
  final String digest;
  final int size;
  final Uri sourceUri;
}
