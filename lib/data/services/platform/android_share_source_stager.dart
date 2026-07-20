import '../../../application/platform/share_source_stager.dart';
import '../import/import_models.dart';

/// Preserves the existing Android share-intent path contract.
final class AndroidShareSourceStager implements ShareSourceStager {
  const AndroidShareSourceStager();

  @override
  Future<List<ImportSource>> recoverPending() async => const [];

  @override
  Future<List<ImportSource>> stage(List<ImportSource> sources) async =>
      List.unmodifiable(sources);
}
