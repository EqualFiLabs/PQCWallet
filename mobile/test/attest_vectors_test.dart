import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/web3dart.dart';
import 'package:pqc_wallet/pqc/attest.dart';

String repeatHex(String b, int count) => '0x' + List.filled(count, b).join();
Uint8List filled(int v) => Uint8List.fromList(List.filled(32, v));

void main() {
  test('golden vectors chainId 1', () {
    final a = Attest(
      userOpHash: filled(0x11),
      wallet: EthereumAddress.fromHex(repeatHex('22', 20)),
      entryPoint: EthereumAddress.fromHex(repeatHex('33', 20)),
      chainId: BigInt.one,
      pqcSigDigest: filled(0x44),
      currentPkCommit: filled(0x55),
      confirmNextCommit: filled(0x66),
      proposeNextCommit: filled(0x77),
      expiresAt: BigInt.from(255),
      prover: EthereumAddress.fromHex(repeatHex('88', 20)),
    );

    expect(bytesToHex0x(typeHashAttest()),
        '0x88a48494697a3fc97814e7b74662ba03cdacb6de8af6b35488b169ff883cbbaf');
    expect(bytesToHex0x(typeHashDomain()),
        '0xb03948446334eb9b2196d5eb166f69b9d49403eb4a12f36de8d3f9f3cb8e15c3');
    expect(bytesToHex0x(domainSeparator()),
        '0xc14cd710ad09e460310b00ecb570b1cdbcbcb6615a361896ec3945f3f61f16f5');
    expect(bytesToHex0x(structHash(a)),
        '0xbc8a677d8deb4c7fbc81b5ef297630b0f5ee5ff784f80c1d0575c89e3fcdaa09');
    expect(bytesToHex0x(hashAttest(a)),
        '0x145acc78f427b0e4b235011aa9d08a2fdf05f1d202dd8fa6faa19a7930760d57');
  });

  test('digest varies with chainId', () {
    final base = Attest(
      userOpHash: filled(0x11),
      wallet: EthereumAddress.fromHex(repeatHex('22', 20)),
      entryPoint: EthereumAddress.fromHex(repeatHex('33', 20)),
      chainId: BigInt.one,
      pqcSigDigest: filled(0x44),
      currentPkCommit: filled(0x55),
      confirmNextCommit: filled(0x66),
      proposeNextCommit: filled(0x77),
      expiresAt: BigInt.from(255),
      prover: EthereumAddress.fromHex(repeatHex('88', 20)),
    );
    final alt = Attest(
      userOpHash: filled(0x11),
      wallet: EthereumAddress.fromHex(repeatHex('22', 20)),
      entryPoint: EthereumAddress.fromHex(repeatHex('33', 20)),
      chainId: BigInt.from(84532),
      pqcSigDigest: filled(0x44),
      currentPkCommit: filled(0x55),
      confirmNextCommit: filled(0x66),
      proposeNextCommit: filled(0x77),
      expiresAt: BigInt.from(255),
      prover: EthereumAddress.fromHex(repeatHex('88', 20)),
    );
    expect(bytesToHex0x(hashAttest(base)),
        '0x145acc78f427b0e4b235011aa9d08a2fdf05f1d202dd8fa6faa19a7930760d57');
    expect(bytesToHex0x(hashAttest(alt)),
        '0x3776a33119e6b6ba8305615e820dc2deb3bed46dfd68fc0ac6bca29cf23c7288');
    expect(bytesToHex0x(hashAttest(base)) == bytesToHex0x(hashAttest(alt)),
        isFalse);
  });

  test('asserts on bad bytes32 length', () {
    expect(
      () => Attest(
        userOpHash: Uint8List(31),
        wallet: EthereumAddress.fromHex(repeatHex('22', 20)),
        entryPoint: EthereumAddress.fromHex(repeatHex('33', 20)),
        chainId: BigInt.one,
        pqcSigDigest: filled(0x44),
        currentPkCommit: filled(0x55),
        confirmNextCommit: filled(0x66),
        proposeNextCommit: filled(0x77),
        expiresAt: BigInt.zero,
        prover: EthereumAddress.fromHex(repeatHex('88', 20)),
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
