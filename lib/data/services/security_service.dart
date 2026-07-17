import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Root lock secret (pattern preferred; legacy PIN still verifiable).
/// See docs/03-architecture/security.md.
class SecurityService {
  SecurityService({
    FlutterSecureStorage? storage,
    DateTime Function()? now,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            ),
        _now = now ?? DateTime.now;

  final FlutterSecureStorage _storage;
  final DateTime Function() _now;

  static const _kSalt = 'pin_salt';
  static const _kHash = 'pin_hash';
  static const _kIterations = 'pin_iterations';
  static const _kBiometric = 'biometric_enabled';
  static const _kKind = 'lock_kind'; // pattern | pin
  static const _kFailCount = 'unlock_fail_count';
  static const _kLockoutUntil = 'unlock_lockout_until';
  static const _kKdfVersion = 'kdf_version';

  static const int legacyIterations = 120000;
  static const int pbkdf2Iterations = 210000;
  static const int _legacyKdfVersion = 1;
  static const int _pbkdf2KdfVersion = 2;

  static const kindPattern = 'pattern';
  static const kindPin = 'pin';

  Future<bool> hasCredential() async {
    final hash = await _storage.read(key: _kHash);
    return hash != null && hash.isNotEmpty;
  }

  /// Back-compat alias.
  Future<bool> hasPin() => hasCredential();

  Future<String> lockKind() async {
    final k = await _storage.read(key: _kKind);
    if (k == kindPattern) return kindPattern;
    if (k == kindPin) return kindPin;
    // Pre-pattern installs only had PIN.
    if (await hasCredential()) return kindPin;
    return kindPattern;
  }

  /// Pattern secret: ordered cell indices 0–8 joined with `-`, min 4 cells.
  /// Example: `0-1-2-5-8`.
  Future<void> setPattern(String pattern) async {
    _assertPatternFormat(pattern);
    await _setSecret(pattern, kind: kindPattern);
  }

  Future<bool> verifyPattern(String pattern) async {
    if (!_isPatternFormat(pattern)) return false;
    return _verifySecret(pattern);
  }

  /// Legacy PIN (4–6 digits). Still used if [lockKind] is pin.
  Future<void> setPin(String pin) async {
    _assertPinFormat(pin);
    await _setSecret(pin, kind: kindPin);
  }

  Future<bool> verifyPin(String pin) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) return false;
    return _verifySecret(pin);
  }

  Future<bool> isBiometricEnabled() async {
    final v = await _storage.read(key: _kBiometric);
    return v == '1';
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: _kBiometric, value: enabled ? '1' : '0');
  }

  /// Wipe root secret (after system auth recovery). Does not delete vault media.
  Future<void> clearCredential() async {
    await _storage.delete(key: _kSalt);
    await _storage.delete(key: _kHash);
    await _storage.delete(key: _kIterations);
    await _storage.delete(key: _kKind);
    await _storage.delete(key: _kKdfVersion);
    await _resetFailures();
    // Keep biometric preference so user can re-enable after new pattern.
  }

  Future<void> _setSecret(String secret, {required String kind}) async {
    final salt = _randomSalt(16);
    const iterations = pbkdf2Iterations;
    final hash = await _derivePbkdf2(secret, salt, iterations);
    await _storage.write(key: _kSalt, value: base64Encode(salt));
    await _storage.write(key: _kHash, value: base64Encode(hash));
    await _storage.write(key: _kIterations, value: iterations.toString());
    await _storage.write(
      key: _kKdfVersion,
      value: _pbkdf2KdfVersion.toString(),
    );
    await _storage.write(key: _kKind, value: kind);
    await _resetFailures();
  }

  Future<bool> _verifySecret(String secret) async {
    if (await lockoutRemaining() != null) return false;

    final saltB64 = await _storage.read(key: _kSalt);
    final hashB64 = await _storage.read(key: _kHash);
    final iterStr = await _storage.read(key: _kIterations);
    if (saltB64 == null || hashB64 == null || iterStr == null) {
      return false;
    }
    final salt = base64Decode(saltB64);
    final expected = base64Decode(hashB64);
    final iterations = int.parse(iterStr);
    final version = await _readKdfVersion();
    final actual = switch (version) {
      _legacyKdfVersion => await compute(
          _deriveLegacyInBackground,
          _Pbkdf2Input(
            secret: secret,
            salt: List<int>.unmodifiable(salt),
            iterations: iterations,
          ),
        ),
      _pbkdf2KdfVersion => await _derivePbkdf2(secret, salt, iterations),
      _ => throw StateError('Unsupported KDF version: $version'),
    };
    final matches = _constantTimeEquals(actual, expected);
    if (!matches) {
      await _recordFailure();
      return false;
    }

    await _resetFailures();
    if (version == _legacyKdfVersion) {
      final storedKind = await _storage.read(key: _kKind);
      final kind = storedKind == kindPattern ? kindPattern : kindPin;
      await _setSecret(secret, kind: kind);
    }
    return true;
  }

  /// Remaining throttling delay, or null when another attempt is allowed.
  Future<Duration?> lockoutRemaining() async {
    final raw = await _storage.read(key: _kLockoutUntil);
    if (raw == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(int.parse(raw));
    final remaining = until.difference(_now());
    if (remaining <= Duration.zero) {
      await _storage.delete(key: _kLockoutUntil);
      return null;
    }
    return remaining;
  }

  Future<int> _readKdfVersion() async {
    final raw = await _storage.read(key: _kKdfVersion);
    return raw == null ? _legacyKdfVersion : int.parse(raw);
  }

  Future<void> _recordFailure() async {
    final raw = await _storage.read(key: _kFailCount);
    final failures = (raw == null ? 0 : int.parse(raw)) + 1;
    await _storage.write(key: _kFailCount, value: failures.toString());
    if (failures < 5) return;

    final exponent = failures - 5;
    final seconds = exponent >= 4 ? 300 : min(300, 30 * (1 << exponent));
    final until = _now().add(Duration(seconds: seconds));
    await _storage.write(
      key: _kLockoutUntil,
      value: until.millisecondsSinceEpoch.toString(),
    );
  }

  Future<void> _resetFailures() async {
    await _storage.delete(key: _kFailCount);
    await _storage.delete(key: _kLockoutUntil);
  }

  void _assertPinFormat(String pin) {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      throw ArgumentError('PIN must be 4–6 digits');
    }
  }

  void _assertPatternFormat(String pattern) {
    if (!_isPatternFormat(pattern)) {
      throw ArgumentError('Pattern must connect at least 4 dots');
    }
  }

  static bool _isPatternFormat(String pattern) {
    final parts = pattern.split('-');
    if (parts.length < 4) return false;
    final seen = <int>{};
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 8) return false;
      if (!seen.add(n)) return false; // no reuse
    }
    return true;
  }

  /// Encode ordered cell indices to storage form.
  static String encodePattern(List<int> cells) => cells.join('-');

  static List<int>? decodePattern(String pattern) {
    if (!_isPatternFormat(pattern)) return null;
    return pattern.split('-').map(int.parse).toList();
  }

  Uint8List _randomSalt(int length) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => r.nextInt(256)));
  }

  Future<Uint8List> _derivePbkdf2(
    String secret,
    List<int> salt,
    int iterations,
  ) {
    return compute(
      _derivePbkdf2InBackground,
      _Pbkdf2Input(
        secret: secret,
        salt: List<int>.unmodifiable(salt),
        iterations: iterations,
      ),
    );
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class _Pbkdf2Input {
  const _Pbkdf2Input({
    required this.secret,
    required this.salt,
    required this.iterations,
  });

  final String secret;
  final List<int> salt;
  final int iterations;
}

Uint8List _deriveLegacyInBackground(_Pbkdf2Input input) {
  final block = utf8.encode(input.secret) + input.salt;
  var digest = sha256.convert(block);
  for (var i = 1; i < input.iterations; i++) {
    digest = sha256.convert(digest.bytes + input.salt);
  }
  return Uint8List.fromList(digest.bytes);
}

Future<Uint8List> _derivePbkdf2InBackground(_Pbkdf2Input input) async {
  final algorithm = cryptography.Pbkdf2.hmacSha256(
    iterations: input.iterations,
    bits: 256,
  );
  final key = await algorithm.deriveKeyFromPassword(
    password: input.secret,
    nonce: input.salt,
  );
  return Uint8List.fromList(await key.extractBytes());
}
