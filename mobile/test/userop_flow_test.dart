import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/web3dart.dart';
import 'package:pqc_wallet/crypto/mnemonic.dart';
import 'package:pqc_wallet/services/storage.dart';
import 'package:pqc_wallet/userop/userop_flow.dart';
import 'package:pqc_wallet/services/rpc.dart';
import 'package:pqc_wallet/services/bundler_client.dart';
import 'package:pqc_wallet/state/settings.dart';

class MockRpc extends RpcClient {
  int _i = 0;
  MockRpc() : super('');
  @override
  Future<dynamic> call(String method, [dynamic params]) async {
    if (method == 'eth_call') {
      switch (_i++) {
        case 0:
          return '0x1';
        case 1:
          return '0x' + '00' * 32;
        case 2:
          return '0x' + '22' * 32;
        case 3:
          return '0x' + '11' * 32;
        case 4:
          return '0x1';
        case 5:
          return '0x' + '00' * 32;
        case 6:
          return '0x' + '22' * 32;
        default:
          return '0x' + '11' * 32;
      }
    }
    if (method == 'eth_feeHistory') {
      return {
        'baseFeePerGas': ['0x1', '0x1'],
        'reward': [
          ['0x1']
        ]
      };
    }
    if (method == 'eth_maxPriorityFeePerGas') {
      return '0x1';
    }
    throw UnimplementedError();
  }
}

class MockBundler extends BundlerClient {
  MockBundler() : super('');
  @override
  Future<Map<String, dynamic>> estimateUserOpGas(
      Map<String, dynamic> userOp, String entryPoint) async {
    return {
      'callGasLimit': '0x1',
      'verificationGasLimit': '0x1',
      'preVerificationGas': '0x1',
    };
  }

  @override
  Future<String> sendUserOperation(
      Map<String, dynamic> userOp, String entryPoint) async {
    return '0xdead';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  test('reuses hybrid signature when userOpHash unchanged', () async {
    final rpc = MockRpc();
    final bundler = MockBundler();
    final store = PendingIndexStore();
    final keys = deriveFromMnemonic(null);
    final cfg = {
      'chainId': 1,
      'walletAddress': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'entryPoint': '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    };
    final flow = UserOpFlow(rpc: rpc, bundler: bundler, store: store);
    final to =
        EthereumAddress.fromHex('0xcccccccccccccccccccccccccccccccccccccccc');
    final logs = <String>[];
    await flow.sendEth(
      cfg: cfg,
      keys: keys,
      to: to,
      amountWei: BigInt.one,
      settings: const AppSettings(),
      ensureAuthorized: (_) async => true,
      log: logs.add,
      selectFees: (f) async => f,
    );
    final first = logs.last;
    logs.clear();
    await flow.sendEth(
      cfg: cfg,
      keys: keys,
      to: to,
      amountWei: BigInt.one,
      settings: const AppSettings(),
      ensureAuthorized: (_) async => true,
      log: logs.add,
      selectFees: (f) async => f,
    );
    final second = logs.last;
    expect(first.contains('decision: fresh'), isTrue);
    expect(second.contains('decision: reuse'), isTrue);
  });
}
