import 'dart:convert';

import '../utils/config.dart';

/// Normalizes/massages the runtime config loaded from assets so the rest of
/// the app can rely on stable keys.
///
/// Accepted aliases:
/// - entryPointAddr -> entryPoint
///
/// Optional fields are defaulted to sensible null/false values rather than
/// missing/undefined to keep UI simple.
Map<String, dynamic> normalizeAppConfig(Map<String, dynamic> raw) {
  // Copy to avoid mutating the caller's map.
  final cfg = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;

  // Aliases
  if (cfg['entryPoint'] == null && cfg['entryPointAddr'] is String) {
    cfg['entryPoint'] = cfg['entryPointAddr'];
  }

  // Coerce chainId into an int regardless of how it was provided.
  final parsedChainId = parseChainId(cfg['chainId'] ?? cfg['chain']);
  if (parsedChainId != null) {
    cfg['chainId'] = parsedChainId;
  }

  // Optional keys — make them present so UI can just render.
  cfg.putIfAbsent('aggregator', () => null);
  cfg.putIfAbsent('proverRegistry', () => null);
  cfg.putIfAbsent('forceOnChainVerify', () => null);
  cfg.putIfAbsent('walletAddress', () => null);
  cfg.putIfAbsent('rpcUrl', () => null);
  cfg.putIfAbsent('bundlerUrl', () => null);

  return cfg;
}
