import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PendingIndexStore {
  final FlutterSecureStorage _ss = const FlutterSecureStorage();

  String _key(int chainId, String wallet) =>
      'pqcwallet/pendingIndex/\$chainId/\${wallet.toLowerCase()}';

  Future<void> save(
      int chainId, String wallet, Map<String, dynamic> data) async {
    await _ss.write(key: _key(chainId, wallet), value: jsonEncode(data));
  }

  Future<Map<String, dynamic>?> load(int chainId, String wallet) async {
    final s = await _ss.read(key: _key(chainId, wallet));
    if (s == null) return null;
    return jsonDecode(s) as Map<String, dynamic>;
  }

  Future<void> clear(int chainId, String wallet) async {
    await _ss.delete(key: _key(chainId, wallet));
  }
}
