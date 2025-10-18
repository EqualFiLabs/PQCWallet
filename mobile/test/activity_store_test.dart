import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pqc_wallet/models/activity.dart';
import 'package:pqc_wallet/services/activity_store.dart';

void main() {
  test('store add and update', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ActivityStore();
    await store.load();
    const item = ActivityItem(
      userOpHash: '0xabc',
      to: '0x1',
      display: '1 ETH',
      ts: 1,
      status: ActivityStatus.sent,
      chainId: 1,
      opKind: 'eth',
    );
    await store.add(item);
    expect(store.items.length, 1);
    await store.setStatus('0xabc', ActivityStatus.confirmed, txHash: '0xdef');
    expect(store.items.first.status, ActivityStatus.confirmed);
    expect(store.items.first.txHash, '0xdef');
  });
}
