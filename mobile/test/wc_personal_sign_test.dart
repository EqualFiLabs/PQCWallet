import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/credentials.dart';
import 'package:web3dart/crypto.dart' as w3;
import 'package:web3dart/web3dart.dart';

import 'package:pqc_wallet/services/rpc.dart';
import 'package:pqc_wallet/walletconnect/wc_signer.dart';

class _StubRpcClient extends RpcClient {
  _StubRpcClient() : super('http://localhost');

  @override
  Future<dynamic> call(String method, [dynamic params]) {
    throw UnsupportedError('RPC not available: $method');
  }
}

void main() {
  group('WcSigner message signing', () {
    const privateKey =
        '0x59c6995e998f97a5a0044966f0945388cf9f7b78a0b21b1b2de54c2d343f8f5b';
    final credentials = EthPrivateKey.fromHex(privateKey.substring(2));
    final signer = WcSigner(
      credentials: credentials,
      rpcClient: _StubRpcClient(),
    );

    test('personal_sign applies prefix and recovers signer address', () async {
      const message = 'EqualFi <> WalletConnect';
      final signatureHex = await signer.personalSign(message);
      expect(signatureHex.startsWith('0x'), isTrue);
      expect(signatureHex, signatureHex.toLowerCase());

      final signatureBytes = w3.hexToBytes(signatureHex);
      expect(signatureBytes, hasLength(65));
      final r = w3.bytesToUnsignedInt(signatureBytes.sublist(0, 32));
      final s = w3.bytesToUnsignedInt(signatureBytes.sublist(32, 64));
      final v = signatureBytes[64];
      final signature = w3.MsgSignature(r, s, v);

      final messageBytes = Uint8List.fromList(utf8.encode(message));
      final prefix = Uint8List.fromList(utf8.encode(
        '${String.fromCharCode(0x19)}Ethereum Signed Message:\n${messageBytes.length}',
      ));
      final prefixed = Uint8List(prefix.length + messageBytes.length)
        ..setRange(0, prefix.length, prefix)
        ..setRange(prefix.length, prefix.length + messageBytes.length, messageBytes);
      final digest = w3.keccak256(prefixed);

      final recovered = w3.ecRecover(digest, signature);
      final recoveredAddress = EthereumAddress.fromPublicKey(recovered);
      final expectedAddress = (await signer.address).hexEip55.toLowerCase();
      expect(recoveredAddress.hexEip55.toLowerCase(), expectedAddress);

      final unprefixedDigest = w3.keccak256(messageBytes);
      final wrongRecovered = EthereumAddress.fromPublicKey(
        w3.ecRecover(unprefixedDigest, signature),
      );
      expect(wrongRecovered.hexEip55.toLowerCase(), isNot(expectedAddress));
    });

    test('eth_sign produces recoverable raw digest signature', () async {
      const payloadHex = '0x68656c6c6f207175616e74756d';
      final signatureHex = await signer.ethSign(payloadHex);
      expect(signatureHex.startsWith('0x'), isTrue);
      expect(signatureHex, signatureHex.toLowerCase());

      final signatureBytes = w3.hexToBytes(signatureHex);
      final r = w3.bytesToUnsignedInt(signatureBytes.sublist(0, 32));
      final s = w3.bytesToUnsignedInt(signatureBytes.sublist(32, 64));
      final v = signatureBytes[64];
      final signature = w3.MsgSignature(r, s, v);

      final digest = w3.keccak256(w3.hexToBytes(payloadHex));
      final recovered = EthereumAddress.fromPublicKey(
        w3.ecRecover(digest, signature),
      );
      final expectedAddress = (await signer.address).hexEip55.toLowerCase();
      expect(recovered.hexEip55.toLowerCase(), expectedAddress);
    });
  });
}
