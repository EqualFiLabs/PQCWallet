import 'package:pqc_wallet/services/key_value_store.dart';

class MemoryStore implements KeyValueStore {
  MemoryStore([Map<String, String>? initial])
      : _store = Map<String, String>.from(initial ?? const {});

  final Map<String, String> _store;

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }
}
