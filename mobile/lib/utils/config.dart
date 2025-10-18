int? parseChainId(dynamic raw) {
  if (raw == null) {
    return null;
  }
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
      return int.tryParse(trimmed.substring(2), radix: 16);
    }
    return int.tryParse(trimmed);
  }
  return null;
}

int requireChainId(Map<String, dynamic> cfg) {
  final parsed = parseChainId(cfg['chainId'] ?? cfg['chain']);
  if (parsed == null) {
    throw const FormatException('Configuration missing a valid chainId');
  }
  cfg['chainId'] = parsed;
  return parsed;
}
