import 'dart:convert';
import 'package:bip39/bip39.dart' as bip39;
import 'package:bip32/bip32.dart' as bip32;
import 'package:crypto/crypto.dart';
import 'dart:typed_data';

class KeyMaterial {
  final String mnemonic;
  final List<int> seed; // BIP39 seed
  final List<int> ecdsaPriv; // secp256k1 private key (32 bytes)
  final List<int> wotsMaster; // HKDF-derived WOTS master seed (32 bytes)

  KeyMaterial(this.mnemonic, this.seed, this.ecdsaPriv, this.wotsMaster);
}

KeyMaterial deriveFromMnemonic(String? existing) {
  final mnemonic =
      existing ?? bip39.generateMnemonic(strength: 128); // 12 words
  final seed = bip39.mnemonicToSeed(mnemonic);
  // Derive BIP32 path m/44'/60'/0'/0/0 for EVM
  final root = bip32.BIP32.fromSeed(Uint8List.fromList(seed));
  final child = root.derivePath("m/44'/60'/0'/0/0");
  final ecdsaPriv = child.privateKey!;
  // WOTS master via HKDF-SHA256 with domain separation
  final wotsMaster = hkdfSha256(ecdsaPriv, utf8.encode("WOTS"), 32);
  return KeyMaterial(mnemonic, seed, ecdsaPriv, wotsMaster);
}

List<int> hkdfSha256(List<int> ikm, List<int> info, int len) {
  final prk = Hmac(sha256, List.filled(32, 0)).convert(ikm).bytes;
  List<int> out = [];
  List<int> t = [];
  int i = 1;
  while (out.length < len) {
    final h = Hmac(sha256, prk).convert([...t, ...info, i]).bytes;
    out.addAll(h);
    t = h;
    i++;
  }
  return out.sublist(0, len);
}
