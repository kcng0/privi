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
      final evidence = File('${output.path}/device-evidence.json');
      if (!await evidence.exists()) {
        throw StateError('Missing real Android input/screenshot evidence');
      }
      final actions =
          jsonDecode(await evidence.readAsString()) as Map<String, dynamic>;
      metrics['native_device_evidence'] = actions;
      await File('${output.path}/metrics.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(metrics));
      if (actions.isEmpty ||
          actions.values
              .any((value) => (value as Map<String, dynamic>)['ok'] != true)) {
        throw StateError(
          'Real Android evidence contains missing/failed actions',
        );
      }
    },
  );
}
