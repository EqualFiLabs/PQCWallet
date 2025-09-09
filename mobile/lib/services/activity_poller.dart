import 'dart:async';
import '../models/activity.dart';
import 'activity_store.dart';
import 'rpc.dart';
import 'bundler_client.dart';

class ActivityPoller {
  final ActivityStore store;
  final RpcClient rpc;
  final BundlerClient bundler;
  Timer? _timer;

  ActivityPoller({
    required this.store,
    required this.rpc,
    required this.bundler,
  });

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
    _tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    final pending = store.items
        .where((e) => e.status == ActivityStatus.pending || e.status == ActivityStatus.sent)
        .toList();

    for (final item in pending) {
      try {
        String? txHash = item.txHash;
        if (txHash == null) {
          final r = await bundler.getUserOperationReceipt(item.userOpHash);
          if (r != null) {
            final m = Map<String, dynamic>.from(r);
            txHash = m['receipt']?['transactionHash'] as String?;
            if (txHash != null) {
              await store.setStatus(item.userOpHash, ActivityStatus.sent, txHash: txHash);
            }
          }
        }

        if (txHash != null) {
          final receipt = await rpc.call('eth_getTransactionReceipt', [txHash]);
          if (receipt != null) {
            final rm = Map<String, dynamic>.from(receipt);
            final statusHex = rm['status'] as String?;
            if (statusHex != null) {
              final ok = statusHex == '0x1';
              await store.setStatus(
                  item.userOpHash, ok ? ActivityStatus.confirmed : ActivityStatus.failed);
            }
          }
        }
      } catch (_) {
        // ignore network errors
      }
    }
  }
}
