import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/services/import_service.dart';
import '../gallery/gallery_controller.dart';
import '../providers.dart';

class ImportUiState {
  const ImportUiState({
    this.running = false,
    this.progress,
    this.lastSummary,
    this.cancelling = false,
  });

  final bool running;
  final ImportProgress? progress;
  final ImportProgress? lastSummary;

  /// True after the user taps Cancel while a hide is still finishing a chunk.
  final bool cancelling;

  ImportUiState copyWith({
    bool? running,
    ImportProgress? progress,
    ImportProgress? lastSummary,
    bool? cancelling,
    bool clearProgress = false,
    bool clearSummary = false,
  }) {
    return ImportUiState(
      running: running ?? this.running,
      progress: clearProgress ? null : (progress ?? this.progress),
      lastSummary: clearSummary ? null : (lastSummary ?? this.lastSummary),
      cancelling: cancelling ?? this.cancelling,
    );
  }
}

class ImportController extends Notifier<ImportUiState> {
  /// Cooperative cancel for the current hide session (resolve + import).
  bool _sessionCancel = false;

  @override
  ImportUiState build() => const ImportUiState();

  /// Start a hide session before path resolve so Cancel works immediately.
  ///
  /// Call this when the progress sheet is shown — not only when native work
  /// starts. Resets any previous cancel flag.
  void beginSession() {
    _sessionCancel = false;
    ref.read(importServiceProvider).resetCancel();
    state = const ImportUiState(
      running: true,
      progress: ImportProgress(
        done: 0,
        total: 0,
        statusMessage: 'Hiding…',
      ),
    );
  }

  bool get isCancelRequested => _sessionCancel;

  Future<ImportProgress?> pickAndImport({String? targetUserAlbumId}) async {
    beginSession();
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
    if (_sessionCancel) {
      return _finishCancelled();
    }
    if (result == null || result.files.isEmpty) {
      _endSession(summary: null);
      return null;
    }

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
    if (sources.isEmpty) {
      _endSession(summary: null);
      return null;
    }
    return runImport(
      sources,
      targetUserAlbumId: targetUserAlbumId,
      sessionAlreadyStarted: true,
    );
  }

  /// Run hide for [sources]. Prefer [beginSession] first when a progress sheet
  /// is already visible (so Cancel works during path resolve).
  Future<ImportProgress> runImport(
    List<ImportSource> sources, {
    String? targetUserAlbumId,
    String? sourceFolderName,
    bool sessionAlreadyStarted = false,
  }) async {
    if (!sessionAlreadyStarted) {
      beginSession();
    } else if (!state.running) {
      // Sheet path called beginSession; keep running=true.
      state = state.copyWith(running: true);
    }

    if (_sessionCancel) {
      return _finishCancelled(total: sources.length);
    }

    final service = ref.read(importServiceProvider);
    // Do not clear a cancel that arrived between beginSession and here.
    if (!_sessionCancel) {
      service.resetCancel();
    }

    ImportProgress summary;
    try {
      summary = await service.importAll(
        sources,
        targetUserAlbumId: targetUserAlbumId,
        defaultSourceFolderName: sourceFolderName,
        isCancelRequested: () => _sessionCancel,
        onProgress: (p) {
          if (!ref.mounted) return;
          state = ImportUiState(
            running: true,
            progress: p,
            cancelling: _sessionCancel || p.cancelled,
            lastSummary: state.lastSummary,
          );
        },
      );
    } catch (e) {
      // Never leave running=true — UI would stick on the progress sheet.
      summary = ImportProgress(
        done: 0,
        total: sources.length,
        failed: sources.length,
        statusMessage: 'Done',
        lastError: e.toString(),
      );
    }

    // Partial success still invalidates gallery so Visible counts recover.
    if (summary.imported > 0 && ref.mounted) {
      final gallery = ref.read(galleryServiceProvider);
      gallery.invalidateVaultPathCache();
      gallery.refreshAfterMutation();
      ref.read(galleryUiEpochProvider.notifier).bump();
      ref.invalidate(galleryFoldersProvider);
      ref.invalidate(albumsProvider);
    }

    _endSession(summary: summary);
    return summary;
  }

  /// Request cancel. Safe to call anytime during a session (resolve or hide).
  void cancel() {
    _sessionCancel = true;
    ref.read(importServiceProvider).cancel();
    if (ref.mounted && state.running) {
      state = state.copyWith(
        cancelling: true,
        progress: state.progress == null
            ? const ImportProgress(
                done: 0,
                total: 0,
                statusMessage: 'Cancelled',
                cancelled: true,
              )
            : ImportProgress(
                done: state.progress!.done,
                total: state.progress!.total,
                currentName: state.progress!.currentName,
                imported: state.progress!.imported,
                skipped: state.progress!.skipped,
                failed: state.progress!.failed,
                cancelled: true,
                statusMessage: 'Cancelled',
                lastError: state.progress!.lastError,
              ),
      );
    }
  }

  void clearSummary() {
    if (!ref.mounted) return;
    state = const ImportUiState();
    _sessionCancel = false;
    ref.read(importServiceProvider).resetCancel();
  }

  ImportProgress _finishCancelled({int total = 0}) {
    final summary = ImportProgress(
      done: 0,
      total: total,
      cancelled: true,
      statusMessage: 'Cancelled',
    );
    _endSession(summary: summary);
    return summary;
  }

  void _endSession({required ImportProgress? summary}) {
    if (!ref.mounted) return;
    state = ImportUiState(
      running: false,
      progress: summary,
      lastSummary: summary,
      cancelling: false,
    );
    _sessionCancel = false;
  }
}

final importControllerProvider =
    NotifierProvider<ImportController, ImportUiState>(ImportController.new);
