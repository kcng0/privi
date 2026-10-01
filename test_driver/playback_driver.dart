import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory('build/playback-validation');
  await output.create(recursive: true);
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      final metrics = {...?data}..remove('screenshots');
      final frames = metrics.remove('decoded_frames') as Map<String, dynamic>?;
      for (final entry in (frames ?? <String, dynamic>{}).entries) {
        await File('${output.path}/decoded-${entry.key}.png')
            .writeAsBytes(base64Decode(entry.value as String));
      }
      await File('${output.path}/metrics.json')
          .writeAsString(jsonEncode(metrics));
    },
  );
}
