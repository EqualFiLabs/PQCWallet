import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WcSessionStore {
  const WcSessionStore({
    FlutterSecureStorage? storage,
    String storageKey = _defaultStorageKey,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _storageKey = storageKey;

  static const String _defaultStorageKey = 'walletconnect.sessions';

  final FlutterSecureStorage _storage;
  final String _storageKey;

  Future<Map<String, Map<String, Object?>>> loadSessions() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) {
      return <String, Map<String, Object?>>{};
    }

    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      await _storage.delete(key: _storageKey);
      return <String, Map<String, Object?>>{};
    }

    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final result = <String, Map<String, Object?>>{};
    var mutated = false;

    for (final entry in decoded.entries) {
      final dynamic value = entry.value;
      if (value is Map<String, dynamic>) {
        final expiry = value['expiry'];
        if (expiry is num && expiry <= nowSeconds) {
          mutated = true;
          continue;
        }
        result[entry.key] = value.cast<String, Object?>();
      } else {
        mutated = true;
      }
    }

    if (mutated) {
      await _writeAll(result);
    }

    return result;
  }

  Future<void> persistSession(String topic, Map<String, Object?> data) async {
    final sessions = await loadSessions();
    sessions[topic] = _deepCopy(data);
    await _writeAll(sessions);
  }

  Future<void> clearSession(String topic) async {
    final sessions = await loadSessions();
    if (!sessions.containsKey(topic)) {
      return;
    }
    sessions.remove(topic);
    await _writeAll(sessions);
  }

  Map<String, Object?> _deepCopy(Map<String, Object?> source) {
    final copy = <String, Object?>{};
    for (final entry in source.entries) {
      final value = entry.value;
      if (value is Map<String, Object?>) {
        copy[entry.key] = _deepCopy(value);
      } else if (value is Map) {
        copy[entry.key] =
            _deepCopy(value.cast<String, Object?>());
      } else if (value is List) {
        copy[entry.key] = List<Object?>.from(value);
      } else {
        copy[entry.key] = value;
      }
    }
    return copy;
  }

  Future<void> _writeAll(Map<String, Map<String, Object?>> sessions) async {
    if (sessions.isEmpty) {
      await _storage.delete(key: _storageKey);
      return;
    }

    final encoded = <String, dynamic>{};
    for (final entry in sessions.entries) {
      encoded[entry.key] = _normalise(entry.value);
    }

    await _storage.write(key: _storageKey, value: jsonEncode(encoded));
  }

  Object? _normalise(Object? value) {
    if (value is Map<String, Object?>) {
      return value.map((key, dynamic v) => MapEntry(key, _normalise(v)));
    }
    if (value is Map) {
      return value.map((dynamic key, dynamic v) =>
          MapEntry(key.toString(), _normalise(v)));
    }
    if (value is Iterable) {
      return value.map<Object?>(_normalise).toList();
    }
    return value;
  }
}
