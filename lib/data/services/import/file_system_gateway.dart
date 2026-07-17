import 'dart:io';
import 'dart:typed_data';

abstract class FileSystemGateway {
  Future<bool> exists(String path);

  Future<int> length(String path);

  Future<void> delete(String path);

  Future<String> rename(String sourcePath, String destinationPath);

  Future<String> copy(String sourcePath, String destinationPath);

  Future<void> createDirectory(String path);

  Future<Uint8List> readBytes(String path);

  Future<void> writeBytes(String path, List<int> bytes);
}

class IoFileSystemGateway implements FileSystemGateway {
  const IoFileSystemGateway();

  @override
  Future<bool> exists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  @override
  Future<int> length(String path) => File(path).length();

  @override
  Future<void> delete(String path) => File(path).delete();

  @override
  Future<String> rename(String sourcePath, String destinationPath) async {
    final result = await File(sourcePath).rename(destinationPath);
    return result.path;
  }

  @override
  Future<String> copy(String sourcePath, String destinationPath) async {
    final result = await File(sourcePath).copy(destinationPath);
    return result.path;
  }

  @override
  Future<void> createDirectory(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      File(path).writeAsBytes(bytes, flush: true);
}
