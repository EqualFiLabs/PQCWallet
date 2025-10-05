import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_wallet/pqc/attest.dart';

String repeatHex(String b, int count) => '0x' + List.filled(count, b).join();
Uint8List filled(int v) => Uint8List.fromList(List.filled(32, v));

void main() {
  test('golden vectors chainId 5', () {
    final a = Attest(
      userOpHash: filled(0x11),
      wallet: repeatHex('22', 20),
      entryPoint: repeatHex('33', 20),
      chainId: BigInt.from(5),
      pqcSigDigest: filled(0x44),
      currentPkCommit: filled(0x55),
      confirmNextCommit: filled(0x66),
      proposeNextCommit: filled(0x77),
      expiresAt: 0,
      prover: repeatHex('88', 20),
    );

    expect(bytesToHex0x(kAttestTypeHash),
        '0x88a48494697a3fc97814e7b74662ba03cdacb6de8af6b35488b169ff883cbbaf');
    expect(bytesToHex0x(domainSeparator()),
        '0xc14cd710ad09e460310b00ecb570b1cdbcbcb6615a361896ec3945f3f61f16f5');
    expect(bytesToHex0x(hashAttest(a)),
        '0x66e6a29ec5fa4ad7b93260aa0b4b9d4bd0b8a0a40ca42aafdc6168eeceab193d');
  });

  test('digest varies with chainId', () {
    final base = Attest(
      userOpHash: filled(0x11),
      wallet: repeatHex('22', 20),
      entryPoint: repeatHex('33', 20),
      chainId: BigInt.from(5),
      pqcSigDigest: filled(0x44),
      currentPkCommit: filled(0x55),
      confirmNextCommit: filled(0x66),
      proposeNextCommit: filled(0x77),
      expiresAt: 0,
      prover: repeatHex('88', 20),
    );
    final alt = Attest(
      userOpHash: filled(0x11),
      wallet: repeatHex('22', 20),
      entryPoint: repeatHex('33', 20),
      chainId: BigInt.from(84532),
      pqcSigDigest: filled(0x44),
      currentPkCommit: filled(0x55),
      confirmNextCommit: filled(0x66),
      proposeNextCommit: filled(0x77),
      expiresAt: 0,
      prover: repeatHex('88', 20),
    );
    expect(bytesToHex0x(hashAttest(base)),
        '0x66e6a29ec5fa4ad7b93260aa0b4b9d4bd0b8a0a40ca42aafdc6168eeceab193d');
    expect(bytesToHex0x(hashAttest(alt)),
        '0x05bb8b01104c3630af3fcec7dc1bb461777da7326bec6521f22a25ad752dcfb9');
    expect(bytesToHex0x(hashAttest(base)) == bytesToHex0x(hashAttest(alt)),
        isFalse);
  });

  test('asserts on bad bytes32 length', () {
    expect(
      () => Attest(
        userOpHash: Uint8List(31),
        wallet: repeatHex('22', 20),
        entryPoint: repeatHex('33', 20),
        chainId: BigInt.one,
        pqcSigDigest: filled(0x44),
        currentPkCommit: filled(0x55),
        confirmNextCommit: filled(0x66),
        proposeNextCommit: filled(0x77),
        expiresAt: 0,
        prover: repeatHex('88', 20),
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
