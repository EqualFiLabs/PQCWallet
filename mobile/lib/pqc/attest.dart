import 'dart:typed_data';

import 'package:web3dart/crypto.dart' as w3;
import 'package:web3dart/web3dart.dart';

/// Attest data used for off-chain PQC verification.
///
/// Must match Solidity (Prover PR-1).
class Attest {
  final Uint8List userOpHash;
  final EthereumAddress wallet;
  final EthereumAddress entryPoint;
  final BigInt chainId;
  final Uint8List pqcSigDigest;
  final Uint8List currentPkCommit;
  final Uint8List confirmNextCommit;
  final Uint8List proposeNextCommit;
  final BigInt expiresAt; // uint64
  final EthereumAddress prover;

  Attest({
    required this.userOpHash,
    required this.wallet,
    required this.entryPoint,
    required this.chainId,
    required this.pqcSigDigest,
    required this.currentPkCommit,
    required this.confirmNextCommit,
    required this.proposeNextCommit,
    required this.expiresAt,
    required this.prover,
  }) {
    assert(userOpHash.length == 32);
    assert(pqcSigDigest.length == 32);
    assert(currentPkCommit.length == 32);
    assert(confirmNextCommit.length == 32);
    assert(proposeNextCommit.length == 32);
  }
}

/// Locked EIP-712 domain name.
const String kEip712Name = 'EqualFiPQCProver';

/// Locked EIP-712 domain version.
const String kEip712Version = '1';

/// Locked Attest type string.
const String kAttestTypeString =
    'Attest(bytes32 userOpHash,address wallet,address entryPoint,uint256 chainId,bytes32 pqcSigDigest,bytes32 currentPkCommit,bytes32 confirmNextCommit,bytes32 proposeNextCommit,uint64 expiresAt,address prover)';

/// Locked domain type string.
const String kDomainTypeString = 'EIP712Domain(string name,string version)';

/// Convert a hex string to a 32-byte array.
Uint8List hexToBytes32(String hex) {
  final b = w3.hexToBytes(hex);
  if (b.length != 32) {
    throw ArgumentError('expected 32 bytes');
  }
  return Uint8List.fromList(b);
}

/// Convert bytes to a 0x-prefixed hex string.
String bytesToHex0x(Uint8List data) => w3.bytesToHex(data, include0x: true);

/// keccak256 of [kAttestTypeString].
Uint8List typeHashAttest() => w3.keccakUtf8(kAttestTypeString);

/// keccak256 of [kDomainTypeString].
Uint8List typeHashDomain() => w3.keccakUtf8(kDomainTypeString);

/// Domain separator using name+version only.
Uint8List domainSeparator() {
  final encoder = const TupleType([
    FixedBytes(32),
    FixedBytes(32),
    FixedBytes(32),
  ]);
  final sink = LengthTrackingByteSink();
  encoder.encode([
    typeHashDomain(),
    w3.keccakUtf8(kEip712Name),
    w3.keccakUtf8(kEip712Version),
  ], sink);
  return w3.keccak256(sink.asBytes());
}

/// Struct hash per EIP-712.
Uint8List structHash(Attest a) {
  final encoder = const TupleType([
    FixedBytes(32),
    FixedBytes(32),
    AddressType(),
    AddressType(),
    UintType(),
    FixedBytes(32),
    FixedBytes(32),
    FixedBytes(32),
    FixedBytes(32),
    UintType(length: 64),
    AddressType(),
  ]);
  final sink = LengthTrackingByteSink();
  encoder.encode([
    typeHashAttest(),
    a.userOpHash,
    a.wallet,
    a.entryPoint,
    a.chainId,
    a.pqcSigDigest,
    a.currentPkCommit,
    a.confirmNextCommit,
    a.proposeNextCommit,
    a.expiresAt,
    a.prover,
  ], sink);
  return w3.keccak256(sink.asBytes());
}

/// Final EIP-191 digest (0x1901 || domainSeparator || structHash).
Uint8List hashAttest(Attest a) {
  final ds = domainSeparator();
  final sh = structHash(a);
  final out = Uint8List(2 + ds.length + sh.length);
  out.setRange(0, 2, const [0x19, 0x01]);
  out.setRange(2, 2 + ds.length, ds);
  out.setRange(2 + ds.length, out.length, sh);
  return w3.keccak256(out);
}
