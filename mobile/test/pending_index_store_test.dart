import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_wallet/services/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  test('save/load/clear pending index record', () async {
    final store = PendingIndexStore();
    final chainId = 1;
    final wallet = '0xabc';
    final data = {'version': 1, 'foo': 'bar'};
    await store.save(chainId, wallet, data);
    final loaded = await store.load(chainId, wallet);
    expect(loaded, isNotNull);
    expect(loaded!['foo'], 'bar');
    await store.clear(chainId, wallet);
    final cleared = await store.load(chainId, wallet);
    expect(cleared, isNull);
  });
}
