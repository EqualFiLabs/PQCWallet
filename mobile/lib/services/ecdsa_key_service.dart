import 'dart:typed_data';
import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:web3dart/crypto.dart' as w3crypto;
import 'package:web3dart/web3dart.dart';

import 'wallet_secret.dart';

class ECDSAKeyPair {
  final Uint8List privateKey;
  final Uint8List publicKey;
  final EthereumAddress address;

  const ECDSAKeyPair({
    required this.privateKey,
    required this.publicKey,
    required this.address,
  });
}

class ECDSAKeyData {
  final String mnemonic;
  final Uint8List seed;
  final ECDSAKeyPair keyPair;

  const ECDSAKeyData({
    required this.mnemonic,
    required this.seed,
    required this.keyPair,
  });
}

class ECDSAKeyService {
  const ECDSAKeyService();

  ECDSAKeyData deriveFromMnemonic(String? existingMnemonic) {
    final mnemonic = existingMnemonic ?? bip39.generateMnemonic(strength: 128);
    final seed = Uint8List.fromList(bip39.mnemonicToSeed(mnemonic));
    final root = bip32.BIP32.fromSeed(seed);
    final child = root.derivePath("m/44'/60'/0'/0/0");
    final privateKey = Uint8List.fromList(child.privateKey!);
    final publicKey = Uint8List.fromList(
      w3crypto.privateKeyBytesToPublic(privateKey),
    );
    final address = EthereumAddress.fromPublicKey(publicKey);
    return ECDSAKeyData(
      mnemonic: mnemonic,
      seed: seed,
      keyPair: ECDSAKeyPair(
        privateKey: privateKey,
        publicKey: publicKey,
        address: address,
      ),
    );
  }

  ECDSAKeyPair deriveFromPrivateKeyHex(String privateKeyHex) {
    final normalized = normalizePrivateKeyHex(privateKeyHex);
    final bytes = Uint8List.fromList(w3crypto.hexToBytes(normalized));
    return deriveFromPrivateKeyBytes(bytes);
  }

  ECDSAKeyPair deriveFromPrivateKeyBytes(Uint8List privateKey) {
    if (privateKey.length != 32) {
      throw ArgumentError('Private key must be 32 bytes.');
    }
    final privCopy = Uint8List.fromList(privateKey);
    final publicKey = Uint8List.fromList(
      w3crypto.privateKeyBytesToPublic(privCopy),
    );
    final address = EthereumAddress.fromPublicKey(publicKey);
    return ECDSAKeyPair(
      privateKey: privCopy,
      publicKey: publicKey,
      address: address,
    );
  }

  Uint8List exportPublicKey(ECDSAKeyPair keyPair) => Uint8List.fromList(keyPair.publicKey);

  EthereumAddress address(ECDSAKeyPair keyPair) => keyPair.address;

  Future<w3crypto.MsgSignature> sign(
    Uint8List messageHash,
    ECDSAKeyPair keyPair, {
    int? chainId,
  }) async {
    final creds = EthPrivateKey(keyPair.privateKey);
    final sigBytes = creds.signToUint8List(messageHash, chainId: chainId);
    return w3crypto.MsgSignature(
      w3crypto.bytesToInt(sigBytes.sublist(0, 32)),
      w3crypto.bytesToInt(sigBytes.sublist(32, 64)),
      sigBytes[64],
    );
  }
}
