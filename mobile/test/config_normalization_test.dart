import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_wallet/services/app_config.dart';

void main() {
  test('normalizes entryPointAddr alias and fills optional fields', () {
    final raw = {
      'rpcUrl': 'https://rpc.example',
      'bundlerUrl': 'https://bundler.example',
      'entryPointAddr': '0xEntry',
      // chainId missing on purpose
    };

    final cfg = normalizeAppConfig(raw);

    expect(cfg['entryPoint'], '0xEntry');
    expect(cfg['chainId'], isNull); // still null, but present
    expect(cfg.containsKey('aggregator'), isTrue);
    expect(cfg.containsKey('proverRegistry'), isTrue);
    expect(cfg.containsKey('forceOnChainVerify'), isTrue);
    expect(cfg['rpcUrl'], 'https://rpc.example');
    expect(cfg['bundlerUrl'], 'https://bundler.example');
  });

  test('coerces string chainId to int', () {
    final raw = {'chainId': '84532'};
    final cfg = normalizeAppConfig(raw);
    expect(cfg['chainId'], 84532);
  });
}
