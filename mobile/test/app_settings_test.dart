import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_wallet/state/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  test('settings persistence and gating logic', () async {
    final store = SettingsStore();
    var s = await store.load();
    expect(s.biometricOnTestnets, isFalse);
    expect(s.useBiometric, isFalse);
    expect(s.requireAuthForChain(8453), isTrue);
    expect(s.requireAuthForChain(84532), isFalse);
    s = s.copyWith(useBiometric: true, biometricOnTestnets: true);
    await store.save(s);
    final loaded = await store.load();
    expect(loaded.biometricOnTestnets, isTrue);
    expect(loaded.useBiometric, isTrue);
    expect(loaded.requireAuthForChain(84532), isTrue);
    expect(loaded.requireAuthForChain(8453), isTrue);
  });
}
