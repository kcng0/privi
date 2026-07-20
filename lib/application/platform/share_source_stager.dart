import '../../data/services/import/import_models.dart';

/// Converts share-plugin inputs into sources whose lifetime is explicit.
///
/// Android keeps the plugin-provided paths. iOS copies App Group attachments
/// into app-private durable staging so lock and process restarts cannot discard
/// an accepted share.
abstract interface class ShareSourceStager {
  Future<List<ImportSource>> recoverPending();

  Future<List<ImportSource>> stage(List<ImportSource> sources);
}
