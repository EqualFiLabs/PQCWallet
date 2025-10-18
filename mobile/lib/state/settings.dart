import 'dart:convert';
import '../services/key_value_store.dart';
import '../services/secure_storage.dart';

class AppSettings {
  static const Object _noChange = Object();

  final bool useBiometric;
  final bool biometricOnTestnets;
  final String? customRpcUrl;
  const AppSettings({
    this.useBiometric = false,
    this.biometricOnTestnets = false,
    this.customRpcUrl,
  });

  AppSettings copyWith({
    bool? useBiometric,
    bool? biometricOnTestnets,
    Object? customRpcUrl = _noChange,
  }) =>
      AppSettings(
        useBiometric: useBiometric ?? this.useBiometric,
        biometricOnTestnets: biometricOnTestnets ?? this.biometricOnTestnets,
        customRpcUrl: identical(customRpcUrl, _noChange)
            ? this.customRpcUrl
            : customRpcUrl as String?,
      );

  Map<String, dynamic> toJson() => {
        'useBiometric': useBiometric,
        'biometricOnTestnets': biometricOnTestnets,
        'customRpcUrl': customRpcUrl,
      };

  static AppSettings fromJson(Map<String, dynamic> json) => AppSettings(
        useBiometric: json['useBiometric'] == true,
        biometricOnTestnets: json['biometricOnTestnets'] == true,
        customRpcUrl: _parseOptionalString(json['customRpcUrl']),
      );

  bool isTestnet(int chainId) =>
      const {84532, 11155111, 5, 80001}.contains(chainId);

  bool requireAuthForChain(int chainId) =>
      chainId == 8453 || (isTestnet(chainId) && biometricOnTestnets);

  static String? _parseOptionalString(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }
}

class SettingsStore {
  SettingsStore({KeyValueStore? store})
      : _store = store ?? SecureStorage.instance;

  final KeyValueStore _store;
  final String _key = 'pqcwallet/settings';

  Future<AppSettings> load() async {
    final s = await _store.read(_key);
    if (s == null) return const AppSettings();
    return AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  Future<void> save(AppSettings s) async {
    await _store.write(_key, jsonEncode(s.toJson()));
  }
}
