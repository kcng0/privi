import 'package:flutter/widgets.dart';

import '../../core/l10n.dart';
import '../../data/services/import/import_models.dart';

/// Localized detail for platform-specific import outcomes.
String? importOutcomeDetail(
  BuildContext context,
  ImportErrorCode? errorCode,
) {
  final l10n = context.l10n;
  return switch (errorCode) {
    ImportErrorCode.permissionDenied => l10n.permissionNeeded,
    ImportErrorCode.limitedAccess => l10n.limitedPhotosAccess,
    ImportErrorCode.notLocallyAvailable => l10n.mediaNotAvailableOffline,
    ImportErrorCode.sourceStillPresent => l10n.sourceStillPresent,
    ImportErrorCode.destinationVerificationFailed =>
      l10n.privateCopyVerificationFailed,
    ImportErrorCode.unsupported => l10n.operationUnavailableOnPlatform,
    ImportErrorCode.platformFailure => l10n.couldNotHideMedia,
    ImportErrorCode.transferFailed ||
    ImportErrorCode.emptyDest ||
    ImportErrorCode.timeout ||
    ImportErrorCode.needManageStorage ||
    null =>
      null,
  };
}
