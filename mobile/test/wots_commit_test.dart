import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_wallet/crypto/wots.dart';

void main() {
  test('commitPk matches Solidity reference', () {
    final pk = List<Uint8List>.generate(67, (i) => Uint8List(32)..[31] = i);
    final commit = Wots.commitPk(pk);
    final expected = Uint8List.fromList([
      0x76,
      0x5d,
      0x90,
      0xc3,
      0xc6,
      0x81,
      0x03,
      0x59,
      0x23,
      0xf5,
      0xdf,
      0x77,
      0x60,
      0xce,
      0xde,
      0xa6,
      0x8e,
      0xbd,
      0x2d,
      0x97,
      0x7f,
      0xc2,
      0x2a,
      0x37,
      0x52,
      0x83,
      0x91,
      0x04,
      0xc6,
      0xb3,
      0x31,
      0x76,
    ]);
    expect(commit, expected);
  });
}
