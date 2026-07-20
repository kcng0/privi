import '../../../application/player/external_player_gateway.dart';

/// iOS deliberately keeps playback in the app until a privacy-preserving
/// hand-off protocol is designed and verified.
final class UnsupportedExternalPlayerGateway implements ExternalPlayerGateway {
  const UnsupportedExternalPlayerGateway();

  @override
  bool get supported => false;

  @override
  Future<bool> open({
    required String filePath,
    required String mimeType,
  }) async {
    return false;
  }

  @override
  ExternalPlayerReturn? takeReturn() => null;
}
