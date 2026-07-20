import 'package:flutter/services.dart';

import '../../application/update/external_url_launcher.dart';

/// Opens trusted release links through UIApplication on the iOS host.
final class IosExternalUrlLauncher implements ExternalUrlLauncher {
  const IosExternalUrlLauncher({
    this.channel = const MethodChannel(_channelName),
  });

  static const channelName = 'com.privi.app/url_launcher';

  static const _channelName = channelName;

  final MethodChannel channel;

  @override
  Future<void> open(Uri uri) async {
    final opened = await channel.invokeMethod<bool>('openUrl', {
      'url': uri.toString(),
    });
    if (opened != true) {
      throw StateError('iOS did not open the requested URL');
    }
  }
}
