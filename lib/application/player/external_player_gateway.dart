/// Outcome reported when an external media activity returns to Privi.
enum ExternalPlayerReturn {
  /// The player supplied position/duration values showing the item reached
  /// the end of playback.
  completed,

  /// The activity returned before a confirmed natural completion (including
  /// Back, Home/app switching, or a player without completion metadata).
  interrupted,
}

abstract interface class ExternalPlayerGateway {
  bool get supported;

  Future<bool> open({
    required String filePath,
    required String mimeType,
  });

  /// Consumes the one-shot result emitted when Android receives an activity
  /// result from the external player.
  ExternalPlayerReturn? takeReturn();
}
