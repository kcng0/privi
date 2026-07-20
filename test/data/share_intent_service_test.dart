import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/platform/share_source_stager.dart';
import 'package:privi/data/services/import/import_models.dart';
import 'package:privi/data/services/share_intent_service.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

final class _FakeShareSourceStager implements ShareSourceStager {
  _FakeShareSourceStager({this.recovered = const [], this.stageError});

  final List<ImportSource> recovered;
  final Object? stageError;
  final List<String> events = [];
  List<ImportSource>? received;

  @override
  Future<List<ImportSource>> recoverPending() async {
    events.add('recover');
    return recovered;
  }

  @override
  Future<List<ImportSource>> stage(List<ImportSource> sources) async {
    events.add('stage');
    received = sources;
    if (stageError case final error?) throw error;
    return [
      for (final source in sources)
        ImportSource(
          path: '/durable/${source.name}',
          name: source.name,
          mimeType: source.mimeType,
          deleteAfterImport: true,
        ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ReceiveSharingIntent.setMockValues(
      initialMedia: const [],
      mediaStream: const Stream.empty(),
    );
  });

  test('merges recovered and initial sources before resetting', () async {
    final stager = _FakeShareSourceStager(
      recovered: const [
        ImportSource(
          path: '/durable/recovered.jpg',
          name: 'recovered.jpg',
          deleteAfterImport: true,
        ),
      ],
    );
    ReceiveSharingIntent.setMockValues(
      initialMedia: [
        SharedMediaFile(
          path: '/app-group/incoming.mov',
          thumbnail: '/app-group/incoming.png',
          mimeType: 'video/quicktime',
          type: SharedMediaType.video,
        ),
      ],
      mediaStream: const Stream.empty(),
    );
    final service = ShareIntentService(stager: stager);
    addTearDown(service.dispose);
    final delivered = <List<ImportSource>>[];

    await service.start((sources) async {
      stager.events.add('deliver');
      delivered.add(sources);
    });

    expect(stager.events, ['recover', 'stage', 'deliver']);
    expect(delivered, hasLength(1));
    expect(
      delivered.single.map((source) => source.path),
      ['/durable/recovered.jpg', '/durable/incoming.mov'],
    );
    expect(
      stager.received?.single.temporaryThumbnailPath,
      '/app-group/incoming.png',
    );
    expect(await ReceiveSharingIntent.instance.getInitialMedia(), isEmpty);
  });

  test('staging failure leaves the plugin event available for retry', () async {
    final stager = _FakeShareSourceStager(
      stageError: StateError('staging unavailable'),
    );
    ReceiveSharingIntent.setMockValues(
      initialMedia: [
        SharedMediaFile(
          path: '/app-group/incoming.jpg',
          type: SharedMediaType.image,
        ),
      ],
      mediaStream: const Stream.empty(),
    );
    final service = ShareIntentService(stager: stager);

    await expectLater(
      service.start((_) {}),
      throwsA(isA<StateError>()),
    );

    expect(await ReceiveSharingIntent.instance.getInitialMedia(), hasLength(1));
  });

  test('callback failure leaves the plugin event available for retry',
      () async {
    final stager = _FakeShareSourceStager();
    ReceiveSharingIntent.setMockValues(
      initialMedia: [
        SharedMediaFile(
          path: '/app-group/incoming.jpg',
          type: SharedMediaType.image,
        ),
      ],
      mediaStream: const Stream.empty(),
    );
    final service = ShareIntentService(stager: stager);

    await expectLater(
      service.start((_) => throw StateError('delivery unavailable')),
      throwsA(isA<StateError>()),
    );

    expect(await ReceiveSharingIntent.instance.getInitialMedia(), hasLength(1));
  });
}
