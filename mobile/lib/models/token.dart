import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;

class ChainTokens {
  final Map<String, dynamic> raw;
  ChainTokens(this.raw);

  String? tokenAddress(String symbol, int chainId) {
    final t = (raw['tokens'] as List).firstWhere(
      (e) => e['symbol'] == symbol,
      orElse: () => null,
    );
    if (t == null) return null;
    return (t['addresses'] as Map)[chainId.toString()] as String?;
  }

  Map<String, dynamic>? token(String symbol) {
    return (raw['tokens'] as List)
        .cast<Map<String, dynamic>?>()
        .firstWhere((e) => e?['symbol'] == symbol, orElse: () => null);
  }

  bool feature(String symbol, String name) {
    final t = token(symbol);
    if (t == null) return false;
    return (t['features']?[name] ?? false) as bool;
  }

  String? permit2Address(int chainId) {
    return (raw['permit2'] as Map)[chainId.toString()] as String?;
  }

  int chainIdBase() => (raw['chainIds']['base'] as num).toInt();
  int chainIdBaseSepolia() => (raw['chainIds']['baseSepolia'] as num).toInt();

  static Future<ChainTokens> load() async {
    try {
      final s = await rootBundle.loadString('assets/tokens.base.json');
      return ChainTokens(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      final s = await File('assets/tokens.base.json').readAsString();
      return ChainTokens(jsonDecode(s) as Map<String, dynamic>);
    }
  }
}
