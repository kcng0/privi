import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:privi/data/repositories/album_repository.dart';
import 'package:privi/data/repositories/media_repository.dart';
import 'package:privi/data/services/vault_backup_service.dart';
import 'package:privi/domain/models/media_item.dart';

import '../support/vault_backup_test_harness.dart';

part 'vault_backup/export_cases.dart';
part 'vault_backup/restore_cases.dart';
part 'vault_backup/compatibility_cases.dart';

void main() {
  configureVaultBackupTestSqlite();
  final harness = VaultBackupTestHarness();

  setUp(harness.setUp);
  tearDown(harness.tearDown);

  registerVaultBackupExportTests(harness);
  registerVaultBackupRestoreTests(harness);
  registerVaultBackupCompatibilityTests(harness);
}
