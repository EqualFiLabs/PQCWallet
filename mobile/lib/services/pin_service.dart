import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores and verifies the wallet unlock PIN using secure storage.
class PinService {
  static const _pinKey = 'pqcwallet/pin-sha256';

  final FlutterSecureStorage _storage;

  const PinService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<bool> hasPin() async {
    final value = await _storage.read(key: _pinKey);
    return value != null && value.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    await _storage.write(key: _pinKey, value: _hash(pin));
  }

  Future<void> clearPin() async {
    await _storage.delete(key: _pinKey);
  }

  Future<bool> verify(String pin) async {
    final stored = await _storage.read(key: _pinKey);
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
