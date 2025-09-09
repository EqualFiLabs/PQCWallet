import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppSettings {
  final bool biometricOnTestnets;
  const AppSettings({this.biometricOnTestnets = false});

  AppSettings copyWith({bool? biometricOnTestnets}) => AppSettings(
      biometricOnTestnets: biometricOnTestnets ?? this.biometricOnTestnets);

  Map<String, dynamic> toJson() => {
        'biometricOnTestnets': biometricOnTestnets,
      };

  static AppSettings fromJson(Map<String, dynamic> json) => AppSettings(
        biometricOnTestnets: json['biometricOnTestnets'] == true,
      );

  bool isTestnet(int chainId) =>
      const {84532, 11155111, 5, 80001}.contains(chainId);

  bool requireBiometricForChain(int chainId) =>
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
