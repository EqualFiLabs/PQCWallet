import 'dart:typed_data';

import 'package:web3dart/crypto.dart' as w3crypto;
import 'package:web3dart/web3dart.dart' as w3;

import '../crypto/mnemonic.dart';
import '../services/erc20.dart';
import '../services/rpc.dart';

class EOATransactions {
  final RpcClient rpc;

  EOATransactions({required this.rpc});

  Future<String> sendEth({
    required KeyMaterial keys,
    required String to,
    required BigInt amountWei,
    required int chainId,
  }) {
    return _sendTransaction(
      keys: keys,
      to: to,
      chainId: chainId,
      value: amountWei,
    );
  }

  Future<String> sendTokenTransfer({
    required KeyMaterial keys,
    required int chainId,
    required String tokenAddress,
    required String to,
    required BigInt amount,
  }) {
    final data = Erc20.encodeTransfer(to, amount);
    return _sendTransaction(
      keys: keys,
      to: tokenAddress,
      chainId: chainId,
      data: data,
    );
  }

  Future<String> approveToken({
    required KeyMaterial keys,
    required int chainId,
    required String tokenAddress,
    required String spender,
    required BigInt amount,
  }) {
    final data = Erc20.encodeApprove(spender, amount);
    return _sendTransaction(
      keys: keys,
      to: tokenAddress,
      chainId: chainId,
      data: data,
    );
  }

  Future<String> _sendTransaction({
    required KeyMaterial keys,
    required String to,
    required int chainId,
    BigInt? value,
    Uint8List? data,
  }) async {
    final from = keys.eoaAddress;
    final nonce = await _getNonce(from.hexEip55);
    final priority = await rpc.maxPriorityFeePerGas();
    final baseFee = await _latestBaseFeePerGas();
    final maxFee = baseFee + priority;
    final gasLimit = await _estimateGas(
      from: from.hexEip55,
      to: to,
      value: value,
      data: data,
      maxFeePerGas: maxFee,
      maxPriorityFeePerGas: priority,
    );

    final tx = w3.Transaction(
      from: from,
      to: w3.EthereumAddress.fromHex(to),
      value: value != null ? w3.EtherAmount.inWei(value) : null,
      data: data ?? Uint8List(0),
      maxGas: gasLimit.toInt(),
      nonce: nonce,
      maxFeePerGas: w3.EtherAmount.inWei(maxFee),
      maxPriorityFeePerGas: w3.EtherAmount.inWei(priority),
    );

    final signer = w3.EthPrivateKey(keys.ecdsa.privateKey);
    final signed = w3.signTransactionRaw(tx, signer, chainId: chainId);
    final payload =
        tx.isEIP1559 ? w3.prependTransactionType(0x02, signed) : signed;
    final raw = '0x${w3crypto.bytesToHex(payload, include0x: false)}';
    final result = await rpc.call('eth_sendRawTransaction', [raw]);
    return result.toString();
  }

  Future<int> _getNonce(String address) async {
    final res = await rpc.call('eth_getTransactionCount', [address, 'pending']);
    final hex = res.toString();
    return hex.startsWith('0x')
        ? int.parse(hex.substring(2), radix: 16)
        : int.parse(hex);
  }

  Future<BigInt> _latestBaseFeePerGas() async {
    try {
      final res = await rpc.call('eth_getBlockByNumber', ['latest', false]);
      if (res is Map && res['baseFeePerGas'] != null) {
        final hex = res['baseFeePerGas'].toString();
        if (hex.length > 2) {
          return BigInt.parse(hex.substring(2), radix: 16);
        }
      }
    } catch (_) {
      // Ignore and fall through to zero.
    }
    return BigInt.zero;
  }

  Future<BigInt> _estimateGas({
    required String from,
    required String to,
    BigInt? value,
    Uint8List? data,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
  }) async {
    final payload = <String, dynamic>{
      'from': from,
      'to': to,
      'type': '0x2',
      'maxFeePerGas': _encodeHex(maxFeePerGas),
      'maxPriorityFeePerGas': _encodeHex(maxPriorityFeePerGas),
    };
    if (value != null) {
      payload['value'] = _encodeHex(value);
    }
    if (data != null) {
      payload['data'] = '0x${w3crypto.bytesToHex(data, include0x: false)}';
    }
    final res = await rpc.call('eth_estimateGas', [payload]);
    final hex = res.toString();
    return hex.startsWith('0x')
        ? BigInt.parse(hex.substring(2), radix: 16)
        : BigInt.parse(hex);
  }

  String _encodeHex(BigInt value) {
    if (value <= BigInt.zero) {
      return '0x0';
    }
    return '0x${value.toRadixString(16)}';
  }
}
