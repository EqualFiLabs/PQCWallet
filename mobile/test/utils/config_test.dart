import 'package:flutter_test/flutter_test.dart';

import 'package:pqc_wallet/utils/config.dart';

void main() {
  group('parseChainId', () {
    test('parses decimal ints', () {
      expect(parseChainId(84532), 84532);
      expect(parseChainId(10.0), 10);
      expect(parseChainId('69'), 69);
    });

    test('parses hex strings', () {
      expect(parseChainId('0x14a34'), 84532);
      expect(parseChainId('0X1'), 1);
    });

    test('returns null for invalid inputs', () {
      expect(parseChainId(null), isNull);
      expect(parseChainId(''), isNull);
      expect(parseChainId('not-a-number'), isNull);
    });
  });

  group('requireChainId', () {
    test('throws when missing', () {
      expect(
        () => requireChainId({}),
        throwsA(isA<FormatException>()),
      );
    });

    test('mutates config with parsed chainId', () {
      final cfg = <String, dynamic>{'chainId': '0x14a34'};
      final parsed = requireChainId(cfg);
      expect(parsed, 84532);
      expect(cfg['chainId'], 84532);
    });
  });
}
