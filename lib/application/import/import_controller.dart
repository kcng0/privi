import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/services/import_service.dart';
import '../../domain/enums.dart';
import '../../domain/models/media_item.dart';
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

class AlbumRestoreResult {
  const AlbumRestoreResult({required this.summary, required this.wasEmpty});

  final ImportProgress summary;
  final bool wasEmpty;
}

class ImportController extends Notifier<ImportUiState> {
  ImportSession? _session;

  @override
  ImportUiState build() => const ImportUiState();

  /// Start a progress session before work so Cancel works immediately.
  ///
  /// Call this when the progress sheet is shown — not only when native work
  /// starts. Resets any previous cancel flag.
  void beginSession({ImportPhase phase = ImportPhase.resolving}) {
    _session = ImportSession();
    state = ImportUiState(
      running: true,
      progress: ImportProgress(
        done: 0,
        total: 0,
        phase: phase,
      ),
    );
  }

  bool get isCancelRequested => _session?.isCancelled ?? false;

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
    if (isCancelRequested) {
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
      state = state.copyWith(running: true);
    }

    if (isCancelRequested) {
      return _finishCancelled(total: sources.length);
    }

    final service = ref.read(importServiceProvider);
    final session = _session ??= ImportSession();

    ImportProgress summary;
    try {
      summary = await service.importAll(
        sources,
        targetUserAlbumId: targetUserAlbumId,
        defaultSourceFolderName: sourceFolderName,
        session: session,
        onProgress: (p) {
          if (!ref.mounted) return;
          state = ImportUiState(
            running: true,
            progress: p,
            cancelling: session.isCancelled || p.cancelled,
            lastSummary: state.lastSummary,
          );
        },
      );
    } catch (e) {
      summary = ImportProgress(
        done: 0,
        total: sources.length,
        phase: ImportPhase.done,
        failed: sources.length,
        lastError: e.toString(),
        errorCode: ImportErrorCode.transferFailed,
      );
    }

    if (summary.imported > 0 && ref.mounted) {
      final gallery = ref.read(galleryServiceProvider);
      gallery.apply(
        VisibleHidden(
          pathId: '',
          hiddenCount: summary.imported,
          assetIds: [
            for (final source in sources)
              if (source.assetId case final id?) id,
          ],
          originalPaths: sources.map((source) => source.path).toList(),
        ),
      );
      ref.invalidate(galleryFoldersProvider);
      ref.invalidate(albumsProvider);
    }

    _endSession(summary: summary);
    return summary;
  }

  /// Batch unhide with the same progress/cancel session model as hide.
  Future<ImportProgress> runReveal(
    List<MediaItem> items, {
    bool sessionAlreadyStarted = false,
  }) async {
    if (!sessionAlreadyStarted) {
      beginSession(phase: ImportPhase.unhiding);
    } else if (!state.running) {
      state = state.copyWith(running: true);
    }

    if (isCancelRequested) {
      return _finishCancelled(total: items.length);
    }

    final service = ref.read(importServiceProvider);
    final session = _session ??= ImportSession();

    ImportProgress summary;
    try {
      summary = await service.revealAll(
        items,
        session: session,
        onProgress: (p) {
          if (!ref.mounted) return;
          state = ImportUiState(
            running: true,
            progress: p,
            cancelling: session.isCancelled || p.cancelled,
            lastSummary: state.lastSummary,
          );
        },
      );
    } catch (e) {
      summary = ImportProgress(
        done: 0,
        total: items.length,
        phase: ImportPhase.done,
        failed: items.length,
        lastError: e.toString(),
        errorCode: ImportErrorCode.transferFailed,
      );
    }

    if (summary.imported > 0 && ref.mounted) {
      await refreshVisibleAfterReveal();
    }

    _endSession(summary: summary);
    return summary;
  }

  /// Resolve and restore a complete vault album through one controller flow.
  Future<AlbumRestoreResult> restoreAlbum(String albumId) async {
    final kind = ref.read(mediaKindFilterProvider);
    final items =
        await ref.read(albumRepositoryProvider).listMediaForAlbum(albumId);
    final filtered = items
        .where(
          (item) =>
              kind == MediaKindFilter.video ? item.isVideo : !item.isVideo,
        )
        .toList(growable: false);
    if (filtered.isEmpty) {
      const empty = ImportProgress(
        done: 0,
        total: 0,
        phase: ImportPhase.done,
      );
      return const AlbumRestoreResult(summary: empty, wasEmpty: true);
    }
    final summary = await runReveal(filtered, sessionAlreadyStarted: true);
    return AlbumRestoreResult(summary: summary, wasEmpty: false);
  }

  /// Force Visible folders to reappear after unhide (no manual pull-to-refresh).
  Future<void> refreshVisibleAfterReveal() async {
    if (!ref.mounted) return;
    final gallery = ref.read(galleryServiceProvider);
    gallery.apply(const VisibleRevealed());
    try {
      await gallery.clearFileCache().timeout(const Duration(seconds: 2));
    } catch (error, stackTrace) {
      debugPrint('visible cache refresh: $error\n$stackTrace');
    }
    // MediaStore needs a short beat after scan before folder counts update.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    ref.invalidate(galleryFoldersProvider);
    ref.invalidate(albumsProvider);
    try {
      await ref.read(galleryFoldersProvider.future);
    } catch (error, stackTrace) {
      debugPrint('visible folder refresh: $error\n$stackTrace');
    }
  }

  /// Request cancel. Safe to call anytime during a session (resolve or hide).
  void cancel() {
    final session = _session;
    if (session == null) return;
    session.cancel();
    if (ref.mounted && state.running) {
      state = state.copyWith(
        cancelling: true,
        progress: state.progress == null
            ? const ImportProgress(
                done: 0,
                total: 0,
                phase: ImportPhase.cancelled,
                cancelled: true,
              )
            : ImportProgress(
                done: state.progress!.done,
                total: state.progress!.total,
                phase: ImportPhase.cancelled,
                currentName: state.progress!.currentName,
                imported: state.progress!.imported,
                skipped: state.progress!.skipped,
                failed: state.progress!.failed,
                cancelled: true,
                lastError: state.progress!.lastError,
              ),
      );
    }
  }

  void clearSummary() {
    if (!ref.mounted) return;
    state = const ImportUiState();
    _session = null;
  }

  ImportProgress _finishCancelled({int total = 0}) {
    final summary = ImportProgress(
      done: 0,
      total: total,
      phase: ImportPhase.cancelled,
      cancelled: true,
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
    _session = null;
  }
}

final importControllerProvider =
    NotifierProvider<ImportController, ImportUiState>(ImportController.new);
