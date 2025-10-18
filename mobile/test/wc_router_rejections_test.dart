import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reown_walletkit/reown_walletkit.dart';

import 'package:pqc_wallet/walletconnect/wc_client.dart';
import 'package:pqc_wallet/services/rpc.dart';
import 'package:pqc_wallet/walletconnect/wc_session_store.dart';
import 'package:pqc_wallet/walletconnect/wc_router.dart';
import 'package:pqc_wallet/walletconnect/wc_signer.dart';
import 'support/memory_store.dart';

class _StubRpcClient extends RpcClient {
  _StubRpcClient() : super('http://localhost');

  @override
  Future<dynamic> call(String method, [dynamic params]) {
    throw UnsupportedError('RPC not available: $method');
  }
}

Future<SessionData> _buildSession(WcSigner signer, int chainId) async {
  final address = (await signer.address).hexEip55;
  final accountId = 'eip155:$chainId:${address.toLowerCase()}';
  const metadata = PairingMetadata(name: 'app', description: '');
  const connection = ConnectionMetadata(publicKey: '0xabc', metadata: metadata);
  return SessionData(
    topic: 'topic',
    pairingTopic: 'pairing',
    relay: Relay('irn'),
    expiry:
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
            1000,
    acknowledged: true,
    controller: address,
    namespaces: {
      'eip155': Namespace(
        accounts: [accountId],
        methods: const [
          'personal_sign',
          'eth_sign',
          'eth_signTypedData',
          'eth_signTypedData_v4',
          'eth_sendTransaction',
          'eth_signTransaction',
        ],
        events: const [],
      ),
    },
    self: connection,
    peer: connection,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final wcClient = WcClient(
    sessionStore: WcSessionStore(
      storage: MemoryStore(),
      storageKey: 'test.wc.sessions',
    ),
    navigatorKey: GlobalKey<NavigatorState>(),
  );
  final router = WcRouter(client: wcClient);

  group('WcRouter rejections', () {
    const privateKey =
        '0x59c6995e998f97a5a0044966f0945388cf9f7b78a0b21b1b2de54c2d343f8f5b';
    final credentials = EthPrivateKey.fromHex(privateKey.substring(2));
    final signer = WcSigner(
      credentials: credentials,
      rpcClient: _StubRpcClient(),
    );

    test('rejects requests for unauthorized chains', () async {
      final session = await _buildSession(signer, 1);
      final request = SessionRequestEvent(
        1,
        session.topic,
        'personal_sign',
        'eip155:10',
        ['0x68656c6c6f', (await signer.address).hexEip55],
        TransportType.relay,
      );
      final response = await router.dispatch(
        event: request,
        session: session,
        signers: {1: signer},
      );
      expect(response.error?.code, 4001);
    });

    test('rejects mismatched from addresses', () async {
      final session = await _buildSession(signer, 1);
      final request = SessionRequestEvent(
        2,
        session.topic,
        'eth_sign',
        'eip155:1',
        ['0x0000000000000000000000000000000000000001', '0x01'],
        TransportType.relay,
      );
      final response = await router.dispatch(
        event: request,
        session: session,
        signers: {1: signer},
      );
      expect(response.error?.code, 4001);
    });

    test('rejects malformed parameter payloads', () async {
      final session = await _buildSession(signer, 1);
      final request = SessionRequestEvent(
        3,
        session.topic,
        'eth_sendTransaction',
        'eip155:1',
        'not-a-list',
        TransportType.relay,
      );
      final response = await router.dispatch(
        event: request,
        session: session,
        signers: {1: signer},
      );
      expect(response.error?.code, 4001);
    });

    test('rejects when no signer is available for chain', () async {
      final session = await _buildSession(signer, 1);
      final request = SessionRequestEvent(
        4,
        session.topic,
        'eth_signTransaction',
        'eip155:1',
        [
          {
            'from': (await signer.address).hexEip55,
            'to': (await signer.address).hexEip55,
            'value': '0x0',
          }
        ],
        TransportType.relay,
      );
      final response = await router.dispatch(
        event: request,
        session: session,
        signers: const {},
      );
      expect(response.error?.code, 4001);
    });
  });
}
