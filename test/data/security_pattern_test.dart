import 'package:flutter_test/flutter_test.dart';
import 'package:privateheart_vault/data/services/security_service.dart';

void main() {
  group('SecurityService pattern helpers', () {
    test('encode/decode round-trip', () {
      const cells = [0, 1, 2, 5, 8];
      final s = SecurityService.encodePattern(cells);
      expect(s, '0-1-2-5-8');
      expect(SecurityService.decodePattern(s), cells);
    });

    test('rejects short patterns', () {
      expect(SecurityService.decodePattern('0-1-2'), isNull);
    });

    test('rejects reuse', () {
      expect(SecurityService.decodePattern('0-1-0-2'), isNull);
    });
  });
}
