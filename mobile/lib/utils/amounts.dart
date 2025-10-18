/// Utilities for working with token and ETH denominations.
///
/// Converts human-readable decimal strings into `BigInt` values scaled by the
/// provided number of decimals. Examples:
/// * `parseDecimalAmount('1', decimals: 18)` -> `1e18`
/// * `parseDecimalAmount('0.001', decimals: 18)` -> `1e15`
/// * `parseDecimalAmount('12.34', decimals: 6)` -> `12340000`
/// Set `treatEmptyAsZero` when blank user input should fall back to zero rather
/// than throwing.
BigInt parseDecimalAmount(
  String input, {
  required int decimals,
  bool treatEmptyAsZero = false,
}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    if (treatEmptyAsZero) {
      return BigInt.zero;
    }
    throw const FormatException('Amount is required');
  }
  if (trimmed.startsWith('-')) {
    throw const FormatException('Negative amounts are not supported');
  }

  final parts = trimmed.split('.');
  if (parts.length > 2) {
    throw const FormatException('Invalid decimal format');
  }

  final wholePart = parts[0];
  final fractionPart = parts.length == 2 ? parts[1] : '';

  if (wholePart.isNotEmpty && !_isDigits(wholePart)) {
    throw const FormatException('Invalid whole number');
  }
  if (fractionPart.isNotEmpty && !_isDigits(fractionPart)) {
    throw const FormatException('Invalid fractional value');
  }

  final whole = wholePart.isEmpty ? BigInt.zero : BigInt.parse(wholePart);
  var fraction = fractionPart;
  if (fraction.length > decimals) {
    fraction = fraction.substring(0, decimals);
  }
  final fractionValue = fraction.isEmpty
      ? BigInt.zero
      : BigInt.parse(fraction.padRight(decimals, '0'));

  final scale = BigInt.from(10).pow(decimals);
  return whole * scale + fractionValue;
}

bool _isDigits(String value) {
  for (final code in value.codeUnits) {
    if (code < 0x30 || code > 0x39) {
      return false;
    }
  }
  return true;
}
