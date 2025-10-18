import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_wallet/crypto/mnemonic.dart';

void main() {
  group('deriveFromPrivateKey', () {
    test('produces expected address for known key', () {
      const privateKey =
          '0x4c0883a69102937d6231471b5dbb6204fe512961708279f1fd50a89c1a7f0c4a';
      final km = deriveFromPrivateKey(privateKey);
      expect(km.mnemonic, isNull);
      expect(km.seed, isNull);
      expect(km.eoaAddress.hexEip55,
          equals('0x926FFf9FBEbDAEad2FaE0e3bD7E73cFA66c4F988'));
    });

    test('throws on invalid private key input', () {
      expect(() => deriveFromPrivateKey('0x1234'), throwsArgumentError);
    });
  });
}
