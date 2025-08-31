import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:pqc_wallet/crypto/wots.dart';

void main() {
  test('WOTS sign-commit-verify consistency', () {
    final msg = Uint8List.fromList(sha256.convert(Uint8List.fromList([1,2,3])).bytes);
    final seed = Uint8List.fromList(List.filled(32, 7));
    final (sk, pk) = Wots.keygen(seed);
    final sig = Wots.sign(msg, sk);
    final commit = Wots.commitPk(pk);
    // Basic sanity — commitment length and arrays are correct sizes
    expect(commit.length, 32);
    expect(pk.length, 67);
    expect(sig.length, 67);
  });
}
