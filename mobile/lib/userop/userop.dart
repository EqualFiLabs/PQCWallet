import 'dart:typed_data';
import 'package:web3dart/crypto.dart' as w3;

class UserOperation {
  String sender = '';
  BigInt nonce = BigInt.zero;
  Uint8List initCode = Uint8List(0);
  Uint8List callData = Uint8List(0);
  BigInt callGasLimit = BigInt.zero;
  BigInt verificationGasLimit = BigInt.from(150000);
  BigInt preVerificationGas = BigInt.from(50000);
  BigInt maxFeePerGas = BigInt.zero;
  BigInt maxPriorityFeePerGas = BigInt.from(1000000);
  Uint8List paymasterAndData = Uint8List(0);
  Uint8List signature = Uint8List(0);

  Map<String, dynamic> toJson() {
    String hex(Uint8List b) => '0x${w3.bytesToHex(b, include0x: false)}';
    String hexBN(BigInt x) => '0x${x.toRadixString(16)}';
    return {
      'sender': sender,
      'nonce': hexBN(nonce),
      'initCode': hex(initCode),
      'callData': hex(callData),
      'callGasLimit': hexBN(callGasLimit),
      'verificationGasLimit': hexBN(verificationGasLimit),
      'preVerificationGas': hexBN(preVerificationGas),
      'maxFeePerGas': hexBN(maxFeePerGas),
      'maxPriorityFeePerGas': hexBN(maxPriorityFeePerGas),
      'paymasterAndData': hex(paymasterAndData),
      'signature': hex(signature),
    };
  }
}
