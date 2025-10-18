import 'dart:typed_data';
import 'package:web3dart/contracts.dart';
import 'package:web3dart/web3dart.dart' as w3;
import 'package:web3dart/crypto.dart' as w3c;

import 'rpc.dart';
import '../userop/userop.dart';

class EntryPointService {
  EntryPointService(this.rpc, this.entryPoint);
  final RpcClient rpc;
  final w3.EthereumAddress entryPoint;

  static const _fnGetUserOpHash = ContractFunction(
    'getUserOpHash',
    [
      FunctionParameter(
          'op',
          TupleType([
            AddressType(),
            UintType(),
            DynamicBytes(),
            DynamicBytes(),
            UintType(),
            UintType(),
            UintType(),
            UintType(),
            UintType(),
            DynamicBytes(),
            DynamicBytes(),
          ]))
    ],
    outputs: [FunctionParameter('', FixedBytes(32))],
  );

  List<dynamic> _encodeOpForAbi(UserOperation op) => [
        w3.EthereumAddress.fromHex(op.sender),
        op.nonce,
        op.initCode,
        op.callData,
        op.callGasLimit,
        op.verificationGasLimit,
        op.preVerificationGas,
        op.maxFeePerGas,
        op.maxPriorityFeePerGas,
        op.paymasterAndData,
        op.signature,
      ];

  Future<Uint8List> getUserOpHash(UserOperation op) async {
    final data = _fnGetUserOpHash.encodeCall([
      _encodeOpForAbi(op),
    ]);
    final hex =
        await rpc.callViewHex(entryPoint.hex, '0x${w3c.bytesToHex(data)}');
    final raw = w3c.hexToBytes(hex);
    return raw.length == 32
        ? raw
        : Uint8List.fromList(raw.sublist(raw.length - 32));
  }
}
