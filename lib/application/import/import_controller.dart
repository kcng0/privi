import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/services/import_service.dart';
import '../providers.dart';

class ImportUiState {
  const ImportUiState({
    this.running = false,
    this.progress,
    this.lastSummary,
  });

  final bool running;
  final ImportProgress? progress;
  final ImportProgress? lastSummary;

  ImportUiState copyWith({
    bool? running,
    ImportProgress? progress,
    ImportProgress? lastSummary,
  }) {
    return ImportUiState(
      running: running ?? this.running,
      progress: progress ?? this.progress,
      lastSummary: lastSummary ?? this.lastSummary,
    );
  }
}

class ImportController extends Notifier<ImportUiState> {
  @override
  ImportUiState build() => const ImportUiState();

  Future<ImportProgress?> pickAndImport({String? targetUserAlbumId}) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'heic',
        'heif',
        'mp4',
        'mov',
        'mkv',
        'webm',
        '3gp',
      ],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final sources = <ImportSource>[];
    for (final f in result.files) {
      final path = f.path;
      if (path == null) continue;
      final parent = p.basename(p.dirname(path));
      sources.add(
        ImportSource(
          path: path,
          name: f.name,
          sourceFolderName: parent.isEmpty ? 'Imported' : parent,
        ),
      );
    }
    if (sources.isEmpty) return null;
    return runImport(sources, targetUserAlbumId: targetUserAlbumId);
  }

  Future<ImportProgress> runImport(
    List<ImportSource> sources, {
    String? targetUserAlbumId,
    String? sourceFolderName,
  }) async {
    final service = ref.read(importServiceProvider);
    state = const ImportUiState(running: true);
    final summary = await service.importAll(
      sources,
      targetUserAlbumId: targetUserAlbumId,
      defaultSourceFolderName: sourceFolderName,
      onProgress: (p) {
        if (ref.mounted) {
          state = ImportUiState(running: true, progress: p);
        }
      },
    );
    if (ref.mounted) {
      state = ImportUiState(
        running: false,
        progress: summary,
        lastSummary: summary,
      );
    }
    return summary;
  }

  void cancel() {
    ref.read(importServiceProvider).cancel();
  }

  void clearSummary() {
    state = const ImportUiState();
  }
}

final importControllerProvider =
    NotifierProvider<ImportController, ImportUiState>(ImportController.new);
