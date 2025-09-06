import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_wallet/userop/userop_signer.dart';
import 'package:web3dart/crypto.dart' as w3;

Uint8List filled(int len, int v) =>
    Uint8List.fromList(List<int>.filled(len, v));

void main() {
  const int ecdsaLen = 65;
  const int wotsSegLen = 67 * 32; // 2144
  const int commitLen = 32;
  const int hybridLen =
      ecdsaLen + wotsSegLen + wotsSegLen + commitLen + commitLen; // 4417
  const int legacyNoCommits = ecdsaLen + wotsSegLen + wotsSegLen; // 4353
  const int legacyOneCommit = legacyNoCommits + commitLen; // 4385

  group('packHybridSignature', () {
    test('produces 4417 bytes with correct section order', () {
      final wotsSig = List.generate(67, (_) => filled(32, 0xBB));
      final wotsPk = List.generate(67, (_) => filled(32, 0xCC));
      final confirmNextCommit =
          Uint8List.fromList(List<int>.generate(32, (i) => i));
      final proposeNextCommit =
          Uint8List.fromList(List<int>.generate(32, (i) => 0xFF - i));

      final sig = packHybridSignature(
        w3.MsgSignature(BigInt.zero, BigInt.zero, 0),
        wotsSig,
        wotsPk,
        confirmNextCommit,
        proposeNextCommit,
      );

      expect(sig.length, hybridLen);

      final wotsSigStart = ecdsaLen;
      final wotsPkStart = wotsSigStart + wotsSegLen;
      final confirmStart = wotsPkStart + wotsSegLen;
      final proposeStart = confirmStart + commitLen;

      expect(sig.sublist(wotsSigStart, wotsPkStart), filled(wotsSegLen, 0xBB));
      expect(sig.sublist(wotsPkStart, confirmStart), filled(wotsSegLen, 0xCC));
      expect(sig.sublist(confirmStart, confirmStart + commitLen),
          confirmNextCommit);
      expect(sig.sublist(proposeStart, proposeStart + commitLen),
          proposeNextCommit);
    });

    test('explicit length check can be performed client-side as a fast-fail',
        () {
      bool isHybrid4417(Uint8List sig) => sig.length == hybridLen;
      expect(isHybrid4417(Uint8List(hybridLen)), isTrue);
      expect(isHybrid4417(Uint8List(legacyNoCommits)), isFalse);
      expect(isHybrid4417(Uint8List(legacyOneCommit)), isFalse);
    });
  });
}
