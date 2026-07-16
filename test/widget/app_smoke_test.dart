import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:privateheart_vault/app.dart';
import 'package:privateheart_vault/application/lock/lock_controller.dart';
import 'package:privateheart_vault/application/providers.dart';
import 'package:privateheart_vault/data/services/biometric_service.dart';
import 'package:privateheart_vault/data/services/security_service.dart';
import 'package:privateheart_vault/domain/enums.dart';
import 'package:privateheart_vault/domain/models/album.dart';
import 'package:privateheart_vault/domain/models/album_view.dart';

class _FakeSecurity extends SecurityService {
  _FakeSecurity() : super();

  bool _has = false;
  bool bio = false;
  String _kind = SecurityService.kindPattern;

  @override
  Future<bool> hasCredential() async => _has;

  @override
  Future<bool> hasPin() async => _has;

  @override
  Future<String> lockKind() async => _kind;

  @override
  Future<void> setPattern(String pattern) async {
    _has = true;
    _kind = SecurityService.kindPattern;
  }

  @override
  Future<bool> verifyPattern(String pattern) async =>
      _has && pattern.split('-').length >= 4;

  @override
  Future<void> setPin(String pin) async {
    _has = true;
    _kind = SecurityService.kindPin;
  }

  @override
  Future<bool> verifyPin(String pin) async => _has && pin.length >= 4;

  @override
  Future<bool> isBiometricEnabled() async => bio;

  @override
  Future<void> setBiometricEnabled(bool enabled) async {
    bio = enabled;
  }
}

class _FakeBio extends BiometricService {
  @override
  Future<bool> isHardwareAvailable() async => false;

  @override
  Future<bool> authenticate({
    String reason = 'Unlock Privi',
    bool biometricOnly = true,
  }) async =>
      false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App boots into lock setup with dark theme', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        securityServiceProvider.overrideWithValue(_FakeSecurity()),
        biometricServiceProvider.overrideWithValue(_FakeBio()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PrivateHeartApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Draw a pattern'), findsOneWidget);
    final MaterialApp app = tester.widget(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('HD Smith Visible|Invisible shell + mosaic tiles', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.utc(2026, 1, 1);
    final views = [
      AlbumView(
        album: Album(
          id: SystemAlbumIds.all,
          name: 'All Media',
          isSystem: true,
          createdAt: now,
          systemKind: SystemAlbumKind.all,
        ),
        count: 12,
      ),
      AlbumView(
        album: Album(
          id: SystemAlbumIds.favorites,
          name: 'Favorites',
          isSystem: true,
          createdAt: now,
          systemKind: SystemAlbumKind.favorites,
        ),
        count: 3,
      ),
      AlbumView(
        album: Album(
          id: 'user-1',
          name: 'paris',
          isSystem: false,
          createdAt: now,
        ),
        count: 4,
      ),
      AlbumView(
        album: Album(
          id: SystemAlbumIds.recycle,
          name: 'Recycle Bin',
          isSystem: true,
          createdAt: now,
          systemKind: SystemAlbumKind.recycle,
        ),
        count: 0,
      ),
    ];

    final container = ProviderContainer(
      overrides: [
        securityServiceProvider.overrideWithValue(_FakeSecurity()),
        biometricServiceProvider.overrideWithValue(_FakeBio()),
        lockControllerProvider.overrideWith(_UnlockedLock.new),
        albumsProvider.overrideWith((ref) => Stream.value(views)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PrivateHeartApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Visible'), findsOneWidget);
    expect(find.text('Invisible'), findsOneWidget);
    expect(find.text('All Media'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('New album'), findsOneWidget);
    expect(find.text('paris'), findsOneWidget);
    expect(find.text('Recycle Bin'), findsOneWidget);
  });
}

class _UnlockedLock extends LockController {
  @override
  VaultLockState build() =>
      const VaultLockState(status: LockStatus.unlocked);
}
