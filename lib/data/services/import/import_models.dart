enum ImportPhase {
  resolving,
  hiding,
  unhiding,
  cancelled,
  done,
}

enum ImportErrorCode {
  needManageStorage,
  transferFailed,
  emptyDest,
  timeout,
  permissionDenied,
  limitedAccess,
  notLocallyAvailable,
  sourceStillPresent,
  destinationVerificationFailed,
  unsupported,
  platformFailure,
}

/// Source for a hide operation (real file path preferred).
class ImportSource {
  const ImportSource({
    required this.path,
    this.name,
    this.mimeType,
    this.contentUri,
    this.assetId,
    this.sourceFolderName,
    this.dateTaken,
    this.deleteAfterImport = false,
    this.temporaryThumbnailPath,
  });

  final String path;
  final String? name;
  final String? mimeType;
  final String? contentUri;
  final String? assetId;
  final String? sourceFolderName;

  /// True only for app-owned staging. A workflow may remove this file after a
  /// verified private copy; user-owned picker and gallery paths must stay false.
  final bool deleteAfterImport;

  /// Optional app-group derivative that the iOS stager consumes with [path].
  final String? temporaryThumbnailPath;

  /// Original capture/create time from MediaStore.
  final DateTime? dateTaken;
}

class ImportProgress {
  const ImportProgress({
    required this.done,
    required this.total,
    required this.phase,
    this.currentName,
    this.cancelled = false,
    this.imported = 0,
    this.skipped = 0,
    this.failed = 0,
    this.removalFailed = 0,
    this.sourceStillPresent = 0,
    this.statusMessage,
    this.lastError,
    this.errorCode,
  });

  final int done;
  final int total;
  final ImportPhase phase;
  final String? currentName;
  final bool cancelled;
  final int imported;
  final int skipped;
  final int failed;
  final int removalFailed;
  final int sourceStillPresent;

  @Deprecated('Use phase and errorCode for localized UI text.')
  final String? statusMessage;

  /// Raw diagnostic detail for logs, never direct user presentation.
  final String? lastError;
  final ImportErrorCode? errorCode;

  double get fraction => total == 0 ? 0 : done / total;
}

class ImportCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class ImportSession {
  ImportSession({ImportCancelToken? cancelToken})
      : cancelToken = cancelToken ?? ImportCancelToken();

  final ImportCancelToken cancelToken;

  bool get isCancelled => cancelToken.isCancelled;

  void cancel() => cancelToken.cancel();
}
