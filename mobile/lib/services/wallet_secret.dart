enum WalletSecretType { mnemonic, privateKey }

class WalletSecret {
  final WalletSecretType type;
  final String value;

  const WalletSecret._(this.type, this.value);

  factory WalletSecret.mnemonic(String mnemonic) {
    final trimmed = mnemonic.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Mnemonic cannot be empty.');
    }
    return WalletSecret._(WalletSecretType.mnemonic, trimmed);
  }

  factory WalletSecret.privateKey(String privateKeyHex) {
    final normalized = normalizePrivateKeyHex(privateKeyHex);
    return WalletSecret._(WalletSecretType.privateKey, normalized);
  }
}

class WalletSecretCodec {
  static const _privateKeyPrefix = 'pk:';

  static WalletSecret? decode(String? raw) {
    if (raw == null) return null;
    if (raw.startsWith(_privateKeyPrefix)) {
      final body = raw.substring(_privateKeyPrefix.length);
      return WalletSecret.privateKey(body);
    }
    return WalletSecret.mnemonic(raw);
  }

  static String encode(WalletSecret secret) {
    switch (secret.type) {
      case WalletSecretType.mnemonic:
        return secret.value;
      case WalletSecretType.privateKey:
        return '$_privateKeyPrefix${secret.value}';
    }
  }
}

String normalizePrivateKeyHex(String input) {
  final trimmed = input.trim();
  final hasPrefix =
      trimmed.startsWith('0x') || trimmed.startsWith('0X');
  final body = hasPrefix ? trimmed.substring(2) : trimmed;
  if (body.length != 64) {
    throw ArgumentError('Private key must be 32 bytes (64 hex chars).');
  }
  final hexRegex = RegExp(r'^[0-9a-fA-F]+$');
  if (!hexRegex.hasMatch(body)) {
    throw ArgumentError('Private key must be hexadecimal.');
  }
  return '0x${body.toLowerCase()}';
}
