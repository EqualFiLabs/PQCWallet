import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_wallet/services/wallet_secret.dart';

void main() {
  group('WalletSecretCodec', () {
    test('round-trips mnemonic secrets', () {
      final original = WalletSecret.mnemonic(
          'gesture runway diesel vapor opera limb tilt autumn grape cable invest resist');
      final encoded = WalletSecretCodec.encode(original);
      expect(encoded.split(' ').length, 12);
      final decoded = WalletSecretCodec.decode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.type, WalletSecretType.mnemonic);
      expect(decoded.value, original.value);
    });

    test('round-trips private key secrets', () {
      final original = WalletSecret.privateKey('0XABCD1234ABCD1234ABCD1234ABCD1234ABCD1234ABCD1234ABCD1234ABCD1234');
      final encoded = WalletSecretCodec.encode(original);
      expect(encoded.startsWith('pk:'), isTrue);
      final decoded = WalletSecretCodec.decode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.type, WalletSecretType.privateKey);
      expect(decoded.value, '0xabcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234');
    });
  });

  group('normalizePrivateKeyHex', () {
    test('throws on invalid length', () {
      expect(() => normalizePrivateKeyHex('0x1234'), throwsArgumentError);
    });

    test('throws on non-hex characters', () {
      expect(() => normalizePrivateKeyHex('0xg1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd'),
          throwsArgumentError);
    });
  });
}
