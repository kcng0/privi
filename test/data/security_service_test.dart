import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/services/security_service.dart';

Uint8List _legacyHash(String secret, List<int> salt, int iterations) {
  var digest = sha256.convert(utf8.encode(secret) + salt);
  for (var i = 1; i < iterations; i++) {
    digest = sha256.convert(digest.bytes + salt);
  }
  return Uint8List.fromList(digest.bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wrong attempts persist and use the documented lockout table', () async {
    FlutterSecureStorage.setMockInitialValues({});
    var now = DateTime.utc(2026, 7, 17, 10);
    final service = SecurityService(now: () => now);
    await service.setPin('1234');

    for (var attempt = 1; attempt <= 4; attempt++) {
      expect(await service.verifyPin('9999'), isFalse);
      expect(await service.lockoutRemaining(), isNull);
    }

    expect(await service.verifyPin('9999'), isFalse);
    expect((await service.lockoutRemaining())!.inSeconds, 30);

    final reloaded = SecurityService(now: () => now);
    expect(await reloaded.verifyPin('1234'), isFalse);
    expect((await reloaded.lockoutRemaining())!.inSeconds, 30);

    const expectedDelays = [60, 120, 240, 300];
    for (final delay in expectedDelays) {
      now = now.add(const Duration(minutes: 6));
      expect(await reloaded.verifyPin('9999'), isFalse);
      expect((await reloaded.lockoutRemaining())!.inSeconds, delay);
    }

    now = now.add(const Duration(minutes: 6));
    expect(await reloaded.verifyPin('1234'), isTrue);
    expect(await reloaded.lockoutRemaining(), isNull);
  });

  test('successful legacy verification migrates the credential to PBKDF2',
      () async {
    const secret = '2468';
    final salt = List<int>.generate(16, (index) => index + 1);
    final legacy = _legacyHash(
      secret,
      salt,
      SecurityService.legacyIterations,
    );
    FlutterSecureStorage.setMockInitialValues({
      'pin_salt': base64Encode(salt),
      'pin_hash': base64Encode(legacy),
      'pin_iterations': SecurityService.legacyIterations.toString(),
      'lock_kind': SecurityService.kindPin,
    });
    const storage = FlutterSecureStorage();
    final service = SecurityService(storage: storage);

    expect(await service.verifyPin(secret), isTrue);
    expect(await storage.read(key: 'kdf_version'), '2');
    expect(
      await storage.read(key: 'pin_iterations'),
      SecurityService.pbkdf2Iterations.toString(),
    );
    expect(await service.verifyPin(secret), isTrue);
  });

  test('wrong legacy secret never migrates the credential', () async {
    const secret = '2468';
    final salt = List<int>.generate(16, (index) => index + 1);
    FlutterSecureStorage.setMockInitialValues({
      'pin_salt': base64Encode(salt),
      'pin_hash': base64Encode(
        _legacyHash(secret, salt, SecurityService.legacyIterations),
      ),
      'pin_iterations': SecurityService.legacyIterations.toString(),
      'lock_kind': SecurityService.kindPin,
    });
    const storage = FlutterSecureStorage();
    final service = SecurityService(storage: storage);

    expect(await service.verifyPin('1357'), isFalse);
    expect(await storage.read(key: 'kdf_version'), isNull);
  });
}
