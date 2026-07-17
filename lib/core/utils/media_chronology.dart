import '../../domain/models/media_item.dart';

/// Original media chronology shared by Visible and Invisible grids.
abstract final class MediaChronology {
  static DateTime forVaultItem(MediaItem item) =>
      item.dateTaken ?? item.dateAdded;

  static DateTime fromEpochMs(int? value) =>
      DateTime.fromMillisecondsSinceEpoch(
        value ?? 0,
        isUtc: true,
      );

  static int compare({
    required DateTime leftDate,
    required String leftName,
    required DateTime rightDate,
    required String rightName,
    required bool ascending,
  }) {
    final dateComparison = ascending
        ? leftDate.compareTo(rightDate)
        : rightDate.compareTo(leftDate);
    if (dateComparison != 0) return dateComparison;

    return leftName.compareTo(rightName);
  }
}
