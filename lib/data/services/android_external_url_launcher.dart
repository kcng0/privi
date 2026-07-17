import 'package:android_intent_plus/android_intent.dart';

import '../../application/update/external_url_launcher.dart';

final class AndroidExternalUrlLauncher implements ExternalUrlLauncher {
  const AndroidExternalUrlLauncher();

  @override
  Future<void> open(Uri uri) {
    return AndroidIntent(action: 'action_view', data: uri.toString()).launch();
  }
}
