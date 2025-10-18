import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'key_value_store.dart';
import 'secure_storage.dart';

/// Stores and verifies the wallet unlock PIN using secure storage.
class PinService {
  static const _pinKey = 'pqcwallet/pin-sha256';

  final KeyValueStore _store;

  PinService({KeyValueStore? store}) : _store = store ?? SecureStorage.instance;

  Future<bool> hasPin() async {
    final value = await _store.read(_pinKey);
    return value != null && value.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    await _store.write(_pinKey, _hash(pin));
  }

  Future<void> clearPin() async {
    await _store.delete(_pinKey);
  }

  Future<bool> verify(String pin) async {
    final stored = await _store.read(_pinKey);
    if (stored == null) return false;
    return _constantTimeEquals(stored, _hash(pin));
  }

  String _hash(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
