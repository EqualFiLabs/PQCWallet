import 'package:flutter_test/flutter_test.dart';

import 'package:pqc_wallet/utils/amounts.dart';

void main() {
  group('parseDecimalAmount', () {
    test('parses fractional wei values with 18 decimals', () {
      final result = parseDecimalAmount('0.001', decimals: 18);
      expect(result, BigInt.from(10).pow(15));
    });

    test('handles whole numbers', () {
      final twoEth = parseDecimalAmount('2', decimals: 18);
      expect(twoEth, BigInt.from(2) * BigInt.from(10).pow(18));
    });

    test('handles fractional part shorter than decimals', () {
      final value = parseDecimalAmount('1.23456789', decimals: 18);
      expect(value, BigInt.parse('1234567890000000000'));
    });

    test('truncates extra fractional precision', () {
      final value = parseDecimalAmount('0.0000000000000000019', decimals: 18);
      expect(value, BigInt.one);
    });

    test('parses with limited decimals', () {
      final value = parseDecimalAmount('1.23456789', decimals: 6);
      expect(value, BigInt.from(1234567));
    });

    test('trims whitespace', () {
      final value = parseDecimalAmount('  3.5  ', decimals: 18);
      final expected = BigInt.from(3) * BigInt.from(10).pow(18) +
          BigInt.from(5) * BigInt.from(10).pow(17);
      expect(value, expected);
    });

    test('throws on invalid characters', () {
      expect(
        () => parseDecimalAmount('abc', decimals: 18),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws on negative amounts', () {
      expect(
        () => parseDecimalAmount('-1', decimals: 18),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws on empty input by default', () {
      expect(
        () => parseDecimalAmount('', decimals: 18),
        throwsA(isA<FormatException>()),
      );
    });

    test('treats empty input as zero when requested', () {
      final value = parseDecimalAmount(
        '',
        decimals: 6,
        treatEmptyAsZero: true,
      );
      expect(value, BigInt.zero);
    });
  });
}
