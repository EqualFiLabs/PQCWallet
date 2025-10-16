import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppSettings {
  final bool useBiometric;
  final bool biometricOnTestnets;
  const AppSettings({
    this.useBiometric = false,
    this.biometricOnTestnets = false,
  });

  AppSettings copyWith({bool? useBiometric, bool? biometricOnTestnets}) =>
      AppSettings(
        useBiometric: useBiometric ?? this.useBiometric,
        biometricOnTestnets: biometricOnTestnets ?? this.biometricOnTestnets,
      );

  Map<String, dynamic> toJson() => {
        'useBiometric': useBiometric,
        'biometricOnTestnets': biometricOnTestnets,
      };

  static AppSettings fromJson(Map<String, dynamic> json) => AppSettings(
        useBiometric: json['useBiometric'] == true,
        biometricOnTestnets: json['biometricOnTestnets'] == true,
      );

  bool isTestnet(int chainId) =>
      const {84532, 11155111, 5, 80001}.contains(chainId);

  bool requireAuthForChain(int chainId) =>
      chainId == 8453 || (isTestnet(chainId) && biometricOnTestnets);
}

class SettingsStore {
  final FlutterSecureStorage _ss = const FlutterSecureStorage();
  final String _key = 'pqcwallet/settings';

  Future<AppSettings> load() async {
    final s = await _ss.read(key: _key);
    if (s == null) return const AppSettings();
    return AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  Future<void> save(AppSettings s) async {
    await _ss.write(key: _key, value: jsonEncode(s.toJson()));
  }
}
