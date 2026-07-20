import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:privi/data/services/import/import_models.dart';
import 'package:privi/data/services/platform/ios_share_source_stager.dart';
import 'package:privi/data/services/vault_storage_service.dart';

final class _StagingStorage extends VaultStorageService {
  _StagingStorage(this.root) : super(initializeSharedRoot: false);

  final Directory root;

  @override
  Future<Directory> get shareStagingDir async {
    final directory = Directory(p.join(root.path, 'share_staging'));
    await directory.create(recursive: true);
    return directory;
  }
}

void main() {
  late Directory temp;
  late _StagingStorage storage;
  late IosShareSourceStager stager;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('privi-share-stager-');
    storage = _StagingStorage(temp);
    stager = IosShareSourceStager(storage: storage);
  });

  tearDown(() => temp.delete(recursive: true));

  test('copies attachments into digest-addressed durable staging', () async {
    final expectedBytes = List<int>.generate(32, (index) => index);
    final incoming = File(p.join(temp.path, 'incoming.mov'))
      ..writeAsBytesSync(expectedBytes);
    final thumbnail = File(p.join(temp.path, 'incoming-thumb.png'))
      ..writeAsBytesSync([1, 2, 3]);

    final staged = await stager.stage([
      ImportSource(
        path: incoming.path,
        name: 'holiday.mov',
        mimeType: 'video/quicktime',
        temporaryThumbnailPath: thumbnail.path,
      ),
    ]);

    expect(staged, hasLength(1));
    expect(staged.single.deleteAfterImport, isTrue);
    expect(staged.single.mimeType, 'video/quicktime');
    expect(await File(staged.single.path).readAsBytes(), expectedBytes);
    expect(await incoming.exists(), isFalse);
    expect(await thumbnail.exists(), isFalse);

    final recovered = await stager.recoverPending();
    expect(recovered.map((source) => source.path), [staged.single.path]);
  });

  test('recovery rejects incomplete staging entries', () async {
    final root = await storage.shareStagingDir;
    await Directory(p.join(root.path, 'broken')).create();

    await expectLater(
      stager.recoverPending(),
      throwsA(isA<StateError>()),
    );
  });

  test('recovery rejects content that no longer matches its digest', () async {
    final incoming = File(p.join(temp.path, 'incoming.jpg'))
      ..writeAsBytesSync([1, 2, 3, 4]);
    final staged = (await stager.stage([
      ImportSource(path: incoming.path, name: 'incoming.jpg'),
    ]))
        .single;
    await File(staged.path).writeAsBytes([9, 8, 7, 6], flush: true);

    await expectLater(
      stager.recoverPending(),
      throwsA(isA<StateError>()),
    );
  });

  test('receipt recovers a staged attachment after provider cleanup', () async {
    final incoming = File(p.join(temp.path, 'retry.jpg'))
      ..writeAsBytesSync([4, 3, 2, 1]);
    final source = ImportSource(path: incoming.path, name: 'retry.jpg');

    final first = (await stager.stage([source])).single;
    expect(await incoming.exists(), isFalse);

    final retry = (await stager.stage([source])).single;
    expect(retry.path, first.path);
    expect(await File(retry.path).readAsBytes(), [4, 3, 2, 1]);

    final entry = File(retry.path).parent;
    await storage.deleteShareStagedSource(retry.path);
    expect(await entry.exists(), isFalse);
  });

  test('staging an already durable source does not consume itself', () async {
    final incoming = File(p.join(temp.path, 'durable-retry.jpg'))
      ..writeAsBytesSync([8, 6, 7, 5]);
    final first = (await stager.stage([
      ImportSource(path: incoming.path, name: 'durable-retry.jpg'),
    ]))
        .single;

    final retry = (await stager.stage([first])).single;

    expect(retry.path, first.path);
    expect(await File(retry.path).readAsBytes(), [8, 6, 7, 5]);
    expect(await stager.recoverPending(), hasLength(1));
  });

  test('later attachment failure does not consume earlier inputs', () async {
    final first = File(p.join(temp.path, 'first.jpg'))
      ..writeAsBytesSync([1, 2, 3]);
    final missing = File(p.join(temp.path, 'missing.jpg'));

    await expectLater(
      stager.stage([
        ImportSource(path: first.path, name: 'first.jpg'),
        ImportSource(path: missing.path, name: 'missing.jpg'),
      ]),
      throwsA(isA<FileSystemException>()),
    );

    expect(await first.exists(), isTrue);
    expect(await stager.recoverPending(), hasLength(1));
  });
}
