import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_wallet/state/settings.dart';
import 'support/memory_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final memory = MemoryStore();

  test('settings persistence and gating logic', () async {
    final store = SettingsStore(store: memory);
    var s = await store.load();
    expect(s.biometricOnTestnets, isFalse);
    expect(s.useBiometric, isFalse);
    expect(s.customRpcUrl, isNull);
    expect(s.requireAuthForChain(8453), isTrue);
    expect(s.requireAuthForChain(84532), isFalse);
    s = s.copyWith(
      useBiometric: true,
      biometricOnTestnets: true,
      customRpcUrl: 'https://example-rpc.test',
    );
    await store.save(s);
    var loaded = await store.load();
    expect(loaded.biometricOnTestnets, isTrue);
    expect(loaded.useBiometric, isTrue);
    expect(loaded.customRpcUrl, 'https://example-rpc.test');
    expect(loaded.requireAuthForChain(84532), isTrue);
    expect(loaded.requireAuthForChain(8453), isTrue);
    s = loaded.copyWith(customRpcUrl: null);
    await store.save(s);
    loaded = await store.load();
    expect(loaded.customRpcUrl, isNull);
  });
}
