import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/services/import/file_system_gateway.dart';
import 'package:privi/data/services/import/hide_preparer.dart';
import 'package:privi/data/services/import/import_models.dart';
import 'package:privi/data/services/import/vault_transfer_runner.dart';
import 'package:privi/data/services/media_rename_service.dart';

class _MemoryFileSystem implements FileSystemGateway {
  final Map<String, Uint8List> files = {};

  void put(String path, int length) {
    files[path] = Uint8List(length);
  }

  @override
  Future<bool> exists(String path) async => files.containsKey(path);

  @override
  Future<int> length(String path) async => files[path]!.length;

  @override
  Future<void> delete(String path) async => files.remove(path);

  @override
  Future<String> rename(String sourcePath, String destinationPath) async {
    files[destinationPath] = files.remove(sourcePath)!;
    return destinationPath;
  }

  @override
  Future<String> copy(String sourcePath, String destinationPath) async {
    files[destinationPath] = Uint8List.fromList(files[sourcePath]!);
    return destinationPath;
  }

  @override
  Future<void> createDirectory(String path) async {}

  @override
  Future<Uint8List> readBytes(String path) async => files[path]!;

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    files[path] = Uint8List.fromList(bytes);
  }
}

class _FakeRenamer extends MediaRenameService {
  Future<List<MediaRenameResult>> Function(List<MediaHideRequest>)? batch;
  Future<MediaRenameResult> Function({
    required String path,
    required String newPath,
    required bool isVideo,
  })? single;

  var singleCalls = 0;

  @override
  Future<List<MediaRenameResult>> hideToVaultBatch(
    List<MediaHideRequest> items,
  ) {
    final handler = batch;
    if (handler != null) return handler(items);
    return Future.value([
      for (final item in items)
        MediaRenameResult(
          ok: true,
          newPath: item.newPath,
          size: 10,
          clientId: item.clientId,
        ),
    ]);
  }

  @override
  Future<MediaRenameResult> hideToVault({
    String? path,
    String? mediaId,
    required String newPath,
    required bool isVideo,
  }) {
    singleCalls++;
    final handler = single;
    if (handler != null) {
      return handler(path: path!, newPath: newPath, isVideo: isVideo);
    }
    return Future.value(
      MediaRenameResult(ok: true, newPath: newPath, size: 10),
    );
  }
}

PreparedHide _job(int index) {
  return PreparedHide(
    id: 'job-$index',
    source: ImportSource(path: '/source/$index.jpg'),
    originalPath: '/source/$index.jpg',
    originalName: '$index.jpg',
    mimeType: 'image/jpeg',
    isVideo: false,
    destinationPath: '/vault/$index.jpg',
    folderName: 'Camera',
    albumId: 'album-camera',
  );
}

void main() {
  group('VaultTransferRunner recovery ladder', () {
    late _MemoryFileSystem files;
    late _FakeRenamer renamer;
    late VaultTransferRunner runner;

    setUp(() {
      files = _MemoryFileSystem();
      renamer = _FakeRenamer();
      runner = VaultTransferRunner(renamer: renamer, fileSystem: files);
    });

    test('batch success preserves result order and sizes', () async {
      final outcomes = await runner.run(
        [_job(0), _job(1)],
        session: ImportSession(),
      );

      expect(outcomes.map((outcome) => outcome.ok), everyElement(isTrue));
      expect(outcomes.map((outcome) => outcome.sizeBytes), [10, 10]);
      expect(renamer.singleCalls, 0);
    });

    test('short batch response backfills missing indexes per item', () async {
      renamer.batch = (items) async => [
            MediaRenameResult(
              ok: true,
              newPath: items.first.newPath,
              size: 11,
              clientId: items.first.clientId,
            ),
          ];

      final outcomes = await runner.run(
        [_job(0), _job(1)],
        session: ImportSession(),
      );

      expect(outcomes.map((outcome) => outcome.sizeBytes), [11, 10]);
      expect(renamer.singleCalls, 1);
    });

    test('batch failure recovers a destination already written', () async {
      files.put('/vault/0.jpg', 24);
      renamer.batch = (_) => throw TimeoutException('batch');

      final outcomes = await runner.run([_job(0)], session: ImportSession());

      expect(outcomes.single.ok, isTrue);
      expect(outcomes.single.sizeBytes, 24);
      expect(renamer.singleCalls, 0);
    });

    test('per-item timeout performs a second destination recovery', () async {
      renamer.batch = (_) async => const [];
      renamer.single = ({required path, required newPath, required isVideo}) {
        files.put(newPath, 31);
        throw TimeoutException('single');
      };

      final outcomes = await runner.run([_job(0)], session: ImportSession());

      expect(outcomes.single.ok, isTrue);
      expect(outcomes.single.sizeBytes, 31);
    });

    test('failed item does not affect successful siblings', () async {
      renamer.batch = (_) async => const [];
      renamer.single = ({required path, required newPath, required isVideo}) {
        if (newPath.endsWith('0.jpg')) {
          return Future.value(
            const MediaRenameResult(ok: false, error: 'native_failed'),
          );
        }
        return Future.value(
          MediaRenameResult(ok: true, newPath: newPath, size: 12),
        );
      };

      final outcomes = await runner.run(
        [_job(0), _job(1)],
        session: ImportSession(),
      );

      expect(outcomes.first.ok, isFalse);
      expect(outcomes.first.errorCode, ImportErrorCode.transferFailed);
      expect(outcomes.last.ok, isTrue);
    });

    test('zero native size is recovered from destination bytes', () async {
      files.put('/vault/0.jpg', 19);
      renamer.batch = (items) async => [
            MediaRenameResult(
              ok: true,
              newPath: items.single.newPath,
              size: 0,
              clientId: items.single.clientId,
            ),
          ];

      final outcomes = await runner.run([_job(0)], session: ImportSession());

      expect(outcomes.single.ok, isTrue);
      expect(outcomes.single.sizeBytes, 19);
    });

    test('empty destination is a visible failure', () async {
      files.put('/vault/0.jpg', 0);
      renamer.batch = (items) async => [
            MediaRenameResult(
              ok: true,
              newPath: items.single.newPath,
              size: 0,
              clientId: items.single.clientId,
            ),
          ];

      final outcomes = await runner.run([_job(0)], session: ImportSession());

      expect(outcomes.single.ok, isFalse);
      expect(outcomes.single.errorCode, ImportErrorCode.emptyDest);
    });

    test('cancel between chunks leaves the remainder untouched', () async {
      final session = ImportSession();
      var chunks = 0;

      final outcomes = await runner.run(
        List.generate(10, _job),
        session: session,
        onChunk: (_) async {
          chunks++;
          session.cancel();
        },
      );

      expect(chunks, 1);
      expect(outcomes, hasLength(VaultTransferRunner.nativeBatchChunk));
    });
  });

  test('mime sniffing handles supported image and video extensions', () {
    const cases = {
      'photo.JPG': 'image/jpeg',
      'still.heic': 'image/heic',
      'clip.mov': 'video/quicktime',
      'movie.mkv': 'video/x-matroska',
      'unknown.bin': null,
    };
    for (final entry in cases.entries) {
      expect(
        HidePreparer.sniffMime(null, entry.key, '/tmp/${entry.key}'),
        entry.value,
        reason: entry.key,
      );
    }
  });
}
