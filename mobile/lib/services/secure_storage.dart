import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_value_store.dart';

class SecureStorage implements KeyValueStore {
  SecureStorage({
    FlutterSecureStorage? primary,
    FlutterSecureStorage? legacy,
  })  : _primary = primary ?? _buildPrimary(),
        _legacy = legacy ?? const FlutterSecureStorage();

  static SecureStorage? _instance;

  static SecureStorage get instance => _instance ??= SecureStorage();

  @visibleForTesting
  static void overwriteForTesting(SecureStorage replacement) {
    _instance = replacement;
  }

  final FlutterSecureStorage _primary;
  final FlutterSecureStorage _legacy;

  static FlutterSecureStorage _buildPrimary() {
    return const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
        resetOnError: true,
        sharedPreferencesName: 'pqcwallet_secure',
        preferencesKeyPrefix: 'pqc_',
      ),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
      ),
      mOptions: MacOsOptions(
        accessibility: KeychainAccessibility.first_unlock,
        useDataProtectionKeyChain: true,
      ),
      webOptions: WebOptions(
        dbName: 'pqc_wallet_secure',
        publicKey: 'pqc_wallet_key',
      ),
      wOptions: WindowsOptions(
        useBackwardCompatibility: true,
      ),
    );
  }

  @override
  Future<String?> read(String key) async {
    try {
      final value = await _primary.read(key: key);
      if (value != null) return value;
    } catch (e, st) {
      debugPrint('SecureStorage primary read error for $key: $e\n$st');
    }

    try {
      final legacyValue = await _legacy.read(key: key);
      if (legacyValue != null) {
        // Migrate legacy value into primary store so future reads succeed.
        try {
          await _primary.write(key: key, value: legacyValue);
          await _legacy.delete(key: key);
        } catch (e, st) {
          debugPrint('SecureStorage migration error for $key: $e\n$st');
        }
        return legacyValue;
      }
    } catch (e, st) {
      debugPrint('SecureStorage legacy read error for $key: $e\n$st');
    }
    return null;
  }

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      await delete(key);
      return;
    }

    try {
      await _primary.write(key: key, value: value);
    } catch (e, st) {
      debugPrint('SecureStorage primary write error for $key: $e\n$st');
      rethrow;
    }

    try {
      await _legacy.delete(key: key);
    } catch (e, st) {
      debugPrint('SecureStorage legacy sync error for $key: $e\n$st');
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _primary.delete(key: key);
    } catch (e, st) {
      debugPrint('SecureStorage primary delete error for $key: $e\n$st');
    }
    try {
      await _legacy.delete(key: key);
    } catch (e, st) {
      debugPrint('SecureStorage legacy delete error for $key: $e\n$st');
    }
  }
}
