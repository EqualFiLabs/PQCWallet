import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:web3dart/credentials.dart';
import 'package:web3dart/crypto.dart' as w3;
import '../crypto/wots.dart';

Uint8List keccak(Uint8List b) => Uint8List.fromList(w3.keccakUtf8(hexNo0x(b)));
String hexNo0x(Uint8List b) => w3.bytesToHex(b, include0x: false);

/// Packs signature = ECDSA(65) || WOTSsig(67*32) || WOTSpk(67*32) || nextCommit(32)
Uint8List packHybridSignature(
  MsgSignature ecdsa,
  List<Uint8List> wotsSig,
  List<Uint8List> wotsPk,
  Uint8List nextCommit,
) {
  final out = BytesBuilder();
  out.add(w3.uint8ListFromList(w3.encodeBigInt(ecdsa.r)));
  out.add(w3.uint8ListFromList(w3.encodeBigInt(ecdsa.s)));
  out.add(Uint8List.fromList([ecdsa.v]));
  for (final s in wotsSig) { out.add(s); }
  for (final p in wotsPk)  { out.add(p); }
  out.add(nextCommit);
  return out.toBytes();
}

/// Derive WOTS per-op seed via HKDF(master, index)
Uint8List hkdfIndex(Uint8List master, int index) {
  final prk = Hmac(sha256, List.filled(32, 0)).convert(master).bytes;
  final info = utf8.encode('WOTS-INDEX-$index');
  var t = <int>[];
  final h = Hmac(sha256, prk).convert([...t, ...info, 1]).bytes;
  return Uint8List.fromList(h.sublist(0, 32));
}
