import 'dart:typed_data';
import 'package:web3dart/contracts.dart';
import 'package:web3dart/web3dart.dart' as w3;

class Erc20 {
  static final _fnTransfer = ContractFunction(
    'transfer',
    [
      FunctionParameter('to', AddressType()),
      FunctionParameter('amount', UintType())
    ],
    outputs: [FunctionParameter('', BoolType())],
  );

  static final _fnApprove = ContractFunction(
    'approve',
    [
      FunctionParameter('spender', AddressType()),
      FunctionParameter('amount', UintType())
    ],
    outputs: [FunctionParameter('', BoolType())],
  );

  static final _fnPermit = ContractFunction(
    'permit',
    [
      FunctionParameter('owner', AddressType()),
      FunctionParameter('spender', AddressType()),
      FunctionParameter('value', UintType()),
      FunctionParameter('deadline', UintType()),
      FunctionParameter('v', UintType(length: 8)),
      FunctionParameter('r', FixedBytes(32)),
      FunctionParameter('s', FixedBytes(32)),
    ],
    outputs: const [],
  );

  static Uint8List encodeTransfer(String to, BigInt amount) =>
      _fnTransfer.encodeCall([
        w3.EthereumAddress.fromHex(to),
        amount,
      ]);

  static Uint8List encodeApprove(String spender, BigInt amount) =>
      _fnApprove.encodeCall([
        w3.EthereumAddress.fromHex(spender),
        amount,
      ]);

  static Uint8List encodePermit({
    required String owner,
    required String spender,
    required BigInt value,
    required BigInt deadline,
    required int v,
    required Uint8List r,
    required Uint8List s,
  }) =>
      _fnPermit.encodeCall([
        w3.EthereumAddress.fromHex(owner),
        w3.EthereumAddress.fromHex(spender),
        value,
        deadline,
        BigInt.from(v),
        r,
        s,
      ]);
}

class Permit2 {
  // Placeholder for future Permit2 encoders
}
