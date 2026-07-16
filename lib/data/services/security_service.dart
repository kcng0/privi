import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Root lock secret (pattern preferred; legacy PIN still verifiable).
/// See docs/03-architecture/security.md.
class SecurityService {
  SecurityService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _kSalt = 'pin_salt';
  static const _kHash = 'pin_hash';
  static const _kIterations = 'pin_iterations';
  static const _kBiometric = 'biometric_enabled';
  static const _kKind = 'lock_kind'; // pattern | pin
  static const int defaultIterations = 120000;

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
    // Keep biometric preference so user can re-enable after new pattern.
  }

  Future<void> _setSecret(String secret, {required String kind}) async {
    final salt = _randomSalt(16);
    const iterations = defaultIterations;
    final hash = _derive(secret, salt, iterations);
    await _storage.write(key: _kSalt, value: base64Encode(salt));
    await _storage.write(key: _kHash, value: base64Encode(hash));
    await _storage.write(key: _kIterations, value: iterations.toString());
    await _storage.write(key: _kKind, value: kind);
  }

  Future<bool> _verifySecret(String secret) async {
    final saltB64 = await _storage.read(key: _kSalt);
    final hashB64 = await _storage.read(key: _kHash);
    final iterStr = await _storage.read(key: _kIterations);
    if (saltB64 == null || hashB64 == null || iterStr == null) {
      return false;
    }
    final salt = base64Decode(saltB64);
    final expected = base64Decode(hashB64);
    final iterations = int.tryParse(iterStr) ?? defaultIterations;
    final actual = _derive(secret, salt, iterations);
    return _constantTimeEquals(actual, expected);
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

  /// Iterated HMAC-SHA256 style KDF (cheap, pure-Dart, no extra deps).
  Uint8List _derive(String secret, List<int> salt, int iterations) {
    final block = utf8.encode(secret) + salt;
    var digest = sha256.convert(block);
    for (var i = 1; i < iterations; i++) {
      digest = sha256.convert(digest.bytes + salt);
    }
    return Uint8List.fromList(digest.bytes);
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
