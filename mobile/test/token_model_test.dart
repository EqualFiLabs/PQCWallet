import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_wallet/models/token.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('loads token registry', () async {
    final registry = await ChainTokens.load();
    expect(registry.chainIdBaseSepolia(), 84532);
    final addr = registry.tokenAddress('USDC', 84532);
    expect(addr, isNotNull);
  });
}
