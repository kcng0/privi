abstract interface class ExternalPlayerGateway {
  Future<bool> open({
    required String filePath,
    required String mimeType,
  });

  /// Consumes the one-shot signal emitted when Android receives an activity
  /// result from the external player.
  bool takeCleanReturn();
}
