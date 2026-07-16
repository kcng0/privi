import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

/// External player / gallery hand-off via Android native ACTION_VIEW.
///
/// Uses a platform channel that starts a normal VIEW intent (not
/// [Intent.createChooser]) so the system can show **Just once** / **Always**
/// when no preferred app is set.
class IntentService {
  static const _channel = MethodChannel('com.privateheart.vault/files');

  /// Open a local media file via the Android app chooser (or fallbacks).
  Future<bool> openExternal({
    required String filePath,
    required String mimeType,
    String chooserTitle = 'Open with',
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return false;

    // Preferred: native ACTION_VIEW (system resolver with Just once / Always).
    try {
      final ok = await _channel.invokeMethod<bool>(
        'openWithChooser',
        {
          'path': filePath,
          'mimeType': mimeType,
          'title': chooserTitle,
        },
      );
      if (ok == true) return true;
    } catch (e) {
      debugPrint('openWithChooser: $e');
    }

    // Fallback: FileProvider URI + plugin launchChooser.
    String? contentUri;
    try {
      contentUri = await _channel.invokeMethod<String>(
        'contentUriForPath',
        {'path': filePath},
      );
    } catch (e) {
      debugPrint('contentUri: $e');
    }

    final data = contentUri ?? filePath;
    final isContent = data.startsWith('content:');
    final flags = isContent
        ? <int>[
            Flag.FLAG_GRANT_READ_URI_PERMISSION,
            Flag.FLAG_ACTIVITY_NEW_TASK,
          ]
        : <int>[Flag.FLAG_ACTIVITY_NEW_TASK];

    // Fallback: direct VIEW (system may show Just once / Always).
    try {
      final intent = AndroidIntent(
        action: 'action_view',
        data: data,
        type: mimeType,
        flags: flags,
      );
      await intent.launch();
      return true;
    } catch (e) {
      debugPrint('ACTION_VIEW failed: $e');
    }

    final result = await OpenFilex.open(filePath, type: mimeType);
    return result.type == ResultType.done;
  }
}
