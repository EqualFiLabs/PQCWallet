import 'dart:convert';
import 'key_value_store.dart';
import 'secure_storage.dart';

class PendingIndexStore {
  final KeyValueStore _store;

  PendingIndexStore({KeyValueStore? store})
      : _store = store ?? SecureStorage.instance;

  String _key(int chainId, String wallet) =>
      'pqcwallet/pendingIndex/\$chainId/\${wallet.toLowerCase()}';

  Future<void> save(
      int chainId, String wallet, Map<String, dynamic> data) async {
    await _store.write(_key(chainId, wallet), jsonEncode(data));
  }

  Future<Map<String, dynamic>?> load(int chainId, String wallet) async {
    final s = await _store.read(_key(chainId, wallet));
    if (s == null) return null;
    return jsonDecode(s) as Map<String, dynamic>;
  }

  Future<void> clear(int chainId, String wallet) async {
    await _store.delete(_key(chainId, wallet));
  }
}
