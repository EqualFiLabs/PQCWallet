import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_wallet/services/storage.dart';
import 'support/memory_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final memory = MemoryStore();

  test('save/load/clear pending index record', () async {
    final store = PendingIndexStore(store: memory);
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
