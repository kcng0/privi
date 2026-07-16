import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/database.dart';
import '../data/repositories/album_repository.dart';
import '../data/repositories/media_repository.dart';
import '../data/services/biometric_service.dart';
import '../data/services/import_service.dart';
import '../data/services/maintenance_service.dart';
import '../data/services/media_store_service.dart';
import '../data/services/security_service.dart';
import '../data/services/vault_backup_service.dart';
import '../data/services/vault_storage_service.dart';
import '../domain/models/album_view.dart';
import '../domain/models/media_item.dart';

/// Core DI graph. Manual providers for Phase 1 (codegen can replace later).

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final vaultStorageProvider = Provider<VaultStorageService>((ref) {
  return VaultStorageService();
});

final securityServiceProvider = Provider<SecurityService>((ref) {
  return SecurityService();
});

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

final mediaStoreServiceProvider = Provider<MediaStoreService>((ref) {
  return MediaStoreService();
});

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(
    ref.watch(databaseProvider),
    ref.watch(vaultStorageProvider),
  );
});

final albumRepositoryProvider = Provider<AlbumRepository>((ref) {
  return AlbumRepository(ref.watch(databaseProvider));
});

final importServiceProvider = Provider<ImportService>((ref) {
  return ImportService(
    storage: ref.watch(vaultStorageProvider),
    mediaRepository: ref.watch(mediaRepositoryProvider),
    albumRepository: ref.watch(albumRepositoryProvider),
  );
});

final vaultBackupServiceProvider = Provider<VaultBackupService>((ref) {
  return VaultBackupService(
    db: ref.watch(databaseProvider),
    media: ref.watch(mediaRepositoryProvider),
    albums: ref.watch(albumRepositoryProvider),
    storage: ref.watch(vaultStorageProvider),
  );
});

final maintenanceServiceProvider = Provider<MaintenanceService>((ref) {
  return MaintenanceService(
    db: ref.watch(databaseProvider),
    media: ref.watch(mediaRepositoryProvider),
    storage: ref.watch(vaultStorageProvider),
    import: ref.watch(importServiceProvider),
  );
});

/// Total vault media bytes (active + recycle) for Settings.
final vaultSizeBytesProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(mediaRepositoryProvider).totalBytes();
});

/// Home album cards (system + user) with live counts/covers.
final albumsProvider = StreamProvider<List<AlbumView>>((ref) {
  return ref.watch(albumRepositoryProvider).watchAlbumViewsReactive();
});

/// Media stream for a given album id (system virtual or user).
final albumMediaProvider =
    StreamProvider.family<List<MediaItem>, String>((ref, albumId) {
  return ref.watch(mediaRepositoryProvider).watchForAlbum(albumId);
});
