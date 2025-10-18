import 'dart:typed_data';
import 'package:web3dart/web3dart.dart';

import '../services/ecdsa_key_service.dart';
import '../services/wots_seed_service.dart';

class KeyMaterial {
  final String? mnemonic;
  final Uint8List? seed;
  final ECDSAKeyPair ecdsa;
  final Uint8List wotsMaster;

  const KeyMaterial({
    required this.mnemonic,
    required this.seed,
    required this.ecdsa,
    required this.wotsMaster,
  });

  Uint8List get ecdsaPriv => Uint8List.fromList(ecdsa.privateKey);
  EthereumAddress get eoaAddress => ecdsa.address;
}

const _ecdsaKeyService = ECDSAKeyService();
const _wotsSeedService = WOTSSeedService();

KeyMaterial deriveFromMnemonic(String? existing) {
  final derived = _ecdsaKeyService.deriveFromMnemonic(existing);
  final wotsMaster =
      _wotsSeedService.deriveMaster(derived.keyPair.privateKey);
  return KeyMaterial(
    mnemonic: derived.mnemonic,
    seed: derived.seed,
    ecdsa: derived.keyPair,
    wotsMaster: wotsMaster,
  );
}

KeyMaterial deriveFromPrivateKey(String privateKeyHex) {
  final pair = _ecdsaKeyService.deriveFromPrivateKeyHex(privateKeyHex);
  final wotsMaster = _wotsSeedService.deriveMaster(pair.privateKey);
  return KeyMaterial(
    mnemonic: null,
    seed: null,
    ecdsa: pair,
    wotsMaster: wotsMaster,
  );
}

ECDSAKeyService get ecdsaKeyService => _ecdsaKeyService;
WOTSSeedService get wotsSeedService => _wotsSeedService;
