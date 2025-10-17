import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/credentials.dart';
import 'package:web3dart/crypto.dart' as w3;

import 'package:pqc_wallet/walletconnect/wc_signer.dart';

void main() {
  group('WcSigner typed data parity', () {
    const privateKey =
        '0x59c6995e998f97a5a0044966f0945388cf9f7b78a0b21b1b2de54c2d343f8f5b';
    final signer = WcSigner(
      credentials: EthPrivateKey.fromHex(
        privateKey.startsWith('0x') ? privateKey.substring(2) : privateKey,
      ),
    );

    test('matches DAI permit digest and signature', () async {
      final payload = <String, dynamic>{
        'primaryType': 'Permit',
        'types': {
          'EIP712Domain': [
            {'name': 'name', 'type': 'string'},
            {'name': 'version', 'type': 'string'},
            {'name': 'chainId', 'type': 'uint256'},
            {'name': 'verifyingContract', 'type': 'address'},
          ],
          'Permit': [
            {'name': 'holder', 'type': 'address'},
            {'name': 'spender', 'type': 'address'},
            {'name': 'nonce', 'type': 'uint256'},
            {'name': 'expiry', 'type': 'uint256'},
            {'name': 'allowed', 'type': 'bool'},
          ],
        },
        'domain': {
          'name': 'Dai Stablecoin',
          'version': '1',
          'chainId': 1,
          'verifyingContract':
              '0x6B175474E89094C44Da98b954EedeAC495271d0F',
        },
        'message': {
          'holder': '0x0dCD2F752394c41875e259e00Bb44fd505297caf',
          'spender': '0x8b3b3b624c3c0397d3Da8fD861512393d51dcbAc',
          'nonce': '1',
          'expiry': '1630540800',
          'allowed': true,
        },
      };

      final typedData = signer.parseTypedDataPayload(payload);
      expect(
        w3.bytesToHex(signer.hashDomain(typedData), include0x: true),
        '0xdbb8cf42e1ecb028be3f3dbc922e1d878b963f411dc388ced501601c60f7c6f7',
      );
      expect(
        w3.bytesToHex(
          signer.hashStruct(typedData, typedData.message),
          include0x: true,
        ),
        '0x4d7a5d4823817dede6c51c811d786f85e7ca73a70a5c940f76c98dad576545e3',
      );
      expect(
        w3.bytesToHex(signer.typedDataDigest(typedData), include0x: true),
        '0xf2b6f844d9edce7eed68d96a3008c5ac6c52ce7f7cff5a9e5646f4bcdfdbd893',
      );

      final signature = await signer.signTypedData(payload);
      expect(
        w3.bytesToHex(signature, include0x: true),
        '0xfe62e1bdc2bc6a3dd6bcabaae2cda9b30b3da65a89aa20f9ada5465e2109a6e50bfbd9ab986503e04ca6af79a258536d46455e866b356f70cdc74e2f460e20101b',
      );
    });

    test('matches Permit2 single digest and signature', () async {
      final payload = <String, dynamic>{
        'primaryType': 'PermitSingle',
        'types': {
          'EIP712Domain': [
            {'name': 'name', 'type': 'string'},
            {'name': 'chainId', 'type': 'uint256'},
            {'name': 'verifyingContract', 'type': 'address'},
          ],
          'PermitDetails': [
            {'name': 'token', 'type': 'address'},
            {'name': 'amount', 'type': 'uint160'},
            {'name': 'expiration', 'type': 'uint48'},
            {'name': 'nonce', 'type': 'uint48'},
          ],
          'PermitSingle': [
            {'name': 'details', 'type': 'PermitDetails'},
            {'name': 'spender', 'type': 'address'},
            {'name': 'sigDeadline', 'type': 'uint256'},
          ],
        },
        'domain': {
          'name': 'Permit2',
          'chainId': 1,
          'verifyingContract':
              '0x000000000022D473030F116dDEE9F6B43aC78BA3',
        },
        'message': {
          'details': {
            'token': '0x0000000000000000000000000000000000000000',
            'amount': '0',
            'expiration': '0',
            'nonce': '0',
          },
          'spender': '0x0000000000000000000000000000000000000000',
          'sigDeadline': '0',
        },
      };

      final typedData = signer.parseTypedDataPayload(payload);
      expect(
        w3.bytesToHex(signer.hashDomain(typedData), include0x: true),
        '0x866a5aba21966af95d6c7ab78eb2b2fc913915c28be3b9aa07cc04ff903e3f28',
      );
      expect(
        w3.bytesToHex(
          signer.hashStruct(typedData, typedData.message),
          include0x: true,
        ),
        '0x40770b4a495478dcbf594acbe0d66264beea8856aebc591a588a2d44b681fbc9',
      );
      expect(
        w3.bytesToHex(signer.typedDataDigest(typedData), include0x: true),
        '0xb7e3db6deb96bb5a33fdc9d498765970c23c50c5eccd82c43d4ba1e6155a7060',
      );

      final signature = await signer.signTypedData(payload);
      expect(
        w3.bytesToHex(signature, include0x: true),
        '0x27b0656ebdc2c6128a724642d4d27e59d637a2cf76d82721b07e7878dae5c8735934122ce6a37482fe9d4db3a20f539f049e4ff6b0eb915ceb411858a88c38631b',
      );
    });

    test('matches Permit2 batch digest and signature', () async {
      final payload = <String, dynamic>{
        'primaryType': 'PermitBatch',
        'types': {
          'EIP712Domain': [
            {'name': 'name', 'type': 'string'},
            {'name': 'chainId', 'type': 'uint256'},
            {'name': 'verifyingContract', 'type': 'address'},
          ],
          'PermitDetails': [
            {'name': 'token', 'type': 'address'},
            {'name': 'amount', 'type': 'uint160'},
            {'name': 'expiration', 'type': 'uint48'},
            {'name': 'nonce', 'type': 'uint48'},
          ],
          'PermitBatch': [
            {'name': 'details', 'type': 'PermitDetails[]'},
            {'name': 'spender', 'type': 'address'},
            {'name': 'sigDeadline', 'type': 'uint256'},
          ],
        },
        'domain': {
          'name': 'Permit2',
          'chainId': 1,
          'verifyingContract':
              '0x000000000022D473030F116dDEE9F6B43aC78BA3',
        },
        'message': {
          'details': [
            {
              'token': '0x0000000000000000000000000000000000000000',
              'amount': '0',
              'expiration': '0',
              'nonce': '0',
            },
            {
              'token': '0x0000000000000000000000000000000000000001',
              'amount': '1',
              'expiration': '1',
              'nonce': '1',
            },
          ],
          'spender': '0x1111111111111111111111111111111111111111',
          'sigDeadline': '0',
        },
      };

      final typedData = signer.parseTypedDataPayload(payload);
      expect(
        w3.bytesToHex(signer.hashDomain(typedData), include0x: true),
        '0x866a5aba21966af95d6c7ab78eb2b2fc913915c28be3b9aa07cc04ff903e3f28',
      );
      expect(
        w3.bytesToHex(
          signer.hashStruct(typedData, typedData.message),
          include0x: true,
        ),
        '0x53b68b7bdc881a68a8477f9d2dd62ae0d3b7d2041d4a0ad1a56e749ca7df4d40',
      );
      expect(
        w3.bytesToHex(signer.typedDataDigest(typedData), include0x: true),
        '0x38ed0d820102dd7784578d00fbeb4439817abe261ba98af45760eb9d5c9f634b',
      );

      final signature = await signer.signTypedData(payload);
      expect(
        w3.bytesToHex(signature, include0x: true),
        '0x637340dc6e13ff7644d215948ce2863db3e5ee7e39661447a295946a0925380c1d552b6d6cc9abad5aa4a67e2fb843a70e4a5a83991e1b85f2f9f7463664cdb51c',
      );
    });
  });
}
